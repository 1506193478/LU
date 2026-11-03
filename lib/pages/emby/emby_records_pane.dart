import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_watch_log.dart';

/// 按服务器打开一条播放记录。
///
/// 本地直链（相册 / 文件 / 网盘直链）直接重开；Emby 条目则回到播放器，
/// 服务端会从上次的 position 续播。
void openEmbyWatchRecord(BuildContext context, EmbyWatchRecord record) {
  if (record.source.isNotEmpty) {
    luPlay(context, title: record.title, url: record.source);
    return;
  }
  EmbyServer? server;
  for (final s in EmbyService.instance.servers) {
    if (s.id == record.serverId) {
      server = s;
      break;
    }
  }
  if (server == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('这台服务器已经不在列表里了'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
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

/// Emby「搜索 → 播放记录」页签。
///
/// 以前这一格是「网盘」，点开只有一句「暂未开放」。现在换成真正有用的东西：
/// 把 [EmbyWatchLog] 里的记录**按服务器分组**列出来，每张卡片带封面、时长、
/// 集号和进度条——多台服务器各有各的片，混在一起根本分不清哪部是哪台的。
class EmbyRecordsPane extends StatefulWidget {
  const EmbyRecordsPane({super.key});

  @override
  State<EmbyRecordsPane> createState() => _EmbyRecordsPaneState();
}

class _EmbyRecordsPaneState extends State<EmbyRecordsPane> {
  List<EmbyWatchRecord> _records = const <EmbyWatchRecord>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _records = EmbyWatchLog.instance.records);
  }

  /// 按服务器名分组，组内保持「最近播放在前」。
  List<MapEntry<String, List<EmbyWatchRecord>>> _grouped() {
    final map = <String, List<EmbyWatchRecord>>{};
    for (final r in _records) {
      final key = r.serverName.isNotEmpty
          ? r.serverName
          : (r.source.isNotEmpty ? '本地文件' : '未知服务器');
      map.putIfAbsent(key, () => <EmbyWatchRecord>[]).add(r);
    }
    return map.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    if (_records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 60,
                color: dark ? Colors.white24 : const Color(0xFFC9C9CF),
              ),
              const SizedBox(height: 14),
              Text(
                '还没有播放记录',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white54 : const Color(0xFF8A8A90),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '播过一集之后，这里会按服务器分开记下来，点一下就能接着看',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: dark ? Colors.white30 : const Color(0xFFA8A8AE),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final groups = _grouped();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
            child: Row(
              children: [
                Text(group.key, style: PvText.groupLabel(context)),
                const SizedBox(width: 8),
                Text(
                  '${group.value.length} 条',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: PvColors.ink3(context),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    for (final r in group.value) {
                      await EmbyWatchLog.instance.remove(r.key);
                    }
                    _reload();
                  },
                  child: Text(
                    '清空',
                    style: TextStyle(fontSize: 12.5, color: PvColors.blue),
                  ),
                ),
              ],
            ),
          ),
          for (final record in group.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecordCard(
                record: record,
                onTap: () => openEmbyWatchRecord(context, record),
                onRemove: () async {
                  await EmbyWatchLog.instance.remove(record.key);
                  _reload();
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.onTap,
    required this.onRemove,
  });

  final EmbyWatchRecord record;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    EmbyServer? server;
    for (final s in EmbyService.instance.servers) {
      if (s.id == record.serverId) {
        server = s;
        break;
      }
    }
    final imageUrl = (server != null && record.itemId.isNotEmpty)
        ? embyImageUrl(
            serverUrl: server.url,
            itemId: record.itemId,
            accessToken: server.accessToken,
            maxHeight: 240,
          )
        : '';

    // 副标题：优先用「S01E02 · 集名」这种能一眼定位的写法。
    final sub = <String>[
      if (record.subtitle.isNotEmpty) record.subtitle,
      if (record.durationMs > 0)
        _fmt(Duration(milliseconds: record.durationMs)),
    ].join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onRemove,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: PvColors.card(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 124,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isEmpty)
                      Container(
                        color: dark ? Colors.white12 : const Color(0xFFECECF1),
                        child: Icon(
                          Icons.movie_outlined,
                          size: 24,
                          color: dark
                              ? Colors.white24
                              : const Color(0xFFB4B4BA),
                        ),
                      )
                    else
                      EmbyImage(
                        url: imageUrl,
                        headers: embyAuthHeaders(server),
                      ),
                    if (record.durationMs > 0)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_fmt(Duration(milliseconds: record.positionMs))}'
                            ' / ${_fmt(Duration(milliseconds: record.durationMs))}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: PvColors.ink(context),
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: PvColors.ink3(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: record.progress <= 0
                          ? 0
                          : record.progress.clamp(0.0, 1.0),
                      minHeight: 3.5,
                      backgroundColor: dark
                          ? Colors.white12
                          : const Color(0xFFEDEDF2),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF3A5680),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    record.finished
                        ? '已看完'
                        : '已看 ${(record.progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: PvColors.ink3(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: PvColors.ink3(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
