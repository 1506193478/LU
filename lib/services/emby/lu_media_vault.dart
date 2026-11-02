import 'dart:convert';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:dio/dio.dart';

/// 本地导入的一条视频。
///
/// kind 决定它归到资源库的哪张卡片下面：
/// - `local`   本地文件
/// - `private` 本地私密
/// - `gallery` 相册视频
/// - `link`    网络链接
class LuMediaEntry {
  const LuMediaEntry({
    required this.id,
    required this.name,
    required this.source,
    required this.kind,
    this.addedAt = 0,
  });

  final String id;
  final String name;

  /// 本地文件路径，或者网络链接。
  final String source;
  final String kind;
  final int addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'kind': kind,
        'addedAt': addedAt,
      };

  factory LuMediaEntry.fromJson(Map<String, dynamic> json) => LuMediaEntry(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'local',
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 一条备用线路（服务器表单里「备用线路」页新增的那种）。
///
/// 跟主线路的区别：**没有账号密码**。备用线路只是同一台服务器换了个
/// 地址（换个域名、走内网、走中转），登录态是跟着 server 走的，所以这里
/// 只存地址四件套 + 一个给人看的名字。
class LuBackupLine {
  const LuBackupLine({
    required this.id,
    this.name = '',
    this.host = '',
    this.path = '',
    this.port = 0,
    this.https = false,
  });

  final String id;
  final String name;
  final String host;
  final String path;
  final int port;
  final bool https;

  /// 线路列表里显示的名字。没填名字就退回主机名。
  String get displayName => name.isNotEmpty ? name : host;

  /// 拼出基址，规则跟 [LuVaultServer.baseUrl] 完全一致，别各写一套。
  String get baseUrl => buildBaseUrl(
        host: host,
        path: path,
        port: port,
        https: https,
      );

  LuBackupLine copyWith({
    String? name,
    String? host,
    String? path,
    int? port,
    bool? https,
  }) =>
      LuBackupLine(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        path: path ?? this.path,
        port: port ?? this.port,
        https: https ?? this.https,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'path': path,
        'port': port,
        'https': https,
      };

  factory LuBackupLine.fromJson(Map<String, dynamic> json) => LuBackupLine(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        host: json['host']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        port: (json['port'] as num?)?.toInt() ?? 0,
        https: json['https'] == true,
      );
}

/// 主机 / 路径 / 端口 / https → `https://host:8096/path`。
///
/// 抽成顶层函数是因为主线路和备用线路必须拼得一模一样，不然「主线路能连、
/// 备用线路连不上」这种问题会查很久。
String buildBaseUrl({
  required String host,
  String path = '',
  int port = 0,
  bool https = false,
}) {
  if (host.isEmpty) return '';
  final scheme = https ? 'https' : 'http';
  final p = port > 0 ? ':$port' : '';
  var h = host.trim();
  if (h.startsWith('http://') || h.startsWith('https://')) {
    h = h.replaceFirst(RegExp(r'^https?://'), '');
  }
  h = h.replaceAll(RegExp(r'/$'), '');
  var suffix = path.trim();
  if (suffix.isNotEmpty && !suffix.startsWith('/')) suffix = '/$suffix';
  suffix = suffix.replaceAll(RegExp(r'/$'), '');
  return '$scheme://$h$p$suffix';
}

/// 资源库里添加的一台"服务器"（Emby / Jellyfin / WebDAV / 网盘…）。
///
/// 表里每一项都按设计稿的表单原样保存，即便某些类型暂时不能直接连，
/// 也先把用户填的东西留住。
class LuVaultServer {
  const LuVaultServer({
    required this.id,
    required this.type,
    this.name = '',
    this.note = '',
    this.host = '',
    this.path = '',
    this.port = 0,
    this.https = false,
    this.user = '',
    this.password = '',
    this.addedAt = 0,
    this.backupLines = const <LuBackupLine>[],
  });

  final String id;

  /// `emby` / `jellyfin` / `plex` / `feiniu` / `webdav` / `smb` / `ftp` /
  /// `115` / `123` / `guangya` / `baidu` / `aliyun` / `onedrive` / `dropbox`
  final String type;
  final String name;
  final String note;
  final String host;
  final String path;
  final int port;

  /// 有没有勾 https。
  final bool https;
  final String user;
  final String password;
  final int addedAt;

  /// 备用线路。主线路连不上时按这个顺序依次顶上去。
  final List<LuBackupLine> backupLines;

  /// 真正能直连浏览的只有 WebDAV（含走 WebDAV 网关的网盘）。
  bool get isWebdav => type == 'webdav';

  /// Emby / Jellyfin 走 Emby 那套 API。
  bool get isEmbyLike => type == 'emby' || type == 'jellyfin' || type == 'feiniu';

  String get displayName => name.isNotEmpty ? name : typeLabel;

  String get typeLabel => switch (type) {
        'emby' => 'Emby',
        'jellyfin' => 'Jellyfin',
        'plex' => 'Plex',
        'feiniu' => '飞牛影视',
        'webdav' => 'WebDAV',
        'smb' => 'SMB',
        'ftp' => 'FTP',
        '115' => '115网盘',
        '123' => '123云盘',
        'guangya' => '光鸭云盘',
        'baidu' => '百度网盘',
        'aliyun' => '阿里网盘',
        'onedrive' => 'OneDrive',
        'dropbox' => 'Dropbox',
        _ => '资源',
      };

  /// 拼出基础地址，例如 `https://host:8096/path`。
  String get baseUrl => buildBaseUrl(
        host: host,
        path: path,
        port: port,
        https: https,
      );

  /// 备用线路里能真正拼出地址的那些（空主机的直接跳过）。
  List<String> get backupUrls => [
        for (final line in backupLines)
          if (line.baseUrl.isNotEmpty) line.baseUrl,
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'note': note,
        'host': host,
        'path': path,
        'port': port,
        'https': https,
        'user': user,
        'password': password,
        'addedAt': addedAt,
        'backupLines': [for (final line in backupLines) line.toJson()],
      };

  factory LuVaultServer.fromJson(Map<String, dynamic> json) => LuVaultServer(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'emby',
        name: json['name']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
        host: json['host']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        port: (json['port'] as num?)?.toInt() ?? 0,
        https: json['https'] == true,
        user: json['user']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
        backupLines: [
          for (final item in (json['backupLines'] as List<dynamic>? ?? const []))
            if (item is Map) LuBackupLine.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
}

/// 本地资源库：管「本地文件 / 本地私密 / 相册视频 / 网络链接」四类导入，
/// 以及资源库里自己添加的服务器（含 WebDAV / 网盘）。
///
/// 全部落在设置盒里（JSON 字符串），跟着 App 一起备份，不需要额外开盒。
class LuMediaVault {
  LuMediaVault._();

  static final LuMediaVault instance = LuMediaVault._();

  static const _entriesKey = SettingKey<String>(
    'luVaultMediaEntries',
    '[]',
    group: SettingGroup.emby,
  );

  static const _serversKey = SettingKey<String>(
    'luVaultServers',
    '[]',
    group: SettingGroup.misc,
  );

  List<LuMediaEntry> _entries = const <LuMediaEntry>[];
  List<LuVaultServer> _servers = const <LuVaultServer>[];

  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final rawEntries = GStorage.getSetting(_entriesKey);
      _entries = (jsonDecode(rawEntries) as List<dynamic>? ?? [])
          .map((e) => LuMediaEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _entries = const <LuMediaEntry>[];
    }
    try {
      final rawServers = GStorage.getSetting(_serversKey);
      _servers = (jsonDecode(rawServers) as List<dynamic>? ?? [])
          .map((e) => LuVaultServer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _servers = const <LuVaultServer>[];
    }
  }

  Future<void> _saveEntries() async {
    await GStorage.putSetting(
      _entriesKey,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveServers() async {
    await GStorage.putSetting(
      _serversKey,
      jsonEncode(_servers.map((e) => e.toJson()).toList()),
    );
  }

  List<LuMediaEntry> entriesOf(String kind) {
    _ensureLoaded();
    return _entries.where((e) => e.kind == kind).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  List<LuVaultServer> get servers {
    _ensureLoaded();
    return List.unmodifiable(_servers);
  }

  /// 加一批（去重：同一 source + kind 只留一条，但刷新时间）。
  Future<void> addEntries(String kind, List<({String name, String source})> items) async {
    _ensureLoaded();
    final list = List<LuMediaEntry>.from(_entries);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final it in items) {
      list.removeWhere((e) => e.kind == kind && e.source == it.source);
      list.add(LuMediaEntry(
        id: '$kind-${now.hashCode}-${list.length}',
        name: it.name,
        source: it.source,
        kind: kind,
        addedAt: now,
      ));
    }
    _entries = list;
    await _saveEntries();
  }

  Future<void> removeEntry(LuMediaEntry entry) async {
    _ensureLoaded();
    _entries = List.of(_entries)..removeWhere((e) => e.id == entry.id);
    await _saveEntries();
  }

  Future<void> saveServer(LuVaultServer server) async {
    _ensureLoaded();
    final list = List<LuVaultServer>.from(_servers)
      ..removeWhere((s) => s.id == server.id);
    list.add(server);
    _servers = list;
    await _saveServers();
  }

  Future<void> removeServer(String id) async {
    _ensureLoaded();
    _servers = List.of(_servers)..removeWhere((s) => s.id == id);
    await _saveServers();
  }
}

/// WebDAV 上列出来的一项。
class WebDavEntry {
  const WebDavEntry({
    required this.name,
    required this.href,
    required this.isDirectory,
  });

  final String name;
  final String href;
  final bool isDirectory;
}

/// 极简 WebDAV 客户端：只做列目录（PROPFIND），够资源库挑视频用了。
class LuWebDavClient {
  LuWebDavClient({required this.baseUrl, this.user = '', this.password = ''});

  final String baseUrl;
  final String user;
  final String password;

  Dio? _dio;

  Dio get _client {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        if (user.isNotEmpty)
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      },
      validateStatus: (code) => code != null && code < 500,
    ));
    return _dio!;
  }

  /// 列目录。`subPath` 是相对 baseUrl 的路径，根目录传 '' 或 '/'。
  Future<List<WebDavEntry>> list(String subPath) async {
    var path = subPath.isEmpty ? '/' : subPath;
    if (!path.startsWith('/')) path = '/$path';
    final url = '$baseUrl$path';

    final resp = await _client.request<String>(
      url,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
        responseType: ResponseType.plain,
      ),
    );
    final body = resp.data ?? '';
    return _parse(body);
  }

  /// 把 PROPFIND 的 XML 拆成条目。这里不引 xml 包，用正则就够了：
  /// 只需要 href 和它对应的 `<d:collection/>`（目录）标记。
  List<WebDavEntry> _parse(String xml) {
    final result = <WebDavEntry>[];
    final blocks = RegExp(r'<d:response\b[^>]*>([\s\S]*?)</d:response>',
            caseSensitive: false)
        .allMatches(xml);
    for (final m in blocks) {
      final block = m.group(1) ?? '';
      final hrefMatch = RegExp(r'<d:href\b[^>]*>([\s\S]*?)</d:href>',
              caseSensitive: false)
          .firstMatch(block);
      if (hrefMatch == null) continue;
      final rawHref = hrefMatch.group(1)!.trim();
      final href = Uri.decodeComponent(rawHref);
      final isDir = RegExp(r'<d:collection\s*/>|<d:collection\b[^>]*>',
              caseSensitive: false)
          .hasMatch(block);

      // 去掉自己这一级，只留子项。
      final name = href
          .replaceAll(RegExp(r'/$'), '')
          .split('/')
          .where((s) => s.isNotEmpty)
          .lastOrNull;
      if (name == null || name.isEmpty) continue;
      if (_isSelf(href)) continue;
      result.add(WebDavEntry(name: name, href: href, isDirectory: isDir));
    }
    result.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  bool _isSelf(String href) {
    final self = Uri.parse(baseUrl).path.replaceAll(RegExp(r'/$'), '');
    final cur = href.replaceAll(RegExp(r'/$'), '');
    return cur == self || cur.isEmpty || cur == '/';
  }

  /// 视频文件的可播地址。
  ///
  /// 需要账号密码的 WebDAV 没法给 media_kit 塞 header，所以把凭据编进 URL
  /// 的 userinfo 段——ffmpeg/libmpv 认这种写法。
  String playableUrl(WebDavEntry entry) {
    final uri = Uri.parse(baseUrl);
    final rawPath = entry.href.startsWith('/') ? entry.href : '/${entry.href}';
    if (user.isEmpty) {
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$rawPath';
    }
    final encUser = Uri.encodeComponent(user);
    final encPass = Uri.encodeComponent(password);
    return '${uri.scheme}://$encUser:$encPass@${uri.host}'
        '${uri.hasPort ? ':${uri.port}' : ''}$rawPath';
  }
}
