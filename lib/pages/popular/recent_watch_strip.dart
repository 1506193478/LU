import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/bean/dialog/dialog_task.dart';
import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/widget/pressable.dart';
import 'package:XL/modules/history/history_module.dart';
import 'package:XL/pages/history/history_controller.dart';
import 'package:XL/services/player/history_playback_service.dart';
import 'package:XL/services/plugin/rule_engine_models.dart' show RuleCancelToken;
import 'package:XL/utils/constants.dart';
import 'package:XL/utils/device.dart';

/// 推荐页顶部的「继续观看」横滑卡片。
///
/// 数据直接取观看历史，按最近观看时间倒序、同一部番只留一条（换源看同一部
/// 番会留多条记录）。点卡片直接续播，跟历史记录页走同一条
/// [HistoryPlaybackService] 解析路径。
class RecentWatchStrip extends StatefulWidget {
  const RecentWatchStrip({super.key, this.maxItems = 10});

  /// 最多铺几张。再多横向也划不完，反而失去「最近」的意义。
  final int maxItems;

  @override
  State<RecentWatchStrip> createState() => _RecentWatchStripState();
}

class _RecentWatchStripState extends State<RecentWatchStrip>
    with KazumiDialogOwner {
  final HistoryController _history = inject<HistoryController>();
  final HistoryPlaybackService _playback = inject<HistoryPlaybackService>();

  @override
  void initState() {
    super.initState();
    // 历史列表只在「历史记录页」和「记录一次播放」时才 init，冷启动直接进
    // 推荐页的话这里是空的。补一次同步读取（从本地仓库读，不联网）。
    if (_history.histories.isEmpty) {
      _history.init();
    }
  }

  List<History> _recent() {
    final List<History> sorted = List<History>.of(_history.histories)
      ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    final seen = <int>{};
    final List<History> result = <History>[];
    for (final entry in sorted) {
      // 同一部番可能被不同源各记一条，只保留最近看的那条。
      if (!seen.add(entry.bangumiItem.id)) continue;
      result.add(entry);
      if (result.length >= widget.maxItems) break;
    }
    return result;
  }

  Future<void> _open(History history) async {
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final result = await task.loading(
        message: '获取中',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () =>
            _playback.open(history, cancelToken: cancelToken),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
            (context) => context.pushNamed('/video/', arguments: args),
          );
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请稍后重试');
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final List<History> items = _recent();
      // 没有历史就整块收起来，不留一条空标题占地方。
      if (items.isEmpty) return const SizedBox.shrink();

      final ThemeData theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              StyleString.cardSpace,
              10,
              StyleString.cardSpace - 4,
              6,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '继续观看',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最近 ${items.length} 部',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.pushNamed('/settings/history/'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('全部'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _RecentCard.height + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: StyleString.cardSpace,
              ),
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                final History entry = items[index];
                return _RecentCard(
                  history: entry,
                  onTap: () => _open(entry),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.history, required this.onTap});

  static const double height = 92;
  static const double width = 214;
  static const double _coverWidth = 54;

  final History history;
  final VoidCallback onTap;

  String get _title {
    final String cn = history.bangumiItem.nameCn.trim();
    return cn.isNotEmpty ? cn : history.bangumiItem.name.trim();
  }

  /// 上次看到哪儿。取这一集最后的位置，没有记录就不显示。
  String get _progressLabel {
    final Progress? progress = history.progresses[history.lastWatchEpisode];
    final Duration position = progress?.progress ?? Duration.zero;
    if (position <= Duration.zero) return '第 ${history.lastWatchEpisode} 集';
    final int seconds = position.inSeconds;
    final String clock = seconds >= 3600
        ? '${seconds ~/ 3600}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
            '${(seconds % 60).toString().padLeft(2, '0')}'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return '第 ${history.lastWatchEpisode} 集 · 看到 $clock';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String cover =
        history.bangumiItem.images['large'] ?? history.bangumiItem.images['common'] ?? '';

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: _coverWidth,
                  height: height - 16,
                  child: cover.isEmpty
                      ? ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : NetworkImgLayer(
                          src: cover,
                          width: _coverWidth,
                          height: height - 16,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    _title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _progressLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
