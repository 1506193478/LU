/// HG 线路层：镜像发布页解析 + 探测 + 自动选线。
///
/// 从 HGhubX `src-tauri/src/lines.rs` + `src/autoLine.ts` 移植：
///
/// * 固定线路两条（FIXED）；真实可用镜像由官方地址发布页下发；
/// * 发布页解析只取**字面量** `var/let/const urls = [...]` 与
///   `subdomains = [...]`，注释/字符串/模板/正则里的假声明一律忽略
///   （fail-closed），远程 JS 永不执行；
/// * 探测：对候选 origin 用真实 edge 信封打 `/api/videos?page=1&size=1`，
///   校验返回的是有效视频列表数据（healthy_video_data），而不是只看状态码；
/// * 自动选线（autoLine.ts）：启动选一次；健康检查 60s/120s/300s 阶梯；
///   连续 2 次失败立即重选；API 失败（网络类）触发检查；主线路恢复优先切回。
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'package:XL/modules/hg/hg_diag.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_session.dart';

/// 地址发布页（lines.rs 的 PUBLISH_PAGES）。
const List<String> kHgPublishPages = [
  'https://huangguoai.pages.dev/',
  'https://huang-guo.pages.dev/',
];

const int _mirrorMax = 60;
const int _publishArrayMax = 256;
const int _recommendedMax = 20;
const int _autoMirrorMax = 10;
const String _autoProbePath = '/api/videos?page=1&size=1';

class HgMirrorItem {
  const HgMirrorItem({required this.url, required this.host});

  final String url;
  final String host;
}

class HgProbeHit {
  const HgProbeHit({
    required this.tier,
    required this.url,
    required this.ok,
    required this.reachable,
    required this.ms,
    this.status,
    this.error,
  });

  final String tier;
  final String url;
  final bool ok;
  final bool reachable;
  final int ms;
  final int? status;
  final String? error;
}

class HgAutoPickResult {
  const HgAutoPickResult({
    required this.base,
    required this.tier,
    required this.ms,
    required this.reason,
    required this.candidates,
    this.mirrorError,
  });

  final String base; // 空串 = all-down
  final String tier; // main / mirror / none
  final int ms;
  final String reason; // main-ok / mirror-ok / all-down
  final List<HgProbeHit> candidates;
  final String? mirrorError;

  bool get switched => base.isNotEmpty;
}

/* ──────────────── 可信镜像集合 ──────────────── */

final LinkedHashSet<String> _trustedMirrors = LinkedHashSet<String>();

/// 只有真实从可信发布页解析出来的 origin 才进集合
/// （lines.rs 的 TRUSTED_MIRRORS：展示/探测不产生信任）。
void _rememberPublished(List<HgMirrorItem> items) {
  for (final item in items) {
    _trustedMirrors.add(item.url);
    if (_trustedMirrors.length > 256) {
      _trustedMirrors.remove(_trustedMirrors.first);
    }
  }
}

bool isTrustedMirror(String origin) => _trustedMirrors.contains(origin);

bool isFixedLine(String url) =>
    kHgFixedLines.any((line) => line.$2 == url);

/* ──────────────── 发布脚本解析（保守词法器） ──────────────── */

class _JsToken {
  const _JsToken.ident(this.ident) : quoted = null, symbol = null;
  const _JsToken.quoted(this.quoted) : ident = null, symbol = null;
  const _JsToken.symbol(this.symbol) : ident = null, quoted = null;

  final String? ident;
  final String? quoted;
  final int? symbol;

  bool get isDeclaration =>
      ident == 'var' || ident == 'let' || ident == 'const';
}

