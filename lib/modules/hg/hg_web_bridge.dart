/// Tauri 命令桥（HG 模块 WebView 化 · 路线 A）。
///
/// WebView 里注入的 shim 把 `window.__TAURI_INTERNALS__.invoke` 转成
/// `flutter_inappwebview.callHandler('hgInvoke', cmd, args)`，由这里分派。
///
/// 命令清单与 HGhubX fork（zxsos/HGhubX @ 2026-11-14）`src-tauri/src/lib.rs`
/// 的 invoke_handler 注册表逐条对齐；api_* 的路径/方法与 api.rs 一致，
/// 返回值保持上游 JSON 原样（透传），前端 types.ts 即契约。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hg_api.dart';
import 'hg_diag.dart';
import 'hg_lines.dart';
import 'hg_models.dart';
import 'hg_net.dart';
import 'hg_session.dart';

class HgWebBridge {
  HgWebBridge._();

  /// flutter_inappwebview addJavaScriptHandler 的入口。
  /// Tauri 的 invoke 失败以「字符串」reject（api.ts 的 call() 直接 typeof 判断），
  /// 所以这里把所有异常统一转成字符串抛出。
  static Future<dynamic> handle(List<dynamic> args) async {
    final cmd = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
    final a = (args.length > 1 && args[1] is Map) ? args[1] as Map : const <dynamic, dynamic>{};
    try {
      return await _dispatch(cmd, a);
    } on HgApiError catch (e) {
      throw e.message;
    } catch (e) {
      throw e.toString();
    }
  }

