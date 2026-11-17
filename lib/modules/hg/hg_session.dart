/// HG 会话：登录 token + 用户资料 + 彩蛋解锁标记，存独立 Hive box。
///
/// 会话按线路 origin 绑定（和 HGhubX 的 session.rs 一致）：换线路
/// token 不跟过去，避免把旧站点的凭证发给新站点。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:hive_ce/hive.dart';

import 'package:XL/modules/hg/hg_models.dart';

class HgSession {
  String origin = '';
  String token = '';
  HgUser? user;

  bool get loggedIn => token.isNotEmpty && origin.isNotEmpty;
}

/// HG 设置项（HGhubX `src/store.tsx` 的 Persist + Settings.tsx 全量照搬）。
///
/// 只作用于 HG 模块内部，存在独立 Hive box 'hg'，不影响 LU 主体偏好。
/// 上游默认值：muted/muteOnStartup=true、volume=0.7、swipeEp=true、
/// preferHevc=false、autoLine=on、theme=system。
class HgPrefs {
  HgPrefs._();

  Box? _box;

  bool _autoLine = true;
  bool _preferHevc = false;
  bool _swipeEp = true;
  bool _muteOnStartup = true;
  double _volume = 0.7;
  String _appearance = 'system'; // system / light / dark
  bool _strictSecurity = false;
  List<String> _searchHist = [];
  String _lineBase = '';
  List<int> _favs = [];
  final Map<String, Map<String, dynamic>> _history = {};
  // 代理（proxy.rs：system/custom/off）与播放诊断日志。
  String _proxyMode = 'system';
  String _proxyUrl = '';
  bool _playbackLog = false;

  bool get autoLine => _autoLine;
  bool get preferHevc => _preferHevc;
  bool get swipeEp => _swipeEp;
  bool get muteOnStartup => _muteOnStartup;
  double get volume => _volume;
  String get appearance => _appearance;
  bool get strictSecurity => _strictSecurity;
  List<String> get searchHist => List.unmodifiable(_searchHist);

  /// 应用代理模式：system（跟随系统/TUN）/ custom / off（直连）。
  String get proxyMode => _proxyMode;

  /// 自定义代理地址（已归一化，凭据仅保存在本地输入框回填用）。
  String get proxyUrl => _proxyUrl;

  /// 播放诊断日志 verbose 开关（失败原因始终记录，不受开关影响）。
  bool get playbackLog => _playbackLog;

  /// 持久化的手选/自动线路（启动时恢复，上游 line.json 语义）。
  String get lineBase => _lineBase;

  /// 本地片库（store.tsx 的 favs）：本地收藏的视频 id 列表。
  List<int> get favs => List.unmodifiable(_favs);

  bool isFav(int videoId) => _favs.contains(videoId);

  Future<void> toggleFav(int videoId) async {
    if (_favs.contains(videoId)) {
      _favs.remove(videoId);
    } else {
      _favs.insert(0, videoId);
    }
    await _box?.put('pref_favs', _favs);
    changed.value++;
  }

  /// 观看记录（store.tsx 的 history）：'id:ep' → {id, ep, t, dur, at}。
  /// onTime 节流写回；resume 进度与「我的→观看记录」都用它。
  Map<String, Map<String, dynamic>> get history =>
      Map.unmodifiable(_history);

  Map<String, dynamic>? historyOf(int videoId, int ep) =>
      _history['$videoId:$ep'];

  Future<void> saveHistory(
    int videoId,
    int ep,
    double t,
    double dur,
  ) async {
    if (dur <= 0) return;
    final key = '$videoId:$ep';
    final prev = _history[key];
    // 播完的条目保留（上游历史列表也显示完整看完的），只是 t 封顶。
    _history[key] = {
      'id': videoId,
      'ep': ep,
      't': t,
      'dur': dur,
      'at': DateTime.now().millisecondsSinceEpoch,
      if (prev?['title'] != null) 'title': prev!['title'],
      if (prev?['cover'] != null) 'cover': prev!['cover'],
    };
    // 上限 200 条：最旧的先淘汰。
    if (_history.length > 200) {
      final keys = _history.keys.toList()
        ..sort((a, b) => ((_history[a]!['at'] as num?) ?? 0)
            .compareTo((_history[b]!['at'] as num?) ?? 0));
      for (final k in keys.take(_history.length - 200)) {
        _history.remove(k);
      }
    }
    await _box?.put('pref_history', _history);
  }

  Future<void> setHistoryMeta(
    int videoId,
    String title,
    String cover,
  ) async {
    var touched = false;
    for (final key in _history.keys.toList()) {
      final entry = _history[key]!;
      if (entry['id'] == videoId) {
        if (entry['title'] != title || entry['cover'] != cover) {
          entry['title'] = title;
          entry['cover'] = cover;
          touched = true;
        }
      }
    }
    if (touched) await _box?.put('pref_history', _history);
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _box?.delete('pref_history');
    changed.value++;
  }

  final ValueNotifier<int> changed = ValueNotifier<int>(0);

