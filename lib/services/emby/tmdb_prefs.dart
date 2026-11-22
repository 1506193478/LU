import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 客户端直连 TMDB 的配置（对标 SenPlayer 的 TMDB 设置页）。
///
/// 用途：图片地址用来拼 Emby 条目 / 刮削候选的海报；API Key 与 API 地址
/// 用在「识别元数据」里做客户端侧搜索——拿到 TMDB ID 后桥接服务端 Apply
/// 写回，这样即使服务端元数据搜索受限，客户端也能搜到候选。
class TmdbPrefs {
  TmdbPrefs._();

  static const defaultApiBase = 'https://api.themoviedb.org/3';
  static const defaultImageBase = 'https://image.tmdb.org/t/p';

  static String get apiKey =>
      GStorage.getSetting(SettingsKeys.tmdbApiKey).trim();

  static String get apiBase {
    final raw = GStorage.getSetting(SettingsKeys.tmdbApiBase).trim();
    return raw.isEmpty ? defaultApiBase : _stripSlash(raw);
  }

  static String get imageBase {
    final raw = GStorage.getSetting(SettingsKeys.tmdbImageBase).trim();
    return raw.isEmpty ? defaultImageBase : _stripSlash(raw);
  }

  static String _stripSlash(String s) {
    var v = s;
    while (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  static Future<void> setApiKey(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbApiKey, value.trim());

  static Future<void> setApiBase(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbApiBase, value.trim());

  static Future<void> setImageBase(String value) =>
      GStorage.putSetting(SettingsKeys.tmdbImageBase, value.trim());

  /// 是否配置了可用的凭据（API Key v3 或 Bearer 读取令牌）。
  static bool get configured => apiKey.isNotEmpty;

  /// 拼 TMDB 图片完整地址。[size] 如 w500 / original。
  static String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    final p = path.startsWith('/') ? path : '/$path';
    return '$imageBase/$size$p';
  }

  /// 认证头：以 eyJ 开头的是 JWT 读取令牌（Bearer），否则是 v3 API Key（query）。
  static bool get isBearerToken => apiKey.startsWith('eyJ');
}
