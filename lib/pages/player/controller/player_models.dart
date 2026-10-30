import 'package:flutter/material.dart';

import 'package:XL/services/video_source/video_source_format.dart';

class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final VideoSourceFormat videoSourceFormat;
  final int bangumiId;
  final String pluginName;
  final int episode;
  final int danmakuEpisodeNumber;
  final String pageUrl;

  /// Parsed title number online, downloaded episode number offline.
  final int? sortNumber;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final String episodeTitle;
  final String referer;
  final int currentRoad;
  final String? coverUrl;
  final String? bangumiName;

  /// 番剧原名（日文/英文），B 站弹幕源按原名二次匹配时用得上。
  final String? bangumiOriginalName;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.bangumiId,
    required this.pluginName,
    required this.episode,
    required this.danmakuEpisodeNumber,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.episodeTitle,
    required this.referer,
    required this.currentRoad,
    this.videoSourceFormat = VideoSourceFormat.auto,
    this.pageUrl = '',
    this.sortNumber,
    this.coverUrl,
    this.bangumiName,
    this.bangumiOriginalName,
  });
}

class SyncPlayChatMessage {
  final String username;
  final String message;
  final bool fromRemote;
  final DateTime time;

  /// 这条是「快捷反应」：`message` 里只有一个 emoji。
  ///
  /// 聊天列表里画成一个没有气泡的大表情，播放器里飘成大字弹幕 —— 两种呈现
  /// 都不该出现「某某说」这种正文排版。
  final bool isReaction;

  SyncPlayChatMessage({
    required this.username,
    required this.message,
    this.fromRemote = true,
    this.isReaction = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

/// 一起看里别人的一个动作，用来在画面上弹一条动态条。
enum SyncPlayActivityKind { join, leave, play, pause, seek, episode, host, stall, vote }

class SyncPlayActivity {
  const SyncPlayActivity({
    required this.username,
    required this.kind,
    this.position,
    this.episode,
    this.revision = 0,
  });

  final String username;
  final SyncPlayActivityKind kind;

  /// 只有 [SyncPlayActivityKind.seek] 会带位置。
  final Duration? position;

  /// 只有 [SyncPlayActivityKind.episode] 会带集数。
  final int? episode;

  /// 每次新事件自增，保证同一个动作连续触发时也能重新弹一次。
  final int revision;

  String get label => switch (kind) {
        SyncPlayActivityKind.join => '来啦！',
        SyncPlayActivityKind.leave => '要休息啦~',
        SyncPlayActivityKind.play => '继续播放',
        SyncPlayActivityKind.pause => '暂停了',
        SyncPlayActivityKind.episode =>
          episode == null ? '换了一集' : '切到第 $episode 话',
        SyncPlayActivityKind.seek =>
          position == null ? '跳转了进度' : '跳到了 ${_clock(position!)}',
        SyncPlayActivityKind.host => '把房间交给你了',
        SyncPlayActivityKind.stall => '让大家等一下',
        SyncPlayActivityKind.vote => episode == null
            ? '发起了一个投票'
            : '提议换到第 $episode 话',
      };

  IconData get icon => switch (kind) {
        SyncPlayActivityKind.join => Icons.favorite_rounded,
        SyncPlayActivityKind.leave => Icons.bedtime_rounded,
        SyncPlayActivityKind.play => Icons.play_arrow_rounded,
        SyncPlayActivityKind.pause => Icons.pause_rounded,
        SyncPlayActivityKind.episode => Icons.skip_next_rounded,
        SyncPlayActivityKind.seek => Icons.fast_forward_rounded,
        SyncPlayActivityKind.host => Icons.workspace_premium_rounded,
        SyncPlayActivityKind.stall => Icons.hourglass_bottom_rounded,
        SyncPlayActivityKind.vote => Icons.how_to_vote_rounded,
      };

  static String _clock(Duration value) {
    final int hours = value.inHours;
    final String minutes =
        value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds =
        value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
