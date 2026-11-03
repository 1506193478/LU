import 'dart:io';

import 'package:dio/dio.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/request/core/dio_factory.dart';
import 'package:XL/request/core/network_config.dart';
import 'package:XL/services/logging/logger.dart';

/// Emby 接口返回的错误，已经翻成人话。
class EmbyApiException implements Exception {
  const EmbyApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'EmbyApiException($statusCode): $message';
}

/// 登录成功后服务端给的东西。
class EmbyAuthResult {
  const EmbyAuthResult({
    required this.accessToken,
    required this.userId,
    required this.userName,
    required this.serverName,
  });

  final String accessToken;
  final String userId;
  final String userName;
  final String serverName;
}

/// 起播前探针的结果。
///
/// 存在的意义：以前地址拼错时，播放器只是"打不开"，用户看到黑屏完全不知道
/// 发生了什么。现在把服务端那句 `Value cannot be null. (Parameter 'mediaSource')`
/// 原样带出来，至少能一眼看出是参数问题还是服务器问题。
class EmbyStreamProbe {
  const EmbyStreamProbe.ok()
      : isOk = true,
        statusCode = 200,
        message = '';

  const EmbyStreamProbe.failed({required this.statusCode, required this.message})
      : isOk = false;

  final bool isOk;
  final int? statusCode;
  final String message;

  /// 给用户看的错误说明。
  String get userMessage {
    final status = statusCode;
    if (message.contains('ffmpeg')) {
      return '服务器转码失败（ffmpeg 起不来），请在服务端重启 Emby，或改用直连播放';
    }
    if (status == 401 || status == 403) {
      return 'Emby 拒绝访问，请在服务器设置里重新登录';
    }
    if (status == 404) {
      return '服务器上找不到这个文件，可能已被删除或移动';
    }
    if (status == 400) {
      return message.isEmpty ? '播放地址被服务器拒绝' : '播放地址被服务器拒绝：$message';
    }
    if (status != null) {
      return message.isEmpty ? '服务器返回 HTTP $status' : '服务器返回 HTTP $status：$message';
    }
    return message.isEmpty ? '连不上服务器' : message;
  }
}

/// Emby / Jellyfin 的 HTTP 客户端。
///
/// 两者 API 基本同源，差异只在认证头：Emby 认 `X-Emby-Authorization`，
/// Jellyfin 认 `Authorization`。这里两个头都发同一份 MediaBrowser 串，
/// 谁认哪个都能过，不需要用户先选"我这是 Emby 还是 Jellyfin"。
///
/// 所有请求都用完整 URL 而不是 dio 的 baseUrl：Emby 允许装在子路径下
/// （`http://host/emby`），baseUrl 拼相对路径时容易被 `Uri.resolve` 的
/// 语义吃掉子路径，手拼反而更稳。
class EmbyClient {
  EmbyClient({
    required String serverUrl,
    List<String> backupUrls = const <String>[],
    this.accessToken,
    bool allowBadCertificate = false,
    String? deviceId,
  })  : _mainUrl = serverUrl,
        _backups = List<String>.unmodifiable(
          backupUrls.where((url) => url.trim().isNotEmpty),
        ),
        _activeUrl = serverUrl,
        _deviceId = deviceId ?? 'lu-emby-client' {
    final base = NetworkConfig.fromSettings(
      // 8 秒太紧了。实测对一台海外机器，冷启动后第一个 TLS 握手（DNS + TCP +
      // 完整握手）能跑到 10 秒以上，8 秒会把「只是慢」直接判成「连不上」。
      connectTimeout: const Duration(seconds: 20),
      // 取剧集列表时服务端可能要先扫库，给宽一点。
      receiveTimeout: const Duration(seconds: 30),
    );
    _dio = DioFactory.createForConfig(
      base.copyWith(
        // 代理开着时 NetworkConfig 自己会放行证书，这里不要覆盖掉。
        allowBadCertificates: allowBadCertificate || base.allowBadCertificates,
        // Emby 请求会带 Token，别把完整 URL 和头打进日志。
        enableLog: false,
      ),
    );
  }

  /// 主线路地址（用户在表单里填的那个）。
  final String _mainUrl;

  /// 备用线路，按用户在「备用线路」页里的排列顺序。
  final List<String> _backups;

