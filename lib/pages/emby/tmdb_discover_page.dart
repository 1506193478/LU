/// TMDB 发现页：客户端直连 TMDB 浏览热门影片 / 剧集。
///
/// 零配置可用（内置公共 Key + 自动线路，见 [TmdbPrefs]）。点海报会在
/// 当前 Emby 媒体库里搜同名条目——有就直接跳详情，没有提示没收录。
library;
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/request/clients/tmdb_client.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/theme/ios_interaction.dart' show KzPressable;

class TmdbDiscoverPage extends StatefulWidget {
  const TmdbDiscoverPage({super.key});

  @override
  State<TmdbDiscoverPage> createState() => _TmdbDiscoverPageState();
}

class _TmdbDiscoverPageState extends State<TmdbDiscoverPage> {
  String _kind = 'movie'; // movie | tv
  String _category = 'trending'; // trending | popular | top

  late final ScrollController _scroll;
  final TmdbClient _tmdb = TmdbClient();

  final List<EmbyRemoteSearchResult> _items = <EmbyRemoteSearchResult>[];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _firstLoadDone = false;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels <
        _scroll.position.maxScrollExtent - 600) {
      return;
    }
    _loadMore();
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _page = 1;
    });
    try {
      final results = await _tmdb.discover(
        kind: _kind,
        category: _category,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(results);
        _loading = false;
        _firstLoadDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _firstLoadDone = true;
        _error = 'TMDB 连不上：到「我的 → TMDB 配置」点「自动选择线路」换一条';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_firstLoadDone || _error != null) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final results = await _tmdb.discover(
        kind: _kind,
        category: _category,
        page: next,
      );
      if (!mounted) return;
      setState(() {
        _page = next;
        _items.addAll(results);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 点海报：在当前媒体库搜同名条目，有就跳详情。
  Future<void> _openInEmby(EmbyRemoteSearchResult result) async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) {
      KazumiDialog.showToast(message: '还没有连接媒体库');
      return;
    }
    KazumiDialog.showToast(message: '正在「${server.name}」里找《${result.name}》…');
    try {
      final client = service.clientFor(server);
      final hits = await client.search(userId: server.userId, keyword: result.name);
      if (!mounted) return;
      if (hits.isEmpty) {
        KazumiDialog.showToast(message: '媒体库没有收录《${result.name}》');
        return;
      }
      // 标题完全一致（忽略大小写）的优先，否则取第一条。
      EmbyItem match = hits.first;
      final lower = result.name.toLowerCase().trim();
      for (final hit in hits) {
        if (hit.name.toLowerCase().trim() == lower) {
          match = hit;
          break;
        }
      }
      EmbyDetailPage.prefetch(match);
      context.pushNamed('/emby/detail', arguments: match);
    } catch (_) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '搜索媒体库失败，检查服务器连接');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '发现页',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _FilterBar(
            kind: _kind,
            category: _category,
            onChanged: (kind, category) {
              if (kind == _kind && category == _category) return;
              setState(() {
                _kind = kind;
                _category = category;
              });
              unawaited(_reload());
            },
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: PvColors.ink3(context)),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: PvColors.ink2(context)),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final double width = MediaQuery.sizeOf(context).width;
    final int columns = width > 700
        ? (width > 1100 ? 6 : 4)
        : 3;
    final double gap = 12;
    final double cardWidth =
        (width - gap * (columns - 1) - 28) / columns;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        // 海报 2:3 + 底部一行信息。
        childAspectRatio: cardWidth / (cardWidth * 1.5 + 38),
      ),
      itemCount: _items.length + (_loadingMore ? columns : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = _items[index];
        return _DiscoverCard(
          item: item,
          onTap: () => unawaited(_openInEmby(item)),
        );
      },
    );
  }
}

/// 顶部筛选栏：电影 / 剧集 分段 + 热门/流行/高分 chips。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.kind,
    required this.category,
    required this.onChanged,
  });

  final String kind;
  final String category;
  final void Function(String kind, String category) onChanged;

  static const Map<String, String> _categoryLabels = <String, String>{
    'trending': '本周热门',
    'popular': '流行',
    'top': '高分',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: CupertinoSlidingSegmentedControl<String>(
                groupValue: kind,
                onValueChanged: (v) {
                  if (v != null) onChanged(v, category);
                },
                children: const <String, Widget>{
                  'movie': Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('电影', style: TextStyle(fontSize: 13)),
                  ),
                  'tv': Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('剧集', style: TextStyle(fontSize: 13)),
                  ),
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          for (final entry in _categoryLabels.entries) ...[
            KzPressable(
              onTap: () => onChanged(kind, entry.key),
              pressedOpacity: 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: category == entry.key
                      ? PvColors.blue
                      : PvColors.card(context),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: category == entry.key
                        ? Colors.white
                        : PvColors.ink2(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// 海报卡：TMDB 海报 + 中文名 + 年份/评分。
class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.item, required this.onTap});

  final EmbyRemoteSearchResult item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.imageUrl.isEmpty
                  ? Container(
                      color: PvColors.card(context),
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_outlined,
                          size: 28, color: PvColors.ink3(context)),
                    )
                  : EmbyImage(url: item.imageUrl),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: PvColors.ink(context),
            ),
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              if (item.year != null)
                Text(
                  '${item.year}',
                  style: TextStyle(
                    fontSize: 11,
                    color: PvColors.ink3(context),
                  ),
                ),
              const Spacer(),
              Icon(Icons.star_rounded, size: 13, color: PvColors.green),
              const SizedBox(width: 2),
              Text(
                (item.raw['vote_average'] as num?)?.toStringAsFixed(1) ?? '-',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink2(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
