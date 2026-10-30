import 'package:XL/pages/player/controller/player_danmaku_controller.dart';
import 'package:XL/pages/player/controller/player_playback_controller.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

class _InteractiveSeekSession {
  _InteractiveSeekSession({
    required this.pauseCompleted,
    required this.initialPosition,
    required this.wasPlaying,
    required this.pausedForPreview,
    required this.player,
  }) : target = initialPosition;

  final Future<void> pauseCompleted;
  final Duration initialPosition;
  final bool wasPlaying;

  /// 这次拖动有没有真的把播放器停下来。
  ///
  /// 一起看时不暂停（见 [PlayerSeekController.beginInteractiveSeek]），
  /// 收尾也就不能再无条件 `play()` —— 那会把本来暂停的画面播起来。
  final bool pausedForPreview;
  final Player? player;
  Duration target;
  Future<bool>? completion;
}

class PlayerSeekController {
  PlayerSeekController({
    required PlayerPlaybackController playback,
    required PlayerDanmakuController danmaku,
    required Future<void> Function({bool enableSync}) pause,
    required Future<void> Function({bool enableSync}) play,
    required Future<void> Function(bool enableSync) onSeekCompleted,
    required bool Function() holdPlaybackDuringScrub,
  })  : _playback = playback,
        _danmaku = danmaku,
        _pause = pause,
        _play = play,
        _onSeekCompleted = onSeekCompleted,
        _holdPlaybackDuringScrub = holdPlaybackDuringScrub;

  final PlayerPlaybackController _playback;
  final PlayerDanmakuController _danmaku;
  final Future<void> Function({bool enableSync}) _pause;
  final Future<void> Function({bool enableSync}) _play;
  final Future<void> Function(bool enableSync) _onSeekCompleted;

  /// 拖动进度条时要不要保持播放。
  ///
  /// 单机模式下暂停预览是对的：不暂停的话每秒的状态同步会把拖动预览
  /// 拽回真实进度。但一起看时「暂停」会作为房间状态广播出去，回声绕回来
  /// 正好落在「松手恢复播放」之后，把刚恢复的播放又按下去 —— 表现就是
  /// 拖一次进度条画面就卡住不动。所以房间里改成不停、直接跳。
  final bool Function() _holdPlaybackDuringScrub;

  final AsyncSerialQueue _seekQueue = AsyncSerialQueue();
  _InteractiveSeekSession? _interactiveSession;

  bool get hasActiveInteractiveSeek => _interactiveSession != null;

  Future<void> seekTo(
    Duration target, {
    bool enableSync = true,
  }) {
    final player = _playback.mediaPlayer;
    if (player == null) {
      return Future<void>.value();
    }

    final normalizedTarget = _normalize(target);
    _playback.currentPosition = normalizedTarget;
    _danmaku.clearAndInvalidateScheduledDanmakus();

    return _seekQueue.run(() async {
      if (!_playback.isCurrentPlayer(player)) {
        return;
      }
      try {
        await player.seek(normalizedTarget);
      } catch (_) {
        return;
      }
      if (!_playback.isCurrentPlayer(player)) {
        return;
      }
      try {
        await _onSeekCompleted(enableSync);
      } catch (e) {
        // Callers often drop this future; it must not complete with an error.
        KazumiLogger()
            .w('PlayerSeekController: seek completion failed', error: e);
      }
    });
  }

  Future<void> seekBy(
    Duration offset, {
    bool enableSync = true,
  }) =>
      seekTo(
        _playback.currentPosition + offset,
        enableSync: enableSync,
      );

  void beginInteractiveSeek() {
    final initialPosition = _playback.currentPosition;
    final previousSession = _interactiveSession;
    // Keep the original playing state across overlapping gestures.
    final wasPlaying = previousSession != null && _isCurrent(previousSession)
        ? previousSession.wasPlaying
        : _playback.playerPlaying;
    final player = _playback.mediaPlayer;
    final bool pauseForPreview = !_holdPlaybackDuringScrub();
    if (!pauseForPreview) {
      // 不暂停就得自己按住进度：每秒一次的 syncPlaybackState 会把
      // currentPosition 改回真实播放位置，拖动预览会一直跳。
      _playback.holdPositionPreview = true;
    }
    _interactiveSession = _InteractiveSeekSession(
      pauseCompleted:
          pauseForPreview ? _pause(enableSync: false) : Future<void>.value(),
      initialPosition: initialPosition,
      wasPlaying: wasPlaying,
      pausedForPreview: pauseForPreview,
      player: player,
    );
  }

  bool updateInteractiveSeek(Duration target) {
    final session = _interactiveSession;
    if (session == null || !_isCurrent(session) || session.completion != null) {
      return false;
    }
    session.target = _normalize(target);
    _playback.currentPosition = session.target;
    return true;
  }

  Future<bool> finishInteractiveSeek({bool cancelled = false}) {
    final session = _interactiveSession;
    if (session == null) {
      return Future<bool>.value(false);
    }
    return session.completion ??=
        _finishInteractiveSeek(session, cancelled: cancelled);
  }

  void invalidateInteractiveSeek() {
    _playback.holdPositionPreview = false;
    _interactiveSession = null;
  }

  Future<bool> _finishInteractiveSeek(
    _InteractiveSeekSession session, {
    required bool cancelled,
  }) async {
    try {
      if (!_isCurrent(session)) {
        return false;
      }
      if (cancelled) {
        // Only the preview moved; cancellation needs no native seek.
        _playback.currentPosition = session.initialPosition;
      }
      await session.pauseCompleted;
      if (!_isCurrent(session)) {
        return false;
      }
      if (!cancelled) {
        // 本地跳转先不报同步：等恢复播放之后再一次性把「正在播放 + 新位置」
        // 发出去。反过来的话（先报、后恢复）房间里收到的最后一条状态是
        // paused=true，自己的客户端也会照它再暂停一次。
        await seekTo(session.target, enableSync: false);
        if (!_isCurrent(session)) {
          return false;
        }
      }
      if (session.pausedForPreview && (!cancelled || session.wasPlaying)) {
        await _play(enableSync: false);
      }
      if (!cancelled) {
        // 此时 playing 已经是最终状态，这一次请求就是房间看到的定论。
        await _onSeekCompleted(true);
        if (!_isCurrent(session)) {
          return false;
        }
      }
      return _isCurrent(session);
    } finally {
      if (identical(_interactiveSession, session)) {
        _interactiveSession = null;
      }
      // 手势可能重叠：只有确实没有活跃拖动了才放开进度锁。
      if (_interactiveSession == null) {
        _playback.holdPositionPreview = false;
      }
    }
  }

  Duration _normalize(Duration target) {
    var milliseconds = target.inMilliseconds;
    if (milliseconds < 0) {
      milliseconds = 0;
    }
    final duration = _playback.duration;
    if (duration > Duration.zero && milliseconds > duration.inMilliseconds) {
      milliseconds = duration.inMilliseconds;
    }
    return Duration(milliseconds: milliseconds);
  }

  bool _isCurrent(_InteractiveSeekSession session) =>
      identical(_interactiveSession, session) &&
      identical(_playback.mediaPlayer, session.player);
}
