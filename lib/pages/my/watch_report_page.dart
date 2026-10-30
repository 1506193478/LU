import 'package:flutter/material.dart';

import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/modules/history/history_module.dart';
import 'package:XL/modules/my/watch_report.dart';

/// 观看年报：把历史记录里躺着的数字摊开给人看。
///
/// 数据全在本地历史里，不联网、不上传。口径在页面底部写清楚了 ——
/// 「累计进度」不是真实观看时长，不写明白就是在编数据。
class WatchReportPage extends StatefulWidget {
  const WatchReportPage({super.key, required this.histories});

  final List<History> histories;

  @override
  State<WatchReportPage> createState() => _WatchReportPageState();
}

class _WatchReportPageState extends State<WatchReportPage> {
  late final List<WatchReportRecord> _records =
      WatchReport.recordsFromHistories(widget.histories);
  late final List<int> _years = WatchReport.availableYears(_records);

  /// 0 = 全部时间。
  int _year = 0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WatchReport report = WatchReport.from(
      records: _records,
      year: _year,
    );

    return SettingsDetailScaffold(
      title: const Text('观看年报'),
      body: report.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text('还没有足够的观看记录', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      '看几集再回来，这里会有你的追番画像。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_years.isNotEmpty)
                  _YearSelector(
                    years: _years,
                    selected: _year,
                    onChanged: (int year) => setState(() => _year = year),
                  ),
                const SizedBox(height: 12),
                _OverviewGrid(report: report),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: '你的追番时段',
                  subtitle: report.busiestHour < 0
                      ? null
                      : '最常在 ${report.busiestHour.toString().padLeft(2, '0')}:00 前后打开',
                ),
                const SizedBox(height: 8),
                _HourlyChart(hourly: report.hourly),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: '看得最多的番',
                  subtitle: report.topBangumi.isEmpty ? null : '按集数排，前五',
                ),
                const SizedBox(height: 8),
                for (final WatchReportEntry entry in report.topBangumi)
                  _TopBangumiRow(entry: entry),
                const SizedBox(height: 24),
                Text(
                  '口径说明：集数是去重后的「番剧 + 集号」，换线路或离线重看不重复计；'
                  '累计进度是每集最后看到的位置之和，拖到片尾也算一整集，所以只会偏大。'
                  '时段按每集最后一次播放的时间统计。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ],
            ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selected,
    required this.onChanged,
  });

  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, 0, '全部'),
          for (final int year in years) _chip(context, year, '$year 年'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, int value, String label) {
    final bool active = value == selected;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onChanged(value),
        showCheckmark: false,
        selectedColor: colors.primaryContainer,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.report});

  final WatchReport report;

  static String _hours(Duration value) {
    final double hours = value.inMinutes / 60.0;
    if (hours >= 10) return hours.round().toString();
    return hours.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final int columns = constraints.maxWidth >= 560 ? 4 : 2;
      final double spacing = 10;
      final double width =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      final List<Widget> cards = <Widget>[
        _StatCard(
          width: width,
          value: '${report.bangumiCount}',
          unit: '部',
          label: '追过的番',
        ),
        _StatCard(
          width: width,
          value: '${report.episodeCount}',
          unit: '集',
          label: '看过的集数',
        ),
        _StatCard(
          width: width,
          value: _hours(report.totalProgress),
          unit: '小时',
          label: '累计进度',
        ),
        _StatCard(
          width: width,
          value: '${report.activeDays}',
          unit: '天',
          label: '有看番的日子',
        ),
      ];
      return Wrap(spacing: spacing, runSpacing: spacing, children: cards);
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.value,
    required this.unit,
    required this.label,
  });

  final double width;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 24 根柱子表示一天里各时段看了多少集。
class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.hourly});

  final List<int> hourly;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int max = hourly.fold<int>(0, (int a, int b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int hour = 0; hour < hourly.length; hour++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Tooltip(
                      message: '${hour.toString().padLeft(2, '0')}:00 · '
                          '${hourly[hour]} 集',
                      child: Container(
                        height: max == 0
                            ? 2
                            : 4 + 76 * (hourly[hour] / max),
                        decoration: BoxDecoration(
                          color: hourly[hour] == 0
                              ? colors.surfaceContainerHighest
                              : colors.primary.withValues(
                                  alpha: 0.35 + 0.55 * (hourly[hour] / max),
                                ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final String label in const ['00', '06', '12', '18', '23'])
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TopBangumiRow extends StatelessWidget {
  const _TopBangumiRow({required this.entry});

  final WatchReportEntry entry;

  static String _duration(Duration value) {
    final int minutes = value.inMinutes;
    if (minutes < 60) return '$minutes 分钟';
    return '${(minutes / 60).toStringAsFixed(1)} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            // 老记录可能没有封面地址，空串交给图片组件会去请求一个空 URL。
            child: entry.coverUrl.isEmpty
                ? Container(
                    width: 44,
                    height: 60,
                    color: colors.surfaceContainerHighest,
                    child: Icon(
                      Icons.movie_outlined,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  )
                : NetworkImgLayer(
                    src: entry.coverUrl,
                    width: 44,
                    height: 60,
                    fadeInDuration: const Duration(milliseconds: 120),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.episodeCount} 集 · ${_duration(entry.progress)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
