// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:XL/services/logging/logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mobx/mobx.dart';

part 'player_debug_controller.g.dart';

class PlayerDebugController = _PlayerDebugController
    with _$PlayerDebugController;

abstract class _PlayerDebugController with Store {
  /// LogLevel 0: 错误 1: 警告 2: 简略 3: 详细
  int playerLogLevel = 2;

  /// 调试日志最多保留这么多行（只在调试面板里看，留太多没意义）。
  static const int _maxLogLines = 400;

  @observable
  ObservableList<String> playerLog = ObservableList.of([]);
  @observable
  int playerWidth = 0;
  @observable
  int playerHeight = 0;
  @observable
  String playerVideoParams = '';
  @observable
  String playerAudioParams = '';
  @observable
  String playerPlaylist = '';
  @observable
  String playerAudioTracks = '';
  @observable
  String playerVideoTracks = '';
  @observable
  String playerAudioBitrate = '';
  @observable
  String playerVideoBitrate = '';

  StreamSubscription<PlayerLog>? playerLogSubscription;
  StreamSubscription<int?>? playerWidthSubscription;
  StreamSubscription<int?>? playerHeightSubscription;
  StreamSubscription<VideoParams>? playerVideoParamsSubscription;
  StreamSubscription<AudioParams>? playerAudioParamsSubscription;
  StreamSubscription<Playlist>? playerPlaylistSubscription;
  StreamSubscription<Track>? playerTracksSubscription;
  StreamSubscription<double?>? playerAudioBitrateSubscription;
  StreamSubscription<double?>? playerVideoBitrateSubscription;

  Future<void> setup(
    Player player, {
    required bool Function(Player player) isCurrentPlayer,
    required bool playerDebugMode,
  }) async {
    await playerLogSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerLogSubscription = player.stream.log.listen((event) {
      // 解码失败时 mpv 会疯狂刷日志（样本里 0.2 秒 20+ 条，每秒上百条）。
      // 之前这里无上限地往 ObservableList 里塞，每条还会触发一次 MobX
      // 通知——内存和 CPU 一起涨，卡着卡着就闪退。这里给个硬上限，
      // 攒到两倍再一次性裁剪，避免每条都触发列表变更。
      if (playerLog.length > _maxLogLines * 2) {
        playerLog.removeRange(0, playerLog.length - _maxLogLines);
      }
      playerLog.add(event.toString());
      if (playerDebugMode) {
        KazumiLogger().i("MPV: ${event.toString()}", forceLog: true);
      }
    });
    await playerWidthSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerWidthSubscription = player.stream.width.listen((event) {
      playerWidth = event ?? 0;
    });
    await playerHeightSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerHeightSubscription = player.stream.height.listen((event) {
      playerHeight = event ?? 0;
    });
    await playerVideoParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoParamsSubscription = player.stream.videoParams.listen((event) {
      playerVideoParams = event.toString();
    });
    await playerAudioParamsSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioParamsSubscription = player.stream.audioParams.listen((event) {
      playerAudioParams = event.toString();
    });
    await playerPlaylistSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerPlaylistSubscription = player.stream.playlist.listen((event) {
      playerPlaylist = event.toString();
    });
    await playerTracksSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerTracksSubscription = player.stream.track.listen((event) {
      playerAudioTracks = event.audio.toString();
      playerVideoTracks = event.video.toString();
    });
    await playerAudioBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerAudioBitrateSubscription = player.stream.audioBitrate.listen((event) {
      playerAudioBitrate = event.toString();
    });
    await playerVideoBitrateSubscription?.cancel();
    if (!isCurrentPlayer(player)) return;
    playerVideoBitrateSubscription = player.stream.videoBitrate.listen((event) {
      playerVideoBitrate = event.toString();
    });
  }

  Future<void> cancel() async {
    // Detach fields before awaiting so a new player cannot lose its listeners.
    final logSubscription = playerLogSubscription;
    final widthSubscription = playerWidthSubscription;
    final heightSubscription = playerHeightSubscription;
    final videoParamsSubscription = playerVideoParamsSubscription;
    final audioParamsSubscription = playerAudioParamsSubscription;
    final playlistSubscription = playerPlaylistSubscription;
    final tracksSubscription = playerTracksSubscription;
    final audioBitrateSubscription = playerAudioBitrateSubscription;
    final videoBitrateSubscription = playerVideoBitrateSubscription;

    playerLogSubscription = null;
    playerWidthSubscription = null;
    playerHeightSubscription = null;
    playerVideoParamsSubscription = null;
    playerAudioParamsSubscription = null;
    playerPlaylistSubscription = null;
    playerTracksSubscription = null;
    playerAudioBitrateSubscription = null;
    playerVideoBitrateSubscription = null;

    await logSubscription?.cancel();
    await widthSubscription?.cancel();
    await heightSubscription?.cancel();
    await videoParamsSubscription?.cancel();
    await audioParamsSubscription?.cancel();
    await playlistSubscription?.cancel();
    await tracksSubscription?.cancel();
    await audioBitrateSubscription?.cancel();
    await videoBitrateSubscription?.cancel();
  }
}
