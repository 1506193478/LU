import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 全局动效节奏。
///
/// 所有动画的时长与曲线都从这里取，避免各处各写一套（之前 120/200/300/350ms
/// 混着用，观感上就不"齐"）。改节奏只改这里。
abstract final class KazumiMotion {
  /// 按下/抬起这类需要"立刻有反应"的反馈。
  static const Duration instant = Duration(milliseconds: 90);

  /// 颜色、透明度这类不需要位移的变化。
  static const Duration fast = Duration(milliseconds: 160);

  /// 默认时长：小范围位移、缩放。
  static const Duration base = Duration(milliseconds: 240);

  /// 页面内的大块内容进出。
  static const Duration slow = Duration(milliseconds: 320);

  /// 跨页面的容器变换。
  static const Duration hero = Duration(milliseconds: 520);

  /// 强调曲线：起步快、收尾慢，用于位移。
  static const Curve emphasized = Cubic(0.2, 0.9, 0.2, 1.0);

  /// 轻微过冲，用于"弹一下"的反馈（导航指示器、按钮回弹）。
  static const Curve spring = Cubic(0.34, 1.42, 0.44, 1.0);

  /// 标准缓动，用于淡入淡出。
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// 系统开了"减少动态效果"时返回零时长，让动画直接到位。
  static Duration scale(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// 触感反馈的统一入口。
///
/// 只在手机上真的触发；桌面端 `HapticFeedback` 本来就没有实现，调了也只是
/// 走一趟 platform channel，所以直接短路掉。失败一律吞掉——震动不该影响功能。
abstract final class KazumiHaptics {
  /// 设置里关掉"触感反馈"时置 false。
  static bool enabled = true;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 轻点：选中项、切换 tab。
  static void select() => _fire(HapticFeedback.selectionClick);

  /// 普通按钮按下。
  static void tap() => _fire(HapticFeedback.lightImpact);

  /// 有结果的确认动作，比如开始播放、进入房间。
  static void success() => _fire(HapticFeedback.mediumImpact);

  static void _fire(Future<void> Function() action) {
    if (!enabled || !_supported) return;
    try {
      action();
    } catch (_) {
      // 部分机型/系统设置下会直接抛，忽略即可。
    }
  }
}
