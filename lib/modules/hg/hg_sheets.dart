/// HG 弹层集合：评论 / 选集 / 登录注册。
library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_module.dart';
import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/modules/hg/hg_user_page.dart';

/// 评论弹层。返回时通过 [onCountChanged] 把最新评论数回调给 Feed。
Future<void> showHgCommentsSheet(
  BuildContext context, {
  required int videoId,
  required int ep,
  required int initialCount,
  ValueChanged<int>? onCountChanged,
  /// 非 null 时按「吃瓜帖评论」加载（上游只读，无发送接口），
  /// 输入行整体隐藏。
  int? postId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HgCommentsSheet(
      videoId: videoId,
      ep: ep,
      initialCount: initialCount,
      onCountChanged: onCountChanged,
      postId: postId,
    ),
  );
}

class _HgCommentsSheet extends StatefulWidget {
  const _HgCommentsSheet({
    required this.videoId,
    required this.ep,
    required this.initialCount,
    this.onCountChanged,
    this.postId,
  });

  final int videoId;
  final int ep;
  final int initialCount;
  final ValueChanged<int>? onCountChanged;
  final int? postId;

  @override
  State<_HgCommentsSheet> createState() => _HgCommentsSheetState();
}

class _HgCommentsSheetState extends State<_HgCommentsSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<HgComment> _items = [];
  HgPagination _pagination = const HgPagination();
  int _count = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _load(1);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 400 &&
          _pagination.page < _pagination.pages &&
          !_loading) {
        _load(_pagination.page + 1);
      }
    });
  }

  Future<void> _load(int page) async {
    if (page == 1) setState(() => _loading = true);
    try {
      final pageData = widget.postId != null
          ? await HgApi.postComments(widget.postId!, page: page)
          : await HgApi.comments(widget.videoId, widget.ep, page: page);
      if (!mounted) return;
      setState(() {
        _items = page == 1
            ? pageData.items
            : [..._items, ...pageData.items];
        _pagination = pageData.pagination;
        if (page == 1 && pageData.items.isNotEmpty) {
          // 上游评论数以接口为准（比卡片缓存准）。
          _count = pageData.pagination.total;
          widget.onCountChanged?.call(_count);
        }
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await HgApi.commentSend(widget.videoId, widget.ep, text);
      _input.clear();
      await _load(1);
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Row(
                children: [
                  Text('评论',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(hgFmtCount(_count),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _error != null && _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : _loading && _items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _items.length,
                          itemBuilder: (context, i) => _commentTile(_items[i]),
                        ),
            ),
            if (widget.postId == null) ...[
              const Divider(height: 1),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: HgStore.session.loggedIn
                                ? '说点什么…'
                                : '登录后才能发评论',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: HgStore.session.loggedIn ? _send : _goLogin,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _goLogin() {
    showHgLoginSheet(context).then((_) {
      // 登录成功返回后刷新输入框提示与发送按钮状态。
      if (mounted) setState(() {});
    });
  }

  Widget _commentTile(HgComment c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (c.userId > 0) {
                hgPush<void>(context,  HgUserPage(userId: c.userId),
                );
              }
            },
            child: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: c.avatar.isEmpty
                  ? null
                  : NetworkImage(HgProxy.coverUrl(c.avatar)),
              child: c.avatar.isEmpty
                  ? Text(
                      c.nickname.isEmpty ? '?' : c.nickname.characters.first,
                      style: const TextStyle(fontSize: 13),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(c.nickname,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    if (c.isPinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.push_pin_rounded,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const Spacer(),
                    Text(c.time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
                const SizedBox(height: 3),
                Text(c.text, style: theme.textTheme.bodyMedium),
                if (c.replyList.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final reply in c.replyList.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${reply.nickname}：',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: theme
                                            .colorScheme.onSurfaceVariant),
                                  ),
                                  TextSpan(
                                      text: reply.text,
                                      style: const TextStyle(fontSize: 12.5)),
                                ],
                              ),
                            ),
                          ),
                      ],
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
}

/// 选集弹层。
Future<void> showHgEpisodesSheet(
  BuildContext context, {
  required HgDetail detail,
  required int currentEp,
  required void Function(int ep) onPick,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${detail.title} · 共 ${detail.episodes.length} 集',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 92,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.6,
                ),
                itemCount: detail.episodes.length,
                itemBuilder: (context, i) {
                  final ep = detail.episodes[i];
                  final selected = ep.epNum == currentEp;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.pop(context);
                      onPick(ep.epNum);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Text(
                        ep.title.isEmpty ? '第${ep.epNum}集' : ep.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 登录 / 注册弹层。成功后自动关闭并回调。
Future<void> showHgLoginSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _HgLoginSheet(),
  );
}

class _HgLoginSheet extends StatefulWidget {
  const _HgLoginSheet();

  @override
  State<_HgLoginSheet> createState() => _HgLoginSheetState();
}

class _HgLoginSheetState extends State<_HgLoginSheet> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await HgApi.register(username, password, _email.text.trim());
      } else {
        await HgApi.login(username, password);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('登录')),
                ButtonSegment(value: true, label: Text('注册')),
              ],
              selected: {_register},
              onSelectionChanged: (s) => setState(() => _register = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            if (_register) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: '邮箱（选填）',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_register ? '注册并登录' : '登录'),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('游客模式继续浏览'),
              ),
            ),
            SafeArea(top: false, child: SizedBox(height: 4)),
          ],
        ),
      ),
    );
  }
}
