/// 自定义解析接口服务（多资源解析）。
///
/// 场景：网盘分享链、第三方资源页给的不是视频直链，而是「解析接口」的
/// 调用方式——把原地址拼进接口模板请求一下，返回的才是可播直链。
///
/// 规则存在设置里（资源库 → 设置 → 资源解析接口）：
///   * `urlParseApi`      接口模板，占位符 `{url}`（原样）/ `{url_enc}`（URL 编码）
///   * `urlParseJsonPath` 返回 JSON 时的字段路径（点分，如 `data.url`），留空自动探测
///
/// 解析形态（按优先级自动判定）：
///   1. 302 直链：接口直接重定向到视频地址，取最终 URL；
///   2. JSON：按 [urlParseJsonPath] 提取，或自动探测常见字段
///      （url / play_url / playUrl / video_url / data.url ...）；
///   3. 纯文本：取返回里第一个 http(s) 链接。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:XL/services/storage/storage.dart';

/// 解析失败异常（消息直接展示给用户）。
class UrlParseException implements Exception {
  const UrlParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UrlParseService {
  UrlParseService._();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  /// 是否配置了解析接口。
  static bool get enabled =>
      GStorage.getSetting(SettingsKeys.urlParseApi).trim().isNotEmpty;

  /// 用模板拼出解析请求地址。
  static String buildRequestUrl(String template, String url) {
    final enc = Uri.encodeFull(url);
    return template
        .replaceAll('{url_enc}', enc)
        .replaceAll('{url}', url)
        .trim();
  }

  /// 把「资源地址」解析成可播直链。
  ///
  /// 未配置解析接口时原样返回；解析失败抛 [UrlParseException]。
  static Future<String> resolve(String url) async {
    final raw = url.trim();
    final template = GStorage.getSetting(SettingsKeys.urlParseApi).trim();
    if (template.isEmpty || raw.isEmpty) return raw;
    // 已经是直链的直接放行（模板里没占位符时也放行，避免把直链再套一层）。
    if (!template.contains('{url}') && !template.contains('{url_enc}')) {
      return raw;
    }
    final requestUrl = buildRequestUrl(template, raw);
    if (Uri.tryParse(requestUrl) == null) {
      throw const UrlParseException('解析接口地址不合法');
    }

    final dio = Dio(BaseOptions(
      method: 'GET',
      // 关掉自动重定向：302 目标本身就是解析结果之一。
      followRedirects: false,
      validateStatus: (code) => code != null && code < 400,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'user-agent': _ua, 'accept': '*/*'},
      responseType: ResponseType.plain,
    ));
    try {
      final resp = await dio.fetch<dynamic>(
        RequestOptions(path: requestUrl, method: 'GET'),
      );
      final status = resp.statusCode ?? 0;
      // 形态 1：30x → Location 就是直链。
      if (status >= 300 && status < 400) {
        final loc = resp.headers.value('location') ?? '';
        if (loc.isNotEmpty) return absolutize(requestUrl, loc);
        throw const UrlParseException('解析接口重定向缺少 Location');
      }

      final body = (resp.data?.toString() ?? '').trim();
      if (body.isEmpty) {
        throw const UrlParseException('解析接口返回为空');
      }

      // 形态 2：JSON（显式路径优先，其次常见字段自动探测）。
      if (body.startsWith('{') || body.startsWith('[')) {
        try {
          final json = jsonDecode(body);
          final path = GStorage
              .getSetting(SettingsKeys.urlParseJsonPath)
              .trim();
          final found = <String>[];
          if (path.isNotEmpty) {
            final v = _walk(json, path.split('.'));
            if (v is String && v.trim().isNotEmpty) found.add(v.trim());
          } else {
            found.addAll(_probe(json));
          }
          for (final c in found) {
            if (c.startsWith('http://') || c.startsWith('https://')) return c;
          }
          if (found.isNotEmpty) return found.first;
          throw const UrlParseException('JSON 里没找到播放地址（检查字段路径）');
        } on UrlParseException {
          rethrow;
        } catch (_) {
          // JSON 解析失败 → 当纯文本兜底。
        }
      }

      // 形态 3：纯文本里找第一个视频链接。
      final match = RegExp(
        r'''https?://[^\s"'<>\\]+''',
        caseSensitive: false,
      ).firstMatch(body);
      if (match != null) {
        return match.group(0)!;
      }
      throw const UrlParseException('解析接口返回里没有可播放的地址');
    } on DioException catch (e) {
      throw UrlParseException('解析接口请求失败（${e.type.name}）');
    } finally {
      dio.close(force: true);
    }
  }

  static String absolutize(String base, String ref) {
    final b = Uri.tryParse(base);
    final r = Uri.tryParse(ref);
    if (b != null && r != null) return b.resolveUri(r).toString();
    return ref;
  }

  /// 按点分路径下钻 JSON（`data.url` → json['data']['url']）。
  static dynamic _walk(dynamic node, List<String> path) {
    dynamic cur = node;
    for (final seg in path) {
      if (cur is Map && cur.containsKey(seg)) {
        cur = cur[seg];
      } else if (cur is List) {
        final idx = int.tryParse(seg);
        if (idx == null || idx < 0 || idx >= cur.length) return null;
        cur = cur[idx];
      } else {
        return null;
      }
    }
    return cur;
  }

  /// 常见字段自动探测（广度优先，先精确后兜底）。
  static Iterable<String> _probe(dynamic json) sync* {
    const keys = [
      'url',
      'play_url',
      'playUrl',
      'video_url',
      'videoUrl',
      'source',
      'link',
      'data',
    ];
    final queue = <dynamic>[json];
    var guard = 0;
    while (queue.isNotEmpty && guard++ < 64) {
      final node = queue.removeAt(0);
      if (node is Map) {
        for (final k in node.keys) {
          final ks = k.toString();
          final v = node[k];
          if ((keys.contains(ks) ||
                  ks.toLowerCase().endsWith('_url') ||
                  ks.toLowerCase().endsWith('url')) &&
              v is String &&
              v.trim().isNotEmpty) {
            yield v.trim();
          } else if (v is Map || v is List) {
            queue.add(v);
          }
        }
      } else if (node is List) {
        for (final v in node.take(16)) {
          if (v is Map || v is List) queue.add(v);
        }
      }
    }
  }
}

