import 'package:flutter/material.dart';

import 'package:XL/theme/ios_interaction.dart';

/// iOS 系统设计 token（Apple HIG 原值）。
///
/// 这一层是「照抄系统」用的：颜色取自 UIColor 的语义色，字号取自
/// UIFont.TextStyle 的字号/字重/行高，尺寸取自 44pt 触控目标与
/// insetGrouped 的 16pt 边距 / 10pt 圆角。
///
/// 为什么要单开一层：原来项目所有页面都用 `PvColors` / `PvText`，那是一套
/// 自成体系的品牌语言（更重的字重、更小的字号、更大的圆角）。只在 iOS 上
/// 「换控件」永远改不到观感——真正决定像不像 iOS 的是这些数值。所以在
/// `Pv*` 里做平台分流，调用点一行都不用动。
class IosPalette {
  IosPalette._();

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  // ---- 背景层级（grouped 场景：设置页、我的页这类列表页） ----

  /// systemGroupedBackground：列表页最底层。
  static Color groupedBackground(BuildContext c) =>
      _dark(c) ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  /// secondarySystemGroupedBackground：分组卡片本身。
  static Color groupedCard(BuildContext c) =>
      _dark(c) ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);

  /// tertiarySystemGroupedBackground：卡片里的次级容器。
  static Color groupedTertiary(BuildContext c) =>
      _dark(c) ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

  // ---- 文字 ----

  static Color label(BuildContext c) =>
      _dark(c) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);

  static Color secondaryLabel(BuildContext c) =>
      _dark(c) ? const Color(0x99EBEBF5) : const Color(0x993C3C43);

  static Color tertiaryLabel(BuildContext c) =>
      _dark(c) ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43);

  static Color quaternaryLabel(BuildContext c) =>
      _dark(c) ? const Color(0x2DEBEBF5) : const Color(0x2D3C3C43);

  // ---- 分隔线 ----

  /// separator：非不透明，能透出底下内容（列表行间那条）。
  static Color separator(BuildContext c) =>
      _dark(c) ? const Color(0xA6545458) : const Color(0x4A3C3C43);

  /// opaqueSeparator：不透明版本。
  static Color opaqueSeparator(BuildContext c) =>
      _dark(c) ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

  // ---- 强调色（系统色，深色模式各自提亮一档） ----

  static const Color _blue = Color(0xFF007AFF);
  static const Color _blueDark = Color(0xFF0A84FF);
  static const Color _green = Color(0xFF34C759);
  static const Color _greenDark = Color(0xFF30D158);
  static const Color _red = Color(0xFFFF3B30);
  static const Color _redDark = Color(0xFFFF453A);
  static const Color _orange = Color(0xFFFF9500);
  static const Color _orangeDark = Color(0xFFFF9F0A);

  static Color tint(BuildContext c) => _dark(c) ? _blueDark : _blue;
  static Color green(BuildContext c) => _dark(c) ? _greenDark : _green;
  static Color red(BuildContext c) => _dark(c) ? _redDark : _red;
  static Color orange(BuildContext c) => _dark(c) ? _orangeDark : _orange;

  // ---- 填充（搜索框、分段控件、卡片内的输入区） ----

  static Color fill(BuildContext c) =>
      _dark(c) ? const Color(0x3D767680) : const Color(0x1F767680);

  static Color fillSecondary(BuildContext c) =>
      _dark(c) ? const Color(0x52767680) : const Color(0x2E767680);

  /// 列表行的按压高亮（iOS 是整行轻微变暗）。
  static Color pressedFill(BuildContext c) =>
      _dark(c) ? const Color(0x14FFFFFF) : const Color(0x0A000000);
}

/// iOS 字号体系（UIFont.TextStyle）。
///
/// 数值全部照抄 HIG：34/28/22/20/17/17/16/15/13/12/11，行高按系统
/// 给的 lineHeight 折算成 Flutter 的 `height` 倍数。
///
/// **字重是关键**：项目原来的大标题是 w800、行标题 w500，而 iOS 是
/// bold(700) 和 regular(400)。SF Pro 本身比大多数中文字体更「细」，
/// 再叠上高字重就明显不像系统 UI。
class IosText {
  IosText._();

  static TextStyle _style(
    BuildContext c, {
    required double size,
    required FontWeight weight,
    required double lineHeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: lineHeight / size,
      letterSpacing: letterSpacing,
      color: color ?? IosPalette.label(c),
    );
  }

