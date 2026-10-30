import 'package:XL/modules/history/history_module.dart';

/// 年报的一条原始记录：某天看了某部番的某一集，看到多少。
///
/// 刻意不直接用 [History]：那是 Hive 模型，构造起来要一堆字段，
/// 也没法在纯 Dart 探针里跑。这里只留聚合真正用得上的东西。
class WatchReportRecord {
  const WatchReportRecord({
    required this.bangumiId,
    required this.name,
    required this.coverUrl,
    required this.episode,
    required this.progress,
    required this.watchedAt,
  });

  final int bangumiId;
  final String name;
  final String coverUrl;
  final int episode;
  final Duration progress;
  final DateTime watchedAt;
}

/// 某部番在报告期内的成绩。
class WatchReportEntry {
  const WatchReportEntry({
    required this.bangumiId,
    required this.name,
    required this.coverUrl,
    required this.episodeCount,
    required this.progress,
  });

  final int bangumiId;
  final String name;
  final String coverUrl;
  final int episodeCount;
  final Duration progress;
}

/// 观看年报：把历史记录聚合成能看的数字。
///
/// 口径说明（页面上也要这么写，别让人误会）：
/// - 「集数」是去重后的 (番剧, 集号) 对，换线路、在线/离线各记一次不算两集；
/// - 「累计进度」是每集最后看到的位置之和，不是真实观看时长 —— 拖到片尾
///   也算一整集，这个数只会偏大不会偏小。
class WatchReport {
  const WatchReport({
    required this.year,
    required this.bangumiCount,
    required this.episodeCount,
    required this.totalProgress,
    required this.activeDays,
    required this.longestStreak,
    required this.hourly,
    required this.topBangumi,
    required this.firstDay,
    required this.lastDay,
  });

  /// 0 表示「全部时间」。
  final int year;

  final int bangumiCount;
  final int episodeCount;
  final Duration totalProgress;

  /// 有观看记录的天数。
  final int activeDays;

  /// 最长连续追番天数。
  final int longestStreak;

  /// 24 个小时的观看次数分布（用每集最后更新时间近似）。
  final List<int> hourly;

  final List<WatchReportEntry> topBangumi;

  final DateTime? firstDay;
  final DateTime? lastDay;

  bool get isEmpty => episodeCount == 0;

  /// 最活跃的那个小时；没有记录时返回 -1。
  int get busiestHour {
    int best = -1;
    int bestValue = 0;
    for (int i = 0; i < hourly.length; i++) {
      if (hourly[i] > bestValue) {
        bestValue = hourly[i];
        best = i;
      }
    }
    return best;
  }

  /// 从历史记录摊平成原始记录。
  static List<WatchReportRecord> recordsFromHistories(
    List<History> histories,
  ) {
    final List<WatchReportRecord> records = <WatchReportRecord>[];
    for (final History history in histories) {
      if (history.progresses.isEmpty) {
        continue;
      }
      final String name = history.bangumiItem.nameCn.trim().isNotEmpty
          ? history.bangumiItem.nameCn
          : history.bangumiItem.name;
      final String cover = history.bangumiItem.images['large'] ??
          history.bangumiItem.images['common'] ??
          '';
      for (final MapEntry<int, Progress> entry
          in history.progresses.entries) {
        final Progress progress = entry.value;
        // updatedAtMs 是后来才加的字段，老记录是 0，退回这条历史的最后观看时间。
        final DateTime watchedAt = progress.updatedAtMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(progress.updatedAtMs)
            : history.lastWatchTime;
        records.add(WatchReportRecord(
          bangumiId: history.bangumiItem.id,
          name: name,
          coverUrl: cover,
          episode: entry.key,
          progress: progress.progress,
          watchedAt: watchedAt,
        ));
      }
    }
    return records;
  }

  /// 有记录的所有年份，从新到旧。
  static List<int> availableYears(List<WatchReportRecord> records) {
    final Set<int> years = <int>{
      for (final WatchReportRecord record in records) record.watchedAt.year,
    };
    final List<int> sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  static WatchReport from({
    required List<WatchReportRecord> records,
    required int year,
  }) {
    // 同一集在换线路 / 在线离线之间会有多条，按 (番剧, 集) 去重取「看到最多」的那条。
    final Map<String, WatchReportRecord> unique = <String, WatchReportRecord>{};
    for (final WatchReportRecord record in records) {
      if (year > 0 && record.watchedAt.year != year) {
        continue;
      }
      final String key = '${record.bangumiId}#${record.episode}';
      final WatchReportRecord? existing = unique[key];
      if (existing == null || record.progress > existing.progress) {
        unique[key] = record;
      }
    }

    final List<int> hourly = List<int>.filled(24, 0);
    final Set<DateTime> days = <DateTime>{};
    final Map<int, _Aggregate> byBangumi = <int, _Aggregate>{};
    Duration total = Duration.zero;

    for (final WatchReportRecord record in unique.values) {
      hourly[record.watchedAt.hour.clamp(0, 23)]++;
      days.add(DateTime(
        record.watchedAt.year,
        record.watchedAt.month,
        record.watchedAt.day,
      ));
      total += record.progress;
      final _Aggregate aggregate = byBangumi.putIfAbsent(
        record.bangumiId,
        () => _Aggregate(
          name: record.name,
          coverUrl: record.coverUrl,
        ),
      );
      aggregate.episodeCount++;
      aggregate.progress += record.progress;
    }

    final List<WatchReportEntry> top = <WatchReportEntry>[
      for (final MapEntry<int, _Aggregate> entry in byBangumi.entries)
        WatchReportEntry(
          bangumiId: entry.key,
          name: entry.value.name,
          coverUrl: entry.value.coverUrl,
          episodeCount: entry.value.episodeCount,
          progress: entry.value.progress,
        ),
    ]..sort((a, b) {
        final int byEpisode = b.episodeCount.compareTo(a.episodeCount);
        if (byEpisode != 0) return byEpisode;
        return b.progress.compareTo(a.progress);
      });

    final List<DateTime> sortedDays = days.toList()..sort();

    return WatchReport(
      year: year,
      bangumiCount: byBangumi.length,
      episodeCount: unique.length,
      totalProgress: total,
      activeDays: days.length,
      longestStreak: _longestStreak(sortedDays),
      hourly: hourly,
      topBangumi: top.length > 5 ? top.sublist(0, 5) : top,
      firstDay: sortedDays.isEmpty ? null : sortedDays.first,
      lastDay: sortedDays.isEmpty ? null : sortedDays.last,
    );
  }

  /// 最长连续天数。按天去重后扫一遍，差一天就接上。
  static int _longestStreak(List<DateTime> sortedDays) {
    if (sortedDays.isEmpty) {
      return 0;
    }
    int best = 1;
    int current = 1;
    for (int i = 1; i < sortedDays.length; i++) {
      final int gap =
          sortedDays[i].difference(sortedDays[i - 1]).inDays;
      if (gap == 1) {
        current++;
      } else if (gap > 1) {
        current = 1;
      }
      if (current > best) {
        best = current;
      }
    }
    return best;
  }
}

class _Aggregate {
  _Aggregate({required this.name, required this.coverUrl});

  final String name;
  final String coverUrl;
  int episodeCount = 0;
  Duration progress = Duration.zero;
}
