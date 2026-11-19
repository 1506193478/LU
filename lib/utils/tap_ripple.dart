import 'package:flutter/material.dart';

/// 双击画面的涟漪反馈：在点击位置泛一圈扩散光环，可选一句文字。
///
/// 走根 Overlay，跨页面/播放器安全；IgnorePointer 不拦截手势；
/// 动画结束自动移除，另有 700ms 兜底清理。
abstract final class TapRipple {
  static void show(
    BuildContext context,
    Offset globalPosition, {
    String? label,
  }) {
    final OverlayState? overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    bool removed = false;
    void safeRemove() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          onEnd: safeRemove,
          builder: (context, t, _) {
            return Stack(
              children: [
                Positioned(
                  left: globalPosition.dx - 72,
                  top: globalPosition.dy - 72,
                  width: 144,
                  height: 144,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: (1 - t) * 0.65),
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: (1 - t) * 0.14),
                          blurRadius: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                if (label != null)
                  Positioned(
                    left: globalPosition.dx - 44,
                    top: globalPosition.dy - 66,
                    width: 88,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 1 - t),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        shadows: const [
                          Shadow(color: Color(0x66000000), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    // 兜底：动画被中断（页面退出等）也能清掉。
    Future.delayed(const Duration(milliseconds: 760), safeRemove);
  }
}
