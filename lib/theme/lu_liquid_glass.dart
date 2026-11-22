import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// iOS 26 液态玻璃统一入口。
///
/// 工程里原有的 [LuGlass] 是「半透明底色 + 渐变 + 高光描边」的**假玻璃**：
/// 视觉接近但缺少真实折射、镜面高光和色散。本适配层用高星维护中的
/// `liquid_glass_widgets`（MIT，pub.dev 1.19.0）提供的 fragment shader
/// 玻璃替换控件层材质，保留全部业务布局与交互。
///
/// 遵守 Apple HIG：玻璃只用于**导航与控件层**（悬浮胶囊、工具条、弹层、
/// 分段控件、开关），不用于滚动内容卡片和视频画面。
class LuLiquidGlass {
  LuLiquidGlass._();

  /// 当前是否启用真玻璃。可在低端设备上一处关掉退回 [LuGlass]。
  /// 由全局 `LiquidGlassWidgets.wrap(adaptiveQuality: true)` 负责画质降级，
  /// 这里只控制「是否走 shader 玻璃」这条路。
  static bool enabled = true;

  /// 导航胶囊（底栏 / 二级 dock / 工具条）用的玻璃参数。
  /// 对齐 iOS 26 `glassEffect(.regular)`：近乎透明、强镜面边缘光、无边框。
  static LiquidGlassSettings chromeFor(BuildContext context) =>
      Theme.maybeBrightnessOf(context) == Brightness.dark
          ? LiquidGlassSettings.ios26Dark
          : LiquidGlassSettings.ios26Light;

  /// 浮层（菜单 / 弹窗 / HUD）用的玻璃参数：比导航稍厚一点，保证文字可读。
  static LiquidGlassSettings overlayFor(BuildContext context) =>
      Theme.maybeBrightnessOf(context) == Brightness.dark
          ? LiquidGlassSettings.ios26Dark.copyWith(
              thickness: 40,
              frostOpacity: .9,
            )
          : LiquidGlassSettings.ios26Light.copyWith(
              thickness: 40,
              frostOpacity: .9,
            );

  /// 胶囊 / 圆角矩形形状。
  static LiquidShape pill(double radius) =>
      LiquidRoundedSuperellipse(borderRadius: radius);

  /// 把任意控件包成一层真实液态玻璃。
  ///
  /// [radius] 圆角半径；[overlay] 选浮层厚玻璃，否则用导航薄玻璃；
  /// [interactive] 打开按压折射（按钮类）；[quality] 由调用点决定是否强制档位
  ///（默认交给全局自适应画质）。
  static Widget surface({
    required BuildContext context,
    required Widget child,
    required double radius,
    bool overlay = false,
    bool interactive = false,
    GlassQuality? quality,
    Key? key,
  }) {
    if (!enabled) return child;
    // 每次 build 从最近的 Theme 取明暗，切主题时玻璃颜色同步跟随。
    // App 内是暗色主题但系统亮色时，这里必须以 App 主题为准。
    return AdaptiveGlass(
      key: key,
      shape: pill(radius),
      settings: overlay
          ? LuLiquidGlass.overlayFor(context)
          : LuLiquidGlass.chromeFor(context),
      quality: quality ?? GlassQuality.standard,
      isInteractive: interactive,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
