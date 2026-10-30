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
    required this.serverUrl,
    this.accessToken,
    bool allowBadCertificate = false,
    String? deviceId,
  }) : _deviceId = deviceId ?? 'lu-emby-client' {
    final base = NetworkConfig.fromSettings(
      connectTimeout: const Duration(seconds: 8),
      // 取剧集列表时服务端可能要先扫库，给宽一点。
      receiveTimeout: const Duration(seconds: 20),
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

  final String serverUrl;
  final String? accessToken;
  final String _deviceId;
  late final Dio _dio;

  static const String _clientVersion = '1.0.0';

  void close() => _dio.close(force: true);

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
      final response = await _dio.get<dynamic>(
        '$serverUrl$path',
        queryParameters: _query(query),
        options: Options(headers: _authHeaders),
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

  /// 登录。Emby 的登录接口就是按用户名密码换 Token。
  Future<EmbyAuthResult> authenticate({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '$serverUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: _authHeaders),
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

  /// 某部剧的所有集。电影在调用方直接当成"唯一一集"处理，不查这个接口。
  Future<List<EmbyItem>> fetchEpisodes({
    required String userId,
    required String seriesId,
  }) async {
    final body = await _getJson(
      '/Shows/$seriesId/Episodes',
      query: {
        'UserId': userId,
        'Fields': 'Overview,ImageTags,RunTimeTicks,ProductionYear',
      },
    );
    return _itemsOf(body);
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
  String directStreamUrl(String itemId) => embyDirectStreamUrl(
        serverUrl: serverUrl,
        itemId: itemId,
        accessToken: accessToken,
      );

  /// 转码兜底：让服务端出 HLS。遇到 mpv 解不了的编码时才用。
  String hlsStreamUrl(String itemId) => embyHlsStreamUrl(
        serverUrl: serverUrl,
        itemId: itemId,
        accessToken: accessToken,
      );

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
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const EmbyApiException('连接超时，服务器没响应');
      case DioExceptionType.connectionError:
        return const EmbyApiException('连不上服务器，请检查地址、端口和是否在同一局域网');
      default:
        return EmbyApiException(
          '请求失败${status == null ? '' : '（HTTP $status）'}',
          statusCode: status,
        );
    }
  }
}
