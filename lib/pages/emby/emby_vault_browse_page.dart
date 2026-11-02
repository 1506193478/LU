import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/lu_media_vault.dart';

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
    luPlay(
      context,
      title: entry.name,
      url: client.playableUrl(entry),
    );
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: dark ? Colors.white10 : const Color(0xFFF0F0F3),
      ),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.play_circle_outline_rounded),
          title: Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            e.source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: dark ? Colors.white38 : const Color(0xFF8A8A90),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () async {
              await LuMediaVault.instance.removeEntry(e);
              if (mounted) setState(() {});
            },
          ),
          onTap: () => luPlay(context, title: e.name, url: e.source),
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
