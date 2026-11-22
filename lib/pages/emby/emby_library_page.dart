import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/bean/widget/error_widget.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/theme/rex_design.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// 某个媒体库里的内容。
///
/// 和旧版的三点差别：
/// 1. 分页拉取（旧版写死 `Limit: 500`，大库一次拉几千条会卡住主线程）；
/// 2. 能排序（名称 / 入库时间 / 评分 / 时长）；
/// 3. 卡片带观看进度，不用点进去就知道看到哪。
class EmbyLibraryPage extends StatefulWidget {
  const EmbyLibraryPage({super.key, required this.library});

  final EmbyLibrary library;

  @override
  State<EmbyLibraryPage> createState() => _EmbyLibraryPageState();
}

enum _LibrarySort {
  name('名称', 'SortName', 'Ascending'),
  dateAdded('入库时间', 'DateCreated', 'Descending'),
  rating('评分', 'CommunityRating', 'Descending'),
  runtime('时长', 'Runtime', 'Descending');

  const _LibrarySort(this.label, this.sortBy, this.sortOrder);

  final String label;
  final String sortBy;
  final String sortOrder;
}

class _EmbyLibraryPageState extends State<EmbyLibraryPage> {
  static const int _pageSize = 60;

  final ScrollController _scrollController = ScrollController();
  final List<EmbyItem> _items = [];

  _LibrarySort _sort = _LibrarySort.name;

  // 筛选：观看状态三态（null=全部 / true=已看 / false=未看）、年份、类型。
  bool? _isPlayed;
  int? _year;
  String? _genre;
  List<int> _years = const [];
  List<String> _genres = const [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _error = '';
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
    _loadFacets();
  }

  /// 筛选项用一次轻量请求拿全，失败就当没有筛选项（不影响主列表）。
  Future<void> _loadFacets() async {
    try {
      final service = EmbyService.instance;
      await service.load();
      final server = service.activeServer;
      if (server == null) return;
      final client = service.clientFor(server);
      final results = await Future.wait([
        client.fetchYears(
          userId: server.userId,
          parentId: widget.library.id,
        ),
        client.fetchGenres(
          userId: server.userId,
          parentId: widget.library.id,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _years = results[0] as List<int>;
        _genres = results[1] as List<String>;
      });
    } catch (e) {
      KazumiLogger().w('Emby library: facets failed', error: e);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final position = _scrollController.position;
    // 提前两屏开始加载，滚到底时才不会卡一下。
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    final int seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = '';
      _items.clear();
      _hasMore = true;
    });
    try {
      final page = await _fetch(0);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      KazumiLogger().w('Emby library: failed to load', error: e);
      setState(() {
        _loading = false;
        _error = embyErrorMessage(e);
      });
    }
  }

