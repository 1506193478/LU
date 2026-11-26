import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/emby_watch_stats.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 观看统计页：本地记录的观看时长趋势 + 热门内容榜。
///
/// 数据来自 [EmbyWatchStats]（播放器每 10 秒记一笔），纯展示层，
/// 不发任何网络请求。
///
/// 样式统一走 [PvColors] / [PvText]：原先直接取 Theme.colorScheme 和
/// 默认 TextStyle，在这套带渐变背景的 Emby 壳里文字会整体发灰，跟其它
/// 设置页明显不是一套排版。
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
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: const KzBackButton(),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, pvSubDockClearance),
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
          Text('最近 14 天', style: PvText.section(context)),
          const SizedBox(height: 10),
          const _TrendChart(),
          const SizedBox(height: 24),
          // ---- 热门内容 ----
          Text('看得最多的', style: PvText.section(context)),
          const SizedBox(height: 6),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '还没有记录\n看一会儿视频再来吧',
                  textAlign: TextAlign.center,
                  style: PvText.rowSub(context).copyWith(height: 1.6),
                ),
              ),
            )
          else
            PvGroup(
              margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              children: [
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
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final clear = await showKzConfirm(
      context: context,
      title: '清空统计',
      message: '观看时长和热门记录会被全部删除，且无法恢复。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!clear || !mounted) return;
    await EmbyWatchStats.instance.clear();
    if (mounted) setState(() {});
  }
}

// ------------------------------------------------------------ 子组件

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.ms});

  final String label;
  final int ms;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: PvColors.card(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: PvText.statLabel(context)),
            const SizedBox(height: 6),
            Text(
              EmbyWatchStats.formatMs(ms),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PvText.statNum.copyWith(color: PvColors.ink(context)),
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
    final maxMs = values.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: BorderRadius.circular(12),
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
                                ? PvColors.blue.withValues(
                                    alpha: i == values.length - 1 ? 1 : 0.62,
                                  )
                                : PvColors.hair(context),
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
    final name = subtitle.isNotEmpty && subtitle != title
        ? '$title · $subtitle'
        : title;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: PvText.rowTitle(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: rank <= 3 ? PvColors.blue : PvColors.ink3(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '未知内容' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PvText.rowTitle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${EmbyWatchStats.formatMs(ms)} · $count 次观看',
                      style: PvText.rowSub(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 48, color: PvColors.hair(context)),
      ],
    );
  }
}
