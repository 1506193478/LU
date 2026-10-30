part of 'search_page.dart';

const _searchSortLabels = {
  'heat': '热度',
  'rank': '排名',
  'score': '评分',
  'match': '匹配',
};

String _sortLabel(String sort) => _searchSortLabels[sort] ?? '热度';

/// 用真实的文字排版量一次高度（要跟系统字号缩放走，不能用固定像素）。
double _measureTextHeight(
    BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout();
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

String _filterSummary(SearchFilterState state) => [
      ...state.tags,
      if (state.season.isNotEmpty) state.season,
      if (state.season.isEmpty && state.dateRange != null)
        '${state.dateRange!.start} 至 ${state.dateRange!.end}',
      if (state.scoreRange?.isValid == true)
        '评分 ${state.scoreRange!.toToken()}',
      if (state.rankRange?.isValid == true) '排名 ${state.rankRange!.toToken()}',
      if (state.weekdays.isNotEmpty)
        '周${state.weekdays.map((day) => '一二三四五六日'[day - 1]).join('、')}',
    ].join(' · ');

String _readableQuery(String query) {
  final state = SearchParser(query).toFilterState();
  final summary = _filterSummary(state);
  return [
    if (state.keyword.isNotEmpty) state.keyword,
    if (state.id.isNotEmpty) '条目 ${state.id}',
    if (summary.isNotEmpty) summary,
    if (state.sort != 'heat') '${_sortLabel(state.sort)}排序',
  ].join(' · ');
}

class _SearchSortMenu extends StatelessWidget {
  const _SearchSortMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KazumiMenuButton(
      animated: true,
      menuChildren: [
        for (final sort in _searchSortLabels.entries)
          KazumiMenuItem(
            label: '按${sort.value}排序',
            selected: sort.key == value,
            onPressed: () => onChanged(sort.key),
          ),
      ],
      builder: (context, toggle) => Tooltip(
        message: '排序方式',
        child: TextButton.icon(
          onPressed: toggle,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          label: Text(_sortLabel(value)),
        ),
      ),
    );
  }
}

class _SearchResultGrid extends StatelessWidget {
  const _SearchResultGrid({
    required this.items,
    required this.width,
    required this.showRating,
  });

  final List<BangumiItem> items;
  final double width;
  final bool showRating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w600, height: 1.4);

    double textHeight(String text, TextStyle style) =>
        _measureTextHeight(context, text, style);

    final titleHeight = textHeight('番剧\n番剧', titleStyle);
    final metadataHeight = math.max(_SearchResultCard.ratingIconSize,
        textHeight('0.0 0000', textTheme.labelMedium!));
    final columns = math.max(2, (width / 180).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 20,
          mainAxisExtent: cardWidth / _SearchResultCard.coverAspectRatio +
              titleHeight +
              metadataHeight +
              _SearchResultCard.titleSpacing +
              _SearchResultCard.metadataSpacing +
              6),
      itemCount: items.length,
      itemBuilder: (_, index) => _SearchResultCard(
          item: items[index],
          showRating: showRating,
          titleHeight: titleHeight,
          titleStyle: titleStyle),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.item,
    required this.showRating,
    required this.titleHeight,
    required this.titleStyle,
  });

  static const coverAspectRatio = 0.7;
  static const titleSpacing = 10.0;
  static const metadataSpacing = 4.0;
  static const ratingIconSize = 14.0;

  final BangumiItem item;
  final bool showRating;
  final double titleHeight;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
          onTap: () => context.pushNamed('/info/', arguments: item),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: coverAspectRatio,
                  child: LayoutBuilder(
                      builder: (_, constraints) => NetworkImgLayer(
                            src: item.images['large'] ??
                                item.images['common'] ??
                                '',
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          )),
                )),
            const SizedBox(height: titleSpacing),
            SizedBox(
                height: titleHeight,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                )),
            const SizedBox(height: metadataSpacing),
            Row(children: [
              if (showRating && item.ratingScore > 0) ...[
                Icon(Icons.star_rounded,
                    size: ratingIconSize, color: theme.colorScheme.primary),
                const SizedBox(width: 3),
                Text(item.ratingScore.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium),
                const SizedBox(width: 10),
              ],
              Expanded(
                  child: Text(year,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant))),
            ]),
          ])),
    );
  }
}

