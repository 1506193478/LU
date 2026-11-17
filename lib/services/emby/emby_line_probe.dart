/// Emby 线路延迟探测。
///
/// 胶囊面板 / 备用线路页要显示每条线路的实时状态：`1.2 s`、`超时`。
/// 探的是 Emby 的公开接口 `/System/Info/Public`（不需要 token），
/// 拿到响应头就算通，整体耗时即延迟。
library;

import 'dart:async';
import 'dart:io';

class EmbyLineProbe {
  EmbyLineProbe._();

  /// 最近一次探测结果：base url → 毫秒（null = 超时/不可达）。
  static final Map<String, int?> results = <String, int?>{};

  /// 探测单条线路。返回毫秒数；超时/不可达返回 null。
  static Future<int?> probe(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final raw = baseUrl.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    final client = HttpClient()
      ..connectionTimeout = timeout
      // 自签证书的 Emby 很常见，探测只为测通，不校验。
      ..badCertificateCallback = (_, __, ___) => true;
    final sw = Stopwatch()..start();
    try {
      final req = await client
          .getUrl(uri.resolve('System/Info/Public'))
          .timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>().timeout(timeout);
      sw.stop();
      final ok = resp.statusCode < 500;
      return ok ? sw.elapsedMilliseconds : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 并发探测多条线路。结果写进 [results]。
  static Future<Map<String, int?>> probeAll(
    List<String> urls, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final unique = <String>{};
    for (final u in urls) {
      final t = u.trim();
      if (t.isNotEmpty) unique.add(t);
    }
    await Future.wait([
      for (final u in unique)
        probe(u, timeout: timeout).then((ms) => results[u] = ms),
    ]);
    return {
      for (final u in unique) u: results[u],
    };
  }

  /// 面板上展示的文案：`1.2 s` / `320 ms` / `超时`。
  static String label(int? ms) {
    if (ms == null) return '超时';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)} s';
    return '$ms ms';
  }
}
