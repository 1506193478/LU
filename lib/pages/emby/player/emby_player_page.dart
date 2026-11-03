import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/pages/emby/player/emby_player_panels.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/utils/motion.dart';

/// Emby 独立播放器。
///
/// 界面照 Rex 的 `RexPlayerUIKit` 那套还原，不是 Material 默认控件：
///
///   * 顶部栏（返回 / 标题 / 更多）—— `PlayerControlsView`
///   * 上下两道渐变遮罩 —— `PlayerChromeGradientView`
///   * 中央三大键（快退 10 / 播放暂停 / 快进 10）—— `PlayerControlsView`
///   * 底部时间 + 进度条 + 工具行 —— `PlayerControlsView` + `PlayerBottomPickerView`
///   * 手势反馈浮层 —— `PlayerInteractionHUDView`
///   * 缓冲指示 —— `PlayerBufferingIndicatorView`
///   * 播放状态角标 —— `PlayerPlaybackStatusView`
///   * 锁定 —— `player.action.lock_controls`
///
/// 桌面和移动同一套控件，行为分开：
///   * 桌面：鼠标移动唤出、隐藏时收起指针、键盘快捷键、双击全屏、窗口全屏
///   * 移动：点击唤出、双击两侧快进、横向拖动 seek、右侧上下调音量、左侧上下调亮度
class EmbyPlayerPage extends StatefulWidget {
  const EmbyPlayerPage({super.key, required this.launch});

  final EmbyPlaybackLaunch launch;

  @override
  State<EmbyPlayerPage> createState() => _EmbyPlayerPageState();
}

class _EmbyPlayerPageState extends State<EmbyPlayerPage> {
  late final EmbyPlayerController controller;
  final FocusNode _focusNode = FocusNode();

  bool _isDesktop = false;
  bool _windowFullscreen = false;

  /// 画面比例，索引对应 [buildEmbyAspectPanel] 里的四项。
  int _aspect = 0;

  // 进度条拖拽
  bool _dragging = false;
  Duration _dragPosition = Duration.zero;

  // 手势 HUD
  String _hudLabel = '';
  IconData? _hudIcon;
  Timer? _hudTimer;

  // ---- 手势 ----
  //
  // 这一版改成用 Listener 自己算，不再挂一堆 GestureDetector 回调：
  //   * GestureDetector 里 onScale 和 onHorizontalDrag 互斥，没法「双指缩放
  //     + 单指横滑」共存；
  //   * 单击 / 双击要自己控制判定窗口，否则单击永远慢 300ms；
  //   * 长按倍速和长按退出需要「按下多久」这个原始信息。
  EmbyGesturePrefs _gesture = EmbyGesturePrefs.current;

  /// 当前按着的手指（多指缩放要用）。
  final Map<int, Offset> _pointers = <int, Offset>{};

  Offset? _downPos;
  bool _moved = false;
  bool _horizontalActive = false;
  Duration _seekStart = Duration.zero;

  double _gestureStartVolume = 100;
  double _gestureStartBrightness = 1;
  bool _verticalIsVolume = true;
  bool _verticalActive = false;

  /// 进入播放器时读到的系统亮度，退出时要还回去——以前没还，整个 App
  /// 跟着变暗，下次进来起手就黑。
  double _lastBrightness = 1;
  double? _originalBrightness;

  Timer? _longPressTimer;
  bool _longPressActive = false;
  double _speedBeforeLongPress = 1;

  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  Timer? _singleTapTimer;

  // ---- 缩放 ----
  double _zoom = 1;
  Offset _zoomOffset = Offset.zero;
  double _zoomStartScale = 1;
  Offset _zoomStartOffset = Offset.zero;
  double? _pinchStartDistance;
  Offset? _pinchStartFocal;
  bool _pinchActive = false;
  DateTime _lastZoomHudAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- 换集 / 屏幕方向 ----
  String _lastItemId = '';
  bool _orientationApplied = false;
  bool _firstItem = true;

