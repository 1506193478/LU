/// Emby 页面共用的视觉组件。
///
/// 从「UI 优化预览」样板里提炼出来的可复用件：空状态、骨架块、信息行、
/// 可折叠技术信息、统计条。它们只描述"长什么样"，业务数据由调用方给，
/// 这样详情页 / 首页 / 统计页接同一套样式，不会再各画一套。
///
/// 设计护栏（沿用项目铁律）：
///   * 颜色一律走 [PvColors]，深浅色自动跟随，不写死色值；
///   * 所有动画时长走 [KazumiMotion.scale]，Reduce Motion 下直接到位；
///   * 骨架微光只作用在前景小块，不动背景层。
library;

import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/theme/ios_interaction.dart' show KzPressable;
import 'package:XL/utils/motion.dart';

/// 三层结构空状态：图标 + 标题 + 说明 + 主次操作。
///
/// 替代散落各处的「暂无数据」一句话。图标底色、按钮配色都跟主题走，
/// [danger] 只把强调色换成红色（连接失败这类场景）。
class EmbyEmptyState extends StatelessWidget {
  const EmbyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.danger = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool danger;

  /// 紧凑模式：嵌在列表卡片里时用，去掉外框和过多留白。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color accent =
        danger ? PvColors.red : PvColors.blue;
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 56 : 72,
          height: compact ? 56 : 72,
          decoration: BoxDecoration(
            color: danger
                ? PvColors.red.withValues(alpha: 0.10)
                : PvColors.capsule(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: compact ? 26 : 32, color: accent),
        ),
        SizedBox(height: compact ? 12 : 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: PvText.rowTitle(context).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: PvText.rowSub(context).copyWith(height: 1.5),
        ),
        if (primaryLabel != null || secondaryLabel != null) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (primaryLabel != null)
                EmbyPillButton(
                  label: primaryLabel!,
                  filled: true,
                  danger: danger,
                  onTap: onPrimary ?? () {},
                ),
              if (secondaryLabel != null)
                EmbyPillButton(
                  label: secondaryLabel!,
                  filled: false,
                  onTap: onSecondary ?? () {},
                ),
            ],
          ),
        ],
      ],
    );

    final Widget padded = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 20 : 28,
      ),
      child: content,
    );
    if (compact) return padded;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: padded,
      ),
    );
  }
}

/// 胶囊按钮，空状态的主次操作共用。
class EmbyPillButton extends StatelessWidget {
  const EmbyPillButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color bg = filled
        ? (danger ? PvColors.red : PvColors.blue)
        : Colors.transparent;
    final Color fg = filled ? Colors.white : PvColors.ink(context);
    return Semantics(
      button: true,
      label: label,
      child: KzPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            border: filled ? null : Border.all(color: PvColors.hair(context)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// 骨架块：前景微光占位，Reduce Motion 下是一块静态色。
class EmbyShimmer extends StatefulWidget {
  const EmbyShimmer({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<EmbyShimmer> createState() => _EmbyShimmerState();
}

class _EmbyShimmerState extends State<EmbyShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    // Reduce Motion 下不建控制器：静态骨架块，不跑微光。
    if (!KazumiMotion.reduceMotion(context)) {
      _controller = AnimationController(
        vsync: this,
        duration: KazumiMotion.scale(context, const Duration(milliseconds: 1400)),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = PvColors.isDark(context)
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFE5E5EA);
    final Widget block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: base,
      ),
    );
    final AnimationController? controller = _controller;
    if (controller == null) return block;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final double t = controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + t * 3.2, 0),
              end: Alignment(-0.6 + t * 3.2, 0),
              colors: [
                base,
                Color.lerp(base, Colors.white, 0.18)!,
                base,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 一行"图标 + 标签 + 值"的元信息。
class EmbyInfoRow extends StatelessWidget {
  const EmbyInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label：$value',
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: PvColors.ink3(context)),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Text(label, style: PvText.rowSub(context)),
            ),
            Expanded(
              child: Text(value, style: PvText.rowTitle(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 类型占比条：一条带标签和百分比的水平进度。
class EmbyGenreBar extends StatelessWidget {
  const EmbyGenreBar({
    super.key,
    required this.label,
    required this.value,
    this.last = false,
  });

  /// 0~1。
  final double value;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Semantics(
        label: '$label ${(v * 100).round()}%',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(label, style: PvText.rowSub(context)),
                ),
                const Spacer(),
                Text('${(v * 100).round()}%', style: PvText.count(context)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: v),
                duration: KazumiMotion.scale(
                  context,
                  const Duration(milliseconds: 600),
                ),
                curve: KazumiMotion.standard,
                builder: (context, t, _) => LinearProgressIndicator(
                  value: t,
                  minHeight: 7,
                  backgroundColor: PvColors.capsule(context),
                  valueColor: AlwaysStoppedAnimation<Color>(PvColors.blue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
