import 'dart:async';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/services/player/external_playback_launcher.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/pages/player/controller/player_danmaku_controller.dart';
import 'package:XL/pages/player/controller/player_debug_controller.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/pages/player/controller/player_seek_controller.dart';
import 'package:XL/pages/player/controller/player_aspect_ratio.dart';
import 'package:XL/pages/player/controller/player_panel_controller.dart';
import 'package:XL/pages/player/controller/player_playback_controller.dart';
import 'package:XL/pages/player/controller/player_super_resolution.dart';
import 'package:XL/pages/player/controller/player_syncplay_controller.dart';
import 'package:XL/pages/player/controller/player_screenshot_controller.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/services/player/audio_controller.dart';
import 'package:XL/utils/async_session.dart';

export 'package:XL/pages/player/controller/player_models.dart';

class PlayerController implements Disposable {
  PlayerController(
    this.shaderAssetService,
    DownloadController downloadController,
    this.audioController,
  ) {
    danmaku = PlayerDanmakuController(
      isLocalPlayback: () => isLocalPlayback,
      downloadController: downloadController,
    );
  }

  final ShaderAssetService shaderAssetService;
  final AudioController audioController;
  final AsyncSessionOwner _initializations = AsyncSessionOwner();
  Future<void>? _shutdownFuture;
  final PlayerPanelController panel = PlayerPanelController();
  final PlayerScreenshotController screenshots = PlayerScreenshotController();
  final PlayerDebugController debug = PlayerDebugController();

  late final PlayerDanmakuController danmaku;
  late final PlayerPlaybackController playback = PlayerPlaybackController(
    shaderAssetService: shaderAssetService,
    debug: debug,
    videoUrl: () => videoUrl,
    isLocalPlayback: () => isLocalPlayback,
  );
  late final PlayerSyncPlayController syncplay = PlayerSyncPlayController(
    bangumiId: () => bangumiId,
    currentEpisode: () => currentEpisode,
    currentRoad: () => currentRoad,
    playing: () => playback.playing,
    currentPosition: () => playback.currentPosition,
    playerPosition: () => playback.playerPosition,
    duration: () => playback.duration,
    pause: pause,
    play: play,
    seek: seek,
    isScrubbing: () => seeking.hasActiveInteractiveSeek,
    playbackSpeed: () => playback.playerSpeed,
    setPlaybackSpeed: setPlaybackSpeed,
    followRemoteSeek: () =>
        GStorage.getSetting<bool>(SettingsKeys.syncPlayFollowRemoteSeek),
  );
  late final PlayerSeekController seeking = PlayerSeekController(
    playback: playback,
    danmaku: danmaku,
    pause: pause,
    play: play,
    onSeekCompleted: _onSeekCompleted,
    // 一起看时不暂停做拖动预览：暂停会被当成房间状态广播出去，
    // 回声回来正好落在恢复播放之后，把画面按死在暂停上。
    holdPlaybackDuringScrub: () => syncplay.hasSession,
  );
  late final ExternalPlaybackLauncher externalPlayback =
      ExternalPlaybackLauncher(
        videoUrl: () => videoUrl,
        referer: () => referer,
      );

  late int bangumiId;
  late int currentEpisode;
  late int currentDanmakuEpisodeNumber;
  late int currentRoad;
  late String referer;
  String? coverUrl;
  String videoUrl = '';

  /// 投屏元数据用：电视端标题栏显示「番剧名 · 第 N 集」。
  String _bangumiName = '';
  String _episodeTitle = '';

  bool isLocalPlayback = false;

  /// 描述 [videoUrl]（不是页面可能还没解析完的那一集）。
  String get mediaTitle {
    final episode = _episodeTitle.isNotEmpty
        ? _episodeTitle
        : '第 $currentEpisode 集';
    return _bangumiName.isEmpty ? episode : '$_bangumiName · $episode';
  }

  Timer? _volumeGestureSyncTimer;
  Timer? _persistVolumeTimer;
  double? _pendingGestureVolume;

