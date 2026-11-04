import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/pages/emby/player/emby_player_panels.dart';
import 'package:XL/pages/emby/player/emby_player_popover.dart';
import 'package:XL/pages/emby/player/emby_subtitle_search_page.dart';
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

class _EmbyPlayerPageState extends State<EmbyPlayerPage>
    with SingleTickerProviderStateMixin {
  late final EmbyPlayerController controller;
  final FocusNode _focusNode = FocusNode();

  /// 控制层的统一显隐动画。
  ///
  /// 以前是 `if (show) …` 直接增删 widget——顶栏、中央键、底栏同一帧冒出来、
  /// 同一帧消失，不管点得多轻都像「啪」一下拍上去。现在三个区域共用这一条
  /// 曲线：淡入淡出 + 各自的位移/缩放，任何一次显隐都是同一节奏。
  late final AnimationController _chromeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 200),
    value: 1,
  );

  late final Animation<double> _chromeAnim = CurvedAnimation(
    parent: _chromeCtrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// 上一次同步给动画的显示状态，避免每帧重复 forward/reverse。
  bool _chromeShown = true;

  /// 淡出到 0 之后把控件层整块摘掉：动画过程要它挂树上，隐藏以后还留着就
  /// 等于每帧白跑一遍布局。
  bool _chromeSettled = false;

  bool _isDesktop = false;
  bool _windowFullscreen = false;

  /// 画面比例，索引对应 [buildEmbyAspectPanel] 里的四项。
  int _aspect = 0;

  /// 画面层缓存。
  ///
  /// 控制器在播放时每个进度 tick 都会 notify，整页跟着 rebuild。画面这棵
  /// 子树（Video / Texture + 字幕）其实只在换片、缩放、改字幕样式时才变，
  /// 复用同一个 widget 实例能让 Flutter 直接跳过它——之前每帧重建纹理层，
  /// 就是掉帧、倍速下更明显的原因之一。
  Widget? _surfaceCache;
  String _surfaceKey = '';

  // 进度条拖拽
  bool _dragging = false;
  Duration _dragPosition = Duration.zero;

  // 手势 HUD
  //
  // _hudLabel 只管「显示还是隐藏」，实际渲染内容取最后一份快照：清空 label
  // 的瞬间如果直接用空字符串，淡出的那 200ms 里会是一个空黑框。
  String _hudLabel = '';
  IconData? _hudIcon;
  String _hudLastLabel = '';
  IconData? _hudLastIcon;
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
    _chromeCtrl.addStatusListener((status) {
      if (!mounted) return;
      final settled = status == AnimationStatus.dismissed;
      if (settled == _chromeSettled) return;
      setState(() => _chromeSettled = settled);
    });
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
      unawaited(
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]),
      );
    }
    if (_windowFullscreen) {
      windowManager.setFullScreen(false);
    }
    _focusNode.dispose();
    _chromeCtrl.dispose();
    controller.dispose();
    super.dispose();
  }

  /// 离开前台时不再自动切内核。
  ///
  /// 之前这里一进 inactive 就 requestPip，而 mpv（直连）片要切内核才能
  /// 画中画——结果用户下拉个通知中心、看一眼消息，播放就被打断、切到
  /// AVPlayer 还起不来。现在只有 AVPlayer 内核的「自动画中画」走原生
  /// （applicationWillResignActive，不打断播放）；mpv 内核必须由用户
  /// 主动点小窗按钮、确认后才切。

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
        DeviceOrientation.landscapeLeft,
      ],
      EmbyLandscapeSide.right => const <DeviceOrientation>[
        DeviceOrientation.landscapeRight,
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
        DeviceOrientation.portraitUp,
      ],
      EmbyOrientationMode.auto => () {
        final w = controller.videoWidth;
        final h = controller.videoHeight;
        // 尺寸还没出来：等第一帧视频信息回来再决定（见 _onPlaybackChanged）。
        if (w <= 0 || h <= 0) return null;
        return w >= h
            ? landscape
            : const <DeviceOrientation>[DeviceOrientation.portraitUp];
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
    _syncChrome();
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
      unawaited(
        _applyOrientation(
          _firstItem ? EmbyDisplayPrefs.enter : EmbyDisplayPrefs.onSwitch,
        ),
      );
      _firstItem = false;
    }
  }

  /// 控件该不该显示，只在这里算一次，交给 [_chromeCtrl] 去过渡。
  void _syncChrome() {
    final bool show = controller.controlsVisible || !controller.playing;
    if (show == _chromeShown) return;
    _chromeShown = show;
    if (show) {
      _chromeSettled = false;
      _chromeCtrl.forward();
    } else {
      _chromeCtrl.reverse();
    }
  }

  /// 把某一层控件套上统一的显隐过渡。
  ///
  /// [slide] 是「完全透明时相对最终位置的偏移」，顶栏往下、底栏往上，
  /// 看起来像整层从画面里浮出来而不是凭空冒出来。
  ///
  /// 控件层即使淡到 0 也仍然挂在树上（这样才有淡出过程），所以必须用
  /// [IgnorePointer] 把点击让回下面的手势层，否则整块画面都不响应单击。
  Widget _chromeLayer({
    required Widget child,
    double slide = 0,
    double scaleFrom = 1,
    bool ignoreWhenHidden = true,
    bool fill = false,
  }) {
    Widget body = AnimatedBuilder(
      animation: _chromeAnim,
      child: child,
      builder: (context, child) {
        final double t = _chromeAnim.value;
        Widget out = child!;
        if (scaleFrom != 1) {
          out = Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * t,
            child: out,
          );
        }
        if (slide != 0) {
          out = Transform.translate(
            offset: Offset(0, slide * (1 - t)),
            child: out,
          );
        }
        return Opacity(opacity: t.clamp(0.0, 1.0), child: out);
      },
    );
    if (ignoreWhenHidden) {
      body = IgnorePointer(ignoring: !_chromeShown, child: body);
    }
    return fill ? Positioned.fill(child: body) : body;
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
    return Offset(value.dx.clamp(-maxX, maxX), value.dy.clamp(-maxY, maxY));
  }

  // ------------------------------------------------------------ 交互

  /// 打开一个菜单页。
  ///
  /// 已经有菜单开着 → push 进当前卡片（顶部出现「‹ 上一级」返回行，换页时
  /// 卡片高度平滑过渡）；没有 → 新开一张。根级面板和二级面板走同一个入口，
  /// 这样从哪里进都长一个样。
  Future<void> _showMenuPage(String title, WidgetBuilder builder) async {
    final menu = embyMenu;
    if (menu != null) {
      menu.push(title, builder);
      return;
    }
    await showEmbyPlayerSheet<void>(
      context,
      title: title,
      isDesktop: _isDesktop,
      builder: builder,
    );
    _resumeAutoHide();
  }

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
      _showHud(
        '音量 ${controller.volume.round()}%',
        icon: Icons.volume_up_rounded,
      );
    } else if (key == LogicalKeyboardKey.arrowDown) {
      await controller.nudgeVolume(-5);
      _showHud(
        '音量 ${controller.volume.round()}%',
        icon: Icons.volume_down_rounded,
      );
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
      _showHud(
        label,
        icon: delta.isNegative
            ? Icons.replay_10_rounded
            : Icons.forward_10_rounded,
      );
    }
  }

  void _showHud(String label, {IconData? icon}) {
    _hudTimer?.cancel();
    setState(() {
      _hudLabel = label;
      _hudIcon = icon;
      _hudLastLabel = label;
      _hudLastIcon = icon;
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
    controller.pauseAutoHide();
  }

  void _resumeAutoHide() {
    controller.resumeAutoHide();
  }

  /// 小窗按钮：AVPlayer 内核直接进；mpv（直连）要切转码，先问一句。
  Future<void> _requestPip() async {
    if (controller.isAvBackend) {
      await controller.requestPip();
      return;
    }
    if (!controller.canSwitchToPip) {
      KazumiDialog.showToast(message: '本地文件暂不支持画中画');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用画中画播放？'),
        content: const Text(
          '当前是直连播放。画中画需要切换为服务器转码，画面会重新加载几秒，'
          '之后自动进入小窗。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.switchToPipByTranscode();
    }
  }

  /// AirPlay：弹系统的输出路由选择器（原生通道里挂一个隐藏的
  /// AVRoutePickerView 触发）。AV / mpv 内核都吃系统路由，都能用。
  static const MethodChannel _castChannel = MethodChannel(
    'com.predidit.kazumi/cast',
  );

  Future<void> _openAirplay() async {
    try {
      final ok =
          await _castChannel.invokeMethod<bool>('openRoutePicker') ?? false;
      if (!ok) KazumiDialog.showToast(message: '附近没有可投屏的设备');
    } catch (_) {
      KazumiDialog.showToast(message: '投屏仅在 iOS 设备上可用');
    }
  }

  Future<void> _openMore() async {
    _pauseAutoHide();
    await _showMenuPage(
      '更多',
      (ctx) => buildEmbyMorePanel(
        ctx,
        EmbyMorePanelActions(
          decodeLabel: controller.decodeMode.label,
          playbackModeLabel: controller.playbackMode.label,
          sleepLabel: embySleepLabel(controller.sleepMode),
          background: controller.backgroundAudio,
          progressAlways: controller.progressAlwaysVisible,
          onDecode: _openDecode,
          onPlaybackMode: _openPlaybackMode,
          onIntroOutro: _openIntroOutro,
          onSleep: _openSleep,
          onInfo: _openInfo,
          onBackground: () {
            controller.setBackgroundAudio(!controller.backgroundAudio);
            Navigator.of(ctx).pop();
          },
          onProgress: () {
            controller.setProgressAlwaysVisible(
              !controller.progressAlwaysVisible,
            );
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openDecode() async {
    _pauseAutoHide();
    await _showMenuPage(
      '解码',
      (ctx) => buildEmbyDecodePanel(
        current: controller.decodeMode,
        onSelect: (mode) {
          controller.setDecodeMode(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _openPlaybackMode() async {
    _pauseAutoHide();
    await _showMenuPage(
      '顺序播放',
      (ctx) => buildEmbyPlaybackModePanel(
        current: controller.playbackMode,
        onSelect: (mode) {
          controller.setPlaybackMode(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _openIntroOutro() async {
    _pauseAutoHide();
    await _showMenuPage(
      '片头片尾',
      (ctx) => AnimatedBuilder(
        // 菜单是 Overlay，页面 controller 的 notify 传不进来；包一层才能
        // 点完开关立刻看到对号和「已开启」。
        animation: controller,
        builder: (context, _) => buildEmbyIntroOutroPanel(
          introSkip: controller.introSkip,
          outroSkip: controller.outroSkip,
          onMarkIntro: () {
            controller.markIntroAt(controller.position);
            KazumiDialog.showToast(message: '已把当前进度标记为片头');
          },
          onMarkOutro: () {
            controller.markOutroAt(controller.position);
            KazumiDialog.showToast(message: '已把当前进度标记为片尾');
          },
          onIntroChanged: controller.setIntroSkip,
          onOutroChanged: controller.setOutroSkip,
        ),
      ),
    );
  }

  Future<void> _openSleep() async {
    _pauseAutoHide();
    await _showMenuPage(
      '定时关闭',
      (ctx) => buildEmbySleepPanel(
        current: controller.sleepMode,
        onSelect: (mode) {
          controller.setSleepTimer(mode);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _openChapters() async {
    _pauseAutoHide();
    await _showMenuPage(
      '章节',
      (ctx) => buildEmbyChapterPanel(
        chapters: controller.chapters,
        current: controller.position,
        onSelect: (start) {
          Navigator.of(ctx).pop();
          controller.seek(start);
        },
      ),
    );
  }

  Future<void> _openEpisodes() async {
    _pauseAutoHide();
    final int index = controller.index;
    await _showMenuPage(
      '选集',
      (ctx) => buildEmbyEpisodePanel(
        ctx,
        episodes: widget.launch.episodes,
        currentIndex: controller.index,
        onSelect: (i) {
          Navigator.of(ctx).pop();
          if (i != index) controller.openIndex(i);
        },
      ),
    );
  }

  Future<void> _openSpeed() async {
    _pauseAutoHide();
    await _showMenuPage(
      '自定义',
      (ctx) => buildEmbySpeedPanel(
        current: controller.speed,
        onSelect: (value) {
          controller.setSpeed(value);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _openAudio() async {
    _pauseAutoHide();
    await _showMenuPage(
      '音轨',
      (ctx) => buildEmbyAudioPanel(
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
        onEnhance: _openGain,
      ),
    );
  }

  Future<void> _openGain() async {
    _pauseAutoHide();
    await _showMenuPage(
      '音频增强',
      (ctx) => buildEmbyGainPanel(
        current: controller.audioGain,
        onSelect: (gain) {
          controller.setAudioGain(gain);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openSubtitle() async {
    _pauseAutoHide();
    await _showMenuPage(
      '字幕',
      (ctx) => buildEmbySubtitlePanel(
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
        onSettings: _openSubtitleSettings,
        onDisableForever: () {
          controller.disableSubtitleForever();
          Navigator.of(ctx).pop();
          _toast('这一集不再自动显示字幕');
        },
        onSearch: _openSubtitleSearch,
        onImport: _importSubtitle,
      ),
    );
  }

  /// 本地导入：挑一个字幕文件，立刻挂到当前这一条上。
  Future<void> _importSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'srt',
          'ass',
          'ssa',
          'vtt',
          'sub',
          'sup',
          'ttml',
        ],
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

  /// 字幕搜索走整页（要打字 + 滚结果列表，菜单卡片塞不下）。
  Future<void> _openSubtitleSearch() {
    return showEmbySubtitleSearchPage(context, controller: controller);
  }

  Future<void> _openSubtitleSettings() async {
    _pauseAutoHide();
    // 面板要跟着 +/- 实时刷新，所以用 StatefulBuilder 拿一份本地值：
    // 原来直接把 controller.subtitleSettings 传进去，点一次不会重建，
    // 显示不动、而且每次都基于同一个旧值算——点十下也还是 +0.5s，
    // 表现出来就是「字幕设置没接入」。
    var current = controller.subtitleSettings;
    await _showMenuPage(
      '字幕设置',
      (ctx) => StatefulBuilder(
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
  }

  Future<void> _openAspect() async {
    _pauseAutoHide();
    await _showMenuPage(
      '画面比例',
      (ctx) => Padding(
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
  }

  Future<void> _openInfo() async {
    _pauseAutoHide();
    final item = controller.current;
    await _showMenuPage(
      '媒体信息',
      (ctx) => buildEmbyInfoPanel(
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
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 手势只铺在**画面**这一层：控件（按钮 / 进度条）在它上面，
                    // 点按钮不会顺带把控件收起来。
                    _buildCachedSurface(),
                    if (!controller.loading &&
                        controller.error.isEmpty &&
                        !_chromeSettled) ...[
                      // 遮罩和控件共用一个 240ms 的曲线。以前遮罩淡 180ms、
                      // 控件瞬切，两套节奏打架，看着就是「硬」。
                      _chromeLayer(
                        child: const _ChromeGradient(),
                        ignoreWhenHidden: false,
                        fill: true,
                      ),
                      _buildTopBar(),
                      _buildCenterControls(),
                      _buildBottomBar(),
                    ],
                    if (controller.loading) _buildLoading(),
                    if (controller.error.isNotEmpty) _buildError(),
                    if (!controller.loading &&
                        controller.buffering &&
                        controller.error.isEmpty &&
                        !controller.completed)
                      _buildBuffering(),
                    _buildLockedBadge(),
                    _buildHud(),
                  ],
                ),
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
          for (final o in ring) Shadow(offset: o, blurRadius: 2.6, color: halo),
        ],
      ),
      textAlign: TextAlign.center,
      // 垂直偏移 0~100 当成「往上抬多少」：0 贴底，100 抬到画面中下部。
      padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + s.verticalOffset * 2.6),
    );
  }

  /// 画面这一层：桌面端保留原来的「单击显隐 / 双击全屏」，移动端走自己的
  /// 指针手势（见 `_onPointerDown` 一带）。
  /// 画面层：只有「真的会影响画面」的状态变了才重建。
  ///
  /// 进度 tick 走的是控制器 notify → 整页 rebuild，但画面（纹理 / 字幕样本）
  /// 只在换片、缩放、改字幕样式时变。返回同一个 widget 实例，Flutter 的
  /// updateChild 会直接复用，不再每帧重铺纹理层。
  Widget _buildCachedSurface() {
    final s = controller.subtitleSettings;
    final key = [
      controller.pipActive,
      controller.avTextureId,
      controller.videoWidth,
      controller.videoHeight,
      _zoom,
      _zoomOffset.dx,
      _zoomOffset.dy,
      _aspect,
      s.opacity,
      s.scale,
      s.verticalOffset,
      controller.avSubtitleText,
      identityHashCode(controller.videoController),
    ].join('|');
    if (key == _surfaceKey && _surfaceCache != null) return _surfaceCache!;
    _surfaceKey = key;
    return _surfaceCache = _buildGestureSurface();
  }

  Widget _buildGestureSurface() {
    // 画中画激活时画面在系统小窗里，这层只是个「还在小窗播」的提示牌，
    // 点一下退小窗回到 app 内播放。其余手势都不用响应。
    if (controller.pipActive) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(controller.stopPip()),
        child: _buildPipPlaceholder(),
      );
    }
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
    // AVPlayer 内核（iOS 转码流）：原生纹理 + Dart 层字幕。
    final textureId = controller.avTextureId;
    if (textureId != null) {
      return _buildAvSurface(textureId);
    }
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

  /// AVPlayer 内核的画面层：Texture 渲染 + 自绘字幕 overlay。
  ///
  /// 字幕样式刻意和 mpv 路径的 [_subtitleViewConfig] 保持同一套
  /// （透明底 + 八向描边 + 缩放 + 垂直偏移），两条路径看起来是一个播放器。
  Widget _buildAvSurface(int textureId) {
    final double w = controller.videoWidth.toDouble();
    final double h = controller.videoHeight.toDouble();
    final Widget video = (w > 0 && h > 0)
        ? Center(
            child: AspectRatio(
              aspectRatio: w / h,
              child: Texture(textureId: textureId),
            ),
          )
        // 尺寸事件还没到：先全屏铺，第一帧到了自然按比例收。
        : SizedBox.expand(child: Texture(textureId: textureId));

    final s = controller.subtitleSettings;
    final double opacity = s.opacity.clamp(0.0, 1.0);
    final double scale = s.scale.clamp(0.5, 2.0);
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

    final Widget child = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          video,
          if (controller.avSubtitleText.isNotEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  0,
                  22,
                  18 + s.verticalOffset * 2.6,
                ),
                child: Text(
                  controller.avSubtitleText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: opacity),
                    fontSize: 30 * scale,
                    height: 1.26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    backgroundColor: Colors.transparent,
                    shadows: [
                      for (final o in ring)
                        Shadow(offset: o, blurRadius: 2.6, color: halo),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    Widget output = child;
    final ratio = _videoAspect;
    if (ratio != null) {
      output = Center(
        child: AspectRatio(aspectRatio: ratio, child: child),
      );
    }
    if (_zoom > 1.001) {
      output = ClipRect(
        child: Transform.translate(
          offset: _zoomOffset,
          child: Transform.scale(scale: _zoom, child: output),
        ),
      );
    }
    return output;
  }

  /// 画中画激活时的占位层：画面在系统小窗里，这里只放提示。
  /// 整层可点（见 [_buildGestureSurface]），点按即退小窗回 app。
  Widget _buildPipPlaceholder() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.picture_in_picture_alt_outlined,
              size: 42,
              color: Colors.white38,
            ),
            const SizedBox(height: 14),
            const Text(
              '画中画播放中',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '视频已在小窗继续播放，点按任意处回到播放器',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
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
      // 拖动进度条时会连续进出缓冲态，硬切会「一闪一闪」。淡入一下。
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
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
      child: _chromeLayer(
        slide: -16,
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
                if (widget.launch.episodes.length > 1) const SizedBox(width: 8),
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
                // 画中画（iOS）：AVPlayer 内核直接进小窗；mpv 内核（直连
                // 原盘）点了会自动切转码、以 AVPlayer 重开再进小窗。
                if (Platform.isIOS) ...[
                  _CircleAction(
                    icon: Icons.picture_in_picture_alt_rounded,
                    iconSize: 18,
                    onTap: () => unawaited(_requestPip()),
                  ),
                  const SizedBox(width: 8),
                ],
                _CircleAction(
                  icon: Icons.more_horiz_rounded,
                  iconSize: 19,
                  onTap: _openMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 中央

  Widget _buildCenterControls() {
    final bool canPrev = controller.hasPrevious;
    final bool canNext = controller.hasNext;
    return _chromeLayer(
      scaleFrom: 0.92,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CenterAction(
              onTap: () =>
                  _seekBy(const Duration(seconds: -10), label: '快退 10 秒'),
              child: const _SeekTenIcon(backward: true, size: 42),
            ),
            const SizedBox(width: 20),
            _PlayPauseButton(
              playing: controller.playing,
              onTap: controller.togglePlay,
            ),
            const SizedBox(width: 20),
            _CenterAction(
              onTap: () =>
                  _seekBy(const Duration(seconds: 10), label: '快进 10 秒'),
              child: const _SeekTenIcon(backward: false, size: 42),
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
      ),
    );
  }

  // ------------------------------------------------------------ 底栏

  Widget _buildBottomBar() {
    final Duration total = controller.duration;
    final Duration shown = _dragging ? _dragPosition : controller.position;

    final List<Widget> leftTools = <Widget>[
      _ToolChip(
        icon: Icons.speed_rounded,
        label: '${_speedText(controller.speed)}×',
        onTap: _openSpeed,
      ),
      _ToolChip(icon: Icons.graphic_eq_rounded, label: '音轨', onTap: _openAudio),
      _ToolChip(
        icon: Icons.subtitles_outlined,
        label: _currentSubtitleLabel().isEmpty ? '字幕' : _currentSubtitleLabel(),
        selected: _currentSubtitleLabel().isNotEmpty,
        onTap: _openSubtitle,
      ),
    ];

    // 选集只留顶栏那一个入口：底栏以前还挂了一个，两个按钮干同一件事，
    // 用户一眼看到两个「选集」只会以为是不同功能。
    final List<Widget> rightTools = <Widget>[
      _CircleAction(
        icon: Icons.aspect_ratio_rounded,
        iconSize: 16,
        size: 34,
        onTap: _openAspect,
      ),
      if (controller.chapters.isNotEmpty)
        _CircleAction(
          icon: Icons.bookmark_outline_rounded,
          iconSize: 16,
          size: 34,
          onTap: _openChapters,
        ),
      // AirPlay：弹系统路由选择器（原生通道），AV / mpv 内核都能用。
      if (Platform.isIOS)
        _CircleAction(
          icon: Icons.airplay,
          iconSize: 16,
          size: 34,
          onTap: _openAirplay,
        ),
      _CircleAction(
        icon: Icons.more_horiz_rounded,
        iconSize: 18,
        size: 34,
        onTap: _openMore,
      ),
    ];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _chromeLayer(
        slide: 20,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _isDesktop ? 22 : 16,
              0,
              _isDesktop ? 22 : 16,
              _isDesktop ? 18 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 时间分列两端、状态贴住总时长——比原来「时间 / 总时长 … 状态」
                // 挤在左边更像播放器，也把进度条上方的空间用满了。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_fmt(shown), style: _timeStyle(Colors.white, 13.5)),
                    const Spacer(),
                    Text(
                      total == Duration.zero ? '--:--' : _fmt(total),
                      style: _timeStyle(Colors.white.withValues(alpha: 0.55)),
                    ),
                    const SizedBox(width: 10),
                    _StatusChip(
                      label: controller.decodeLabel,
                      value: controller.resolutionLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
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
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 窄屏（手机竖屏）放不下就横向滚，不要挤成两行。
                    if (constraints.maxWidth < 560) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ...leftTools,
                            const SizedBox(width: 10),
                            ...rightTools.map(
                              (w) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: w,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Row(
                      children: [
                        ...leftTools,
                        const Spacer(),
                        ...rightTools.map(
                          (w) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: w,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _timeStyle(Color color, [double size = 12.5]) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget _buildLockedBadge() {
    final bool locked = controller.locked;
    // 只留一枚小锁钉在左下角：原来居中的大胶囊「已锁定，点此解锁」
    // 正好糊在画面中间，太挡视频了。位置在 SafeArea 之内。
    return Positioned(
      left: 18,
      bottom: 74,
      child: IgnorePointer(
        ignoring: !locked,
        child: GestureDetector(
          onTap: locked ? controller.toggleLock : null,
          child: AnimatedOpacity(
            opacity: locked ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: locked ? 1 : 0.86,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    final bool visible = _hudLabel.isNotEmpty;
    // 淡出时继续用上一份内容，避免中途闪成空框。
    final String label = visible ? _hudLabel : _hudLastLabel;
    final IconData? icon = visible ? _hudIcon : _hudLastIcon;
    if (label.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: Duration(milliseconds: visible ? 140 : 220),
            curve: visible ? Curves.easeOutCubic : Curves.easeIn,
            child: AnimatedScale(
              scale: visible ? 1 : 0.94,
              duration: Duration(milliseconds: visible ? 160 : 220),
              curve: visible ? Curves.easeOutCubic : Curves.easeIn,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) Icon(icon, size: 22, color: Colors.white),
                    if (icon != null) const SizedBox(height: 6),
                    Text(
                      label,
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
        _showHud(
          '缩放 ${next.toStringAsFixed(1)}×',
          icon: Icons.zoom_out_map_rounded,
        );
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
      // 长按倍速中不抢手势：长按已经在拖动倍速，再来一套音量/亮度 /
      // seek 会互相打架，观感就是「手指一歪画面乱跳」。
      final bool busy = _longPressActive;
      _horizontalActive =
          horizontal &&
          _gesture.seekByDrag &&
          !controller.locked &&
          !busy;
      _verticalActive =
          !horizontal &&
          (_gesture.brightness || _gesture.volume) &&
          !controller.locked &&
          !busy;
      _verticalIsVolume = down.dx > size.width * 0.5;
      _gestureStartVolume = controller.baseVolume;
      _gestureStartBrightness = _lastBrightness;
      _seekStart = controller.position;
      // 只有控制层本来就在显示时才暂停自动隐藏——不能主动把它唤出来。
      if (controller.controlsVisible && _horizontalActive) _pauseAutoHide();
    }
    if (!_moved) return;

    if (_horizontalActive) {
      final total = controller.duration;
      if (total <= Duration.zero) return;
      final target =
          _seekStart +
          Duration(
            microseconds: (delta.dx / size.width * total.inMicroseconds)
                .round(),
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
      // 手势（seek / 音量 / 亮度）不该把控制层带出来：控制层本来就显示着
      // 才暂停自动隐藏。之前无条件 pauseAutoHide，调个音量松手整个
      // 播放器页面全展开了。
      if (controller.controlsVisible) _pauseAutoHide();
      return;
    }

    // 单击 / 双击
    final pos = event.localPosition;
    final now = DateTime.now();
    final lastAt = _lastTapAt;
    final lastPos = _lastTapPos;
    final isDouble =
        lastAt != null &&
        now.difference(lastAt) < const Duration(milliseconds: 250) &&
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
    // 控件是收起的：这一下就是要把它唤出来，立刻响应。
    // 以前不管什么情况都先等 250ms 判断双击，结果「点一下画面」永远慢半拍，
    // 是整套交互里最明显的滞涩来源。双击的快进/暂停落在第二击，控件已经出来
    // 了也不影响。
    if (!controller.controlsVisible) {
      if (_gesture.tapToggleControls) _toggleControls();
      return;
    }
    // 已经显示着，才需要等一个窗口判断是不是双击（否则会先收起再处理双击）。
    if (_gesture.doubleTapSeek || _gesture.doubleTapPlayPause) {
      _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
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
      await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
        value,
      );
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

/// 记住刚才点的按钮在屏幕上的位置，菜单从它身上长出来。
///
/// 放在按钮自己的 build context 上算，误差只有一圈外间距；比每个调用点都
/// 传一个 GlobalKey 省事得多。
void _recordAnchor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    embyLastAnchor = box.localToGlobal(Offset.zero) & box.size;
  }
}

/// 上下两道渐变遮罩（Rex 的 `PlayerChromeGradientView`）。
///
/// 透明度交给外层的 [_chromeLayer] 统一控制，这里只负责画。
class _ChromeGradient extends StatelessWidget {
  const _ChromeGradient();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
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
      onTap: enabled && onTap != null
          ? () {
              _recordAnchor(context);
              onTap!();
            }
          : null,
      onLongPress: enabled ? onLongPress : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // 顶栏这几个小键只是辅助，底子压到 0.08 并与描边一起做「玻璃片」，
          // 比原来的 0.14 实心圆轻得多，不抢画面。
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.32),
          ),
        ),
      ),
    );
  }
}

/// 中央两枚快退 / 快进。
///
/// 图标是自绘的细线圆弧（见 [_SeekTenIcon]），不用 Material 那颗实心
/// `replay_10`——那个形态太粗，压在明亮画面上就是两块白斑。
class _CenterAction extends StatefulWidget {
  const _CenterAction({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_CenterAction> createState() => _CenterActionState();
}

class _CenterActionState extends State<_CenterAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: 66,
          height: 66,
          child: Center(
            child: AnimatedScale(
              scale: _down ? 0.86 : 1,
              duration: Duration(milliseconds: _down ? 110 : 240),
              curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _down ? 0.55 : 0.95,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆环 + 中间的「10」。
///
/// 一圈 2px 的圆弧，缺口处收一个同粗细的箭头，中间写数字。比 Material 的
/// 填充箭头轻一档，和旁边那颗玻璃播放键放在一起才是一套。
class _SeekTenIcon extends StatelessWidget {
  const _SeekTenIcon({required this.backward, this.size = 42});

  final bool backward;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SeekTenPainter(backward: backward)),
    );
  }
}

class _SeekTenPainter extends CustomPainter {
  _SeekTenPainter({required this.backward});

  final bool backward;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final Offset center = size.center(Offset.zero);
    final double radius = w * 0.375;
    final Paint ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;

    // 缺口角度：留出一小段给箭头，不然箭头会和环叠在一起。
    const double gap = 0.62;
    final double startAngle = backward
        ? -math.pi / 2 + gap
        : -math.pi / 2 - gap;
    final double sweep = (2 * math.pi - 2 * gap) * (backward ? -1 : 1);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      ring,
    );

    // 箭头：落在弧的起点，指向弧前进的方向。
    final Offset tip =
        center + Offset(math.cos(startAngle), math.sin(startAngle)) * radius;
    final Offset tangent =
        Offset(-math.sin(startAngle), math.cos(startAngle)) *
        (sweep.isNegative ? -1 : 1);
    final Offset normal = Offset(math.cos(startAngle), math.sin(startAngle));
    final double len = w * 0.155;
    final Offset back = tip - tangent * len;
    canvas.drawLine(tip, back + normal * len * 0.62, ring);
    canvas.drawLine(tip, back - normal * len * 0.62, ring);

    final TextPainter text = TextPainter(
      text: TextSpan(
        text: '10',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.98),
          fontSize: w * 0.33,
          fontWeight: FontWeight.w600,
          height: 1,
          letterSpacing: -0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(_SeekTenPainter oldDelegate) =>
      oldDelegate.backward != backward;
}

/// 中央播放 / 暂停。
///
/// 原来是 68px 的纯白实心圆 + 黑色图标，压在画面上像贴了个按钮贴纸。现在改成
/// 半透明玻璃：斜向白色渐变 + 发丝描边 + 投影，图标转白。按下时提亮一档，
/// 松手回落，比单纯缩一下更「有手感」。
class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: 84,
          height: 84,
          child: Center(
            child: AnimatedScale(
              scale: _down ? 0.94 : 1,
              duration: Duration(milliseconds: _down ? 110 : 240),
              curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: _down ? 0.26 : 0.17),
                      Colors.white.withValues(alpha: _down ? 0.13 : 0.07),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: _down ? 0.34 : 0.20),
                    width: 0.9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.72, end: 1).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Transform.translate(
                      key: ValueKey<bool>(widget.playing),
                      // play 三角形的视觉重心偏左，右挪 2px 才「站得正」。
                      offset: Offset(widget.playing ? 0 : 2, 0),
                      child: Icon(
                        widget.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: widget.playing ? 32 : 34,
                        color: Colors.white.withValues(alpha: 0.96),
                        shadows: const [
                          Shadow(
                            color: Color(0x4D000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
        onTap: () {
          _recordAnchor(context);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: selected ? 0.26 : 0.12),
              width: 0.8,
            ),
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
  const _PressScale({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;

  /// 长按（用来做「长按返回键退出播放器」这种二次确认的手势）。
  final VoidCallback? onLongPress;

  /// 按下时的缩放比例。
  static const double scale = 0.95;

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
          scale: _down ? _PressScale.scale : 1,
          // 按下要跟手（短），松手带回弹（长一点，easeOutBack 过冲约 2%），
          // 以前两头都是 100ms 线性，按下去和弹回来一样快，就显得「木」。
          duration: Duration(milliseconds: _down ? 110 : 240),
          curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
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
  bool _hover = false;

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
    final double progress = total <= 0
        ? 0
        : (widget.position.inMicroseconds / total).clamp(0.0, 1.0);
    final double buffered = total <= 0
        ? 0
        : (widget.buffer.inMicroseconds / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        const double thumb = 13;
        final bool lit = _active || _hover;
        final double thumbX = (width * progress - thumb / 2).clamp(
          -thumb / 2,
          width - thumb / 2,
        );
        return MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) {
            if (!widget.enabled) return;
            setState(() => _hover = true);
          },
          onExit: (_) {
            if (!_hover) return;
            setState(() => _hover = false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled
                ? (d) =>
                      widget.onTapSeek(_positionFor(d.localPosition.dx, width))
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
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
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
                                  color: Colors.white.withValues(alpha: 0.34),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: ColoredBox(
                                  color: Colors.white.withValues(alpha: 0.96),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 手柄：拖动或桌面悬停时才浮出来，静止时只是一个纯色条。
                  Positioned(
                    left: thumbX,
                    child: AnimatedScale(
                      scale: lit ? 1 : 0.4,
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: lit ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Container(
                          width: thumb,
                          height: thumb,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
