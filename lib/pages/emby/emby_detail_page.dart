import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/theme/rex_design.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/history/history_controller.dart';
import 'package:XL/services/emby/emby_playback_builder.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// 剧集 / 电影详情 —— 对齐 3.9.20 预览稿（视频 ca688619）。
///
/// 版式：顶部一整块通栏大图顶到状态栏、底部渐隐进页面底色；
/// 标题 34px 白字居中压在渐变上，下面评分行 / meta 行 / 白底播放胶囊 /
/// 已看收藏圆钮 / 两三行简介；季下拉 + 倒正序 + 「更多」打开全集列表页；
/// 集号圆点横滑（选中白底深字放大）+ 集卡横滑（47% 宽、白圈选中、
/// 点集卡联动 meta / 简介 / 圆点 / 自动滚动）；最后是类似作品和
/// 当前集媒体信息胶囊。旧版「集数按钮墙」彻底废弃。
class EmbyDetailPage extends StatefulWidget {
  const EmbyDetailPage({super.key, required this.item});

  final EmbyItem item;

  @override
  State<EmbyDetailPage> createState() => _EmbyDetailPageState();
}

class _EmbyDetailPageState extends State<EmbyDetailPage> {
  Future<_DetailData>? _future;

  /// 当前季的剧集。季可以切换，所以单独持有而不是塞进 _DetailData。
  Future<List<EmbyItem>>? _episodesFuture;
  String? _seasonId;

  /// 选中集（0 起算）。集号圆点、集卡、播放、简介前缀都跟着它走。
  int _picked = 0;
  bool _descending = false;
  bool _starting = false;
  bool _overviewExpanded = false;
  bool _favorite = false;
  bool _played = false;

  /// 选中集的播放信息缓存：itemId -> mediaSource（可能为 null = 加载失败）。
  final Map<String, EmbyMediaSource?> _mediaCache = {};
  final Map<String, GlobalKey> _cardKeys = {};
  final Map<String, GlobalKey> _numKeys = {};

  @override
  void initState() {
    super.initState();
    _favorite = widget.item.isFavorite;
    _played = widget.item.played;
    _future = _load();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<_DetailData> _load() async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) {
      return const _DetailData(server: null, seasons: [], similar: []);
    }
    final client = service.clientFor(server);
    var seasons = <EmbyItem>[];
    if (widget.item.isSeries) {
      try {
        seasons = await client.fetchSeasons(
          seriesId: widget.item.id,
          userId: server.userId,
        );
      } catch (e) {
        KazumiLogger().w('Emby detail: failed to load seasons', error: e);
      }
    }
    _seasonId = seasons.isNotEmpty ? seasons.first.id : null;
    _episodesFuture = _loadEpisodes(server, _seasonId);