/// 保守词法器（lines.rs 的 js_tokens）：注释、字符串、模板、正则都
/// 不能引入声明；歧义输入 fail-closed 抛错。
List<_JsToken> _jsTokens(String source) {
  final bytes = source.codeUnits;
  final out = <_JsToken>[];
  var at = 0;
  while (at < bytes.length) {
    final byte = bytes[at];
    if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
      at += 1;
      continue;
    }
    if (byte == 0x2F /* / */ && at + 1 < bytes.length && bytes[at + 1] == 0x2F) {
      at += 2;
      while (at < bytes.length && bytes[at] != 10) {
        at += 1;
      }
      continue;
    }
    if (byte == 0x2F /* / */ && at + 1 < bytes.length && bytes[at + 1] == 0x2A) {
      final end = source.indexOf('*/', at + 2);
      if (end < 0) throw '发布脚本注释未闭合';
      at = end + 2;
      continue;
    }
    if (byte == 39 /* ' */ || byte == 34 /* " */ || byte == 96 /* ` */) {
      final start = at;
      at += 1;
      while (at < bytes.length && bytes[at] != byte) {
        if (bytes[at] == 92) at += 1;
        at += 1;
      }
      if (at >= bytes.length) throw '发布脚本字符串未闭合';
      at += 1;
      out.add(byte == 96
          ? const _JsToken.symbol(0)
          : _JsToken.quoted(source.substring(start, at)));
      continue;
    }
    // 除号按正则处理：发布数据不需要算术，歧义直接拒绝。
    if (byte == 0x2F /* / */) {
      at += 1;
      var inClass = false;
      while (at < bytes.length) {
        final b = bytes[at];
        if (b == 92) {
          at += 2;
          continue;
        }
        if (b == 0x5B) {
          inClass = true;
        } else if (b == 0x5D) {
          inClass = false;
        } else if (b == 0x2F && !inClass) {
          break;
        } else if (b == 10 || b == 13) {
          throw '发布脚本包含不支持的表达式';
        }
        at += 1;
      }
      if (at >= bytes.length) throw '发布脚本表达式未闭合';
      at += 1;
      while (at < bytes.length && _isAlpha(bytes[at])) {
        at += 1;
      }
      out.add(const _JsToken.symbol(0));
      continue;
    }
    if (_isAlpha(byte) || byte == 0x5F || byte == 0x24) {
      final start = at;
      at += 1;
      while (at < bytes.length &&
          (_isAlnum(bytes[at]) || bytes[at] == 0x5F || bytes[at] == 0x24)) {
        at += 1;
      }
      out.add(_JsToken.ident(source.substring(start, at)));
    } else {
      out.add(_JsToken.symbol(byte));
      at += 1;
    }
  }
  return out;
}

bool _isAlpha(int b) =>
    (b >= 65 && b <= 90) || (b >= 97 && b <= 122);
bool _isAlnum(int b) => _isAlpha(b) || (b >= 48 && b <= 57);

String _jsString(String raw) {
  final body = raw.substring(1, raw.length - 1);
  final out = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final ch = body[i];
    if (ch != r'\') {
      if (_isControl(ch)) throw '镜像字符串含控制字符';
      out.write(ch);
      i += 1;
      continue;
    }
    i += 1;
    if (i >= body.length) throw '镜像字符串含不支持的转义';
    final esc = body[i];
    switch (esc) {
      case '\\':
      case "'":
      case '"':
      case '/':
        out.write(esc);
        i += 1;
      case 'x':
        final code = i + 3 <= body.length ? body.substring(i + 1, i + 3) : '';
        final value = int.tryParse(code, radix: 16);
        if (code.length != 2 || value == null) throw '镜像字符串转义无效';
        out.writeCharCode(value);
        i += 3;
      case 'u':
        final code = i + 5 <= body.length ? body.substring(i + 1, i + 5) : '';
        final value = int.tryParse(code, radix: 16);
        if (code.length != 4 || value == null) throw '镜像字符串转义无效';
        out.writeCharCode(value);
        i += 5;
      default:
        throw '镜像字符串含不支持的转义';
    }
  }
  return out.toString();
}

bool _isControl(String ch) {
  final code = ch.codeUnitAt(0);
  return code < 0x20 || code == 0x7F;
}

/// 只接受顶层字面量 `var/let/const name = [字符串, ...]`（lines.rs 的
/// js_array）：子域名格式坏掉时不回退信任裸域名。
List<String>? _jsArray(List<_JsToken> tokens, String name) {
  var depth = 0;
  List<String>? result;
  for (var at = 0; at < tokens.length; at++) {
    final token = tokens[at];
    if (depth == 0 &&
        token.isDeclaration &&
        at + 1 < tokens.length &&
        tokens[at + 1].ident == name) {
      if (result != null) throw '发布脚本重复声明 $name';
      if (at + 3 >= tokens.length ||
          tokens[at + 2].symbol != 0x3D /* = */ ||
          tokens[at + 3].symbol != 0x5B /* [ */) {
        throw '发布脚本的 $name 必须是字符串数组';
      }
      var cursor = at + 4;
      final values = <String>[];
      while (cursor < tokens.length && tokens[cursor].symbol != 0x5D) {
        final raw = tokens[cursor].quoted;
        if (raw == null) throw '发布脚本的 $name 含非字符串值';
        if (values.length >= _publishArrayMax) {
          throw '$name exceeds the publisher array size limit';
        }
        values.add(_jsString(raw));
        cursor += 1;
        if (cursor >= tokens.length) throw '发布脚本的 $name 数组格式无效';
        final next = tokens[cursor].symbol;
        if (next == 0x2C /* , */) {
          cursor += 1;
        } else if (next != 0x5D /* ] */) {
          throw '发布脚本的 $name 数组格式无效';
        }
      }
      if (cursor + 1 < tokens.length && tokens[cursor + 1].symbol != 0x3B /* ; */) {
        throw '发布脚本的 $name 不能使用动态表达式';
      }
      result = values;
    }
    final sym = token.symbol;
    if (sym == 0x7B || sym == 0x28 || sym == 0x5B) {
      depth += 1;
    } else if (sym == 0x7D || sym == 0x29 || sym == 0x5D) {
      if (depth > 0) depth -= 1;
    }
  }
  return result;
}

