// 一起看两条新协议的纯逻辑探针。
//
// 这两个协议都是「借聊天通道发内部信令」：反应会被直接画到别人屏幕上，
// 倒计时会让所有人同时起播。解析一旦放水，房间里任何人就能往你画面上塞
// 任意文字，或者让你永远在倒数。所以边界必须逐条咬住。
//
// 跑法：
//   dart tool/syncplay_protocol_probe.dart \
//     --packages=.dart_tool/package_config.json
import 'package:XL/services/player/syncplay_countdown.dart';
import 'package:XL/services/player/syncplay_drift.dart';
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/syncplay_reaction.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';

int _passed = 0;
final List<String> _failures = <String>[];

void _check(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failures.add(name);
  }
}

void main() {
  _probeReaction();
  _probeCountdown();
  _probeNoCollision();
  _probeDrift();
  _probeRoomSignals();

  if (_failures.isEmpty) {
    print('OK: $_passed checks passed');
    return;
  }
  print('FAILED: ${_failures.length} of ${_passed + _failures.length}');
  for (final String failure in _failures) {
    print('  - $failure');
  }
}

void _probeReaction() {
  // 编码 / 解码往返
  for (final String emoji in SyncPlayReaction.palette) {
    final String encoded = SyncPlayReaction.encode(emoji);
    _check('encode($emoji) 带前缀', SyncPlayReaction.isReaction(encoded));
    _check('encode($emoji) 能解回', SyncPlayReaction.tryParse(encoded) == emoji);
    _check(
      'encode($emoji) 不超过 150 字符',
      encoded.length <= 150,
    );
  }

  // 非白名单内容一律拒绝：这是防止别人往你屏幕上塞字的唯一一道闸。
  _check(
    '未知 emoji 被拒',
    SyncPlayReaction.tryParse('${SyncPlayReaction.prefix}🍉') == null,
  );
  _check(
    '空内容被拒',
    SyncPlayReaction.tryParse(SyncPlayReaction.prefix) == null,
  );
  _check(
    '只有空白被拒',
    SyncPlayReaction.tryParse('${SyncPlayReaction.prefix}   ') == null,
  );
  _check(
    '拼接长文本被拒',
    SyncPlayReaction.tryParse('${SyncPlayReaction.prefix}😂 快来 http://x') ==
        null,
  );
  _check(
    '两个 emoji 拼接被拒',
    SyncPlayReaction.tryParse('${SyncPlayReaction.prefix}😂😂') == null,
  );

  // 普通聊天不能被误判成反应
  _check('普通聊天不算反应', !SyncPlayReaction.isReaction('大家好'));
  _check('播放请求不算反应', !SyncPlayReaction.isReaction('XLPLAY1|a/1/1|x'));
  _check('普通聊天解析为 null', SyncPlayReaction.tryParse('😂') == null);
  _check(
    '前缀大小写敏感',
    SyncPlayReaction.tryParse('xlr1|😂') == null,
  );

  // 白名单本身
  _check('调色板非空', SyncPlayReaction.palette.isNotEmpty);
  _check(
    '调色板无重复',
    SyncPlayReaction.palette.toSet().length ==
        SyncPlayReaction.palette.length,
  );
}