  /// 当前正在用的线路。
  ///
  /// 一开始是主线路；某次请求发现它连不上，就会换成备用线路并**留在这里**，
  /// 后面的请求直接从能用的那条开始，不用每次都先等主线路超时。
  String _activeUrl;

  final String? accessToken;
  final String _deviceId;
  late final Dio _dio;

  /// 当前生效的基址。图片、直链、HLS 地址都按它拼，所以切线路之后
  /// 海报和播放地址会一起跟着换。
  String get serverUrl => _activeUrl;

  /// 主线路基址。
  String get mainUrl => _mainUrl;

  /// 现在是不是跑在备用线路上（界面上可以据此提示用户）。
  bool get usingBackupLine => _activeUrl != _mainUrl;

  /// 要尝试的线路顺序：当前生效的排第一，然后主线路，最后按配置顺序的备用。
  List<String> get _lines {
    final list = <String>[];
    void add(String url) {
      if (url.isNotEmpty && !list.contains(url)) list.add(url);
    }

    add(_activeUrl);
    add(_mainUrl);
    for (final url in _backups) {
      add(url);
    }
    return list;
  }

  static const String _clientVersion = '1.0.0';

  void close() => _dio.close(force: true);

  /// 发请求，连不上就自动换下一条线路。
  ///
  /// 只对「连不上」换线路：4xx / 5xx 说明线路是通的、服务端在回话，换一条
  /// 也一样，直接抛给上层。全部线路都连不上时抛最后一次的错误。
  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function(String baseUrl) build,
  ) async {
    DioException? last;
    for (final baseUrl in _lines) {
      try {
        final response = await build(baseUrl);
        if (baseUrl != _activeUrl) {
          _activeUrl = baseUrl;
          KazumiLogger().i('Emby: 线路切换 → $baseUrl');
        }
        return response;
      } on DioException catch (e) {
        if (!_isLineDown(e)) rethrow;
        last = e;
        KazumiLogger().w('Emby: 线路 $baseUrl 连不上，试下一条', error: e);
      }
    }
    throw last!;
  }

  /// 这个错误算不算「线路本身不通」。
  ///
  /// 超时只认 connectTimeout：receiveTimeout 是服务器接了连接但回得慢，
  /// 换个地址通常也没用，反而把用户的等待时间翻倍。
  bool _isLineDown(DioException e) => switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.unknown =>
          true,
        _ => false,
      };

  /// MediaBrowser 认证串，Emby / Jellyfin 通用格式。
  String _authorizationValue({String? token}) {
    final parts = <String>[
      'MediaBrowser Client="LU"',
      'Device="${_deviceLabel()}"',
      'DeviceId="$_deviceId"',
      'Version="$_clientVersion"',
      if (token != null && token.isNotEmpty) 'Token="$token"',
    ];
    return parts.join(', ');
  }

  String _deviceLabel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  Map<String, String> get _authHeaders {
    final value = _authorizationValue(token: accessToken);
    return {
      'X-Emby-Authorization': value,
      'Authorization': value,
      'Accept': 'application/json',
    };
  }

  /// 把 Token 同时塞进查询串。反向代理经常把自定义头吃掉，`api_key`
  /// 是 Emby 和 Jellyfin 都认的兜底方式。
  Map<String, dynamic> _query(Map<String, dynamic> extra) => {
        ...extra,
        if (accessToken != null && accessToken!.isNotEmpty)
          'api_key': accessToken,
      };

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    try {
      final response = await _send(
        (baseUrl) => _dio.get<dynamic>(
          '$baseUrl$path',
          queryParameters: _query(query),
          options: Options(headers: _authHeaders),
        ),
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  /// 有些接口（Latest、Seasons 之外还有几个）直接返回数组，不是 `{Items:[]}`。
  /// 用 [_getJsonList] 把它们也塞进统一的 map 形状，省得每个调用点各判断一次。
  Future<Map<String, dynamic>> _getJsonList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    try {
      final response = await _send(
        (baseUrl) => _dio.get<dynamic>(
          '$baseUrl$path',
          queryParameters: _query(query),
          options: Options(headers: _authHeaders),
        ),
      );
      final data = response.data;
      if (data is List) return {'Items': data};
      return _asMap(data);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  /// POST / DELETE 用。播放上报这类接口失败不该打断播放，
  /// 所以带 [ignoreErrors] 的调用会把异常吞掉只留日志。
  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic> query = const {},
    Object? data,
    String method = 'POST',
    bool ignoreErrors = false,
  }) async {
    try {
      final response = await _send(
        (baseUrl) => _dio.request<dynamic>(
          '$baseUrl$path',
          data: data,
          queryParameters: _query(query),
          options: Options(method: method, headers: _authHeaders),
        ),
      );
      return _asMap(response.data);
    } on DioException catch (e) {
      if (ignoreErrors) {
        KazumiLogger().d('Emby: $method $path failed (ignored)', error: e);
        return const {};
      }
      throw _translate(e);
    }
  }

  /// 登录。Emby 的登录接口就是按用户名密码换 Token。
  Future<EmbyAuthResult> authenticate({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _send(
        (baseUrl) => _dio.post<dynamic>(
          '$baseUrl/Users/AuthenticateByName',
          data: {'Username': username, 'Pw': password},
          options: Options(headers: _authHeaders),
        ),
      );
      final body = _asMap(response.data);
      final token = body['AccessToken']?.toString() ?? '';
      if (token.isEmpty) {
        throw const EmbyApiException('服务器没有返回 Token，请确认这是 Emby 或 Jellyfin 服务');
      }
      final user = _asMap(body['User']);
      return EmbyAuthResult(
        accessToken: token,
        userId: user['Id']?.toString() ?? '',
        userName: user['Name']?.toString() ?? username,
        serverName: await _fetchServerName(),
      );
    } on DioException catch (e) {
      // 登录接口的 401 就是密码错了，别报"服务器异常"。
      if (e.response?.statusCode == 401) {
        throw const EmbyApiException('账号或密码不正确', statusCode: 401);
      }
      throw _translate(e);
    }
  }

  /// 服务器名，只用于界面展示，取不到就用 host 兜底。
  Future<String> _fetchServerName() async {
    try {
      final body = await _getJson('/System/Info/Public');
      final name = body['ServerName']?.toString() ?? '';
      if (name.isNotEmpty) return name;
    } catch (e) {
      KazumiLogger().d('Emby: failed to read server name', error: e);
    }
    return Uri.tryParse(serverUrl)?.authority ?? serverUrl;
  }

  /// 媒体库列表。
  Future<List<EmbyLibrary>> fetchLibraries(String userId) async {
    final body = await _getJson('/Users/$userId/Views');
    final items = body['Items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) EmbyLibrary.fromJson(Map<String, dynamic>.from(item)),
    ].where((library) => library.id.isNotEmpty).toList();
  }

  /// 某个媒体库下的内容。
  ///
  /// [includeItemTypes] 传 `Series,Movie` 这类；不传就让服务端按库类型返回，
  /// 但那样会把文件夹也带出来，所以调用方最好显式指定。
  Future<List<EmbyItem>> fetchItems({
    required String userId,
    required String parentId,
    String includeItemTypes = 'Series,Movie',
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items',
      query: {
        'ParentId': parentId,
        'IncludeItemTypes': includeItemTypes,
        'Recursive': 'true',
        'Fields': 'ProductionYear,CommunityRating,Overview,ImageTags,RunTimeTicks',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        // 库大的时候不限量会一次拉几千条，先给个上限，需要再分页。
        'Limit': '500',
      },
    );
    return _itemsOf(body);
  }

  /// 收藏列表。
  ///
  /// `Filters=IsFavorite` 是服务端侧的过滤，只回用户真正收藏过的条目；
  /// 排序用「最近收藏」，刚收藏的那部排在最前面才是收藏夹该有的样子。
  Future<List<EmbyItem>> fetchFavorites({
    required String userId,
    int limit = 300,
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items',
      query: {
        'UserId': userId,
        'Filters': 'IsFavorite',
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series,BoxSet,Video',
        'Fields': _itemFields,
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Limit': '$limit',
        'EnableImageTypes': 'Primary',
      },
    );
    return _itemsOf(body);
  }

  /// 某部剧的所有集。电影在调用方直接当成"唯一一集"处理，不查这个接口。
  ///
  /// [seasonId] 传了就只拉该季；不传拉全部季的集（服务端按季号排序）。
  Future<List<EmbyItem>> fetchEpisodes({
    required String userId,
    required String seriesId,
    String? seasonId,
  }) async {
    final body = await _getJson(
      '/Shows/$seriesId/Episodes',
      query: {
        'UserId': userId,
        // 这里必须用统一字段表。原来只取 4 个字段，导致：
        //   * 没有 UserData → 集卡上看不到「看到哪了」；
        //   * 没有 IndexNumber → 集号只能靠下标猜，乱序时对不上；
        //   * 没有 CommunityRating → 截图里那张卡片右下的评分永远空着；
        //   * 没有 Genres / OfficialRating → 详情页 meta 行缺内容。
        'Fields': _itemFields,
        if (seasonId != null && seasonId.isNotEmpty) 'SeasonId': seasonId,
      },
    );
    return _itemsOf(body);
  }

  /// 单个条目的完整元数据。
  ///
  /// 列表/搜索接口返回的条目经常是「瘦身版」：`Overview`、`Genres`、
  /// `OfficialRating` 都可能没有。详情页直接拿它渲染，就会出现「没有简介」。
  /// 进详情页时再问一次单条接口，把这些字段补齐。
  Future<EmbyItem?> fetchItemMeta({
    required String userId,
    required String itemId,
  }) async {
    if (itemId.isEmpty) return null;
    final body = await _getJson(
      '/Users/$userId/Items/$itemId',
      query: {
        'Fields': '$_itemFields,Taglines,PrimaryImageAspectRatio,'
            'SeriesPrimaryImageTag,ParentPrimaryImageTag,People',
      },
    );
    if (body['Id'] == null) return null;
    return EmbyItem.fromJson(body);
  }

  List<EmbyItem> _itemsOf(Map<String, dynamic> body) {
    final items = body['Items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map) EmbyItem.fromJson(Map<String, dynamic>.from(item)),
    ].where((item) => item.id.isNotEmpty).toList();
  }

  /// 封面图地址。`tag` 带上才能命中服务端缓存，不带每次都会重转。
  String imageUrl(String itemId, {int maxHeight = 400, String? tag}) =>
      embyImageUrl(
        serverUrl: serverUrl,
        itemId: itemId,
        accessToken: accessToken,
        maxHeight: maxHeight,
        tag: tag,
      );

  /// 原盘直连地址：不转码，mpv 自己解。绝大多数片源都该走这条。
  ///
  /// [mediaSourceId] 必须来自 `PlaybackInfo`，**不能传条目 id**——传错就是 400。
  /// 传 null 时地址里不带该参数，服务端会自己挑唯一媒体源。
  String directStreamUrl(String itemId, {String? mediaSourceId}) =>
      embyDirectStreamUrl(
        serverUrl: serverUrl,
        itemId: itemId,
        accessToken: accessToken,
        mediaSourceId: mediaSourceId,
      );

  /// 转码兜底：让服务端出 HLS。遇到 mpv 解不了的编码时才用。
  String hlsStreamUrl(
    String itemId, {
    String? mediaSourceId,
    int maxBitrateBps = 0,
  }) =>
      embyHlsStreamUrl(
        serverUrl: serverUrl,
        itemId: itemId,
        accessToken: accessToken,
        mediaSourceId: mediaSourceId,
        maxBitrateBps: maxBitrateBps,
      );

  // ------------------------------------------------------------ 播放信息

  /// 问服务端「这一条到底怎么播」。
  ///
  /// 这是唯一能拿到**真实媒体源 id** 的接口。之前手拼地址时把条目 id 当媒体源
  /// id 用，Emby 4.9+ 直接 400，整块播放功能不可用。所有起播都必须先走这里。
  Future<EmbyMediaSource?> fetchPlaybackInfo({
    required String itemId,
    required String userId,
  }) async {
    try {
      final body = await _postJson(
        '/Items/$itemId/PlaybackInfo',
        query: {'UserId': userId},
        data: {'UserId': userId, 'AutoOpenLiveStream': false},
      );
      final sources = body['MediaSources'];
      if (sources is! List || sources.isEmpty) return null;
      final first = sources.first;
      if (first is! Map) return null;
      final source = EmbyMediaSource.fromJson(Map<String, dynamic>.from(first));
      return source.id.isEmpty ? null : source;
    } catch (e) {
      // 拿不到就退回"不带 MediaSourceId"的地址，服务端会自己挑媒体源。
      KazumiLogger().w('Emby: playback info failed, fallback to plain url', error: e);
      return null;
    }
  }

  /// 条目详情里的媒体源。
  ///
  /// 少数服务端（或前面挡了一层反向代理缓存）的 `PlaybackInfo` 只回
  /// `MediaSources` 的壳、不带 `MediaStreams`，字幕面板就会空着。
  /// 这里再问一次 `/Items/{id}?Fields=MediaSources`，两条路取并集。
  Future<EmbyMediaSource?> fetchItemMediaSource({
    required String itemId,
    required String userId,
  }) async {
    try {
      final body = await _getJson(
        '/Items/$itemId',
        query: {
          'UserId': userId,
          'Fields': 'MediaSources,MediaStreams,Chapters',
        },
      );
      final sources = body['MediaSources'];
      if (sources is! List || sources.isEmpty) return null;
      final first = sources.first;
      if (first is! Map) return null;
      final source = EmbyMediaSource.fromJson(Map<String, dynamic>.from(first));
      return source.mediaStreams.isEmpty && source.id.isEmpty ? null : source;
    } catch (e) {
      KazumiLogger().w('Emby: item media source failed', error: e);
      return null;
    }
  }

  /// 问服务端有哪些外挂字幕可下（走服务器上配好的 OpenSubtitles 插件）。
  ///
  /// Emby 的接口是 `/Items/{id}/RemoteSearch/Subtitles/{语言三字码}`。
  /// 服务器没装字幕插件时这里会 400/404，调用方按「搜不到」处理即可。
  Future<List<EmbyRemoteSubtitle>> searchRemoteSubtitles({
    required String itemId,
    required String language,
  }) async {
    final body = await _getJsonList(
      '/Items/$itemId/RemoteSearch/Subtitles/$language',
    );
    final items = body['Items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map)
          EmbyRemoteSubtitle.fromJson(Map<String, dynamic>.from(item)),
    ].where((s) => s.id.isNotEmpty).toList();
  }

  /// 下载选中的外挂字幕到服务器，之后重新问 PlaybackInfo 就能看到新轨道。
  Future<void> downloadRemoteSubtitle({
    required String itemId,
    required String subtitleId,
  }) async {
    await _postJson('/Items/$itemId/RemoteSearch/Subtitles/$subtitleId');
  }

  /// 起播前探一下地址，把 4xx/5xx 拦在播放器外面。
  ///
  /// 不探的话用户看到的是黑屏 + 播放器里一行 "failed to open"，根本不知道
  /// 是 Token 过期、媒体源 id 不对，还是服务端转码挂了。这里只取 1KB，
  /// 成本极低。
  Future<EmbyStreamProbe> probeStream(String url) async {
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {..._authHeaders, 'Range': 'bytes=0-1023'},
          responseType: ResponseType.stream,
          // 探针不该等太久，卡住就说明这条地址不通。
          receiveTimeout: const Duration(seconds: 12),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      final contentType = response.headers.value('content-type') ?? '';
      final isSuccess = status == 200 || status == 206;
      // 反向代理没配好时，播放地址常被回一张登录页（200 + text/html）。
      // 这种「成功」喂给播放器还是黑屏，必须当失败处理。
      final looksLikeHtml = contentType.contains('text/html');
      if (isSuccess && !looksLikeHtml) {
        return const EmbyStreamProbe.ok();
      }
      if (isSuccess && looksLikeHtml) {
        return const EmbyStreamProbe.failed(
          statusCode: 200,
          message: '播放地址返回的是网页而不是视频，请检查反向代理是否拦截了 /Videos 路径',
        );
      }
      final message = await _readErrorBody(response.data);
      return EmbyStreamProbe.failed(
        statusCode: status,
        message: message.isEmpty ? 'HTTP $status' : message,
      );
    } on DioException catch (e) {
      return EmbyStreamProbe.failed(
        statusCode: e.response?.statusCode,
        message: _translate(e).message,
      );
    }
  }

  Future<String> _readErrorBody(ResponseBody? body) async {
    if (body == null) return '';
    try {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 512) break;
      }
      return String.fromCharCodes(bytes).replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ 首页数据

  /// 继续观看。服务端按 `UserData.PlaybackPositionTicks` 挑出来的。
  Future<List<EmbyItem>> fetchResume({
    required String userId,
    int limit = 12,
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items/Resume',
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'MediaTypes': 'Video',
        'Recursive': 'true',
        'Fields': _itemFields,
        'ImageTypeLimit': '1',
        'EnableImageTypes': 'Primary,Backdrop',
      },
    );
    return _itemsOf(body);
  }

  /// 最新入库。
  Future<List<EmbyItem>> fetchLatest({
    required String userId,
    String? parentId,
    int limit = 16,
  }) async {
    final body = await _getJsonList(
      '/Users/$userId/Items/Latest',
      query: {
        'UserId': userId,
        'Limit': '$limit',
        if (parentId != null && parentId.isNotEmpty) 'ParentId': parentId,
        'Fields': _itemFields,
        'EnableImageTypes': 'Primary,Backdrop',
      },
    );
    return _itemsOf(body);
  }

  /// 某个剧的所有季。
  Future<List<EmbyItem>> fetchSeasons({
    required String seriesId,
    required String userId,
  }) async {
    final body = await _getJson(
      '/Shows/$seriesId/Seasons',
      query: {
        'UserId': userId,
        'Fields': _itemFields,
        'EnableImageTypes': 'Primary',
      },
    );
    return _itemsOf(body);
  }

  /// 相关推荐。
  Future<List<EmbyItem>> fetchSimilar({
    required String itemId,
    required String userId,
    int limit = 12,
  }) async {
    final body = await _getJson(
      '/Items/$itemId/Similar',
      query: {
        'UserId': userId,
        'Limit': '$limit',
        'Fields': _itemFields,
        'EnableImageTypes': 'Primary',
      },
    );
    return _itemsOf(body);
  }

  /// 服务器内容统计（电影 / 节目 / 集数），媒体库页统计条用。
  ///
  /// `/Items/Counts` 是 Emby/Jellyfin 的标准接口；个别反代可能关掉它，
  /// 调用方要 catch 住，统计条缺失不该影响整页。
  Future<EmbyItemCounts> fetchItemCounts({required String userId}) async {
    final body = await _getJson(
      '/Items/Counts',
      query: {'UserId': userId},
    );
    return EmbyItemCounts.fromJson(body);
  }

  /// 某个媒体库的条目总数。`Limit=0` 只拿 TotalRecordCount，开销极小。
  Future<int> fetchLibraryCount({
    required String userId,
    required String parentId,
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items',
      query: {
        'ParentId': parentId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Series,Movie,Episode',
        'Limit': '0',
        'EnableTotalRecordCount': 'true',
      },
    );
    return (body['TotalRecordCount'] as num?)?.toInt() ?? 0;
  }

  /// 服务器版本号（/System/Info 的 Version 字段），「我的」页签展示用。
  Future<String> fetchServerVersion() async {
    final body = await _getJson('/System/Info');
    return body['Version']?.toString() ?? '';
  }

  /// 跨库搜索。
  /// 搜索。
  ///
  /// [includeItemTypes] 默认只给「剧集 / 电影 / 合集」——资源库的搜索页要求
  /// **只出剧，不出集**（搜「仙逆」不该把 194 个单集全列出来）。要看单集就显式
  /// 传 `Episode`。
  Future<List<EmbyItem>> search({
    required String userId,
    required String keyword,
    int limit = 60,
    String includeItemTypes = 'Movie,Series,BoxSet',
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items',
      query: {
        'UserId': userId,
        'SearchTerm': keyword,
        'Recursive': 'true',
        'IncludeItemTypes': includeItemTypes,
        'Fields': _itemFields,
        'Limit': '$limit',
        'EnableImageTypes': 'Primary',
      },
    );
    return _itemsOf(body);
  }

  /// 媒体库内容，带分页。
  Future<List<EmbyItem>> fetchItemsPaged({
    required String userId,
    required String parentId,
    String includeItemTypes = 'Series,Movie',
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    List<String> genres = const [],
    int? year,
    bool? isPlayed,
  }) async {
    final body = await _getJson(
      '/Users/$userId/Items',
      query: {
        'ParentId': parentId,
        'IncludeItemTypes': includeItemTypes,
        'Recursive': 'true',
        'Fields': _itemFields,
        'SortBy': sortBy,
        'SortOrder': sortOrder,
        'StartIndex': '$startIndex',
        'Limit': '$limit',
        if (genres.isNotEmpty) 'Genres': genres.join('|'),
        if (year != null) 'Years': '$year',
        if (isPlayed != null) 'Filters': isPlayed ? 'IsPlayed' : 'IsUnplayed',
        'EnableImageTypes': 'Primary',
      },
    );
    return _itemsOf(body);
  }

  static const String _itemFields =
      'ProductionYear,CommunityRating,Overview,ImageTags,BackdropImageTags,'
      'RunTimeTicks,UserData,Genres,OfficialRating,SeriesName,ChildCount,'
      'RecursiveItemCount,ParentIndexNumber,IndexNumber';

  // ------------------------------------------------------------ 播放上报

  /// 开始播放。服务端靠它把这条记进「正在播放」，也是续播进度的起点。
  Future<void> reportPlaybackStart({
    required String itemId,
    required String mediaSourceId,
    int positionTicks = 0,
  }) async {
    await _postJson(
      '/Sessions/Playing',
      data: {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PositionTicks': positionTicks,
        'CanSeek': true,
        'IsPaused': false,
        'IsMuted': false,
        'PlayMethod': 'DirectStream',
      },
      ignoreErrors: true,
    );
  }

  /// 进度心跳。十秒一次，退出时再来一发 Stopped。
  Future<void> reportPlaybackProgress({
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
    bool isPaused = false,
  }) async {
    await _postJson(
      '/Sessions/Playing/Progress',
      data: {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PositionTicks': positionTicks,
        'CanSeek': true,
        'IsPaused': isPaused,
        'IsMuted': false,
        'PlayMethod': 'DirectStream',
      },
      ignoreErrors: true,
    );
  }

  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required int positionTicks,
  }) async {
    await _postJson(
      '/Sessions/Playing/Stopped',
      data: {
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PositionTicks': positionTicks,
      },
      ignoreErrors: true,
    );
  }

  /// 标记已看 / 未看。
  Future<void> setPlayed(String itemId, bool played, {required String userId}) async {
    await _postJson(
      '/Users/$userId/PlayedItems/$itemId',
      method: played ? 'POST' : 'DELETE',
    );
  }

  /// 收藏 / 取消收藏。
  Future<void> setFavorite(
    String itemId,
    bool favorite, {
    required String userId,
  }) async {
    await _postJson(
      '/Users/$userId/FavoriteItems/$itemId',
      method: favorite ? 'POST' : 'DELETE',
    );
  }

  EmbyApiException _translate(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return EmbyApiException('登录状态已失效，请在服务器设置里重新登录',
          statusCode: status);
    }
    if (status == 404) {
      return EmbyApiException('接口不存在，请确认地址填的是 Emby / Jellyfin 服务器根地址',
          statusCode: status);
    }
    switch (e.type) {
      case DioExceptionType.badCertificate:
        return const EmbyApiException(
            '证书校验失败。局域网自签证书的服务器，请在服务器设置里打开「允许自签证书」');
      case DioExceptionType.connectionTimeout:
        // 「连不上」和「连上了但不回话」是两回事，给用户的下一步动作也不同，
        // 原来三种超时共用一句「连接超时，服务器没响应」，等于什么都没说。
        return const EmbyApiException(
            '连接超时：一直没连上服务器。检查地址、端口，或者换一条线路');
      case DioExceptionType.receiveTimeout:
        return const EmbyApiException('服务器连上了但一直没回数据，可能正在扫库或负载过高');
      case DioExceptionType.sendTimeout:
        return const EmbyApiException('上传请求超时，网络上行太慢');
      case DioExceptionType.connectionError:
        final reason = e.error?.toString() ?? '';
        if (reason.contains('HandshakeException')) {
          return const EmbyApiException(
              'TLS 握手被中断。多半是中间网络在拦，换个网络或打开「允许自签证书」再试');
        }
        return const EmbyApiException('连不上服务器，请检查地址、端口和是否在同一局域网');
      default:
        return EmbyApiException(
          '请求失败${status == null ? '' : '（HTTP $status）'}',
          statusCode: status,
        );
    }
  }
}
