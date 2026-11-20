import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_vault_browse_page.dart';
import 'package:XL/pages/emby/emby_vault_lock_page.dart';

/// SenPlayer「文件」页签：本地与网络文件入口聚合。
///
/// 每个入口复用工程里已有的 [EmbyVaultBrowsePage]，不重复造浏览逻辑；
/// 「私密空间」进入前先过锁，和默认首页的落地逻辑保持一致。
class EmbyFilesPane extends StatelessWidget {
  const EmbyFilesPane({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <_FileEntry>[
      const _FileEntry(
        'local',
        '本地文件',
        '浏览设备上的视频文件',
        Icons.folder_open_rounded,
        Color(0xFF007AFF),
      ),
      const _FileEntry(
        'gallery',
        '相册视频',
        '读取系统相册里的视频',
        Icons.photo_library_rounded,
        Color(0xFF34C759),
      ),
      const _FileEntry(
        'private',
        '私密空间',
        '加密保存的私密视频',
        Icons.lock_rounded,
        Color(0xFF8E8E93),
      ),
      const _FileEntry(
        'link',
        '网络链接',
        '直接播放一条网络地址',
        Icons.link_rounded,
        Color(0xFFFF9500),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                '文件',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: PvColors.ink(context),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              delegate: SliverChildListDelegate(
                <Widget>[
                  for (final _FileEntry e in entries)
                    _FileCard(entry: e, onTap: () => _open(context, e)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, _FileEntry e) async {
    if (e.kind == 'private') {
      final bool unlocked =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => const EmbyVaultLockPage(),
            ),
          ) ??
          false;
      if (!unlocked || !context.mounted) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmbyVaultBrowsePage(title: e.title, kind: e.kind),
      ),
    );
  }
}

class _FileEntry {
  const _FileEntry(this.kind, this.title, this.subtitle, this.icon, this.color);

  final String kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.entry, required this.onTap});

  final _FileEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PvColors.card(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(entry.icon, color: entry.color, size: 22),
              ),
              const Spacer(),
              Text(
                entry.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: PvColors.ink3(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
