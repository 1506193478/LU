// ignore_for_file: library_private_types_in_public_api

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:flutter/foundation.dart';
import 'package:XL/modules/danmaku/danmaku_module.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/request/apis/bilibili_danmaku_api.dart';
import 'package:XL/request/apis/danmaku_api.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:mobx/mobx.dart';
import 'package:XL/utils/danmaku.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

enum DanmakuLoadStatus {
  success,
  empty,
  failed,
}

class DanmakuLoadResult {
  const DanmakuLoadResult({
    required this.danmakus,
    required this.bangumiID,
    required this.status,
  });

  factory DanmakuLoadResult.success({
    required List<DanmakuEntry> danmakus,
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: danmakus,
      bangumiID: bangumiID,
      status: danmakus.isEmpty
          ? DanmakuLoadStatus.empty
          : DanmakuLoadStatus.success,
    );
  }

  factory DanmakuLoadResult.failed({
    required int bangumiID,
  }) {
    return DanmakuLoadResult(
      danmakus: const [],
      bangumiID: bangumiID,
      status: DanmakuLoadStatus.failed,
    );
  }

  final List<DanmakuEntry> danmakus;
  final int bangumiID;
  final DanmakuLoadStatus status;

  bool get hasDanmakus => status == DanmakuLoadStatus.success;

  bool get isFailed => status == DanmakuLoadStatus.failed;
}