    var similar = <EmbyItem>[];
    try {
      similar = await client.fetchSimilar(
        itemId: widget.item.id,
        userId: server.userId,
      );
    } catch (e) {
      KazumiLogger().w('Emby detail: failed to load similar', error: e);
    }
    return _DetailData(server: server, seasons: seasons, similar: similar);
  }

  Future<List<EmbyItem>> _loadEpisodes(
    EmbyServer server,
    String? seasonId,
  ) async {
    final client = EmbyService.instance.clientFor(server);
    final List<EmbyItem> episodes;
    if (widget.item.isSeries) {
      episodes = await client.fetchEpisodes(
        userId: server.userId,
        seriesId: widget.item.id,
        seasonId: seasonId,
      );
    } else {
      // 电影、单个视频：它自己就是唯一一集。
      episodes = [widget.item];
    }
    // 恢复观看：上次看到第几集就选中第几集。
    final progress = inject<HistoryController>().lastWatching(
      embyBangumiItem(widget.item, server),
      server.adapterName,
    );
    if (progress != null && progress.episode >= 1 && episodes.isNotEmpty) {
      _picked = (progress.episode - 1).clamp(0, episodes.length - 1);
    } else {
      _picked = 0;
    }
    _ensureMedia(episodes[_picked]);
    return episodes;
  }

  void _switchSeason(EmbyServer server, String seasonId) {
    if (seasonId == _seasonId) return;
    setState(() {
      _seasonId = seasonId;
      _picked = 0;
      _episodesFuture = _loadEpisodes(server, seasonId);
    });
  }

  void _toggleOrder() {
    setState(() => _descending = !_descending);
  }

  void _pick(List<EmbyItem> episodes, int index) {
    if (index < 0 || index >= episodes.length) return;
    setState(() => _picked = index);
    _ensureMedia(episodes[index]);
    // 集卡和集号圆点都滚到看得见的位置。
    final id = episodes[index].id;
    final cardCtx = _cardKeys[id]?.currentContext;
    if (cardCtx != null) {
      Scrollable.ensureVisible(
        cardCtx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
    final numCtx = _numKeys[id]?.currentContext;
    if (numCtx != null) {
      Scrollable.ensureVisible(
        numCtx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    }
  }

  /// 选中集变了就把它的媒体流信息拉回来（媒体信息胶囊用）。
  Future<void> _ensureMedia(EmbyItem episode) async {
    if (_mediaCache.containsKey(episode.id)) return;
    _mediaCache[episode.id] = null;
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    try {
      final source = await EmbyService.instance
          .clientFor(server)
          .fetchPlaybackInfo(itemId: episode.id, userId: server.userId);
      if (mounted) setState(() => _mediaCache[episode.id] = source);
    } catch (e) {
      KazumiLogger().w('Emby detail: playback info failed', error: e);
    }
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
      // 走 Emby 自己的播放器，不再借番剧那条链路（弹幕/一起看/假插件）。
      await context.pushNamed(
        '/emby/player',
        arguments: EmbyPlaybackLaunch(
          server: server,
          title: widget.item.name,
          episodes: items,
          initialIndex: index,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        _reload();
      }
    }
  }

  Future<void> _toggleFavorite(EmbyServer server) async {
    final next = !_favorite;
    setState(() => _favorite = next);
    try {
      await EmbyService.instance
          .clientFor(server)
          .setFavorite(widget.item.id, next, userId: server.userId);
    } catch (e) {
      KazumiLogger().w('Emby detail: set favorite failed', error: e);
      if (mounted) setState(() => _favorite = !next);
    }
  }

  Future<void> _togglePlayed(EmbyServer server) async {
    final next = !_played;
    setState(() => _played = next);
    try {
      await EmbyService.instance
          .clientFor(server)
          .setPlayed(widget.item.id, next, userId: server.userId);
    } catch (e) {
      KazumiLogger().w('Emby detail: set played failed', error: e);
      if (mounted) setState(() => _played = !next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmbyPageShell(
      title: '',
      overlay: true,
      actions: [
        RexIconButton(
          icon: Icons.refresh_rounded,
          iconSize: 18,
          size: 36,
          glass: false,
          color: Colors.white,
          tooltip: '刷新',
          onTap: _reload,
        ),
      ],
      body: EmbyFutureView<_DetailData>(
        future: _future!,
        onRetry: _reload,
        emptyTitle: '没有可播放的内容',
        emptyMessage: '这部剧在 Emby 服务端还没有任何剧集文件。',
        builder: (context, data) =>
            ColoredBox(color: RexPalette.of(context).canvas, child: _body(context, data)),
      ),
    );
  }

  Widget _body(BuildContext context, _DetailData data) {
    final server = data.server;
    if (server == null) return const SizedBox.shrink();

    final bool desktop = embyIsDesktop(context);
    final double heroH = desktop ? 400 : 424;
    final double overlap = desktop ? 190 : 196;
    final double inset = desktop ? 24 : 20;

    // 集数部分单独一个 Future：季切换时会换。
    final episodesFuture = _episodesFuture;
    if (episodesFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget content = ListView(
      padding: EdgeInsets.zero,
      children: [
        // hero 图不占布局（Positioned），内容列整体上移叠在图上。
        Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH,
              child: _Hero(item: widget.item, server: server),
            ),
            Padding(
              padding: EdgeInsets.only(top: heroH - overlap),
              child: _InfoColumn(
                item: widget.item,
                server: server,
                seasons: data.seasons,
                similar: data.similar,
                episodesFuture: episodesFuture,
                inset: inset,
                playStarting: _starting,
                picked: _picked,
                descending: _descending,
                overviewExpanded: _overviewExpanded,
                favorite: _favorite,
                played: _played,
                mediaCache: _mediaCache,
                cardKeys: _cardKeys,
                numKeys: _numKeys,
                onToggleOverview: () =>
                    setState(() => _overviewExpanded = !_overviewExpanded),
                onToggleOrder: _toggleOrder,
                onSwitchSeason: (id) => _switchSeason(server, id),
                onPick: _pick,
                onPlayPicked: (items, index) => _play(items, index),
                onToggleFavorite: () => _toggleFavorite(server),
                onTogglePlayed: () => _togglePlayed(server),
                currentSeasonId: _seasonId ?? '',
                onPickedFromAllPage: (i) =>
                    _episodesFuture?.then((eps) => _pick(eps, i)),
              ),
            ),
          ],
        ),
        SizedBox(height: desktop ? 40 : 30),
      ],
    );

    // 宽屏：整列限宽居中。
    if (desktop) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: content,
        ),
      );
    }
    return content;
  }
}

