import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/pages/emby/emby_ui_kit.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_watch_log.dart';
import 'package:XL/services/logging/logger.dart';

/// 按服务器打开一条播放记录。
///
/// 本地直链（相册 / 文件 / 网盘直链）直接重开；Emby 条目则先补一次元数据，
/// 再按「单集 → 整季」把剧集列表拉回来——播放记录里只存了 itemId，以前
/// 直接拿它拼一条假条目去播，结果播放器里连选集入口都没有。
Future<void> openEmbyWatchRecord(
  BuildContext context,
  EmbyWatchRecord record,
) async {
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
    KazumiDialog.showToast(message: '这台服务器已经不在列表里了');
    return;
  }

  final client = EmbyService.instance.clientFor(server);
  EmbyItem? meta;
  try {
    meta = await client.fetchItemMeta(
      userId: server.userId,
      itemId: record.itemId,
    );
  } catch (e) {
    KazumiLogger().w(
      'Emby records: failed to load item meta',
      error: e,
    );
  }

  // 续播位置：服务端 userData 最准；拿不到再退回本地记录里的进度。
  // 已经看完的不续播（从最后一秒开始没有意义）。
  Duration? resume;
  if (meta != null) {
    if (meta.isInProgress) resume = meta.resumePosition;
  } else if (!record.finished && record.positionMs > 0) {
    resume = Duration(milliseconds: record.positionMs);
  }

  var episodes = <EmbyItem>[
    meta ??
        EmbyItem(
          id: record.itemId,
          name: record.subtitle.isEmpty ? record.title : record.subtitle,
          type: 'Movie',
        ),
  ];
  var index = 0;

  // 单集：把整季拉回来，播放器里才有「选集 / 下一集」。
  final seriesId = meta?.seriesId;
  if (meta != null &&
      meta.isEpisode &&
      seriesId != null &&
      seriesId.isNotEmpty) {
    try {
      final all = await client.fetchEpisodes(
        userId: server.userId,
        seriesId: seriesId,
      );
      if (all.isNotEmpty) {
        episodes = all;
        final found = all.indexWhere((e) => e.id == meta!.id);
        index = found < 0 ? 0 : found;
      }
    } catch (e) {
      KazumiLogger().w(
        'Emby records: failed to load episodes',
        error: e,
      );
    }
  }

  if (!context.mounted) return;
  await context.pushNamed(
    '/emby/player',
    arguments: EmbyPlaybackLaunch(
      server: server,
      title: record.title,
      startAt: resume,
      episodes: episodes,
      initialIndex: index,
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
  bool _loadingServer = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _mergeServerResume();
  }

  void _reload() {
    setState(() => _records = EmbyWatchLog.instance.records);
  }

  /// 把服务端「继续观看」并进本地记录，解决多设备续播只在首页看得到的问题。
  ///
  /// 去重键和本地写入保持一致（`emby:{serverId}:{itemId}`）：
  ///   * 同 key：进度取服务端（最准、跨设备），时间取两者较新的；
  ///   * 服务端独有：其它设备看过的也加进来。
  /// 服务端拉取失败不影响本地记录展示。
  Future<void> _mergeServerResume() async {
    if (_loadingServer) return;
    _loadingServer = true;
    try {
      final service = EmbyService.instance;
      await service.load();
      final merged = <String, EmbyWatchRecord>{
        for (final r in EmbyWatchLog.instance.records) r.key: r,
      };
      for (final server in service.servers) {
        try {
          final items = await service
              .clientFor(server)
              .fetchResume(userId: server.userId, limit: 30);
          for (final item in items) {
            if (item.id.isEmpty) continue;
            final key = 'emby:${server.id}:${item.id}';
            final position = item.resumePosition;
            final total = item.runTime;
            if (position == null || total == null) continue;
            final serverRecord = EmbyWatchRecord(
              key: key,
              title: item.name,
              subtitle: item.cardSubtitle,
              itemId: item.id,
              serverId: server.id,
              serverName: server.name,
              positionMs: position.inMilliseconds,
              durationMs: total.inMilliseconds,
              // 服务端没有本地观看时间戳，用 0 让本地记录的时间优先。
              playedAt: 0,
            );
            final local = merged[key];
            if (local == null) {
              merged[key] = serverRecord;
            } else {
              // 进度用服务端；时间取更新的那个，保证排序不倒退。
              merged[key] = EmbyWatchRecord(
                key: key,
                title: local.title,
                subtitle: local.subtitle.isEmpty
                    ? serverRecord.subtitle
                    : local.subtitle,
                itemId: local.itemId,
                serverId: local.serverId,
                serverName: local.serverName,
                source: local.source,
                positionMs: serverRecord.positionMs,
                durationMs: serverRecord.durationMs,
                playedAt: local.playedAt > 0 ? local.playedAt : serverRecord.playedAt,
              );
            }
          }
        } catch (e) {
          KazumiLogger().w(
            'Emby records: server resume failed for ${server.name}',
            error: e,
          );
        }
      }
      if (!mounted) return;
      final list = merged.values.toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
      setState(() => _records = list);
    } finally {
      _loadingServer = false;
    }
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
    if (_records.isEmpty) {
      return const EmbyEmptyState(
        icon: Icons.history_rounded,
        title: '还没有播放记录',
        message: '播过一集之后，这里会按服务器分开记下来，点一下就能接着看。',
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
