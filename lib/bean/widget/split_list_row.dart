import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/utils/motion.dart';

const double splitListOuterRadius = 16;
const double splitListInnerRadius = 4;
const double splitListRowGap = 4;

const Duration splitListMotionDuration = Duration(milliseconds: 250);
const Curve splitListMotionCurve = Curves.easeInOutCubic;

/// 分组列表里的一行。
///
/// 视觉上是"一块粘土砖"：左上受光、右下背光的渐变 + 0.5px 高光边。
/// 按下时渐变方向翻过来并下沉 1px —— 和 [ClayButton] 同一套受压逻辑，
/// 所以整块砖看起来是被按进页面里的，而不是换了个颜色。
///
/// 行与行之间留 4px 缝隙、只有首尾行用大圆角，所以一列读起来是一条
/// 被切成若干块的板子。这个结构全项目都在用（设置、来源检索、弹幕选择），
/// 改这里等于一起改。
class SplitListRow extends StatefulWidget {
  const SplitListRow({
    super.key,
    required this.child,
    this.topRadius = splitListInnerRadius,
    this.bottomRadius = splitListInnerRadius,
    this.pressedRadius = splitListOuterRadius,
    this.onTap,
  });

  final Widget child;

  final double topRadius;
  final double bottomRadius;

  /// 保留参数以兼容旧调用点；粘土按压靠渐变反向表达，不再改圆角
  /// （圆角突变在粘土材质上会显得像"跳了一下"）。
  final double pressedRadius;
  final VoidCallback? onTap;

  /// Forward a child InkWell's onHighlightChanged here.
  static ValueChanged<bool>? pressReporterOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SplitRowScope>()
        ?.onPressChanged;
  }

  @override
  State<SplitListRow> createState() => _SplitListRowState();
}

class _SplitListRowState extends State<SplitListRow> {
  bool _pressed = false;

  void _reportPress(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final child = widget.onTap == null
        ? widget.child
        : InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _reportPress,
            child: widget.child,
          );

    final BorderRadius radius = BorderRadius.vertical(
      top: Radius.circular(widget.topRadius),
      bottom: Radius.circular(widget.bottomRadius),
    );

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : KazumiMotion.fast,
      curve: splitListMotionCurve,
      clipBehavior: Clip.antiAlias,
      // 按下只做 1px 下沉 + 底色压深，不再翻渐变、不再有粘土的高光边。
      transform: Matrix4.translationValues(0, _pressed ? 1 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pressed
            ? PvColors.searchFill(context)
            : PvColors.card(context),
        borderRadius: radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTileTheme(
          data: theme.listTileTheme.copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            titleTextStyle: theme.textTheme.bodyLarge
                ?.copyWith(color: PvColors.ink(context)),
            subtitleTextStyle: theme.textTheme.bodyMedium
                ?.copyWith(color: PvColors.ink3(context)),
          ),
          child: _SplitRowScope(onPressChanged: _reportPress, child: child),
        ),
      ),
    );
  }
}

class _SplitRowScope extends InheritedWidget {
  const _SplitRowScope({required this.onPressChanged, required super.child});

  final ValueChanged<bool> onPressChanged;

  // The callback always targets the same state.
  @override
  bool updateShouldNotify(_SplitRowScope oldWidget) => false;
}

class SplitListGroup extends StatelessWidget {
  const SplitListGroup({
    super.key,
    required this.children,
    this.outerRadius = splitListOuterRadius,
  });

  final List<Widget> children;

  final double outerRadius;

  @override
  Widget build(BuildContext context) {
    // Pv 的分组是一张整卡 + 行间发丝线，不是「一块块粘土砖拼起来」：
    // 砖块之间的 4px 缝在 Pv 上会读成碎裂，分隔要靠线而不是缝。
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: BorderRadius.circular(outerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: 0.8,
                margin: const EdgeInsets.only(left: 16),
                color: PvColors.hair(context),
              ),
            SplitListRow(
              topRadius: 0,
              bottomRadius: 0,
              pressedRadius: outerRadius,
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}
