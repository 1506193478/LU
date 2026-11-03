import 'dart:io';

import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/lu_media_vault.dart';
import 'package:XL/services/emby/lu_video_thumb.dart';

/// 资源库里"本地文件 / 本地私密 / 相册视频 / 网络链接 / WebDAV"的浏览页。
///
/// 本地模式列已经导入的条目；WebDAV 模式现连现列目录。点视频就用 LU 的
/// Emby 播放器播。
class EmbyVaultBrowsePage extends StatefulWidget {
  const EmbyVaultBrowsePage({
    super.key,
    required this.title,
    this.kind,
    this.server,
  });

  final String title;

  /// 本地模式：`local` / `private` / `gallery` / `link`。
  final String? kind;

  /// WebDAV 模式：给了 server 就走网盘。
  final LuVaultServer? server;

  @override
  State<EmbyVaultBrowsePage> createState() => _EmbyVaultBrowsePageState();
}

class _EmbyVaultBrowsePageState extends State<EmbyVaultBrowsePage> {
  bool _loading = false;
  String _error = '';
  List<WebDavEntry> _dav = const <WebDavEntry>[];
  String _davPath = '';

  LuWebDavClient? _client;

  bool get _isDav => widget.server != null;

  @override
  void initState() {
    super.initState();
    if (_isDav) {
      final s = widget.server!;
      _client = LuWebDavClient(
        baseUrl: s.baseUrl,
        user: s.user,
        password: s.password,
      );
      _list('');
    }
  }

  Future<void> _list(String path) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await client.list(path);
      if (!mounted) return;
      setState(() {
        _dav = items;
        _davPath = path;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '连不上这个网盘：${e.toString().split('\n').first}';
      });
    }
  }

  void _onDavTap(WebDavEntry entry) {
    final client = _client;
    if (client == null) return;
    if (entry.isDirectory) {
      _list(entry.href);
      return;
    }
    if (!_looksLikeVideo(entry.name)) {
      _toast('${entry.name} 不是视频文件');
      return;
    }
    luPlay(context, title: entry.name, url: client.playableUrl(entry));
  }

  bool _looksLikeVideo(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.mpg') ||
        lower.endsWith('.mpeg');
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: PvColors.page(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (_isDav)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () => _list(_davPath),
            ),
        ],
      ),
      body: _isDav ? _buildDav(dark) : _buildLocal(dark),
    );
  }

  Widget _buildLocal(bool dark) {
    final entries = LuMediaVault.instance.entriesOf(widget.kind ?? 'local');
    if (entries.isEmpty) {
      return _Empty(dark: dark, text: '还没有导入${widget.title}，回资源库点卡片导入');
    }
    // Emby 首页同款封面墙：竖版海报卡 + 标题，首帧缩略图做封面。
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisSpacing: 16,
        crossAxisSpacing: 11,
        childAspectRatio: 0.54,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _VaultCard(
          entry: e,
          dark: dark,
          onPlay: () => luPlay(context, title: e.name, url: e.source),
          onRemove: () async {
            await LuMediaVault.instance.removeEntry(e);
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  Widget _buildDav(bool dark) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: dark ? Colors.white54 : const Color(0xFF8A8A90),
            ),
          ),
        ),
      );
    }
    if (_dav.isEmpty) {
      return _Empty(dark: dark, text: '这个目录是空的');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
      itemCount: _dav.length + (_davPath.isEmpty ? 0 : 1),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: dark ? Colors.white10 : const Color(0xFFF0F0F3),
      ),
      itemBuilder: (context, i) {
        if (_davPath.isNotEmpty && i == 0) {
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.arrow_upward_rounded),
            title: const Text('上一级'),
            onTap: () {
              final parent = _davPath.replaceAll(RegExp(r'/$'), '');
              final cut = parent.lastIndexOf('/');
              _list(cut <= 0 ? '' : parent.substring(0, cut));
            },
          );
        }
        final entry = _dav[_davPath.isEmpty ? i : i - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.play_circle_outline_rounded,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          ),
          onTap: () => _onDavTap(entry),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: dark ? Colors.white38 : const Color(0xFF8A8A90),
          ),
        ),
      ),
    );
  }
}

/// 封面墙的一张卡：竖版海报 + 标题，右上角一枚小 × 负责删除。
///
/// 封面来自视频首帧（[LuVideoThumb]，临时目录缓存）；拿不到（非本地文件、
/// 桌面端、生成失败）就用渐变底 + 播放图标占位，不阻塞列表渲染。
class _VaultCard extends StatefulWidget {
  const _VaultCard({
    required this.entry,
    required this.dark,
    required this.onPlay,
    required this.onRemove,
  });

  final LuMediaEntry entry;
  final bool dark;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  State<_VaultCard> createState() => _VaultCardState();
}

class _VaultCardState extends State<_VaultCard> {
  bool _confirmRemove = false;

  String get _title {
    final n = widget.entry.name;
    final dot = n.lastIndexOf('.');
    if (dot > 0 && n.length - dot <= 5) return n.substring(0, dot);
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    return GestureDetector(
      onTap: widget.onPlay,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面。
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE9E7EA),
                    child: FutureBuilder<String?>(
                      future: LuVideoThumb.pathFor(widget.entry.source),
                      builder: (context, snap) {
                        final path = snap.data;
                        if (path == null) {
                          return Center(
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              size: 34,
                              color: dark ? Colors.white24 : const Color(0xFFB9B6BD),
                            ),
                          );
                        }
                        return Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        );
                      },
                    ),
                  ),
                ),
                // 删除 ×：点一下进入确认态，再点一下才真删，防误触。
                Positioned(
                  right: 5,
                  top: 5,
                  child: GestureDetector(
                    onTap: () {
                      if (_confirmRemove) {
                        widget.onRemove();
                      } else {
                        setState(() => _confirmRemove = true);
                        // 几秒不动就退出确认态。
                        Future.delayed(const Duration(seconds: 3), () {
                          if (mounted) setState(() => _confirmRemove = false);
                        });
                      }
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _confirmRemove
                            ? PvColors.red
                            : Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _confirmRemove ? Icons.check_rounded : Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              color: dark ? const Color(0xFFEDEDEF) : const Color(0xFF17171B),
            ),
          ),
        ],
      ),
    );
  }
}
