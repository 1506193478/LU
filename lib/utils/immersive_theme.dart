import 'package:flutter/material.dart';
import 'package:XL/utils/constants.dart';

/// 内容沉浸型主题：深色为主、大圆角、去边框、弱化分割线。
///
/// 种子色只保留为强调色，所有承载内容的 surface 一律换成中性灰阶，
/// 让封面图成为页面里唯一的高饱和元素。
const Color immersiveDarkScaffold = Color(0xFF0B0C0F);
const Color immersiveLightScaffold = Color(0xFFF5F6F8);

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
const double immersiveTabBarHeight = 66;
const double immersiveTabBarGap = 14;

/// 底部导航条实际占掉的高度（含系统安全区）。
double immersiveTabBarInset(BuildContext context) =>
    immersiveTabBarHeight +
    immersiveTabBarGap +
    MediaQuery.paddingOf(context).bottom;

const BorderRadius immersiveBorderRadius =
    BorderRadius.all(Radius.circular(immersiveRadius));
const BorderRadius immersiveBorderRadiusLarge =
    BorderRadius.all(Radius.circular(immersiveRadiusLarge));

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
  final ColorScheme seed = colorScheme ??
      ColorScheme.fromSeed(
        seedColor: color ?? kDefaultAccent,
        brightness: brightness,
      );
  return seed.copyWith(
    surface: dark ? _darkSurface : _lightSurface,
    surfaceContainerLowest:
        dark ? _darkSurfaceLowest : _lightSurfaceLowest,
    surfaceContainerLow: dark ? _darkSurfaceLow : _lightSurfaceLow,
    surfaceContainer: dark ? _darkSurfaceContainer : _lightSurfaceContainer,
    surfaceContainerHigh: dark ? _darkSurfaceHigh : _lightSurfaceHigh,
    surfaceContainerHighest:
        dark ? _darkSurfaceHighest : _lightSurfaceHighest,
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
  );

  return base.copyWith(
    scaffoldBackgroundColor:
        dark ? immersiveDarkScaffold : immersiveLightScaffold,
    // 卡片一律无边框、无阴影、大圆角。
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: immersiveBorderRadius,
      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: immersiveBorderRadius,
      ),
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    // 开关/单选/复选统一吃强调色，避免和自制粘土控件并排时配色打架。
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
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
