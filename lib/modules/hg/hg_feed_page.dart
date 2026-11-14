/// HG 短剧·竖滑刷视频页（抖音式）。
///
/// PageView 竖向滑动，当前页播放、上下邻页显示封面；右下角
/// 点赞/评论/收藏带真实数量（详情接口 counts 优先，卡片缓存兜底）。
/// 互动需登录（游客点开引导登录），浏览完全免登录。
library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_discover_page.dart';
import 'package:XL/modules/hg/hg_feed_player.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_sheets.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/modules/hg/hg_user_page.dart';
import 'package:XL/utils/motion.dart';

class HgFeedPage extends StatefulWidget {
  const HgFeedPage({super.key, this.startVideoId});

  /// 从搜索/详情跳进来时定位到指定视频。
  final int? startVideoId;

  @override
  State<HgFeedPage> createState() => _HgFeedPageState();
}

class _HgFeedPageState extends State<HgFeedPage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final Map<int, HgDetail> _details = {};
  final Map<String, String> _playUrls = {}; // '$id:$ep' → 上游地址
  final Map<int, int> _eps = {}; // id → 当前集

  final List<HgVideoCard> _cards = [];  int _feedPage = 0;
  bool _loadingFeed = false;
  bool _feedExhausted = false;
  int _index = 0;
  bool _initializing = true;
  /// 顶栏推入了发现页/用户页（true 时当前视频静音暂停）。
  bool _covered = false;
  /// App 整体退到后台（true 时暂停播放）。
  bool _appPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台时暂停当前视频；回前台恢复播放交给用户点击。
    if (state == AppLifecycleState.paused) {
      setState(() => _appPaused = true);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _appPaused = false);
    }
  }

  Future<void> _bootstrap() async {
    // 从外部指定视频进入：把该卡放到第一位，再拼推荐流。
    if (widget.startVideoId != null) {
      try {
        final detail = await HgApi.video(widget.startVideoId!);
        _details[detail.id] = detail;
        _cards.add(_cardFromDetail(detail));
      } catch (_) {
        // 起始视频拉不到就纯走推荐流。
      }
    }
    await _loadMore();
    if (mounted) setState(() => _initializing = false);
  }

  HgVideoCard _cardFromDetail(HgDetail d) => HgVideoCard(
        id: d.id,
        title: d.title,
        cover: d.cover,
        description: d.description,
        tags: d.tags,
        score: d.score,
        episodeCount: d.episodeCount,
        totalEpisodes: d.totalEpisodes,
        likeCount: d.likeCount,
        collectCount: d.collectCount,
        commentCount: d.commentCount,
        hot: d.hot,
        isFinished: d.isFinished,
        isOriginal: d.isOriginal,
        author: d.author,
      );

  Future<void> _loadMore() async {
    if (_loadingFeed || _feedExhausted) return;
    _loadingFeed = true;
    try {
      _feedPage++;
      final paged = await HgApi.feed(page: _feedPage, size: 10);
      if (!mounted) return;
      setState(() {
        _cards.addAll(paged.items);
        _feedExhausted =
            paged.pagination.page >= paged.pagination.pages ||
                paged.items.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _feedPage--);
    } finally {
      _loadingFeed = false;
    }
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (index >= _cards.length - 3) _loadMore();
    _preload(index);
  }

  /// 预取当前±1的详情和播放地址（HGhubX Feed 同款策略）。
  Future<void> _preload(int index) async {
    final ids = [
      for (final i in [index - 1, index, index + 1])
        if (i >= 0 && i < _cards.length) _cards[i].id,
    ];
    for (final id in ids) {
      if (!_details.containsKey(id)) {
        try {
          final d = await HgApi.video(id);
          _details[id] = d;
          if (mounted) setState(() {});
        } catch (_) {
          // 详情失败不影响播放（播放地址单独拉）。
        }
      }
    }
    if (ids.isNotEmpty) await _ensurePlayUrl(ids.last, _epFor(ids.last));
  }

  int _epFor(int id) {
    final d = _details[id];
    final maxEp = d != null && d.episodes.isNotEmpty ? d.episodes.length : 1;
    final current = _eps[id] ?? 1;
    return current.clamp(1, maxEp < 1 ? 1 : maxEp);
  }

  Future<String> _ensurePlayUrl(int id, int ep) async {
    final key = '$id:$ep';
    if (_playUrls.containsKey(key)) return _playUrls[key]!;
    try {
      final info = await HgApi.play(id, ep);
      _playUrls[key] = info.videoUrl;
      if (mounted) setState(() {});
      return info.videoUrl;
    } catch (_) {
      return '';
    }
  }

  /* ── 互动 ── */

  Future<void> _toggleLike(HgVideoCard card) async {
    if (!_requireLogin()) return;
    final detail = _details[card.id];
    final liked = detail?.liked ?? false;
    // 乐观更新。
    if (detail != null) {
      _details[card.id] = HgDetail(
        id: detail.id,
        title: detail.title,
        description: detail.description,
        cover: detail.cover,
        tags: detail.tags,
        score: detail.score,
        episodeCount: detail.episodeCount,
        totalEpisodes: detail.totalEpisodes,
        episodes: detail.episodes,
        likeCount: detail.likeCount + (liked ? -1 : 1),
        collectCount: detail.collectCount,
        commentCount: detail.commentCount,
        hot: detail.hot,
        author: detail.author,
        liked: !liked,
        collected: detail.collected,
        isFinished: detail.isFinished,
        isOriginal: detail.isOriginal,
      );
    }
    if (mounted) setState(() {});
    try {
      await HgApi.like(card.id, _epFor(card.id), !liked);
    } catch (e) {
      // 失败回滚。
      if (detail != null) {
        _details[card.id] = detail;
        if (mounted) setState(() {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _toggleCollect(HgVideoCard card) async {
    if (!_requireLogin()) return;
    final detail = _details[card.id];
    final collected = detail?.collected ?? false;
    if (detail != null) {
      _details[card.id] = HgDetail(
        id: detail.id,
        title: detail.title,
        description: detail.description,
        cover: detail.cover,
        tags: detail.tags,
        score: detail.score,
        episodeCount: detail.episodeCount,
        totalEpisodes: detail.totalEpisodes,
        episodes: detail.episodes,
        likeCount: detail.likeCount,
        collectCount: detail.collectCount + (collected ? -1 : 1),
        commentCount: detail.commentCount,
        hot: detail.hot,
        author: detail.author,
        liked: detail.liked,
        collected: !collected,
        isFinished: detail.isFinished,
        isOriginal: detail.isOriginal,
      );
    }
    if (mounted) setState(() {});
    try {
      await HgApi.collect(card.id, !collected);
    } catch (e) {
      if (detail != null) {
        _details[card.id] = detail;
        if (mounted) setState(() {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _openComments(HgVideoCard card) {
    final detail = _details[card.id];
    showHgCommentsSheet(
      context,
      videoId: card.id,
      ep: _epFor(card.id),
      initialCount: detail?.commentCount ?? card.commentCount,
      onCountChanged: (count) {
        final old = _details[card.id];
        if (old != null) {
          _details[card.id] = HgDetail(
            id: old.id,
            title: old.title,
            description: old.description,
            cover: old.cover,
            tags: old.tags,
            score: old.score,
            episodeCount: old.episodeCount,
            totalEpisodes: old.totalEpisodes,
            episodes: old.episodes,
            likeCount: old.likeCount,
            collectCount: old.collectCount,
            commentCount: count,
            hot: old.hot,
            author: old.author,
            liked: old.liked,
            collected: old.collected,
            isFinished: old.isFinished,
            isOriginal: old.isOriginal,
          );
          if (mounted) setState(() {});
        }
      },
    );
  }

  bool _requireLogin() {
    if (HgStore.session.loggedIn) return true;
    showHgLoginSheet(context).then((_) {
      // 弹层关闭（可能已登录成功）后刷新顶栏等 UI。
      if (mounted) setState(() {});
    });
    return false;
  }

  void _openUser(HgAuthor? author) async {
    if (author == null || author.id <= 0) return;
    setState(() => _covered = true);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HgUserPage(userId: author.id),
    ));
    if (mounted) setState(() => _covered = false);
  }

  void _openEpisodes(HgVideoCard card) {
    final detail = _details[card.id];
    if (detail == null || detail.episodes.isEmpty) return;
    showHgEpisodesSheet(
      context,
      detail: detail,
      currentEp: _epFor(card.id),
      onPick: (ep) {
        _eps[card.id] = ep;
        _playUrls.remove('${card.id}:$ep');
        setState(() {});
        _ensurePlayUrl(card.id, ep);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _GlassBtn(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                _GlassBtn(
                  icon: Icons.grid_view_rounded,
                  onTap: () async {
                    // 推入发现页期间暂停当前视频，返回后恢复。
                    setState(() => _covered = true);
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const HgDiscoverPage(),
                    ));
                    if (mounted) setState(() => _covered = false);
                  },
                ),
                const SizedBox(width: 8),
                _GlassBtn(
                  icon: HgStore.session.loggedIn
                      ? Icons.person_rounded
                      : Icons.login_rounded,
                  onTap: () async {
                    await showHgLoginSheet(context);
                    // 登录/退出成功后弹层关闭，刷新顶栏图标。
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: Colors.black,
      body: _initializing
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.4))
          : _cards.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.white54, size: 40),
                      const SizedBox(height: 10),
                      Text('加载失败，检查网络后下拉重试',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _initializing = true);
                          _bootstrap();
                        },
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: _cards.length,
                  onPageChanged: _onPageChanged,
                  controller: _pageController,
                  itemBuilder: (context, i) => _buildPage(i),
                ),
    );
  }

  Widget _buildPage(int index) {
    final card = _cards[index];
    final detail = _details[card.id];
    final ep = _epFor(card.id);
    // 页面级活跃：非当前页不播；页面被推入的发现页/用户页盖住、
    // 或 App 退到后台时也不播。
    final isActive = index == _index && !_covered && !_appPaused;

    return Stack(
      children: [
        Positioned.fill(
          child: index == _index
              ? FutureBuilder<String>(
                  // 播放地址异步取，取到前显示封面。
                  future: _ensurePlayUrl(card.id, ep),
                  builder: (context, snapshot) {
                    final url = snapshot.data ?? '';
                    if (url.isEmpty) {
                      return _coverLayer(card, detail);
                    }
                    // 播放器保持挂载：active=false 时暂停而不是卸载，
                    // 避免从发现页/用户页返回后重新加载、丢进度。
                    return HgFeedPlayer(upstreamUrl: url, active: isActive);
                  },
                )
              : _coverLayer(card, detail),
        ),
        // 右下角操作栏（真实计数）。
        Positioned(
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 86,
          child: _actionRail(card, detail),
        ),
        // 左下角信息区。
        Positioned(
          left: 16,
          right: 84,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          child: _infoColumn(card, detail, ep),
        ),
      ],
    );
  }

  Widget _coverLayer(HgVideoCard card, HgDetail? detail) {
    final cover = HgProxy.coverUrl(detail?.cover.isNotEmpty == true && detail!.cover.isNotEmpty
        ? detail.cover
        : card.cover);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover.isNotEmpty)
          Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) {
            return Container(color: const Color(0xFF14141A));
          })
        else
          Container(color: const Color(0xFF14141A)),
      ],
    );
  }

  /// 右下角竖排：心形+点赞数 / 气泡+评论数 / 星形+收藏数。
  /// 数量优先级：详情接口 counts > 卡片缓存，点赞收藏状态来自详情 interaction。
  Widget _actionRail(HgVideoCard card, HgDetail? detail) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _railButton(
          icon: detail?.liked == true
              ? Icons.favorite_rounded
              : Icons.favorite_outline_rounded,
          color: detail?.liked == true ? const Color(0xFFFF3B5C) : Colors.white,
          label: hgFmtCount(detail?.likeCount ?? card.likeCount),
          onTap: () => _toggleLike(card),
        ),
        const SizedBox(height: 18),
        _railButton(
          icon: Icons.mode_comment_outlined,
          color: Colors.white,
          label: hgFmtCount(detail?.commentCount ?? card.commentCount),
          onTap: () => _openComments(card),
        ),
        const SizedBox(height: 18),
        _railButton(
          icon: detail?.collected == true
              ? Icons.star_rounded
              : Icons.star_outline_rounded,
          color:
              detail?.collected == true ? const Color(0xFFFFB03A) : Colors.white,
          label: hgFmtCount(detail?.collectCount ?? card.collectCount),
          onTap: () => _toggleCollect(card),
        ),
        const SizedBox(height: 18),
        _railButton(
          icon: Icons.playlist_play_rounded,
          color: Colors.white,
          label: '选集',
          onTap: () => _openEpisodes(card),
        ),
      ],
    );
  }

  Widget _railButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    const labelStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
    );
    return GestureDetector(
      onTap: () {
        KazumiHaptics.select();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 34, shadows: const [
            Shadow(blurRadius: 6, color: Colors.black45),
          ]),
          const SizedBox(height: 3),
          Text(label, style: labelStyle),
        ],
      ),
    );
  }

  Widget _infoColumn(HgVideoCard card, HgDetail? detail, int ep) {
    final title = detail?.title.isNotEmpty == true && detail!.title.isNotEmpty
        ? detail.title
        : card.title;
    final desc = detail?.description ?? card.description;
    final tags = detail?.tags.isNotEmpty == true && detail!.tags.isNotEmpty
        ? detail.tags
        : card.tags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (detail?.author?.name.isNotEmpty == true) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openUser(detail.author),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 13, color: Colors.white.withValues(alpha: 0.75)),
                    const SizedBox(width: 3),
                    Text(detail!.author!.name,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (detail != null && detail.episodes.isNotEmpty)
              Text('第$ep集 / 共${detail.episodes.length}集',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.75))),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: tags.take(4).map((t) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85))),
                )).toList(),
          ),
        ],
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            desc,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.72),
              shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
            ),
          ),
        ],
      ],
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 40,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
