import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// 「我的 → 资源模块 → 收藏」：服务端侧 `Filters=IsFavorite` 的条目。
///
/// 以前这一行只弹一句「收藏暂未开放」。现在读的是 Emby 自己的收藏标记，
/// 跟网页端 / 别的客户端完全同步——详情页那颗心点亮之后，这里就有一条。
class EmbyFavoritesPage extends StatefulWidget {
  const EmbyFavoritesPage({super.key});

  @override
  State<EmbyFavoritesPage> createState() => _EmbyFavoritesPageState();
}

class _EmbyFavoritesPageState extends State<EmbyFavoritesPage> {
  List<EmbyItem> _items = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final server = EmbyService.instance.activeServer;
    if (server == null) {
      setState(() {
        _loading = false;
        _error = '还没有连接 Emby 服务器';
      });
      return;
    }
    if (mounted) {
      setState(() {
        _loading = _items.isEmpty;
        _error = '';
      });
    }
    try {
      final items = await EmbyService.instance
          .clientFor(server)
          .fetchFavorites(userId: server.userId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      KazumiLogger().w('Emby favorites: load failed', error: e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _removeFavorite(EmbyItem item) async {
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    final confirmed = await showKzConfirm(
      context: context,
      title: '取消收藏',
      message: '把《${item.name}》从收藏里移掉？',
      cancelLabel: '留着',
      confirmLabel: '取消收藏',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await EmbyService.instance
          .clientFor(server)
          .setFavorite(item.id, false, userId: server.userId);
      if (!mounted) return;
      setState(
        () => _items = _items
            .where((e) => e.id != item.id)
            .toList(growable: false),
      );
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '取消失败：$e');
    }
  }

  Future<void> _open(EmbyItem item) async {
    EmbyDetailPage.prefetch(item);
    await context.pushNamed('/emby/detail', arguments: item);
    // 详情页里可能把心点掉了，回来重新拉一次，别让已经取消的还留在这儿。
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final server = EmbyService.instance.activeServer;
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: PvColors.page(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: PvColors.ink(context),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '收藏',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: PvColors.ink(context),
          ),
        ),
        centerTitle: true,
        actions: [
          if (server != null)
            IconButton(
              tooltip: '刷新',
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: PvColors.ink2(context),
              ),
              onPressed: _load,
            ),
        ],
      ),
      body: _body(server),
    );
  }

  Widget _body(EmbyServer? server) {
    if (_loading) {
      return const Center(child: KzLoading());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '收藏没能拉下来',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: PvColors.ink3(context),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (server == null) {
      return Center(
        child: Text(
          '还没有连接 Emby 服务器',
          style: TextStyle(fontSize: 13.5, color: PvColors.ink3(context)),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border_rounded,
                size: 40,
                color: PvColors.chev(context),
              ),
              const SizedBox(height: 12),
              Text(
                '还没有收藏',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在影片详情页点一下那颗心，这里就会出现',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: PvColors.ink3(context)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 2, 17, 4),
          child: Row(
            children: [
              Text('${_items.length} 部', style: PvText.count(context)),
              const Spacer(),
              Text(
                '长按海报取消收藏',
                style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
              ),
            ],
          ),
        ),
        Expanded(
          child: KzRefreshIndicator(
            onRefresh: _load,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 132,
                mainAxisSpacing: 16,
                crossAxisSpacing: 11,
                childAspectRatio: 0.54,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
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
                  onTap: () => _open(item),
                  onLongPress: () => _removeFavorite(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