  Future<void> _loadMore() async {
    final int seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_items.length);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      KazumiLogger().w('Emby library: failed to load more', error: e);
      setState(() => _loadingMore = false);
    }
  }

  Future<List<EmbyItem>> _fetch(int startIndex) async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) return const [];
    return service
        .clientFor(server)
        .fetchItemsPaged(
          userId: server.userId,
          parentId: widget.library.id,
          startIndex: startIndex,
          limit: _pageSize,
          sortBy: _sort.sortBy,
          sortOrder: _sort.sortOrder,
          isPlayed: _isPlayed,
          year: _year,
          genres: _genre == null ? const [] : <String>[_genre!],
        );
  }

  void _changeSort(_LibrarySort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _applyFilter();
  }

  void _applyFilter() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _reload();
  }

  bool get _hasFilter =>
      _isPlayed != null || _year != null || _genre != null;

  void _resetFilter() {
    if (!_hasFilter) return;
    setState(() {
      _isPlayed = null;
      _year = null;
      _genre = null;
    });
    _applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return EmbyPageShell(
      title: widget.library.name,
      subtitle: _items.isEmpty ? null : '共 ${_items.length} 部',
      actions: [
        PopupMenuButton<_LibrarySort>(
          tooltip: '排序',
          icon: Icon(Icons.sort_rounded, size: 20, color: p.inkPrimary),
          initialValue: _sort,
          color: p.surfaceRaised,
          onSelected: _changeSort,
          itemBuilder: (context) => [
            for (final sort in _LibrarySort.values)
              PopupMenuItem(
                value: sort,
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: sort == _sort
                          ? Icon(Icons.check_rounded, size: 16, color: p.accent)
                          : null,
                    ),
                    Text(
                      sort.label,
                      style: RexText.body.copyWith(color: p.inkPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        RexIconButton(
          icon: Icons.refresh_rounded,
          iconSize: 18,
          size: 36,
          glass: false,
          tooltip: '刷新',
          onTap: _reload,
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: KzLoading());
    }
    if (_error.isNotEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GeneralErrorWidget(
          title: '加载失败',
          errMsg: _error,
          onRetry: _reload,
        ),
      );
    }
    if (_items.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GeneralErrorWidget(
          title: '这个库是空的',
          errMsg: '换个库看看，或者先在 Emby 服务端往这个库里添加内容。',
          icon: Icons.inbox_rounded,
          onRetry: _reload,
        ),
      );
    }

    final server = EmbyService.instance.activeServer;
    if (server == null) return const SizedBox.shrink();

    return KzRefreshIndicator(
      onRefresh: _reload,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(context),
          Expanded(
            child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          embyIsDesktop(context) ? 24 : 16,
          12,
          embyIsDesktop(context) ? 24 : 16,
          28,
        ),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: embyIsDesktop(context) ? 160 : 124,
          mainAxisSpacing: embyIsDesktop(context) ? 18 : 14,
          crossAxisSpacing: embyIsDesktop(context) ? 14 : 10,
          childAspectRatio: 0.56,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          final item = _items[index];
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
            onTap: () {
              EmbyDetailPage.prefetch(item);
              context.pushNamed('/emby/detail', arguments: item);
            },
          );
        },
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选条：观看状态三态 + 年份 + 类型，横向可滚。
  /// 没有可选年份/类型时对应下拉不显示，避免空菜单。
  Widget _buildFilterBar(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final bool anyFacet = _years.isNotEmpty || _genres.isNotEmpty;
    if (!anyFacet && !_hasFilter) return const SizedBox.shrink();

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return KzPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? p.accent : p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? p.accent : p.hairlineStrong,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: RexText.caption.copyWith(
              color: selected ? p.accentInk : p.inkSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(
              label: '全部',
              selected: _isPlayed == null,
              onTap: () {
                setState(() => _isPlayed = null);
                _applyFilter();
              },
            ),
            const SizedBox(width: 8),
            chip(
              label: '未看',
              selected: _isPlayed == false,
              onTap: () {
                setState(() => _isPlayed = false);
                _applyFilter();
              },
            ),
            const SizedBox(width: 8),
            chip(
              label: '已看',
              selected: _isPlayed == true,
              onTap: () {
                setState(() => _isPlayed = true);
                _applyFilter();
              },
            ),
            if (_years.isNotEmpty) ...[
              const SizedBox(width: 8),
              PopupMenuButton<int?>(
                tooltip: '年份',
                color: p.surfaceRaised,
                initialValue: _year,
                onSelected: (value) {
                  setState(() => _year = value);
                  _applyFilter();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<int?>(
                    value: null,
                    child: Text('全部年份', style: RexText.body.copyWith(color: p.inkPrimary)),
                  ),
                  for (final year in _years.take(40))
                    PopupMenuItem<int?>(
                      value: year,
                      child: Text('$year', style: RexText.body.copyWith(color: p.inkPrimary)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _year == null ? p.surface : p.accent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _year == null ? p.hairlineStrong : p.accent,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _year == null ? '年份' : '$_year',
                        style: RexText.caption.copyWith(
                          color: _year == null ? p.inkSecondary : p.accentInk,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (_genres.isNotEmpty) ...[
              const SizedBox(width: 8),
              PopupMenuButton<String?>(
                tooltip: '类型',
                color: p.surfaceRaised,
                initialValue: _genre,
                onSelected: (value) {
                  setState(() => _genre = value);
                  _applyFilter();
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text('全部类型', style: RexText.body.copyWith(color: p.inkPrimary)),
                  ),
                  for (final genre in _genres.take(60))
                    PopupMenuItem<String?>(
                      value: genre,
                      child: Text(genre, style: RexText.body.copyWith(color: p.inkPrimary)),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _genre == null ? p.surface : p.accent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _genre == null ? p.hairlineStrong : p.accent,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _genre ?? '类型',
                        style: RexText.caption.copyWith(
                          color: _genre == null ? p.inkSecondary : p.accentInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            if (_hasFilter) ...[
              const SizedBox(width: 8),
              KzPressable(
                onTap: _resetFilter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Icon(Icons.close_rounded, size: 16, color: p.inkSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