  static Future<dynamic> _dispatch(String cmd, Map a) async {
    /* ── 应用 / 系统 ── */
    switch (cmd) {
      case 'app_boot':
        return _appBoot();
      case 'security_set':
        await HgStore.prefs.setStrictSecurity(a['strict'] == true);
        return true;
      case 'debug_log':
        await HgDiag.trace('web.debug', {'msg': a['msg']?.toString() ?? ''});
        return null;
      case 'net_diag':
        final r = await HgNetDiag.run();
        return r.raw;
      case 'cache_clear':
        await _clearCache();
        return null;
      case 'set_orientation':
        final landscape = a['landscape'] == true;
        await SystemChrome.setPreferredOrientations(landscape
            ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
            : [DeviceOrientation.portraitUp]);
        return null;
      case 'set_text_interaction':
        // 上游 iOS 专用（WKWebView 文本交互开关）。Flutter WebView 无对应
        // 概念，长按放大镜由外层手势策略处理，这里恒为 no-op。
        return null;
      case 'open_url':
        final url = a['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
        return null;
      case 'check_update':
        return _checkUpdate();

      /* ── 播放诊断日志 ── */
      case 'playback_log_status':
        return _logStatus(null);
      case 'playback_log_set':
        await HgStore.prefs.setPlaybackLog(a['enabled'] == true);
        return _logStatus(null);
      case 'playback_log_write':
        await _logWrite(a['entries']);
        return null;
      case 'playback_log_read':
        return HgDiag.read();

      /* ── 线路（数据源） ── */
      case 'line_state':
        return _lineState();
      case 'line_set':
        return setManualLine(a['url']?.toString() ?? '');
      case 'line_custom_set':
        return {'base': await setCustomLine(a['url']?.toString() ?? ''), 'custom': true};
      case 'line_reset':
        return {'base': await resetLine(), 'custom': false};
      case 'line_cancel':
        // Rust 侧取消进行中的 auto pick；我们的 autoPick 生命周期短，
        // 直接返回（与 auto.ts 的轮询语义兼容）。
        return null;
      case 'line_mirrors':
        return _lineMirrors();
      case 'line_probe':
        return _lineProbe(a['urls']);
      case 'line_auto':
        return _lineAuto();
      case 'line_try_main':
        return _lineTryMain();
      case 'line_health':
        return _lineHealth();

      /* ── 应用内代理 ── */
      case 'proxy_state':
        return _proxyState();
      case 'proxy_set':
        await HgStore.prefs.setProxy(a['mode']?.toString() ?? 'system', a['url']?.toString() ?? '');
        return _proxyState();
      case 'proxy_test':
        return _proxyTest(a['mode']?.toString() ?? 'system', a['url']?.toString() ?? '');

      /* ── 会话 ── */
      case 'api_login':
        final user = await HgApi.login(
          a['username']?.toString() ?? '',
          a['password']?.toString() ?? '',
        );
        return {'user': _userJson(user)};
      case 'api_register':
        final user = await HgApi.register(
          a['username']?.toString() ?? '',
          a['password']?.toString() ?? '',
          a['email']?.toString() ?? '',
        );
        return {'user': _userJson(user)};
      case 'api_logout':
        await HgApi.logout();
        return {'ok': true};
      case 'api_me':
        return _apiMe();

      /* ── 播放（双接口回退 + normalize） ── */
      case 'api_play':
        return _apiPlay(
          (a['id'] as num?)?.toInt() ?? 0,
          (a['ep'] as num?)?.toInt() ?? 0,
        );

      /* ── 其余 api_*：与 api.rs 相同路径/方法，透传 ── */
      case 'api_feed':
        return _edgeGet('/api/videos?page=${_num(a, 'page')}&size=${_num(a, 'size')}');
      case 'api_original_videos':
        return _originalVideos(a);
      case 'api_topics':
        return _edgeGet('/api/topics?size=100');
      case 'api_topic':
        return _edgeGet('/api/topics/${Uri.encodeComponent(a['slug']?.toString() ?? '')}');
      case 'api_tags':
        return _edgeGet('/api/tags');
      case 'api_tag_videos':
        return _edgeGet(
            '/api/videos/tag/${Uri.encodeComponent(a['tag']?.toString() ?? '')}?page=${_num(a, 'page')}&size=${_num(a, 'size')}');
      case 'api_category':
        return _edgeGet(_withSort(
            '/api/videos/category/${a['cate']?.toString() ?? ''}?page=${_num(a, 'page')}&size=${_num(a, 'size')}',
            a['sort']));
      case 'api_rank':
        return _edgeGet('/api/ranks/${a['kind']?.toString() ?? 'hot'}');
      case 'api_search':
        return _edgeGet(_searchPath(a));
      case 'api_search_hot':
        return _edgeGet('/api/search_hot');
      case 'api_posts':
        return _edgeGet(_withSort('/api/posts?page=${_num(a, 'page')}&size=${_num(a, 'size')}', a['sort']));
      case 'api_post':
        return _edgeGet('/api/posts/${_num(a, 'id')}');
      case 'api_post_playback':
        return _edgePost('/api/posts/${_num(a, 'id')}/playback', {});
      case 'api_video':
        return _edgeGet('/api/videos/${_num(a, 'id')}');
      case 'api_comments':
        return _edgeGet(
            '/api/videos/${_num(a, 'id')}/comments?ep=${_num(a, 'ep')}&page=${_num(a, 'page')}&size=${_num(a, 'size')}');
      case 'api_comment_send':
        return _commentSend(a);
      case 'api_like':
        return _edge(a['on'] == true ? 'POST' : 'DELETE',
            '/api/videos/${_num(a, 'id')}/like?ep=${_num(a, 'ep')}', authed: true);
      case 'api_collect':
        return _edge(a['on'] == true ? 'POST' : 'DELETE',
            '/api/videos/${_num(a, 'id')}/collect', authed: true);
      case 'api_follow':
        return _edge(a['on'] == true ? 'POST' : 'DELETE',
            '/api/users/${_num(a, 'uid')}/follow', authed: true);
      case 'api_post_like':
        return _edge(a['on'] == true ? 'POST' : 'DELETE', '/api/posts/${_num(a, 'id')}/like',
            authed: true);
      case 'api_post_collect':
        return _edge(a['on'] == true ? 'POST' : 'DELETE',
            '/api/posts/${_num(a, 'id')}/collect', authed: true);
      case 'api_post_comments':
        return _edgeGet(
            '/api/posts/${_num(a, 'id')}/comments?page=${_num(a, 'page')}&size=${_num(a, 'size')}');
      case 'api_post_categories':
        return _edgeGet('/api/site/categories/post');
      case 'api_post_category':
        return _edgeGet(_withSort(
            '/api/posts/category/${Uri.encodeComponent(a['route']?.toString() ?? '')}?page=${_num(a, 'page')}&size=${_num(a, 'size')}',
            a['sort']));
      case 'api_related':
        return _edgeGet('/api/videos/${_num(a, 'id')}/related');
      case 'api_following':
        return _edgeGet('/api/videos/following?page=${_num(a, 'page')}&size=${_num(a, 'size')}');
      case 'api_user':
        return _edgeGet('/api/users/${_num(a, 'id')}');
      case 'api_user_stats':
        return _edgeGet('/api/users/${_num(a, 'id')}/stats');
      case 'api_user_videos':
        return _edgeGet(
            '/api/videos/user/${_num(a, 'id')}?page=${_num(a, 'page')}&size=${_num(a, 'size')}');

      /* ── Tauri 插件命令 ── */
      case 'plugin:clipboard-manager|write_text':
        await Clipboard.setData(ClipboardData(text: a['text']?.toString() ?? ''));
        return null;
      case 'plugin:clipboard-manager|read_text':
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        return clip?.text ?? '';
    }

    // Tauri window 插件（DesktopChrome 的最小化/最大化/关闭，仅桌面壳渲染）。
    if (cmd.startsWith('plugin:window|')) return null;

    throw '未知命令: $cmd';
  }

  /* ════════════════════ 实现 ════════════════════ */

  /// api.rs 的 app_boot：会话 + 线路 + 严格模式状态一次下发。
  static Future<Map<String, dynamic>> _appBoot() async {
    final origin = HgNet.base;
    final session = HgStore.session;
    final strict = HgStore.prefs.strictSecurity;
    // Rust：严格模式下，非可信 origin 不允许下发凭据。
    final allowed = !strict || isFixedLine(origin) || isTrustedMirror(origin);
    return {
      'user': allowed ? _userJsonOrNull(session.user) : null,
      'logged_in': allowed && session.loggedIn && session.origin == origin,
      'base': origin,
      'strict_security': strict,
      'cli_relaxed': false,
    };
  }

  /// api.rs 的 api_me：透传 + 会话刷新。
  static Future<dynamic> _apiMe() async {
    final data = await _edgeGet('/api/account/me');
    final origin = HgNet.base;
    final session = HgStore.session;
    if (session.loggedIn && session.origin == origin) {
      final user = HgUser.fromJson(data);
      await HgStore.setSession(origin, session.token, user);
    }
    return data;
  }

  /// api.rs 的 api_play：新接口 playback 优先，legacy play 兜底；
  /// normalize 把 streams.main/hevc 回填到 video_url/video_url_hevc。
  static Future<dynamic> _apiPlay(int id, int ep) async {
    dynamic primary;
    String? primaryError;
    try {
      primary = await _edgePost('/api/videos/$id/episodes/$ep/playback', {});
      if (primary is Map) _normalizePlayInfo(primary);
      if (_hasPlayUrl(primary)) return primary;
    } catch (e) {
      primaryError = e.toString();
    }
    try {
      final legacy = await _edgeGet('/api/videos/$id/play?ep=$ep&page_texts=0');
      if (legacy is Map) _normalizePlayInfo(legacy);
      if (_hasPlayUrl(legacy) || primaryError != null) return legacy;
    } catch (_) {
      // 用新接口的错误兜底。
    }
    if (primaryError != null) throw primaryError;
    return primary;
  }

  static void _normalizePlayInfo(Map info) {
    final streams = info['streams'];
    if (streams is! Map) return;
    for (final entry in [
      ('video_url', 'main'),
      ('video_url_hevc', 'hevc'),
    ]) {
      final field = entry.$1;
      final key = entry.$2;
      final url = streams[key];
      if (url is String && url.trim().isNotEmpty) {
        final cur = info[field];
        if (cur is! String || cur.trim().isEmpty) info[field] = url;
      }
    }
  }

  static bool _hasPlayUrl(dynamic info) =>
      info is Map && info['video_url'] is String && (info['video_url'] as String).trim().isNotEmpty;

  static Future<dynamic> _originalVideos(Map a) async {
    final cate = a['cate']?.toString() ?? 'all';
    final sort = _sortSuffix(a['sort']);
    final path = cate == 'all'
        ? '/api/videos?is_original=1&page=${_num(a, 'page')}&size=${_num(a, 'size')}$sort'
        : '/api/videos/category/$cate?is_original=1&page=${_num(a, 'page')}&size=${_num(a, 'size')}$sort';
    return _edgeGet(path);
  }

  static Future<dynamic> _commentSend(Map a) async {
    final id = _num(a, 'id');
    final ep = _num(a, 'ep');
    final text = a['text']?.toString() ?? '';
    final replyId = a['replyId'];
    final rid = (replyId is num && replyId > 0) ? replyId.toInt() : null;
    final body = <String, dynamic>{'text': text};
    final path = rid != null
        ? '/api/videos/$id/comments'
        : '/api/videos/$id/comments?ep=$ep';
    if (rid != null) body['reply_id'] = rid;
    return _edge('POST', path, body: body, authed: true);
  }

  /* ── 线路 ── */

  static Map<String, dynamic> _lineState() {
    final base = HgNet.base;
    return {
      'base': base,
      'default': kHgDefaultBase,
      'fixed': [
        for (final line in kHgFixedLines)
          {'name': line.$1, 'url': line.$2, 'host': _hostOf(line.$2)},
      ],
      'custom':
          HgStore.prefs.lineBase.isNotEmpty && !isFixedLine(base),
    };
  }

  static Future<Map<String, dynamic>> _lineMirrors() async {
    final listing = await mirrors();
    return {
      'source': '',
      'script': null,
      'items': [
        for (final m in listing.items)
          {'name': m.host, 'url': m.url, 'host': m.host},
      ],
      'recommended_source': '',
      'recommended': [
        for (final m in listing.recommended)
          {'name': m.host, 'url': m.url, 'host': m.host},
      ],
      'errors': listing.errors,
    };
  }

  static Future<List<Map<String, dynamic>>> _lineProbe(dynamic urls) async {
    final list = <String>[
      if (urls is List) for (final u in urls) u?.toString() ?? '',
    ];
    final hits = await probe(list);
    return [for (final h in hits) _probeJson(h)];
  }

  static Future<Map<String, dynamic>> _lineAuto() async {
    final previous = HgNet.base;
    final r = await autoPick();
    // autoPick 只探测不切换；切换在这里落（对齐 lines.rs 的 line_auto）。
    if (r.base.isNotEmpty && r.base != previous) {
      await setManualLine(r.base);
    }
    return {
      'previous': previous,
      'base': r.base.isNotEmpty ? r.base : HgNet.base,
      'switched': r.base.isNotEmpty && r.base != previous,
      'pick': {
        'base': r.base,
        'tier': r.tier,
        'ms': r.ms,
        'reason': r.reason,
        'candidates': [for (final h in r.candidates) _candidateJson(h)],
      },
      if (r.mirrorError != null) 'mirror_error': r.mirrorError,
    };
  }

  static Future<Map<String, dynamic>> _lineTryMain() async {
    final previous = HgNet.base;
    final h = await tryMain();
    var switched = false;
    if (h.ok && h.url != previous) {
      await setManualLine(h.url);
      switched = true;
    }
    return {
      'previous': previous,
      'base': switched ? h.url : HgNet.base,
      'switched': switched,
      'probe': {
        'ok': h.ok,
        'base': h.url,
        'tier': h.tier,
        'ms': h.ms,
        'status': h.status,
      },
    };
  }

  static Future<Map<String, dynamic>> _lineHealth() async {
    final h = await health();
    return {'base': HgNet.base, 'ok': h.ok, 'ms': h.ms, 'status': h.status};
  }

  static Map<String, dynamic> _probeJson(HgProbeHit h) => {
        'url': h.url,
        'ok': h.ok,
        'status': h.status,
        'ms': h.ms,
        'error': h.error,
      };

  static Map<String, dynamic> _candidateJson(HgProbeHit h) => {
        'tier': h.tier,
        'url': h.url,
        'ok': h.ok,
        'reachable': h.reachable,
        'ms': h.ms,
        'status': h.status,
      };

  /* ── 代理 ── */

  static Map<String, dynamic> _proxyState() {
    final mode = HgStore.prefs.proxyMode;
    return {
      'mode': mode,
      'url': HgStore.prefs.proxyUrl,
      'effective': mode == 'custom' ? HgStore.prefs.proxyUrl : null,
      'system_proxy': null,
      'env_proxy': null,
    };
  }

  static Future<Map<String, dynamic>> _proxyTest(String mode, String url) async {
    final (ok, ms, status, error) = await HgNet.testProxy(mode, url);
    return {
      'ok': ok,
      'status': status,
      'ms': ms,
      'error': error.isEmpty ? null : error,
    };
  }

  /* ── 播放诊断日志 ── */

  static Map<String, dynamic> _logStatus(String? error) => {
        'enabled': HgStore.prefs.playbackLog,
        'path': HgDiag.path,
        'error': error,
      };

  static Future<void> _logWrite(dynamic entries) async {
    if (entries is! List) return;
    for (final e in entries) {
      if (e is! Map) continue;
      final data = e['data'];
      await HgDiag.trace(
        e['event']?.toString() ?? 'web.event',
        data is Map ? data.map((k, v) => MapEntry(k.toString(), v)) : {},
      );
    }
  }

  /* ── 更新检查（对 LU 仓库的 Release，而不是上游 HGhubX） ── */

  static Future<Map<String, dynamic>> _checkUpdate() async {
    const repo = '1506193478/LU';
    final current = _currentVersion;
    try {
      final body = await _httpGet('https://api.github.com/repos/$repo/releases/latest');
      final rel = jsonDecode(body) as Map;
      final tag = rel['tag_name']?.toString() ?? '';
      final latest = tag.replaceFirst(RegExp(r'^v'), '');
      final assets = (rel['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => {'name': a['name']?.toString() ?? '', 'url': a['browser_download_url']?.toString() ?? ''})
          .toList();
      Map<String, String>? asset;
      final plat = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : 'windows';
      for (final a in assets) {
        final name = a['name']!.toLowerCase();
        if ((plat == 'android' && name.endsWith('.apk')) ||
            (plat == 'ios' && name.endsWith('.ipa')) ||
            (plat == 'windows' && name.endsWith('.zip'))) {
          asset = a.cast<String, String>();
          break;
        }
      }
      return {
        'asset': asset,
        'current': current,
        'latest': latest,
        'tag': tag,
        'has_update': latest.isNotEmpty && latest != current,
        'url': rel['html_url']?.toString() ?? 'https://github.com/$repo/releases',
        'name': rel['name']?.toString(),
        'published_at': rel['published_at']?.toString(),
        'notes': rel['body']?.toString(),
      };
    } catch (e) {
      return {
        'asset': null,
        'current': current,
        'latest': current,
        'has_update': false,
        'url': 'https://github.com/$repo/releases',
      };
    }
  }

  /// LU 的当前版本号（发版流程统一 bump pubspec，从那里读）。
  static String get _currentVersion {
    // 由宿主在 init 时注入（main.dart 启动时调用 setAppVersion）。
    if (_appVersion.isNotEmpty) return _appVersion;
    return '0.0.0';
  }

  static String _appVersion = '';

  /// 宿主启动时注入应用版本（package_info 的一次性快照）。
  static void setAppVersion(String v) => _appVersion = v;

  /* ── 杂项 ── */

  static Future<void> _clearCache() async {
    try {
      // 图片内存缓存 + 磁盘缓存（HG 模块没有独立 HTTP 缓存层）。
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
  }

  static Future<dynamic> _edgeGet(String path) => _edge('GET', path);

  static Future<dynamic> _edgePost(String path, Map<String, dynamic> body) =>
      _edge('POST', path, body: body);

  static Future<dynamic> _edge(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authed = false,
  }) =>
      HgNet.edge(method, path, body: body, authed: authed);

  /* ── 小工具 ── */

  static int _num(Map a, String key) {
    final v = a[key];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String _sortSuffix(dynamic sort) {
    final s = sort?.toString() ?? '';
    return s.trim().isEmpty ? '' : '&sort=$s';
  }

  static String _withSort(String path, dynamic sort) => '$path${_sortSuffix(sort)}';

  static String _searchPath(Map a) {
    final q = Uri.encodeComponent(a['q']?.toString() ?? '');
    final kind = a['kind']?.toString();
    final scope = kind == 'post' ? '&type=post' : (kind == 'video' ? '&type=video' : '');
    return '/api/search?q=$q&page=${_num(a, 'page')}&size=${_num(a, 'size')}$scope';
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    }
  }

  static Map<String, dynamic>? _userJsonOrNull(HgUser? u) =>
      u == null ? null : _userJson(u);

  static Map<String, dynamic> _userJson(HgUser u) => {
        'id': u.id,
        'username': u.username,
        'nickname': u.nickname,
        'avatar': u.avatar,
        'avatar_color': u.avatarColor,
        'sign': u.sign,
        'desc': u.desc,
      };
}

Future<String> _httpGet(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'LU-HG-Module');
    final res = await req.close().timeout(const Duration(seconds: 15));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

