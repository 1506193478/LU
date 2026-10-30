// 一起看播放队列协议的纯 Dart 自检。
//
// 跑法：dart --packages=.dart_tool/package_config.json tool/syncplay_queue_probe.dart
//
// 为什么不用 flutter test：沙箱里 reg.exe 被安全策略拉黑，跑 test 会触发
// native build hook 直接失败。这里只依赖纯 Dart 代码，能跑。
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

void main() {
  // ---- 编码 / 解析往返
  _check('空列表编码', SyncPlayQueue.encode(const <int>[]), 'XLQ1|');
  _check('单集编码', SyncPlayQueue.encode(<int>[3]), 'XLQ1|3');
  _check('多集编码', SyncPlayQueue.encode(<int>[3, 4, 5]), 'XLQ1|3,4,5');
  _check('往返', SyncPlayQueue.tryParse('XLQ1|3,4,5'), '[3, 4, 5]');

  // ---- 归一化：去重 / 丢非正数 / 保序 / 截断
  _check('去重保序', SyncPlayQueue.normalize(<int>[3, 1, 3, 2]), '[3, 1, 2]');
  _check('丢掉 0 和负数', SyncPlayQueue.normalize(<int>[0, -1, 2]), '[2]');
  _check(
    '截到上限',
    SyncPlayQueue.normalize(
      List<int>.generate(SyncPlayQueue.maxEntries + 5, (int i) => i + 1),
    ).length,
    SyncPlayQueue.maxEntries,
  );
  _check(
    '上限内的最后一项',
    SyncPlayQueue.normalize(
      List<int>.generate(SyncPlayQueue.maxEntries + 5, (int i) => i + 1),
    ).last,
    SyncPlayQueue.maxEntries,
  );

  // ---- 解析脏数据
  _check('非本协议', SyncPlayQueue.tryParse('XLPLAY1|3'), '[]');
  _check('空内容 = 清空', SyncPlayQueue.tryParse('XLQ1|'), '[]');
  _check('只有逗号', SyncPlayQueue.tryParse('XLQ1|,,,'), '[]');
  _check('混进非数字', SyncPlayQueue.tryParse('XLQ1|3,abc,5'), '[3, 5]');
  _check('负数被丢', SyncPlayQueue.tryParse('XLQ1|-2,4'), '[4]');
  _check('空格容忍', SyncPlayQueue.tryParse('XLQ1| 2 , 6 '), '[2, 6]');

  // ---- 前缀不能互相包含（撞车会截走别的消息）
  const List<String> prefixes = <String>[
    SyncPlayPin.prefix,
    SyncPlayNudge.prefix,
    SyncPlayQueue.prefix,
  ];
  for (final String a in prefixes) {
    for (final String b in prefixes) {
      if (a == b) continue;
      _check('$a 不吞 $b', b.startsWith(a), false);
    }
  }

  // ---- 队列消息不会被当成公告/敲一敲
  const String queueMessage = 'XLQ1|1,2';
  _check('队列不算公告', SyncPlayPin.isPin(queueMessage), false);
  _check('队列不算敲一敲', SyncPlayNudge.isNudge(queueMessage), false);

  // ---- 集数顺序映射（和 UI 里的 _episodeAt / _indexOfEpisode 同一套算式）
  List<int> orderOf(int count, bool descending) => descending
      ? List<int>.generate(count, (int i) => count - i)
      : List<int>.generate(count, (int i) => i + 1);
  _check('正序 12 集', orderOf(12, false).take(3), '(1, 2, 3)');
  _check('倒序 12 集', orderOf(12, true).take(3), '(12, 11, 10)');
  _check('倒序末项是第 1 集', orderOf(12, true).last, 1);
  _check('正序末项是最后一集', orderOf(12, false).last, 12);
  // 倒序时第 1 行是最后一集，定位当前集要能反算回去
  const int count = 12;
  const int current = 4;
  final int descIndex = count - current;
  _check('倒序定位下标', orderOf(count, true)[descIndex], current);
  _check('正序定位下标', orderOf(count, false)[current - 1], current);

  // ignore: avoid_print
  print('通过 $_passed 项，失败 $_failed 项');
  if (_failed > 0) {
    throw StateError('有 $_failed 项没过');
  }
}