class DanmakuTimeline {
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds = playbackPosition.inMilliseconds -
        (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

/// 画布还没建好时用的空控制器。
///
/// 所有方法都是空实现，`option` 返回一份默认配置。这样在 `DanmakuScreen` 回调
/// 之前发生的 `pause` / `resume` / `clear` / `addDanmaku` 都变成无害的空操作，
/// 而不是抛 `LateInitializationError` 把调用方（换集、起播、聊天）一起带崩。
/// 这段窗口期里本来也不可能有弹幕可画 —— 播放器还没出画面。
canvas.DanmakuController _createNullDanmakuController() {
  const canvas.DanmakuOption option = canvas.DanmakuOption();
  return canvas.DanmakuController(
    addDanmaku: (_) {},
    updateOption: (_) {},
    pause: () {},
    resume: () {},
    clear: () {},
    getOption: () => option,
    isRunning: () => false,
    findDanmaku: (_) => const <canvas.DanmakuItem>[],
    findSingleDanmaku: (_) => null,
    getViewWidth: () => 0,
    getViewHeight: () => 0,
    scrollDanmaku: const <canvas.DanmakuItem>[],
    staticDanmaku: const <canvas.DanmakuItem>[],
    specialDanmaku: const <canvas.DanmakuItem>[],
  );
}

abstract class _PlayerDanmakuController with Store {
  _PlayerDanmakuController({
    required this.isLocalPlayback,
    required this.downloadController,
  });

  final bool Function() isLocalPlayback;
  final DownloadController downloadController;

  /// 弹幕画布控制器。
  ///
  /// `DanmakuScreen` 要等播放页真正建起来之后才回调 `createdController`，而
  /// `pause` / `resume` / `clear` / `addDanmaku` 这些调用散落在换集、拖进度条、
  /// 一起看聊天等**可能早于播放页构建**的路径上（`player_seek_controller`、
  /// `player_controller.setPlaying`、`video_page` 的聊天监听都会碰它）。
  ///
  /// 原来这里是个裸 `late`，谁先抢跑谁抛 `LateInitializationError`：轻则弹幕
  /// 从此不出来，重则换集/起播这条链路直接中断（表现就是"拉不起播放器"）。
  /// iOS 首帧更慢、转场更长，撞上的概率比安卓高得多。先挂一个空实现兜底，
  /// 画布建好再换成真的。
  canvas.DanmakuController canvasController = _createNullDanmakuController();

  final Map<int, List<DanmakuEntry>> danDanmakus = {};

  /// 弹幕集合的版本号，每变一次 +1。
  ///
  /// 热力条拿它当缓存键：`danDanmakus` 是原地增删的，光比较长度不一定能
  /// 发现变化（清空再灌满同样条数），而且 Map 本身不是 observable。
  final ValueNotifier<int> heatRevision = ValueNotifier<int>(0);

  void _bumpHeatRevision() => heatRevision.value = heatRevision.value + 1;
  @observable
  bool danmakuOn = false;
  @observable
  bool danmakuLoading = false;

  int bangumiID = 0;
  int _scheduledDanmakuGeneration = 0;

  int get scheduledDanmakuGeneration => _scheduledDanmakuGeneration;

  double get timelineOffsetSeconds {
    final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);
    return offset;
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final danmakuSecond = resolveDanmakuSecond(playbackPosition);
    if (danmakuSecond == null) {
      return const [];
    }
    return danDanmakus[danmakuSecond] ?? const [];
  }

  @action
  void setDanmakuEnabled(bool value) {
    danmakuOn = value;
  }

  void clearAndInvalidateScheduledDanmakus() {
    _scheduledDanmakuGeneration++;
    canvasController.clear();
  }

  // Apply fetched data only after VideoPageController validates the session.
  Future<DanmakuLoadResult> fetchDanmaku(
    int bangumiId,
    String pluginName,
    int episode, {
    String bangumiTitle = '',
    String bangumiOriginalTitle = '',
  }) async {
    if (isLocalPlayback()) {
      return await _fetchCachedDanmaku(
        bangumiId,
        pluginName,
        episode,
        bangumiTitle: bangumiTitle,
        bangumiOriginalTitle: bangumiOriginalTitle,
      );
    }
    if (_usesBilibiliSource) {
      return await _fetchBilibiliDanmaku(
        bangumiTitle,
        episode,
        originalTitle: bangumiOriginalTitle,
      );
    }
    return await _fetchDanDanmakuByBgmBangumiID(
      bangumiId,
      episode,
    );
  }

  /// 弹幕源开关。B 站免凭据可用，弹弹play 需要自备开放平台密钥。
  bool get _usesBilibiliSource =>
      GStorage.getSetting(SettingsKeys.danmakuSource) != 'dandanplay';

  Future<DanmakuLoadResult> _fetchBilibiliDanmaku(
    String title,
    int episode, {
    String originalTitle = '',
  }) async {
    final nextBangumiID = bangumiID;
    if (title.trim().isEmpty) {
      KazumiLogger().i('PlayerController: bilibili source needs a title');
      return DanmakuLoadResult.success(
        danmakus: const [],
        bangumiID: nextBangumiID,
      );
    }
    KazumiLogger().i(
        'PlayerController: attempting bilibili danmaku "$title" ep $episode');
    try {
      final res = await BilibiliDanmakuApi.fetchByTitleAndEpisode(
        title: title,
        episode: episode,
        originalTitle: originalTitle.isEmpty ? null : originalTitle,
      );
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: nextBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to fetch bilibili danmaku for "$title"',
          error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
  }

  @action
  void beginDanmakuLoad() {
    danDanmakus.clear();
    _bumpHeatRevision();
    danmakuLoading = true;
  }

  @action
  void applyDanmakuLoad(
    DanmakuLoadResult result, {
    required bool enableDanmaku,
  }) {
    bangumiID = result.bangumiID;
    addDanmakus(result.danmakus);
    danmakuOn = enableDanmaku;
    danmakuLoading = false;
  }

  @action
  void applyUnavailableDanmakuLoad(DanmakuLoadResult result) {
    bangumiID = result.bangumiID;
    danDanmakus.clear();
    _bumpHeatRevision();
    danmakuOn = false;
    danmakuLoading = false;
  }

  @action
  void finishDanmakuLoad({bool disableDanmaku = false}) {
    if (disableDanmaku) {
      danDanmakus.clear();
    _bumpHeatRevision();
      danmakuOn = false;
    }
    danmakuLoading = false;
  }

  Future<DanmakuLoadResult> _fetchCachedDanmaku(
      int bangumiId, String pluginName, int episode,
      {String bangumiTitle = '', String bangumiOriginalTitle = ''}) async {
    KazumiLogger().i(
        'PlayerController: attempting to load cached danmaku for episode $episode');
    var nextBangumiID = bangumiID;
    try {
      final cachedDanmakus = await downloadController.getCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
      );

      if (cachedDanmakus != null && cachedDanmakus.isNotEmpty) {
        KazumiLogger().i(
            'PlayerController: loaded ${cachedDanmakus.length} cached danmakus');
        return DanmakuLoadResult.success(
          danmakus: cachedDanmakus,
          bangumiID: nextBangumiID,
        );
      } else {
        KazumiLogger()
            .i('PlayerController: no cached danmaku, attempting online fetch');
        try {
          if (_usesBilibiliSource) {
            final res = await BilibiliDanmakuApi.fetchByTitleAndEpisode(
              title: bangumiTitle,
              episode: episode,
              originalTitle: bangumiOriginalTitle.isEmpty
                  ? null
                  : bangumiOriginalTitle,
            );
            if (res.isNotEmpty) {
              KazumiLogger().i(
                  'PlayerController: fetched ${res.length} bilibili danmakus online');
              _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                  episode, res, nextBangumiID);
            }
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
          nextBangumiID =
              await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bangumiId);
          if (nextBangumiID != 0) {
            var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
            if (res.isNotEmpty) {
              KazumiLogger()
                  .i('PlayerController: fetched ${res.length} danmakus online');
              _saveDanmakuToCache(downloadController, bangumiId, pluginName,
                  episode, res, nextBangumiID);
            }
            return DanmakuLoadResult.success(
              danmakus: res,
              bangumiID: nextBangumiID,
            );
          }
        } catch (e) {
          KazumiLogger().w(
              'PlayerController: failed to fetch danmaku online (may be offline)',
              error: e);
          return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
        }
      }
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to load cached danmaku', error: e);
      return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
    }
    return DanmakuLoadResult.success(
      danmakus: const [],
      bangumiID: nextBangumiID,
    );
  }