void _probeCountdown() {
  for (int seconds = 2; seconds <= 10; seconds++) {
    final String encoded = SyncPlayCountdown.encode(seconds);
    _check('countdown($seconds) 带前缀', SyncPlayCountdown.isCountdown(encoded));
    _check(
      'countdown($seconds) 能解回',
      SyncPlayCountdown.tryParse(encoded) == seconds,
    );
  }

  // 越界要夹住而不是原样发出去：发 0 秒等于没倒数，发 600 秒就是让人干等。
  _check('0 秒被夹到下限', SyncPlayCountdown.tryParse(
        SyncPlayCountdown.encode(0),
      ) ==
      SyncPlayCountdown.minSeconds);
  _check('负数被夹到下限', SyncPlayCountdown.tryParse(
        SyncPlayCountdown.encode(-5),
      ) ==
      SyncPlayCountdown.minSeconds);
  _check('超大值被夹到上限', SyncPlayCountdown.tryParse(
        SyncPlayCountdown.encode(600),
      ) ==
      SyncPlayCountdown.maxSeconds);

  // 手搓的越界消息（不是自己 encode 出来的）必须拒掉
  _check(
    '收到 1 秒被拒',
    SyncPlayCountdown.tryParse('${SyncPlayCountdown.prefix}1') == null,
  );
  _check(
    '收到 99 秒被拒',
    SyncPlayCountdown.tryParse('${SyncPlayCountdown.prefix}99') == null,
  );
  _check(
    '非数字被拒',
    SyncPlayCountdown.tryParse('${SyncPlayCountdown.prefix}abc') == null,
  );
  _check(
    '空内容被拒',
    SyncPlayCountdown.tryParse(SyncPlayCountdown.prefix) == null,
  );
  _check(
    '浮点被拒',
    SyncPlayCountdown.tryParse('${SyncPlayCountdown.prefix}3.5') == null,
  );
  _check(
    '带尾巴被拒',
    SyncPlayCountdown.tryParse('${SyncPlayCountdown.prefix}3x') == null,
  );
  _check('普通聊天不算倒计时', !SyncPlayCountdown.isCountdown('3'));
}

/// 三条协议共用同一条聊天通道，前缀必须互不前缀包含，否则一种消息会被
/// 另一种先截走。
void _probeNoCollision() {
  const String play = SyncPlayPlayRequest.prefix;
  const String reaction = SyncPlayReaction.prefix;
  const String countdown = SyncPlayCountdown.prefix;
  const String sticker = SyncPlayStickerMessage.prefix;
  final List<String> prefixes = <String>[
    play,
    reaction,
    countdown,
    sticker,
    SyncPlayPin.prefix,
    SyncPlayNudge.prefix,
  ];
  for (final String a in prefixes) {
    for (final String b in prefixes) {
      if (a == b) continue;
      _check('$a 不以 $b 开头', !a.startsWith(b));
    }
  }
  _check(
    '反应不会被当成播放请求',
    !play.startsWith(reaction) && !reaction.startsWith(play),
  );
  _check(
    '倒计时不会被当成反应',
    SyncPlayReaction.tryParse('${SyncPlayCountdown.prefix}3') == null,
  );
  _check(
    '反应不会被当成倒计时',
    SyncPlayCountdown.tryParse('${SyncPlayReaction.prefix}😂') == null,
  );
  _check(
    '表情包不会被当成反应',
    SyncPlayReaction.tryParse('${SyncPlayStickerMessage.prefix}a/b') == null,
  );
  _check(
    '反应不会被当成表情包',
    !SyncPlayStickerMessage.isSticker('${SyncPlayReaction.prefix}😂'),
  );
}