class _DetailData {
  const _DetailData({
    required this.server,
    required this.seasons,
    required this.similar,
  });

  final EmbyServer? server;
  final List<EmbyItem> seasons;
  final List<EmbyItem> similar;
}

// ---------------------------------------------------------------- hero 大图

/// 通栏大图：顶到页面最上面，底部 270px 渐隐进页面底色。
class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.server});

  final EmbyItem item;
  final EmbyServer server;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    final String image = item.backdropImageTag != null
        ? embyBackdropUrl(
            serverUrl: server.url,
            itemId: item.id,
            accessToken: server.accessToken,
            tag: item.backdropImageTag,
          )
        : embyImageUrl(
            serverUrl: server.url,
            itemId: item.id,
            accessToken: server.accessToken,
            maxHeight: 900,
            tag: item.primaryImageTag,
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        EmbyImage(url: image, headers: embyAuthHeaders(server)),
        // 底部渐隐到页面底色，标题压在渐变上。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.36, 1.0],
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.18),
                p.canvas,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 详情正文

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({
    required this.item,
    required this.server,
    required this.seasons,
    required this.similar,
    required this.episodesFuture,
    required this.inset,
    required this.playStarting,
    required this.picked,
    required this.descending,
    required this.overviewExpanded,
    required this.favorite,
    required this.played,
    required this.mediaCache,
    required this.cardKeys,
    required this.numKeys,
    required this.onToggleOverview,
    required this.onToggleOrder,
    required this.onSwitchSeason,
    required this.onPick,
    required this.onPlayPicked,
    required this.onToggleFavorite,
    required this.onTogglePlayed,
    required this.currentSeasonId,
    required this.onPickedFromAllPage,
  });

  final EmbyItem item;
  final EmbyServer server;
  final List<EmbyItem> seasons;
  final List<EmbyItem> similar;
  final Future<List<EmbyItem>> episodesFuture;
  final double inset;
  final bool playStarting;
  final int picked;
  final bool descending;
  final bool overviewExpanded;
  final bool favorite;
  final bool played;
  final Map<String, EmbyMediaSource?> mediaCache;
  final Map<String, GlobalKey> cardKeys;
  final Map<String, GlobalKey> numKeys;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleOrder;
  final ValueChanged<String> onSwitchSeason;
  final void Function(List<EmbyItem> items, int index) onPick;
  final void Function(List<EmbyItem> items, int index) onPlayPicked;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePlayed;

  /// 当前选中的季 id（state 持有）。
  final String currentSeasonId;

  /// 全集列表页里点了某一集并关闭后回传的下标。
  final ValueChanged<int> onPickedFromAllPage;

  @override
  Widget build(BuildContext context) {
    return EmbyFutureView<List<EmbyItem>>(
      future: episodesFuture,
      onRetry: () {},
      isEmpty: (eps) => eps.isEmpty,
      emptyTitle: '没有可播放的内容',
      emptyMessage: '这个季在 Emby 服务端还没有任何剧集文件。',
      builder: (context, episodes) {
        final order = _orderOf(episodes.length);
        final pickedItem = episodes[picked.clamp(0, episodes.length - 1)];
        final source = mediaCache[pickedItem.id];
        final String seasonName = seasons.isEmpty
            ? item.name
            : _currentSeasonName(seasons);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // —— 标题（白字居中，压在渐变上）
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -1.2,
                  shadows: [Shadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 3))],
                ),
              ),
            ),
            // —— 评分行：★ 分数 · 分级胶囊 · 类型
            const SizedBox(height: 11),
            _RateRow(item: item),
            // —— meta 行：时长 / 年份 / 媒体流摘要（选中集）
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: _MetaRow(item: pickedItem, source: source),
            ),
            // —— 播放大按钮（白底胶囊）
            const SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: _PlayButton(
                label: episodes.length > 1
                    ? '播放 · 第 ${picked + 1} 集'
                    : '播放',
                starting: playStarting,
                onTap: () => onPlayPicked(episodes, picked),
              ),
            ),
            // —— 操作行：已看 / 收藏
            const SizedBox(height: 14),
            _ActionRow(
              played: played,
              favorite: favorite,
              onTogglePlayed: onTogglePlayed,
              onToggleFavorite: onToggleFavorite,
            ),
            // —— 简介
            if (pickedItem.overview != null &&
                pickedItem.overview!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: _Overview(
                  prefix: '[${item.name} · $seasonName · 第 ${picked + 1} 集] ',
                  text: pickedItem.overview!.trim(),
                  expanded: overviewExpanded,
                  onToggle: onToggleOverview,
                ),
              ),
            ],
            // —— 季选择 + 排序 + 全集列表入口
            if (seasons.length > 1 || episodes.length > 1) ...[
              const SizedBox(height: 20),
              _SeasonBar(
                seasons: seasons,
                currentSeasonId: currentSeasonId,
                seasonName: seasonName,
                descending: descending,
                pickedIndex: picked,
                onOpenAll: () => _openAllEpisodes(context, episodes),
                onSwitchSeason: onSwitchSeason,
                onToggleOrder: onToggleOrder,
              ),
              // —— 集号圆点横滑
              const SizedBox(height: 12),
              _EpisodeNums(
                episodes: episodes,
                order: order,
                picked: picked,
                numKeys: numKeys,
                onPick: (i) => onPick(episodes, i),
              ),
              // —— 集卡横滑
              const SizedBox(height: 14),
              _EpisodeRail(
                episodes: episodes,
                order: order,
                picked: picked,
                server: server,
                inset: inset,
                cardKeys: cardKeys,
                onPick: (i) => onPick(episodes, i),
              ),
            ],
            // —— 类似作品
            if (similar.isNotEmpty) ...[
              const SizedBox(height: 26),
              EmbySectionHeader(title: '类似作品'),
              EmbyRail(
                itemCount: similar.length,
                itemBuilder: (context, index) {
                  final s = similar[index];
                  return EmbyPosterTile(
                    item: s,
                    imageUrl: embyImageUrl(
                      serverUrl: server.url,
                      itemId: s.id,
                      accessToken: server.accessToken,
                      maxHeight: 420,
                      tag: s.primaryImageTag,
                    ),
                    headers: embyAuthHeaders(server),
                    onTap: () =>
                        context.pushNamed('/emby/detail', arguments: s),
                  );
                },
              ),
            ],
            // —— 媒体信息（选中集）
            if (source != null && _streamsOf(source).isNotEmpty) ...[
              const SizedBox(height: 26),
              EmbySectionHeader(title: '媒体信息'),
              _MediaInfoScroll(source: source, inset: inset),
            ],
          ],
        );
      },
    );
  }

  String _currentSeasonName(List<EmbyItem> seasons) {
    for (final s in seasons) {
      if (s.id == currentSeasonId) return s.name;
    }
    return seasons.isNotEmpty ? seasons.first.name : '第1季';
  }

  List<int> _orderOf(int count) => descending
      ? List<int>.generate(count, (int i) => count - 1 - i)
      : List<int>.generate(count, (int i) => i);

  void _openAllEpisodes(BuildContext context, List<EmbyItem> episodes) {
    Navigator.of(context)
        .push<int>(MaterialPageRoute<int>(
          builder: (_) => _AllEpisodesPage(
            seasonName: _currentSeasonName(seasons),
            server: server,
            episodes: episodes,
            descending: descending,
            pickedIndex: picked,
          ),
        ))
        .then((index) {
      if (index != null) onPickedFromAllPage(index);
    });
  }
}