/// 搜索中的骨架网格。
///
/// 列数、卡片宽度、行高都跟 [_SearchResultGrid] 用同一套算式，
/// 结果回来时卡片是原地替换，不会整块往下跳。
class _SearchSkeletonGrid extends StatelessWidget {
  const _SearchSkeletonGrid({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle =
        textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, height: 1.4);
    final titleHeight = _measureTextHeight(context, '番剧\n番剧', titleStyle);
    final metadataHeight = math.max(_SearchResultCard.ratingIconSize,
        _measureTextHeight(context, '0.0 0000', textTheme.labelMedium!));
    final columns = math.max(2, (width / 180).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 20,
          mainAxisExtent: cardWidth / _SearchResultCard.coverAspectRatio +
              titleHeight +
              metadataHeight +
              _SearchResultCard.titleSpacing +
              _SearchResultCard.metadataSpacing +
              6),
      itemCount: columns * 2,
      itemBuilder: (_, index) => const BangumiCardSkeleton(compact: true),
    );
  }
}

/// 把命中片段加粗高亮。
///
/// 参考客户端的联想结果带 `highlightTitle` / `highlightMatch` 两个字段，
/// 由服务端直接返回带高亮标记的标题。Bangumi 没有这个能力，这里在客户端
/// 按查询词做一次不区分大小写的子串匹配来还原同样的视觉效果。
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final keyword = query.trim();
    final index =
        keyword.isEmpty ? -1 : text.toLowerCase().indexOf(keyword.toLowerCase());
    if (index < 0 || text.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + keyword.length),
            style: TextStyle(color: highlightColor, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: text.substring(index + keyword.length)),
        ],
      ),
    );
  }
}

/// 输入联想面板。
///
/// 对应参考客户端的 `getSuggestions(keyword, pageSize)`：边打字边出结果，
/// 点条目直接进详情，点底部一行按原词完整搜索。
class _SearchSuggestionPanel extends StatelessWidget {
  const _SearchSuggestionPanel({
    required this.keyword,
    required this.items,
    required this.busy,
    required this.onSubmit,
    required this.onOpen,
  });

  final String keyword;
  final List<BangumiItem> items;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final ValueChanged<BangumiItem> onOpen;

  static const double _coverWidth = 36;
  static const double _coverHeight = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (items.isEmpty) {
      return busy
          ? const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LoadingIndicator(size: 24),
            )
          : const SizedBox.shrink();
    }
    final titleStyle = theme.textTheme.bodyMedium!;
    final subtitleStyle = theme.textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final item in items)
            ListTile(
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 12, right: 12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: _coverWidth,
                  height: _coverHeight,
                  child: NetworkImgLayer(
                    src: item.images['medium'] ??
                        item.images['small'] ??
                        item.images['large'] ??
                        '',
                    width: _coverWidth,
                    height: _coverHeight,
                  ),
                ),
              ),
              title: _HighlightedText(
                text: item.nameCn.isNotEmpty ? item.nameCn : item.name,
                query: keyword,
                style: titleStyle,
                highlightColor: colors.primary,
              ),
              subtitle: Text(
                [
                  if (item.nameCn.isNotEmpty && item.name != item.nameCn) item.name,
                  if (item.airDate.length >= 4) item.airDate.substring(0, 4),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
              // 整行都是「进详情」的入口。之前这里放了个独立的 IconButton
              // 走 onOpen，行本身却调 onSubmit 又搜一遍，于是点整行看起来
              // 就是「没反应」——面板收起了，页面还停在原地。
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              onTap: () => onOpen(item),
            ),
          ListTile(
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.search_rounded,
                size: 20, color: colors.onSurfaceVariant),
            title: Text('搜索「$keyword」', style: titleStyle),
            onTap: () => onSubmit(keyword),
          ),
        ]),
      ),
    );
  }
}

/// 热搜榜名次徽标，前三名用主色突出。
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highlighted = rank <= 3;
    return SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text('$rank',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlighted
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                  )),
        ),
      ),
    );
  }
}

/// 热度趋势图标，对应 `HotSearchTrend`。
class _TrendIcon extends StatelessWidget {
  const _TrendIcon({required this.trend});

