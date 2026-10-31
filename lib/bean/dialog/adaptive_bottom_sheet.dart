// Adapted from m3e_core 1.1.2's M3EBottomSheet (MIT).
// Copyright (c) 2026 Mudit Purohit. See licenses/m3e_core.txt.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:XL/utils/motion.dart';

BoxConstraints _adaptiveBottomSheetConstraints(
  BuildContext context, {
  required double maxHeightFactor,
  required double compactLandscapeMaxHeightFactor,
}) {
  final size = MediaQuery.sizeOf(context);
  final isLandscape = size.width > size.height;
  final useFullWidth = !isLandscape && size.width < 600;
  final maxWidth =
      useFullWidth ? size.width : math.min(size.width * 0.72, 640.0);
  final useExpandedLandscapeHeight = isLandscape && size.height < 600;
  final maxHeight = size.height *
      (useExpandedLandscapeHeight
          ? compactLandscapeMaxHeightFactor
          : maxHeightFactor);

  return BoxConstraints(
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

// Native route motion and the extra surface entrance spring are separate.
//
// 路由这一段以前是 250/200ms + Easing.legacyDecelerate，跟全局节奏表
// （240/160/320）对不上，同一个 App 里弹层的"进出速度"和页面切换、按钮
// 反馈是三种手感。现在直接取 KazumiMotion 的 token，曲线也用同一套：
// 进场用 emphasized（起步快、收尾稳），退场用 standard（不拖尾巴）。
const AnimationStyle _materialSheetAnimationStyle = AnimationStyle(
  duration: KazumiMotion.base,
  reverseDuration: KazumiMotion.fast,
  curve: KazumiMotion.emphasized,
  reverseCurve: KazumiMotion.standard,
);

Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFactor = 0.75,
  double compactLandscapeMaxHeightFactor = 0.9,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // A single surface owns the handle and background to avoid a second cap.
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    constraints: _adaptiveBottomSheetConstraints(
      context,
      maxHeightFactor: maxHeightFactor,
      compactLandscapeMaxHeightFactor: compactLandscapeMaxHeightFactor,
    ),
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    showDragHandle: false,
    useSafeArea: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : _materialSheetAnimationStyle,
    builder: (context) => _MaterialSheetSurface(
      child: Builder(builder: builder),
    ),
  );
}

class _MaterialSheetSurface extends StatefulWidget {
  const _MaterialSheetSurface({required this.child});

  final Widget child;

  @override
  State<_MaterialSheetSurface> createState() => _MaterialSheetSurfaceState();
}

class _MaterialSheetSurfaceState extends State<_MaterialSheetSurface>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController.unbounded(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _entrance.value = 1;
    } else if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
        _entrance.animateWith(SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 380,
            ratio: 0.8,
          ),
          0,
          1,
          0,
          snapToEnd: false,
        ));
      });
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    // 弹层底板要比里面的粘土砖更暗一档，否则行与行之间的 4px 缝隙会消失，
    // 整块砖会糊成一片。这里不用 ClayTone.surface，单独给一组"更深"的端点。
    final Color sheetTop = dark ? const Color(0xFF1C1F26) : const Color(0xFFFFFFFF);
    final Color sheetBottom =
        dark ? const Color(0xFF0E1014) : const Color(0xFFF1F2F6);
    // 底部补块用渐变的末端色，弹层回弹过头时不会露出另一种底色。
    final Color background = sheetBottom;
    final surface = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sheetTop, sheetBottom],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: theme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: MaterialLocalizations.of(context)
                      .modalBarrierDismissLabel,
                  onDismiss: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Flexible(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Cover the bottom gap during spring overshoot.
        Positioned(
          left: 0,
          right: 0,
          bottom: -400,
          height: 450,
          child: ColoredBox(color: background),
        ),
        AnimatedBuilder(
          animation: _entrance,
          child: surface,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - _entrance.value) * 200),
            child: Opacity(
              opacity: _entrance.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
