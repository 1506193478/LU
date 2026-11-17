/// HG 播放诊断日志 + 网络诊断（HGhubX `playback_log.rs` + `net.rs diagnose`
/// + `src/netDiagReport.ts` 的移植）。
///
/// * 播放日志：版本/平台/当前线路/播放失败原因**始终记录**（追加到
///   应用文档目录 playback.log）；设置开关只放开拖动与缓冲等细粒度事件。
/// * 网络诊断：DNS / TCP / HTTP 三层快照 + 结论（verdict），一键复制
///   成分段可读报告，直接贴给维护者定位「打不开」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:path_provider/path_provider.dart';

import 'package:XL/modules/hg/hg_dial.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_policy.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/request/config/api_endpoints.dart';

class HgDiag {
  HgDiag._();

  static File? _file;
  static bool _ready = false;
  static final List<String> _queue = [];
  static Timer? _flushTimer;
  static Future<void>? _writing;

  static String? get path => _file?.path;

  /// 启动绑定：文档目录 playback.log。
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}playback.log');
      _ready = true;
      await trace('app.start', {
        'version': ApiEndpoints.version,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'line': HgNet.base,
        'strict': HgStore.prefs.strictSecurity,
        'proxy_mode': HgStore.prefs.proxyMode,
        'auto_line': HgStore.prefs.autoLine,
      });
    } catch (_) {
      _ready = false;
    }
  }

  /// 始终记录的通道（失败/线路/诊断）。verbose 事件走 [traceVerbose]，
  /// 只在「播放诊断日志」开关打开时落盘。
  static Future<void> trace(String event, Map<String, dynamic> data) =>
      _write(event, data);

  /// verbose 通道（拖动/缓冲细节）：开关关闭时丢弃。
  static void traceVerbose(String event, Map<String, dynamic> data) {
    if (!HgStore.prefs.playbackLog) return;
    _write(event, data);
  }

  static Future<void> _write(String event, Map<String, dynamic> data) async {
    if (!_ready) return;
    final entry = jsonEncode({
      'event': event,
      ...data,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    _queue.add(entry);
    _flushTimer ??= Timer(const Duration(milliseconds: 300), _flush);
  }

  static Future<void> _flush() async {
    _flushTimer = null;
    if (_queue.isEmpty) return;
    final batch = _queue.toList();
    _queue.clear();
    final text = batch.map((l) => '$l\n').join();
    _writing = _writing?.then<void>((_) async {
          await _file?.writeAsString(text,
              mode: FileMode.append, flush: false);
        }).catchError((_) {}) ??
        Future<void>.value();
    await _writing;
  }

  static Future<String> read() async {
    await _flush();
    if (_file == null) return '';
    try {
      final stat = await _file!.length();
      if (stat > 256 * 1024) {
        // 太大只取尾部 256 KiB。
        final raf = await _file!.open();
        try {
          await raf.setPosition(stat - 256 * 1024);
          final bytes = await raf.read(256 * 1024);
          return utf8.decode(bytes, allowMalformed: true);
        } finally {
          await raf.close();
        }
      }
      return await _file!.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      await _file?.writeAsString('', mode: FileMode.write);
    } catch (_) {}
  }
}


/* ═════════════════════════ 网络诊断 ═════════════════════════ */

class HgNetDiagResult {
  const HgNetDiagResult(this.report, this.shortVerdict, this.raw);
  final String report;
  final String shortVerdict;
  final Map<String, dynamic> raw;
}

class HgNetDiag {
  HgNetDiag._();

  static const _verdictText = {
    'ok': '连通正常',
    'ok_proxy': '代理/TUN 接管中，连接正常',
    'fake_ip': '被代理 / TUN 接管（fake-ip）',
    'dns_fail': 'DNS 解析失败',
    'dns_false_alarm': 'DNS 探测异常，但实际可通',
    'dns_hijack': 'DNS 被劫持到内网 / 保留地址',
    'tcp_timeout': '直连 TCP 探测超时',
    'tcp_refused': '直连 TCP 探测被拒',
    'tls_fail': 'TLS 握手失败',
    'proxy_fail': '代理请求失败',
    'http_fail': 'HTTP 请求失败',
    'http_status': '服务端返回错误状态码',
    'unknown': '信息不足',
  };

  /// 诊断当前线路（net.rs 的 diagnose）。[strict] 传入 null 表示跟随设置。
  static Future<HgNetDiagResult> run() async {
    final base = HgNet.base;
    final host = Uri.tryParse(base)?.host ?? '';
    final strict = HgStore.prefs.strictSecurity;

    /* ── DNS ── */
    final dnsStarted = DateTime.now();
    Map<String, dynamic> dns;
    List<InternetAddress> addrs = const [];
    if (host.isEmpty) {
      dns = {'error': '当前线路没有主机名'};
    } else {
      try {
        addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 6));
        final ips = addrs.map((a) => a.address).toSet().toList()..sort();
        final kinds = addrs.map(hgIpKind).toSet().toList()..sort();
        final suspicious = [
          for (final a in addrs)
            if (hgIpKind(a) != 'public') a.address,
        ];
        dns = {
          'ms': DateTime.now().difference(dnsStarted).inMilliseconds,
          'count': ips.length,
          'kinds': kinds,
          'suspicious': suspicious,
          'has_fake_ip': kinds.contains('fake_ip'),
        };
      } on TimeoutException {
        dns = {'error': 'DNS 解析超时', 'timeout': true, 'ms': 6000};
      } catch (e) {
        dns = {
          'error': 'DNS 解析失败',
          'detail': e.toString(),
          'ms': DateTime.now().difference(dnsStarted).inMilliseconds,
        };
      }
    }

    /* ── TCP（独立 socket，绕过应用代理） ── */
    Map<String, dynamic> tcp;
    if (addrs.isEmpty) {
      tcp = {'skipped': true, 'reason': '没有可用的解析结果'};
    } else {
      final target = addrs.first;
      final started = DateTime.now();
      try {
        final socket = await Socket.connect(
          target,
          443,
          timeout: const Duration(seconds: 5),
        );
        socket.destroy();
        tcp = {
          'ok': true,
          'family': target.type == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4',
          'addr': '${target.address}:443',
          'ms': DateTime.now().difference(started).inMilliseconds,
        };
      } on TimeoutException {
        tcp = {
          'ok': false,
          'timeout': true,
          'family': target.type == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4',
          'addr': '${target.address}:443',
          'ms': 5000,
        };
      } catch (e) {
        tcp = {
          'ok': false,
          'family': target.type == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4',
          'addr': '${target.address}:443',
          'error': e.toString(),
          'ms': DateTime.now().difference(started).inMilliseconds,
        };
      }
    }

    /* ── HTTP（走应用网络层，与真实请求同路径） ── */
    final httpStarted = DateTime.now();
    Map<String, dynamic> http;
    final proxyConfigured = HgStore.prefs.proxyMode == 'custom';
    try {
      final (ctype, bytes) = await HgDial.fetch(
        base,
        base,
        attempts: 1,
      );
      http = {
        'status': 200,
        'proxy_configured': proxyConfigured,
        'content_type': ctype,
        'bytes': bytes.length,
        'ms': DateTime.now().difference(httpStarted).inMilliseconds,
      };
    } catch (e) {
      http = {
        'error': e.toString(),
        'proxy_configured': proxyConfigured,
        'ms': DateTime.now().difference(httpStarted).inMilliseconds,
      };
    }

    /* ── 环境 ── */
    final env = Platform.environment;
    String? redact(String? v) {
      if (v == null) return null;
      final match = RegExp(r'^(https?|socks5h?)://([^/@]+)@').firstMatch(v);
      if (match != null) {
        return v.replaceRange(match.start + v.indexOf('://') + 3,
            match.end, '${match.group(2)?.split(':')[0]}:***@');
      }
      return v;
    }

    final envReport = <String, dynamic>{
      'HTTP_PROXY': redact(env['HTTP_PROXY']),
      'HTTPS_PROXY': redact(env['HTTPS_PROXY']),
      'ALL_PROXY': redact(env['ALL_PROXY']),
      'NO_PROXY': env['NO_PROXY'] != null ? '[已配置，列表已隐藏]' : null,
      'system_proxy_mobile':
          Platform.isAndroid || Platform.isIOS ? '移动端由 VPN/TUN 接管，无系统代理环境变量' : null,
      'app_proxy_mode': HgStore.prefs.proxyMode,
      'app_proxy': HgStore.prefs.proxyMode == 'custom'
          ? redact(HgStore.prefs.proxyUrl)
          : null,
      'strict_security': strict,
    };
    envReport.removeWhere((_, v) => v == null);

    /* ── 结论（verdict 移植） ── */
    final (code, summary, advice) = _verdict(dns, tcp, http);

    final raw = <String, dynamic>{
      'verdict': code,
      'summary': summary,
      'advice': advice,
      'base': base,
      'host': host,
      'dns': dns,
      'tcp': tcp,
      'http': http,
      'env': envReport,
      'runtime': {
        'os': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'app': ApiEndpoints.version,
      },
    };
    await HgDiag.trace('net.diag', {
      'verdict': code,
      'host': host,
      'strict': strict,
    });
    return HgNetDiagResult(formatNetDiag(raw), '$code · $summary', raw);
  }

  static (String, String, List<String>) _verdict(
    Map<String, dynamic> dns,
    Map<String, dynamic> tcp,
    Map<String, dynamic> http,
  ) {
    final dnsErr = dns['error'] as String?;
    final fake = dns['has_fake_ip'] == true;
    final kinds = (dns['kinds'] as List?)?.cast<String>() ?? const [];
    final status = http['status'] as int?;
    final httpErr = (http['error'] as String?) ?? '';
    final tcpOk = tcp['ok'] as bool?;
    final proxyConfigured = http['proxy_configured'] == true;

    // 实际 HTTP 响应优先（TCP 探测可能走不同路径）。
    if (status != null && status >= 200 && status < 400) {
      if (dnsErr != null) {
        return ('dns_false_alarm', 'DNS 探测异常，但应用 HTTP 请求已成功（HTTP $status）', []);
      }
      if (fake) {
        return ('ok_proxy', 'DNS 由代理/TUN 接管，应用 HTTP 请求正常（HTTP $status）', []);
      }
      if (proxyConfigured || tcpOk == false) {
        return ('ok_proxy', '应用 HTTP 请求已成功（HTTP $status）', []);
      }
      if (kinds.any((k) => k == 'loopback' || k == 'private' || k == 'reserved')) {
        return (
          'dns_hijack',
          'DNS 返回了非公网地址，但应用 HTTP 请求已成功（HTTP $status）',
          ['检查本机 DNS、VPN/TUN 和代理设置是否符合预期'],
        );
      }
      return ('ok', '连通正常（HTTP $status），线路可用', []);
    }
    if (status != null) {
      return (
        'http_status',
        '应用 HTTP 请求收到服务端状态码 $status',
        ['确认账号或内容权限；若持续出现，请稍后重试'],
      );
    }
    if (dnsErr != null && httpErr.isEmpty) {
      if (proxyConfigured) return ('proxy_fail', 'DNS 解析失败，且未配置应用代理时无法解析', []);
      return ('dns_fail', 'DNS 解析失败：$dnsErr', [
        '若你使用 VPN/TUN（Clash/Surge 等），先开启它们再试',
        '若没有代理且在大陆网络，固定线路可能需要镜像线路（设置 → 网络 → 播放源）',
      ]);
    }
    if (httpErr.contains('SocketException') || httpErr.contains('Connection')) {
      if (tcpOk == false && (tcp['timeout'] == true)) {
        return ('tcp_timeout', '直连 TCP 探测超时，HTTP 请求也失败', [
          '该线路在当前网络可能被阻断；尝试镜像线路或开启代理',
        ]);
      }
      if (tcpOk == false) {
        return ('tcp_refused', '直连 TCP 探测被拒，HTTP 请求也失败', [
          '该线路在当前网络不可达；尝试镜像线路或开启代理',
        ]);
      }
      return ('http_fail', 'HTTP 请求失败：$httpErr', ['尝试镜像线路或开启代理']);
    }
    if (httpErr.isNotEmpty) {
      return ('http_fail', 'HTTP 请求失败：$httpErr', [
        '尝试镜像线路；若你使用特殊代理，可尝试关闭严格安全模式',
      ]);
    }
    return ('unknown', '信息不足', ['开启播放诊断日志后复现问题，再复制日志反馈']);
  }

  /// 分段可读报告（netDiagReport.ts 移植）。
  static String formatNetDiag(Map<String, dynamic> raw) {
    final dns = (raw['dns'] as Map?)?.cast<String, dynamic>() ?? {};
    final tcp = (raw['tcp'] as Map?)?.cast<String, dynamic>() ?? {};
    final http = (raw['http'] as Map?)?.cast<String, dynamic>() ?? {};
    final env = (raw['env'] as Map?)?.cast<String, dynamic>() ?? {};
    final rt = (raw['runtime'] as Map?)?.cast<String, dynamic>() ?? {};
    final verdict = (raw['verdict'] as String?) ?? 'unknown';
    final summary = (raw['summary'] as String?) ?? '';
    final lines = <String>[];

    final when = DateTime.now().toString().substring(0, 19);
    lines.add('【LU · HG 短剧 网络诊断】$when');
    lines.add('');
    lines.add('结论：${summary.isEmpty ? (_verdictText[verdict] ?? verdict) : summary}');
    lines.add('代码：$verdict（${_verdictText[verdict] ?? '未归类'}）');
    lines.add('');

    lines.add('── 运行环境 ──────────────────────');
    lines.add('平台      ${rt['os'] ?? '-'}');
    lines.add('版本      ${rt['app'] ?? '-'}');
    lines.add('线路      ${raw['base'] ?? '-'}');
    lines.add('主机      ${raw['host'] ?? '-'}');
    lines.add('');

    lines.add('── DNS ───────────────────────────');
    final dnsError = dns['error'] as String?;
    if (dnsError != null) {
      lines.add(
          '状态      失败 · $dnsError${dns['timeout'] == true ? '（超时 6s）' : ' · ${dns['ms'] ?? '?'}ms'}');
      if (dns['detail'] != null) lines.add('原因      ${dns['detail']}');
    } else {
      final kinds = (dns['kinds'] as List?)?.join(', ') ?? '-';
      lines.add('状态      ${dns['ms'] ?? '?'}ms · ${dns['count'] ?? 0} 条记录');
      lines.add('类型      $kinds');
      final suspicious = (dns['suspicious'] as List?)?.join(', ');
      if (suspicious?.isNotEmpty == true) {
        lines.add('可疑地址  $suspicious');
      }
      if (dns['has_fake_ip'] == true) {
        lines.add('判定      fake-ip：DNS 被 Clash / Surge 等 TUN 接管');
      }
    }
    lines.add('');

    lines.add('── TCP ───────────────────────────');
    if (tcp['skipped'] == true) {
      lines.add('状态      跳过 · ${tcp['reason'] ?? '无解析结果'}');
    } else {
      final ok = tcp['ok'] == true;
      final state = ok ? '可连接' : (tcp['timeout'] == true ? '超时（无响应）' : '失败');
      final family = (tcp['family'] as String?) ?? '';
      lines.add('状态      直连探测 · $family · $state · ${tcp['ms'] ?? '?'}ms');
      if (tcp['addr'] != null) lines.add('目标      ${tcp['addr']}');
      if (tcp['error'] != null) lines.add('错误      ${tcp['error']}');
    }
    lines.add('');

    lines.add('── HTTP ──────────────────────────');
    final status = http['status'] as int?;
    if (status != null) {
      lines.add('状态      $status · ${http['ms'] ?? '?'}ms');
    } else {
      lines.add('状态      失败 · ${http['ms'] ?? '?'}ms');
    }
    lines.add(
        '代理路径  ${http['proxy_configured'] == true ? '检测到应用 HTTP 代理配置' : '未检测到应用 HTTP 代理配置（VPN/TUN 仍可能接管）'}');
    if (http['error'] != null) lines.add('错误      ${http['error']}');
    lines.add('');

    if (env['app_proxy_mode'] != null) {
      final labels = {'system': '跟随系统', 'custom': '自定义代理', 'off': '直连'};
      lines.add('── 应用代理 ──────────────────────');
      lines.add('模式      ${labels[env['app_proxy_mode']] ?? env['app_proxy_mode']}');
      if (env['app_proxy'] != null) lines.add('出口      ${env['app_proxy']}');
      lines.add('');
    }

    lines.add('── 系统代理 / 环境 ────────────────');
    final envKeys = env.keys.toList()..sort();
    if (envKeys.isEmpty) {
      lines.add('无相关环境变量');
    } else {
      lines.add(envKeys.map((k) => '$k=${env[k] ?? '-'}').join('  |  '));
    }
    lines.add('');

    final advice = (raw['advice'] as List?)?.cast<String>() ?? [];
    if (advice.isNotEmpty) {
      lines.add('── 建议 ──────────────────────────');
      for (var i = 0; i < advice.length; i++) {
        lines.add('${i + 1}. ${advice[i]}');
      }
      lines.add('');
    }

    lines.add('── 原始数据（JSON）───────────────');
    lines.add(const JsonEncoder.withIndent('  ').convert(raw));
    return lines.join('\n');
  }
}
