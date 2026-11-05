import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';

import 'package:XL/navigation.dart';
import 'package:XL/theme/ios_interaction.dart';

/// iOS 风格轻提示（HUD）。
///
/// iOS 没有 SnackBar：系统级提示是「一块深色毛玻璃 + 短文案」，浮在屏幕
/// 中下部，两秒后自己淡出——不挡操作、不推挤布局、也不占满整行宽。
///
/// 原来这里走的是 Material SnackBar：一条从底部滑上来的黑条，宽度贴边，
/// 是整套界面里最明显的「安卓感」来源。现在 iOS 走 HUD，Android 保持
/// SnackBar（那边确实就是这么提示的）。
class KzHud {
  KzHud._();

  static OverlayEntry? _entry;
  static Timer? _hideTimer;
  static final ValueNotifier<bool> _visible = ValueNotifier<bool>(false);

  /// 正在显示时再调用会替换掉上一条，不会叠成一摞。
  static void show(
    String message, {
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!kIsCupertinoPlatform) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hideTimer?.cancel();
    _removeEntry();

    final entry = OverlayEntry(
      builder: (_) => _HudView(
        message: message,
        visible: _visible,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    // 下一帧再拉起透明度，让入场动画真的跑起来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entry == entry) _visible.value = true;
    });

    _hideTimer = Timer(duration, hide);
  }

  static void hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_entry == null) return;
    _visible.value = false;
    // 等淡出跑完再摘掉，避免「啪」一下消失。
    final entry = _entry;
    _entry = null;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (_entry == null) entry?.remove();
    });
  }

  static void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _visible.value = false;
  }
}

class _HudView extends StatelessWidget {
  const _HudView({
    required this.message,
    required this.visible,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final ValueNotifier<bool> visible;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    return IgnorePointer(
      ignoring: !hasAction,
      child: Align(
        alignment: const Alignment(0, 0.52),
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, shown, child) {
            return AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: shown ? 1 : 0.94,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: EdgeInsets.fromLTRB(
                    18,
                    13,
                    hasAction ? 10 : 18,
                    13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.35,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasAction)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 0),
                          onPressed: () {
                            KzHud.hide();
                            onAction!();
                          },
                          child: Text(
                            actionLabel!,
                            style: const TextStyle(
                              color: kCupertinoBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
