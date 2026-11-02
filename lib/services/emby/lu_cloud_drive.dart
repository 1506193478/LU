import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 网盘接入。
///
/// 每家都走自己的官方接口：
///   * 123 云盘：账号密码换 token（`/b/api/user/sign_in`），再列目录 / 取直链
///   * 115 网盘：扫码登录（`qrcodeapi.115.com` → `passportapi.115.com`），
///     之后用 `webapi.115.com/files` 列目录、`files/download` 取直链
///   * 阿里 / 百度 / OneDrive / Dropbox：粘贴各家控制台签发的 access token，
///     直接用 OpenAPI 列目录（这些家的 OAuth 必须带自家注册的 client_id，
///     没法内置，所以做成"粘贴令牌"这一步，等价于 OAuth 的最后一步）
///   * 光鸭云盘：没有公开接口，先只存账号，取目录会给出明确提示
///
/// 拿到的直链直接丢给 LU 的播放器（media_kit），不落地、不转码。
class LuCloudDrive {
  LuCloudDrive._();

  /// 走网盘通道的类型。其余（webdav/smb/ftp/emby/jellyfin）走服务器表单。
  static const Set<String> cloudTypes = {
    '115',
    '123',
    'guangya',
    'baidu',
    'aliyun',
    'onedrive',
    'dropbox',
  };

  static bool isCloudType(String type) => cloudTypes.contains(type);

  /// 授权方式：`password` 账号密码、`qrcode` 扫码、`token` 粘贴令牌、`none` 暂不支持。
  static String authMode(String type) => switch (type) {
        '123' => 'password',
        '115' => 'qrcode',
        'aliyun' || 'baidu' || 'onedrive' || 'dropbox' => 'token',
        _ => 'none',
      };

  static String labelOf(String type) => switch (type) {
        '115' => '115网盘',
        '123' => '123云盘',
        'guangya' => '光鸭云盘',
        'baidu' => '百度网盘',
        'aliyun' => '阿里网盘',
        'onedrive' => 'OneDrive',
        'dropbox' => 'Dropbox',
        _ => type,
      };

  /// 各家令牌的获取入口，卡片上会显示成一行小字。
  static String tokenHint(String type) => switch (type) {
        'aliyun' => '在阿里云盘开放平台控制台拿 access_token（或扫码后复制）',
        'baidu' => '在百度网盘开放平台控制台拿 access_token',
        'onedrive' => '在 Microsoft Graph 拿 access_token（需应用注册）',
        'dropbox' => '在 Dropbox App Console 拿 access_token',
        _ => '粘贴该网盘的访问令牌',
      };

  static String accountId(String type) =>
      'cloud-$type-${DateTime.now().millisecondsSinceEpoch}';
}

/// 一个已授权的网盘账号。
class LuCloudAccount {
  const LuCloudAccount({
    required this.id,
    required this.type,
    required this.label,
    this.user = '',
    this.token = '',
    this.refreshToken = '',
    this.extra = '',
    required this.addedAt,
  });

  final String id;
  final String type;
  final String label;
  final String user;
  final String token;
  final String refreshToken;

  /// 各家自己的补充字段（uid / driveId / 过期时间…），存成 JSON 字符串。
  final String extra;
  final int addedAt;

  String get typeLabel => LuCloudDrive.labelOf(type);

