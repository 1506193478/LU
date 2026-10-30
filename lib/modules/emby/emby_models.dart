/// Emby / Jellyfin 服务端配置与媒体条目模型。
///
/// 没有用 Hive TypeAdapter：新增 adapter 要占 typeId 并重新生成 .g.dart，
/// 而服务器配置是低频小数据，整份 JSON 塞进一个 String 设置项更省事，
/// 以后加字段只要在 fromJson 里给默认值，不用动存储 schema。
class EmbyServer {
  const EmbyServer({
    required this.id,
    required this.name,
    required this.url,
    required this.userId,
    required this.userName,
    required this.accessToken,
    this.allowBadCertificate = false,
  });

  /// 本地生成的稳定标识，用于去重和"当前选中服务器"。
  final String id;

  /// 显示名，默认取服务器 host。
  final String name;

  /// 规范化后的基址：无尾斜杠，不含 /web/index.html 之类的界面路径。
  final String url;

  final String userId;
  final String userName;
  final String accessToken;

  /// 局域网自签证书的服务器要开这个，否则 dio 直接拒连。
  final bool allowBadCertificate;

  /// 写进 [PlaybackHistoryIdentity.pluginName] 的适配器名。
  ///
  /// 历史按 adapterName 分档（`History.key => scopedKey(adapterName, ...)`），
  /// 所以用 `emby:<host:port>` 就能让 Emby 记录和插件记录互不覆盖。
  String get adapterName {
    final authority = Uri.tryParse(url)?.authority;
    return 'emby:${authority == null || authority.isEmpty ? id : authority}';
  }

  EmbyServer copyWith({
    String? id,
    String? name,
    String? url,
    String? userId,
    String? userName,
    String? accessToken,
    bool? allowBadCertificate,
  }) {
    return EmbyServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      accessToken: accessToken ?? this.accessToken,
      allowBadCertificate: allowBadCertificate ?? this.allowBadCertificate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'userId': userId,
        'userName': userName,
        'accessToken': accessToken,
        'allowBadCertificate': allowBadCertificate,
      };

  factory EmbyServer.fromJson(Map<String, dynamic> json) => EmbyServer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        accessToken: json['accessToken']?.toString() ?? '',
        allowBadCertificate: json['allowBadCertificate'] == true,
      );
}

/// 媒体库（Emby 里叫 View）。`collectionType` 决定怎么取内容。
class EmbyLibrary {
  const EmbyLibrary({
    required this.id,
    required this.name,
    required this.collectionType,
    this.imageTag,
  });

  final String id;
  final String name;

  /// `movies` / `tvshows` / `music` / `boxsets` …，可能为空。
  final String collectionType;
  final String? imageTag;

  factory EmbyLibrary.fromJson(Map<String, dynamic> json) => EmbyLibrary(
        id: json['Id']?.toString() ?? '',
        name: json['Name']?.toString() ?? '',
        collectionType: json['CollectionType']?.toString() ?? '',
        imageTag: _imageTagOf(json),
      );
}

/// 媒体条目：剧集（Series）、电影（Movie）、单集（Episode）都用它。
class EmbyItem {
  const EmbyItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesId,
    this.indexNumber,
    this.parentIndexNumber,
    this.productionYear,
    this.overview,
    this.communityRating,
    this.primaryImageTag,
    this.runTimeTicks,
  });

  final String id;
  final String name;

  /// `Series` / `Movie` / `Episode` / `Video` …
  final String type;
  final String? seriesId;

  /// 集号（Episode 才有）。
  final int? indexNumber;

  /// 季号（Episode 才有）。
  final int? parentIndexNumber;
  final int? productionYear;
  final String? overview;
  final double? communityRating;
  final String? primaryImageTag;

  /// Emby 的时长单位是 100 纳秒一格。
  final int? runTimeTicks;

  bool get isSeries => type == 'Series';
  bool get isMovie => type == 'Movie';

  /// 详情页标题用的副标题，例如「2021 · 8.4 分」。
  String get metaLine {
    final parts = <String>[
      if (productionYear != null) '$productionYear',
      if (communityRating != null) '${communityRating!.toStringAsFixed(1)} 分',
    ];
    return parts.join(' · ');
  }

  Duration? get runTime {
    final ticks = runTimeTicks;
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: ticks ~/ 10);
  }

  factory EmbyItem.fromJson(Map<String, dynamic> json) => EmbyItem(
        id: json['Id']?.toString() ?? '',
        name: json['Name']?.toString() ?? '',
        type: json['Type']?.toString() ?? '',
        seriesId: json['SeriesId']?.toString(),
        indexNumber: _intOrNull(json['IndexNumber']),
        parentIndexNumber: _intOrNull(json['ParentIndexNumber']),
        productionYear: _intOrNull(json['ProductionYear']),
        overview: json['Overview']?.toString(),
        communityRating: _doubleOrNull(json['CommunityRating']),
        primaryImageTag: _imageTagOf(json),
        runTimeTicks: _intOrNull(json['RunTimeTicks']),
      );
}

String? _imageTagOf(Map<String, dynamic> json) {
  final tags = json['ImageTags'];
  if (tags is Map) {
    final primary = tags['Primary']?.toString();
    if (primary != null && primary.isNotEmpty) return primary;
  }
  return null;
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleOrNull(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

/// 把 Emby 的字符串 id 折成一个稳定的正整数，喂给 [PlaybackInitParams.bangumiId]。
///
/// 播放器和历史都要求 int 型 bangumiId，而 Emby 用 GUID。这里用 FNV-1a
/// 取 31 位，保证同一部剧每次算出来一样（历史才能命中），也不会溢出 int。
int embyBangumiId(String itemId) {
  var hash = 0x811c9dc5;
  for (final unit in itemId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  // 0 会让部分历史逻辑当成"无效条目"，避一下。
  return hash == 0 ? 1 : hash;
}

/// 规范化用户填进来的服务器地址。
///
/// 用户经常直接粘贴 Emby 网页地址（带 /web/index.html），或者漏了协议。
/// 这里统一成 `scheme://host:port[/子路径]`，去掉查询串和界面路径。
String normalizeEmbyUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  if (!text.contains('://')) {
    text = 'http://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return '';
  var path = uri.path;
  // 砍掉 Emby 网页端的入口路径。
  final webIndex = path.indexOf('/web/');
  if (webIndex >= 0) path = path.substring(0, webIndex);
  if (path.endsWith('/web')) path = path.substring(0, path.length - 4);
  // 用户手打的地址常有 `host:8096//` 这种，一个 endsWith 只能砍一层。
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '${uri.scheme}://${uri.authority}$path';
}
