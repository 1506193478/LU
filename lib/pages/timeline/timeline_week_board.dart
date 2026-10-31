part of 'timeline_page.dart';

/// 桌面宽屏的「一周七列」时间表。
///
/// 手机和窄窗口仍然走上面那套「一天一页 + 顶部周条」——一列挤到 130 宽以后
/// 标题只能放下三四个字，信息密度反而比翻页差。
class _TimelineWeekBoard extends StatelessWidget {
  const _TimelineWeekBoard({
    required this.calendar,
    required this.watchingIds,
    required this.showRating,
    required this.loading,
    required this.failed,
    required this.inset,
    required this.compact,
    required this.header,
    required this.todayIndex,
    required this.onRetry,
  });

  final List<List<BangumiItem>> calendar;
  final Set<int> watchingIds;
  final bool showRating;
  final bool loading;
  final bool failed;
  final double inset;
  final bool compact;
  final Widget? header;
  final int? todayIndex;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: kazumiScrollPhysics,
      slivers: [
        if (header != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 8, inset, 20),
              child: header,
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, 0, inset, 8),
          sliver: SliverToBoxAdapter(child: _buildBody(context)),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: immersiveTabBarInset(context) + 16),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (failed) {
      return BangumiMirrorErrorWidget(
        onRetry: onRetry,
        onSettingsReturned: () {},
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var day = 0; day < 7; day++) ...[
          if (day > 0) const SizedBox(width: 12),
          Expanded(
            child: _TimelineDayColumn(
              day: day,
              items: loading ? const <BangumiItem>[] : calendar[day],
              isToday: day == todayIndex,
              isLoading: loading,
              compact: compact,
              showRating: showRating,
              watchingIds: watchingIds,
            ),
          ),
        ],
      ],
    );
  }
}

class _TimelineDayColumn extends StatelessWidget {
  const _TimelineDayColumn({
    required this.day,
    required this.items,
    required this.isToday,
    required this.isLoading,
    required this.compact,
    required this.showRating,
    required this.watchingIds,
  });

  final int day;
  final List<BangumiItem> items;
  final bool isToday;
  final bool isLoading;
  final bool compact;
  final bool showRating;
  final Set<int> watchingIds;

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return NeuSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday ? colors.primary : Colors.transparent,
                  ),
                ),
                if (isToday) const SizedBox(width: 6),
                Text(
                  isToday ? '今天' : _weekdays[day],
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isToday ? colors.primary : colors.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  isLoading ? '—' : '${items.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: compact ? 52 : 56,
                  child: const BangumiRowSkeleton(compact: true, coverWidth: 40),
                ),
              )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '暂无放送',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _TimelineMiniRow(
                  item: item,
                  compact: compact,
                  showRating: showRating,
                  isWatching: watchingIds.contains(item.id),
                  onTap: () => context.pushNamed('/info/', arguments: item),
                ),
              ),
        ],
      ),
    );
  }
}

/// 七列里的一行：小封面 + 两行字。整列宽度只有 150 上下，
/// 用时间表那种 88 宽封面的横卡会把标题压成一条竖线。
class _TimelineMiniRow extends StatelessWidget {
  const _TimelineMiniRow({
    required this.item,
    required this.compact,
    required this.showRating,
    required this.isWatching,
    required this.onTap,
  });

  final BangumiItem item;
  final bool compact;
  final bool showRating;
  final bool isWatching;
  final VoidCallback onTap;

  static final _episodePattern =
      RegExp(r'^\s*([1-9]\d*)\s*[话話集](?=\s*(?:[/／]|$))');

  String get _title {
    final cn = item.nameCn.trim();
    return cn.isNotEmpty ? cn : item.name.trim();
  }

  String get _meta {
    final List<String> parts = <String>[];
    final episodes = _episodePattern.firstMatch(item.info);
    if (episodes != null) parts.add('${episodes.group(1)} 话');
    if (showRating && item.ratingScore > 0) {
      parts.add(item.ratingScore.toStringAsFixed(1));
    }
    final tags = item.metaTags.isNotEmpty
        ? item.metaTags
        : item.tags.map((tag) => tag.name);
    for (final name in tags) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || parts.contains(trimmed)) continue;
      parts.add(trimmed);
      if (parts.length >= 2) break;
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String title = _title;
    final String meta = _meta;
    final String cover = item.images['large'] ?? item.images['common'] ?? '';
    final double coverHeight = compact ? 52 : 56;

    return Pressable(
      haptic: false,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: 40,
                height: coverHeight,
                child: Hero(
                  tag: item.id,
                  transitionOnUserGestures: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: cover.isEmpty
                        ? ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie_outlined,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          )
                        : NetworkImgLayer(
                            src: cover,
                            width: 40,
                            height: coverHeight,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (isWatching) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.bookmark_rounded,
                            size: 12, color: colors.primary),
                        const SizedBox(width: 3),
                        Text(
                          '在追',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
