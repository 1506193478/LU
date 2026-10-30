import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/pages/history/history_controller.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/services/emby/emby_playback_builder.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/storage/storage.dart';

/// 剧集 / 电影详情。选集之后直接进播放页。
class EmbyDetailPage extends StatefulWidget {
  const EmbyDetailPage({super.key, required this.item});

  final EmbyItem item;

  @override
  State<EmbyDetailPage> createState() => _EmbyDetailPageState();
}

class _EmbyDetailPageState extends State<EmbyDetailPage> {
  Future<List<EmbyItem>>? _future;
  bool _starting = false;

  /// 和播放器里的选集面板共用一个设置。
  late bool _descending =
      GStorage.getSetting<bool>(SettingsKeys.episodeListDescending);

  void _toggleOrder() {
    setState(() => _descending = !_descending);
    GStorage.putSetting<bool>(SettingsKeys.episodeListDescending, _descending);
  }

  /// 按当前顺序给出条目下标：正序 0,1,2…；倒序 末尾,倒数第二…
  ///
  /// 只改「显示顺序」，条目本身的下标不变 —— 播放时仍然按真实集号取。
  List<int> _episodeOrder(int count) => _descending
      ? List<int>.generate(count, (int i) => count - 1 - i)
      : List<int>.generate(count, (int i) => i);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<List<EmbyItem>> _load() async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) return const [];
    final client = service.clientFor(server);
    if (widget.item.isSeries) {
      return client.fetchEpisodes(
        userId: server.userId,
        seriesId: widget.item.id,
      );
    }
    // 电影、单个视频：它自己就是唯一一集。
    return [widget.item];
  }

  /// 上次看到第几集（1 起算），没有记录返回 null。
  ///
  /// 历史是按 `adapterName` 分档存的，这里用的 adapterName 必须和
  /// [VideoPageController] 写入时一致，否则永远查不到。
  int? _resumeEpisode() {
    final server = EmbyService.instance.activeServer;
    if (server == null) return null;
    final progress = inject<HistoryController>().lastWatching(
      embyBangumiItem(widget.item, server),
      server.adapterName,
    );
    if (progress == null || progress.episode < 1) return null;
    return progress.episode;
  }

  Future<void> _play(List<EmbyItem> items, int index) async {
    if (_starting) return;
    final server = EmbyService.instance.activeServer;
    if (server == null) {
      KazumiDialog.showToast(message: '服务器配置丢失，请返回重新进入');
      return;
    }
    if (index < 0 || index >= items.length) return;
    setState(() => _starting = true);
    try {
      await context.pushNamed(
        '/video/',
        arguments: EmbyVideoPlaybackArgs(
          bangumiItem: embyBangumiItem(widget.item, server),
          server: server,
          plugin: embyPlugin(server),
          seriesTitle: widget.item.name,
          seriesItemId: widget.item.id,
          episodes: embyPlaybackEpisodes(items),
          initialEpisode: index + 1,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        // 播放页回来时续播点可能变了，重算一次。
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = EmbyService.instance.activeServer;
    final client = server == null ? null : EmbyService.instance.clientFor(server);
    final String posterUrl = client == null
        ? ''
        : client.imageUrl(
            widget.item.id,
            maxHeight: 640,
            tag: widget.item.primaryImageTag,
          );

    return SettingsDetailScaffold(
      title: Text(widget.item.name, overflow: TextOverflow.ellipsis),
      body: EmbyFutureView<List<EmbyItem>>(
        future: _future!,
        onRetry: _reload,
        emptyTitle: '没有可播放的内容',
        emptyMessage: '这部剧在 Emby 服务端还没有任何剧集文件。',
        isEmpty: (items) => items.isEmpty,
        builder: (context, items) => _body(context, items, posterUrl),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<EmbyItem> items,
    String posterUrl,
  ) {
    final theme = Theme.of(context);
    final int? resumeEpisode = _resumeEpisode();
    final int startIndex = resumeEpisode == null
        ? 0
        : (resumeEpisode - 1).clamp(0, items.length - 1);
    final bool isSingle = items.length == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double inset = constraints.maxWidth < 600 ? 16 : 28;
        final bool wide = constraints.maxWidth >= 760;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Poster(url: posterUrl),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _meta(context, items, startIndex,
                              resumeEpisode, isSingle),
                        ),
                      ],
                    )
                  else ...[
                    Center(child: _Poster(url: posterUrl, width: 150)),
                    const SizedBox(height: 16),
                    _meta(context, items, startIndex, resumeEpisode, isSingle),
                  ],
                  if (!isSingle) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('选集',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          tooltip: _descending
                              ? '改为正序（第 1 集在最前）'
                              : '改为倒序（最新一集在最前）',
                          onPressed: _toggleOrder,
                          icon: Icon(
                            _descending
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final int i in _episodeOrder(items.length))
                          _EpisodeChip(
                            label: embyEpisodeLabel(items[i], i + 1),
                            isResume: resumeEpisode == i + 1,
                            onTap: () => _play(items, i),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _meta(
    BuildContext context,
    List<EmbyItem> items,
    int startIndex,
    int? resumeEpisode,
    bool isSingle,
  ) {
    final theme = Theme.of(context);
    final item = widget.item;
    final String buttonLabel = _starting
        ? '正在打开…'
        : isSingle
            ? '播放'
            : resumeEpisode == null
                ? '从第 1 集开始'
                : '继续观看 第 $resumeEpisode 集';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (item.metaLine.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            item.metaLine,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _starting ? null : () => _play(items, startIndex),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(buttonLabel),
        ),
        if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            item.overview!.trim(),
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, this.width = 200});

  final String url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double height = width / 0.68;
    final Widget image = url.isEmpty
        ? ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Center(
              child: Icon(Icons.movie_rounded,
                  size: width * 0.3, color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        : NetworkImgLayer(src: url, width: width, height: height);
    if (isNeuLayout(context)) {
      return NeuMedia(
        radius: 20,
        width: width,
        height: height,
        child: image,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.label,
    required this.isResume,
    required this.onTap,
  });

  final String label;
  final bool isResume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isResume) ...[
            Icon(Icons.play_circle_fill_rounded,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
    if (isNeuLayout(context)) {
      return NeuSurface(
        radius: 16,
        mode: isResume ? NeuMode.recess : NeuMode.raised,
        onTap: onTap,
        child: content,
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
