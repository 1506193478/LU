/// 「一起看」的 3-2-1 开场倒计时信令。
///
/// 房主点「开始一起看」时先广播一条 `XLC1|<秒>`，房间里所有人各自倒数完
/// 再起播，把「各自 seek 到同一 position」造成的 1~2 秒错位压掉。
///
/// 为什么不用绝对时间戳：服务端时间是别人说了算的，客户端时钟还可能偏出
/// 几十秒。传「倒数几秒」让每个客户端按自己的时钟数，误差只剩单程网络延迟
/// （几十毫秒），比对齐绝对时间可靠得多。
class SyncPlayCountdown {
  const SyncPlayCountdown._();

  static const String prefix = 'XLC1|';

  /// 允许的倒计时区间。太小没意义，太大就成了干等。
  static const int minSeconds = 2;
  static const int maxSeconds = 10;

  static String encode(int seconds) {
    final int clamped = seconds.clamp(minSeconds, maxSeconds);
    return '$prefix$clamped';
  }

  static bool isCountdown(String text) => text.startsWith(prefix);

  /// 不是本协议、或者秒数不在 [minSeconds]~[maxSeconds] 里时返回 null。
  static int? tryParse(String text) {
    if (!isCountdown(text)) {
      return null;
    }
    final int? seconds = int.tryParse(text.substring(prefix.length).trim());
    if (seconds == null || seconds < minSeconds || seconds > maxSeconds) {
      return null;
    }
    return seconds;
  }
}
