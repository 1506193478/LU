// 3.6.1 三个新协议 + 温和追帧策略的纯 Dart 自检。
//
// 跑法：dart --packages=.dart_tool/package_config.json tool/syncplay_catch_up_probe.dart
import 'package:XL/services/player/syncplay_catch_up.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';

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

bool _between(double value, double min, double max) =>
    value >= min - 1e-9 && value <= max + 1e-9;

void main() {
  // ---------------------------------------------------------- 温和追帧
  _check('偏差 500ms 不动', SyncPlayCatchUp.speedFactor(500), 1.0);
  _check('偏差 0 不动', SyncPlayCatchUp.speedFactor(0), 1.0);
  _check('800ms 不算需要追', SyncPlayCatchUp.needsCatchUp(800), true);
  _check('700ms 不追', SyncPlayCatchUp.needsCatchUp(700), false);
  _check('3000ms 还在追帧区间', SyncPlayCatchUp.needsCatchUp(3000), true);
  _check('3001ms 硬跳', SyncPlayCatchUp.needsHardSeek(3001), true);
  _check('3000ms 不硬跳', SyncPlayCatchUp.needsHardSeek(3000), false);
  _check('200ms 算追上了', SyncPlayCatchUp.isDone(200), true);
  _check('600ms 没追上', SyncPlayCatchUp.isDone(600), false);

  final double small = SyncPlayCatchUp.speedFactor(1000);
  final double large = SyncPlayCatchUp.speedFactor(3000);
  _check('落后 1 秒要加速', small > 1.0, true);
  _check('落后 1 秒不超过上限', small <= SyncPlayCatchUp.maxSpeed, true);
  _check('落后 3 秒给满', large, SyncPlayCatchUp.maxSpeed);
  _check('加速幅度不低于 2%', small >= 1.02, true);

  final double ahead = SyncPlayCatchUp.speedFactor(-2000);
  _check('超前要减速', ahead < 1.0, true);
  _check('减速不低过下限', ahead >= SyncPlayCatchUp.minSpeed, true);
  _check(
    '倍率永远在 [0.95, 1.06]',
    _between(ahead, SyncPlayCatchUp.minSpeed, SyncPlayCatchUp.maxSpeed) &&
        _between(large, SyncPlayCatchUp.minSpeed, SyncPlayCatchUp.maxSpeed),
    true,
  );

  // ---------------------------------------------------------- 等我一下
  _check('编码 30 秒', SyncPlayStall.encode(30), 'XLS1|30');
  _check('解析 30 秒', SyncPlayStall.tryParse('XLS1|30'), 30);
  _check('太短夹到 5', SyncPlayStall.tryParse('XLS1|1'), 5);
  _check('太长夹到 120', SyncPlayStall.tryParse('XLS1|999'), 120);
  _check('非数字返回 null', SyncPlayStall.tryParse('XLS1|abc'), null);
  _check('非本协议返回 null', SyncPlayStall.tryParse('XLP1|30'), null);

  // ------------------------------------------------------------ 投票
  _check(
    '两人房：1 同意 0 反对 通过',
    SyncPlayVote.isPassed(yes: 1, no: 0, totalMembers: 2),
    true,
  );
  _check(
    '两人房：1 同意 1 反对 不通过',
    SyncPlayVote.isPassed(yes: 1, no: 1, totalMembers: 2),
    false,
  );
  _check(
    '四人房：2 同意 1 反对 通过',
    SyncPlayVote.isPassed(yes: 2, no: 1, totalMembers: 4),
    true,
  );
  _check(
    '四人房：2 同意 2 反对 不通过',
    SyncPlayVote.isPassed(yes: 2, no: 2, totalMembers: 4),
    false,
  );
  _check(
    '四人房：1 同意 0 反对 不够',
    SyncPlayVote.isPassed(yes: 1, no: 0, totalMembers: 4),
    false,
  );
  _check(
    '没人同意永远不过',
    SyncPlayVote.isPassed(yes: 0, no: 0, totalMembers: 0),
    false,
  );

  final String voteText = SyncPlayVote.encode(
    id: 'alice#1700000000',
    kind: SyncPlayVoteKind.episode,
    value: 5,
    stance: 'start',
  );
  _check('投票编码', voteText, 'XLV1|alice#1700000000|e|5|start');
  final SyncPlayVoteMessage? parsed = SyncPlayVote.tryParse(voteText);
  _check('投票解析 id', parsed?.id, 'alice#1700000000');
  _check('投票解析类型', parsed?.kind, SyncPlayVoteKind.episode);
  _check('投票解析集数', parsed?.value, 5);
  _check('投票解析表态', parsed?.stance, 'start');
  _check(
    '非法表态被拒',
    SyncPlayVote.tryParse('XLV1|a|p|0|maybe'),
    null,
  );
  _check(
    '字段数不对被拒',
    SyncPlayVote.tryParse('XLV1|a|p|0'),
    null,
  );

  // ---------------------------------------------------------- 片源指纹
  _check(
    '片源编码',
    SyncPlaySourceTag.encode(pluginName: 'AGE', road: 1, roadName: '线路B'),
    'XLF1|AGE|1|线路B',
  );
  final SyncPlaySourceInfo? source =
      SyncPlaySourceTag.tryParse('XLF1|AGE|1|线路B');
  _check('片源解析插件', source?.pluginName, 'AGE');
  _check('片源解析线路', source?.road, 1);
  _check('片源解析线路名', source?.roadName, '线路B');
  _check(
    '名字里的竖线被清掉',
    SyncPlaySourceTag.tryParse(
      SyncPlaySourceTag.encode(pluginName: 'A|B', road: 0, roadName: 'x|y'),
    )?.pluginName,
    'A B',
  );
  _check(
    '超长名字被截断',
    SyncPlaySourceTag.tryParse(
      SyncPlaySourceTag.encode(
        pluginName: 'p' * 100,
        road: 0,
        roadName: 'r',
      ),
    )?.pluginName.length,
    SyncPlaySourceTag.maxNameLength,
  );

  // ------------------------------------------------ 前缀互不吞并
  const List<String> prefixes = <String>[
    SyncPlayPin.prefix,
    SyncPlayNudge.prefix,
    SyncPlayQueue.prefix,
    SyncPlayStall.prefix,
    SyncPlayVote.prefix,
    SyncPlaySourceTag.prefix,
  ];
  for (final String a in prefixes) {
    for (final String b in prefixes) {
      if (a == b) continue;
      _check('$a 不吞 $b', b.startsWith(a), false);
    }
  }

  // ignore: avoid_print
  print('通过 $_passed 项，失败 $_failed 项');
  if (_failed > 0) {
    throw StateError('有 $_failed 项没过');
  }
}
