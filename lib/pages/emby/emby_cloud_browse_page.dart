import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/lu_cloud_drive.dart';

/// 网盘浏览页：一层层点进去，点视频直接用 LU 播放器起播。
class LuCloudBrowsePage extends StatefulWidget {
  const LuCloudBrowsePage({super.key, required this.account});

  final LuCloudAccount account;

  @override
  State<LuCloudBrowsePage> createState() => _LuCloudBrowsePageState();
}

class _LuCloudBrowsePageState extends State<LuCloudBrowsePage> {
  final List<(String, String)> _stack = [('', '根目录')];
  List<LuCloudFile> _files = const [];
  bool _loading = true;
  String _error = '';
  String _opening = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await LuCloudApi.list(
        widget.account,
        parentId: _stack.last.$1,
      );
      if (!mounted) return;
      setState(() {
        _files = list
          ..sort((a, b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.compareTo(b.name);
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is LuCloudException ? e.message : '$e';
      });
    }
  }

  Future<void> _open(LuCloudFile file) async {
    if (file.isDir) {
      setState(() => _stack.add((file.id, file.name)));
      await _load();
      return;
    }
    if (!file.looksLikeVideo) {
      _toast('这个文件不是视频');
      return;
    }
    setState(() => _opening = file.id);
    try {
      final url = await LuCloudApi.playUrl(widget.account, file);
      if (!mounted) return;
      setState(() => _opening = '');
      if (url == null || url.isEmpty) {
        _toast('拿不到直链，可能是会员/权限限制');
        return;
      }
      luPlay(context, title: file.name, url: url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = '');
      _toast(e is LuCloudException ? e.message : '$e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
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
          icon: Icon(
            _stack.length > 1
                ? Icons.arrow_back_ios_new_rounded
                : Icons.close_rounded,
            size: 19,
          ),
          onPressed: () {
            if (_stack.length > 1) {
              setState(() => _stack.removeLast());
              _load();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: Text(
          _stack.last.$2,
          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(dark),
    );
  }

  Widget _buildBody(bool dark) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 46,
                  color: dark ? Colors.white24 : const Color(0xFFC9C9CF)),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: dark ? Colors.white54 : const Color(0xFF8A8A8E),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_files.isEmpty) {
      return Center(
        child: Text(
          '这个文件夹是空的',
          style: TextStyle(
            fontSize: 13.5,
            color: dark ? Colors.white38 : const Color(0xFF9A9AA0),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
      itemCount: _files.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        indent: 52,
        color: dark ? Colors.white12 : const Color(0xFFF0F0F3),
      ),
      itemBuilder: (context, i) {
        final f = _files[i];
        final busy = _opening == f.id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            f.isDir
                ? Icons.folder_rounded
                : (f.looksLikeVideo
                    ? Icons.play_circle_outline_rounded
                    : Icons.insert_drive_file_outlined),
            color: f.isDir
                ? const Color(0xFFFFB321)
                : (f.looksLikeVideo
                    ? const Color(0xFF2FBF5C)
                    : (dark ? Colors.white38 : const Color(0xFF9A9AA0))),
            size: 26,
          ),
          title: Text(
            f.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14.5),
          ),
          subtitle: f.sizeLabel.isEmpty
              ? null
              : Text(
                  f.sizeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: dark ? Colors.white38 : const Color(0xFF9A9AA0),
                  ),
                ),
          trailing: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: () => _open(f),
        );
      },
    );
  }
}
