import 'dart:async';

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';

import 'package:XL/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/bean/widget/embedded_native_control_area.dart';
import 'package:XL/bean/widget/loading_indicator.dart';
import 'package:XL/bean/widget/media_error_widget.dart';
import 'package:XL/modules/download/download_module.dart';
import 'package:XL/navigation.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/download/download_episode_sheet.dart';
import 'package:XL/pages/history/history_controller.dart';
import 'package:XL/pages/player/episode_comments_sheet.dart';
import 'package:XL/pages/player/player_controller.dart';
import 'package:XL/pages/player/player_item.dart';
import 'package:XL/pages/player/syncplay_room_panel.dart';
import 'package:XL/pages/video/episode_selection_panel.dart';
import 'package:XL/pages/video/player_content_tabs.dart';
import 'package:XL/modules/history/history_module.dart';
import 'package:XL/pages/video/video_controller.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/pages/video/video_page_layout.dart';
import 'package:XL/pages/video/video_side_panel.dart';
import 'package:XL/pages/video/video_system_bars.dart';
import 'package:XL/services/player/pip_utils.dart';
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/timed_shutdown_service.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/device.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.args,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.downloadController,
  });

  final VideoPlaybackArgs args;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final DownloadController downloadController;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with SingleTickerProviderStateMixin, WindowListener {
  PlayerController get playerController => widget.playerController;
  VideoPageController get videoPageController => widget.videoPageController;
  bool _didInitializePlayback = false;
  bool _isExiting = false;
  HistoryController get historyController => widget.historyController;
  DownloadController get downloadController => widget.downloadController;
  late bool playResume;
  bool showDebugLog = false;
  List<String> webviewLogLines = [];
  StreamSubscription<String>? _logSubscription;
  final FocusNode keyboardFocus =
      FocusNode(debugLabel: 'Video player shortcut scope');

  final _episodePanelKey = GlobalKey<EpisodeSelectionPanelState>();
  final _sidePanelKey = GlobalKey<VideoSidePanelState>();
  late TabController tabController;

  late final bool disableAnimations;

  StreamSubscription<SyncPlayChatMessage>? _syncChatSubscription;
  late final mobx.ReactionDisposer _pipModeListener;
  LocalHistoryEntry? _desktopPipEntry;
  late ModalRoute<Object?> _route;

  static const Duration _offlinePlayerInitDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    videoPageController.applyPlaybackArgs(widget.args);
    windowManager.addListener(this);
    // iOS：路由转场期间旧页面的输入焦点不会被自动释放，键盘会一路跟着
    // 进播放器（一起看跟播最常见，大厅的房间号输入框正拿着焦点），而且
    // 播放器里没有任何能收起它的地方。进来时无条件收一次。
    FocusManager.instance.primaryFocus?.unfocus();

    tabController = TabController(length: 3, vsync: this);

    playResume = GStorage.getSetting(SettingsKeys.playResume);
    disableAnimations =
        GStorage.getSetting(SettingsKeys.playerDisableAnimations);
    // 一起看「切到房主的线路」：播放器控制器不持有 videoPageController，
    // 由页面把换集能力注进去。
    playerController.syncPlayRoadSwitcher = (int road) => changeEpisode(
          videoPageController.playbackEpisode.episode,
          currentRoad: road,
        );
    // 一起看「拉取正在播放」：房间里有新成员求同步时，把当前番剧信息
    // 定向回给他。播放器控制器只有 id 和集号，拼不出能跟播的完整信息，
    // 必须由页面提供；离线 / Emby 播放没有可分享的片源，返回 null。
    playerController.syncplay.currentPlayRequestProvider = () {
      if (videoPageController.isOfflineMode ||
          videoPageController.isEmbyMode) {
        return null;
      }
      final item = videoPageController.bangumiItem;
      return SyncPlayPlayRequest(
        bangumiId: item.id,
        name: item.name,
        nameCn: item.nameCn,
        coverUrl: item.images['large'] ?? '',
        pluginName: videoPageController.currentPlugin.name,
        title: videoPageController.title.isNotEmpty
            ? videoPageController.title
            : (item.nameCn.isNotEmpty ? item.nameCn : item.name),
        src: videoPageController.src,
      );
    };
    _pipModeListener = mobx.reaction<bool>(
      (_) => videoPageController.isPip,
      _syncDesktopPipHistory,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializePlayback) {
      return;
    }
    _didInitializePlayback = true;
    _route = ModalRoute.of(context)!;
    closeOnExternalNavigation(_route);
    videoPageController.fullscreen.attach(_route);
    if (isDesktop()) {
      unawaited(videoPageController.fullscreen
          .initializeDesktop(windowManager.isFullScreen));
    }
    _initializePlayback();
  }

  void _initializePlayback() {
    if (videoPageController.isOfflineMode) {
      _initOfflineMode();
    } else if (videoPageController.isEmbyMode) {
      _initEmbyMode();
    } else {
      _initOnlineMode();
    }

    _joinPendingSyncPlayRoom();

    _syncChatSubscription =
        playerController.syncplay.chatStream.listen((event) {
      // 降噪开关：关掉之后聊天记录照旧，只是不再飘到画面上。
      if (!GStorage.getSetting<bool>(SettingsKeys.syncPlayChatDanmaku)) {
        return;
      }
      final localUsername =
          playerController.syncplay.syncplayController?.username ?? '';
      // 反应只飘 emoji 本身，带上「某某：」反而像在说话。
      final String displayText = event.isReaction
          ? event.message
          : '${event.username}：${event.message}';

      if (playerController.danmaku.danmakuOn &&
          event.username != localUsername &&
          event.fromRemote) {
        playerController.danmaku.canvasController.addDanmaku(
          DanmakuContentItem(
            displayText,
            color: event.isReaction ? Colors.amber : Colors.orange,
            isColorful: true,
            type: DanmakuItemType.bottom,
            extra: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    });
  }

  /// 「一起看」页建房后跳转过来时，播放器接管同一个房间。
  void _joinPendingSyncPlayRoom() {
    final String? room = widget.args.syncPlayRoom;
    final String? userName = widget.args.syncPlayUserName;
    if (room == null || room.isEmpty || userName == null || userName.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await playerController.createSyncPlayRoom(room, userName, changeEpisode);
    });
  }

  void _initOfflineMode() {
    final identity = videoPageController.currentHistoryIdentity;
    videoPageController.historyOffset = identity == null
        ? 0
        : videoPageController.getHistoryOffsetFor(identity);
    _revealCurrentEpisode();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(_offlinePlayerInitDelay);
      if (!mounted) {
        return;
      }

      await changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: videoPageController.historyOffset,
      );
    });
  }

  /// Emby 起播。
  ///
  /// 和在线模式的区别只在「起播集从哪来」：在线模式会读"上次看到第几集"
  /// 把用户拉回去，而 Emby 是用户在媒体库里点了具体某一集，那一集就是目标。
  /// 该集自己的续播秒数不用在这里算——`_changeEmbyEpisode` 会按集号去查历史。
  void _initEmbyMode() {
    videoPageController.historyOffset = 0;
    _revealCurrentEpisode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      changeEpisode(
        videoPageController.selectedEpisode.episode,
        currentRoad: videoPageController.selectedEpisode.road,
        offset: 0,
      );
    });
  }

  void _initOnlineMode() {    videoPageController.historyOffset = 0;

    var progress = historyController.lastWatching(
        videoPageController.bangumiItem,
        videoPageController.currentPlugin.name);
    if (progress != null) {
      if (videoPageController.roadList.length > progress.road) {
        if (videoPageController.roadList[progress.road].data.length >=
            progress.episode) {
          videoPageController.resetEpisodeState(
            episode: progress.episode,
            road: progress.road,
          );
          if (playResume) {
            videoPageController.historyOffset = progress.progress.inSeconds;
          }
        }
      }
    }
    _revealCurrentEpisode();

    _logSubscription = videoPageController.logStream.listen((log) {
      if (mounted) {
        setState(() {
          webviewLogLines.add(log);
          if (webviewLogLines.length > 100) {
            webviewLogLines.removeAt(0);
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      changeEpisode(videoPageController.selectedEpisode.episode,
          currentRoad: videoPageController.selectedEpisode.road,
          offset: videoPageController.historyOffset);
    });
  }

  @override
  void dispose() {
    // 闭包里抓着 videoPageController，页面没了就不能再让它被调用。
    playerController.syncplay.currentPlayRequestProvider = null;
    clearExternalNavigationMark(_route);
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    try {
      _syncChatSubscription?.cancel();
    } catch (_) {}
    try {
      _logSubscription?.cancel();
    } catch (_) {}
    _pipModeListener();
    _desktopPipEntry?.remove();
    _desktopPipEntry = null;
    if (!isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (_) {}
    }
    unawaited(videoPageController.fullscreen.close());
    keyboardFocus.dispose();
    tabController.dispose();
    TimedShutdownService().cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(true);
  }

  @override
  void onWindowLeaveFullScreen() {
    videoPageController.fullscreen.onDesktopFullscreenChanged(false);
  }

  void _toggleDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  Future<void> changeEpisode(int episode,
      {int currentRoad = 0, int offset = 0}) async {
    if (!mounted || _isExiting) {
      return;
    }
    setState(() {
      webviewLogLines.clear();
      showDebugLog = false;
    });
    await videoPageController.changeEpisode(episode,
        currentRoad: currentRoad,
        offset: offset,
        playerController: playerController);
    _publishSyncPlaySource();
  }

  /// 把自己的片源指纹（插件 + 线路）告诉房间：同插件不同线路可以一键切过去，
  /// 跨插件只能提示。换集、换线路都要重发。
  void _publishSyncPlaySource() {
    final int road = videoPageController.selectedEpisode.road;
    final roads = videoPageController.roadList;
    if (road < 0 || road >= roads.length) {
      return;
    }
    playerController.updateSyncPlaySource(
      pluginName: videoPageController.currentPlugin.name,
      road: road,
      roadName: roads[road].name,
    );
  }

  void _revealCurrentEpisode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _episodePanelKey.currentState?.revealCurrentEpisode();
    });
  }

  void _toggleSidePanel() => _sidePanelKey.currentState?.toggle();
  void _closeSidePanel() => _sidePanelKey.currentState?.close();

  /// 这部番已经看过的集号（按当前插件的历史算）。
  ///
  /// 只认「看了 20 秒以上」的集：点开就退出的不算看过，否则选集面板上
  /// 会一片都是勾，等于没有信息。
  Set<int> get _watchedEpisodes {
    final String adapter = videoPageController.currentPlugin.name;
    final int id = videoPageController.bangumiItem.id;
    for (final History history in historyController.histories) {
      if (history.bangumiItem.id != id || history.adapterName != adapter) {
        continue;
      }
      return <int>{
        for (final MapEntry<int, Progress> entry
            in history.progresses.entries)
          if (entry.value.progress > const Duration(seconds: 20)) entry.key,
      };
    }
    return const <int>{};
  }

  /// 当前线路一共几集，给一起看面板的播放队列做越界判断用。
  int get _currentRoadEpisodeCount {
    final int road = videoPageController.selectedEpisode.road;
    final roads = videoPageController.roadList;
    if (road < 0 || road >= roads.length) return 0;
    return roads[road].data.length;
  }

  // Only desktop PiP participates in local navigation.
  void _syncDesktopPipHistory(bool isPip) {
    if (!isDesktop()) return;
    if (isPip && _desktopPipEntry == null) {
      _desktopPipEntry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          _desktopPipEntry = null;
          if (videoPageController.isPip) {
            videoPageController.isPip = false;
            unawaited(PipUtils.exitDesktopPIPWindow());
          }
        },
      );
      ModalRoute.of(context)!.addLocalHistoryEntry(_desktopPipEntry!);
    } else if (!isPip) {
      _desktopPipEntry?.remove();
      _desktopPipEntry = null;
    }
  }

  void _onBackPressed() {
    unawaited(Navigator.of(context).maybePop());
  }

  void pauseForTimedShutdown() {
    if (playerController.playback.playing) {
      playerController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          setState(() => _isExiting = true);
          playerController.beginShutdown();
        }
      },
      child: Observer(builder: (context) {
        final bool isPip = videoPageController.isPip;
        return VideoSystemBars(
          fullscreen: videoPageController.isFullscreen,
          isPip: isPip,
          child: Scaffold(
            body: VideoPageLayout(
              fullscreen: videoPageController.isFullscreen,
              isPip: isPip,
              playerBuilder: (context, layout) => ColoredBox(
                color: Colors.black,
                child: Focus(
                  focusNode: keyboardFocus,
                  autofocus: true,
                  // Cleanup resets loading while the route is still visible.
                  child: _isExiting
                      ? const SizedBox.expand()
                      : Observer(builder: (_) => _buildPlayerBody(layout)),
                ),
              ),
              tabs: tabBody,
              sidePanel: VideoSidePanel(
                key: _sidePanelKey,
                fullscreen: videoPageController.isFullscreen,
                disableAnimations: disableAnimations,
                onOpened: _revealCurrentEpisode,
                onClosed: keyboardFocus.requestFocus,
                child: tabBody,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPlayerBody(VideoPlayerLayout layout) {
    final bool playerLoading = playerController.playback.loading;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (videoPageController.loading ||
                  playerLoading ||
                  videoPageController.errorMessage != null)
                Container(
                  color: Colors.black,
                  child: Observer(builder: (context) {
                    final errorMessage = videoPageController.errorMessage;
                    if (errorMessage != null) {
                      return MediaErrorWidget(
                        title: '暂时无法播放',
                        errMsg: errorMessage,
                        icon: Icons.videocam_off_outlined,
                      );
                    }
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LoadingIndicator(
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiaryContainer),
                          const SizedBox(height: 10),
                          Text(
                            videoPageController.loading
                                ? '视频资源解析中'
                                : '视频资源解析成功, 播放器加载中',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              Visibility(
                visible: (videoPageController.loading || playerLoading) &&
                    showDebugLog,
                child: Container(
                  color: Colors.black,
                  child: Align(
                    alignment: Alignment.center,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: webviewLogLines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          webviewLogLines[index],
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !videoPageController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                            onPressed: _onBackPressed,
                          ),
                          const Expanded(
                              child: dtb.DragToMoveArea(
                                  child: SizedBox(height: 40))),
                          IconButton(
                            icon: const Icon(Icons.refresh_outlined,
                                color: Colors.white),
                            onPressed: () {
                              changeEpisode(
                                  videoPageController.selectedEpisode.episode,
                                  currentRoad:
                                      videoPageController.selectedEpisode.road);
                            },
                          ),
                          if (layout.hasSidePanel)
                            IconButton(
                              onPressed: _toggleSidePanel,
                              icon: const Icon(
                                Icons.menu_open_rounded,
                                color: Colors.white,
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                                showDebugLog
                                    ? Icons.bug_report
                                    : Icons.bug_report_outlined,
                                color: Colors.white),
                            onPressed: _toggleDebugConsole,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerLoading
              ? const SizedBox.shrink()
              : PlayerItem(
                  fillsWindow: layout.fillsWindow,
                  playerController: playerController,
                  videoPageController: videoPageController,
                  onToggleSidePanel:
                      layout.hasSidePanel ? _toggleSidePanel : null,
                  changeEpisode: changeEpisode,
                  onBackPressed: _onBackPressed,
                  keyboardFocus: keyboardFocus,
                  disableAnimations: disableAnimations,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                ),
        ),
      ],
    );
  }

  Widget get episodePanel => Observer(builder: (context) {
        final downloads = <String, DownloadEpisode>{};
        if (!videoPageController.isOfflineMode) {
          for (final record in downloadController.records) {
            if (record.bangumiId != videoPageController.bangumiItem.id ||
                record.pluginName != videoPageController.currentPlugin.name) {
              continue;
            }
            for (final episode in record.episodes.values) {
              if (episode.episodePageUrl.isNotEmpty) {
                downloads[episode.episodePageUrl] = episode;
              } else if (episode.road >= 0 &&
                  episode.road < videoPageController.roadList.length) {
                // Older records have no URL; only match within their own road.
                final urls = videoPageController.roadList[episode.road].data;
                if (episode.episodeNumber > 0 &&
                    episode.episodeNumber <= urls.length) {
                  downloads[urls[episode.episodeNumber - 1]] = episode;
                }
              }
            }
          }
        }
        return EpisodeSelectionPanel(
          key: _episodePanelKey,
          title: videoPageController.title,
          watchedEpisodes: _watchedEpisodes,
          roads: videoPageController.roadList,
          selectedRoad: videoPageController.selectedEpisode.road,
          selectedEpisode: videoPageController.selectedEpisode.episode,
          downloads: downloads,
          isOffline: videoPageController.isOfflineMode,
          isPlaying: playerController.playback.playing &&
              !playerController.playback.loading &&
              !videoPageController.loading,
          disableAnimations: disableAnimations,
          onEpisodeSelected: (episode, road) {
            if (episode == videoPageController.selectedEpisode.episode &&
                road == videoPageController.selectedEpisode.road) {
              return;
            }
            _closeSidePanel();
            changeEpisode(episode, currentRoad: road);
          },
          // Emby 的内容下载不了：下载链路要的是能被 WebView 解析的页面地址，
          // 而 Emby 给的是直连流。传 null 会把选集面板里的下载按钮置灰。
          onDownload: videoPageController.isEmbyMode
              ? null
              : (road) => showAdaptiveBottomSheet<void>(
                    context: context,
                    builder: (context) => DownloadEpisodeSheet(
                      road: road,
                      videoPageController: videoPageController,
                    ),
                  ),
        );
      });

  Widget get tabBody {
    final colors = Theme.of(context).colorScheme;
    final int episodeNum = videoPageController.commentsEpisode;

    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayerContentTabs(
            controller: tabController,
            onEpisodesSelected: _revealCurrentEpisode,
          ),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                episodePanel,
                EpisodeCommentsSheet(
                  episode: episodeNum,
                  selection: videoPageController.selectedEpisode,
                  videoPageController: videoPageController,
                ),
                SyncPlayRoomPanel(
                  playerController: playerController,
                  episodeCount: _currentRoadEpisodeCount,
                  onChangeEpisode: (episode) => changeEpisode(
                    episode,
                    currentRoad: videoPageController.selectedEpisode.road,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
