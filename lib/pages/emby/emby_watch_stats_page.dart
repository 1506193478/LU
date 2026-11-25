import 'package:flutter/material.dart';

import 'package:XL/services/emby/emby_watch_stats.dart';

/// 观看统计页：本地记录的观看时长趋势 + 热门内容榜。
///
/// 数据来自 [EmbyWatchStats]（播放器每 10 秒记一笔），纯展示层，
/// 不发任何网络请求。
class EmbyWatchStatsPage extends StatefulWidget {
  const EmbyWatchStatsPage({super.key});

  @override
  State<EmbyWatchStatsPage> createState() => _EmbyWatchStatsPageState();
}

class _EmbyWatchStatsPageState extends State<EmbyWatchStatsPage> {
  @override
  Widget build(BuildContext context) {
    final stats = EmbyWatchStats.instance;
    final today = stats.todayMs;
    final week = stats.msInDays(7);
    final month = stats.msInDays(30);
    final top = stats.topTitles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('观看统计'),
        actions: [
          if (top.isNotEmpty)
            IconButton(
              tooltip: '清空统计',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmClear(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---- 总览三卡 ----
          Row(
            children: [
              _SummaryCard(label: '今天', ms: today),
              const SizedBox(width: 10),
              _SummaryCard(label: '最近 7 天', ms: week),
              const SizedBox(width: 10),
              _SummaryCard(label: '最近 30 天', ms: month),
            ],
          ),
          const SizedBox(height: 20),
          // ---- 14 天趋势 ----
          Text(
            '最近 14 天',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          const _TrendChart(),
          const SizedBox(height: 24),
          // ---- 热门内容 ----
          Text(
            '看得最多的',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '还没有记录\n看一会儿视频再来吧',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    height: 1.6,
                  ),
                ),
              ),
            )
          else
            ...[
              for (var i = 0; i < top.length; i++)
                _TitleRow(
                  rank: i + 1,
                  title: (top[i].value['t'] ?? '') as String,
                  subtitle: (top[i].value['sub'] ?? '') as String,
                  ms: (top[i].value['ms'] as num?)?.toInt() ?? 0,
                  count: (top[i].value['count'] as num?)?.toInt() ?? 0,
                  showDivider: i < top.length - 1,
                ),
            ],
        ],
      ),
    );
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空统计'),
        content: const Text('观看时长和热门记录会被全部删除，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await EmbyWatchStats.instance.clear();
              if (mounted) setState(() {});
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ 子组件

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.ms});

  final String label;
  final int ms;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: scheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              EmbyWatchStats.formatMs(ms),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最近 14 天的迷你柱状图。纯 Container 拼，不引图表库。
class _TrendChart extends StatelessWidget {
  const _TrendChart();

  @override
  Widget build(BuildContext context) {
    final values = EmbyWatchStats.instance.dailyMs(14);
    final scheme = Theme.of(context).colorScheme;
    final maxMs = values.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Tooltip(
                message: EmbyWatchStats.formatMs(values[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: SizedBox(
                    height: 64,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: maxMs <= 0
                            ? 0.02
                            : (values[i] / maxMs).clamp(0.02, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: values[i] > 0
                                ? scheme.primary.withValues(
                                    alpha: i == values.length - 1 ? 1 : 0.62,
                                  )
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.ms,
    required this.count,
    required this.showDivider,
  });

  final int rank;
  final String title;
  final String subtitle;
  final int ms;
  final int count;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = subtitle.isNotEmpty && subtitle != title
        ? '$title · $subtitle'
        : title;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '未知内容' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${EmbyWatchStats.formatMs(ms)} · $count 次观看',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 38,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}
