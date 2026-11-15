/// HG「我的」页（HGhubX `src/pages/Profile.tsx` 照搬）。
///
/// 登录状态卡片 / 本地片库（收藏）/ 观看记录（含续播）/ 设置入口 /
/// 登出。游客展示登录引导。
library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_feed_page.dart';
import 'package:XL/modules/hg/hg_module.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/modules/hg/hg_settings_page.dart';
import 'package:XL/modules/hg/hg_sheets.dart';

class HgProfilePage extends StatefulWidget {
  const HgProfilePage({super.key});

  @override
  State<HgProfilePage> createState() => _HgProfilePageState();
}

class _HgProfilePageState extends State<HgProfilePage> {
  @override
  void initState() {
    super.initState();
    HgStore.prefs.changed.addListener(_onChanged);
    // 登录状态下顺手刷新一次资料（头像/昵称可能变了）。
    if (HgStore.session.loggedIn) {
      HgApi.me().catchError((_) => null);
    }
  }

  @override
  void dispose() {
    HgStore.prefs.changed.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    await HgApi.logout();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已退出登录')));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = HgStore.session;
    final prefs = HgStore.prefs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '设置',
            onPressed: () => hgPush<void>(context, const HgSettingsPage())
                .then((_) => _onChanged()),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 登录状态卡片。
          if (!session.loggedIn)
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.person_rounded,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              title: const Text('未登录'),
              subtitle: const Text('登录后可点赞 / 收藏 / 评论'),
              trailing: FilledButton(
                onPressed: () =>
                    showHgLoginSheet(context).then((_) => _onChanged()),
                child: const Text('登录'),
              ),
            )
          else
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundImage: session.user?.avatar.isNotEmpty == true
                    ? NetworkImage(HgProxy.coverUrl(session.user!.avatar))
                    : null,
                child: session.user?.avatar.isNotEmpty == true
                    ? null
                    : const Icon(Icons.person_rounded),
              ),
              title: Text(session.user?.username ?? '已登录'),
              subtitle: const Text('已登录'),
              trailing: TextButton(
                onPressed: _logout,
                child: const Text('退出'),
              ),
            ),
          const Divider(height: 1),

          // 本地片库（收藏）。
          ListTile(
            leading: const Icon(Icons.collections_bookmark_rounded),
            title: const Text('本地片库'),
            subtitle: Text('${prefs.favs.length} 部收藏'),
          ),
          if (prefs.favs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('在竖滑页点右栏「片库」收藏喜欢的剧',
                  style: TextStyle(fontSize: 12.5)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in prefs.favs.take(30))
                    ActionChip(
                      label: Text('ID $id'),
                      onPressed: () => hgPush<void>(
                          context, HgFeedPage(startVideoId: id)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // 观看记录。
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('观看记录'),
            subtitle: Text('${prefs.history.length} 条 · 点按续播'),
            trailing: prefs.history.isEmpty
                ? null
                : TextButton(
                    onPressed: () async {
                      await HgStore.prefs.clearHistory();
                    },
                    child: const Text('清空'),
                  ),
          ),
          ..._historyTiles(context, theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _historyTiles(BuildContext context, ThemeData theme) {
    final entries = HgStore.prefs.history.values.toList()
      ..sort((a, b) => ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0));
    return [
      for (final entry in entries.take(50))
        ListTile(
          dense: true,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: entry['cover']?.toString().isNotEmpty == true
                ? Image.network(
                    HgProxy.coverUrl(entry['cover'].toString()),
                    width: 56,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                        width: 56,
                        height: 34,
                        color: theme.colorScheme.surfaceContainerHighest),
                  )
                : Container(
                    width: 56,
                    height: 34,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie_rounded, size: 18),
                  ),
          ),
          title: Text(
            entry['title']?.toString().isNotEmpty == true
                ? entry['title'].toString()
                : '视频 #${entry['id']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            '第${entry['ep']}集 · ${_progressLabel(entry)}',
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => hgPush<void>(
            context,
            HgFeedPage(
                startVideoId: (entry['id'] as num?)?.toInt() ?? 0),
          ),
        ),
    ];
  }

  static String _progressLabel(Map<String, dynamic> entry) {
    final t = (entry['t'] as num?)?.toDouble() ?? 0;
    final dur = (entry['dur'] as num?)?.toDouble() ?? 0;
    if (dur <= 0) return '未记录';
    if (t >= dur - 3) return '已看完';
    final pct = (t / dur * 100).round();
    final m = t ~/ 60;
    final s = (t % 60).toInt();
    return '看到 $pct% · $m:${s.toString().padLeft(2, '0')}';
  }
}
