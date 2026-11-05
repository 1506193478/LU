import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_res_pane.dart';
import 'package:XL/pages/emby/emby_search_pane.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/theme/rex_big_view.dart';

/// Emby 首页：底部二级导航「媒体库 / 资源库 / 我的」。
///
/// 按 `LU_3.9.19_预览.html` 落地：
/// - **媒体库**：通栏大图 + 服务器胶囊（页内下拉切换）+ 继续观看 +
///   我的媒体 + 每库一轨的海报滑轨 + 统计条；
/// - **资源库**：搜索条 + 两列渐变网格卡 + 添加来源 / 显示选项菜单；
/// - **我的**：Emby 服务器信息 + 资源模块 + 播放器设置（iOS 分组）。
///
/// 二级导航浮在底栏上方（不占内容高度），三个页签用 [IndexedStack] 保状态。
class EmbyPage extends StatefulWidget {
  const EmbyPage({super.key});

  @override
  State<EmbyPage> createState() => _EmbyPageState();
}

class _EmbyPageState extends State<EmbyPage> {
  int _pane = 0;
  Future<_HomeData>? _future;
  bool _opening = false;

  /// 顶栏要用的服务器。故意和 future 解耦：future 还在跑、或者已经失败，
  /// 顶栏也得显示当前是哪台服务器，否则用户不知道自己在连谁。
  EmbyServer? _server;

  @override
  void initState() {
    super.initState();
    // `load()` 里没有真正的 await，同步读一次就能拿到已保存的服务器。
    unawaited(EmbyService.instance.load());
    _server = EmbyService.instance.activeServer;
    _future = _load();
    EmbyService.instance.revision.addListener(_onRevisionChanged);
  }

  /// 我的页签要显示的库数量（_load 拉到 libraries 后更新）。
  int _libCount = 0;

  @override
  void dispose() {
    EmbyService.instance.revision.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() {
    if (!mounted) return;
    setState(() {
      _server = EmbyService.instance.activeServer;
      _future = _load();
    });
  }

  Future<_HomeData> _load() async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) {
      return const _HomeData(
        server: null,
        libraries: [],
        resume: [],
        latest: [],
        rails: [],
      );
    }
    final client = service.clientFor(server);
    final libraries = await client.fetchLibraries(server.userId);
    if (mounted) setState(() => _libCount = libraries.length);

    // 这两块是「锦上添花」，服务器不支持或者超时都不该让整页变成错误态。
    var resume = <EmbyItem>[];
    var latest = <EmbyItem>[];
    EmbyItemCounts? counts;
    try {
      resume = await client.fetchResume(userId: server.userId);
    } catch (e) {
      KazumiLogger().w('Emby home: failed to load resume', error: e);
    }
    try {
      latest = await client.fetchLatest(userId: server.userId);
    } catch (e) {
      KazumiLogger().w('Emby home: failed to load latest', error: e);
    }

    // 每个内容库一条海报滑轨（预览稿的「3.追番」「4.日番」就是这种轨）。
    // 音乐 / 书籍类库不进首页，最多取 4 条轨避免一次打太多请求。
    final rails = <_LibRail>[];
    final railLibs = libraries
        .where(
          (lib) =>
              lib.collectionType != 'music' &&
              lib.collectionType != 'audiobooks' &&
              lib.collectionType != 'books' &&
              lib.collectionType != 'playlists',
        )
        .take(4);
    final railFutures = <Future<_LibRail?>>[
      for (final lib in railLibs)
        () async {
          try {
            final items = await client.fetchLatest(
              userId: server.userId,
              parentId: lib.id,
              limit: 12,
            );
            var count = 0;
            try {
              count = await client.fetchLibraryCount(
                userId: server.userId,
                parentId: lib.id,
              );
            } catch (_) {}
            return _LibRail(library: lib, items: items, count: count);
          } catch (e) {
            KazumiLogger().w(
              'Emby home: failed to load rail ${lib.name}',
              error: e,
            );
            return null;
          }
        }(),
    ];
    rails.addAll((await Future.wait(railFutures)).whereType<_LibRail>());

    // 统计条：电影 / 节目 / 集数。拿不到就整条不显示。
    try {
      counts = await client.fetchItemCounts(userId: server.userId);
    } catch (e) {
      KazumiLogger().w('Emby home: failed to load counts', error: e);
    }

