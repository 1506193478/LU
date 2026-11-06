import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/bean/widget/window_drag.dart';

/// LU_3.9.19_预览.html 的设计令牌与 iOS 风组件。
///
/// 这份文件是「预览稿 → Flutter」的直译层：浅色模式的每一个颜色、字号、
/// 圆角都严格对应预览稿 CSS 变量（`:root{...}`），深色模式给同一布局的
/// 合理暗色对应值。Emby 三个页签的资源库 / 我的 / 弹层全部从这里取样式，
/// 保证界面和预览稿分毫不差。
/// 页面底部要给「二级导航胶囊」让出的高度。
///
/// 胶囊浮在 App 底栏上方 6dp、本体 32 高，再留一点呼吸空间。三个页签的
/// 滚动列表统一用它，否则最后一行会被胶囊压住（原来写死 120，胶囊落到
/// 底栏上沿之后正好差一截）。
const double pvSubDockClearance = 168;

class PvColors {
  PvColors._();

  /// 页面底色：iOS `systemGroupedBackground`（浅 #F2F2F7 / 深 #000000）。
  ///
  /// 原来是预览稿的 #F3F1F2 —— 偏暖的灰，配白卡会显「灰里发粉」。系统色是
  /// 冷灰，白卡压上去层次更干净，这也是所有 iOS 分组列表的底。
  static Color page(BuildContext context) =>
      isDark(context) ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  /// 卡片底：iOS `secondarySystemGroupedBackground`（浅 #FFFFFF / 深 #1C1C1E）。
  static Color card(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C1C1E) : Colors.white;

  /// `--ink` 主文字。
  static Color ink(BuildContext context) =>
      isDark(context) ? const Color(0xFFF2F2F5) : const Color(0xFF0B0B0F);

  /// `--ink2` 次级文字。
  static Color ink2(BuildContext context) =>
      isDark(context) ? const Color(0xFFA5A5AC) : const Color(0xFF6B6B70);

  /// `--ink3` 弱文字。
  static Color ink3(BuildContext context) =>
      isDark(context) ? const Color(0xFF74747C) : const Color(0xFF9A9AA0);

  /// 分隔线：iOS `separator`（浅 #C6C6C8 / 深 #38383A）。
  ///
  /// 原来浅色是 7% 的黑，压在白卡上几乎看不见——一张卡里七八行会糊成一块。
  /// 系统色是实打实的 #C6C6C8，画 0.5px 才有那条「发丝」。
  static Color hair(BuildContext context) =>
      isDark(context) ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

  /// `--blue` #007AFF。
  static const blue = Color(0xFF007AFF);

  /// `--green` #2FBF5C。
  static const green = Color(0xFF2FBF5C);

  /// `--red` #FF3B30。
  static const red = Color(0xFFFF3B30);

  /// 琥珀强调色：置顶公告、置顶入口这类「提醒」语义，浅底深字 / 深底浅字。
  static Color amberInk(BuildContext context) =>
      isDark(context) ? const Color(0xFFF0C878) : const Color(0xFF854F0B);

  /// 琥珀底色，跟 [amberInk] 配对使用。
  static Color amberFill(BuildContext context) =>
      isDark(context) ? const Color(0xFF3A2E14) : const Color(0xFFFAEEDA);

  /// `--dockink` 底栏选中文字 #3A5680。
  static Color dockInk(BuildContext context) =>
      isDark(context) ? const Color(0xFF9DB4D8) : const Color(0xFF3A5680);

  /// 底栏选中胶囊 `--capsule` rgba(56,84,128,.13)。
  static Color capsule(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.12)
      : const Color(0x21385480);

  /// 二级导航选中背景 rgba(56,84,128,.15)。
  static Color subCap(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0x26385480);

  /// 二级导航选中文字 #2F4E7A。
  static Color subInk(BuildContext context) =>
      isDark(context) ? const Color(0xFFA9C0E4) : const Color(0xFF2F4E7A);

  /// 底栏未选中 #8E8E93。
  static const dockIdle = Color(0xFF8E8E93);

  /// 箭头 #C4C4C9。
  static Color chev(BuildContext context) =>
      isDark(context) ? const Color(0xFF55555C) : const Color(0xFFC4C4C9);

  /// 搜索条底 #EFEFF3。
  static Color searchFill(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFEFEFF3);

  /// 搜索占位字 #8A8A8E。
  static Color searchHint(BuildContext context) =>
      isDark(context) ? const Color(0xFF77777E) : const Color(0xFF8A8A8E);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// 预览稿字号 / 字重（px 直接用 HTML 里的数值）。
class PvText {
  PvText._();

  /// 大标题：iOS largeTitle 34pt / Bold / 轻微收紧。
  ///
  /// 原来 w800 + ls-1.1，比系统粗一档、挤一档，看起来像设计稿上的字而不是
  /// 系统标题。
  static TextStyle pageTitle(BuildContext context) => TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.15,
    color: PvColors.ink(context),
  );