  @override
  void initState() {
    super.initState();
    _isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    controller = EmbyPlayerController(
      launch: widget.launch,
      shaderAssetService: inject<ShaderAssetService>(),
    );
    controller.start();
    _gesture = EmbyGesturePrefs.current;
    _lastItemId = controller.current?.id ?? '';
    if (!_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _readInitialBrightness();
      unawaited(_applyOrientation(EmbyDisplayPrefs.enter));
      _restoreZoom(_lastItemId);
    }
    controller.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _longPressTimer?.cancel();
    _singleTapTimer?.cancel();
    controller.removeListener(_onPlaybackChanged);
    if (_longPressActive) {
      unawaited(controller.setSpeed(_speedBeforeLongPress));
    }
    _saveZoom();
    if (!_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // 还原亮度 + 放开方向锁。少了这两行，退出播放器后整个 App 是暗的、
      // 而且可能卡在横屏。
      final original = _originalBrightness;
      if (original != null) unawaited(_applyBrightness(original));
      unawaited(SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]));
    }
    if (_windowFullscreen) {
      windowManager.setFullScreen(false);
    }
    _focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _readInitialBrightness() async {
    try {
      final value = await ScreenBrightnessPlatform.instance.application;
      _originalBrightness = value;
      _lastBrightness = value;
    } catch (_) {
      // 平台不支持（或 iOS 没给权限）就按 100% 起手，不要停在 0.5 那种
      // 「一进来就半黑」的状态。
      _lastBrightness = 1;
    }
  }

  /// 按偏好切换屏幕方向。桌面端不锁方向，直接返回。
  Future<void> _applyOrientation(EmbyOrientationMode mode) async {
    if (_isDesktop) return;
    final side = EmbyDisplayPrefs.side;
    final landscape = switch (side) {
      EmbyLandscapeSide.left => const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft
        ],
      EmbyLandscapeSide.right => const <DeviceOrientation>[
          DeviceOrientation.landscapeRight
        ],
      EmbyLandscapeSide.auto => const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
    };
    final List<DeviceOrientation>? target = switch (mode) {
      EmbyOrientationMode.keep => null,
      EmbyOrientationMode.landscape => landscape,
      EmbyOrientationMode.portrait => const <DeviceOrientation>[
          DeviceOrientation.portraitUp
        ],
      EmbyOrientationMode.auto => () {
          final w = controller.videoWidth;
          final h = controller.videoHeight;
          // 尺寸还没出来：等第一帧视频信息回来再决定（见 _onPlaybackChanged）。
          if (w <= 0 || h <= 0) return null;
          return w >= h ? landscape : const <DeviceOrientation>[
            DeviceOrientation.portraitUp
          ];
        }(),
    };
    if (target == null) return;
    try {
      await SystemChrome.setPreferredOrientations(target);
    } catch (_) {
      // 某些定制 ROM 会拒绝，忽略即可。
    }
  }

  /// 换集 / 首帧就绪时决定要不要重新应用方向。
  void _onPlaybackChanged() {
    if (!mounted) return;
    final id = controller.current?.id ?? '';
    if (id != _lastItemId) {
      _saveZoom();
      _lastItemId = id;
      if (!_isDesktop) _restoreZoom(id);
      _orientationApplied = false;
    }
    if (!_isDesktop &&
        !_orientationApplied &&
        controller.videoWidth > 0 &&
        controller.videoHeight > 0) {
      _orientationApplied = true;
      unawaited(_applyOrientation(
        _firstItem ? EmbyDisplayPrefs.enter : EmbyDisplayPrefs.onSwitch,
      ));
      _firstItem = false;
    }
  }

  void _restoreZoom(String itemId) {
    final value = _gesture.rememberZoom ? EmbyZoomMemory.of(itemId) : 1.0;
    if (!mounted) return;
    setState(() {
      _zoom = value;
      _zoomOffset = Offset.zero;
    });
  }

  void _saveZoom() {
    if (!_gesture.rememberZoom) return;
    unawaited(EmbyZoomMemory.put(_lastItemId, _zoom));
  }

  Offset _clampZoomOffset(Offset value, double zoom, Size size) {
    final maxX = size.width * (zoom - 1) / 2;
    final maxY = size.height * (zoom - 1) / 2;
    return Offset(
      value.dx.clamp(-maxX, maxX),
      value.dy.clamp(-maxY, maxY),
    );
  }

  // ------------------------------------------------------------ 交互

  void _toggleControls() {
    if (controller.locked) return;
    controller.toggleControls();
    _focusNode.requestFocus();
  }

  Future<void> _toggleFullscreen() async {
    if (_isDesktop) {
      setState(() => _windowFullscreen = !_windowFullscreen);
      await windowManager.setFullScreen(_windowFullscreen);
      return;
    }
    final isImmersive =
        MediaQuery.of(context).orientation == Orientation.landscape;
    await SystemChrome.setEnabledSystemUIMode(
      isImmersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _handleKey(KeyEvent event) async {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      await controller.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      await _seekBy(const Duration(seconds: -10), label: '快退 10 秒');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      await _seekBy(const Duration(seconds: 10), label: '快进 10 秒');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      await controller.nudgeVolume(5);
      _showHud('音量 ${controller.volume.round()}%', icon: Icons.volume_up_rounded);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      await controller.nudgeVolume(-5);
      _showHud('音量 ${controller.volume.round()}%', icon: Icons.volume_down_rounded);
    } else if (key == LogicalKeyboardKey.keyF) {
      await _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyL) {
      controller.toggleLock();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_windowFullscreen) {
        setState(() => _windowFullscreen = false);
        await windowManager.setFullScreen(false);
      } else if (controller.locked) {
        controller.toggleLock();
      } else if (mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _seekBy(Duration delta, {String? label}) async {
    final target = controller.position + delta;
    await controller.seek(target);
    controller.setControlsVisible(true);
    if (label != null) {
      _showHud(label, icon: delta.isNegative
          ? Icons.replay_10_rounded
          : Icons.forward_10_rounded);
    }
  }

  void _showHud(String label, {IconData? icon}) {
    _hudTimer?.cancel();
    setState(() {
      _hudLabel = label;
      _hudIcon = icon;
    });
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _hudLabel = '';
        _hudIcon = null;
      });
    });
  }

  // ------------------------------------------------------------ 面板

  void _pauseAutoHide() {
    controller.setControlsVisible(true);
  }

  Future<void> _openMore() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '更多',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyMorePanel(
        ctx,
        EmbyMorePanelActions(
          decodeLabel: controller.decodeMode.label,
          playbackModeLabel: controller.playbackMode.label,
          sleepLabel: embySleepLabel(controller.sleepMode),
          background: controller.backgroundAudio,
          progressAlways: controller.progressAlwaysVisible,
          onDecode: () {
            Navigator.of(ctx).pop();
            _openDecode();
          },
          onPlaybackMode: () {
            Navigator.of(ctx).pop();
            _openPlaybackMode();
          },
          onIntroOutro: () {
            Navigator.of(ctx).pop();
            _openIntroOutro();
          },
          onSleep: () {
            Navigator.of(ctx).pop();
            _openSleep();
          },
          onInfo: () {
            Navigator.of(ctx).pop();
            _openInfo();
          },
          onBackground: () {
            controller.setBackgroundAudio(!controller.backgroundAudio);
            Navigator.of(ctx).pop();
          },
          onProgress: () {
            controller.setProgressAlwaysVisible(!controller.progressAlwaysVisible);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openDecode() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '解码',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyDecodePanel(
        current: controller.decodeMode,
        onSelect: (mode) {
          controller.setDecodeMode(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openPlaybackMode() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '顺序播放',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyPlaybackModePanel(
        current: controller.playbackMode,
        onSelect: (mode) {
          controller.setPlaybackMode(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openIntroOutro() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '片头片尾',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyIntroOutroPanel(
        introSkip: controller.introSkip,
        outroSkip: controller.outroSkip,
        onMarkOutro: () {
          controller.markOutroAt(controller.position);
          Navigator.of(ctx).pop();
        },
        onIntroChanged: controller.setIntroSkip,
        onOutroChanged: controller.setOutroSkip,
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openSleep() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '定时关闭',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbySleepPanel(
        current: controller.sleepMode,
        onSelect: (mode) {
          controller.setSleepTimer(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openChapters() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '章节',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyChapterPanel(
        chapters: controller.chapters,
        current: controller.position,
        onSelect: (start) {
          Navigator.of(ctx).pop();
          controller.seek(start);
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openEpisodes() async {
    _pauseAutoHide();
    final int index = controller.index;
    await showEmbyPlayerSheet<void>(
      context,
      title: '选集',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyEpisodePanel(
        ctx,
        episodes: widget.launch.episodes,
        currentIndex: controller.index,
        onSelect: (i) {
          Navigator.of(ctx).pop();
          if (i != index) controller.openIndex(i);
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openSpeed() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '自定义',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbySpeedPanel(
        current: controller.speed,
        onSelect: (value) {
          controller.setSpeed(value);
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openAudio() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '音轨',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyAudioPanel(
        tracks: controller.audioTracks,
        current: controller.currentAudio,
        gain: controller.audioGain,
        onDisableAudio: () {
          controller.selectAudio(AudioTrack.no());
          Navigator.of(ctx).pop();
        },
        onSelect: (track) {
          controller.selectAudio(track);
          Navigator.of(ctx).pop();
        },
        onEnhance: () {
          Navigator.of(ctx).pop();
          _openGain();
        },
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openGain() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '音频增强',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyGainPanel(
        current: controller.audioGain,
        onSelect: (gain) {
          controller.setAudioGain(gain);
          Navigator.of(ctx).pop();
        },
      ),
    );
    _pauseAutoHide();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openSubtitle() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '字幕',
      isDesktop: _isDesktop,
      hideHeaderWhenWide: true,
      builder: (ctx) => buildEmbySubtitlePanel(
        tracks: controller.allSubtitleTracks,
        current: controller.currentSubtitle,
        secondary: controller.secondarySubtitle,
        onSelect: (track) {
          controller.selectSubtitle(track);
          Navigator.of(ctx).pop();
        },
        onSelectSecondary: (track) {
          controller.selectSecondarySubtitle(track);
        },
        onSettings: () {
          Navigator.of(ctx).pop();
          _openSubtitleSettings();
        },
        onDisableForever: () {
          controller.disableSubtitleForever();
          Navigator.of(ctx).pop();
          _toast('这一集不再自动显示字幕');
        },
        onSearch: () {
          Navigator.of(ctx).pop();
          _openSubtitleSearch();
        },
        onImport: () {
          Navigator.of(ctx).pop();
          _importSubtitle();
        },
      ),
    );
    _pauseAutoHide();
  }

  /// 本地导入：挑一个字幕文件，立刻挂到当前这一条上。
  Future<void> _importSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'ttml'],
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final ok = await controller.importSubtitle(path);
      _toast(ok ? '字幕已挂上' : '这个文件没能加载');
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  /// 字幕搜索：走服务端配好的字幕插件（OpenSubtitles 之类）。
  Future<void> _openSubtitleSearch() async {
    final language = EmbyStreamPrefs.subtitleLanguage;
    List<EmbyRemoteSubtitle> results = const [];
    String error = '';
    var loading = true;

    await showEmbyPlayerSheet<void>(
      context,
      title: '字幕搜索',
      isDesktop: _isDesktop,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (loading) {
            unawaited(() async {
              try {
                final found = await controller
                    .searchRemoteSubtitles(language.isEmpty ? 'chi' : language);
                if (!ctx.mounted) return;
                setSheetState(() {
                  results = found;
                  loading = false;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setSheetState(() {
                  error = '$e';
                  loading = false;
                });
              }
            }());
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (error.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text(
                '搜索失败：$error\n\n'
                '字幕搜索用的是服务器上的字幕插件。到 Emby 服务端后台装好 '
                'OpenSubtitles 插件、配好账号之后再试。',
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            );
          }
          if (results.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text(
                '服务器没找到可用的字幕。\n'
                '可以换个语言再试，或者用「本地导入」挂自己的字幕文件。',
                style: TextStyle(fontSize: 13, height: 1.6, color: _hintInk(ctx)),
              ),
            );
          }
          return Column(
            children: [
              for (final sub in results)
                ListTile(
                  dense: true,
                  title: Text(
                    sub.name.isEmpty ? '未命名字幕' : sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    [
                      if (sub.language.isNotEmpty) sub.language,
                      if (sub.format.isNotEmpty) sub.format.toUpperCase(),
                      if (sub.downloadCount > 0) '下载 ${sub.downloadCount}',
                      if (sub.isHashMatch) '匹配片源',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: _hintInk(ctx)),
                  ),
                  trailing: const Icon(Icons.download_rounded, size: 18),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      final ok = await controller.applyRemoteSubtitle(sub);
                      _toast(ok ? '字幕已下载并启用' : '下载了但没能挂上，重开这一集试试');
                    } catch (e) {
                      _toast('下载失败：$e');
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
    _pauseAutoHide();
  }

  Color _hintInk(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9A9AA2)
          : const Color(0xFF8A8A90);

  Future<void> _openSubtitleSettings() async {
    _pauseAutoHide();
    // 面板要跟着 +/- 实时刷新，所以用 StatefulBuilder 拿一份本地值：
    // 原来直接把 controller.subtitleSettings 传进去，点一次不会重建，
    // 显示不动、而且每次都基于同一个旧值算——点十下也还是 +0.5s，
    // 表现出来就是「字幕设置没接入」。
    var current = controller.subtitleSettings;
    await showEmbyPlayerSheet<void>(
      context,
      title: '字幕设置',
      isDesktop: _isDesktop,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => buildEmbySubtitleSettingsPanel(
          settings: current,
          subtitleActive: (controller.currentSubtitle?.id ?? 'no') != 'no',
          onChanged: (next) {
            current = next;
            controller.setSubtitleSettings(next);
            setSheetState(() {});
          },
          onReset: () {
            current = const EmbySubtitleSettings();
            controller.setSubtitleSettings(current);
            setSheetState(() {});
          },
        ),
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openAspect() async {
    _pauseAutoHide();
    await showEmbyPlayerSheet<void>(
      context,
      title: '画面比例',
      isDesktop: _isDesktop,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: buildEmbyAspectPanel(
          current: _aspect,
          onSelect: (value) {
            setState(() => _aspect = value);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
    _pauseAutoHide();
  }

  Future<void> _openInfo() async {
    _pauseAutoHide();
    final item = controller.current;
    await showEmbyPlayerSheet<void>(
      context,
      title: '媒体信息',
      isDesktop: _isDesktop,
      builder: (ctx) => buildEmbyInfoPanel(
        title: item?.seriesName?.trim().isNotEmpty == true
            ? item!.seriesName!.trim()
            : (item?.name ?? ''),
        subtitle: item == null
            ? ''
            : [
                if (controller.episodeLabel.isNotEmpty) controller.episodeLabel,
                if (item.isEpisode) item.name,
              ].join(' · '),
        resolution: controller.resolutionLabel,
        decode: controller.decodeLabel,
        modeLabel: controller.playbackMode.label,
        sleepLabel: embySleepLabel(controller.sleepMode),
        chapterCount: controller.chapters.length,
        position: controller.position,
        duration: controller.duration,
        buffer: controller.buffer,
        speed: controller.speed,
        streamUrl: controller.streamUrl,
        streamMode: controller.streamModeLabel,
      ),
    );
    _pauseAutoHide();
  }

  String _currentSubtitleLabel() {
    final track = controller.currentSubtitle;
    if (track == null || track.id == 'no') return '';
    final title = track.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return track.language ?? '已开启';
  }

  static String _speedText(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  }

  BoxFit get _videoBoxFit =>
      embyAspectOptions[_aspect.clamp(0, embyAspectOptions.length - 1)].fit;
  double? get _videoAspect =>
      embyAspectOptions[_aspect.clamp(0, embyAspectOptions.length - 1)].ratio;

  // ------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          _handleKey(event);
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final bool show = controller.controlsVisible || !controller.playing;
            return MouseRegion(
              cursor: show ? SystemMouseCursors.basic : SystemMouseCursors.none,
              onHover: (_) {
                if (!_isDesktop) return;
                if (!controller.controlsVisible) {
                  controller.setControlsVisible(true);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                    // 手势只铺在**画面**这一层：控件（按钮 / 进度条）在它上面，
                    // 点按钮不会顺带把控件收起来。
                    _buildGestureSurface(),
                    if (show && !controller.loading && controller.error.isEmpty)
                      _ChromeGradient(visible: true),
                    if (controller.loading) _buildLoading(),
                    if (controller.error.isNotEmpty) _buildError(),
                    if (!controller.loading &&
                        controller.buffering &&
                        controller.error.isEmpty &&
                        !controller.completed)
                      _buildBuffering(),
                    if (show && !controller.loading && controller.error.isEmpty) ...[
                      _buildTopBar(),
                      _buildCenterControls(),
                      _buildBottomBar(),
                    ],
                    if (controller.locked) _buildLockedBadge(),
                    if (_hudLabel.isNotEmpty) _buildHud(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 字幕样式：必须从这里传给 `Video`。
  ///
  /// media_kit 的字幕是 **Flutter 层画的**（`SubtitleView`），不是 libass
  /// 直接叠在画面上。不传配置时它用默认样式，里面写着
  /// `backgroundColor: Color(0xaa000000)`——用户看到的那条「黑边」就是它。
  /// 同理，面板里的字号/位置/透明度改的是 mpv 的 `sub-*` 属性，对 Flutter
  /// 画的这一层没有任何作用，所以「怎么改都没有用」。
  ///
  /// 这里按 [EmbySubtitleSettings] 现算一份：透明底 + 一圈柔和描边（比黑底
  /// 不挡画面，白字压在亮背景上也读得清），字号走缩放，整体透明度走 alpha，
  /// 底部留白走垂直偏移。
  SubtitleViewConfiguration _subtitleViewConfig() {
    final s = controller.subtitleSettings;
    final double opacity = s.opacity.clamp(0.0, 1.0);
    final double scale = s.scale.clamp(0.5, 2.0);
    final Color ink = Colors.white.withValues(alpha: opacity);
    final Color halo = Colors.black.withValues(alpha: 0.62 * opacity);
    const List<Offset> ring = [
      Offset(-1.6, -1.6),
      Offset(1.6, -1.6),
      Offset(-1.6, 1.6),
      Offset(1.6, 1.6),
      Offset(0, -2.2),
      Offset(0, 2.2),
      Offset(-2.2, 0),
      Offset(2.2, 0),
    ];
    return SubtitleViewConfiguration(
      style: TextStyle(
        color: ink,
        fontSize: 30 * scale,
        height: 1.26,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        // 关键：透明底。留这一行是为了防止以后有人又退回默认样式。
        backgroundColor: Colors.transparent,
        shadows: [
          for (final o in ring)
            Shadow(offset: o, blurRadius: 2.6, color: halo),
        ],
      ),
      textAlign: TextAlign.center,
      // 垂直偏移 0~100 当成「往上抬多少」：0 贴底，100 抬到画面中下部。
      padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + s.verticalOffset * 2.6),
    );
  }

  /// 画面这一层：桌面端保留原来的「单击显隐 / 双击全屏」，移动端走自己的
  /// 指针手势（见 `_onPointerDown` 一带）。
  Widget _buildGestureSurface() {
    final surface = _buildVideoSurface();
    if (_isDesktop) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTap: _toggleFullscreen,
        child: surface,
      );
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: surface,
    );
  }

  Widget _buildVideoSurface() {
    final videoController = controller.videoController;
    if (videoController == null) {
      return const ColoredBox(color: Colors.black);
    }
    final Widget child = Video(
      controller: videoController,
      controls: NoVideoControls,
      fit: _videoBoxFit,
      fill: Colors.black,
      subtitleViewConfiguration: _subtitleViewConfig(),
    );
    Widget output = child;
    final ratio = _videoAspect;
    if (ratio != null) {
      // 4:3 / 16:9 这类具体比例：把画面裁成该比例居中显示。
      output = Center(
        child: AspectRatio(aspectRatio: ratio, child: child),
      );
    }
    if (_zoom > 1.001) {
      // 双指放大：先缩放再平移，裁掉越界的部分，不然会画到控制条上去。
      output = ClipRect(
        child: Transform.translate(
          offset: _zoomOffset,
          child: Transform.scale(scale: _zoom, child: output),
        ),
      );
    }
    return output;
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    return Center(
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 34,
                  color: Colors.white54,
                ),
                const SizedBox(height: 14),
                const Text(
                  '暂时无法播放',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PillAction(
                      label: '返回',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    _PillAction(
                      label: '重试',
                      filled: true,
                      onTap: controller.retry,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 顶栏

  Widget _buildTopBar() {
    final item = controller.current;
    final series = item?.seriesName?.trim();
    final title = (series != null && series.isNotEmpty)
        ? series
        : (item?.name ?? widget.launch.title);
    final sub = item == null
        ? ''
        : [
            if (controller.episodeLabel.isNotEmpty) controller.episodeLabel,
            if (item.isEpisode) item.name,
          ].join(' · ');

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _isDesktop ? 20 : 12,
            _isDesktop ? 14 : 8,
            _isDesktop ? 20 : 12,
            8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 短按先收起控件（视频里那颗按钮的手感），长按才真的退出。
              // 不想这样的话可以在「播放手势 → 长按返回键退出播放器」关掉。
              _CircleAction(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 17,
                onTap: _gesture.longPressExit
                    ? _toggleControls
                    : () => Navigator.of(context).maybePop(),
                onLongPress: _gesture.longPressExit
                    ? () => Navigator.of(context).maybePop()
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.launch.episodes.length > 1)
                _CircleAction(
                  icon: Icons.menu_book_rounded,
                  iconSize: 17,
                  onTap: _openEpisodes,
                ),
              if (widget.launch.episodes.length > 1)
                const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.info_outline_rounded,
                iconSize: 17,
                onTap: _openInfo,
              ),
              const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.lock_open_rounded,
                iconSize: 17,
                onTap: controller.toggleLock,
              ),
              const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.more_horiz_rounded,
                iconSize: 19,
                onTap: _openMore,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 中央

  Widget _buildCenterControls() {
    final bool canPrev = controller.hasPrevious;
    final bool canNext = controller.hasNext;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CenterAction(
            icon: Icons.replay_10_rounded,
            size: 46,
            onTap: () => _seekBy(const Duration(seconds: -10), label: '快退 10 秒'),
          ),
          const SizedBox(width: 28),
          _PlayPauseButton(
            playing: controller.playing,
            onTap: controller.togglePlay,
          ),
          const SizedBox(width: 28),
          _CenterAction(
            icon: Icons.forward_10_rounded,
            size: 46,
            onTap: () => _seekBy(const Duration(seconds: 10), label: '快进 10 秒'),
          ),
          if (canPrev || canNext) ...[
            const SizedBox(width: 22),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CircleAction(
                  icon: Icons.skip_next_rounded,
                  iconSize: 18,
                  size: 38,
                  enabled: canNext,
                  onTap: canNext ? controller.playNext : null,
                ),
                const SizedBox(height: 8),
                _CircleAction(
                  icon: Icons.skip_previous_rounded,
                  iconSize: 18,
                  size: 38,
                  enabled: canPrev,
                  onTap: canPrev ? controller.playPrevious : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ 底栏

  Widget _buildBottomBar() {
    final Duration total = controller.duration;
    final Duration shown = _dragging ? _dragPosition : controller.position;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _isDesktop ? 22 : 14,
            0,
            _isDesktop ? 22 : 14,
            _isDesktop ? 18 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    _fmt(shown),
                    style: _timeStyle(Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '/',
                    style: _timeStyle(Colors.white.withValues(alpha: 0.35)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    total == Duration.zero ? '--:--' : _fmt(total),
                    style: _timeStyle(Colors.white.withValues(alpha: 0.62)),
                  ),
                  const Spacer(),
                  _StatusChip(
                    label: controller.decodeLabel,
                    value: controller.resolutionLabel,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _RexSeekBar(
                position: shown,
                duration: total,
                buffer: controller.buffer,
                // 「拖动进度条」关掉后只显示不让拖，防止横屏误触。
                enabled: total > Duration.zero && _gesture.dragProgressBar,
                onDragStart: () {
                  setState(() {
                    _dragging = true;
                    _dragPosition = controller.position;
                  });
                  _pauseAutoHide();
                },
                onDragUpdate: (value) {
                  setState(() => _dragPosition = value);
                  _showHud(_fmt(value), icon: Icons.fast_forward_rounded);
                },
                onDragEnd: (value) {
                  controller.seek(value);
                  setState(() => _dragging = false);
                  if (_gesture.hapticProgress) KazumiHaptics.select();
                  _pauseAutoHide();
                },
                onTapSeek: (value) {
                  controller.seek(value);
                  _pauseAutoHide();
                },
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ToolChip(
                      icon: Icons.speed_rounded,
                      label: '${_speedText(controller.speed)}×',
                      onTap: _openSpeed,
                    ),
                    _ToolChip(
                      icon: Icons.graphic_eq_rounded,
                      label: '音轨',
                      onTap: _openAudio,
                    ),
                    _ToolChip(
                      icon: Icons.subtitles_outlined,
                      label: _currentSubtitleLabel().isEmpty
                          ? '字幕'
                          : _currentSubtitleLabel(),
                      selected: _currentSubtitleLabel().isNotEmpty,
                      onTap: _openSubtitle,
                    ),
                    if (widget.launch.episodes.length > 1)
                      _ToolChip(
                        icon: Icons.video_library_outlined,
                        label: '选集',
                        onTap: _openEpisodes,
                      ),
                    _ToolChip(
                      icon: Icons.aspect_ratio_rounded,
                      label: embyAspectOptions[_aspect.clamp(0, embyAspectOptions.length - 1)].label,
                      onTap: _openAspect,
                    ),
                    if (controller.chapters.isNotEmpty)
                      _ToolChip(
                        icon: Icons.bookmark_outline_rounded,
                        label: '章节',
                        onTap: _openChapters,
                      ),
                    _ToolChip(
                      icon: Icons.more_horiz_rounded,
                      label: '更多',
                      onTap: _openMore,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextStyle _timeStyle(Color color) => TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _buildLockedBadge() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: GestureDetector(
            onTap: controller.toggleLock,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
                  SizedBox(width: 6),
                  Text(
                    '已锁定，点此解锁',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _hudLabel.isEmpty ? 0 : 1,
            duration: const Duration(milliseconds: 140),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hudIcon != null)
                    Icon(_hudIcon, size: 22, color: Colors.white),
                  if (_hudIcon != null) const SizedBox(height: 6),
                  Text(
                    _hudLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 手势

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _downPos = event.localPosition;
      _moved = false;
      _horizontalActive = false;
      _verticalActive = false;
      _longPressTimer?.cancel();
      if (_gesture.longPressSpeed && !controller.locked) {
        _longPressTimer = Timer(const Duration(milliseconds: 460), () {
          if (!mounted || _moved) return;
          _longPressActive = true;
          _speedBeforeLongPress = controller.speed;
          unawaited(controller.setSpeed(_gesture.longPressRate));
          if (_gesture.hapticLongPress) KazumiHaptics.select();
          _showHud(
            '${_speedText(_gesture.longPressRate)}× 倍速中',
            icon: Icons.fast_forward_rounded,
          );
        });
      }
    } else if (_pointers.length == 2) {
      // 第二根手指落下：取消长按（并在按着时先恢复原速），进入缩放。
      _longPressTimer?.cancel();
      if (_longPressActive) {
        _longPressActive = false;
        unawaited(controller.setSpeed(_speedBeforeLongPress));
      }
      if (_gesture.pinchZoom) {
        _pinchStartDistance = null;
        _pinchStartFocal = null;
        _zoomStartScale = _zoom;
        _zoomStartOffset = _zoomOffset;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final size = MediaQuery.sizeOf(context);

    // 双指：缩放 + 拖动画面。
    if (_pointers.length >= 2) {
      if (!_gesture.pinchZoom) return;
      // 双指一旦动过，这次就不能再判成「点击」——否则松开最后一根手指
      // 会顺带把控件收起来。
      _pinchActive = true;
      _moved = true;
      final pts = _pointers.values.toList();
      final focal = (pts[0] + pts[1]) / 2;
      final dist = (pts[0] - pts[1]).distance;
      _pinchStartDistance ??= dist <= 0 ? 1 : dist;
      _pinchStartFocal ??= focal;
      final base = _pinchStartDistance!;
      final ratio = dist / (base <= 0 ? 1 : base);
      final next = (_zoomStartScale * ratio).clamp(1.0, 4.0);
      final moved = focal - _pinchStartFocal!;
      setState(() {
        _zoom = next;
        _zoomOffset = _clampZoomOffset(_zoomStartOffset + moved, next, size);
      });
      // HUD 限流 120ms：每帧都刷会把主线程占满，缩放反而发涩。
      final now = DateTime.now();
      if (next > 1.02 &&
          now.difference(_lastZoomHudAt) > const Duration(milliseconds: 120)) {
        _lastZoomHudAt = now;
        _showHud('缩放 ${next.toStringAsFixed(1)}×',
            icon: Icons.zoom_out_map_rounded);
      }
      return;
    }

    final down = _downPos;
    if (down == null) return;
    final delta = event.localPosition - down;

    // 超过阈值才锁方向：太小的话点一下就误判成滑动。
    if (!_moved && delta.distance > 12) {
      _moved = true;
      _longPressTimer?.cancel();
      final horizontal = delta.dx.abs() > delta.dy.abs();
      _horizontalActive =
          horizontal && _gesture.seekByDrag && !controller.locked;
      _verticalActive = !horizontal &&
          (_gesture.brightness || _gesture.volume) &&
          !controller.locked;
      _verticalIsVolume = down.dx > size.width * 0.5;
      _gestureStartVolume = controller.baseVolume;
      _gestureStartBrightness = _lastBrightness;
      _seekStart = controller.position;
      if (_horizontalActive) _pauseAutoHide();
    }
    if (!_moved) return;

    if (_horizontalActive) {
      final total = controller.duration;
      if (total <= Duration.zero) return;
      final target = _seekStart +
          Duration(
            microseconds:
                (delta.dx / size.width * total.inMicroseconds).round(),
          );
      final clamped = target < Duration.zero
          ? Duration.zero
          : (target > total ? total : target);
      setState(() {
        _dragging = true;
        _dragPosition = clamped;
      });
      _showHud(_fmt(clamped), icon: Icons.fast_forward_rounded);
      return;
    }

    if (_verticalActive) {
      final frac = -delta.dy / (size.height * 0.6);
      if (_verticalIsVolume) {
        // 用 baseVolume（不含音频增强）算，否则开了 300% 增益时
        // controller.volume 是 300，随手一滑就被 clamp 到 100。
        final next = (_gestureStartVolume + frac * 100).clamp(0.0, 100.0);
        unawaited(controller.setVolume(next));
        _showHud(
          '音量 ${next.round()}%',
          icon: next <= 0.5
              ? Icons.volume_off_rounded
              : (next < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded),
        );
      } else {
        final next = (_gestureStartBrightness + frac).clamp(0.0, 1.0);
        _lastBrightness = next;
        unawaited(_applyBrightness(next));
        _showHud(
          '亮度 ${(next * 100).round()}%',
          icon: Icons.brightness_6_rounded,
        );
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;

    if (_pinchActive) {
      _pinchActive = false;
      // 开了「记住缩放大小」就在松手这一刻落盘，别等退出页面——中途被杀
      // 进程就白调了。
      if (_gesture.rememberZoom) _saveZoom();
      _moved = false;
      _pauseAutoHide();
      return;
    }

    _longPressTimer?.cancel();
    if (_longPressActive) {
      _longPressActive = false;
      unawaited(controller.setSpeed(_speedBeforeLongPress));
      _pauseAutoHide();
      return;
    }

    if (_moved) {
      if (_horizontalActive) {
        unawaited(controller.seek(_dragPosition));
        if (_gesture.hapticSeek) KazumiHaptics.select();
      }
      _horizontalActive = false;
      _verticalActive = false;
      if (_dragging) setState(() => _dragging = false);
      _pauseAutoHide();
      return;
    }

    // 单击 / 双击
    final pos = event.localPosition;
    final now = DateTime.now();
    final lastAt = _lastTapAt;
    final lastPos = _lastTapPos;
    final isDouble = lastAt != null &&
        now.difference(lastAt) < const Duration(milliseconds: 320) &&
        lastPos != null &&
        (lastPos - pos).distance < 56;
    if (isDouble) {
      _lastTapAt = null;
      _singleTapTimer?.cancel();
      _handleDoubleTap(pos);
      return;
    }
    _lastTapAt = now;
    _lastTapPos = pos;
    _singleTapTimer?.cancel();
    // 开了双击功能就必须等一个窗口，否则单点会先闪一下控件再处理双击。
    if (_gesture.doubleTapSeek || _gesture.doubleTapPlayPause) {
      _singleTapTimer = Timer(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        if (_gesture.tapToggleControls) _toggleControls();
      });
    } else if (_gesture.tapToggleControls) {
      _toggleControls();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _longPressTimer?.cancel();
    if (_longPressActive) {
      _longPressActive = false;
      unawaited(controller.setSpeed(_speedBeforeLongPress));
    }
    if (_moved) {
      _horizontalActive = false;
      _verticalActive = false;
      if (_dragging) setState(() => _dragging = false);
    }
    if (_pointers.isEmpty) {
      _moved = false;
      _downPos = null;
    }
  }

  void _handleDoubleTap(Offset pos) {
    if (controller.locked) return;
    final size = MediaQuery.sizeOf(context);
    // 放大状态下双击先复位——各家播放器都这么约定，比跳进度更符合预期。
    if (_gesture.pinchZoom && _zoom > 1.01) {
      setState(() {
        _zoom = 1;
        _zoomOffset = Offset.zero;
      });
      if (_gesture.rememberZoom) unawaited(EmbyZoomMemory.put(_lastItemId, 1));
      _showHud('已复位', icon: Icons.zoom_out_map_rounded);
      return;
    }
    final x = pos.dx / size.width;
    final seconds = _gesture.doubleTapSeconds;
    if (x < 0.33 && _gesture.doubleTapSeek) {
      unawaited(_seekBy(Duration(seconds: -seconds), label: '快退 $seconds 秒'));
      if (_gesture.hapticSeek) KazumiHaptics.select();
    } else if (x > 0.67 && _gesture.doubleTapSeek) {
      unawaited(_seekBy(Duration(seconds: seconds), label: '快进 $seconds 秒'));
      if (_gesture.hapticSeek) KazumiHaptics.select();
    } else if (_gesture.doubleTapPlayPause) {
      unawaited(controller.togglePlay());
    } else if (_gesture.tapToggleControls) {
      _toggleControls();
    }
  }

  Future<void> _applyBrightness(double value) async {
    try {
      await ScreenBrightnessPlatform.instance
          .setApplicationScreenBrightness(value);
    } catch (_) {
      // 平台不支持就算了，不打断播放。
    }
  }

  static String _fmt(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    final String mm = m.toString().padLeft(2, '0');
    final String ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

// ---------------------------------------------------------------- 小部件

/// 上下两道渐变遮罩（Rex 的 `PlayerChromeGradientView`）。
class _ChromeGradient extends StatelessWidget {
  const _ChromeGradient({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            Container(
              height: 132,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 208,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xC7000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.iconSize = 20,
    this.size = 38,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double iconSize;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.35),
          ),
        ),
      ),
    );
  }
}

class _CenterAction extends StatelessWidget {
  const _CenterAction({
    required this.icon,
    required this.onTap,
    this.size = 46,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      scale: 0.9,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size, color: Colors.white),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(playing),
              size: 34,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.black : Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右上角的解码 / 分辨率小标（Rex 的 `PlayerPlaybackStatusView`）。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = value.isEmpty ? label : '$label · $value';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 按压缩放（Rex 的 `PressScale`）。
class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 长按（用来做「长按返回键退出播放器」这种二次确认的手势）。
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 自绘进度条。
///
/// 比 Material 的 Slider 准：命中区 26px、拖动时条子变粗、松手才 seek。
class _RexSeekBar extends StatefulWidget {
  const _RexSeekBar({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.enabled,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTapSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool enabled;
  final VoidCallback onDragStart;
  final ValueChanged<Duration> onDragUpdate;
  final ValueChanged<Duration> onDragEnd;
  final ValueChanged<Duration> onTapSeek;

  @override
  State<_RexSeekBar> createState() => _RexSeekBarState();
}

class _RexSeekBarState extends State<_RexSeekBar> {
  bool _active = false;

  /// 拖拽过程中的最新值。父组件是通过 setState 回传的，可能比手势慢一帧，
  /// 松手时用这个值才准。
  Duration _lastDrag = Duration.zero;

  Duration _positionFor(double dx, double width) {
    if (width <= 0 || widget.duration <= Duration.zero) return Duration.zero;
    final ratio = (dx / width).clamp(0.0, 1.0);
    return Duration(
      microseconds: (widget.duration.inMicroseconds * ratio).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double total = widget.duration.inMicroseconds.toDouble();
    final double progress =
        total <= 0 ? 0 : (widget.position.inMicroseconds / total).clamp(0.0, 1.0);
    final double buffered =
        total <= 0 ? 0 : (widget.buffer.inMicroseconds / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (d) => widget.onTapSeek(_positionFor(d.localPosition.dx, width))
                : null,
            onHorizontalDragStart: widget.enabled
                ? (_) {
                    setState(() => _active = true);
                    _lastDrag = widget.position;
                    widget.onDragStart();
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) {
                    final value = _positionFor(d.localPosition.dx, width);
                    _lastDrag = value;
                    widget.onDragUpdate(value);
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (_) {
                    setState(() => _active = false);
                    widget.onDragEnd(_lastDrag);
                  }
                : null,
            onHorizontalDragCancel: () => setState(() => _active = false),
            child: SizedBox(
              height: 26,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  height: _active ? 6 : 3.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: buffered,
                            child: ColoredBox(
                              color: Colors.white.withValues(alpha: 0.38),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
