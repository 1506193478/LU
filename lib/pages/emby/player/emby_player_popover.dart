import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 播放器里的 iOS 风格弹出菜单（对标 `UIMenu`）。
///
/// 为什么不用 bottom sheet：播放器是横屏全屏画面，从底部升起来一张大板子，
/// 既挡画面又和「点哪个按钮就在哪弹」的心理预期对不上。这里的做法是：
///
///   * 从被点的按钮（anchor）长出来，右边缘对齐、落在按钮下方；
///   * 卡片是浅色材质（圆角 14 / 发丝分隔线 / 强投影），跟 iOS 系统菜单一致；
///   * 展开用 spring 感（easeOutBack 轻微过冲）+ 淡入，焦点对准锚点那一角，
///     收起快而干脆；
///   * 打开、选中各给一次触觉。

/// 菜单材质色。iOS 的 UIMenu 是毛玻璃，视频在下面，这里用高不透明度浅色 +
/// 一层真实模糊（对解码画面无效，但对覆盖在上面的渐变遮罩有效），足够像。
const Color embyMenuBg = Color(0xFFF7F7F7);
const Color embyMenuInk = Color(0xFF101013);
const Color embyMenuInkSecondary = Color(0xFF8A8A8E);
const Color embyMenuHeaderBg = Color(0x14000000);
const Color embyMenuLine = Color(0x24000000);
const Color embyMenuPressed = Color(0x0F000000);
const Color embyMenuChecked = Color(0x0D3C3C43);

/// 一行菜单。
class EmbyMenuRow extends StatelessWidget {
  const EmbyMenuRow({
    super.key,
    required this.label,
    this.detail,
    this.icon,
    this.checked = false,
    this.chevron = false,
    this.destructive = false,
    this.enabled = true,
    this.onTap,
  });

  final String label;

  /// 副标题（编码信息、当前值这类），单独一行、字号小一号。
  final String? detail;
  final IconData? icon;
  final bool checked;

