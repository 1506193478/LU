/// 一起看里「我落后多少」的算法。
///
/// 单独拎出来是因为这里很容易写反：`别人的进度 - 我的进度` 才是「落后」，
/// 反过来就变成「超前」，界面文案会整段反着显示。纯函数也方便写探针。
library;

/// 用房间里其他人的进度算出自己落后多少。
///
/// 正数 = 自己落后，负数 = 自己超前。没有任何可用的别人进度时返回 null
/// （房间里只有自己）。
///
/// 取**中位数**而不是平均值：有人刚进房还停在 0 秒、或者有人在拖进度条时，
/// 平均值会被一两个极端值拽偏，中位数不会。偶数个时取偏后那个，跟
/// 「房间里多数人在哪」这个直觉一致。
Duration? syncPlayDriftBehind({
  required Duration self,
  required Iterable<double?> othersSeconds,
}) {
  final List<double> valid = <double>[
    for (final double? seconds in othersSeconds)
      if (seconds != null && seconds.isFinite) seconds,
  ];
  if (valid.isEmpty) {
    return null;
  }
  valid.sort();
  final double median = valid[valid.length ~/ 2];
  return Duration(milliseconds: (median * 1000).round() - self.inMilliseconds);
}
