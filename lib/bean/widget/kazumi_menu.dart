import 'package:flutter/material.dart';

import 'package:XL/utils/motion.dart';

typedef KazumiMenuBuilder =
    Widget Function(BuildContext context, VoidCallback? toggle);

const _menuItemStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(144, 48)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  alignment: AlignmentDirectional.centerStart,
  visualDensity: VisualDensity.standard,
);

class KazumiMenuButton extends StatelessWidget {
  const KazumiMenuButton({
    super.key,
    required this.builder,
    required this.menuChildren,
    this.controller,
    this.enabled = true,
    this.animated = false,
    this.crossAxisUnconstrained = true,
    this.onOpen,
    this.onClose,
    this.style,
  });

  final KazumiMenuBuilder builder;
  final List<Widget> menuChildren;
  final MenuController? controller;
  final bool enabled;

  /// Opt in only for menus that previously animated.
  final bool animated;
  final bool crossAxisUnconstrained;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final MenuStyle? style;

  @override
  Widget build(BuildContext context) {
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        // Submenu entries must use the same inset as ordinary menu items.
        style: _menuItemStyle.merge(MenuButtonTheme.of(context).style),
      ),
      child: MenuAnchor(
        controller: controller,
        consumeOutsideTap: true,
        crossAxisUnconstrained: crossAxisUnconstrained,
        animated: animated && !MediaQuery.disableAnimationsOf(context),
        onOpen: onOpen,
        onClose: onClose,
        style: style,
        menuChildren: menuChildren,
        builder: (context, controller, _) => builder(
          context,
          enabled && menuChildren.isNotEmpty
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
        ),
      ),
    );
  }
}

class KazumiMenuItem extends StatelessWidget {
  const KazumiMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.selected,
    this.destructive = false,
    this.requestFocusOnHover = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;

  /// Null for actions; a bool exposes single-choice selection semantics.
  final bool? selected;
  final bool destructive;
  final bool requestFocusOnHover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive
        ? colors.error
        : selected == true
        ? colors.primary
        : null;
    final foregroundColor = color == null
        ? null
        : WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.disabled) ? null : color,
          );
    // 勾选图标弹性出现：选中态不只是变色，还有一下「落定」的动作。
    final checkIcon = selected == true
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1),
            duration: KazumiMotion.base,
            curve: KazumiMotion.spring,
            builder: (context, scale, child) =>
                AnimatedScale(scale: scale, duration: Duration.zero, child: child),
            child: Icon(Icons.check_rounded, size: 18),
          )
        : null;
    final item = MenuItemButton(
      onPressed: onPressed,
      requestFocusOnHover: requestFocusOnHover,
      style: ButtonStyle(
        foregroundColor: foregroundColor,
        iconColor: foregroundColor,
      ),
      leadingIcon: leadingIcon,
      trailingIcon: checkIcon,
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: selected == null ? null : true,
        child: Text(label, textAlign: TextAlign.start),
      ),
    );
    // 按压反馈：Listener 只旁观指针、不抢菜单的手势；禁用项不给反馈。
    return _KazumiMenuItemPress(enabled: onPressed != null, child: item);
  }
}

/// 菜单条目的按压缩放 + 选择触感。条目背景是透明的，缩放露出的是
/// 菜单容器表面色，不会露缝。
class _KazumiMenuItemPress extends StatefulWidget {
  const _KazumiMenuItemPress({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_KazumiMenuItemPress> createState() => _KazumiMenuItemPressState();
}

class _KazumiMenuItemPressState extends State<_KazumiMenuItemPress> {
  double _scale = 1;

  void _down(PointerEvent _) {
    if (!widget.enabled) return;
    KazumiHaptics.select();
    setState(() => _scale = 0.96);
  }

  void _up(PointerEvent _) {
    if (_scale == 1) return;
    setState(() => _scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: _scale,
        duration: _scale < 1
            ? KazumiMotion.instant
            : KazumiMotion.base,
        curve: _scale < 1 ? KazumiMotion.emphasized : KazumiMotion.spring,
        child: widget.child,
      ),
    );
  }
}
