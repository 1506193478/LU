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
    _push(
      message: message,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 底部胶囊通知（错误播报统一走这里）。
  ///
  /// 和居中的 [show] 是两套：中间那块黑玻璃适合「操作已生效」这种一闪而过
  /// 的反馈，而报错需要「我从底部升上来、停一会儿、再落下去」，而且要有
  /// 一个能一眼看出性质的图标。样式对齐系统通知横幅：整宽减 14、圆角 14、
  /// 浅色材质 + 铃铛 + 15pt 正文。
  static void showNotice(
    String message, {
    Duration duration = const Duration(seconds: 3),
    IconData? icon = Icons.notifications_none_rounded,
  }) {
    _push(
      message: message,
      duration: duration,
      notice: true,
      icon: icon,
    );
  }

  static void _push({
    required String message,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
    bool notice = false,
    IconData? icon,
  }) {
    if (!kIsCupertinoPlatform) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _hideTimer?.cancel();
    _removeEntry();

    final entry = OverlayEntry(
      builder: (_) => notice
          ? _NoticeView(message: message, visible: _visible, icon: icon)
          : _HudView(
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

/// 底部胶囊通知。
///
/// 位置刻意抬到底部导航之上（[bottomInset] + 安全区），否则会被胶囊导航
/// 压住一半——这正是「错误提示看不清」最容易被忽略的原因。
class _NoticeView extends StatelessWidget {
  const _NoticeView({
    required this.message,
    required this.visible,
    this.icon,
  });

  final String message;
  final ValueNotifier<bool> visible;
  final IconData? icon;

  /// 底部预留：导航胶囊 + 一点呼吸。
  static const double _reserved = 96;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fill = dark ? const Color(0xF22C2C2E) : const Color(0xF7FFFFFF);
    final Color ink = dark ? Colors.white : const Color(0xFF101013);
    final Color sub = dark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF8A8A8E);
    final double bottomInset =
        _reserved + MediaQuery.paddingOf(context).bottom;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset),
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, shown, child) {
              return AnimatedSlide(
                offset: Offset(0, shown ? 0 : 0.35),
                duration: const Duration(milliseconds: 260),
                curve: shown ? Curves.easeOutCubic : Curves.easeIn,
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: child,
                ),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.36 : 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: sub),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        height: 1.3,
                        letterSpacing: -0.2,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