  bool muted = false;
  double _preMuteVolume = 100;

  Future<void> toggleMute() async {
    if (!muted && playback.volume > 0) {
      _preMuteVolume = playback.volume;
      muted = true;
      _persistMuteState();
      await setVolume(0);
    } else {
      muted = false;
      _persistMuteState();
      await setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  void _persistMuteState() {
    unawaited(GStorage.putSetting<bool>(SettingsKeys.playerMuted, muted));
  }

  /// 在音量被主动调高（手势 / 按键 / 滚轮）时退出静音状态。
  void _clearMuteIfNeeded(double value) {
    if (muted && value > 0) {
      muted = false;
      _persistMuteState();
    }
  }

  void setVolumeDuringGesture(double value) {
    _pendingGestureVolume = value.clamp(0.0, 100.0);
    playback.updateVolume(_pendingGestureVolume!);
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = Timer(const Duration(milliseconds: 80), () {
      final vol = _pendingGestureVolume;
      if (vol == null) {
        return;
      }
      unawaited(playback.syncVolumeToDevice(vol));
    });
  }

  Future<void> finishVolumeGesture() async {
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = null;
    final vol = _pendingGestureVolume;
    _pendingGestureVolume = null;
    if (vol != null) {
      playback.volume = vol;
    }
    playback.invalidatePreciseVolume();
    await playback.syncVolumeToDevice(vol);
    final resolved = vol ?? playback.volume;
    _clearMuteIfNeeded(resolved);
    _persistVolume(resolved);
  }

  /// 记下用户习惯的音量，下次进播放器直接用这个值。
  ///
  /// 静音时不动它：静音只是把当前音量临时压到 0，记住的应该是「解除静音后
  /// 该回到多少」。
  void _persistVolume(double value) {
    if (muted) {
      return;
    }
    final clamped = value.clamp(0.0, 100.0);
    final stored = GStorage.getSetting(SettingsKeys.defaultVolume);
    if (stored.round() == clamped.round()) {
      return;
    }
    unawaited(GStorage.putSetting<double>(SettingsKeys.defaultVolume, clamped));
  }

  /// 拖滑杆时每帧都写一次存储会卡：攒 400ms 再落盘。
  void _schedulePersistVolume(double value) {
    _persistVolumeTimer?.cancel();
    _persistVolumeTimer = Timer(const Duration(milliseconds: 400), () {
      _persistVolumeTimer = null;
      _persistVolume(value);
    });
  }

  Future<bool> init(PlaybackInitParams params) async {
    if (_initializations.isClosed) {
      return false;
    }
    final initialization = _initializations.begin();

    videoUrl = params.videoUrl;
    _bangumiName = params.bangumiName ?? '';
    _episodeTitle = params.episodeTitle.trim();
    isLocalPlayback = params.isLocalPlayback;
    bangumiId = params.bangumiId;
    currentEpisode = params.episode;
    currentDanmakuEpisodeNumber = params.danmakuEpisodeNumber;
    currentRoad = params.currentRoad;
    referer = params.referer;

    KazumiLogger().i(
      'PlayerController: ${params.isLocalPlayback ? "local" : "online"} playback, url: ${params.videoUrl}',
    );

    playback.resetForInit();
    debug.playerLogLevel = GStorage.getSetting(SettingsKeys.playerLogLevel);
    playback.playerSpeed = GStorage.getSetting(SettingsKeys.defaultPlaySpeed);
    panel.aspectRatioMode = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultAspectRatioType),
    );

    playback.buttonSkipTime = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    playback.arrowKeySkipTime = GStorage.getSetting(
      SettingsKeys.arrowKeySkipTime,
    );
    try {
      await _releasePlaybackResources();
    } catch (_) {}
    if (initialization.isStale) {
      return false;
    }

    final Player? player;
    try {
      player = await playback.createVideoController(
        params.httpHeaders,
        params.adBlockerEnabled,
        canInstall: () => initialization.isActive,
        offset: params.offset,
        videoSourceFormat: params.videoSourceFormat,
      );
    } catch (e) {
      if (initialization.isStale) {
        return false;
      }
      playback.loading = false;
      KazumiLogger().e(
        'PlayerController: failed to initialize video',
        error: e,
      );
      return false;
    }
    if (player == null || !_ownsInitialization(initialization, player)) {
      return false;
    }

    // 音量统一走 app 内音量（mpv 的音量），两端一致。
    //
    // 手机上以前读的是系统音量、写回去也是系统音量，等于把播放器音量做成了
    // 系统音量的镜像：想单独把片源压小声，会连通知和闹钟一起压。现在系统音量
    // 只当「上限」，播放器音量是它下面独立的旋钮，硬件键改的仍然是系统音量。
    final freshStart = playback.volume == -1;
    if (freshStart) {
      muted = GStorage.getSetting(SettingsKeys.playerMuted);
      final remembered = GStorage.getSetting(SettingsKeys.defaultVolume);
      _preMuteVolume = remembered > 0 ? remembered : 100;
      playback.volume = muted ? 0 : remembered;
    }
    await setVolume(playback.volume);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    await setPlaybackSpeed(playback.playerSpeed);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    KazumiLogger().i('PlayerController: video initialized');
    playback.loading = false;

    coverUrl = params.coverUrl;

    if (syncplay.syncplayController?.isConnected ?? false) {
      if (syncplay.syncplayController!.currentFileName !=
          "$bangumiId[$currentEpisode]") {
        setSyncPlayPlayingBangumi(
          forceSyncPlaying: true,
          forceSyncPosition: 0.0,
        );
      }
    }
    return true;
  }