  /// 区块标题：iOS title3 20pt / Semibold。
  ///
  /// 原来 17 和正文一样大，只靠字重区分，结果区块之间没有层级。
  static TextStyle section(BuildContext context) => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: PvColors.ink(context),
  );

  /// `.sect .cnt` 12.5 灰。
  static TextStyle count(BuildContext context) => TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: PvColors.ink3(context),
  );

  /// 列表行标题：iOS body 17pt / Regular。
  ///
  /// 15pt + w500 是最「像画的」的那个值：系统设置里所有行都是 17pt 常规字重，
  /// 15 会显得整页被缩小打印过。
  static TextStyle rowTitle(BuildContext context) => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: PvColors.ink(context),
  );

  /// 行副标题：iOS footnote 13pt / secondaryLabel。
  static TextStyle rowSub(BuildContext context) => TextStyle(
    fontSize: 13,
    letterSpacing: -0.05,
    height: 1.25,
    color: PvColors.ink2(context),
  );

  /// 分组小标题：iOS section header 13pt / secondaryLabel。
  ///
  /// 原来 11.5 + w600 + 正字距，是网页里的小标签排版；系统是 13pt 常规。
  static TextStyle groupLabel(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.05,
    color: PvColors.ink2(context),
  );

  /// `.statcard b` 21 w800 ls-0.6。
  static const statNum = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  /// `.statcard span` 11.5 灰。
  static TextStyle statLabel(BuildContext context) => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: PvColors.ink3(context),
  );

  /// `.libcard .nm` 16 w700 ls-0.4。
  static TextStyle libName(BuildContext context) => TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
    color: const Color(0xFF17171B),
  );

  /// `.libcard .stats` 12.5。
  static const libStat = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF5E5E64),
  );

  /// `.libcard .foot` 12 灰。
  static const libFoot = TextStyle(fontSize: 12, color: Color(0xFF8A8A8E));
}

/// iOS 风设置分组：白底圆角 16。
class PvGroup extends StatelessWidget {
  const PvGroup({super.key, required this.children, this.margin});

  final List<Widget> children;

  /// 预览稿 `.group` 外边距 `0 20px 14px`。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: PvColors.card(context),
        // iOS inset grouped 的圆角是 10（不是网页卡的 16）。
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// `.glabel` 分组上方的小标签。
class PvGroupLabel extends StatelessWidget {
  const PvGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: PvText.groupLabel(context)),
      ),
    );
  }
}

/// `.row` 右侧内容的形态。
enum PvRowTrailing { chevron, value, widget, none }

/// iOS 风设置行：高 50，左侧 28x28 彩色圆角图标，标题 + 可选副文字。
class PvRow extends StatelessWidget {
  const PvRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.titleColor,
    this.trailing = PvRowTrailing.chevron,
    this.trailingWidget,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;

  /// 标题颜色，默认跟主题 ink；「关闭密码锁」这类破坏性行传红色。
  final Color? titleColor;
  final PvRowTrailing trailing;
  final Widget? trailingWidget;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Container(
              // iOS 设置里的行图标是 29pt 圆角 7，不是 28/8。
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PvText.rowTitle(context).copyWith(
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PvText.rowSub(context),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(value!, style: PvText.rowSub(context)),
            ],
            if (trailing == PvRowTrailing.chevron) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: PvColors.chev(context),
              ),
            ],
            if (trailing == PvRowTrailing.widget && trailingWidget != null)
              trailingWidget!,
          ],
        ),
      ),
    );

    // iOS 的列表行按下是「内容变淡」，不是 Material 的矩形高亮。
    // 这里换掉 InkWell：全局已关掉 splash，InkWell 的高亮又是方的，
    // 在圆角卡片里会露出四个直角。
    final body = onTap == null
        ? row
        : KzPressable(onTap: onTap, child: row);

    if (!showDivider) return body;
    // `.row + .row::before`：左侧 15px 起的分隔线。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.5,
          margin: const EdgeInsets.only(left: 16),
          color: PvColors.hair(context),
        ),
        body,
      ],
    );
  }
}