/* ──────────────── 镜像列表 ──────────────── */

bool _validDnsLabel(String value) {
  if (value.isEmpty || value.length > 63) return false;
  if (!_isAlnum(value.codeUnitAt(0))) return false;
  if (!_isAlnum(value.codeUnitAt(value.length - 1))) return false;
  for (final b in value.codeUnits) {
    if (!_isAlnum(b) && b != 0x2D) return false;
  }
  return true;
}

bool _validDnsName(String value) {
  if (value.length > 253 || !value.contains('.')) return false;
  const badSuffixes = ['localhost', 'local', 'internal', 'home.arpa'];
  for (final s in badSuffixes) {
    if (value == s || value.endsWith('.$s')) return false;
  }
  return value.split('.').every(_validDnsLabel);
}

/// 解析发布脚本（lines.rs 的 parse_mirrors）。
List<HgMirrorItem> parseMirrors(String js) {
  final tokens = _jsTokens(js);
  final domains = _jsArray(tokens, 'urls') ?? const <String>[];
  final subs = _jsArray(tokens, 'subdomains') ?? const <String>[];
  if (domains.isEmpty) throw '发布脚本中没有找到镜像域名';
  final items = <HgMirrorItem>[];
  final seen = <String>{};
  for (var domain in domains) {
    domain = domain.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    if (!_validDnsName(domain)) continue;
    final hosts = <String>[];
    if (subs.isEmpty) {
      hosts.add(domain);
    } else {
      for (final sub in subs) {
        final s = sub.trim().toLowerCase();
        if (_validDnsLabel(s)) hosts.add('$s.$domain');
      }
    }
    for (final host in hosts) {
      if (!_validDnsName(host) || !seen.add(host)) continue;
      final origin = HgNet.normalizeBase('https://$host');
      if (origin == null) continue;
      items.add(HgMirrorItem(url: origin, host: host));
      if (items.length >= _mirrorMax) return items;
    }
  }
  if (items.isEmpty) throw '发布脚本中没有合法镜像地址';
  return items;
}

