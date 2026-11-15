/// HG 网络层：edge 信封网关 + 原始字节拉取。
///
/// 上游站点（HGhubX 的线路）所有业务请求都不直接 GET 业务路径，
/// 而是 POST `{base}/api/edge/request` 一个信封：
/// `{method, path, body(base64), content_type}`，响应 `{status:1, data:…}`。
/// 这是从 HGhubX `src-tauri/src/net.rs` 的 `edge()` 移植的：
/// * 所有请求带桌面 Chrome UA（net.rs 的 `UA` 常量）；
/// * 防盗链靠 `Referer: {base}/` 请求头；
/// * 业务 POST 拒绝重定向（net.rs 的 edge_redirect_target：非 guest GET
///   的重定向一律报错），避免 Dart HttpClient 自动把信封 POST 降级成 GET。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:XL/modules/hg/hg_session.dart';

/// 固定线路（lines.rs 的 FIXED）。
const List<(String, String)> kHgFixedLines = [
  ('固定线路 1', 'https://huangguoai.com'),
  ('固定线路 2', 'https://huangguoai.ai'),
];

const String kHgDefaultBase = 'https://huangguoai.com';

/// net.rs 的 UA 常量：站点/CDN 对无 UA 或可疑 UA 的请求会拒绝。
const String kHgUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class HgNet {
  HgNet._();

  static String _base = kHgDefaultBase;
  static String get base => _base;

  static HttpClient? _client;

  /// API 失败观察者（autoLine 的 net observer 等价物）：
  /// edge 业务请求失败且像网络问题时回调，驱动自动线路检查。
  static void Function(bool networkish)? onApiFailure;

  static HttpClient _httpClient() {
    _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true
      ..userAgent = kHgUserAgent;
    return _client!;
  }

  /// 切换线路（会话跟随 origin 绑定，换线路后旧 token 不再使用）。
  static void setBase(String url) {
    final normalized = normalizeBase(url);
    if (normalized == null || normalized == _base) return;
    _base = normalized;
    _client?.close(force: true);
    _client = null;
  }

  /// 宽容规范化：补 https、去尾斜杠。不合格式返回 null。
  static String? normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final buffer = StringBuffer('${uri.scheme}://${uri.host}');
    if (uri.hasPort) buffer.write(':${uri.port}');
    return buffer.toString();
  }

  static String _tokenFor(String origin) {
    final s = HgStore.session;
    return s.loggedIn && s.origin == origin ? s.token : '';
  }

  /// edge 网关请求。成功返回 data 字段，业务失败抛 [HgApiError]。
  ///
  /// [baseOverride] 供线路探测对任意候选 origin 发起无凭证请求，
  /// 不影响当前线路（lines.rs 的 probe_hit 同款语义）。
  static Future<dynamic> edge(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authed = false,
    String? baseOverride,
  }) async {
    final origin = baseOverride ?? _base;
    var token = baseOverride == null ? _tokenFor(origin) : '';
    if (authed && token.isEmpty) {
      throw const HgApiError('请先登录');
    }
    final encoded = body == null
        ? ''
        : base64.encode(utf8.encode(jsonEncode(body)));
    final envelope = {
      'method': method,
      'path': path,
      'body': encoded,
      'content_type': body == null ? '' : 'application/json',
    };

    final url = '$origin/api/edge/request';
    // net.rs：edge 信封 POST 逐跳重建、拒绝降级。Dart 的 HttpClient 会把
    // 301/302/303 的 POST 自动改成 GET 跟随，导致信封丢失——这里关闭
    // 自动跟随，guest GET 自己跟一跳，其余直接报错。
    final request = await _httpClient()
        .postUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('Referer', '$origin/');
    if (token.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.write(jsonEncode(envelope));

    var response = await request.close().timeout(const Duration(seconds: 25));
    final isGuestGet =
        method.toUpperCase() == 'GET' && body == null && token.isEmpty;
    if (isGuestGet && response.statusCode >= 300 && response.statusCode < 400) {
      // guest GET 允许跟随重定向（一跳，仍走 edge 信封语义）。
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location != null && location.isNotEmpty) {
        final next = Uri.parse(url).resolve(location);
        final redirect = await _httpClient()
            .postUrl(next)
            .timeout(const Duration(seconds: 20));
        redirect.followRedirects = true;
        redirect.headers.set('Content-Type', 'application/json');
        redirect.headers.set('Accept', 'application/json');
        redirect.headers.set('Referer', '$origin/');
        redirect.write(jsonEncode(envelope));
        response = await redirect.close().timeout(const Duration(seconds: 25));
      }
    }
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode == 401 || response.statusCode == 403) {
      // token 过期：清掉本地会话，让上层引导重新登录。
      if (baseOverride == null) await HgStore.clearSession();
      throw const HgApiError('登录已过期，请重新登录', unauthorized: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (baseOverride == null) {
        onApiFailure?.call(response.statusCode >= 500 ||
            response.statusCode >= 400 ||
            text.isEmpty);
      }
      throw HgApiError(
        'HTTP ${response.statusCode}: ${_clip(text)}',
        statusCode: response.statusCode,
      );
    }
    if (text.trim().isEmpty) return null;

    dynamic value;
    try {
      value = jsonDecode(text);
    } catch (_) {
      if (baseOverride == null) onApiFailure?.call(true);
      throw HgApiError('接口返回异常: ${_clip(text)}');
    }
    if (value is Map && value['status'] == 1) {
      return value['data'];
    }
    final msg = value is Map && value['msg']?.toString().isNotEmpty == true
        ? value['msg'].toString()
        : '接口返回失败';
    if (baseOverride == null) onApiFailure?.call(true);
    throw HgApiError(msg);
  }

  /// 拉原始字节（封面 / m3u8 / 分片 / key），带 UA + Referer 防盗链头。
  static Future<(String? contentType, Uint8List bytes)> fetchBytes(
    String url, {
    String? refererBase,
  }) async {
    final referer = refererBase ?? _base;
    final request = await _httpClient()
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    request.headers.set('Referer', '$referer/');
    final response = await request.close().timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HgApiError('HTTP ${response.statusCode}');
    }
    final ctype = response.headers.value('content-type');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return (ctype, builder.takeBytes());
  }

  /// 发布页专用 GET（lines.rs 的 get_text）：带 UA 与宽 Accept，
  /// 拒绝跨源重定向，限制 512 KiB。返回文本。
  static Future<String> getPublishText(String raw) async {
    final target = Uri.parse(raw);
    final request = await _httpClient()
        .getUrl(target)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set('Accept', 'text/html,application/javascript');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode >= 300 && response.statusCode < 400) {
      // 发布页权威不允许跨源跳转（get_text 的 final_url 校验）。
      final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
      final resolved = target.resolve(location);
      if (resolved.origin != target.origin) {
        throw '发布页或发布脚本跳转到了非可信地址';
      }
      final redirect = await _httpClient()
          .getUrl(resolved)
          .timeout(const Duration(seconds: 8));
      redirect.followRedirects = true;
      redirect.headers.set('Accept', 'text/html,application/javascript');
      final rr = await redirect.close().timeout(const Duration(seconds: 8));
      return _readBounded(rr);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw 'HTTP ${response.statusCode}';
    }
    return _readBounded(response);
  }

  static Future<String> _readBounded(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    const max = 512 * 1024;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > max) throw '地址发布页或脚本超过 512 KiB 限制';
      builder.add(chunk);
    }
    try {
      return utf8.decode(builder.takeBytes());
    } catch (_) {
      throw '地址发布页或脚本不是有效 UTF-8';
    }
  }

  static String _clip(String s) =>
      s.length > 160 ? s.substring(0, 160) : s;
}

class HgApiError implements Exception {
  const HgApiError(this.message, {this.statusCode, this.unauthorized = false});

  final String message;
  final int? statusCode;
  final bool unauthorized;

  @override
  String toString() => message;
}
