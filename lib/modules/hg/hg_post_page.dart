/// 吃瓜帖详情页：视频播放 + 点赞/收藏/评论（真实计数）。
///
/// 视频地址由 playback 接口下发（详情里 video_url 恒空），可能多段——
/// 多段时显示分页按钮。评论上游只读，复用评论弹层的 postId 模式。

library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_module.dart';
import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_feed_player.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/modules/hg/hg_sheets.dart';
import 'package:XL/modules/hg/hg_user_page.dart';
import 'package:XL/bean/dialog/dialog.dart';

class HgPostPage extends StatefulWidget {
  const HgPostPage({super.key, required this.postId, this.post});

  final int postId;
  final HgPost? post;

  @override
  State<HgPostPage> createState() => _HgPostPageState();
}

class _HgPostPageState extends State<HgPostPage> {
  HgPost? _post;
  List<String> _videoUrls = [];
  int _videoIndex = 0;
  bool _loading = true;
  bool _liked = false;
  bool _collected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _liked = false;
    _collected = false;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await HgApi.post(widget.postId);
      final urls = await HgApi.postPlayback(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = detail;
        _videoUrls = urls;
        _videoIndex = 0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool get _requireLogin {
    if (HgStore.session.loggedIn) return true;
    showHgLoginSheet(context).then((_) {
      if (mounted) setState(() {});
    });
    return false;
  }

  Future<void> _toggleLike() async {
    if (!_requireLogin || _post == null) return;
    final on = !_liked;
    setState(() {
      _liked = on;
      _post = _replaceCounts(_post!, like: on ? _post!.likeCount + 1 : _post!.likeCount - 1);
    });
    try {
      await HgApi.postLike(_post!.id, on);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !on;
        _post = _replaceCounts(_post!, like: on ? _post!.likeCount - 1 : _post!.likeCount + 1);
      });
      KazumiDialog.showError(message: e.toString());
    }
  }

  Future<void> _toggleCollect() async {
    if (!_requireLogin || _post == null) return;
    final on = !_collected;
    setState(() {
      _collected = on;
      _post = _replaceCounts(_post!, collect: on ? _post!.collectCount + 1 : _post!.collectCount - 1);
    });
    try {
      await HgApi.postCollect(_post!.id, on);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _collected = !on;
        _post = _replaceCounts(_post!, collect: on ? _post!.collectCount - 1 : _post!.collectCount + 1);
      });
      KazumiDialog.showError(message: e.toString());
    }
  }

  HgPost _replaceCounts(
    HgPost old, {
    int? like,
    int? collect,
    int? comment,
  }) {
    return HgPost(
      id: old.id,
      title: old.title,
      desc: old.desc,
      content: old.content,
      cover: old.cover,
      tags: old.tags,
      hot: old.hot,
      videoUrl: old.videoUrl,
      videoId: old.videoId,
      author: old.author,
      likeCount: like ?? old.likeCount,
      commentCount: comment ?? old.commentCount,
      collectCount: collect ?? old.collectCount,
      shareCount: old.shareCount,
      createdAt: old.createdAt,
    );
  }

  void _openComments() {
    showHgCommentsSheet(
      context,
      videoId: 0,
      ep: 0,
      initialCount: _post?.commentCount ?? 0,
      postId: widget.postId,
      onCountChanged: (c) {
        if (mounted && _post != null && c != _post!.commentCount) {
          setState(() => _post = _replaceCounts(_post!, comment: c));
        }
      },
    );
  }

  void _openUser(HgAuthor? author) {
    if (author == null || author.id <= 0) return;
    hgPush<void>(context,  HgUserPage(userId: author.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(post?.title ?? '吃瓜帖',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading && post == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _error != null && post == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: _videoUrls.isNotEmpty
                          ? HgFeedPlayer(upstreamUrl: _videoUrls[_videoIndex])
                          : _coverOrEmpty(post),
                    ),
                    // 多段视频切换（playback 可下发多段）。
                    if (_videoUrls.length > 1)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < _videoUrls.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ChoiceChip(
                                    label: Text('段${i + 1}'),
                                    selected: _videoIndex == i,
                                    onSelected: (_) =>
                                        setState(() => _videoIndex = i),
                                    visualDensity: VisualDensity.compact,
                                    labelStyle:
                                        const TextStyle(color: Colors.white),
                                    selectedColor: Colors.white24,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    // 右下角操作栏：心形/气泡/星形 + 真实计数。
                    Positioned(
                      right: 14,
                      bottom: 24,
                      child: Column(
                        children: [
                          _railButton(
                            icon: _liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_outline_rounded,
                            color: _liked ? const Color(0xFFFF4D67) : Colors.white,
                            label: hgFmtCount(post?.likeCount),
                            onTap: _toggleLike,
                          ),
                          const SizedBox(height: 16),
                          _railButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            color: Colors.white,
                            label: hgFmtCount(post?.commentCount),
                            onTap: _openComments,
                          ),
                          const SizedBox(height: 16),
                          _railButton(
                            icon: _collected
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: _collected
                                ? const Color(0xFFFFC53A)
                                : Colors.white,
                            label: hgFmtCount(post?.collectCount),
                            onTap: _toggleCollect,
                          ),
                        ],
                      ),
                    ),
                    // 底部信息层。
                    Positioned(
                      left: 16,
                      right: 72,
                      bottom: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _openUser(post?.author),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  backgroundImage:
                                      (post?.author?.avatar.isEmpty ?? true)
                                          ? null
                                          : NetworkImage(HgProxy.coverUrl(
                                              post!.author!.avatar)),
                                  child: (post?.author?.avatar.isEmpty ?? true)
                                      ? const Icon(Icons.person_rounded,
                                          size: 14, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Text(post?.author?.name ?? '',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          if (post?.content.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              post!.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _coverOrEmpty(HgPost? post) {
    final cover = HgProxy.coverUrl(post?.cover ?? '');
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (cover.isNotEmpty)
          Image.network(cover, fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink()),
      ],
    );
  }

  Widget _railButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        IconButton.filledTonal(
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: Colors.white24),
          icon: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
