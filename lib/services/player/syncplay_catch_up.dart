/// 温和追帧：偏差在 1~3 秒之间时用微调倍速悄悄追上，不硬跳。
///
/// 为什么不直接 seek：一起看时只要和房间差 1 秒就跳一下，网络一抖画面就顿，
/// 观感比「慢半拍」差得多。倍速追帧的成本几乎为零 —— 播放器已经设了
/// `af scaletempo2`，改速度不变调，1.06 倍听不出区别。
///
/// 全部是纯函数，方便用 `dart tool/syncplay_catch_up_probe.dart` 自检。
class SyncPlayCatchUp {
  const SyncPlayCatchUp._();

  /// 小于这个偏差不处理：正常抖动，越处理越乱。
  static const int ignoreBelowMs = 800;

  /// 超过这个偏差就别磨了，直接 seek。追帧一分钟不如跳一下。
  static const int hardSeekAboveMs = 3000;

  /// 追到这么近就算追上，恢复原速。
  static const int doneBelowMs = 400;

  /// 追帧时的最大倍速。再高就能听出来了。
  static const double maxSpeed = 1.06;

  /// 超前时最多放慢到多少。
  static const double minSpeed = 0.95;

  /// 一次追帧最多跑多久。防止一直追不上（比如对方也在拖）。
  static const Duration maxDuration = Duration(seconds: 25);

  /// 这个偏差该不该硬跳。
  static bool needsHardSeek(int driftMs) => driftMs.abs() > hardSeekAboveMs;

  /// 这个偏差该不该用倍速追。
  static bool needsCatchUp(int driftMs) =>
      driftMs.abs() >= ignoreBelowMs && driftMs.abs() <= hardSeekAboveMs;

  /// 追上了没有。
  static bool isDone(int driftMs) => driftMs.abs() <= doneBelowMs;

  /// 根据偏差给出「相对原速的倍率」。
  ///
  /// [driftMs] 正数表示自己落后（要加速），负数表示超前（要放慢）。
  ///
  /// 用「按 20 秒追平」折算，再夹到 [1.02, 1.06] / [0.95, 0.98]：
  /// - 差 0.8 秒 → 1.04（几乎看不出来）
  /// - 差 2 秒   → 1.06（能感觉到一点点，但不到半分钟就追平）
  /// 不按比例一路给满 1.06，是为了让「小漂移」尽量无感。
  static double speedFactor(int driftMs) {
    final int magnitude = driftMs.abs();
    if (magnitude < ignoreBelowMs) {
      return 1.0;
    }
    // 20 秒追平所需的倍率增量，夹在 2%~6% 之间。
    final double raw = magnitude / 20000.0;
    final double delta = raw.clamp(0.02, 0.06);
    if (driftMs > 0) {
      return 1.0 + delta;
    }
    // 超前时放慢的幅度略小一点：慢过头比快过头更容易被听出来。
    return 1.0 - delta.clamp(0.02, 0.05);
  }
}