  bool _ownsInitialization(AsyncSession initialization, Player player) {
    return initialization.isActive && playback.isCurrentPlayer(player);
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    await playback.setShader(mode, player: player);
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    await playback.setPlaybackSpeed(playerSpeed);
    try {
      updateDanmakuSpeed();
    } catch (_) {}
  }

  void updateDanmakuSpeed() {
    danmaku.updateDanmakuSpeed(playback.playerSpeed);
  }

  Future<void> setVolume(double value) async {
    await playback.setVolume(value);
    _clearMuteIfNeeded(value);
    _schedulePersistVolume(value);
  }

  void syncPlaybackState() {
    playback.syncPlaybackState();
  }

  Future<void> playOrPause() async {
    await playback.playOrPause(pause: pause, play: play);
  }

  Future<void> seek(Duration duration, {bool enableSync = true}) =>
      seeking.seekTo(duration, enableSync: enableSync);

  Future<void> seekBy(Duration offset, {bool enableSync = true}) =>
      seeking.seekBy(offset, enableSync: enableSync);

  Future<void> _onSeekCompleted(bool enableSync) async {
    if (syncplay.hasSession) {
      setSyncPlayCurrentPosition();
      if (enableSync) {
        await requestSyncPlaySync(doSeek: true);
      }
    }
  }