// ------------------------------------------------------------- 小组件

/// ★ 评分 + 分级胶囊 + 类型。
class _RateRow extends StatelessWidget {
  const _RateRow({required this.item});

  final EmbyItem item;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (item.communityRating != null) ...[
        const Text('★', style: TextStyle(color: Color(0xFFFFD166), fontSize: 14)),
        const SizedBox(width: 3),
        Text(
          item.communityRating!.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            shadows: [Shadow(color: Color(0x40000000), blurRadius: 6)],
          ),
        ),
      ],
      if (item.officialRating != null && item.officialRating!.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.3),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            item.officialRating!,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      if (item.genres.isNotEmpty)
        Text(
          item.genres.take(3).join(' / '),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Color(0x40000000), blurRadius: 6)],
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}

/// meta 行：时长 · 年份 · 媒体流摘要（4K / HDR / fps…）。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.item, required this.source});

  final EmbyItem item;
  final EmbyMediaSource? source;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    final parts = <String>[
      if (item.runTime != null) _formatRuntime(item.runTime!),
      if (item.productionYear != null) '${item.productionYear}',
      ..._mediaChips(source),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final part in parts)
          Text(
            part,
            style: TextStyle(
              color: p.inkPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  List<String> _mediaChips(EmbyMediaSource? source) {
    if (source == null) return const [];
    final out = <String>[];
    for (final s in source.mediaStreams) {
      final t = s.label;
      if (t.isEmpty) continue;
      // 视频流的 displayTitle 常自带「4K · HDR · 60FPS」这类描述。
      if (out.length >= 3) break;
      out.add(t);
    }
    return out;
  }

  String _formatRuntime(Duration value) {
    if (value.inHours >= 1) {
      final minutes = value.inMinutes % 60;
      return minutes == 0 ? '${value.inHours} 小时' : '${value.inHours} 小时 $minutes 分';
    }
    return '${value.inMinutes} 分钟';
  }
}

/// 白底大播放按钮。
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.label,
    required this.starting,
    required this.onTap,
  });

  final String label;
  final bool starting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: 0,
      shadowColor: const Color(0x1A141E32),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: starting ? null : onTap,
        child: Container(
          height: 47,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(color: Color(0x1A141E32), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              starting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 22, color: Color(0xFF111111)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已看 / 收藏 圆圈按钮行。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.played,
    required this.favorite,
    required this.onTogglePlayed,
    required this.onToggleFavorite,
  });

  final bool played;
  final bool favorite;
  final VoidCallback onTogglePlayed;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    Widget circle({required bool on, required IconData icon, required String tip, required VoidCallback onTap}) {
      return Tooltip(
        message: tip,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: on ? const Color(0xFF0A84FF) : const Color(0x38000000),
                width: 1.4,
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: on ? const Color(0xFF0A84FF) : const Color(0xFF2A2A30),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        circle(
          on: played,
          icon: Icons.check_rounded,
          tip: played ? '取消标记已看' : '标记已看',
          onTap: onTogglePlayed,
        ),
        const SizedBox(width: 34),
        circle(
          on: favorite,
          icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          tip: favorite ? '取消收藏' : '收藏',
          onTap: onToggleFavorite,
        ),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.prefix,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String prefix;
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    return GestureDetector(
      onTap: onToggle,
      child: Text(
        prefix + text,
        maxLines: expanded ? null : 3,
        overflow: expanded ? null : TextOverflow.ellipsis,
        style: TextStyle(
          color: p.inkSecondary,
          fontSize: 12.5,
          height: 1.65,
        ),
      ),
    );
  }
}

