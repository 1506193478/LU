import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart' show PvColors;
import 'package:XL/utils/motion.dart';

/// 「今日选片」卡片堆叠（B19）：顶部一张卡可横向拖拽，
/// 超过阈值/快甩沿手势方向飞出，下一张从 0.95 放大补位；不够则弹回。
///
/// 放在推荐页顶部，占位很小（高 132）；卡片数据为空时整块不渲染。
class PopularDeck extends StatefulWidget {
  const PopularDeck({
    super.key,
    required this.items,
    required this.onOpen,
  });

  /// 候选条目：标题 + 封面 URL。
  final List<({String title, String cover, String? meta})> items;
  final ValueChanged<int> onOpen;

  @override
  State<PopularDeck> createState() => _PopularDeckState();
}

class _PopularDeckState extends State<PopularDeck> {
  int _top = 0;
  Offset _dragOffset = Offset.zero;
  Offset? _start;
  DateTime _downAt = DateTime.now();

  int get _count => widget.items.length;
  bool get _hasCards => _count >= 2;

  void _flyOut(double dir) {
    // 飞出动画期间禁用再拖；结束后补位。
    setState(() => _dragOffset = Offset(dir * 480, 0));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _top = (_top + 1) % _count;
        _dragOffset = Offset.zero;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCards) return const SizedBox.shrink();
    return SizedBox(
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var back = math.min(_count - 1, 2); back >= 1; back--)
            Transform.translate(
              offset: Offset(0, back * 8),
              child: Transform.scale(
                scale: 0.95 - (back - 1) * 0.02,
                child: Opacity(
                  opacity: 1 - (back - 1) * 0.35,
                  child: _deckCard(((_top + back) % _count), interactive: false),
                ),
              ),
            ),
          // 顶部卡：跟手 + 倾斜。
          Transform.translate(
            offset: _dragOffset,
            child: Transform.rotate(
              angle: _dragOffset.dx / 16 * math.pi / 180,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _start = d.globalPosition;
                  _downAt = DateTime.now();
                },
                onPanUpdate: (d) {
                  if (_start == null) return;
                  setState(() => _dragOffset = d.globalPosition - _start!);
                },
                onPanEnd: (d) {
                  if (_start == null) return;
                  _start = null;
                  final dx = _dragOffset.dx;
                  final double vx =
                      d.velocity.pixelsPerSecond.dx / 1000;
                  if (dx.abs() > 90 || vx.abs() > 0.5) {
                    final dir = (dx == 0 ? vx : dx).sign;
                    KazumiHaptics.select();
                    _flyOut(dir);
                  } else {
                    setState(() => _dragOffset = Offset.zero);
                  }
                },
                onTap: () => widget.onOpen(_top),
                child: _deckCard(_top),
              ),
            ),
          ),
          // 提示文案。
          if (_dragOffset == Offset.zero)
            Positioned(
              bottom: 2,
              child: Text(
                '左右滑动换一部 · 点按打开',
                style: TextStyle(
                  fontSize: 10.5,
                  color: PvColors.ink3(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deckCard(int index, {bool interactive = true}) {
    final item = widget.items[index];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: interactive ? () => widget.onOpen(index) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 220,
          height: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: NetworkImage(item.cover),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Color(0x88000000), blurRadius: 8)],
                ),
              ),
              if (item.meta != null)
                Text(
                  item.meta!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10.5,
                    shadows: const [Shadow(color: Color(0x88000000), blurRadius: 8)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