  /// largeTitle：34 bold / 41。
  static TextStyle largeTitle(BuildContext c, {Color? color}) => _style(
    c,
    size: 34,
    weight: FontWeight.w700,
    lineHeight: 41,
    letterSpacing: 0.37,
    color: color,
  );

  /// title1：28 bold / 34。
  static TextStyle title1(BuildContext c, {Color? color}) => _style(
    c,
    size: 28,
    weight: FontWeight.w700,
    lineHeight: 34,
    letterSpacing: 0.36,
    color: color,
  );

  /// title2：22 bold / 28。
  static TextStyle title2(BuildContext c, {Color? color}) => _style(
    c,
    size: 22,
    weight: FontWeight.w700,
    lineHeight: 28,
    letterSpacing: -0.26,
    color: color,
  );

  /// title3：20 semibold / 25。
  static TextStyle title3(BuildContext c, {Color? color}) => _style(
    c,
    size: 20,
    weight: FontWeight.w600,
    lineHeight: 25,
    letterSpacing: -0.45,
    color: color,
  );

  /// headline：17 semibold / 22（分组标题、导航栏标题）。
  static TextStyle headline(BuildContext c, {Color? color}) => _style(
    c,
    size: 17,
    weight: FontWeight.w600,
    lineHeight: 22,
    letterSpacing: -0.41,
    color: color,
  );

  /// body：17 regular / 22（列表主标题）。
  static TextStyle body(BuildContext c, {Color? color}) => _style(
    c,
    size: 17,
    weight: FontWeight.w400,
    lineHeight: 22,
    letterSpacing: -0.41,
    color: color,
  );

  /// callout：16 regular / 21。
  static TextStyle callout(BuildContext c, {Color? color}) => _style(
    c,
    size: 16,
    weight: FontWeight.w400,
    lineHeight: 21,
    letterSpacing: -0.32,
    color: color,
  );

  /// subheadline：15 regular / 20。
  static TextStyle subheadline(BuildContext c, {Color? color}) => _style(
    c,
    size: 15,
    weight: FontWeight.w400,
    lineHeight: 20,
    letterSpacing: -0.24,
    color: color,
  );

  /// footnote：13 regular / 18（列表副标题、分组标题）。
  static TextStyle footnote(BuildContext c, {Color? color}) => _style(
    c,
    size: 13,
    weight: FontWeight.w400,
    lineHeight: 18,
    letterSpacing: -0.08,
    color: color,
  );

  /// caption1：12 regular / 16。
  static TextStyle caption1(BuildContext c, {Color? color}) => _style(
    c,
    size: 12,
    weight: FontWeight.w400,
    lineHeight: 16,
    color: color,
  );

  /// caption2：11 regular / 13。
  static TextStyle caption2(BuildContext c, {Color? color}) => _style(
    c,
    size: 11,
    weight: FontWeight.w400,
    lineHeight: 13,
    letterSpacing: 0.07,
    color: color,
  );
}

/// iOS 尺寸（44pt 触控目标 + insetGrouped 分组骨架）。
class IosMetrics {
  IosMetrics._();

  /// 列表行最小高度。低于 44 就是 HIG 违规。
  static const double rowHeight = 44;

  /// insetGrouped 左右边距。
  static const double groupedInset = 16;

  /// 分组卡片圆角。
  static const double groupedRadius = 10;

  /// 组与组之间的间距。
  static const double sectionSpacing = 26;

  /// 分组标题距上 / 距下。
  static const double groupLabelTop = 18;
  static const double groupLabelBottom = 7;

  /// 设置行左侧图标：29x29 / 圆角 6.5（系统设置页同款）。
  static const double iconSize = 29;
  static const double iconRadius = 6.5;

  /// 图标右到文字的间距。
  static const double iconGap = 12;

  /// 行内左右内边距（insetGrouped 卡片内部）。
  static const double rowInset = 16;

  /// Tab bar 内容高度（不含底部安全区）。
  static const double tabBarHeight = 49;

  /// 导航栏内容高度。
  static const double navBarHeight = 44;

  /// 分隔线左缩进：有图标时让出图标宽度，没有则贴 16。
  static double separatorInset({bool hasIcon = true}) =>
      hasIcon ? rowInset + iconSize + iconGap : rowInset;
}

/// 当前是否走 iOS 系统设计语言。
///
/// 用一个统一入口，避免各文件自己判断 `kIsCupertinoPlatform` 判断漏了。
bool get kIosSystemized => kIsCupertinoPlatform;