/// 季下拉 + 倒序/正序 + 「更多」打开全集列表页。
class _SeasonBar extends StatelessWidget {
  const _SeasonBar({
    required this.seasons,
    required this.currentSeasonId,
    required this.seasonName,
    required this.descending,
    required this.pickedIndex,
    required this.onOpenAll,
    required this.onSwitchSeason,
    required this.onToggleOrder,
  });

  final List<EmbyItem> seasons;
  final String currentSeasonId;
  final String seasonName;
  final bool descending;
  final int pickedIndex;
  final VoidCallback onOpenAll;
  final ValueChanged<String> onSwitchSeason;
  final VoidCallback onToggleOrder;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (seasons.length > 1)
            PopupMenuButton<String>(
              initialValue: currentSeasonId,
              onSelected: onSwitchSeason,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (context) => [
                for (final s in seasons)
                  PopupMenuItem<String>(
                    value: s.id,
                    child: Row(
                      children: [
                        Expanded(child: Text(s.name, style: const TextStyle(fontSize: 14))),
                        if (s.id == currentSeasonId)
                          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF0A84FF)),
                      ],
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seasonName,
                    style: TextStyle(
                      color: p.inkPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: p.inkPrimary),
                ],
              ),
            )
          else
            Text(
              seasonName,
              style: TextStyle(
                color: p.inkPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: descending ? '改为正序' : '改为倒序（最新在前）',
            onPressed: onToggleOrder,
            icon: Icon(
              Icons.format_line_spacing_rounded,
              size: 19,
              color: p.inkSecondary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onOpenAll,
            child: Text(
              '更多',
              style: TextStyle(color: p.inkSecondary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 集号圆点横滑：34px 圆钮，选中白底深字并放大 1.06。
class _EpisodeNums extends StatelessWidget {
  const _EpisodeNums({
    required this.episodes,
    required this.order,
    required this.picked,
    required this.numKeys,
    required this.onPick,
  });

  final List<EmbyItem> episodes;
  final List<int> order;
  final int picked;
  final Map<String, GlobalKey> numKeys;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final int i in order)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _EpNumButton(
                key: numKeys[episodes[i].id],
                label: '${i + 1}',
                selected: i == picked,
                onTap: () => onPick(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpNumButton extends StatelessWidget {
  const _EpNumButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '第 $label 集',
      child: InkResponse(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(context).colorScheme.surface.withValues(alpha: 0.66),
              boxShadow: selected
                  ? const [BoxShadow(color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 2))]
                  : const [BoxShadow(color: Color(0x0D000000), blurRadius: 2)],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 集卡横滑：47% 宽露边、16:9 图、白圈选中、下面集号标题 + 三行简介。
class _EpisodeRail extends StatelessWidget {
  const _EpisodeRail({
    required this.episodes,
    required this.order,
    required this.picked,
    required this.server,
    required this.inset,
    required this.cardKeys,
    required this.onPick,
  });

  final List<EmbyItem> episodes;
  final List<int> order;
  final int picked;
  final EmbyServer server;
  final double inset;
  final Map<String, GlobalKey> cardKeys;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final bool desktop = embyIsDesktop(context);

    return SizedBox(
      // 演示视频里集卡是"竖版近方形缩略图 + 下面三行字"，比原来高不少。
      height: desktop ? 340 : 300,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: inset),
        itemExtent: desktop ? 250 : null,
        children: [
          for (final int i in order)
            LayoutBuilder(builder: (context, constraints) {
              final double cardWidth = desktop
                  ? 250
                  : (constraints.maxWidth * 0.28);
              return Padding(
                padding: EdgeInsets.only(
                  right: i == order.last ? 0 : 12,
                ),
                child: SizedBox(
                  width: cardWidth,
                  child: _EpisodeCard(
                    key: cardKeys[episodes[i].id],
                    item: episodes[i],
                    server: server,
                    index: i,
                    selected: i == picked,
                    onPick: () => onPick(i),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    super.key,
    required this.item,
    required this.server,
    required this.index,
    required this.selected,
    required this.onPick,
  });

  final EmbyItem item;
  final EmbyServer server;
  final int index;
  final bool selected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    // 单集经常没有自己的封面图（服务端默认不生成剧集缩略图），
    // 这时候拿剧集本身的图顶上——比留一块灰底强得多。
    final bool hasOwnImage = (item.primaryImageTag ?? '').isNotEmpty;
    final String? seriesId = item.seriesId;
    final String image = embyImageUrl(
      serverUrl: server.url,
      itemId: !hasOwnImage && seriesId != null && seriesId.isNotEmpty
          ? seriesId
          : item.id,
      accessToken: server.accessToken,
      maxHeight: 420,
      tag: hasOwnImage ? item.primaryImageTag : null,
    );

    return GestureDetector(
      onTap: onPick,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              // 选中：白色描边（视频里是白圈），未选中留一圈很淡的内描边。
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.22),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                          color: Color(0x38000000),
                          blurRadius: 14,
                          offset: Offset(0, 3)),
                    ]
                  : const [],
            ),
            child: AspectRatio(
              // 竖版近方形：跟演示视频一致，横图会被居中裁切填满。
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EmbyImage(url: image, headers: embyAuthHeaders(server)),
                    if (item.watchedRatio > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black45,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: item.watchedRatio.clamp(0.0, 1.0),
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'E${(index + 1).toString().padLeft(2, '0')} · ${embyEpisodeLabel(item, index + 1)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.inkPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              item.overview!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.inkTertiary, fontSize: 11, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

/// 媒体信息横滑胶囊：视频 / 音轨 / 字幕 / 容器。
class _MediaInfoScroll extends StatelessWidget {
  const _MediaInfoScroll({required this.source, required this.inset});

  final EmbyMediaSource source;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    final chips = <String>[
      if (source.container.isNotEmpty) source.container.toUpperCase(),
      ..._streamsOf(source),
    ];
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: inset),
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: p.hairlineStrong.withValues(alpha: 0.6)),
                ),
                child: Text(
                  chip,
                  style: TextStyle(
                    color: p.inkSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

List<String> _streamsOf(EmbyMediaSource source) {
  final out = <String>[];
  for (final s in source.mediaStreams) {
    if (s.isAudio || s.isSubtitle) {
      final t = s.label;
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    } else {
      final t = s.label;
      if (t.isNotEmpty && !out.contains(t)) out.insert(0, t);
    }
    if (out.length >= 5) break;
  }
  return out;
}

// ---------------------------------------------------------- 全集列表页

/// 「第N季 · 全集」：白底、返回 + 居中标题 + 圆圈对号关闭、两列 16:9 网格。
class _AllEpisodesPage extends StatelessWidget {
  const _AllEpisodesPage({
    required this.seasonName,
    required this.server,
    required this.episodes,
    required this.descending,
    required this.pickedIndex,
  });

  final String seasonName;
  final EmbyServer server;
  final List<EmbyItem> episodes;
  final bool descending;
  final int pickedIndex;

  List<int> get _order => descending
      ? List<int>.generate(episodes.length, (int i) => episodes.length - 1 - i)
      : List<int>.generate(episodes.length, (int i) => i);

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Row(
                children: [
                  RexIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 16,
                    size: 34,
                    glass: false,
                    color: p.inkPrimary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      '$seasonName · 全集',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.inkPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  // 右上圆圈对号 = 关闭返回。
                  _CircleCheck(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                // 跟详情页集卡对齐：图片固定 3:4 竖版，下面留一行集号。
                final double cardWidth = (c.maxWidth - 40 - 12) / 2;
                final double extent = cardWidth * 4 / 3 + 7 + 21;
                return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 34),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  mainAxisExtent: extent,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, listIndex) {
                  final int i = _order[listIndex.clamp(0, episodes.length - 1)];
                  final item = episodes[i];
                  return _AllEpisodeCard(
                    item: item,
                    server: server,
                    index: i,
                    selected: i == pickedIndex,
                    onTap: () => Navigator.of(context).pop(i),
                  );
                },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleCheck extends StatelessWidget {
  const _CircleCheck({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.inkPrimary.withValues(alpha: 0.28), width: 1.6),
        ),
        child: Icon(Icons.check_rounded, size: 17, color: p.inkPrimary),
      ),
    );
  }
}

class _AllEpisodeCard extends StatelessWidget {
  const _AllEpisodeCard({
    required this.item,
    required this.server,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final EmbyItem item;
  final EmbyServer server;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = RexPalette.of(context);
    final bool hasOwnImage = (item.primaryImageTag ?? '').isNotEmpty;
    final String? seriesId = item.seriesId;
    final String image = embyImageUrl(
      serverUrl: server.url,
      itemId: !hasOwnImage && seriesId != null && seriesId.isNotEmpty
          ? seriesId
          : item.id,
      accessToken: server.accessToken,
      maxHeight: 420,
      tag: hasOwnImage ? item.primaryImageTag : null,
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.22),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                          color: Color(0x38000000),
                          blurRadius: 14,
                          offset: Offset(0, 3)),
                    ]
                  : const [],
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EmbyImage(url: image, headers: embyAuthHeaders(server)),
                    if (item.watchedRatio > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black45,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: item.watchedRatio.clamp(0.0, 1.0),
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'E${(index + 1).toString().padLeft(2, '0')} · ${embyEpisodeLabel(item, index + 1)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.inkPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
