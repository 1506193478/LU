import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:XL/request/core/dio_factory.dart';
import 'package:XL/services/logging/logger.dart';

/// B 站 web 接口的 wbi 签名。
///
/// 未签名的 `x/web-interface/wbi/search/type` 会被风控拦下，返回一段 HTML
/// 挑战页而不是 JSON，所以搜索前必须先取 nav 里的 img/sub key 再签名。
class BilibiliWbi {
  BilibiliWbi._();

  /// 官方前端固定使用的密钥重排表，长度为 64。
  static const List<int> _mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, //
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52, //
  ];

  static String? _mixinKey;
  static DateTime? _mixinKeyFetchedAt;
  static Future<String>? _pending;

  /// mixinKey 每天轮换，缓存 6 小时足够，失败时下次调用会重新取。
  static const Duration _mixinKeyTtl = Duration(hours: 6);

  /// 返回已签名的查询串（含 `wts` 与 `w_rid`），调用方直接拼到 URL 后面。
  ///
  /// 这里自己拼串而不用 Dio 的 `queryParameters`，因为签名覆盖的是编码后的
  /// 原始字符串，交给 Dio 重新编码会导致签名对不上。
  static Future<String> signedQuery(Map<String, String> params) async {
    final mixinKey = await _loadMixinKey();
    final filtered = <String, String>{};
    params.forEach((key, value) {
      // 与 B 站前端一致：值里的这些字符不参与签名。
      filtered[key] = value.replaceAll(RegExp(r"[!'()*]"), '');
    });
    filtered['wts'] =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final orderedKeys = filtered.keys.toList()..sort();
    final query = orderedKeys
        .map(
          (key) =>
              '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(filtered[key]!)}',
        )
        .join('&');
    final wRid = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return '$query&w_rid=$wRid';
  }

  static Future<String> _loadMixinKey() {
    final cached = _mixinKey;
    final fetchedAt = _mixinKeyFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _mixinKeyTtl) {
      return Future.value(cached);
    }
    // 并发调用只发一次 nav 请求。
    return _pending ??= _fetchMixinKey().whenComplete(() => _pending = null);
  }

  static Future<String> _fetchMixinKey() async {
    final response = await DioFactory.apiDio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/nav',
      options: Options(headers: {'referer': 'https://www.bilibili.com'}),
    );
    final body = response.data;
    final data = body is Map ? body['data'] : null;
    final wbiImg = data is Map ? data['wbi_img'] : null;
    if (wbiImg is! Map) {
      throw StateError('Bilibili wbi_img 缺失，nav 接口可能被风控');
    }
    final imgKey = _keyFromUrl(wbiImg['img_url']?.toString() ?? '');
    final subKey = _keyFromUrl(wbiImg['sub_url']?.toString() ?? '');
    if (imgKey.isEmpty || subKey.isEmpty) {
      throw StateError('Bilibili wbi key 解析失败');
    }
    final raw = '$imgKey$subKey';
    final mixin = StringBuffer();
    for (final index in _mixinKeyEncTab) {
      if (index < raw.length) {
        mixin.write(raw[index]);
      }
    }
    // 官方实现只取前 32 位作为 mixinKey。
    final full = mixin.toString();
    final key = full.length > 32 ? full.substring(0, 32) : full;
    if (key.length < 32) {
      throw StateError('Bilibili mixin key 长度异常');
    }
    _mixinKey = key;
    _mixinKeyFetchedAt = DateTime.now();
    KazumiLogger().i('Danmaku: bilibili wbi key refreshed');
    return key;
  }

  /// 从 `https://i0.hdslb.com/bfs/wbi/7cd0....png` 里取出 `7cd0...`。
  static String _keyFromUrl(String url) {
    if (url.isEmpty) {
      return '';
    }
    final name = url.split('/').last;
    final dot = name.indexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }
}