    return _HomeData(
      server: server,
      libraries: libraries,
      resume: resume,
      latest: latest,
      rails: rails,
      counts: counts,
    );
  }

  Future<void> _openServers() async {
    await context.pushNamed('/emby/servers');
  }

  /// 首页右上角的搜索：只搜这台服务器上的影片。
  ///
  /// 和「搜索」页签（聚合所有服务器 + 播放记录）刻意分开：那一个是找
  /// 「我到底把它放哪了」，这一个是在当前服务器里翻片。
  Future<void> _openServerSearch(EmbyServer server) async {
    final active = EmbyService.instance.activeServer;
    if (active?.id != server.id) {
      await EmbyService.instance.setActive(server.id);
    }
    if (!mounted) return;
    await context.pushNamed('/emby/search', arguments: server.id);
  }

  void _openDetail(EmbyItem item) {
    // 点卡片的瞬间就开始拉详情数据，转场期间网络并行跑。
    EmbyDetailPage.prefetch(item);
    context.pushNamed('/emby/detail', arguments: item);
  }

  void _openLibrary(EmbyLibrary library) {
    context.pushNamed('/emby/library', arguments: library);
  }

  /// 点资源库里的服务器卡片：切成这台服务器并跳到媒体库页签。
  ///
  /// 换服务器会触发 revision，`_onRevisionChanged` 自己会把媒体库刷一遍。
  Future<void> _switchServer(EmbyServer server) async {
    final current = EmbyService.instance.activeServer;
    if (current?.id == server.id) {
      setState(() => _pane = 0);
      return;
    }
    await EmbyService.instance.setActive(server.id);
    if (mounted) setState(() => _pane = 0);
  }

  void _pickPane(int index) {
    if (index == _pane) return;
    setState(() => _pane = index);
  }

  /// 从首页直接起播。
  ///
  /// 单集要先把整季拉下来，否则播放器里没有「下一集」；剧集本身不能直接播，
  /// 交给详情页让用户选。电影就是自己一条。
  Future<void> _play(EmbyItem item) async {
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    if (item.isSeries) {
      _openDetail(item);
      return;
    }
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final client = EmbyService.instance.clientFor(server);
      var episodes = <EmbyItem>[item];
      var index = 0;
      if (item.isEpisode && (item.seriesId?.isNotEmpty ?? false)) {
        try {
          final all = await client.fetchEpisodes(
            userId: server.userId,
            seriesId: item.seriesId!,
          );
          if (all.isNotEmpty) {
            episodes = all;
            final found = all.indexWhere((e) => e.id == item.id);
            index = found < 0 ? 0 : found;
          }
        } catch (e) {
          KazumiLogger().w(
            'Emby home: failed to load episodes for play',
            error: e,
          );
        }
      }
      if (!mounted) return;
      await context.pushNamed(
        '/emby/player',
        arguments: EmbyPlaybackLaunch(
          server: server,
          title: item.isEpisode
              ? (item.seriesName?.isNotEmpty == true
                    ? item.seriesName!
                    : item.name)
              : item.name,
          episodes: episodes,
          initialIndex: index,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        _onRevisionChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      body: Stack(
        children: [
          // IndexedStack 保三个页签的状态：切走再回来不用重新拉数据，
          // 滚动位置也还在。空服务器时三个页签都给引导。
          IndexedStack(
            index: _pane,
            children: [
              _LibraryPane(
                future: _future,
                server: _server,
                onRetry: _onRevisionChanged,
                onSwitchServer: _openServers,
                onPlay: _play,
                onOpenDetail: _openDetail,
                onOpenLibrary: _openLibrary,
                onSearchServer: _openServerSearch,
              ),
              EmbyResourcePane(
                onSwitchServer: _switchServer,
                onEditServer: _openServers,
                onOpenLibrary: () => setState(() => _pane = 0),
              ),
              EmbySearchPane(
                onOpenDetail: _openDetail,
                onPlay: (item) => _play(item),
              ),
              EmbyMinePane(libraryCount: _libCount),
            ],
          ),
          // 二级导航：浮在底栏上方，不占内容高度。
          //
          // 基准必须用 `MediaQuery.padding.bottom`，不能再调
          // `immersiveTabBarInset()`。原因在外壳：`menu.dart` 的 Scaffold 是
          // `extendBody: true`，Flutter 会在 `_BodyBuilder` 里把底栏高度注入
          // body 的 MediaQuery——
          //   padding.bottom = max(系统安全区, bottomWidgetsHeight)
          // 也就是说 body 里量到的 padding.bottom **就是底栏上沿离屏幕底的
          // 距离**，body 本身是伸到屏幕底的。
          //
          // 之前两次都错在这一步：
          //   · `inset + 1`：immersiveTabBarInset 自己又加 62+6，底栏高度被算
          //     了两遍，整条浮到半空（截图量出来 68dp 正好是 62+6）；
          //   · `bottom: 2`：矫枉过正，整条沉到屏幕底，跟底栏完全重合、看不见。
          //
          // 现在 = 底栏上沿 + 6 的缝，落在「继续观看」下面那条空带上。
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 6,
            child: Center(
              child: _EmbySubDock(index: _pane, onChanged: _pickPane),
            ),
          ),
        ],
      ),
    );
  }
}

