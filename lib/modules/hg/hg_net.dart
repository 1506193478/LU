/// HG 网络层：edge 信封网关 + 原始字节拉取。
///
/// 上游站点（HGhubX 的线路）所有业务请求都不直接 GET 业务路径，
/// 而是 POST `{base}/api/edge/request` 一个信封：
/// `{method, path, body(base64), content_type}`，响应 `{status:1, data:…}`。
/// 这是从 HGhubX `src-tauri/src/net.rs` 的 `edge()` 移植的，防盗链
/// 靠 `Referer: {base}/` 请求头。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:XL/modules/hg/hg_session.dart';

/// 固定线路（lines.rs 的 FIXED）。一期只写死这两条 + 默认线路。
const List<(String, String)> kHgFixedLines = [
  ('固定线路 1', 'https://huangguoai.com'),
  ('固定线路 2', 'https://huangguoai.ai'),
];

const String kHgDefaultBase = 'https://huangguoai.com';

class HgNet {
  HgNet._();

  static String _base = kHgDefaultBase;
  static String get base => _base;

  static HttpClient? _client;

  static HttpClient _httpClient() {
    _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true;
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
  static Future<dynamic> edge(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authed = false,
  }) async {
    final origin = _base;
    var token = _tokenFor(origin);
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
    final request = await _httpClient()
        .postUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('Referer', '$origin/');
    if (token.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.write(jsonEncode(envelope));

    final response = await request.close().timeout(const Duration(seconds: 25));
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode == 401 || response.statusCode == 403) {
      // token 过期：清掉本地会话，让上层引导重新登录。
      await HgStore.clearSession();
      throw const HgApiError('登录已过期，请重新登录', unauthorized: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
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
      throw HgApiError('接口返回异常: ${_clip(text)}');
    }
    if (value is Map && value['status'] == 1) {
      return value['data'];
    }
    final msg = value is Map && value['msg']?.toString().isNotEmpty == true
        ? value['msg'].toString()
        : '接口返回失败';
    throw HgApiError(msg);
  }

  /// 拉原始字节（封面 / m3u8 / 分片 / key），带 Referer 防盗链头。
  static Future<(String? contentType, Uint8List bytes)> fetchBytes(
    String url,
  ) async {
    final request = await _httpClient()
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    request.headers.set('Referer', '$_base/');
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
