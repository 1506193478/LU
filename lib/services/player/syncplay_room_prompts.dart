import 'package:XL/services/player/syncplay_room_signals.dart';

/// 房间里正在发生的「需要你回应一下」的事：等我一下 / 投票 / 片源不一致。
///
/// 这三件事共用播放器顶部那一条横幅，所以状态也放在一起，同一时间只显示一条：
/// 先来后到，后来的排队（用 [revision] 让 UI 知道换人了）。
class SyncPlayStallState {
  SyncPlayStallState({
    required this.by,
    required this.totalSeconds,
    DateTime? endsAt,
  }) : endsAt = endsAt ?? DateTime.now().add(Duration(seconds: totalSeconds));

  final String by;
  final int totalSeconds;

  /// 到点自动继续。存绝对时刻，UI 自己按秒重绘，不用控制器每秒推一次。
  final DateTime endsAt;

  int get remainingSeconds {
    final int left = endsAt.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  bool get isOver => remainingSeconds <= 0;
}

/// 一次进行中的投票。
class SyncPlayVoteState {
  SyncPlayVoteState({
    required this.id,
    required this.by,
    required this.kind,
    required this.value,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String id;
  final String by;
  final SyncPlayVoteKind kind;

  /// 只有换集投票用得上。
  final int value;

  final DateTime startedAt;

  final Set<String> yes = <String>{};
  final Set<String> no = <String>{};

  int get yesCount => yes.length;
  int get noCount => no.length;

  bool get isExpired =>
      DateTime.now().difference(startedAt) > SyncPlayVote.lifetime;

  int get remainingSeconds {
    final int left = SyncPlayVote.lifetime.inSeconds -
        DateTime.now().difference(startedAt).inSeconds;
    return left < 0 ? 0 : left;
  }

  String get title => switch (kind) {
        SyncPlayVoteKind.pause => '暂停一下',
        SyncPlayVoteKind.resume => '继续播放',
        SyncPlayVoteKind.episode => '换到第 $value 话',
      };

  bool hasVoted(String username) => yes.contains(username) || no.contains(username);
}

/// 片源不一致：对方用的插件 / 线路和我这边不一样。
class SyncPlaySourceMismatch {
  const SyncPlaySourceMismatch({
    required this.by,
    required this.info,
    required this.samePlugin,
  });

  /// 谁在用别的源。
  final String by;
  final SyncPlaySourceInfo info;

  /// 同一个插件、只是线路不同 —— 这种可以一键切过去。
  final bool samePlugin;
}