  Map<String, dynamic> get extraMap {
    if (extra.isEmpty) return const {};
    try {
      final v = jsonDecode(extra);
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        'user': user,
        'token': token,
        'refreshToken': refreshToken,
        'extra': extra,
        'addedAt': addedAt,
      };

  factory LuCloudAccount.fromJson(Map<String, dynamic> json) => LuCloudAccount(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        user: json['user']?.toString() ?? '',
        token: json['token']?.toString() ?? '',
        refreshToken: json['refreshToken']?.toString() ?? '',
        extra: json['extra']?.toString() ?? '',
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 账号持久化。
class LuCloudStore {
  LuCloudStore._();

  static final LuCloudStore instance = LuCloudStore._();

  static const SettingKey<String> _key = SettingKey<String>(
    'luCloudAccounts',
    '[]',
    group: SettingGroup.emby,
  );

  List<LuCloudAccount> get accounts {
    final raw = GStorage.getSetting(_key);
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map) LuCloudAccount.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(LuCloudAccount account) async {
    final next = [
      for (final a in accounts)
        if (a.id != account.id) a,
      account,
    ];
    await _write(next);
  }

  Future<void> remove(String id) async {
    await _write([
      for (final a in accounts)
        if (a.id != id) a,
    ]);
  }

  Future<void> _write(List<LuCloudAccount> list) => GStorage.putSetting(
        _key,
        jsonEncode([for (final a in list) a.toJson()]),
      );
}

/// 网盘里的一个文件 / 文件夹。
class LuCloudFile {
  const LuCloudFile({
    required this.id,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.raw = const {},
  });

  final String id;
  final String name;
  final bool isDir;
  final int size;
  final Map<String, dynamic> raw;

  String get sizeLabel {
    if (size <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = size.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  bool get looksLikeVideo {
    final n = name.toLowerCase();
    return const [
      '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.ts', '.flv', '.wmv', '.webm', '.rmvb', '.mpg', '.mpeg', '.iso',
    ].any(n.endsWith);
  }
}

class LuCloudException implements Exception {
  LuCloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 扫码登录的会话。
class LuQrSession {
  const LuQrSession({
    required this.imageUrl,
    required this.uid,
    required this.time,
    required this.sign,
  });

  final String imageUrl;
  final String uid;
  final String time;
  final String sign;
}

/// 扫码状态。
enum LuQrState { waiting, scanned, confirmed, expired }

/// 各家接口。
class LuCloudApi {
  LuCloudApi._();

  static Dio _dio(Map<String, String> headers) => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        validateStatus: (code) => code != null && code < 500,
        headers: headers,
      ));

  static const Map<String, String> _ua = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
  };

  // ------------------------------------------------------------ 123 云盘

  /// 账号密码登录，返回带 token 的账号。
  static Future<LuCloudAccount> login123({
    required String user,
    required String password,
    required String label,
  }) async {
    final dio = _dio({..._ua, 'platform': 'web', 'app-version': '3'});
    final Response<dynamic> res;
    try {
      res = await dio.post(
        'https://www.123pan.com/b/api/user/sign_in',
        data: {'passport': user, 'password': password, 'remember': true},
      );
    } on DioException catch (e) {
      throw LuCloudException('连接 123 云盘失败：${e.message ?? e.type.name}');
    }
    final body = res.data;
    if (body is! Map || body['code'] != 200) {
      throw LuCloudException(
        '123 云盘登录失败：${body is Map ? (body['message'] ?? body['code']) : res.statusCode}',
      );
    }
    final data = body['data'];
    if (data is! Map || data['token'] == null) {
      throw LuCloudException('123 云盘返回里没有 token');
    }
    return LuCloudAccount(
      id: LuCloudDrive.accountId('123'),
      type: '123',
      label: label,
      user: user,
      token: data['token'].toString(),
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<List<LuCloudFile>> _list123(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio({
      ..._ua,
      'platform': 'web',
      'app-version': '3',
      'Authorization': 'Bearer ${a.token}',
    });
    final res = await dio.get(
      'https://www.123pan.com/b/api/file/list/new',
      queryParameters: {
        'driveId': '0',
        'limit': '100',
        'next': '0',
        'orderBy': 'file_name',
        'orderDirection': 'asc',
        'parentFileId': parentId,
        'trashed': 'false',
        'Page': '1',
        'SearchData': '',
      },
    );
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    final list = data is Map ? data['InfoList'] : null;
    if (list is! List) {
      throw LuCloudException('123 云盘目录读取失败：${body is Map ? body['message'] : res.statusCode}');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['FileId']?.toString() ?? '',
            name: e['FileName']?.toString() ?? '',
            isDir: e['Type'] == 1,
            size: (e['Size'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _play123(LuCloudAccount a, LuCloudFile f) async {
    final direct = f.raw['DownloadUrl']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;

    final dio = _dio({
      ..._ua,
      'platform': 'web',
      'app-version': '3',
      'Authorization': 'Bearer ${a.token}',
    });
    final res = await dio.post(
      'https://www.123pan.com/b/api/file/download_info',
      data: {
        'driveId': 0,
        'etag': f.raw['Etag'] ?? '',
        'fileId': int.tryParse(f.id) ?? f.id,
        's3keyFlag': f.raw['S3KeyFlag'] ?? '',
        'type': f.raw['Type'] ?? 0,
        'fileName': f.name,
        'size': f.size,
      },
    );
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    final url = data is Map ? data['DownloadUrl'] : null;
    return url?.toString();
  }

  // ------------------------------------------------------------ 115 网盘

  /// 起一个扫码会话（115 的二维码是官方接口直接给的图片地址）。
  static Future<LuQrSession> start115Qr() async {
    final dio = _dio(_ua);
    final res = await dio.get('https://qrcodeapi.115.com/api/1.0/web/1.0/token/');
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    if (data is! Map) {
      throw LuCloudException('115 扫码初始化失败');
    }
    return LuQrSession(
      imageUrl: data['qrcode']?.toString() ?? '',
      uid: data['uid']?.toString() ?? '',
      time: data['time']?.toString() ?? '',
      sign: data['sign']?.toString() ?? '',
    );
  }

  /// 轮询扫码状态；确认后返回账号，否则返回 null。
  static Future<(LuQrState, LuCloudAccount?)> poll115Qr(
    LuQrSession s, {
    required String label,
  }) async {
    final dio = _dio(_ua);
    final res = await dio.get(
      'https://qrcodeapi.115.com/get/status/',
      queryParameters: {'uid': s.uid, 'time': s.time, 'sign': s.sign},
    );
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    if (data is! Map) return (LuQrState.waiting, null);
    final status = (data['status'] as num?)?.toInt() ?? 0;
    if (status == 0) return (LuQrState.waiting, null);
    if (status == 1) return (LuQrState.scanned, null);
    if (status != 2) return (LuQrState.expired, null);

    // status == 2：确认登录，拿 cookie。
    final cookie = _cookieFrom(data, res.headers);
    if (cookie.isEmpty) return (LuQrState.expired, null);
    final uid = data['uid']?.toString() ?? '';
    return (
      LuQrState.confirmed,
      LuCloudAccount(
        id: LuCloudDrive.accountId('115'),
        type: '115',
        label: label,
        user: uid,
        token: cookie,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static String _cookieFrom(Map data, Headers headers) {
    // 有的版本在 data 里给 uid/cid/seid/kid，有的只在 Set-Cookie 里给。
    final uid = data['uid']?.toString();
    final cid = data['cid']?.toString();
    final seid = data['seid']?.toString();
    final kid = data['kid']?.toString();
    if (uid != null && cid != null && seid != null) {
      return 'UID=$uid; CID=$cid; SEID=$seid; KID=${kid ?? ''}';
    }
    final raw = headers.map['set-cookie'];
    if (raw == null || raw.isEmpty) return '';
    final parts = <String>[];
    for (final line in raw) {
      final head = line.split(';').first.trim();
      if (head.startsWith('UID=') ||
          head.startsWith('CID=') ||
          head.startsWith('SEID=') ||
          head.startsWith('KID=')) {
        parts.add(head);
      }
    }
    return parts.join('; ');
  }

  static Future<List<LuCloudFile>> _list115(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio({..._ua, 'Cookie': a.token});
    final res = await dio.get(
      'https://webapi.115.com/files',
      queryParameters: {
        'aid': '1',
        'cid': parentId,
        'o': 'user_ptime',
        'asc': '0',
        'offset': '0',
        'show_dir': '1',
        'limit': '100',
        'snap': '0',
        'natsort': '1',
        'format': 'json',
      },
    );
    final body = res.data;
    final list = body is Map ? body['data'] : null;
    if (list is! List) {
      throw LuCloudException('115 目录读取失败（登录可能已过期）');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['cid']?.toString() ?? e['fid']?.toString() ?? '',
            name: e['n']?.toString() ?? '',
            isDir: e['cid'] != null && e['fid'] == null,
            size: (e['s'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _play115(LuCloudAccount a, LuCloudFile f) async {
    final pick = f.raw['pc']?.toString() ?? '';
    if (pick.isEmpty) return null;
    final dio = _dio({..._ua, 'Cookie': a.token});
    final res = await dio.get(
      'https://webapi.115.com/files/download',
      queryParameters: {'pick_code': pick},
    );
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    final nested = data is Map ? data['url'] : null;
    final url = nested is Map ? nested['url'] : null;
    return url?.toString();
  }

  // ------------------------------------------------------------ 阿里 / 百度 / OneDrive / Dropbox

  static Future<List<LuCloudFile>> _listAliyun(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio({
      ..._ua,
      'Authorization': 'Bearer ${a.token}',
      'Content-Type': 'application/json',
    });
    final driveId = a.extraMap['driveId']?.toString() ?? 'default';
    final res = await dio.post(
      'https://openapi.alipan.com/adrive/v3/file/list',
      data: {
        'drive_id': driveId,
        'parent_file_id': parentId.isEmpty ? 'root' : parentId,
        'limit': 100,
        'order_by': 'name',
        'order_direction': 'ASC',
      },
    );
    final body = res.data;
    final list = body is Map ? body['items'] : null;
    if (list is! List) {
      throw LuCloudException('阿里网盘目录读取失败：${body is Map ? body['message'] : res.statusCode}');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['file_id']?.toString() ?? '',
            name: e['name']?.toString() ?? '',
            isDir: e['type'] == 'folder',
            size: (e['size'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _playAliyun(LuCloudAccount a, LuCloudFile f) async {
    final dio = _dio({
      ..._ua,
      'Authorization': 'Bearer ${a.token}',
      'Content-Type': 'application/json',
    });
    final driveId = a.extraMap['driveId']?.toString() ?? 'default';
    final res = await dio.post(
      'https://openapi.alipan.com/adrive/v2/file/getDownloadUrl',
      data: {'drive_id': driveId, 'file_id': f.id},
    );
    final body = res.data;
    return body is Map ? body['url']?.toString() : null;
  }

  static Future<List<LuCloudFile>> _listBaidu(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio(_ua);
    final res = await dio.get(
      'https://pan.baidu.com/rest/2.0/xpan/file',
      queryParameters: {
        'method': 'list',
        'access_token': a.token,
        'dir': parentId.isEmpty ? '/' : parentId,
        'limit': '100',
        'order': 'name',
      },
    );
    final body = res.data;
    final list = body is Map ? body['list'] : null;
    if (list is! List) {
      throw LuCloudException('百度网盘目录读取失败：${body is Map ? body['errmsg'] : res.statusCode}');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['path']?.toString() ?? e['fs_id']?.toString() ?? '',
            name: e['server_filename']?.toString() ?? '',
            isDir: e['isdir'] == 1,
            size: (e['size'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _playBaidu(LuCloudAccount a, LuCloudFile f) async {
    final dio = _dio(_ua);
    final res = await dio.get(
      'https://pan.baidu.com/rest/2.0/xpan/multimedia',
      queryParameters: {
        'method': 'filemetas',
        'access_token': a.token,
        'fsids': '[${f.raw['fs_id']}]',
        'dlink': '1',
      },
    );
    final body = res.data;
    final list = body is Map ? body['list'] : null;
    if (list is List && list.isNotEmpty && list.first is Map) {
      final dlink = (list.first as Map)['dlink']?.toString();
      if (dlink != null && dlink.isNotEmpty) {
        return '$dlink&access_token=${a.token}';
      }
    }
    return null;
  }

  static Future<List<LuCloudFile>> _listOneDrive(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio({..._ua, 'Authorization': 'Bearer ${a.token}'});
    final path = parentId.isEmpty
        ? '/me/drive/root/children'
        : '/me/drive/items/$parentId/children';
    final res = await dio.get('https://graph.microsoft.com/v1.0$path');
    final body = res.data;
    final list = body is Map ? body['value'] : null;
    if (list is! List) {
      throw LuCloudException('OneDrive 目录读取失败：${body is Map ? body['error'] : res.statusCode}');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['id']?.toString() ?? '',
            name: e['name']?.toString() ?? '',
            isDir: e['folder'] != null,
            size: (e['size'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _playOneDrive(LuCloudAccount a, LuCloudFile f) async {
    final direct = f.raw['@microsoft.graph.downloadUrl']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final dio = _dio({..._ua, 'Authorization': 'Bearer ${a.token}'});
    final res = await dio.get(
      'https://graph.microsoft.com/v1.0/me/drive/items/${f.id}',
    );
    final body = res.data;
    return body is Map
        ? body['@microsoft.graph.downloadUrl']?.toString()
        : null;
  }

  static Future<List<LuCloudFile>> _listDropbox(
    LuCloudAccount a, {
    required String parentId,
  }) async {
    final dio = _dio({
      ..._ua,
      'Authorization': 'Bearer ${a.token}',
      'Content-Type': 'application/json',
    });
    final res = await dio.post(
      'https://api.dropboxapi.com/2/files/list_folder',
      data: {'path': parentId, 'limit': 200},
    );
    final body = res.data;
    final list = body is Map ? body['entries'] : null;
    if (list is! List) {
      throw LuCloudException('Dropbox 目录读取失败：${body is Map ? body['error_summary'] : res.statusCode}');
    }
    return [
      for (final e in list)
        if (e is Map)
          LuCloudFile(
            id: e['path_lower']?.toString() ?? e['id']?.toString() ?? '',
            name: e['name']?.toString() ?? '',
            isDir: e['.tag'] == 'folder',
            size: (e['size'] as num?)?.toInt() ?? 0,
            raw: Map<String, dynamic>.from(e),
          ),
    ];
  }

  static Future<String?> _playDropbox(LuCloudAccount a, LuCloudFile f) async {
    final dio = _dio({
      ..._ua,
      'Authorization': 'Bearer ${a.token}',
      'Content-Type': 'application/json',
    });
    final res = await dio.post(
      'https://api.dropboxapi.com/2/files/get_temporary_link',
      data: {'path': f.id},
    );
    final body = res.data;
    return body is Map ? body['link']?.toString() : null;
  }

  // ------------------------------------------------------------ 统一入口

  static Future<List<LuCloudFile>> list(
    LuCloudAccount a, {
    String parentId = '',
  }) async {
    try {
      switch (a.type) {
        case '123':
          return await _list123(a, parentId: parentId.isEmpty ? '0' : parentId);
        case '115':
          return await _list115(a, parentId: parentId.isEmpty ? '0' : parentId);
        case 'aliyun':
          return await _listAliyun(a, parentId: parentId);
        case 'baidu':
          return await _listBaidu(a, parentId: parentId);
        case 'onedrive':
          return await _listOneDrive(a, parentId: parentId);
        case 'dropbox':
          return await _listDropbox(a, parentId: parentId);
        default:
          throw LuCloudException(
            '${LuCloudDrive.labelOf(a.type)} 没有公开接口，暂时只能保存账号，取不到目录',
          );
      }
    } on DioException catch (e) {
      throw LuCloudException('${a.typeLabel} 请求失败：${e.message ?? e.type.name}');
    }
  }

  static Future<String?> playUrl(LuCloudAccount a, LuCloudFile f) async {
    try {
      switch (a.type) {
        case '123':
          return await _play123(a, f);
        case '115':
          return await _play115(a, f);
        case 'aliyun':
          return await _playAliyun(a, f);
        case 'baidu':
          return await _playBaidu(a, f);
        case 'onedrive':
          return await _playOneDrive(a, f);
        case 'dropbox':
          return await _playDropbox(a, f);
        default:
          return null;
      }
    } on DioException catch (e) {
      throw LuCloudException('${a.typeLabel} 取直链失败：${e.message ?? e.type.name}');
    }
  }
}