  Future<void> pause({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    danmaku.canvasController.pause();
    try {
      await player.pause();
    } catch (_) {
      return;
    }
    playback.playing = false;
    if (syncplay.hasSession) {
      setSyncPlayCurrentPosition();
      if (enableSync) {
        await requestSyncPlaySync();
      }
    }
  }

  Future<void> play({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    danmaku.canvasController.resume();
    try {
      await player.play();
    } catch (_) {
      return;
    }
    playback.playing = true;
    if (syncplay.hasSession) {
      setSyncPlayCurrentPosition();
      if (enableSync) {
        await requestSyncPlaySync();
      }
    }
  }

  @override
  void dispose() {
    beginShutdown();
  }

  /// Starts the idempotent player shutdown without blocking route navigation.
  ///
  /// Native media and audio-session cleanup may finish after the route is
  /// removed. Immediate ownership detachment happens synchronously before this
  /// method returns.
  void beginShutdown() {
    _initializations.close();
    if (_shutdownFuture != null) {
      return;
    }
    screenshots.dispose();
    final shutdown = _shutdownResources();
    _shutdownFuture = shutdown;
    unawaited(
      shutdown.catchError((Object error, StackTrace stackTrace) {
        KazumiLogger().e(
          'PlayerController: failed to dispose asynchronously',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  Future<void> _shutdownResources() async {
    await Future.wait([_releasePlaybackResources(), syncplay.dispose()]);
  }

  Future<void> _releasePlaybackResources() async {
    _volumeGestureSyncTimer?.cancel();
    _persistVolumeTimer?.cancel();
    _persistVolumeTimer = null;
    await Future.wait([audioController.deactivate(), playback.stop()]);
  }

  Future<void> stop() async {
    _initializations.cancel();
    await _releasePlaybackResources();
  }

  Future<Uint8List?> screenshotPng() => playback.screenshotPng();

  void setButtonForwardTime(int time) {
    playback.buttonSkipTime = time;
    GStorage.putSetting(SettingsKeys.buttonSkipTime, time);
  }

  void setArrowKeyForwardTime(int time) {
    playback.arrowKeySkipTime = time;
    GStorage.putSetting(SettingsKeys.arrowKeySkipTime, time);
  }

  Future<void> launchExternalPlayer() async {
    await externalPlayback.launch();
  }

  Future<void> createSyncPlayRoom(
    String room,
    String username,
    Future<void> Function(int episode, {int currentRoad, int offset})
    changeEpisode,
  ) async {
    await syncplay.createRoom(room, username, changeEpisode);
  }

  void setSyncPlayCurrentPosition({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) {
    syncplay.setCurrentPosition(
      forceSyncPlaying: forceSyncPlaying,
      forceSyncPosition: forceSyncPosition,
    );
  }

  Future<void> setSyncPlayPlayingBangumi({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) async {
    await syncplay.setPlayingBangumi(
      forceSyncPlaying: forceSyncPlaying,
      forceSyncPosition: forceSyncPosition,
    );
  }

  Future<void> requestSyncPlaySync({bool? doSeek}) async {
    await syncplay.requestSync(doSeek: doSeek);
  }

  /// 一起看「切到别人的线路」用：由视频页注入（播放器控制器不持有 videoPageController）。
  Future<void> Function(int road)? syncPlayRoadSwitcher;

  Future<void> switchSyncPlayRoad(int road) async {
    await syncPlayRoadSwitcher?.call(road);
  }

  /// 全房间回退：正数往前、负数往后（`seek` 会带上 doSeek 广播给房间）。
  Future<void> seekForRoom(Duration delta) =>
      seek(playback.currentPosition + delta);

  Future<void> requestSyncPlayStall([
    int seconds = SyncPlayStall.defaultSeconds,
  ]) => syncplay.requestStall(seconds);

  Future<void> startSyncPlayVote(SyncPlayVoteKind kind, {int episode = 0}) =>
      syncplay.startVote(kind, episode: episode);

  Future<void> castSyncPlayVote({required bool agree}) =>
      syncplay.castVote(agree: agree);

  void updateSyncPlaySource({
    required String pluginName,
    required int road,
    required String roadName,
  }) => syncplay.updateSource(
    pluginName: pluginName,
    road: road,
    roadName: roadName,
  );

  Future<void> sendSyncPlayChatMessage(String message) async {
    await syncplay.sendChatMessage(message);
  }

  Future<void> sendSyncPlaySticker(SyncPlayStickerMessage sticker) async {
    await syncplay.sendSticker(sticker);
  }

  Future<void> sendSyncPlayReaction(String emoji) async {
    await syncplay.sendReaction(emoji);
  }

  Future<void> sendSyncPlayNudge(String target) async {
    await syncplay.nudge(target);
  }

  Future<void> exitSyncPlayRoom() async {
    await syncplay.exitRoom();
  }
}
