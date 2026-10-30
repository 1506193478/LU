/// 弹幕热力：把「哪一段最热闹」算成一条密度条，顺便挑出本集的高能时刻。
///
/// 数据就在本地（弹幕按秒存成 `Map<int, List<DanmakuEntry>>`），不用联网、
/// 不用额外依赖，纯计算。所以这里全是纯函数，方便 `dart tool/...` 自检。
library;

/// 一个高能时刻：某段时间里弹幕最密。
class DanmakuHotspot {
  const DanmakuHotspot({
    required this.position,
    required this.count,
  });

  /// 跳到哪（取窗口中心，落在这个窗口里最不容易跳过头）。
  final Duration position;

  /// 这个窗口里有多少条弹幕。
  final int count;
}

class DanmakuHeatmap {
  const DanmakuHeatmap._();

  /// 把弹幕时间点压成 [buckets] 根柱子，值归一化到 0~1。
  ///
  /// - 没有弹幕、时长未知 → 返回空列表（界面据此整条隐藏）；
  /// - 超出时长的弹幕（时间轴偏移没设对）直接丢掉，不然后面几根柱子会虚高。
  static List<double> densities({
    required Iterable<int> seconds,
    required int durationSeconds,
    int buckets = 96,
  }) {
    if (durationSeconds <= 0 || buckets <= 0) {
      return const <double>[];
    }
    final List<int> counts = List<int>.filled(buckets, 0);
    int max = 0;
    for (final int second in seconds) {
      if (second < 0 || second >= durationSeconds) {
        continue;
      }
      final int index = (second * buckets ~/ durationSeconds).clamp(0, buckets - 1);
      final int next = counts[index] + 1;
      counts[index] = next;
      if (next > max) {
        max = next;
      }
    }
    if (max == 0) {
      return List<double>.filled(buckets, 0);
    }
    return <double>[for (final int c in counts) c / max];
  }

  /// 挑出最热闹的 [count] 段，互不重叠。
  ///
  /// 用滑动窗口而不是直接取峰值那一秒：单秒爆 30 条可能是有人刷屏，
  /// 二十秒里持续有弹幕才是真的「名场面」。
  static List<DanmakuHotspot> hotspots({
    required Iterable<int> seconds,
    required int durationSeconds,
    int count = 3,
    int windowSeconds = 20,
  }) {
    if (durationSeconds <= 0 || count <= 0 || windowSeconds <= 0) {
      return const <DanmakuHotspot>[];
    }
    final List<int> perSecond = List<int>.filled(durationSeconds, 0);
    for (final int second in seconds) {
      if (second < 0 || second >= durationSeconds) {
        continue;
      }
      perSecond[second]++;
    }
    final List<DanmakuHotspot> result = <DanmakuHotspot>[];
    // 已经挑走的窗口，避免三个高能时刻全挤在同一段。
    final List<bool> taken = List<bool>.filled(durationSeconds, false);
    for (int i = 0; i < count; i++) {
      int bestStart = -1;
      int bestSum = 0;
      for (int start = 0; start < durationSeconds; start += 1) {
        if (taken[start]) {
          continue;
        }
        int sum = 0;
        final int end = (start + windowSeconds).clamp(0, durationSeconds);
        for (int s = start; s < end; s++) {
          sum += perSecond[s];
        }
        if (sum > bestSum) {
          bestSum = sum;
          bestStart = start;
        }
      }
      if (bestStart < 0 || bestSum == 0) {
        break;
      }
      final int center =
          (bestStart + windowSeconds ~/ 2).clamp(0, durationSeconds - 1);
      result.add(DanmakuHotspot(
        position: Duration(seconds: center),
        count: bestSum,
      ));
      // 把所有和这一段重叠的窗口起点都标记掉。
      //
      // 范围是 [start - window + 1, start + window - 1]：任何起点落在这个区间
      // 里的窗口都会和刚挑走的那段有交集。之前只往前留半个窗口，结果第二段
      // 贴着第一段的左边缘又挑了一次（60 秒那段挑完，第二段挑到 49 秒）。
      final int from =
          (bestStart - windowSeconds + 1).clamp(0, durationSeconds - 1);
      final int to =
          (bestStart + windowSeconds - 1).clamp(0, durationSeconds - 1);
      for (int s = from; s <= to; s++) {
        taken[s] = true;
      }
    }
    return result;
  }
}
