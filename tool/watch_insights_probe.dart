// 弹幕热力 + 观看年报的纯逻辑自检。
//
// 跑法：dart --packages=.dart_tool/package_config.json tool/watch_insights_probe.dart
import 'package:XL/modules/my/watch_report.dart';
import 'package:XL/services/player/danmaku_heatmap.dart';

int _passed = 0;
int _failed = 0;

void _check(String name, Object? actual, Object? expected) {
  final String a = actual.toString();
  final String e = expected.toString();
  if (a == e) {
    _passed++;
  } else {
    _failed++;
    // ignore: avoid_print
    print('FAIL  $name\n      期望: $e\n      实际: $a');
  }
}

void main() {
  // ------------------------------------------------------------ 弹幕热力
  _check(
    '没有时长就没有柱子',
    DanmakuHeatmap.densities(seconds: <int>[1, 2], durationSeconds: 0).length,
    0,
  );
  _check(
    '没有弹幕也给出全零',
    DanmakuHeatmap.densities(
      seconds: const <int>[],
      durationSeconds: 100,
      buckets: 10,
    ).every((double v) => v == 0),
    true,
  );
  final List<double> bars = DanmakuHeatmap.densities(
    seconds: <int>[0, 0, 0, 50, 99],
    durationSeconds: 100,
    buckets: 10,
  );
  _check('柱子数量', bars.length, 10);
  _check('最密的那格是 1.0', bars[0], 1.0);
  _check('稀疏的格子有值', bars[5] > 0, true);
  _check(
    '超出时长的弹幕被丢掉',
    DanmakuHeatmap.densities(
      seconds: <int>[200],
      durationSeconds: 100,
      buckets: 10,
    ).every((double v) => v == 0),
    true,
  );

  // 第 60~80 秒最密，第 10 秒次之
  final List<int> dense = <int>[
    for (int i = 60; i < 80; i++) i,
    for (int i = 60; i < 80; i++) i,
    for (int i = 10; i < 20; i++) i,
  ];
  final List<DanmakuHotspot> spots = DanmakuHeatmap.hotspots(
    seconds: dense,
    durationSeconds: 300,
    count: 2,
    windowSeconds: 20,
  );
  _check('挑出两段', spots.length, 2);
  _check('第一段落在 60~80 之间', spots.first.position.inSeconds >= 60 &&
      spots.first.position.inSeconds <= 80, true);
  _check('第一段条数最多', spots.first.count, 40);
  _check(
    '两段不重叠',
    (spots.first.position - spots[1].position).inSeconds.abs() >= 20,
    true,
  );
  _check(
    '没有弹幕时没有高能时刻',
    DanmakuHeatmap.hotspots(
      seconds: const <int>[],
      durationSeconds: 100,
    ).isEmpty,
    true,
  );

  // ------------------------------------------------------------ 观看年报
  DateTime day(int y, int m, int d, [int hour = 21]) =>
      DateTime(y, m, d, hour);

  final List<WatchReportRecord> records = <WatchReportRecord>[
    // 同一集看了两次（换线路），应该只算一集，取进度大的那条
    WatchReportRecord(
      bangumiId: 1,
      name: '番A',
      coverUrl: '',
      episode: 1,
      progress: const Duration(minutes: 10),
      watchedAt: day(2026, 3, 1),
    ),
    WatchReportRecord(
      bangumiId: 1,
      name: '番A',
      coverUrl: '',
      episode: 1,
      progress: const Duration(minutes: 20),
      watchedAt: day(2026, 3, 1, 22),
    ),
    WatchReportRecord(
      bangumiId: 1,
      name: '番A',
      coverUrl: '',
      episode: 2,
      progress: const Duration(minutes: 24),
      watchedAt: day(2026, 3, 2),
    ),
    WatchReportRecord(
      bangumiId: 2,
      name: '番B',
      coverUrl: '',
      episode: 1,
      progress: const Duration(minutes: 5),
      watchedAt: day(2026, 3, 4, 9),
    ),
    WatchReportRecord(
      bangumiId: 3,
      name: '去年番',
      coverUrl: '',
      episode: 1,
      progress: const Duration(minutes: 5),
      watchedAt: day(2025, 12, 31),
    ),
  ];

  final WatchReport thisYear = WatchReport.from(records: records, year: 2026);
  _check('本年番剧数', thisYear.bangumiCount, 2);
  _check('本年集数（去重）', thisYear.episodeCount, 3);
  _check('累计进度取大的那条', thisYear.totalProgress.inMinutes, 20 + 24 + 5);
  _check('活跃天数', thisYear.activeDays, 3);
  _check('最长连续（3/1、3/2 两天）', thisYear.longestStreak, 2);
  _check('凌晨以外的时段有记录', thisYear.hourly[21] >= 1, true);
  _check('早上九点那一格', thisYear.hourly[9], 1);
  _check('TOP1 是番A', thisYear.topBangumi.first.name, '番A');
  _check('TOP1 集数', thisYear.topBangumi.first.episodeCount, 2);

  final WatchReport all = WatchReport.from(records: records, year: 0);
  _check('全部时间番剧数', all.bangumiCount, 3);
  _check('全部时间集数', all.episodeCount, 4);

  _check('可选年份', WatchReport.availableYears(records), '[2026, 2025]');
  _check(
    '空数据不炸',
    WatchReport.from(records: const <WatchReportRecord>[], year: 2026)
        .isEmpty,
    true,
  );
  // 21 / 22 / 9 各一集，并列时取最早的那个小时。
  _check(
    '并列时取最早的小时',
    thisYear.busiestHour,
    9,
  );

  // ignore: avoid_print
  print('通过 $_passed 项，失败 $_failed 项');
  if (_failed > 0) {
    throw StateError('有 $_failed 项没过');
  }
}
