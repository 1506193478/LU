import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/utils/constants.dart';

/// 内容沉浸型主题：深色为主、大圆角、去边框、弱化分割线。
///
/// 种子色只保留为强调色，所有承载内容的 surface 一律换成中性灰阶，
/// 让封面图成为页面里唯一的高饱和元素。
// Pv 作为唯一设计语言之后，全局页面底色就是 Pv 的 `--page`：
// 浅色 #F3F1F2 / 深色 #151417。原来这里是 #F5F6F8 / #0B0C0F，
// 和 Pv 卡片一对比就分得出两套底，切页时尤其明显。
const Color immersiveDarkScaffold = Color(0xFF151417);
const Color immersiveLightScaffold = Color(0xFFF3F1F2);

/// Pv 卡片底色（`--canvas`），跟 [PvColors.card] 是同一组值。
const Color immersiveDarkCard = Color(0xFF1F1E22);
const Color immersiveLightCard = Color(0xFFFFFFFF);

/// 默认强调色。
///
/// 深色底上偏冷的紫，和海报里常见的高饱和暖色区分得开，不会跟封面抢戏。
/// 想换主色只改这一处（设置里选"默认"时用的就是它）。
const Color kDefaultAccent = Color(0xFFB69CFF);

/// 粘土材质的两端颜色：左上受光偏亮，右下背光偏暗。
///
/// 粘土的体积感全靠这两个色拉开——差太小像塑料片，差太大像金属。
const Color clayLight = Color(0xFF262933);
const Color clayDark = Color(0xFF15171D);

/// 强调色粘土（主操作按钮）。
const Color clayAccentLight = Color(0xFFC6B0FF);
const Color clayAccentDark = Color(0xFF8B6DF0);

/// 卡片与容器的统一圆角。
const double immersiveRadius = 16;
const double immersiveRadiusLarge = 24;

/// 悬浮导航条的高度与离屏距离。
///
/// 页面底部留白要按 [immersiveTabBarInset] 算，不然内容会被导航条压住。
const double immersiveTabBarHeight = 62;

/// 导航条底边到「安全区上沿」的距离。
///
/// 原来给的是 14，加上 iPhone 的 34 底部安全区，整条离屏幕底 48 —— 视觉上
/// 飘在半空。收到 6 之后 iPhone 是 40、安卓手势导航是 30，都落回「浮起来但
/// 贴着底」的区间；三键导航（安全区 48）时这条会被压到 0，正好贴着按键栏，
/// 不会重叠。
const double immersiveTabBarGap = 6;

/// 底部导航条实际占掉的高度（含系统安全区）。
double immersiveTabBarInset(BuildContext context) =>
    immersiveTabBarHeight +
    immersiveTabBarGap +
    MediaQuery.paddingOf(context).bottom;

const BorderRadius immersiveBorderRadius = BorderRadius.all(
  Radius.circular(immersiveRadius),
);
const BorderRadius immersiveBorderRadiusLarge = BorderRadius.all(
  Radius.circular(immersiveRadiusLarge),
);

/// 深色模式的容器灰阶，从最底到最高逐层提亮。
const Color _darkSurface = Color(0xFF15171C);
const Color _darkSurfaceLowest = Color(0xFF0E1014);
const Color _darkSurfaceLow = Color(0xFF191B21);
const Color _darkSurfaceContainer = Color(0xFF1D1F26);
const Color _darkSurfaceHigh = Color(0xFF23252D);
const Color _darkSurfaceHighest = Color(0xFF2A2C34);
const Color _darkOutline = Color(0xFF2E3037);
const Color _darkOutlineVariant = Color(0xFF21232A);

/// 浅色模式的容器灰阶。
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _lightSurfaceLowest = Color(0xFFFFFFFF);
const Color _lightSurfaceLow = Color(0xFFF7F8FA);
const Color _lightSurfaceContainer = Color(0xFFF2F3F6);
const Color _lightSurfaceHigh = Color(0xFFECEEF2);
const Color _lightSurfaceHighest = Color(0xFFE4E7EC);
const Color _lightOutline = Color(0xFFD6D9DF);
const Color _lightOutlineVariant = Color(0xFFE6E8ED);

ColorScheme _immersiveColorScheme({
  required Brightness brightness,
  Color? color,
  ColorScheme? colorScheme,
}) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme seed =
      colorScheme ??
      ColorScheme.fromSeed(
        seedColor: color ?? kDefaultAccent,
        brightness: brightness,
      );
  return seed.copyWith(
    surface: dark ? _darkSurface : _lightSurface,
    surfaceContainerLowest: dark ? _darkSurfaceLowest : _lightSurfaceLowest,
    surfaceContainerLow: dark ? _darkSurfaceLow : _lightSurfaceLow,
    surfaceContainer: dark ? _darkSurfaceContainer : _lightSurfaceContainer,
    surfaceContainerHigh: dark ? _darkSurfaceHigh : _lightSurfaceHigh,
    surfaceContainerHighest: dark ? _darkSurfaceHighest : _lightSurfaceHighest,
    outline: dark ? _darkOutline : _lightOutline,
    outlineVariant: dark ? _darkOutlineVariant : _lightOutlineVariant,
    // 关闭 M3 的高程染色，避免容器被强调色污染。
    surfaceTint: Colors.transparent,
  );
}

