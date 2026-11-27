import 'dart:async';
import 'dart:convert';

import 'package:XL/services/storage/storage.dart';

/// 观看时长统计（本地）。
///
/// 播放器每 10 秒的进度 tick 里顺手记一笔：按「天」累计总时长，按「条目」
/// 累计观看时长与次数。数据只存设置盒里的一小块 JSON：
///   * `days`   — { 'yyyy-MM-dd': 毫秒 }，保留 90 天；
///   * `titles` — { key: {t, sub, ms, at, count} }，保留最近 100 条。
///
/// 不追求秒级精确（暂停时的 tick 会被跳过，退出前最后不足 10 秒的一段
/// 不计入），做趋势和榜单足够了。
class EmbyWatchStats {
  EmbyWatchStats._();

  static final EmbyWatchStats instance = EmbyWatchStats._();

  static const int _maxDays = 90;
  static const int _maxTitles = 100;

  static const _key = SettingKey<String>(
    'emby.watchStats',
    '',
    group: SettingGroup.emby,
  );

  Map<String, int> _days = {};
  Map<String, Map<String, dynamic>> _titles = {};
  bool _loaded = false;
  Timer? _flushTimer;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = GStorage.getSetting(_key);
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final days = decoded['days'];
      final titles = decoded['titles'];
      if (days is Map) {
        _days = days.map((k, v) => MapEntry('$k', (v as num).toInt()));
      }
      if (titles is Map) {
        _titles = titles.map(
          (k, v) => MapEntry(
            '$k',
            v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
          ),
        );
      }
    } catch (_) {
      _days = {};
      _titles = {};
    }
  }

  static String _dayKey(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }

  /// 播放器每 10 秒 tick 调一次：这一段（[deltaMs]，默认 10 秒）算在看。
  ///
  /// [key] 用观看记录同一个键（emby:serverId:itemId / src:直链），
  /// 这样统计和「播放列表」能对得上。
  void addTick({
    required String key,
    required String title,
    String subtitle = '',
    String genre = '',
    int deltaMs = 10000,
  }) {
    if (key.isEmpty || deltaMs <= 0) return;
    _ensureLoaded();
    final now = DateTime.now();
    final day = _dayKey(now);
    _days[day] = (_days[day] ?? 0) + deltaMs;
    _pruneDays();

    final entry = _titles[key] ?? <String, dynamic>{};
    entry['t'] = title;
    if (subtitle.isNotEmpty) entry['sub'] = subtitle;
    // 类型占比用：只留第一个类型就够了，多了占比图反而碎。
    // 旧记录没有这个字段，读取时归到「其它」，不用迁移。
    if (genre.isNotEmpty) entry['g'] = genre;
    entry['ms'] = ((entry['ms'] as num?)?.toInt() ?? 0) + deltaMs;
    entry['at'] = now.millisecondsSinceEpoch;
    entry['count'] = ((entry['count'] as num?)?.toInt() ?? 0) + 1;
    _titles[key] = entry;
    _pruneTitles();

    // 写盘别跟着 tick 每十秒一次：攒 30 秒（3 个 tick）合并刷一次。
    _flushTimer ??= Timer(const Duration(seconds: 30), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  void _pruneDays() {
    if (_days.length <= _maxDays) return;
    final keys = _days.keys.toList()..sort();
    for (final k in keys.take(_days.length - _maxDays)) {
      _days.remove(k);
    }
  }

  void _pruneTitles() {
    if (_titles.length <= _maxTitles) return;
    final sorted = _titles.entries.toList()
      ..sort((a, b) {
        final at = (a.value['at'] as num?)?.toInt() ?? 0;
        final bt = (b.value['at'] as num?)?.toInt() ?? 0;
        return bt.compareTo(at);
      });
    _titles = {
      for (final e in sorted.take(_maxTitles)) e.key: e.value,
    };
  }

  Future<void> _flush() async {
    try {
      await GStorage.putSetting(_key, jsonEncode(_toJson()));
    } catch (_) {
      // 统计写盘失败不影响播放。
    }
  }

  Map<String, dynamic> _toJson() => {'days': _days, 'titles': _titles};

  // ------------------------------------------------------------ 聚合

  /// 最近 [days] 天（含今天）的总观看时长，毫秒。
  int msInDays(int days) {
    _ensureLoaded();
    final now = DateTime.now();
    var sum = 0;
    for (var i = 0; i < days; i++) {
      sum += _days[_dayKey(now.subtract(Duration(days: i)))] ?? 0;
    }
    return sum;
  }

  int get todayMs => msInDays(1);

  /// 最近 [days] 天，每天的观看时长（旧→新，末尾是今天）。
  List<int> dailyMs(int days) {
    _ensureLoaded();
    final now = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        _days[_dayKey(now.subtract(Duration(days: i)))] ?? 0,
    ];
  }

  /// 类型占比：按累计观看时长聚合 [addTick] 记下的首个类型，
  /// 返回 (类型, 占比 0~1)，按占比倒序，最多 6 项。旧记录无类型时归「其它」。
  List<MapEntry<String, double>> genreShares() {
    _ensureLoaded();
    final byGenre = <String, int>{};
    var total = 0;
    for (final entry in _titles.values) {
      final ms = (entry['ms'] as num?)?.toInt() ?? 0;
      if (ms <= 0) continue;
      final genre = (entry['g'] as String?) ?? '其它';
      byGenre[genre] = (byGenre[genre] ?? 0) + ms;
      total += ms;
    }
    if (total <= 0) return const [];
    final sorted = byGenre.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).map((e) => MapEntry(e.key, e.value / total)).toList();
  }

  /// 热门内容，按累计时长倒序。返回 (key, data) 列表。
  List<MapEntry<String, Map<String, dynamic>>> topTitles({int limit = 50}) {
    _ensureLoaded();
    final entries = _titles.entries.toList()
      ..sort((a, b) {
        final am = (a.value['ms'] as num?)?.toInt() ?? 0;
        final bm = (b.value['ms'] as num?)?.toInt() ?? 0;
        return bm.compareTo(am);
      });
    return entries.take(limit).toList();
  }

  Future<void> clear() async {
    _ensureLoaded();
    _days = {};
    _titles = {};
    await GStorage.putSetting(_key, jsonEncode(_toJson()));
  }

  static String formatMs(int ms) {
    if (ms <= 0) return '0 分钟';
    final minutes = ms ~/ 60000;
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h < 24) return m > 0 ? '$h 小时 $m 分' : '$h 小时';
    final d = h ~/ 24;
    return '$d 天 ${h % 24} 小时';
  }
}