/// 二级导航胶囊（预览稿 `.subdock`）。
///
/// 顺序固定为「媒体库 / 资源库 / 搜索 / 我的」。整条内高 26（外高 32），
/// 白 68% 毛玻璃；选中项底色 rgba(56,84,128,.15)、文字 #2F4E7A。
///
/// 用户明确说过「不是要薄，是要位置往下」——所以厚度保持这个比例，
/// 靠上面的 Positioned 去调位置。
class _EmbySubDock extends StatelessWidget {
  const _EmbySubDock({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = <(IconData, String)>[
    (Icons.grid_view_rounded, '媒体库'),
    (Icons.dns_rounded, '资源库'),
    (Icons.search_rounded, '搜索'),
    (Icons.person_outline_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);

    return Material(
      color: dark
          ? Colors.black.withValues(alpha: 0.46)
          : Colors.white.withValues(alpha: 0.68),
      shape: StadiumBorder(
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: const Color(0x21141E32),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _items.length; i++)
              _SubDockButton(
                icon: _items[i].$1,
                label: _items[i].$2,
                selected: i == index,
                onTap: () => onChanged(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubDockButton extends StatelessWidget {
  const _SubDockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = selected
        ? PvColors.subInk(context)
        : const Color(0xFF6C6C72);

    return PressableInk(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PvColors.subCap(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 无主题依赖的按压缩放包装（预览稿的按下反馈很轻，只要一点透明度）。
class PressableInk extends StatelessWidget {
  const PressableInk({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.server,
    required this.libraries,
    required this.resume,
    required this.latest,
    this.rails = const [],
    this.counts,
  });

  final EmbyServer? server;
  final List<EmbyLibrary> libraries;
  final List<EmbyItem> resume;
  final List<EmbyItem> latest;
  final List<_LibRail> rails;
  final EmbyItemCounts? counts;
}

/// 每个内容库一条滑轨的数据。
class _LibRail {
  const _LibRail({
    required this.library,
    required this.items,
    required this.count,
  });

  final EmbyLibrary library;
  final List<EmbyItem> items;
  final int count;
}

/// 媒体库页签。
class _LibraryPane extends StatelessWidget {
  const _LibraryPane({
    required this.future,
    required this.server,
    required this.onRetry,
    required this.onSwitchServer,
    required this.onPlay,
    required this.onOpenDetail,
    required this.onOpenLibrary,
    required this.onSearchServer,
  });

  final Future<_HomeData>? future;
  final EmbyServer? server;
  final VoidCallback onRetry;
  final VoidCallback onSwitchServer;
  final ValueChanged<EmbyItem> onPlay;
  final ValueChanged<EmbyItem> onOpenDetail;
  final ValueChanged<EmbyLibrary> onOpenLibrary;
  final ValueChanged<EmbyServer> onSearchServer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: EmbyFutureView<_HomeData>(
        future: future!,
        onRetry: onRetry,
        onSwitchServer: onSwitchServer,
        builder: (context, data) {
          if (data.server == null) {
            return _NoServerGuide(onAdd: onSwitchServer);
          }
          return _HomeBody(
            data: data,
            onPlay: onPlay,
            onOpenDetail: onOpenDetail,
            onOpenLibrary: onOpenLibrary,
            onRetry: onRetry,
            onOpenServers: onSwitchServer,
            onSearchServer: onSearchServer,
          );
        },
      ),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({
    required this.data,
    required this.onPlay,
    required this.onOpenDetail,
    required this.onOpenLibrary,
    required this.onRetry,
    required this.onOpenServers,
    required this.onSearchServer,
  });

  final _HomeData data;
  final ValueChanged<EmbyItem> onPlay;
  final ValueChanged<EmbyItem> onOpenDetail;
  final ValueChanged<EmbyLibrary> onOpenLibrary;
  final VoidCallback onRetry;
  final VoidCallback onOpenServers;

  /// 右上角搜索：只搜这台服务器（另一个搜索页签是聚合所有服务器）。
  final ValueChanged<EmbyServer> onSearchServer;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  /// 顶栏毛玻璃的「进度」：滚多少，玻璃吃多少背景。
  ///
  /// 用 ValueNotifier 而不是 setState——滚动是每帧都在变的事件，整页跟着
  /// rebuild 就本末倒置了（首页本来就有一堆网络图）。
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) {
      _scroll.value = n.metrics.pixels;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final server = data.server!;
    final bool desktop = embyIsDesktop(context);

    final heroItems = _heroItems();
    final double heroHeight = desktop
        ? 380
        : (MediaQuery.sizeOf(context).height * 0.59).clamp(440.0, 560.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 内容整条滑到顶栏下面，顶栏不再跟着滚走。
        KzRefreshIndicator(
          onRefresh: () async => widget.onRetry(),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              slivers: [
                // 通栏大图：图片顶到状态栏底下，服务器胶囊浮在左上、爱心在右上。
                SliverToBoxAdapter(
                  child: RexBigViewCarousel(
                    items: heroItems,
                    fadeColor: PvColors.page(context),
                    height: heroHeight,
                    emptyBuilder: _EmptyHero(
                      onOpenServers: widget.onOpenServers,
                    ),
                  ),
                ),
                if (data.resume.isNotEmpty) ...[
                  PvSliverHead(
                    title: '继续观看',
                    count: '${data.resume.length}',
                    onMore: () {},
                  ),
                  SliverToBoxAdapter(
                    child: _ResumeRail(
                      data: data,
                      // 顶部状态栏压在大图上，先给顶栏留出安全区。
                      onPlay: widget.onPlay,
                    ),
                  ),
                ],
                PvSliverHead(
                  title: '我的媒体',
                  count: '${data.libraries.length}',
                  onMore: () {},
                ),
                SliverToBoxAdapter(
                  child: _MediaFolderRail(
                    data: data,
                    onOpen: widget.onOpenLibrary,
                  ),
                ),
                for (final rail in data.rails) ...[
                  PvSliverHead(
                    title: rail.library.name,
                    count: rail.count > 0 ? _formatCount(rail.count) : null,
                    onMore: () => widget.onOpenLibrary(rail.library),
                  ),
                  SliverToBoxAdapter(
                    child: _PosterRail(
                      server: server,
                      items: rail.items,
                      onTap: (item) => item.isSeries
                          ? widget.onOpenDetail(item)
                          : widget.onPlay(item),
                    ),
                  ),
                ],
                if (data.counts != null)
                  SliverToBoxAdapter(child: _StatsRow(counts: data.counts!)),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: pvSubDockClearance),
                ),
              ],
            ),
          ),
        ),
        // 常驻顶栏：液态玻璃胶囊，滚到哪都在，背景从下面透出来。
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _GlassTopBar(
            server: server,
            scroll: _scroll,
            onManage: widget.onOpenServers,
            onSearch: () => widget.onSearchServer(server),
            onFavorite: () =>
                KazumiDialog.showToast(message: '已收藏这个服务器'),
          ),
        ),
      ],
    );
  }

  /// 大视图轮播数据：正在看的优先，再补最近入库，最多 5 条。
  List<RexBigViewItem> _heroItems() {
    final data = widget.data;
    final server = data.server!;
    final heroes = <EmbyItem>[];
    for (final item in data.resume) {
      if (item.isInProgress) heroes.add(item);
      if (heroes.length >= 5) break;
    }
    for (final item in data.latest) {
      if (heroes.length >= 5) break;
      if (!heroes.any((h) => h.id == item.id)) heroes.add(item);
    }
    if (heroes.isEmpty) {
      heroes.addAll(data.resume.take(2));
    }
    return [
      for (final item in heroes)
        RexBigViewItem(
          imageUrl: item.backdropImageTag != null
              ? embyBackdropUrl(
                  serverUrl: server.url,
                  itemId: item.id,
                  accessToken: server.accessToken,
                  tag: item.backdropImageTag,
                )
              : embyImageUrl(
                  serverUrl: server.url,
                  itemId: item.coverItemId,
                  accessToken: server.accessToken,
                  maxHeight: 900,
                  tag: item.coverTag,
                ),
          headers: embyAuthHeaders(server),
          title: item.name,
          score: item.communityRating?.toStringAsFixed(1),
          year: item.productionYear?.toString(),
          badge: (item.officialRating ?? '').isEmpty
              ? null
              : item.officialRating,
          genres: item.genres.isEmpty ? null : item.genres.take(2).join(' / '),
          desc: (item.overview ?? '').trim().isEmpty
              ? null
              : item.overview!.trim(),
          onTap: () => item.isEpisode
              ? widget.onPlay(item)
              : widget.onOpenDetail(item),
        ),
    ];
  }
}

/// 千分位格式化：15941 → 15,941（预览稿统计条样式）。
String _formatCount(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - 1 - i;
    if (left > 0 && left % 3 == 0) buf.write(',');
  }
  return buf.toString();
}

/// `.sect` 区块标题的 Sliver 版。
class PvSliverHead extends SliverToBoxAdapter {
  PvSliverHead({
    super.key,
    required String title,
    String? count,
    VoidCallback? onMore,
  }) : super(
         child: PvSectionHead(title, count: count, onMore: onMore),
       );
}

/// 服务器胶囊 + 页内下拉（预览稿 `.chip2` + `#chipDrop`）。
class _ServerChipWithDrop extends StatefulWidget {
  const _ServerChipWithDrop({required this.server, required this.onManage});

  final EmbyServer server;
  final VoidCallback onManage;

  @override
  State<_ServerChipWithDrop> createState() => _ServerChipWithDropState();
}

class _ServerChipWithDropState extends State<_ServerChipWithDrop> {
  final GlobalKey _chipKey = GlobalKey();

  Future<void> _openDrop() async {
    final box = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final service = EmbyService.instance;
    final servers = service.servers;
    final active = service.activeServer;

    await showPvMenu<Object>(
      context: context,
      minWidth: 250,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height + 6,
        (overlay.size.width - origin.dx - 250).clamp(0.0, overlay.size.width),
        0,
      ),
      items: [
        for (final server in servers)
          PvMenuItem(
            server.name,
            checked: server.id == active?.id,
            onTap: () async {
              if (server.id == active?.id) return;
              await EmbyService.instance.setActive(server.id);
            },
          ),
        const PvMenuItem.divider(),
        PvMenuItem('管理服务器…', onTap: widget.onManage),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    return KzPressable(
      key: _chipKey,
      onTap: _openDrop,
      pressedOpacity: 0.6,
      child: _GlassPlate(
        radius: 19,
        height: 38,
        padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 预览稿 chip2 的图标：绿色圆角方块 + 白色播放三角。
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: PvColors.green,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                widget.server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: dark
                      ? const Color(0xFFEDEDEF)
                      : const Color(0xFF1B1B1F),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: dark ? const Color(0xFF9A9AA2) : const Color(0xFF5A5A60),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常驻顶栏：服务器胶囊 + 服务器内搜索 + 收藏。
///
/// 之前这排按钮挂在通栏大图的 `topOverlay` 上，跟着大图一起滚走——滑到
/// 「继续观看」就没有入口了。现在钉在页面顶部，滚动时背景从玻璃后面透
/// 出来（液态玻璃：磨砂 + 淡色调 + 高光描边），滚得越多雾面越实。
class _GlassTopBar extends StatelessWidget {
  const _GlassTopBar({
    required this.server,
    required this.scroll,
    required this.onManage,
    required this.onSearch,
    required this.onFavorite,
  });

  final EmbyServer server;
  final ValueListenable<double> scroll;
  final VoidCallback onManage;
  final VoidCallback onSearch;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final Color page = PvColors.page(context);
    return ValueListenableBuilder<double>(
      valueListenable: scroll,
      builder: (context, offset, _) {
        // 0 = 还压在大图上（几乎全透），1 = 已经滑到海报墙上（雾面兜住）。
        final double t = (offset / 120).clamp(0.0, 1.0);
        return Stack(
          children: [
            if (t > 0.02)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              page.withValues(alpha: 0.88 * t),
                              page.withValues(alpha: 0.62 * t),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context) - 6,
                  10,
                  embyPagePadding(context),
                  10,
                ),
                child: Row(
                  children: [
                    _ServerChipWithDrop(server: server, onManage: onManage),
                    const Spacer(),
                    _GlassIconButton(
                      icon: Icons.search_rounded,
                      hint: '搜索这台服务器的影片',
                      onTap: onSearch,
                    ),
                    const SizedBox(width: 8),
                    _GlassIconButton(
                      icon: Icons.favorite_rounded,
                      color: PvColors.red,
                      hint: '收藏',
                      onTap: onFavorite,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 液态玻璃底板：圆角裁切 + 背景模糊 + 半透明着色 + 顶部高光。
///
/// `BackdropFilter` 必须包在 `ClipRRect` 里，否则模糊会溢出圆角，看起来
/// 就是一块糊掉的方块而不是玻璃。
class _GlassPlate extends StatelessWidget {
  const _GlassPlate({
    required this.child,
    this.radius = 19,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            // 深色主题用黑玻璃、浅色用白玻璃；两边都留一点底色保证文字
            // 压在任何封面上都读得清。
            color: (dark ? Colors.black : Colors.white).withValues(
              alpha: dark ? 0.44 : 0.58,
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.14 : 0.72),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A141E32),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 顶栏的圆形玻璃按钮（搜索 / 收藏）。
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.hint,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String hint;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return Semantics(
      button: true,
      label: hint,
      child: KzPressable(
        onTap: onTap,
        pressedOpacity: 0.6,
        child: _GlassPlate(
          radius: 19,
          width: 38,
          height: 38,
          child: Center(
            child: Icon(
              icon,
              size: 19,
              color:
                  color ??
                  (dark ? const Color(0xFFEDEDEF) : const Color(0xFF26262B)),
            ),
          ),
        ),
      ),
    );
  }
}

/// 继续观看横滑：预览稿 `.resumecard`，一屏两张（58% 宽）、时间码贴右下。
class _ResumeRail extends StatelessWidget {
  const _ResumeRail({required this.data, required this.onPlay});

  final _HomeData data;
  final ValueChanged<EmbyItem> onPlay;

  @override
  Widget build(BuildContext context) {
    final server = data.server!;
    final double cardWidth = embyIsDesktop(context)
        ? 300
        : MediaQuery.sizeOf(context).width * 0.58;
    return SizedBox(
      height: cardWidth * 9 / 16 + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: data.resume.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = data.resume[index];
          final hasOwnImage = (item.primaryImageTag ?? '').isNotEmpty;
          final seriesId = item.seriesId;
          final imageUrl = embyImageUrl(
            serverUrl: server.url,
            itemId: !hasOwnImage && seriesId != null && seriesId.isNotEmpty
                ? seriesId
                : item.id,
            accessToken: server.accessToken,
            maxHeight: 420,
            tag: hasOwnImage ? item.primaryImageTag : null,
          );
          return SizedBox(
            width: cardWidth,
            child: EmbyResumeCard(
              imageUrl: imageUrl,
              headers: embyAuthHeaders(server),
              title: item.isEpisode
                  ? (item.seriesName?.isNotEmpty == true
                        ? item.seriesName!
                        : item.name)
                  : item.name,
              subtitle: item.isEpisode ? item.cardSubtitle : '继续观看',
              timeLabel: _timeLabel(item),
              progress: item.watchedRatio,
              onTap: () => onPlay(item),
            ),
          );
        },
      ),
    );
  }

  String _timeLabel(EmbyItem item) {
    final total = item.runTime;
    if (total == null) return '继续播放';
    final watched = Duration(
      microseconds: (item.playbackPositionTicks ?? 0) ~/ 10,
    );
    String fmt(Duration d) {
      final m = d.inMinutes.clamp(0, 999);
      final s = d.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    return '▶ ${fmt(watched)} / ${fmt(total)}';
  }
}

/// 我的媒体横滑：预览稿 `.mediacard`，47% 宽、文字压图正中。
class _MediaFolderRail extends StatelessWidget {
  const _MediaFolderRail({required this.data, required this.onOpen});

  final _HomeData data;
  final ValueChanged<EmbyLibrary> onOpen;

  static const _tones = <Color>[
    Color(0xFF5C6E82),
    Color(0xFF6E5C50),
    Color(0xFF4C5E6E),
    Color(0xFF56645C),
    Color(0xFF6E5C6E),
  ];

  @override
  Widget build(BuildContext context) {
    final server = data.server!;
    final double cardWidth = embyIsDesktop(context)
        ? 260
        : MediaQuery.sizeOf(context).width * 0.47;
    return SizedBox(
      height: cardWidth * 9 / 16 + 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: data.libraries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final library = data.libraries[index];
          final hasImage = (library.imageTag ?? '').isNotEmpty;
          return SizedBox(
            width: cardWidth,
            child: EmbyFolderCard(
              name: library.name,
              imageUrl: hasImage
                  ? embyImageUrl(
                      serverUrl: server.url,
                      itemId: library.id,
                      accessToken: server.accessToken,
                      maxHeight: 420,
                      tag: library.imageTag,
                    )
                  : '',
              headers: embyAuthHeaders(server),
              fallbackColor: _tones[index % _tones.length],
              icon: _libraryIcon(library.collectionType),
              onTap: () => onOpen(library),
            ),
          );
        },
      ),
    );
  }

  IconData _libraryIcon(String type) {
    switch (type) {
      case 'movies':
        return Icons.movie_outlined;
      case 'tvshows':
        return Icons.live_tv_outlined;
      case 'music':
        return Icons.music_note_outlined;
      case 'boxsets':
        return Icons.collections_bookmark_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
}

/// 每库一条的海报滑轨。
class _PosterRail extends StatelessWidget {
  const _PosterRail({
    required this.server,
    required this.items,
    required this.onTap,
  });

  final EmbyServer server;
  final List<EmbyItem> items;
  final ValueChanged<EmbyItem> onTap;

  @override
  Widget build(BuildContext context) {
    return EmbyRail(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final count = item.childCount ?? 0;
        return EmbyPosterTile(
          item: item,
          imageUrl: embyImageUrl(
            serverUrl: server.url,
            itemId: item.coverItemId,
            accessToken: server.accessToken,
            maxHeight: 480,
            tag: item.coverTag,
          ),
          headers: embyAuthHeaders(server),
          // 预览稿海报右上角是集数徽标、右下角是评分。
          countBadge: item.isSeries && count > 0 ? _formatCount(count) : null,
          score: item.communityRating?.toStringAsFixed(1),
          onTap: () => onTap(item),
        );
      },
    );
  }
}

/// 统计条（预览稿 `.statsrow`）：电影 / 节目 / 集数 三张白卡。
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.counts});

  final EmbyItemCounts counts;

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final cardColor = dark ? const Color(0xFF232227) : Colors.white;
    Widget stat(int n, String label, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: dark
                ? null
                : const [BoxShadow(color: Color(0x0D000000), blurRadius: 3)],
          ),
          child: Column(
            children: [
              Text(
                n > 0 ? _formatCount(n) : '—',
                style: PvText.statNum.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(label, style: PvText.statLabel(context)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          stat(counts.movies, '电影', const Color(0xFFFF3B30)),
          const SizedBox(width: 11),
          stat(counts.series, '节目', const Color(0xFF3E7BFA)),
          const SizedBox(width: 11),
          stat(counts.episodes, '集数', PvColors.green),
        ],
      ),
    );
  }
}

/// 大图为空时的占位：保持高度，给出一句引导。
class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.onOpenServers});

  final VoidCallback onOpenServers;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PvColors.searchFill(context),
      child: Center(
        child: Text(
          '还没有正在看和最近入库的内容',
          style: TextStyle(fontSize: 13, color: PvColors.ink3(context)),
        ),
      ),
    );
  }
}

class _NoServerGuide extends StatelessWidget {
  const _NoServerGuide({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EmbyIntro(
                icon: Icons.dns_rounded,
                title: '连接 Emby 服务器',
                description: '填好服务器地址和账号密码，就能在 LU 里直接浏览和播放你自建媒体库的内容。',
              ),
              const SizedBox(height: 20),
              NeuSurface(
                radius: NeuRadius.card,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hint(
                      context,
                      '1',
                      '地址填服务器根地址，例如 http://192.168.1.10:8096',
                    ),
                    _hint(context, '2', '局域网自签证书的服务器，打开「允许自签证书」'),
                    _hint(context, '3', 'Emby 和 Jellyfin 都支持，不用区分'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加服务器'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String index, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              index,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