/// `.switch`：iOS 开关。
class PvSwitch extends StatelessWidget {
  const PvSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 47,
      height: 29,
      child: FittedBox(
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: const Color(0xFF34C759),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// `.searchbar`：高 38 圆角 11 灰底搜索条。
class PvSearchField extends StatelessWidget {
  const PvSearchField({
    super.key,
    this.hint = '搜索',
    this.onTap,
    this.controller,
    this.onChanged,
  });

  final String hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: PvColors.searchFill(context),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 17,
            color: PvColors.searchHint(context),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: PvColors.searchHint(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

/// `.page-head` + `.page-title`：34px 大标题行，右侧可选操作按钮。
class PvPageHead extends StatelessWidget {
  const PvPageHead({
    super.key,
    required this.title,
    this.actions = const [],
    this.topPadding = 14,
  });

  final String title;
  final List<Widget> actions;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    // 页内大标题也是窗口的「标题栏」：无边框窗口下这块能拖着走，
    // 否则「我的」这类页面整页只有顶上 8px 能抓。
    return WindowDragRegion(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topPadding, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: PvText.pageTitle(context))),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: actions),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.iconbtn`：30x30 蓝色图标按钮；[circled] 时是 27x27 蓝色圆圈。
class PvIconBtn extends StatelessWidget {
  const PvIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.circled = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool circled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget btn = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // 系统导航栏的按钮是**裸字形**，没有圆圈也没有描边。
      // 原来 [circled] 会画一圈 1.6px 的蓝边，和 iOS 工具栏完全不是一回事；
      // 这里保留参数只为了让调用点不用改，但两种形态都画成裸图标。
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(icon, size: circled ? 21 : 22, color: PvColors.blue),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

/// `.sect` 区块标题：17px 粗体 + 数量 + 右侧箭头。
class PvSectionHead extends StatelessWidget {
  const PvSectionHead(
    this.title, {
    super.key,
    this.count,
    this.onMore,
    this.topPadding = 22,
  });

  final String title;
  final String? count;
  final VoidCallback? onMore;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 10),
      child: Row(
        children: [
          Text(title, style: PvText.section(context)),
          if (count != null && count!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(count!, style: PvText.count(context)),
          ],
          if (onMore != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: const Color(0xFFB0B0B6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 资源库卡片的四色渐变（预览稿 `.tone-*`）。
class PvLibTone {
  PvLibTone._();

  static const amber = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFFEF6E6),
    Color(0xFFFBE7BE),
  ];
  static const gold = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFFDF3DF),
    Color(0xFFF8E0B4),
  ];
  static const sky = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFEDF3FD),
    Color(0xFFD8E6F8),
  ];
  static const green = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFEAF8EE),
    Color(0xFFCDEEDA),
  ];
}

/// `.libcard`：高 120 圆角 18 的资源库卡。
class PvLibCard extends StatelessWidget {
  const PvLibCard({
    super.key,
    required this.name,
    required this.tone,
    required this.icon,
    required this.iconColor,
    this.online = false,
    this.stats = const <(String, IconData)>[],
    this.foot,
    this.onTap,
    this.onLongPress,
  });

  final String name;
  final List<Color> tone;
  final IconData icon;
  final Color iconColor;
  final bool online;
  final List<(String, IconData)> stats;
  final List<String>? foot;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final List<Color> colors = dark
        ? tone
              .map((c) => Color.lerp(c, const Color(0xFF232227), 0.82)!)
              .toList()
        : tone;

    return KzPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      // 整张卡片面积大，压得太狠会显得"陷下去"，取 0.72。
      pressedOpacity: 0.72,
      child: Container(
        height: 120,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.2,
                      color: dark
                          ? const Color(0xFFEDEDEF)
                          : const Color(0xFF17171B),
                    ),
                  ),
                ),
                if (online) ...[
                  const SizedBox(width: 3),
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      color: PvColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(icon, size: 34, color: iconColor),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const SizedBox(width: 11),
                    Icon(stats[i].$2, size: 13, color: const Color(0xFF5E5E64)),
                    const SizedBox(width: 4),
                    Text(
                      stats[i].$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: dark
                            ? const Color(0xFFB9B9C0)
                            : const Color(0xFF5E5E64),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const Spacer(),
            if (foot != null && foot!.length == 2)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      foot![0],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: dark
                            ? const Color(0xFF8A8A92)
                            : const Color(0xFF8A8A8E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    foot![1],
                    style: TextStyle(
                      fontSize: 12,
                      color: dark
                          ? const Color(0xFF8A8A92)
                          : const Color(0xFF8A8A8E),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 弹出菜单（预览稿 `.popmenu`）：白底圆角 14、行高 46、字 16.5。
///
/// 用 [showMenu] 实现，锚点由调用方给。
Future<T?> showPvMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PvMenuItem> items,
  double minWidth = 200,
}) {
  final dark = PvColors.isDark(context);
  return showMenu<T>(
    context: context,
    position: position,
    elevation: 18,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    color: dark ? const Color(0xFF26252A) : Colors.white,
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: 320),
    items: [
      for (final item in items)
        if (item.isDivider)
          const PopupMenuDivider()
        else
          PopupMenuItem<T>(
            height: 46,
            padding: EdgeInsets.zero,
            onTap: item.onTap,
            value: item.value is T ? item.value as T : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (item.checked)
                    Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: PvColors.ink(context),
                    )
                  else if (item.icon != null)
                    Icon(item.icon, size: 21, color: const Color(0xFF3B4252))
                  else
                    const SizedBox(width: 21),
                  if (item.icon != null || item.checked)
                    const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w500,
                        color: item.destructive
                            ? PvColors.red
                            : (dark
                                  ? const Color(0xFFEDEDEF)
                                  : const Color(0xFF17171B)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}

/// [showPvMenu] 的条目。
class PvMenuItem {
  const PvMenuItem(
    this.label, {
    this.icon,
    this.onTap,
    this.value,
    this.checked = false,
    this.isDivider = false,
    this.destructive = false,
  });

  const PvMenuItem.divider()
    : label = '',
      icon = null,
      onTap = null,
      value = null,
      checked = false,
      isDivider = true,
      destructive = false;

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Object? value;
  final bool checked;
  final bool isDivider;
  final bool destructive;
}