/// 构建一个内容沉浸型主题。
///
/// [color] 与 [colorScheme] 与 [ThemeData] 的语义一致：后者优先。
ThemeData buildImmersiveTheme({
  required Brightness brightness,
  Color? color,
  ColorScheme? colorScheme,
  String? fontFamily,
}) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = _immersiveColorScheme(
    brightness: brightness,
    color: color,
    colorScheme: colorScheme,
  );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: brightness,
    colorScheme: scheme,
    progressIndicatorTheme: progressIndicatorTheme2024,
    sliderTheme: sliderTheme2024,
    pageTransitionsTheme: pageTransitionsTheme2024,
    // ---- iOS 交互层（全局一次生效） ----
    // Material 的水波纹在 iOS 上不存在：iOS 的按压反馈是「内容自己变暗」，
    // 涟漪一出来整页的交互语言就露馅了。这里全局关掉，onTap 行为不变，
    // 51 处 InkWell 不用逐个包。
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    // 但**不能连高亮也关掉**：上一版这里给了 transparent，结果点任何
    // InkWell 都毫无反馈——iOS 的按压反馈本来就是「内容自己变暗」，
    // 涟漪可以没有，变暗必须有。给一个比 iOS 原生（约 6%）略淡的值，
    // 既能感知到按下了，又不会让大面积卡片突然一变。
    highlightColor: scheme.onSurface.withValues(alpha: dark ? 0.08 : 0.05),
    hoverColor: scheme.onSurface.withValues(alpha: 0.04),
  );

  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? immersiveDarkScaffold
        : immersiveLightScaffold,
    // 卡片一律无边框、无阴影、大圆角。
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // 卡片一律用 Pv 的白卡（深色 #1F1E22），不再跟 M3 的
      // surfaceContainerLow 走 —— 后者跟页面底色差得太少，整页糊成一片。
      color: dark ? immersiveDarkCard : immersiveLightCard,
      shape: const RoundedRectangleBorder(borderRadius: immersiveBorderRadius),
    ),
    // AppBar 融入背景，滚动时不抬升高程。
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? immersiveDarkScaffold : immersiveLightScaffold,
      centerTitle: false,
    ),
    // 分割线压到近乎不可见。
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(borderRadius: immersiveBorderRadius),
      iconColor: scheme.onSurfaceVariant,
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      // 对话框统一走粘土底板色；真正需要渐变/阴影的地方用 ClayDialog。
      backgroundColor: dark ? clayLight : scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: immersiveBorderRadiusLarge,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(immersiveRadiusLarge),
        ),
      ),
    ),
    // ---- iOS 平台控件默认值（只影响还没走 Kz* 适配封装的零散调用） ----
    // 开关的绿色轨道下面已有专门配置，这里只补文本选择与 Cupertino 强调色。
    // 光标、选中高亮、选择手柄统一成 iOS 系统蓝：TextField 在 iOS 上本来
    // 就用 Cupertino 那套选择菜单，只有颜色还是主题色，看着很"错位"。
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: kCupertinoBlue,
      selectionColor: kCupertinoBlue.withValues(alpha: 0.24),
      selectionHandleColor: kCupertinoBlue,
    ),
    // Cupertino 组件的强调色（ActionSheet 按钮、滑块、日期选择器）。
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: kCupertinoBlue,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 68,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      elevation: 0,
      backgroundColor: Colors.transparent,
      indicatorShape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: immersiveBorderRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: immersiveBorderRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: immersiveBorderRadius,
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: immersiveBorderRadius,
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: const StadiumBorder(),
      backgroundColor: scheme.surfaceContainerHigh,
      labelStyle: TextStyle(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: immersiveBorderRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: immersiveBorderRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: immersiveBorderRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(dividerHeight: 0),
    // 开关做成 iOS 的样子：绿色轨道、白色圆钮、无描边。之前用强调色（紫），
    // 和粘土控件并排不打架，但用户一眼就能看出「这不是 iOS 的开关」。
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged)
            ? const Color(0xFFF2F2F7)
            : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF34C759)
            : (dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA)),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      trackOutlineWidth: WidgetStateProperty.all(0),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : Colors.transparent,
      ),
      side: BorderSide(color: scheme.outline, width: 1.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? clayLight : scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: dark ? const Color(0xFFEDEDF2) : scheme.onInverseSurface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
    ),
  );
}
