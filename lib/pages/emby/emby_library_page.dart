import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/widget/error_widget.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/theme/rex_design.dart';
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
    return service.clientFor(server).fetchItemsPaged(
          userId: server.userId,
          parentId: widget.library.id,
          startIndex: startIndex,
          limit: _pageSize,
          sortBy: _sort.sortBy,
          sortOrder: _sort.sortOrder,
        );
  }

  void _changeSort(_LibrarySort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _reload();
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
      return const Center(child: CircularProgressIndicator());
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

    return RefreshIndicator(
      onRefresh: _reload,
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
              itemId: item.id,
              accessToken: server.accessToken,
              maxHeight: 480,
              tag: item.primaryImageTag,
            ),
            headers: embyAuthHeaders(server),
            onTap: () => context.pushNamed('/emby/detail', arguments: item),
          );
        },
      ),
    );
  }
}
