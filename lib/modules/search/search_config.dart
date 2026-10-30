/// 搜索页「搜索配置」与「热搜榜」的数据模型。
///
/// 结构对齐参考客户端的 `SearchConfigApiData` → `HotSearchDataApi` →
/// `HotSearchItemApi` 三层：一次请求同时返回「默认搜索词」和「热搜榜」，
/// 让搜索页在用户还没输入任何内容时就有东西可展示，而不是一片空白。
///
/// 参考实现的热搜榜来自自建服务端的 `/api/v1/app/client/video/searchConfig`，
/// 带真实播放量与名次变化；Bangumi 没有等价接口，热度值只能拿「评分人数」
/// 近似，趋势也只能区分「新开播 / 持平」。因此这里的模型保留了
/// rank / heatValue / trend 三元组的外形，但数值语义是 Bangumi 的。
library;

import 'package:XL/modules/bangumi/bangumi_item.dart';

/// 热搜条目的热度趋势。
///
/// 对应参考实现里的 `TrendType`（Rising / Falling / New / Steady）。
/// Bangumi 侧没有历史榜单可比对，`rising` / `falling` 需要调用方把上一轮
/// 快照的名次传进 [HotSearchTrend.fromDelta] 才能得出；默认只能区分
/// 「近期开播的新番」与「名次持平」。
enum HotSearchTrend {
  /// 名次上升
  rising,

  /// 名次下降
  falling,

  /// 新上榜（近期开播）
  newEntry,

  /// 名次持平
  steady;

  /// 由前后两次榜单的名次差推导趋势。
  ///
  /// 上一轮没有这条记录时视为持平，避免首次加载满屏「上升」。
  static HotSearchTrend fromDelta(int? previousRank, int currentRank) {
    if (previousRank == null || previousRank == currentRank) {
      return HotSearchTrend.steady;
    }
    return previousRank > currentRank
        ? HotSearchTrend.rising
        : HotSearchTrend.falling;
  }
}

/// 判断 `airDate` 是否落在「近期开播」窗口内（默认 45 天）。
bool _isFreshAirDate(String airDate, DateTime now, {int days = 45}) {
  final parsed = DateTime.tryParse(airDate);
  if (parsed == null) return false;
  final diff = now.difference(parsed).inDays;
  return diff >= -days && diff <= days;
}

/// 热搜榜单里的单条目。
///
/// 对应参考实现的 `HotSearchItemApi{ rank, heatValue, trendType, video }`。
class HotSearchItem {
  const HotSearchItem({
    required this.rank,
    required this.heatValue,
    required this.trend,
    required this.bangumiItem,
  });

  /// 名次，从 1 开始。
  final int rank;

  /// 热度值。Bangumi 侧用条目评分人数（[BangumiItem.votes]）近似。
  final int heatValue;

  /// 热度趋势。
  final HotSearchTrend trend;

  /// 命中的番剧条目。
  final BangumiItem bangumiItem;

  /// 展示用标题，优先中文名。
  String get title =>
      bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;

  @override
  bool operator ==(Object other) {
    return other is HotSearchItem && other.bangumiItem.id == bangumiItem.id;
  }

  @override
  int get hashCode => bangumiItem.id.hashCode;
}

/// 搜索页配置，对应参考实现的 `SearchConfigApiData`。
class SearchConfig {
  const SearchConfig({
    this.defaultKeyword = '',
    this.hotSearchTitle = '热门搜索',
    this.hotSearchItems = const [],
    required this.updateTime,
  });

  /// 搜索框占位提示词。
  ///
  /// 参考实现由服务端下发 `defaultKeyword`，这里改为取热搜榜第一名，
  /// 服务端拿不到数据时退化为固定的「搜索番剧名称」。
  final String defaultKeyword;

  /// 热搜榜标题，对应 `HotSearchDataApi.title`。
  final String hotSearchTitle;

  /// 热搜榜条目，对应 `HotSearchDataApi.items`。
  final List<HotSearchItem> hotSearchItems;

  /// 榜单更新时间，对应 `HotSearchDataApi.updateTime`。
  final DateTime updateTime;

  bool get isEmpty => hotSearchItems.isEmpty;

  /// 按名次排序后取前 [limit] 条，供搜索框占位词使用。
  String suggestDefaultKeyword(String fallback) {
    for (final item in hotSearchItems) {
      final title = item.title.trim();
      if (title.isNotEmpty) return title;
    }
    return fallback;
  }
}

/// 把一份番剧列表包装成热搜榜。
///
/// [previousRanks] 传入上一轮快照的「条目 id → 名次」用于推导上升 / 下降，
/// 传 null 时只区分新番与持平。
List<HotSearchItem> buildHotSearchItems(
  List<BangumiItem> items, {
  Map<int, int>? previousRanks,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final seen = <int>{};
  final result = <HotSearchItem>[];
  for (final item in items) {
    if (!seen.add(item.id)) continue;
    final rank = result.length + 1;
    final previous = previousRanks?[item.id];
    final trend = _isFreshAirDate(item.airDate, current)
        ? HotSearchTrend.newEntry
        : HotSearchTrend.fromDelta(previous, rank);
    result.add(HotSearchItem(
      rank: rank,
      heatValue: item.votes,
      trend: trend,
      bangumiItem: item,
    ));
  }
  return result;
}

/// 热搜榜快照，用于下一轮计算名次变化。
Map<int, int> hotSearchRankSnapshot(List<HotSearchItem> items) =>
    {for (final item in items) item.bangumiItem.id: item.rank};

/// 把「YYYY-MM-DD」风格的开播日期格式化成 `M月D日`。
String formatAirDateLabel(String airDate) {
  final parsed = DateTime.tryParse(airDate);
  if (parsed == null) return '';
  return '${parsed.month}月${parsed.day}日';
}
