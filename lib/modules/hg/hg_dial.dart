/// HG 媒体取流的 DNS 自愈（HGhubX `media_dns.rs` + `net.rs fetch_bytes`
/// 的 with_retry / network.dns_fallback 移植）。
///
/// 上游注释原文的问题：普通排序把 IPv4 排在前面；共享 IPv4 出口被上游
/// 接口限流时，请求会挂起或 502/503，而同一网络下 IPv6 一切正常。
/// 此外系统 DNS 被污染时，媒体域名会解析到假地址。
///
/// 策略（与上游一致）：
/// * 连接类失败（DNS/超时/传输层）→ 下一跳改用公共 DNS 解析
///   （阿里 DoH dns.alidns.com，自举 223.5.5.5 / 223.6.6.6，只取公网 A 记录）；
/// * 公网 DNS 成功 → 记住该域名 30 秒，期间优先走公网 DNS；
/// * 公网 DNS 失败 → 忘掉，回退系统 DNS；
/// * 最多 3 次尝试，间隔 350ms × n；
/// * 直连 IP 需要手动 Host 头 + 证书校验（subject 必须覆盖目标域名）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:XL/modules/hg/hg_diag.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_policy.dart';

class HgDial {
  HgDial._();

  /* ── Routes（media_dns.rs，30 秒 TTL） ── */

  static final Map<String, DateTime> _publicDns = {};

  static bool _prefersPublic(String host) {
    final exp = _publicDns[host];
    return exp != null && DateTime.now().isBefore(exp);
  }

  static void _remember(String host) {
    _publicDns.removeWhere((_, exp) => DateTime.now().isAfter(exp));
    if (_publicDns.length >= 64) _publicDns.clear();
    _publicDns[host] = DateTime.now().add(const Duration(seconds: 30));
  }

  static void _forget(String host) {
    _publicDns.remove(host);
  }

  /* ── eligible（media_dns.rs）：只对 https 域名的连接类故障自愈 ── */

  static bool _eligible(Uri target, String error) {
    if (target.scheme != 'https') return false;
    if (InternetAddress.tryParse(target.host) != null) return false;
    return _retryable(error);
  }

  static bool _retryable(String error) {
    return error.contains('SocketException') ||
        error.contains('TimeoutException') ||
        error.contains('HandshakeException') ||
        error.contains('DNS 解析') ||
        error.contains('连接超时') ||
        error.contains('Connection closed') ||
        error.contains('Connection reset');
  }

  /* ── fetch_bytes 主入口 ── */