  /// 右侧 `>`，表示还会再弹一层。
  final bool chevron;
  final bool destructive;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = destructive
        ? const Color(0xFFD93025)
        : (enabled ? embyMenuInk : embyMenuInkSecondary);
    return _MenuPress(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        // 行自带发丝线：面板内部是一个整块 Column，外层插不进分隔线，
        // 每行自己画就不会漏。最后一行多出的那 0.5px 被卡片圆角裁掉了。
        decoration: BoxDecoration(
          color: checked ? embyMenuChecked : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: embyMenuLine, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 勾位常驻，勾不勾文字都对齐在同一条竖线上，切换时不会左右跳。
            SizedBox(
              width: 22,
              child: checked
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: embyMenuInk,
                    )
                  : null,
            ),
            if (icon != null) ...[
              Icon(icon, size: 17, color: ink),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 15.5,
                      height: 1.25,
                      fontWeight: checked ? FontWeight.w500 : FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (detail != null && detail!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: embyMenuInkSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (chevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: embyMenuInkSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组标题：灰底、居中的小字，和 iOS 菜单里的分组头一样。
class EmbyMenuHeader extends StatelessWidget {
  const EmbyMenuHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 34),
      alignment: Alignment.center,
      color: embyMenuHeaderBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: embyMenuInkSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// 只读信息行（媒体信息面板用）。
class EmbyMenuInfoRow extends StatelessWidget {
  const EmbyMenuInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                color: embyMenuInkSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: embyMenuInk,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按下反馈：底色压深一档 + 轻微缩放，比 InkWell 的涟漪更接近 iOS。
class _MenuPress extends StatefulWidget {
  const _MenuPress({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_MenuPress> createState() => _MenuPressState();
}

class _MenuPressState extends State<_MenuPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: _down ? 80 : 180),
        curve: Curves.easeOut,
        color: _down ? embyMenuPressed : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// 最近一次点击的按钮矩形。
///
/// 播放器同一时刻只会有一个菜单，用这个全局记录就够了：按钮在 onTap 里先
/// 把自己写到这儿，紧接着打开面板，面板拿它当锚点。这样 14 个调用点一行
/// 都不用改，也不会出现「菜单从屏幕右边凭空冒出来」。
Rect? embyLastAnchor;

/// 打开一个弹出菜单。
///
/// [anchor] 是触发按钮在屏幕上的矩形，菜单右边缘对齐它、落在它下方；下方
/// 放不下就整体上移。
Future<T?> showEmbyPopover<T>(
  BuildContext context, {
  required Rect anchor,
  required List<Widget> children,
  String? header,
  double width = 272,
  bool autoSeparators = true,
}) {
  final Size screen = MediaQuery.sizeOf(context);
  final double maxWidth = (screen.width - 24).clamp(160.0, width);

  // 右边缘贴住按钮；越界就夹回来。
  double left = anchor.right - maxWidth;
  if (left < 12) left = 12;
  if (left + maxWidth > screen.width - 12) {
    left = screen.width - maxWidth - 12;
  }

  // 上下各剩多少空间。菜单只在有空间的那一侧展开，并且**贴着按钮**：
  // 向上展开时用 bottom 定位，内容多高就往上长多高，不会在画面中间飘着。
  final double spaceBelow = screen.height - anchor.bottom - 18;
  final double spaceAbove = anchor.top - 18;
  final bool opensUpward = spaceBelow < 300 && spaceAbove > spaceBelow;
  final double maxHeight = (opensUpward ? spaceAbove : spaceBelow).clamp(
    140.0,
    460.0,
  );

  final double? top = opensUpward ? null : anchor.bottom + 8;
  final double? bottom = opensUpward ? (screen.height - anchor.top + 8) : null;

  // 焦点对准离按钮最近的那个角，缩放时看起来是从按钮里「长」出来的。
  final Alignment origin = opensUpward
      ? (left + maxWidth / 2 < anchor.center.dx
            ? Alignment.bottomLeft
            : Alignment.bottomRight)
      : (left + maxWidth / 2 < anchor.center.dx
            ? Alignment.topLeft
            : Alignment.topRight);

  unawaitedHaptic();

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    // iOS 菜单外面只压一点点，不是那种把画面压黑的遮罩。
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondary) {
      return _PopoverHost(
        animation: animation,
        origin: origin,
        left: left,
        top: top,
        bottom: bottom,
        width: maxWidth,
        maxHeight: maxHeight,
        header: header,
        autoSeparators: autoSeparators,
        children: children,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) => child,
  );
}

void unawaitedHaptic() {
  // 打开菜单给一次轻触觉；失败无所谓（部分安卓机型没有马达）。
  HapticFeedback.selectionClick();
}

class _PopoverHost extends StatelessWidget {
  const _PopoverHost({
    required this.animation,
    required this.origin,
    required this.left,
    required this.top,
    required this.bottom,
    required this.width,
    required this.maxHeight,
    required this.children,
    required this.autoSeparators,
    this.header,
  });

  final Animation<double> animation;
  final Alignment origin;
  final double left;
  final double? top;
  final double? bottom;
  final double width;
  final double maxHeight;
  final List<Widget> children;
  final bool autoSeparators;
  final String? header;

  List<Widget> _withSeparators() {
    if (!autoSeparators) return children;
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0 &&
          children[i] is! EmbyMenuHeader &&
          children[i - 1] is! EmbyMenuHeader) {
        out.add(const _MenuSeparator());
      }
      out.add(children[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // 展开：先快后慢、轻微过冲（iOS 菜单的 spring 感）；收起：干脆的加速淡出。
    final Animation<double> scale = animation.drive(
      Tween<double>(
        begin: 0.86,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
    );
    final Animation<double> fade = animation.drive(
      CurveTween(curve: const Interval(0, 0.7, curve: Curves.easeOut)),
    );

    return Stack(
      // 对话框给的是紧约束，这里显式铺满，免得某些平台下 Stack 缩成 0 尺寸。
      fit: StackFit.expand,
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: width,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              alignment: origin,
              child: _MenuCard(
                header: header,
                maxHeight: maxHeight,
                children: _withSeparators(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.children,
    required this.maxHeight,
    this.header,
  });

  final List<Widget> children;
  final double maxHeight;
  final String? header;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 34,
            spreadRadius: 2,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        // 不做 BackdropFilter：视频是原生纹理，模糊对它无效，只会白掉一层
        // layer 的重绘开销。iOS 菜单的质感靠高不透明度底色 + 强投影就够。
        child: Material(
          color: embyMenuBg,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null && header!.isNotEmpty)
                  EmbyMenuHeader(header!),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 0.5, thickness: 0.5, color: embyMenuLine);
  }
}