  void _saveDanmakuToCache(
      DownloadController downloadController,
      int bangumiId,
      String pluginName,
      int episode,
      List<DanmakuEntry> danmakus,
      int danDanID) {
    try {
      downloadController.updateCachedDanmakus(
        bangumiId,
        pluginName,
        episode,
        danmakus,
        danDanID,
      );
      KazumiLogger()
          .i('PlayerController: saved ${danmakus.length} danmakus to cache');
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to save danmaku to cache', error: e);
    }
  }

  Future<DanmakuLoadResult> _fetchDanDanmakuByBgmBangumiID(
      int bgmBangumiID, int episode) async {
    KazumiLogger().i(
        'PlayerController: attempting to get danmaku [BgmBangumiID] $bgmBangumiID');
    var nextBangumiID = bangumiID;
    try {
      nextBangumiID =
          await DanmakuApi.getDanDanBangumiIDByBgmBangumiID(bgmBangumiID);
      if (nextBangumiID == 0) {
        return DanmakuLoadResult.success(
          danmakus: const [],
          bangumiID: nextBangumiID,
        );
      }
      var res = await DanmakuApi.getDanDanmaku(nextBangumiID, episode);
      return DanmakuLoadResult.success(
        danmakus: res,
        bangumiID: nextBangumiID,
      );
    } catch (e) {
      KazumiLogger().w(
          'PlayerController: failed to get danmaku [BgmBangumiID] $bgmBangumiID',
          error: e);
    }
    return DanmakuLoadResult.failed(bangumiID: nextBangumiID);
  }

  @action
  Future<bool> getDanDanmakuByEpisodeID(int episodeID) async {
    KazumiLogger().i('PlayerController: attempting to get danmaku $episodeID');
    danmakuLoading = true;
    try {
      danDanmakus.clear();
    _bumpHeatRevision();
      var res = await DanmakuApi.getDanDanmakuByEpisodeID(episodeID);
      addDanmakus(res);
      return res.isNotEmpty;
    } catch (e) {
      KazumiLogger().w('PlayerController: failed to get danmaku', error: e);
      rethrow;
    } finally {
      danmakuLoading = false;
    }
  }

  /// 手动选源时按 B 站 cid 加载弹幕，与 [getDanDanmakuByEpisodeID] 对称。
  @action
  Future<bool> getBilibiliDanmakuByCid(int cid) async {
    KazumiLogger().i('PlayerController: attempting bilibili danmaku cid $cid');
    danmakuLoading = true;
    try {
      danDanmakus.clear();
    _bumpHeatRevision();
      final res = await BilibiliDanmakuApi.getDanmaku(cid);
      addDanmakus(res);
      return res.isNotEmpty;
    } catch (e) {
      KazumiLogger()
          .w('PlayerController: failed to get bilibili danmaku', error: e);
      rethrow;
    } finally {
      danmakuLoading = false;
    }
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    final bool danmakuDeduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = danmakuDeduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final danmakuSecond = element.time.toInt();
      (danDanmakus[danmakuSecond] ??= <DanmakuEntry>[]).add(element);
    }
    _bumpHeatRevision();
  }

  void updateDanmakuSpeed(double playerSpeed) {
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    canvasController
        .updateOption(canvasController.option.copyWith(duration: duration));
  }
}