  Future<void> init(Box box) async {
    _box = box;
    _autoLine = box.get('pref_autoLine') as bool? ?? true;
    _preferHevc = box.get('pref_preferHevc') as bool? ?? false;
    _swipeEp = box.get('pref_swipeEp') as bool? ?? true;
    _muteOnStartup = box.get('pref_muteOnStartup') as bool? ?? true;
    _volume = (box.get('pref_volume') as num?)?.toDouble() ?? 0.7;
    _appearance = box.get('pref_appearance') as String? ?? 'system';
    _strictSecurity = box.get('pref_strictSecurity') as bool? ?? false;
    _searchHist =
        (box.get('pref_searchHist') as List?)?.cast<String>().toList() ?? [];
    _lineBase = box.get('pref_lineBase') as String? ?? '';
    _proxyMode = box.get('pref_proxyMode') as String? ?? 'system';
    if (!['system', 'custom', 'off'].contains(_proxyMode)) _proxyMode = 'system';
    _proxyUrl = box.get('pref_proxyUrl') as String? ?? '';
    _playbackLog = box.get('pref_playbackLog') as bool? ?? false;
    _favs = (box.get('pref_favs') as List?)?.cast<int>().toList() ?? [];
    final historyRaw = box.get('pref_history');
    if (historyRaw is Map) {
      _history
        ..clear()
        ..addAll({
          for (final e in historyRaw.entries)
            if (e.value is Map)
              e.key.toString():
                  Map<String, dynamic>.from(e.value as Map),
        });
    }
  }

  Future<void> setAutoLine(bool v) async {
    if (_autoLine == v) return;
    _autoLine = v;
    await _box?.put('pref_autoLine', v);
    changed.value++;
  }

  Future<void> setPreferHevc(bool v) async {
    if (_preferHevc == v) return;
    _preferHevc = v;
    await _box?.put('pref_preferHevc', v);
    changed.value++;
  }

  Future<void> setSwipeEp(bool v) async {
    if (_swipeEp == v) return;
    _swipeEp = v;
    await _box?.put('pref_swipeEp', v);
    changed.value++;
  }

  Future<void> setMuteOnStartup(bool v) async {
    _muteOnStartup = v;
    await _box?.put('pref_muteOnStartup', v);
    changed.value++;
  }

  Future<void> setVolume(double v) async {
    v = v.clamp(0.0, 1.0);
    _volume = v;
    await _box?.put('pref_volume', v);
    changed.value++;
  }

  Future<void> setAppearance(String v) async {
    if (_appearance == v) return;
    _appearance = v;
    await _box?.put('pref_appearance', v);
    changed.value++;
  }

  Future<void> setStrictSecurity(bool v) async {
    _strictSecurity = v;
    await _box?.put('pref_strictSecurity', v);
    changed.value++;
  }

  Future<void> addSearchHist(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    _searchHist
      ..remove(query)
      ..insert(0, query);
    if (_searchHist.length > 20) _searchHist.length = 20;
    await _box?.put('pref_searchHist', _searchHist);
    changed.value++;
  }

  Future<void> clearSearchHist() async {
    _searchHist.clear();
    await _box?.delete('pref_searchHist');
    changed.value++;
  }

  Future<void> setLineBase(String base) async {
    if (_lineBase == base) return;
    _lineBase = base;
    await _box?.put('pref_lineBase', base);
    changed.value++;
  }

  Future<void> setProxy(String mode, String url) async {
    _proxyMode = mode;
    _proxyUrl = mode == 'custom' ? url : _proxyUrl;
    await _box?.put('pref_proxyMode', mode);
    await _box?.put('pref_proxyUrl', _proxyUrl);
    changed.value++;
  }

  Future<void> setPlaybackLog(bool v) async {
    if (_playbackLog == v) return;
    _playbackLog = v;
    await _box?.put('pref_playbackLog', v);
    changed.value++;
  }
}

class HgStore {
  HgStore._();

  static Box? _box;
  static final HgSession session = HgSession();
  static final HgPrefs prefs = HgPrefs._();

  /// 彩蛋解锁标记（连点「关于」3 次后置 true，底栏出现入口）。
  ///
  /// 底栏 [_ScaffoldMenu] 不在关于页的 widget 子树里，解锁后靠这个
  /// notifier 把变化推过去立即重建；初始值在 init() 里回填。
  static bool _unlocked = false;
  static final ValueNotifier<bool> unlockedNotifier = ValueNotifier<bool>(false);
  static bool get unlocked => _unlocked;

  static Future<void> init() async {
    _box = await Hive.openBox('hg');
    await prefs.init(_box!);
    final origin = _box!.get('session_origin') as String? ?? '';
    final token = _box!.get('session_token') as String? ?? '';
    final userRaw = _box!.get('session_user');
    _unlocked = _box!.get('unlocked') as bool? ?? false;
    unlockedNotifier.value = _unlocked;
    if (token.isNotEmpty && origin.isNotEmpty) {
      session
        ..origin = origin
        ..token = token
        ..user = userRaw is Map
            ? HgUser.fromJson(Map<String, dynamic>.from(userRaw))
            : null;
    }
  }

  static Future<void> setSession(String origin, String token, HgUser? user) async {
    session
      ..origin = origin
      ..token = token
      ..user = user;
    await _box?.put('session_origin', origin);
    await _box?.put('session_token', token);
    await _box?.put(
      'session_user',
      user == null ? null : jsonDecode(jsonEncode(user.toJson())),
    );
  }

  static Future<void> clearSession() async {
    session
      ..origin = ''
      ..token = ''
      ..user = null;
    await _box?.delete('session_origin');
    await _box?.delete('session_token');
    await _box?.delete('session_user');
  }

  static Future<void> unlock() async {
    _unlocked = true;
    unlockedNotifier.value = true;
    await _box?.put('unlocked', true);
  }

  /// 重新隐藏入口（关于标题再连点 3 次）：只隐藏，登录/片库等数据保留。
  static Future<void> lock() async {
    _unlocked = false;
    unlockedNotifier.value = false;
    await _box?.put('unlocked', false);
  }
}
