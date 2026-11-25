import 'package:XL/services/storage/storage.dart';

/// 客户端直连 TMDB 的配置（对标 SenPlayer 的 TMDB 设置页）。
///
/// 零配置可用：内置公共 v3 Key 兜底 + 三条候选线路（官方备用域名 /
/// 官方主域名 / 社区公共反代），设置页可一键探测选线；用户自己的 Key
/// 与自定义地址优先级最高。
///
/// 用途：图片地址用来拼 Emby 条目 / 刮削候选的海报；API Key 与 API 地址
/// 用在「识别元数据」里做客户端侧搜索——拿到 TMDB ID 后桥接服务端 Apply
/// 写回，这样即使服务端元数据搜索受限，客户端也能搜到候选。
class TmdbPrefs {
  TmdbPrefs._();

  static const defaultApiBase = 'https://api.themoviedb.org/3';
  static const defaultImageBase = 'https://image.tmdb.org/t/p';

  /// 内置公共 v3 Key：开源社区广泛流通的公共凭据，只读权限，供未配置
  /// 的用户兜底。有速率上限，重度使用建议在设置页填自己的 Key。
  static const builtinApiKey = '3fd2be6f0c70a2a598f084adfb064088';

  /// 候选线路（按国内可达概率排序）。探测时逐条请求 /configuration，
  /// 第一条通的就采用并记住，下次不再探测。
  static const builtinLines = <({String url, String label})>[
    (
      url: 'https://api.tmdb.org/3',
      label: '官方备用域名 · 国内常可直连',
    ),
    (
      url: 'https://api.themoviedb.org/3',
      label: '官方主域名 · 需代理',
    ),
    (
      url: 'https://tmdb-proxy.demojameson.de5.net/3',
      label: '社区公共反代 · 兜底',
    ),
  ];

  static String get apiKey =>
      GStorage.getSetting(SettingsKeys.tmdbApiKey).trim();

  /// 实际生效的凭据：用户 Key 优先，没填就用内置公共 Key。
  static String get effectiveApiKey {
    final own = apiKey;
    return own.isNotEmpty ? own : builtinApiKey;
  }

  /// 是否在用内置公共 Key（设置页展示用）。
  static bool get usingBuiltinKey => apiKey.isEmpty;

  /// 用户是否自定义了 API 地址。历史版本会把官方主域名写进存储，
  /// 所以等于官方主域名也视为「没自定义」，让自动选线接管。
  static bool get hasCustomBase {
    final raw = GStorage.getSetting(SettingsKeys.tmdbApiBase).trim();
    return raw.isNotEmpty && raw != defaultApiBase;
  }

  static String get customBase {
    final raw = GStorage.getSetting(SettingsKeys.tmdbApiBase).trim();
    return hasCustomBase ? _stripSlash(raw) : '';
  }

  /// 自动选线结果（设置页探测后写入），空表示还没探测过。
  static String get autoLine =>
      GStorage.getSetting(SettingsKeys.tmdbAutoLine).trim();

  /// 当前生效的 API 地址：自定义 > 自动选线 > 官方主域名。
  static String get apiBase {
    final custom = customBase;
    if (custom.isNotEmpty) return custom;
    final auto = autoLine;
    if (auto.isNotEmpty) return auto;
    return defaultApiBase;
  }

  static String get imageBase {
    final raw = GStorage.getSetting(SettingsKeys.tmdbImageBase).trim();
    return raw.isEmpty ? defaultImageBase : _stripSlash(raw);
  }

  static String _stripSlash(String s) {
    var v = s;
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static Future<void> setApiKey(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbApiKey, value.trim());

  static Future<void> setApiBase(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbApiBase, value.trim());

  static Future<void> setImageBase(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbImageBase, value.trim());

  /// 记住自动选线结果；传空 = 清除（回到官方主域名）。
  static Future<void> setAutoLine(String url) =>
      GStorage.putSetting(SettingsKeys.tmdbAutoLine, url.trim());

  /// 凭据是否可用——内置公共 Key 之后恒为 true，旧调用点（「未配置」
  /// 警告）自然失效。保留名字兼容现有代码。
  static bool get configured => true;

  /// 拼 TMDB 图片完整地址。[size] 如 w500 / original。
  static String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    final p = path.startsWith('/') ? path : '/$path';
    return '$imageBase/$size$p';
  }

  /// 认证头：以 eyJ 开头的是 JWT 读取令牌（Bearer），否则是 v3 API Key（query）。
  static bool get isBearerToken => effectiveApiKey.startsWith('eyJ');
}