  final HotSearchTrend trend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (IconData, Color, String) style = switch (trend) {
      HotSearchTrend.rising =>
        (Icons.trending_up_rounded, colors.error, '热度上升'),
      HotSearchTrend.falling =>
        (Icons.trending_down_rounded, colors.onSurfaceVariant, '热度下降'),
      HotSearchTrend.newEntry =>
        (Icons.fiber_new_rounded, colors.tertiary, '近期开播'),
      HotSearchTrend.steady =>
        (Icons.trending_flat_rounded, colors.onSurfaceVariant, '热度持平'),
    };
    return Tooltip(
      message: style.$3,
      child: Icon(style.$1, size: 18, color: style.$2),
    );
  }
}

/// 把评分人数压成「1.2万」这种短热度值。
String _formatHeatValue(int value) {
  if (value < 10000) return '$value';
  return '${(value / 10000).toStringAsFixed(1)}万';
}

/// 热搜榜。
///
/// 对应参考客户端 `SearchConfigApiData.hotSearchData`：名次 + 热度值 + 趋势，
/// 点任一条直接按番剧名搜索。
class _HotSearchBoard extends StatelessWidget {
  const _HotSearchBoard({required this.items, required this.onPick});

  final List<HotSearchItem> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.only(left: 16, right: 8, bottom: 6),
          child: Row(children: [
            Icon(Icons.local_fire_department_rounded,
                size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text('热门搜索',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.onSurfaceVariant))),
          ])),
      for (final item in items.take(10))
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            visualDensity: VisualDensity.compact,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            leading: _RankBadge(rank: item.rank),
            title: Text(item.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: item.heatValue > 0
                ? Text('${_formatHeatValue(item.heatValue)} 人评分',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant))
                : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _TrendIcon(trend: item.trend),
              const SizedBox(width: 10),
              Icon(Icons.north_west_rounded,
                  size: 18, color: colors.onSurfaceVariant),
            ]),
            onTap: () => onPick(item.title),
          ),
        ),
    ]);
  }
}

/// 横向番剧卡片，用于「最新上线」这类推荐位。
class _RailCard extends StatelessWidget {
  const _RailCard({required this.item, required this.width});

  static const double coverAspectRatio = 0.7;

  final BangumiItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';
    return SizedBox(
      width: width,
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.pushNamed('/info/', arguments: item),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: coverAspectRatio,
                      child: NetworkImgLayer(
                        src: item.images['large'] ??
                            item.images['common'] ??
                            '',
                        width: width,
                        height: width / coverAspectRatio,
                      ),
                    )),
                const SizedBox(height: 8),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall!
                        .copyWith(fontWeight: FontWeight.w600, height: 1.4)),
                const SizedBox(height: 2),
                Text(year,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
        ),
      ),
    );
  }
}

/// 横向推荐栏，带标题。
class _BangumiRail extends StatelessWidget {
  const _BangumiRail({
    required this.title,
    required this.items,
  });

  static const double cardWidth = 112;

  final String title;
  final List<BangumiItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
          child: Row(children: [
            Icon(Icons.auto_awesome_rounded,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant))),
          ])),
      SizedBox(
        height: cardWidth / _RailCard.coverAspectRatio + 58,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) =>
              _RailCard(item: items[index], width: cardWidth),
        ),
      ),
    ]);
  }
}

/// 搜索没有结果时的兜底页。
///
/// 参考客户端此时展示「未找到匹配结果」+「…的相关视频，建议更换搜索词」，
/// 并在下方继续推「为你推荐」，而不是只放一个空状态图标。
class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.keyword,
    required this.recommendations,
    required this.onClearFilters,
    this.hasFilters = false,
  });

  final String keyword;
  final List<BangumiItem> recommendations;
  final VoidCallback onClearFilters;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GeneralEmptyState(
        compact: true,
        icon: Icons.search_off_rounded,
        title: '没有找到相关番剧',
        actions: [
          if (hasFilters)
            StateActionButton.tonal(
              onPressed: onClearFilters,
              icon: Icons.filter_alt_off_rounded,
              text: '清除筛选条件',
            ),
        ],
      ),
      if (keyword.isNotEmpty) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('「$keyword」没有相关番剧，建议更换搜索词',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ),
      ],
      if (recommendations.isNotEmpty) ...[
        const SizedBox(height: 28),
        _BangumiRail(title: '为你推荐', items: recommendations),
      ],
    ]);
  }
}
