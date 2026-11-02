import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_watch_log.dart';

/// 「我的 → 播放列表」：在 Emby 播放器里真正播过的影片记录。
///
/// 数据来源是本地播放记录本（[EmbyWatchLog]），不是服务端的播放列表接口，
/// 因为用户要的就是"播放过的影片记录"。
class EmbyPlaylistPage extends StatefulWidget {
  const EmbyPlaylistPage({super.key});

  @override
  State<EmbyPlaylistPage> createState() => _EmbyPlaylistPageState();
}

class _EmbyPlaylistPageState extends State<EmbyPlaylistPage> {
  List<EmbyWatchRecord> _records = const <EmbyWatchRecord>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _records = EmbyWatchLog.instance.records);
  }

  Future<void> _open(EmbyWatchRecord record) async {
    // 本地直链：直接重开。
    if (record.source.isNotEmpty) {
      luPlay(context, title: record.title, url: record.source);
      return;
    }
    final server = EmbyService.instance.servers
        .cast<EmbyServer?>()
        .firstWhere((s) => s?.id == record.serverId, orElse: () => null);
    if (server == null) {
      _toast('这台服务器已经不在列表里了');
      return;
    }
    if (!mounted) return;
    context.pushNamed(
      '/emby/player',
      arguments: EmbyPlaybackLaunch(
        server: server,
        title: record.title,
        episodes: [
          EmbyItem(
            id: record.itemId,
            name: record.subtitle.isEmpty ? record.title : record.subtitle,
            type: 'Movie',
          ),
        ],
      ),
    );
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
        title: const Text(
          '播放列表',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: () async {
                await EmbyWatchLog.instance.clear();
                if (mounted) _reload();
              },
            ),
        ],
      ),
      body: _records.isEmpty
          ? Center(
              child: Text(
                '还没有播放记录，播一部之后这里就有了',
                style: TextStyle(
                  fontSize: 13.5,
                  color: dark ? Colors.white38 : const Color(0xFF8A8A90),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
              itemCount: _records.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: dark ? Colors.white10 : const Color(0xFFF0F0F3),
              ),
              itemBuilder: (context, i) {
                final r = _records[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.subtitle.isNotEmpty)
                        Text(
                          r.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: dark
                                ? Colors.white38
                                : const Color(0xFF8A8A90),
                          ),
                        ),
                      const SizedBox(height: 3),
                      // 进度条：看过多少一目了然。
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: r.progress <= 0 ? null : r.progress,
                          minHeight: 3,
                          backgroundColor:
                              dark ? Colors.white12 : const Color(0xFFE8E8EE),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF3A5680),
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () async {
                      await EmbyWatchLog.instance.remove(r.key);
                      if (mounted) _reload();
                    },
                  ),
                  onTap: () => _open(r),
                );
              },
            ),
    );
  }
}