/// 置顶公告与敲一敲。
void _probeRoomSignals() {
  // 公告往返
  _check(
    '公告往返',
    SyncPlayPin.tryParse(SyncPlayPin.encode('今晚看 1-3 集')) == '今晚看 1-3 集',
  );
  // 换行压成空格：一行公告被撑成一块会把房间卡顶得很难看
  _check(
    '换行被压平',
    SyncPlayPin.tryParse(SyncPlayPin.encode('第一行\n第二行')) == '第一行 第二行',
  );
  _check(
    '首尾空白被去掉',
    SyncPlayPin.tryParse(SyncPlayPin.encode('   公告   ')) == '公告',
  );
  // 超长要截断，不能把服务端 150 字符的上限撑爆
  final String long = 'A' * 300;
  final String? truncated = SyncPlayPin.tryParse(SyncPlayPin.encode(long));
  _check('超长公告被截断', truncated != null && truncated.length == SyncPlayPin.maxLength);
  _check(
    '截断后的整条消息不超 150 字符',
    SyncPlayPin.encode(long).length <= 150,
  );
  // 空公告 = 取消置顶：isPin 要认，tryParse 要返回 null
  _check('空公告算本协议', SyncPlayPin.isPin(SyncPlayPin.prefix));
  _check('空公告解析为 null', SyncPlayPin.tryParse(SyncPlayPin.prefix) == null);
  _check(
    '只有空白的公告也算取消',
    SyncPlayPin.tryParse('${SyncPlayPin.prefix}   ') == null,
  );
  _check('普通聊天不是公告', !SyncPlayPin.isPin('今晚看什么'));

  // 敲一敲
  _check('敲一敲往返', SyncPlayNudge.tryParse(SyncPlayNudge.encode('Alice')) == 'Alice');
  _check('敲一敲去掉空白', SyncPlayNudge.tryParse(SyncPlayNudge.encode(' Bob ')) == 'Bob');
  _check(
    '空目标被拒',
    SyncPlayNudge.tryParse(SyncPlayNudge.prefix) == null,
  );
  _check(
    '超长目标被拒',
    SyncPlayNudge.tryParse(
          '${SyncPlayNudge.prefix}${'x' * (SyncPlayNudge.maxNameLength + 1)}',
        ) ==
        null,
  );
  // 名字里出现分隔符说明这条消息是拼出来的，不能当合法目标
  _check(
    '含竖线的目标被拒',
    SyncPlayNudge.tryParse('${SyncPlayNudge.prefix}a|b') == null,
  );
  _check('普通聊天不是敲一敲', !SyncPlayNudge.isNudge('敲一下'));
  // 两条新协议不能互相误判
  _check(
    '公告不会被当成敲一敲',
    SyncPlayNudge.tryParse('${SyncPlayPin.prefix}公告') == null,
  );
  _check(
    '敲一敲不会被当成公告',
    SyncPlayPin.tryParse('${SyncPlayNudge.prefix}Alice') == null,
  );
}

/// 「我落后多少」的符号与聚合方式。
void _probeDrift() {
  Duration d(int ms) => Duration(milliseconds: ms);

  // 房间里只有自己
  _check(
    '没有别人时返回 null',
    syncPlayDriftBehind(self: d(1000), othersSeconds: const <double?>[]) ==
        null,
  );
  _check(
    '别人位置全为空时返回 null',
    syncPlayDriftBehind(
          self: d(1000),
          othersSeconds: const <double?>[null, null],
        ) ==
        null,
  );

  // 符号方向：别人在 10 秒，我在 8 秒 → 我落后 2 秒（正数）
  final Duration behind = syncPlayDriftBehind(
    self: d(8000),
    othersSeconds: const <double?>[10.0],
  )!;
  _check('落后为正数', behind.inMilliseconds == 2000);
  _check('落后不算负', !behind.isNegative);

  // 我在 12 秒，别人 10 秒 → 我超前 2 秒（负数）
  final Duration ahead = syncPlayDriftBehind(
    self: d(12000),
    othersSeconds: const <double?>[10.0],
  )!;
  _check('超前为负数', ahead.inMilliseconds == -2000);
  _check('超前是负的', ahead.isNegative);

  // 完全同步
  _check(
    '同步时为零',
    syncPlayDriftBehind(
          self: d(5000),
          othersSeconds: const <double?>[5.0],
        )!
            .inMilliseconds ==
        0,
  );

  // 中位数：一个人停在 0 秒（刚进房），另外两个在 100 秒 → 中位数 100，
  // 平均值会算成 66.7，那样「落后」会被凭空缩小三分之一。
  final Duration medianCase = syncPlayDriftBehind(
    self: d(100000),
    othersSeconds: const <double?>[0.0, 100.0, 100.0],
  )!;
  _check('取中位数而不是平均值', medianCase.inMilliseconds == 0);

  // 乱序输入也要取到正确的中位数
  _check(
    '乱序输入结果一致',
    syncPlayDriftBehind(
          self: d(10000),
          othersSeconds: const <double?>[30.0, 10.0, 20.0],
        )!
            .inMilliseconds ==
        10000,
  );

  // 非法值要过滤掉，不能把 NaN/Infinity 带进排序
  _check(
    'NaN 与 Infinity 被过滤',
    syncPlayDriftBehind(
          self: d(4000),
          othersSeconds: const <double?>[double.nan, double.infinity, 6.0],
        )!
            .inMilliseconds ==
        2000,
  );
}
