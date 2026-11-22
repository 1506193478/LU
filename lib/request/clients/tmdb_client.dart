import 'package:dio/dio.dart';

import 'package:XL/request/core/dio_factory.dart';
import 'package:XL/request/core/network_config.dart';
import 'package:XL/services/emby/tmdb_prefs.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/modules/emby/emby_models.dart';

/// 客户端直连 TMDB 的轻量客户端。
///
/// 只做两件事：搜索候选 + 测试连接。拿到候选后由调用方把 TMDB ID 桥接给
/// 服务端的 Apply 接口写回元数据——所以这里不需要 TMDB 的写入权限，
/// 只读的 API Key / 读取令牌就够。
class TmdbClient {
  TmdbClient() {
    _dio = DioFactory.createForConfig(NetworkConfig.fromSettings());
  }

  late final Dio _dio;

  Map<String, dynamic> _authQuery() =>
      TmdbPrefs.isBearerToken ? const <String, dynamic>{} : {'api_key': TmdbPrefs.apiKey};

  Map<String, String> _authHeaders() => TmdbPrefs.isBearerToken
      ? <String, String>{'Authorization': 'Bearer ${TmdbPrefs.apiKey}', 'accept': 'application/json'}
      : <String, String>{'accept': 'application/json'};

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${TmdbPrefs.apiBase}$path',
      queryParameters: <String, dynamic>{..._authQuery(), ...query},
      options: Options(headers: _authHeaders()),
    );
    return response.data ?? const <String, dynamic>{};
  }

  /// 测试连接：TMDB 的 /configuration 只需只读权限，返回 images 配置即通。
  /// 返回 null 表示成功，否则返回错误说明。
  Future<String?> testConnection() async {
    if (!TmdbPrefs.configured) return '请先填写 API Key 或读取令牌';
    try {
      final body = await _get('/configuration');
      if (body['images'] is Map) return null;
      return '响应异常：${body.toString().substring(0, body.toString().length.clamp(0, 120))}';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) return '认证失败：API Key / 令牌无效';
      if (code == 404) return 'API 地址不对，检查是否以 /3 结尾';
      return '连接失败：${e.message ?? e.type.name}';
    } catch (e) {
      return '连接失败：$e';
    }
  }

  /// 按标题搜索。优先一次 multi 搜索（电影/剧集混合），失败再分别搜。
  Future<List<EmbyRemoteSearchResult>> search(String keyword) async {
    if (keyword.trim().isEmpty || !TmdbPrefs.configured) return const [];
    try {
      final body = await _get(
        '/search/multi',
        query: {'query': keyword.trim(), 'include_adult': false, 'page': 1},
      );
      final results = body['results'];
      if (results is! List) return const [];
      return [
        for (final r in results)
          if (r is Map) _fromMulti(Map<String, dynamic>.from(r)),
      ].where((r) => r.name.isNotEmpty).toList();
    } on DioException catch (e) {
      KazumiLogger().w('TMDB: multi search failed', error: e);
      return _searchSplit(keyword);
    } catch (e) {
      KazumiLogger().w('TMDB: search failed', error: e);
      return const [];
    }
  }

  Future<List<EmbyRemoteSearchResult>> _searchSplit(String keyword) async {
    try {
      final movie = await _get('/search/movie', query: {'query': keyword.trim(), 'page': 1});
      final tv = await _get('/search/tv', query: {'query': keyword.trim(), 'page': 1});
      final out = <EmbyRemoteSearchResult>[];
      final mr = movie['results'];
      final tr = tv['results'];
      if (mr is List) {
        for (final r in mr) {
          if (r is Map) out.add(_from(Map<String, dynamic>.from(r), 'Movie'));
        }
      }
      if (tr is List) {
        for (final r in tr) {
          if (r is Map) out.add(_from(Map<String, dynamic>.from(r), 'Series'));
        }
      }
      return out.where((r) => r.name.isNotEmpty).toList();
    } catch (e) {
      KazumiLogger().w('TMDB: split search failed', error: e);
      return const [];
    }
  }

  EmbyRemoteSearchResult _fromMulti(Map<String, dynamic> r) {
    final type = r['media_type']?.toString() ?? '';
    final isSeries = type == 'tv';
    return _from(r, isSeries ? 'Series' : 'Movie');
  }

  EmbyRemoteSearchResult _from(Map<String, dynamic> r, String kind) {
    final id = r['id']?.toString() ?? '';
    final poster = r['poster_path']?.toString() ?? '';
    final yearRaw = (r['release_date'] ?? r['first_air_date']).toString();
    int? year;
    if (yearRaw.length >= 4) year = int.tryParse(yearRaw.substring(0, 4));
    return EmbyRemoteSearchResult(
      name: (r['title'] ?? r['name'] ?? '').toString(),
      year: year,
      overview: (r['overview'] ?? '').toString(),
      imageUrl: TmdbPrefs.imageUrl(poster),
      providerName: 'TMDB',
      providerIds: <String, String>{'Tmdb': id},
      // Apply 回传需要这些字段，保留原始 map（补上 ProviderIds）。
      raw: <String, dynamic>{
        ...r,
        'ProviderIds': <String, String>{'Tmdb': id},
        'SearchProviderName': 'TMDB',
      },
    );
  }
}
