/// 用户主页：资料 + 统计（粉丝/关注/获赞/作品数）+ 作品网格 + 关注按钮。
///
/// 入口：Feed 底部作者行、帖子页作者、评论头像。

library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_module.dart';
import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_discover_page.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_feed_page.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/modules/hg/hg_sheets.dart';

class HgUserPage extends StatefulWidget {
  const HgUserPage({super.key, required this.userId});

  final int userId;

  @override
  State<HgUserPage> createState() => _HgUserPageState();
}

class _HgUserPageState extends State<HgUserPage> {
  HgUserProfile? _profile;
  final List<HgVideoCard> _videos = [];
  int _page = 0;
  int _pages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _following = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await HgApi.userProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
      await _loadPage(1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadPage(int page) async {
    if (page > _pages || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final paged = await HgApi.userVideos(widget.userId, page: page, size: 30);
      if (!mounted) return;
      setState(() {
        _page = page;
        _pages = paged.pagination.pages < 1 ? 1 : paged.pagination.pages;
        _videos.addAll(paged.items);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (!HgStore.session.loggedIn) {
      showHgLoginSheet(context).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    final on = !_following;
    setState(() => _following = on);
    try {
      await HgApi.follow(widget.userId, on);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !on);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.displayName ?? '用户'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _error != null && _profile == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                      _loadPage(_page + 1);
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _header(theme)),
                      const SliverToBoxAdapter(child: Divider(height: 1)),
                      SliverPadding(
                        padding: const EdgeInsets.all(12),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.62,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => HgVideoGridCard(
                              card: _videos[i],
                              onOpen: (card) {
                                hgPush<void>(context, 
                                      HgFeedPage(startVideoId: card.id),
                                );
                              },
                            ),
                            childCount: _videos.length,
                          ),
                        ),
                      ),
                      if (_loadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2.2)),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(ThemeData theme) {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    final avatar = HgProxy.coverUrl(p.avatar);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage:
                    avatar.isEmpty ? null : NetworkImage(avatar),
                child: avatar.isEmpty
                    ? Text(p.displayName.characters.first,
                        style: const TextStyle(fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (p.sign.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(p.sign,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _toggleFollow,
                child: Text(_following ? '已关注' : '关注'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(theme, hgFmtCount(p.followers), '粉丝'),
              _stat(theme, hgFmtCount(p.following), '关注'),
              _stat(theme, hgFmtCount(p.likeCount), '获赞'),
              _stat(theme, hgFmtCount(p.videoCount), '作品'),
              _stat(theme, hgFmtCount(p.postCount), '帖子'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
