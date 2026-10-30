part of 'timeline_page.dart';

class _TimelineWeekSelector extends StatelessWidget {
  const _TimelineWeekSelector({
    required this.counts,
    this.todayIndex,
    this.isLoading = false,
  });

  final List<int> counts;
  final int? todayIndex;
  final bool isLoading;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static double heightFor(TextScaler scaler) =>
      40 + scaler.scale(20) + scaler.scale(16);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final minTabWidth = (scaler.scale(14) * 2 + 16).clamp(48.0, 112.0);
      final scrollable = constraints.maxWidth - 8 < minTabWidth * 7;
      // 圆角取半个条高做成胶囊。
      //
      // 原来写死 28，而这条高 76——圆角只占 37%，桌面端一根近 1000px 宽的
      // 条上，这个弧度视觉上等于直角；更要紧的是底色用的
      // `surfaceContainerLow`(#F6F7F9)，跟钉住头部画的
      // `scaffoldBackgroundColor`(#F5F6F8) 几乎同色，条和底衬糊成一片，
      // 圆角彻底看不见。
      //
      // 改成拟态的凹陷轨道（`recess` 比页面底色暗一档 + 内阴影 + 1px 硬描边），
      // 形状才立得住，也跟「分段控件是凹进去的」这套设计语言一致。
      final radius = heightFor(scaler) / 2;
      final indicatorRadius = radius - 4;
      return NeuSurface(
        mode: NeuMode.recess,
        radius: radius,
        padding: const EdgeInsets.all(4),
        child: TabBar(
          isScrollable: scrollable,
          tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
          dividerHeight: 0,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(indicatorRadius),
          ),
          indicatorAnimation: TabIndicatorAnimation.elastic,
          labelColor: colors.onPrimary,
          unselectedLabelColor: colors.onSurfaceVariant,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          overlayColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? colors.primary.withValues(alpha: .08)
                  : null),
          splashBorderRadius: BorderRadius.circular(indicatorRadius),
          tabs: [
            for (var day = 0; day < 7; day++)
              Tab(
                height: heightFor(scaler) - 8,
                child: Semantics(
                  label: '星期${_weekdays[day]}'
                      '${day == todayIndex ? '，今天' : ''}'
                      '${isLoading ? '，加载中' : '，${counts[day]}部'}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: scrollable ? minTabWidth : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day == todayIndex ? '今天' : '周${_weekdays[day]}'),
                        const SizedBox(height: 4),
                        Text(
                          isLoading ? '—' : '${counts[day]}',
                          style: TextStyle(
                            fontSize: theme.textTheme.labelSmall?.fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
