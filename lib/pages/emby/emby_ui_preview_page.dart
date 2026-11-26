/// Emby UI 优化预览（可交互 demo）。
///
/// 把「Hero 转场 / 骨架屏 / 空状态 / 触觉反馈 / 详情信息扩展 / 深色模式 /
/// 可访问性 / 智能推荐 / 观看统计」九项改进各自做成一个可点的演示页，
/// 用于评审视觉方向，不参与业务逻辑。
///
/// 入口：`/emby/ui-preview`。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/theme/ios_interaction.dart' show KzPressable;
import 'package:XL/theme/rex_design.dart';

class EmbyUIPreviewPage extends StatefulWidget {
  const EmbyUIPreviewPage({super.key});

  @override
  State<EmbyUIPreviewPage> createState() => _EmbyUIPreviewPageState();
}

class _DemoItem {
  const _DemoItem({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}

class _EmbyUIPreviewPageState extends State<EmbyUIPreviewPage> {
  int _selectedDemo = 0;

  static final List<_DemoItem> _demos = [
    _DemoItem(
      title: 'Hero 动画 + 骨架屏',
      icon: Icons.animation_rounded,
      builder: (_) => const _HeroAnimationDemo(),
    ),
    _DemoItem(
      title: '空状态美化',
      icon: Icons.inbox_rounded,
      builder: (_) => const _EmptyStateDemo(),
    ),
    _DemoItem(
      title: '触觉反馈',
      icon: Icons.vibration_rounded,
      builder: (_) => const _HapticFeedbackDemo(),
    ),
    _DemoItem(
      title: '详情页信息扩展',
      icon: Icons.info_outline_rounded,
      builder: (_) => const _DetailInfoDemo(),
    ),
    _DemoItem(
      title: '深色模式对比',
      icon: Icons.dark_mode_rounded,
      builder: (_) => const _DarkModeDemo(),
    ),
    _DemoItem(
      title: '可访问性改造',
      icon: Icons.accessibility_new_rounded,
      builder: (_) => const _AccessibilityDemo(),
    ),
    _DemoItem(
      title: '智能推荐卡片',
      icon: Icons.recommend_rounded,
      builder: (_) => const _SmartRecommendationDemo(),
    ),
    _DemoItem(
      title: '观看统计可视化',
      icon: Icons.bar_chart_rounded,
      builder: (_) => const _WatchStatsDemo(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Emby UI 优化预览'),
        backgroundColor: p.surface,
        foregroundColor: p.inkPrimary,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool wide = constraints.maxWidth >= 900;
          if (wide) {
            return Row(
              children: [
                SizedBox(width: 280, child: _menu(p)),
                Expanded(
                  child: ClipRect(
                    child: _demos[_selectedDemo].builder(context),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              _horizontalMenu(p),
              Expanded(
                child: ClipRect(
                  child: _demos[_selectedDemo].builder(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _menu(RexPalette p) {
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.hairline)),
      ),
      child: ListView.builder(
        itemCount: _demos.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, index) {
          final _DemoItem demo = _demos[index];
          final bool selected = index == _selectedDemo;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: KzPressable(
              onTap: () => setState(() => _selectedDemo = index),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? p.surfaceSunken : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      demo.icon,
                      size: 20,
                      color: selected ? p.inkPrimary : p.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        demo.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? p.inkPrimary : p.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _horizontalMenu(RexPalette p) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _demos.length,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemBuilder: (context, index) {
          final _DemoItem demo = _demos[index];
          final bool selected = index == _selectedDemo;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: KzPressable(
              onTap: () => setState(() => _selectedDemo = index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? p.surfaceSunken : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      demo.icon,
                      size: 18,
                      color: selected ? p.inkPrimary : p.inkSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      demo.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? p.inkPrimary : p.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 演示页通用外壳：标题 + 说明 + 内容。
class _DemoScaffold extends StatelessWidget {
  const _DemoScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: p.inkPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: p.inkSecondary)),
        const SizedBox(height: 20),
      ],
    );
    return Container(
      color: p.canvas,
      child: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [header, child],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.all(20), child: header),
                Expanded(child: child),
              ],
            ),
    );
  }
}

/// 海报占位块。演示页不依赖网络图片。
class _Poster extends StatelessWidget {
  const _Poster({required this.seed, this.radius = 12});

  final int seed;
  final double radius;

  static const List<List<Color>> _gradients = [
    [Color(0xFF2E3A59), Color(0xFF6C7FA8)],
    [Color(0xFF4A2E3A), Color(0xFFA86C7F)],
    [Color(0xFF2E4A3A), Color(0xFF6CA88A)],
    [Color(0xFF4A4230), Color(0xFFA89664)],
    [Color(0xFF322E4A), Color(0xFF7F6CA8)],
    [Color(0xFF4A322E), Color(0xFFA8776C)],
  ];

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = _gradients[seed % _gradients.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 28,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 1. Hero 动画 + 骨架屏
// ============================================================

class _HeroAnimationDemo extends StatelessWidget {
  const _HeroAnimationDemo();

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return _DemoScaffold(
      scrollable: false,
      title: 'Hero 动画 + 骨架屏',
      subtitle: '点海报看封面无缝转场；详情页先出骨架，数据到了再淡入',
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.62,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
        ),
        itemCount: 9,
        itemBuilder: (context, index) {
          return KzPressable(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _HeroDetailPage(index: index),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Hero(
                    tag: 'preview-poster-$index',
                    child: _Poster(seed: index),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '示例剧集 ${index + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.inkPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '2024 · 全 ${12 + index} 集',
                  style: TextStyle(fontSize: 11, color: p.inkTertiary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroDetailPage extends StatefulWidget {
  const _HeroDetailPage({required this.index});

  final int index;

  @override
  State<_HeroDetailPage> createState() => _HeroDetailPageState();
}

class _HeroDetailPageState extends State<_HeroDetailPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400)).then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: p.canvas,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: AnimatedOpacity(
                opacity: _loading ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  '示例剧集 ${widget.index + 1}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              titlePadding:
                  const EdgeInsets.only(left: 52, right: 16, bottom: 14),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'preview-poster-${widget.index}',
                    child: _Poster(seed: widget.index, radius: 0),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _loading
                    ? const _DetailSkeleton()
                    : const _DetailLoaded(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Color base = p.isDark ? p.surfaceRaised : p.surfaceSunken;
    return Column(
      key: const ValueKey('skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SkeletonBox(width: 48, height: 16, color: base),
            const SizedBox(width: 12),
            _SkeletonBox(width: 120, height: 16, color: base),
          ],
        ),
        const SizedBox(height: 14),
        _SkeletonBox(width: 96, height: 28, color: base),
        const SizedBox(height: 20),
        _SkeletonBox(width: double.infinity, height: 46, color: base),
        const SizedBox(height: 18),
        Row(
          children: [
            _SkeletonBox(width: 52, height: 52, color: base, borderRadius: 26),
            const SizedBox(width: 14),
            _SkeletonBox(width: 52, height: 52, color: base, borderRadius: 26),
            const SizedBox(width: 14),
            _SkeletonBox(width: 52, height: 52, color: base, borderRadius: 26),
          ],
        ),
        const SizedBox(height: 24),
        _SkeletonBox(width: double.infinity, height: 13, color: base),
        const SizedBox(height: 8),
        _SkeletonBox(width: double.infinity, height: 13, color: base),
        const SizedBox(height: 8),
        _SkeletonBox(width: 220, height: 13, color: base),
        const SizedBox(height: 28),
        _SkeletonBox(width: 140, height: 16, color: base),
        const SizedBox(height: 14),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, _) =>
                _SkeletonBox(width: 150, height: 120, color: base),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.color,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final Color color;
  final double borderRadius;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + t * 3.2, 0),
              end: Alignment(-0.6 + t * 3.2, 0),
              colors: [
                widget.color,
                Color.lerp(widget.color, Colors.white, 0.18)!,
                widget.color,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class _DetailLoaded extends StatelessWidget {
  const _DetailLoaded();

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Column(
      key: const ValueKey('loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF2C14E)),
            const SizedBox(width: 4),
            Text('9.2',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.inkPrimary)),
            const SizedBox(width: 14),
            Text('2024 · 24 集 · 科幻',
                style: TextStyle(fontSize: 13, color: p.inkSecondary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.circular(6),
              ),
              child:
                  Text('4K', style: TextStyle(fontSize: 11, color: p.inkSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, color: p.accentInk, size: 22),
              const SizedBox(width: 6),
              Text('继续观看 第 5 集',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.accentInk)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _RoundAction(icon: Icons.check_rounded, label: '已看'),
            const SizedBox(width: 22),
            _RoundAction(icon: Icons.favorite_border_rounded, label: '收藏'),
            const SizedBox(width: 22),
            _RoundAction(icon: Icons.download_outlined, label: '下载'),
            const SizedBox(width: 22),
            _RoundAction(icon: Icons.more_horiz_rounded, label: '更多'),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          '一场跨越星系的远征，把人类文明最后的火种送向未知。'
          '剧情紧凑，视听语言极佳，是本年度最值得一看的科幻剧集。',
          style: TextStyle(fontSize: 14, height: 1.6, color: p.inkPrimary),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Text('剧集',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.inkPrimary)),
            const Spacer(),
            Text('共 24 集',
                style: TextStyle(fontSize: 12, color: p.inkTertiary)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 12,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return Container(
                width: 128,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: index == 4 ? p.accent : p.hairline,
                    width: index == 4 ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('第 ${index + 1} 集',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.inkPrimary)),
                    const Spacer(),
                    Text(index == 4 ? '观看至 12:30' : '42 分钟',
                        style:
                            TextStyle(fontSize: 11, color: p.inkTertiary)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: p.surface,
            shape: BoxShape.circle,
            border: Border.all(color: p.hairline),
          ),
          child: Icon(icon, size: 22, color: p.inkPrimary),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: p.inkSecondary)),
      ],
    );
  }
}

// ============================================================
// 2. 空状态美化
// ============================================================

class _EmptyStateDemo extends StatelessWidget {
  const _EmptyStateDemo();

  @override
  Widget build(BuildContext context) {
    return _DemoScaffold(
      title: '空状态美化',
      subtitle: '图标 / 标题 / 说明 / 主次操作三层结构，替代一句干巴巴的提示',
      child: Column(
        children: [
          _EmptyCard(
            icon: Icons.video_library_outlined,
            title: '还没有添加内容',
            message: '从 Emby 服务器同步媒体库，或手动添加视频文件。',
            primaryLabel: '浏览媒体库',
            secondaryLabel: '添加服务器',
            onPrimary: () {},
            onSecondary: () {},
          ),
          const SizedBox(height: 16),
          _EmptyCard(
            icon: Icons.search_off_rounded,
            title: '没有找到相关内容',
            message: '换个关键词试试，或者检查一下拼写。',
            primaryLabel: '清除搜索',
            onPrimary: () {},
          ),
          const SizedBox(height: 16),
          _EmptyCard(
            icon: Icons.wifi_off_rounded,
            title: '连接失败',
            message: '无法连接到 Emby 服务器，请检查网络或服务器地址。',
            primaryLabel: '重试',
            secondaryLabel: '切换服务器',
            danger: true,
            onPrimary: () {},
            onSecondary: () {},
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Color tint = danger ? p.danger : p.inkPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color:
                  danger ? p.danger.withValues(alpha: 0.10) : p.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: tint),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: p.inkPrimary)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: p.inkSecondary),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _PillButton(
                label: primaryLabel,
                filled: true,
                danger: danger,
                onTap: onPrimary,
              ),
              if (secondaryLabel != null)
                _PillButton(
                  label: secondaryLabel!,
                  filled: false,
                  onTap: onSecondary ?? () {},
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
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
    final RexPalette p = RexPalette.of(context);
    final Color bg =
        filled ? (danger ? p.danger : p.accent) : Colors.transparent;
    final Color fg =
        filled ? (danger ? Colors.white : p.accentInk) : p.inkPrimary;
    return KzPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          border: filled ? null : Border.all(color: p.hairlineStrong),
        ),
        child: Text(
          label,
          style:
              TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
        ),
      ),
    );
  }
}

// ============================================================
// 3. 触觉反馈
// ============================================================

class _HapticFeedbackDemo extends StatefulWidget {
  const _HapticFeedbackDemo();

  @override
  State<_HapticFeedbackDemo> createState() => _HapticFeedbackDemoState();
}

class _HapticFeedbackDemoState extends State<_HapticFeedbackDemo> {
  String _last = '点下面的按钮试一下（桌面端没有马达，只在移动端有反馈）';

  void _fire(String name, VoidCallback haptic) {
    haptic();
    setState(() => _last = '已触发：$name');
  }

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return _DemoScaffold(
      title: '触觉反馈',
      subtitle: '按操作权重分级：点选轻、播放中、删除重',
      child: Column(
        children: [
          _HapticRow(
            title: 'Light Impact',
            scene: '切换页签 / 选中卡片',
            onTap: () => _fire('Light Impact', HapticFeedback.lightImpact),
          ),
          _HapticRow(
            title: 'Medium Impact',
            scene: '播放 / 暂停 / 收藏',
            onTap: () => _fire('Medium Impact', HapticFeedback.mediumImpact),
          ),
          _HapticRow(
            title: 'Heavy Impact',
            scene: '删除 / 关键确认',
            onTap: () => _fire('Heavy Impact', HapticFeedback.heavyImpact),
          ),
          _HapticRow(
            title: 'Selection Click',
            scene: '滚动选择器 / 拖动进度',
            onTap: () =>
                _fire('Selection Click', HapticFeedback.selectionClick),
          ),
          _HapticRow(
            title: 'Vibrate',
            scene: '长按拖拽排序',
            onTap: () => _fire('Vibrate', HapticFeedback.vibrate),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: p.inkSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_last,
                      style: TextStyle(fontSize: 13, color: p.inkSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HapticRow extends StatelessWidget {
  const _HapticRow({
    required this.title,
    required this.scene,
    required this.onTap,
  });

  final String title;
  final String scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KzPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.vibration_rounded, size: 20, color: p.inkSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.inkPrimary)),
                    const SizedBox(height: 2),
                    Text(scene,
                        style: TextStyle(fontSize: 12, color: p.inkTertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: p.inkTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 4. 详情页信息扩展
// ============================================================

class _DetailInfoDemo extends StatefulWidget {
  const _DetailInfoDemo();

  @override
  State<_DetailInfoDemo> createState() => _DetailInfoDemoState();
}

class _DetailInfoDemoState extends State<_DetailInfoDemo> {
  bool _showTech = false;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return _DemoScaffold(
      title: '详情页信息扩展',
      subtitle: '基础元数据常驻，技术信息折叠，避免一屏塞满',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              children: [
                _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: '首播',
                    value: '2024 年 1 月'),
                _InfoRow(
                    icon: Icons.tv_rounded, label: '集数', value: '24 集全'),
                _InfoRow(
                    icon: Icons.category_outlined,
                    label: '类型',
                    value: '科幻 / 悬疑 / 惊悚'),
                _InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: '导演',
                    value: '陈默'),
                _InfoRow(
                    icon: Icons.people_outline_rounded,
                    label: '主演',
                    value: '林墨 / 苏晚 / 周野'),
                _InfoRow(
                    icon: Icons.language_rounded, label: '语言', value: '中文 / 英文'),
                _InfoRow(
                    icon: Icons.flag_outlined,
                    label: '地区',
                    value: '中国大陆',
                    last: true),
                Divider(color: p.hairline, height: 24),
                KzPressable(
                  onTap: () => setState(() => _showTech = !_showTech),
                  child: Row(
                    children: [
                      Icon(Icons.memory_rounded,
                          size: 18, color: p.inkSecondary),
                      const SizedBox(width: 10),
                      Text('技术信息',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.inkPrimary)),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _showTech ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.expand_more_rounded,
                            size: 20, color: p.inkTertiary),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: _showTech
                      ? Column(
                          children: [
                            const SizedBox(height: 8),
                            _InfoRow(
                                icon: Icons.video_settings_outlined,
                                label: '视频编码',
                                value: 'H.265 (HEVC)'),
                            _InfoRow(
                                icon: Icons.high_quality_outlined,
                                label: '分辨率',
                                value: '3840 × 2160 (4K)'),
                            _InfoRow(
                                icon: Icons.speed_rounded,
                                label: '码率',
                                value: '15.2 Mbps'),
                            _InfoRow(
                                icon: Icons.audiotrack_rounded,
                                label: '音频',
                                value: 'AAC 5.1 384 kbps'),
                            _InfoRow(
                                icon: Icons.subtitles_outlined,
                                label: '字幕',
                                value: '中文 / 英文 / 日文',
                                last: true),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
    final RexPalette p = RexPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: p.inkTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child:
                Text(label, style: TextStyle(fontSize: 13, color: p.inkSecondary)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, color: p.inkPrimary)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 5. 深色模式对比
// ============================================================

class _DarkModeDemo extends StatelessWidget {
  const _DarkModeDemo();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 760;
        final Widget light = _ModePreview(palette: RexPalette.light);
        final Widget dark = _ModePreview(palette: RexPalette.dark);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: light),
              Expanded(child: dark),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: light),
            Expanded(child: dark),
          ],
        );
      },
    );
  }
}

class _ModePreview extends StatelessWidget {
  const _ModePreview({required this.palette});

  final RexPalette palette;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = palette;
    return ColoredBox(
      color: p.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  p.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size: 16,
                  color: p.inkSecondary,
                ),
                const SizedBox(width: 6),
                Text(p.isDark ? '深色' : '浅色',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.inkSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('继续观看',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.inkPrimary)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                          width: 56,
                          height: 76,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _Poster(seed: 1, radius: 8),
                          )),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('示例剧集',
                                style: TextStyle(
                                    fontSize: 13, color: p.inkPrimary)),
                            const SizedBox(height: 4),
                            Text('第 5 集 · 剩余 28 分钟',
                                style: TextStyle(
                                    fontSize: 11, color: p.inkTertiary)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: 0.42,
                                minHeight: 4,
                                backgroundColor: p.surfaceSunken,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    p.accent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text('主要操作',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.accentInk)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.hairlineStrong),
                    ),
                    child: Center(
                      child: Text('次要操作',
                          style:
                              TextStyle(fontSize: 13, color: p.inkPrimary)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: p.surfaceSunken,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('标签',
                      style: TextStyle(fontSize: 13, color: p.inkSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '正文文字对比度检查：inkPrimary 用于标题与正文，inkSecondary '
              '用于辅助说明，hairline 只做 1px 分隔，不承载信息。',
              style:
                  TextStyle(fontSize: 12, height: 1.6, color: p.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 6. 可访问性
// ============================================================

class _AccessibilityDemo extends StatefulWidget {
  const _AccessibilityDemo();

  @override
  State<_AccessibilityDemo> createState() => _AccessibilityDemoState();
}

class _AccessibilityDemoState extends State<_AccessibilityDemo> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return _DemoScaffold(
      title: '可访问性改造',
      subtitle: '拖滑块模拟系统字体放大；布局用 Expanded / Wrap，不写死高度',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Text('字体',
                    style: TextStyle(fontSize: 13, color: p.inkSecondary)),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text('${(_scale * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 13, color: p.inkPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(_scale)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: '播放按钮',
                  hint: '点击开始播放视频',
                  child: KzPressable(
                    onTap: () {},
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color: p.accentInk, size: 22),
                          const SizedBox(width: 6),
                          Text('播放',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: p.accentInk)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: Text('示例剧集名称',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: p.inkPrimary)),
                ),
                const SizedBox(height: 10),
                Text(
                  '字号放大后按钮高度、卡片行高都跟着涨。角色用 Semantics 标注，'
                  '读屏软件能读出「播放按钮」而不是「播放」。',
                  style: TextStyle(
                      fontSize: 14, height: 1.55, color: p.inkPrimary),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PillButton(label: '已看', filled: false, onTap: () {}),
                    _PillButton(label: '收藏', filled: false, onTap: () {}),
                    _PillButton(label: '下载', filled: false, onTap: () {}),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 7. 智能推荐
// ============================================================

class _SmartRecommendationDemo extends StatelessWidget {
  const _SmartRecommendationDemo();

  static const List<List<int>> _rows = [
    [1, 2, 3, 4],
    [5, 0, 2, 3],
    [4, 1, 5, 0],
  ];

  static const List<String> _reasons = [
    '因为你看了《星际穿越》',
    '你常看科幻 · 悬疑',
    '本周热门',
  ];

  @override
  Widget build(BuildContext context) {
    return _DemoScaffold(
      title: '智能推荐卡片',
      subtitle: '推荐理由摆在最前面，用户知道「为什么给我看这个」',
      child: Column(
        children: [
          for (int i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _RecommendRow(reason: _reasons[i], seeds: _rows[i]),
            ),
        ],
      ),
    );
  }
}

class _RecommendRow extends StatelessWidget {
  const _RecommendRow({required this.reason, required this.seeds});

  final String reason;
  final List<int> seeds;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: p.inkSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(reason,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.inkPrimary)),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: p.inkTertiary),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seeds.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final int seed = seeds[index];
                return SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: _Poster(seed: seed)),
                            Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${90 - index * 4}%',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text('推荐片单 ${seed + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: p.inkPrimary)),
                      const SizedBox(height: 2),
                      Text('科幻 · 2023',
                          style:
                              TextStyle(fontSize: 10, color: p.inkTertiary)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 8. 观看统计
// ============================================================

class _WatchStatsDemo extends StatelessWidget {
  const _WatchStatsDemo();

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return _DemoScaffold(
      title: '观看统计可视化',
      subtitle: '概览数字 + 周趋势 + 类型占比，数据全部来自本地观看记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                icon: Icons.play_circle_outline_rounded,
                value: '156',
                label: '观看次数',
              ),
              _StatCard(
                icon: Icons.schedule_rounded,
                value: '48.5 h',
                label: '总时长',
              ),
              _StatCard(
                icon: Icons.local_fire_department_outlined,
                value: '17 天',
                label: '连续观看',
              ),
              _StatCard(
                icon: Icons.favorite_border_rounded,
                value: '12',
                label: '收藏',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('本周观看',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: p.inkPrimary)),
                    const Spacer(),
                    Text('合计 30.3 h',
                        style:
                            TextStyle(fontSize: 12, color: p.inkTertiary)),
                  ],
                ),
                const SizedBox(height: 18),
                const _WeeklyBars(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('类型分布',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.inkPrimary)),
                const SizedBox(height: 16),
                const _GenreBar(label: '科幻', value: 0.45),
                const _GenreBar(label: '剧情', value: 0.30),
                const _GenreBar(label: '动作', value: 0.15),
                const _GenreBar(label: '喜剧', value: 0.10, last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Container(
      width: 156,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: p.inkPrimary),
          ),
          const SizedBox(height: 14),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.inkPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: p.inkTertiary)),
        ],
      ),
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars();

  static const List<double> _hours = [3.5, 2.8, 4.2, 5.5, 3.0, 6.5, 4.8];
  static const List<String> _days = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final double maxHour = _hours.reduce(math.max);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < _hours.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${_hours[i]}',
                        style: TextStyle(fontSize: 10, color: p.inkTertiary)),
                    const SizedBox(height: 5),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _hours[i] / maxHour),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) {
                        return Container(
                          height: 96 * t,
                          decoration: BoxDecoration(
                            color: i == 5
                                ? p.accent
                                : p.accent.withValues(alpha: 0.22),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 7),
                    Text(_days[i],
                        style: TextStyle(fontSize: 10, color: p.inkTertiary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GenreBar extends StatelessWidget {
  const _GenreBar({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final double value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: p.inkPrimary)),
              ),
              const Spacer(),
              Text('${(value * 100).round()}%',
                  style: TextStyle(fontSize: 11, color: p.inkTertiary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                return LinearProgressIndicator(
                  value: t,
                  minHeight: 7,
                  backgroundColor: p.surfaceSunken,
                  valueColor: AlwaysStoppedAnimation<Color>(p.accent),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
