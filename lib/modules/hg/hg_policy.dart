/// HG 网络安全策略（HGhubX `src-tauri/src/network_policy.rs` 移植）。
///
/// 严格安全模式（默认开启，可在 设置 → 网络 关闭）：
/// * 目标只允许不带认证信息的 HTTP(S) 地址；
/// * 拒绝本机/内网主机名（localhost、*.local、home.arpa 等）；
/// * DNS 解析结果逐个校验——私网/回环/保留地址一律拒绝，
///   唯一例外是 FakeIP 198.18.0.0/15（Clash/Surge TUN 明确放行）；
/// * 禁止 HTTPS 降级到 HTTP 的重定向。
///
/// 关闭后仅保留「应用内部协议主机名」的最小防线，其余全部放行——
/// 与上游 `--no-strict` 兼容模式语义一致。特殊代理/DNS 环境导致
/// 正文打不开时，关闭严格模式即可恢复。
library;

import 'dart:async';
import 'dart:io';

import 'package:XL/modules/hg/hg_session.dart';

class HgPolicyError implements Exception {
  const HgPolicyError(this.message);
  final String message;

  @override
  String toString() => message;
}

bool get _strict => HgStore.prefs.strictSecurity;

/// IP 分类（net.rs 的 ip_kind）：诊断与拦截共用。
String hgIpKind(InternetAddress addr) {
  final raw = addr.address;
  final ip = addr.type == InternetAddressType.IPv6 && raw.contains('%')
      ? raw.substring(0, raw.indexOf('%'))
      : raw;
  final v4 = addr.type == InternetAddressType.IPv4;
  if (ip == '::1' || ip == '::') return v4 ? 'reserved' : 'loopback';
  if (ip.startsWith('127.')) return 'loopback';
  if (ip.startsWith('198.18.') || ip.startsWith('198.19.')) return 'fake_ip';
  if (ip.startsWith('10.')) return 'private';
  if (ip.startsWith('192.168.')) return 'private';
  if (v4 && ip.startsWith('172.')) {
    final b = int.tryParse(ip.split('.')[1]) ?? 0;
    if (b >= 16 && b <= 31) return 'private';
  }
  if (ip.startsWith('169.254.')) return 'link_local';
  if (v4 && ip.startsWith('100.')) {
    final b = int.tryParse(ip.split('.')[1]) ?? 0;
    if (b >= 64 && b <= 127) return 'private';
  }
  if (v4 && (ip.startsWith('224.') || ip.startsWith('240.'))) return 'reserved';
  if (v4 && (ip.startsWith('0.') || ip.startsWith('192.0.') ||
      ip.startsWith('198.51.') || ip.startsWith('203.0.'))) {
    return 'reserved';
  }
  if (addr.type == InternetAddressType.IPv6) {
    final lower = ip.toLowerCase();
    if (lower.startsWith('fc') || lower.startsWith('fd')) return 'private';
    if (lower.startsWith('fe8') || lower.startsWith('fe9') ||
        lower.startsWith('fea') || lower.startsWith('feb')) {
      return 'link_local';
    }
    if (lower.startsWith('ff')) return 'multicast';
    // NAT64/Teredo/6to4 等可封装 IPv4 的过渡段按保留处理。
    if (lower.startsWith('64:ff9b') || lower.startsWith('2002:') ||
        lower.startsWith('2001:0')) {
      return 'reserved';
    }
    if (lower.startsWith('2001:db8') || lower.startsWith('3fff')) {
      return 'reserved';
    }
    if (lower.startsWith('2001:')) {
      final parts = lower.split(':');
      final second = int.tryParse(parts[1], radix: 16) ?? 0x10000;
      if (second < 0x0200 || second == 0x0db8) return 'reserved';
    }
  }
  return 'public';
}

/// network_policy.rs 的 allowed_ip：严格模式下放行的地址检查。
bool hgAllowedIp(InternetAddress addr) => hgIpKind(addr) == 'public';

/// 本机/内网主机名后缀（严格模式拒绝；内部协议主机名任何模式都拒绝）。
const List<String> _internalHostSuffix = [
  'localhost',
  'local',
  'internal',
  'home.arpa',
];

/// network_policy.rs 的 parse_target_with_mode：请求前的目标校验。
/// 返回错误消息（null = 通过）。
String? hgCheckTarget(Uri uri, {bool? strict}) {
  final s = strict ?? _strict;
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return '目标只允许 HTTP(S) 地址';
  }
  if (uri.userInfo.isNotEmpty) {
    return '目标不允许携带账号密码';
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return '目标缺少主机名';
  if (host == 'tauri.localhost' || host == 'hg.localhost' ||
      host == 'ipc.localhost') {
    return '禁止访问应用内部协议主机名';
  }
  if (!s) return null;
  for (final suffix in _internalHostSuffix) {
    if (host == suffix || host.endsWith('.$suffix')) {
      return '禁止访问本机或内网主机名';
    }
  }
  // 字面量 IP 目标在严格模式下直接校验。
  final addr = InternetAddress.tryParse(host);
  if (addr != null && !hgAllowedIp(addr)) {
    return '禁止访问内网、回环或保留地址（仅放行 FakeIP 198.18.0.0/15）';
  }
  return null;
}

/// network_policy.rs 的 resolve_target：域名解析 + 严格模式地址校验。
/// 非严格模式也解析（供诊断/日志），但只在校验失败时抛错。
Future<List<InternetAddress>> hgResolve(Uri uri, {bool? strict}) async {
  final s = strict ?? _strict;
  final host = uri.host;
  List<InternetAddress> addrs;
  try {
    addrs = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    throw const HgPolicyError('DNS 解析超时');
  } catch (_) {
    throw const HgPolicyError('DNS 解析失败');
  }
  if (addrs.isEmpty) throw const HgPolicyError('目标没有可用的 DNS 地址');
  if (s) {
    // 混合公私网答案整体拒绝（不能回退到私网地址）。
    for (final addr in addrs) {
      if (!hgAllowedIp(addr)) {
        throw HgPolicyError(
            'DNS 返回了非公网地址 ${addr.address}（严格安全模式拦截；'
            '若你使用特殊代理/DNS，可在设置中关闭严格安全模式）');
      }
    }
  }
  return addrs;
}

/// network_policy.rs 的 redirect_target_with_mode：重定向逐跳校验。
/// 返回错误消息（null = 允许）。
String? hgCheckRedirect(Uri from, Uri to, {bool? strict}) {
  final s = strict ?? _strict;
  final base = hgCheckTarget(to, strict: s);
  if (base != null) return base;
  if (s && from.scheme == 'https' && to.scheme != 'https') {
    return '禁止 HTTPS 降级重定向';
  }
  return null;
}