  static Future<(String? contentType, Uint8List bytes)> fetch(
    String url,
    String refererBase, {
    int attempts = 3,
  }) async {
    final target = Uri.tryParse(url);
    final host = target?.host ?? '';
    var publicDns = _prefersPublic(host);
    var lastError = 'network error';

    for (var attempt = 0; attempt < attempts; attempt++) {
      final started = DateTime.now();
      try {
        final result = publicDns
            ? await _fetchPublicDns(target!, refererBase)
            : await _fetchSystemDns(target!, refererBase);
        if (publicDns) _remember(host);
        HgDiag.traceVerbose('network.end', {
          'resource': _resourceId(url),
          'attempt': attempt + 1,
          'public_dns': publicDns,
          'ms': DateTime.now().difference(started).inMilliseconds,
          'bytes': result.$2.length,
        });
        return result;
      } catch (e) {
        lastError = e.toString();
        if (publicDns) _forget(host);
        HgDiag.traceVerbose('network.end', {
          'resource': _resourceId(url),
          'attempt': attempt + 1,
          'public_dns': publicDns,
          'ms': DateTime.now().difference(started).inMilliseconds,
          'error_kind': _errorKind(lastError),
        });
        if (target != null && _eligible(target, lastError)) {
          publicDns = !publicDns;
          HgDiag.traceVerbose('network.dns_fallback', {
            'resource': _resourceId(url),
            'public_dns': publicDns,
          });
        }
        // 非 HTTP 状态类错误且可重试才继续；状态码错误立即抛。
        if (!_retryable(lastError) || attempt == attempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw HgApiError(lastError);
  }

  /// 资源标识（playback_log.resource_id）：只留路径，不带查询串。
  static String _resourceId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segs = uri.pathSegments;
    return segs.isEmpty ? uri.path : segs.last;
  }

  static String _errorKind(String error) {
    if (error.contains('SocketException')) return 'transport_error';
    if (error.contains('TimeoutException') || error.contains('连接超时')) {
      return 'timeout';
    }
    if (error.contains('HandshakeException')) return 'tls_error';
    if (error.contains('DNS')) return 'dns_error';
    if (error.startsWith('HTTP ')) return 'http_error';
    return 'other';
  }

  /* ── 系统 DNS 直连（守卫 + 手动重定向） ── */

  static Future<(String?, Uint8List)> _fetchSystemDns(
    Uri target,
    String refererBase,
  ) async {
    final guard = hgCheckTarget(target);
    if (guard != null) throw HgApiError(guard);
    final client = _newClient();
    try {
      var current = target;
      for (var hop = 0; hop < 5; hop++) {
        final response = await _open(client, current, refererBase);
        // 读完正文/排水重定向后才轮换下一跳；client 在 body 消费完才关——
        // 提前 close(force) 会掐断尚未读取的响应流。
        final next = await _redirectOrBody(response, current, refererBase);
        if (next.$1) return next.$2!;
        current = next.$3!;
      }
      throw const HgApiError('重定向次数过多');
    } finally {
      client.close(force: true);
    }
  }

  /* ── 公共 DNS（阿里 DoH）解析 + IP 直连 ── */

  static Future<(String?, Uint8List)> _fetchPublicDns(
    Uri target,
    String refererBase,
  ) async {
    final addrs = await _dohResolve(target.host);
    // 逐个地址尝试（第一个失败换下一个）。
    Object? last;
    for (final addr in addrs.take(3)) {
      final client = _newClient();
      try {
        final response = await _open(client, target, refererBase, via: addr);
        final next = await _redirectOrBody(response, target, refererBase);
        if (next.$1) return next.$2!;
        // 重定向换源：回退系统 DNS 语义，从新地址重新走常规路径。
        return await _fetchSystemDns(next.$3!, refererBase);
      } catch (e) {
        last = e;
        continue;
      } finally {
        client.close(force: true);
      }
    }
    throw last ?? HgApiError('备用 DNS 没有可用地址');
  }

  /// 阿里 DoH（media_dns.rs 的 resolve）：自举 IP 直连，
  /// 只取公网 A 记录（拒绝内网/保留/FakeIP）。
  static Future<List<InternetAddress>> _dohResolve(String host) async {
    Object? last;
    for (final boot in const ['223.5.5.5', '223.6.6.6']) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..userAgent = kHgUserAgent
        ..autoUncompress = true
        // 自举 IP 直连无 SNI：证书必须真实覆盖 dns.alidns.com。
        ..badCertificateCallback = (cert, h, p) =>
            cert.subject.contains('dns.alidns.com');
      try {
        final request = await client
            .getUrl(Uri.parse('https://$boot/resolve?name=$host&type=A'))
            .timeout(const Duration(seconds: 4));
        request.headers.set(HttpHeaders.hostHeader, 'dns.alidns.com');
        request.headers.set('Accept', 'application/dns-json');
        final response =
            await request.close().timeout(const Duration(seconds: 4));
        if (response.statusCode != 200) {
          last = '备用 DNS 服务不可用';
          continue;
        }
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 4));
        if (body.length > 16 * 1024) throw '备用 DNS 响应过大';
        final value = jsonDecode(body) as Map;
        if (value['Status'] != 0) throw '备用 DNS 解析失败';
        final records = value['Answer'] as List?;
        if (records == null || records.isEmpty) {
          throw '备用 DNS 没有可用地址';
        }
        final out = <InternetAddress>{};
        for (final record in records) {
          if (record is! Map || record['type'] != 1) continue;
          final ip = InternetAddress.tryParse('${record['data']}');
          if (ip == null) throw '备用 DNS 地址无效';
          if (!hgAllowedIp(ip)) throw '备用 DNS 返回内网或保留地址';
          out.add(ip);
        }
        if (out.isEmpty || out.length > 32) {
          throw '备用 DNS 没有可用地址';
        }
        return out.toList();
      } catch (e) {
        last = e;
      } finally {
        client.close(force: true);
      }
    }
    throw last ?? '备用 DNS 解析失败';
  }

  /* ── 底层请求 ── */

  static HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = kHgUserAgent
    ..autoUncompress = true;

  static Future<HttpClientResponse> _open(
    HttpClient client,
    Uri current,
    String refererBase, {
    InternetAddress? via,
  }) async {
    var url = current;
    if (via != null) {
      // IP 直连：URL host 换成地址字面量，Host 头保留原域名；
      // 无 SNI 时证书校验按目标域名的 subject 人工确认（IP 直连证书
      // 校验失败才走该回调，正常域名证书不受影响）。
      client.badCertificateCallback = (cert, h, p) =>
          cert.subject.contains(current.host);
      url = current.replace(host: via.address);
    }
    final request = await client
        .getUrl(url)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set('Referer', '$refererBase/');
    if (via != null) {
      request.headers.set(HttpHeaders.hostHeader, current.host);
    }
    return await request.close().timeout(const Duration(seconds: 25));
  }

  /// 处理响应：(true, body, null) = 已拿到正文；(false, _, next) = 需要跟随重定向。
  static Future<(bool, (String?, Uint8List)?, Uri?)> _redirectOrBody(
    HttpClientResponse response,
    Uri current,
    String refererBase,
  ) async {
    final status = response.statusCode;
    if (status >= 300 && status < 400) {
      final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
      await response.drain<void>().catchError((_) {});
      if (location.isEmpty) throw const HgApiError('重定向缺少 Location');
      final next = current.resolve(location);
      final guard = hgCheckRedirect(current, next);
      if (guard != null) throw HgApiError(guard);
      return (false, null, next);
    }
    if (status < 200 || status >= 300) {
      await HgDiag.trace('media.http_error', {
        'resource': _resourceId(current.toString()),
        'status': status,
      });
      throw HgApiError('HTTP $status');
    }
    final ctype = response.headers.value('content-type');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return (true, (ctype, builder.takeBytes()), null);
  }
}