/// 从发布页 HTML 里取第一个同源 publish.js 地址（lines.rs 的 script_src +
/// absolute：只接受同源 HTTPS、文件名必须是 publish.js）。
String scriptSrc(String page, String html) {
  final matches = RegExp(
    r'''<script[^>]*\bsrc\s*=\s*("([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  ).allMatches(html);
  for (final m in matches) {
    final src = m.group(2) ?? m.group(3) ?? '';
    if (src.isEmpty) continue;
    try {
      return _absolutePublishScript(page, src);
    } catch (_) {
      // 继续找下一个 script 标签。
    }
  }
  throw '地址发布页没有同源 publish.js 脚本';
}

String _absolutePublishScript(String base, String relative) {
  if (relative.codeUnits.any((c) => c < 0x20 || c == 0x7F)) {
    throw '发布脚本地址含控制字符';
  }
  final baseUri = Uri.parse(base);
  final target = baseUri.resolve(relative.trim());
  final fileName = target.path.split('/').last;
  if (baseUri.scheme != 'https' ||
      target.scheme != 'https' ||
      target.origin != baseUri.origin ||
      (target.userInfo.isNotEmpty) ||
      (target.fragment.isNotEmpty) ||
      fileName != 'publish.js') {
    throw '只接受发布页同源的 HTTPS publish.js';
  }
  return target.toString();
}

class _PublishedPage {
  const _PublishedPage(this.source, this.items);
  final String source;
  final List<HgMirrorItem> items;
}

Future<_PublishedPage> _mirrorsFromPage(String page) async {
  final html = await HgNet.getPublishText(page);
  final script = scriptSrc(page, html);
  final js = await HgNet.getPublishText(script);
  return _PublishedPage(page, parseMirrors(js));
}

class HgMirrorListing {
  const HgMirrorListing({
    required this.items,
    required this.recommended,
    this.errors = const [],
  });

  final List<HgMirrorItem> items;
  final List<HgMirrorItem> recommended;
  final List<String> errors;
}

/// 拉镜像列表（lines.rs 的 mirrors）：两个发布页并发、独立超时，
/// 一方失败不吞掉另一方成功结果；交错合并避免第一页盖住第二页。
Future<HgMirrorListing> mirrors() async {
  final results = await Future.wait<_PublishedPage?>(
    kHgPublishPages.map((page) async {
      try {
        return await _mirrorsFromPage(page);
      } catch (_) {
        return null;
      }
    }),
  );
  final pages = results.whereType<_PublishedPage>().toList();
  final errors = <String>[
    for (var i = 0; i < results.length; i++)
      if (results[i] == null) '${kHgPublishPages[i]}: 获取失败',
  ];
  final items = <HgMirrorItem>[];
  final seen = <String>{};
  for (var index = 0; index < _mirrorMax; index++) {
    for (final page in pages) {
      if (index < page.items.length) {
        final item = page.items[index];
        if (items.length < _mirrorMax && seen.add(item.url)) {
          items.add(item);
        }
      }
    }
  }
  if (items.isEmpty) {
    throw errors.isEmpty ? '地址发布页里没有可用的镜像地址' : errors.join('；');
  }
  _rememberPublished(items);
  final recommended = <HgMirrorItem>[];
  final recSeen = <String>{};
  final current = HgNet.normalizeBase(HgNet.base);
  if (current != null) {
    final host = Uri.parse(current).host;
    recSeen.add(current);
    recommended.add(HgMirrorItem(url: current, host: host));
  }
  for (final item in items) {
    if (recommended.length >= _recommendedMax) break;
    if (recSeen.add(item.url)) recommended.add(item);
  }
  return HgMirrorListing(items: items, recommended: recommended, errors: errors);
}

/* ──────────────── 探测 ──────────────── */

/// 校验 /api/videos 返回的是真视频列表（lines.rs 的 healthy_video_data）。
bool healthyVideoData(dynamic data) {
  if (data is! Map) return false;
  final items = data['items'];
  final pagination = data['pagination'];
  if (items is! List || pagination is! Map) return false;
  int? integer(String key) {
    final v = pagination[key];
    return v is num ? v.toInt() : null;
  }

  final page = integer('page');
  final size = integer('size');
  if (page == null || page == 0 || size == null || size == 0) return false;
  if (integer('pages') == null || integer('total') == null) return false;
  for (final item in items) {
    if (item is! Map) return false;
    final id = item['id'];
    final title = item['title'];
    if (id is! num || id <= 0) return false;
    if (title is! String || title.trim().isEmpty) return false;
  }
  return true;
}

Future<HgProbeHit> probeHit(String tier, String raw) async {
  var url = raw;
  var ok = false;
  var reachable = false;
  int? status;
  String? error;
  final origin = HgNet.normalizeBase(raw);
  if (origin == null) {
    return HgProbeHit(
      tier: tier,
      url: raw,
      ok: false,
      reachable: false,
      ms: 0,
      error: '线路必须是安全 HTTPS origin',
    );
  }
  url = origin;
  final started = DateTime.now();
  try {
    final data = await HgNet.edge(
      'GET',
      _autoProbePath,
      baseOverride: origin,
    ).timeout(const Duration(seconds: 5));
    reachable = true;
    status = 200;
    ok = healthyVideoData(data);
    if (!ok) error = '接口未返回有效视频列表数据';
  } on TimeoutException {
    error = '视频接口探测超时（5 秒）';
  } catch (e) {
    error = e.toString();
  }
  return HgProbeHit(
    tier: tier,
    url: url,
    ok: ok,
    reachable: reachable,
    ms: DateTime.now().difference(started).inMilliseconds,
    status: status,
    error: error,
  );
}

/// 手动探测任意 origin 列表（lines.rs 的 probe，LinePicker 用，并发）。
Future<List<HgProbeHit>> probe(List<String> urls) async {
  final list = urls.take(_mirrorMax).toList();
  return Future.wait(list.map((origin) => probeHit('mirror', origin)));
}

HgAutoPickResult _pickFromHits(List<HgProbeHit> hits) {
  HgProbeHit? winner;
  var bestMs = -1;
  for (final hit in hits) {
    if (!hit.ok) continue;
    if (winner == null || hit.ms < bestMs) {
      winner = hit;
      bestMs = hit.ms;
    }
  }
  if (winner != null) {
    return HgAutoPickResult(
      base: winner.url,
      tier: winner.tier,
      ms: winner.ms,
      reason: winner.tier == 'main' ? 'main-ok' : 'mirror-ok',
      candidates: hits,
    );
  }
  return HgAutoPickResult(
    base: '',
    tier: 'none',
    ms: 0,
    reason: 'all-down',
    candidates: hits,
  );
}

/// 自动候选只来自真实发布条目（lines.rs 的 auto_candidates）：
/// 排除固定线路、必须已被发布页收录（可信）；当前线路若确实在发布
/// 列表里则保留为候选。
List<String> _autoCandidates(List<HgMirrorItem> items) {
  final candidates = <String>[];
  final seen = <String>{};
  final current = HgNet.normalizeBase(HgNet.base);
  final published = <String>[
    for (final item in items)
      if (!kHgFixedLines.any((l) => l.$2 == item.url) &&
          isTrustedMirror(item.url))
        item.url,
  ];
  if (current != null && published.contains(current)) {
    seen.add(current);
    candidates.add(current);
  }
  for (final origin in published) {
    if (candidates.length >= _autoMirrorMax) break;
    if (seen.add(origin)) candidates.add(origin);
  }
  return candidates;
}

/// 自动选线（lines.rs 的 auto_pick）：主线路 OK 直接用；否则拉镜像
/// 列表并发探测候选，取最快的可用者。
Future<HgAutoPickResult> autoPick() async {
  final mainHit = await probeHit('main', kHgFixedLines[0].$2);
  if (mainHit.ok) {
    return _pickFromHits([mainHit]);
  }
  String? mirrorError;
  final hits = <HgProbeHit>[mainHit];
  try {
    final listing = await mirrors();
    final candidates = _autoCandidates(listing.items);
    final mirrorHits = await probe(candidates);
    hits.addAll(mirrorHits);
  } catch (e) {
    mirrorError = e.toString();
  }
  final result = _pickFromHits(hits);
  if (mirrorError != null) {
    return HgAutoPickResult(
      base: result.base,
      tier: result.tier,
      ms: result.ms,
      reason: result.reason,
      candidates: result.candidates,
      mirrorError: mirrorError,
    );
  }
  return result;
}

/// 主线路探测（lines.rs 的 try_main）：健康时优先切回主线路。
Future<HgProbeHit> tryMain() => probeHit('main', kHgFixedLines[0].$2);

/// 当前线路健康检查（lines.rs 的 health）。
Future<HgProbeHit> health() => probeHit('current', HgNet.base);

/* ──────────────── 手动选线（LinePicker.tsx 的 applyLine） ──────────────── */

/// 手动切换线路：立即关自动选线（失败恢复），成功后持久化并广播。
/// 返回归一化后的 origin。
Future<String> setManualLine(String url, {bool custom = false}) async {
  final wasAuto = HgStore.prefs.autoLine;
  final previous = HgNet.base;
  try {
    if (wasAuto) await HgStore.prefs.setAutoLine(false);
    final normalized = HgNet.normalizeBase(url);
    if (normalized == null) throw '线路必须是合法的 HTTP(S) 地址';
    HgNet.setBase(normalized);
    await HgStore.prefs.setLineBase(normalized);
    HgAutoLine.lineEpoch.value++;
    await HgDiag.trace('line.manual', {
      'line': normalized,
      'prev': previous,
      'custom': custom,
      'ok': true,
    });
    return normalized;
  } catch (e) {
    if (wasAuto) await HgStore.prefs.setAutoLine(true);
    await HgDiag.trace('line.manual', {
      'line': url,
      'prev': previous,
      'ok': false,
      'err': e.toString(),
    });
    rethrow;
  }
}

/// 自定义镜像（LinePicker.tsx 的 saveCustom）：只接受 HTTPS 站点根地址，
/// 不带路径、参数、账号密码。
Future<String> setCustomLine(String raw) async {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw '请填写 HTTPS 站点根地址，不带路径、参数或账号密码';
  }
  return setManualLine(s, custom: true);
}

/// 恢复主站（LinePicker.tsx 的 line_reset）。
Future<String> resetLine() => setManualLine(kHgDefaultBase);

/* ──────────────── 自动选线调度（autoLine.ts） ──────────────── */

class HgAutoLine {
  HgAutoLine._();

  static const _healthSteps = [60, 120, 300]; // 秒
  static const _recheckMs = 4000;
  static const _pickCooldownMs = 15000;

  static Timer? _timer;
  static int _step = 0;
  static int _downStreak = 0;
  static int _failStreak = 0;
  static DateTime? _lastPickAt;
  static bool _picking = false;
  static bool _checking = false;
  static bool _started = false;

  /// 线路变化纪元：UI（发现页/设置页）监听它重建。
  static final ValueNotifier<int> lineEpoch = ValueNotifier<int>(0);

  static bool get enabled => HgStore.prefs.autoLine;

  static void start() {
    if (_started) return;
    _started = true;
    HgNet.onApiFailure = _onApiFailure;
    if (!enabled) return;
    pickLine('boot', force: true);
  }

  static void setEnabled(bool on) {
    HgStore.prefs.setAutoLine(on);
    if (!on) {
      _timer?.cancel();
      _timer = null;
    } else if (_started) {
      pickLine('manual', force: true);
    }
    lineEpoch.value++;
  }

  static void _onApiFailure(bool networkish) {
    if (!enabled) return;
    if (!networkish) {
      _failStreak = 0;
      return;
    }
    _failStreak += 1;
    if (_failStreak < 2) return;
    _failStreak = 0;
    check('api-fail');
  }

  /// 立即重选线路（播放失败重试按钮也可调用）。
  static Future<void> pickLine(String reason, {bool force = false}) async {
    if (!enabled || _picking) return;
    if (!force &&
        _lastPickAt != null &&
        DateTime.now().difference(_lastPickAt!).inMilliseconds <
            _pickCooldownMs) {
      return;
    }
    _picking = true;
    var down = false;
    try {
      final result = await autoPick();
      _lastPickAt = DateTime.now();
      _downStreak = 0;
      _failStreak = 0;
      _step = 0;
      if (result.reason == 'all-down') {
        down = true;
        return;
      }
      if (HgNet.base != result.base) {
        HgNet.setBase(result.base);
        await HgStore.prefs.setLineBase(result.base);
        HgAutoLine.lineEpoch.value++;
        await HgDiag.trace('line.auto', {
          'line': result.base,
          'tier': result.tier,
          'ms': result.ms,
          'reason': result.reason,
          'mirror_error': result.mirrorError,
        });
      }
    } catch (_) {
      // 选线失败不致命，等下次健康检查。
    } finally {
      _picking = false;
      if (enabled) _schedule(down ? 10 : _healthSteps[0]);
    }
  }

  /// 当前线路健康检查：ok 则阶梯拉长检查间隔；连续 2 次失败重选。
  static Future<void> check(String reason) async {
    if (!enabled || _checking) return;
    if (_picking) {
      _schedule(_healthSteps[_step]);
      return;
    }
    _checking = true;
    try {
      final hit = await health();
      if (hit.ok) {
        _downStreak = 0;
        if (_step < _healthSteps.length - 1) _step += 1;
        if (Uri.parse(HgNet.base).host != 'huangguoai.com') {
          // 非主线路：主线路恢复时优先切回。
          final main = await tryMain();
          if (main.ok && HgNet.base != main.url) {
            HgNet.setBase(main.url);
            await HgStore.prefs.setLineBase(main.url);
            HgAutoLine.lineEpoch.value++;
            await HgDiag.trace('line.auto', {
              'line': main.url,
              'tier': 'main',
              'reason': 'main-restored',
            });
          }
        }
        _schedule(_healthSteps[_step]);
        return;
      }
      _downStreak += 1;
      if (_downStreak < 2) {
        _schedule(_recheckMs ~/ 1000);
        return;
      }
      _downStreak = 0;
      _step = 0;
      await pickLine(reason, force: true);
    } catch (_) {
      _schedule(_healthSteps[_step]);
    } finally {
      _checking = false;
    }
  }

  static void _schedule(int seconds) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds), () {
      // 后台时不打扰（autoLine 的 visibilitychange 语义）。
      if (WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed) {
        check('timer');
      } else {
        _schedule(_healthSteps[0]);
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    HgNet.onApiFailure = null;
  }
}
