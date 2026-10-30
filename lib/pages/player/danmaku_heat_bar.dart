import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:XL/modules/danmaku/danmaku_module.dart';
import 'package:XL/pages/player/player_controller.dart';
import 'package:XL/services/player/danmaku_heatmap.dart';
import 'package:XL/utils/format.dart';

/// 进度条上面那条弹幕热力条。
///
/// 一眼看出本集哪段最热闹，点一下直接跳过去；长按看「高能时刻」列表。
/// 数据全在本地（弹幕按秒存着），不联网、不加依赖。
///
/// 高度只有 8：它贴在进度条上，是「参考信息」不是「控件」，
/// 抢走视觉重心就本末倒置了。
class DanmakuHeatBar extends StatefulWidget {
  const DanmakuHeatBar({
    super.key,
    required this.bySecond,
    required this.revision,
    required this.duration,
    required this.sideLabels,
    required this.onSeek,
    this.onLongPress,
  });

  /// 弹幕本体：秒 → 这一秒的弹幕列表。
  final Map<int, List<DanmakuEntry>> bySecond;

  /// 弹幕集合的版本号。Map 是原地改的，光看长度不一定能发现变化。
  final ValueListenable<int> revision;

  final Duration duration;

  /// 侧边有时间标签时，进度轨道会内缩，热力条要跟着缩。
  final bool sideLabels;

  final ValueChanged<Duration> onSeek;
  final VoidCallback? onLongPress;

  @override
  State<DanmakuHeatBar> createState() => _DanmakuHeatBarState();
}

class _DanmakuHeatBarState extends State<DanmakuHeatBar> {
  static const int _buckets = 96;

  List<double> _bars = const <double>[];
  int _cachedRevision = -1;
  int _cachedDuration = -1;

  @override
  void initState() {
    super.initState();
    widget.revision.addListener(_rebuild);
    _ensureBars();
  }

  @override
  void didUpdateWidget(covariant DanmakuHeatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      oldWidget.revision.removeListener(_rebuild);
      widget.revision.addListener(_rebuild);
    }
    _ensureBars();
  }

  @override
  void dispose() {
    widget.revision.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    _ensureBars(force: true);
  }

  void _ensureBars({bool force = false}) {
    final int revision = widget.revision.value;
    final int durationSeconds = widget.duration.inSeconds;
    if (!force &&
        revision == _cachedRevision &&
        durationSeconds == _cachedDuration) {
      return;
    }
    _cachedRevision = revision;
    _cachedDuration = durationSeconds;
    final List<double> next = DanmakuHeatmap.densities(
      seconds: widget.bySecond.keys,
      durationSeconds: durationSeconds,
      buckets: _buckets,
    );
    if (mounted) {
      setState(() => _bars = next);
    } else {
      _bars = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bars.isEmpty || widget.duration <= Duration.zero) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    // 和进度条的圆头对齐：轨道两端各留半个条高。
    final double inset =
        widget.sideLabels ? _labelInset(context) + 2.5 : 2.5;
    return LayoutBuilder(builder: (context, constraints) {
      final double usable = constraints.maxWidth - inset * 2;
      return Tooltip(
        message: widget.onLongPress == null
            ? '弹幕热力 · 点一下跳过去'
            : '弹幕热力 · 点一下跳过去，长按看高能时刻',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (usable <= 0) return;
            final double fraction =
                ((details.localPosition.dx - inset) / usable).clamp(0.0, 1.0);
            widget.onSeek(Duration(
              milliseconds:
                  (widget.duration.inMilliseconds * fraction).round(),
            ));
          },
          onLongPress: widget.onLongPress,
          child: SizedBox(
            height: 8,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: CustomPaint(
                painter: _HeatPainter(
                  bars: _bars,
                  color: colors.primary,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      );
    });
  }

  /// 侧边时间标签占的宽度，和进度条内部算法一致。
  double _labelInset(BuildContext context) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: durationToString(widget.duration),
        style: const TextStyle(fontSize: 12, fontFeatures: [
          FontFeature.tabularFigures(),
        ]),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width + 13;
  }
}

class _HeatPainter extends CustomPainter {
  const _HeatPainter({required this.bars, required this.color});

  final List<double> bars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    final double step = size.width / bars.length;
    final double barWidth = step * 0.62;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < bars.length; i++) {
      final double value = bars[i].clamp(0.0, 1.0);
      if (value <= 0) continue;
      // 再冷清也留 1.5px 高，否则稀疏的段落看着像「没有弹幕」。
      final double height = 1.5 + (size.height - 1.5) * value;
      paint.color = color.withValues(alpha: 0.18 + 0.62 * value);
      final Rect rect = Rect.fromLTWH(
        i * step + (step - barWidth) / 2,
        size.height - height,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.color != color;
}

/// 高能时刻：本集弹幕最密的几段，点一下跳过去。
Future<void> showDanmakuHotspotsSheet(
  BuildContext context, {
  required PlayerController playerController,
}) async {
  final int durationSeconds = playerController.playback.duration.inSeconds;
  final List<DanmakuHotspot> spots = DanmakuHeatmap.hotspots(
    seconds: playerController.danmaku.danDanmakus.keys,
    durationSeconds: durationSeconds,
  );
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final ThemeData theme = Theme.of(sheetContext);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '本集高能时刻',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                spots.isEmpty
                    ? '这集还没有足够的弹幕可以统计。'
                    : '按二十秒窗口里弹幕最多的地方挑出来的，点一下跳过去。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final DanmakuHotspot spot in spots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bolt_rounded),
                  title: Text(durationToString(spot.position)),
                  subtitle: Text('${spot.count} 条弹幕'),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    playerController.seek(spot.position);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
