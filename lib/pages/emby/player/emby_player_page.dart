import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/player/emby_danmaku.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/emby/player/emby_player_controller.dart';
import 'package:XL/pages/emby/player/emby_player_panels.dart';
import 'package:XL/pages/emby/player/emby_player_popover.dart';
import 'package:XL/pages/emby/player/emby_notes_sheet.dart';
import 'package:XL/pages/emby/player/emby_player_buttons_page.dart';
import 'package:XL/pages/emby/player/emby_subtitle_search_page.dart';
import 'package:XL/pages/settings/danmaku/danmaku_settings.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/emby/player_button_prefs.dart';
import 'package:XL/services/player/pip_utils.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/subtitle/han_convert.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/utils/format.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // ---- 顶栏状态行（时间 / 网速 / 帧率 / 电量）----
  // 每秒一跳的独立计时器，只驱动顶栏那一小块文字；值没变就不 setState。
  Timer? _statusTimer;
  int _statusTick = 0;
  String _clockText = '';
  String _netSpeedText = '';
  String _fpsText = '';
  int? _batteryLevel;

  // 弹幕（dandanplay 自动匹配 / 本地 XML 导入）。画布 widget 缓存，
  // 只有显示设置变化（optionRev）才重建。
  final EmbyDanmakuController danmaku = EmbyDanmakuController();
  int _danmakuOptionRev = -1;
  Widget? _danmakuChild;
  bool _batteryCharging = false;
  final Battery _battery = Battery();

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
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_onPlaybackChanged);
    PlayerButtonPrefs.instance.revision.addListener(_onPlayerButtonsChanged);
    _statusTimer = Timer.periodic(const Duration(seconds: 1), _onStatusTick);
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
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_onPlaybackChanged);
    PlayerButtonPrefs.instance.revision.removeListener(_onPlayerButtonsChanged);
    if (_longPressActive) {
      unawaited(controller.setSpeed(_speedBeforeLongPress));
    }
    _saveZoom();
    danmaku.dispose();
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

  /// 退后台就主动暂停，回前台再接着播。
  ///
  /// iOS / Android 在后台都会把视频渲染上下文挂起甚至回收，mpv 的 Metal
  /// surface、AVPlayer 的纹理都可能失效——回到前台继续播就是掉帧、卡顿，
  /// 严重时直接崩。暂停一下让解码器干净地停住，回来再起，比硬扛着稳。
  /// 开着「后台音频」或正在画中画时不介入（这两种本来就要继续播）。
  bool _pausedByBackground = false;

  /// 真的进过后台（`paused`），不只是下拉通知中心那种 `inactive`。
  /// 只有这种才需要重建解码器——VT 会话是在进后台时被系统回收的。
  bool _wasBackgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDesktop) return;
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      if (_pausedByBackground) return;
      if (controller.backgroundAudio) return;
      if (!controller.playing) return;
      // 直接暂停：画中画已下线，不再需要「等小窗接管」的时间窗。
      _pausedByBackground = true;
      unawaited(controller.togglePlay());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final wasPaused = _pausedByBackground;
      final rebuild = _wasBackgrounded;
      _pausedByBackground = false;
      _wasBackgrounded = false;
      // 进过后台就必须重建解码器：iOS 会回收 VideoToolbox 会话，不重建
      // 就是满屏解码失败（掉帧，然后闪退）。只是下拉通知中心（inactive）
      // 不重建，避免无谓的画面闪烁。
      // 顺序也要对——先重建再起播，中途切 hwdec 时播放器是停着的，不闪。
      unawaited(() async {
        if (rebuild) {
          await controller.rebuildDecoderAfterBackground();
          if (!mounted) return;
        }
        if (wasPaused && !controller.playing && controller.error.isEmpty) {
          await controller.togglePlay();
        }
      }());
    }
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

  /// 按钮开关在设置页里改完立即生效：播放器不用退出重进。
  void _onPlayerButtonsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool _shownButton(String id) => PlayerButtonPrefs.instance.shown(id);

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
          streamModeLabel: EmbyStreamPrefs.mode.label,
          onDecode: _openDecode,
          onPlaybackMode: _openPlaybackMode,
          onIntroOutro: _openIntroOutro,
          onSleep: _openSleep,
          onStreamMode: _openStreamMode,
          onInfo: _openInfo,
          onChapters: controller.chapters.isEmpty ? null : _openChapters,
          onNotes: _openNotes,
          onPlayerButtons: _openPlayerButtons,
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

  /// 播放器按钮设置是独立整页（不是播放器内卡片），从「更多 → 工具」进。
  /// 开关改动会通过 PlayerButtonPrefs.revision 直接刷新当前控制栏。
  Future<void> _openPlayerButtons() async {
    _pauseAutoHide();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const EmbyPlayerButtonsPage(),
      ),
    );
    _resumeAutoHide();
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
          introMarked: controller.hasIntroMark,
          outroMarked: controller.hasOutroMark,
          introLabel: controller.introMarkLabel,
          outroLabel: controller.outroMarkLabel,
          onMarkIntro: () {
            controller.markIntroAt(controller.position);
            KazumiDialog.showToast(message: '已标记：从这里开始是正片');
          },
          onMarkOutro: () {
            controller.markOutroAt(controller.position);
            KazumiDialog.showToast(message: '已标记：片尾从这里开始');
          },
          onClearIntro: () {
            controller.clearIntroMark();
            KazumiDialog.showToast(message: '已清除片头标记');
          },
          onClearOutro: () {
            controller.clearOutroMark();
            KazumiDialog.showToast(message: '已清除片尾标记');
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

  /// 重新加载当前流（换线路 / 卡住自救）。
  Future<void> _reloadStream() async {
    unawaited(controller.openIndex(controller.index));
  }

  bool get _pipSupported {
    if (Platform.isAndroid) return true;
    if (Platform.isIOS) return controller.pipAvailable;
    return false;
  }

  /// 画中画：AV 内核直接进原生小窗；mpv 在 Android 走系统画中画
  /// （画面由 Flutter 继续渲染），iOS 直连原盘要先切转码内核。
  Future<void> _togglePip() async {
    if (controller.isAvBackend) {
      // AVPlayer 内核：原生桥自建 AVPlayerLayer + AVPictureInPictureController，
      // 点一下就真的进系统小窗（不再让用户去点控制条上的按钮）。
      final bool ok = await controller.requestPip();
      if (!ok && mounted) _toast('画中画暂时不可用');
      return;
    }
    if (Platform.isAndroid) {
      final ok = await PipUtils.enterAndroidPIPWindow(
        width: controller.videoWidth <= 0 ? 16 : controller.videoWidth,
        height: controller.videoHeight <= 0 ? 9 : controller.videoHeight,
      );
      if (!ok) _toast('画中画暂时不可用');
      return;
    }
    if (Platform.isIOS) {
      final confirmed = await showKzConfirm(
        context: context,
        title: '进入画中画',
        message: '直连原盘需要先切换到系统转码内核，会重新加载当前进度。',
      );
      if (!confirmed || !mounted) return;
      await controller.switchToPipByTranscode();
    }
  }

  /// 截图：取当前帧 → 预览弹窗（分享 / 保存到相册）。
  Future<void> _openScreenshot() async {
    Uint8List? bytes;
    try {
      bytes = await controller.playback.screenshotPng();
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _toast('截图失败：当前内核不支持取帧');
      return;
    }
    final Uint8List shot = bytes;
    await showDialog<void>(
      context: context,
      builder: (_) => _ScreenshotDialog(
        bytes: shot,
        title: controller.current?.name ?? '截图',
      ),
    );
  }
  /// 视频笔记：截图 + 文字，点笔记跳回对应时间点。
  Future<void> _openNotes() async {
    _pauseAutoHide();
    final item = controller.current;
    if (item == null) return;
    Navigator.of(context).pop(); // 先收起「更多」菜单
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmbyNotesSheet(
        videoKey: item.id.isNotEmpty ? item.id : (item.seriesId ?? item.name),
        videoTitle: item.name,
        position: controller.position,
        onJump: (Duration target) => controller.seek(target),
        capture: () async {
          try {
            return await controller.playback.screenshotPng();
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }

  /// 弹幕菜单：本地导入 / 禁用 / 位置 / 设置 / 永久禁用。
  Future<void> _openDanmaku() async {
    _pauseAutoHide();
    await _showMenuPage(
      '弹幕',
      (ctx) => AnimatedBuilder(
        animation: danmaku,
        builder: (context, _) => buildEmbyDanmakuPanel(
          on: danmaku.on,
          loading: danmaku.loading,
          status: danmaku.status,
          count: danmaku.count,
          matchedTitle: danmaku.matchedTitle,
          onImport: () async {
            final n = await danmaku.importLocal();
            KazumiDialog.showToast(
                message: n > 0 ? '已导入 $n 条弹幕' : '没有解析到弹幕');
          },
          onToggle: () {
            danmaku.setSessionOn(!danmaku.sessionOn);
          },
          onPosition: _openDanmakuPosition,
          onSettings: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DanmakuSettingsPage()),
            );
          },
          onDisableForever: () {
            danmaku.setForeverDisabled(!danmaku.foreverDisabled);
            KazumiDialog.showToast(
                message: danmaku.foreverDisabled ? '弹幕已永久禁用' : '已恢复弹幕');
          },
        ),
      ),
    );
  }

  Future<void> _openDanmakuPosition() async {
    _pauseAutoHide();
    await _showMenuPage(
      '弹幕位置',
      (ctx) => buildEmbyDanmakuPositionPanel(
        scroll: GStorage.getSetting(SettingsKeys.danmakuScroll),
        top: GStorage.getSetting(SettingsKeys.danmakuTop),
        bottom: GStorage.getSetting(SettingsKeys.danmakuBottom),
        onToggle: (kind) {
          danmaku.togglePosition(kind);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  /// 切换线路（直连 / 转码 / 自动）：改完重开当前集生效。
  Future<void> _openStreamMode() async {
    _pauseAutoHide();
    await _showMenuPage(
      '切换线路',
      (ctx) => buildEmbyStreamModePanel(
        current: EmbyStreamPrefs.mode,
        onSelect: (mode) {
          Navigator.of(ctx).pop();
          if (mode == EmbyStreamPrefs.mode) return;
          EmbyStreamPrefs.setMode(mode);
          controller.openIndex(controller.index);
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
    KazumiDialog.notify(message);
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
    // 简繁转换是全局设置（不是按集存的），面板上要能立刻看到当前值。
    var hanMode = HanConvert.mode;
    await _showMenuPage(
      '字幕设置',
      (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => buildEmbySubtitleSettingsPanel(
          settings: current,
          subtitleActive: (controller.currentSubtitle?.id ?? 'no') != 'no',
          hanMode: hanMode,
          onHanModeChanged: (mode) async {
            setSheetState(() => hanMode = mode);
            await controller.setHanConvertMode(mode);
            if (mounted) setSheetState(() {});
          },
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
                    // 弹幕层（mpv 内核）：在画面之上、控件之下。
                    if (!controller.isAvBackend) _buildDanmakuLayer(),
                    // AVPlayer 内核走系统原生控制条（AVKit 自带），不叠自绘
                    // 播放控件；App 级入口（返回/标题/选集/锁定/更多）由
                    // 顶部功能层补回，不能因为换内核而丢功能。
                    if (controller.isAvBackend &&
                        !controller.loading &&
                        controller.error.isEmpty)
                      _buildAvAppChrome(),
                    if (!controller.isAvBackend &&
                        !controller.loading &&
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
    // HDR 字幕亮度：调高时加深描边并铺一层半透明底板，让白字在 HDR
    // 高光场景里依然读得清。0 = 完全沿用原来的描边行为。
    final double hdr = s.hdrBrightness.clamp(0.0, 1.0);
    final Color ink = Colors.white.withValues(alpha: opacity);
    final Color halo = Colors.black.withValues(alpha: (0.62 + hdr * 0.3).clamp(0, 1) * opacity);
    final Color subtitleBg = hdr > 0
        ? Colors.black.withValues(alpha: hdr * 0.34 * opacity)
        : Colors.transparent;
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
      // 开了简繁转换 / 挂了副字幕时，这一层会被关掉，由
      // [_buildMpvSubtitleOverlay] 顶上——原生那层只认 mpv 给的原文，
      // 改不了文本也画不出第二行。
      visible: !controller.usesCustomSubtitleLayer,
      style: TextStyle(
        color: ink,
        fontSize: 30 * scale,
        height: 1.26,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        backgroundColor: subtitleBg,
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
      // 简繁转换开关 / 双字幕开关变了要重建画面层：它决定走原生字幕层
      // 还是自绘层，不在这份 key 里就会出现「开了转换但画面不刷新」。
      controller.usesCustomSubtitleLayer,
      controller.primarySubtitleText,
      controller.secondarySubtitleText,
      identityHashCode(controller.videoController),
    ].join('|');
    if (key == _surfaceKey && _surfaceCache != null) return _surfaceCache!;
    _surfaceKey = key;
    return _surfaceCache = _buildGestureSurface();
  }

  Widget _buildGestureSurface() {
    final surface = _buildVideoSurface();
    // AVPlayer 内核（iOS）：原生交互——点击呼出/隐藏系统控制条、滑动快进、
    // 音轨字幕选择全是 AVKit 自带的，Flutter 手势层直接让路。
    if (controller.isAvBackend) return surface;
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

  /// 弹幕画布层：widget 缓存，显示设置变化（optionRev）才重建。
  Widget _buildDanmakuLayer() {
    Widget? child;
    return AnimatedBuilder(
      animation: danmaku,
      builder: (context, _) {
        if (!danmaku.on || danmaku.entries.isEmpty) {
          return const SizedBox.shrink();
        }
        if (_danmakuOptionRev != danmaku.optionRev || _danmakuChild == null) {
          _danmakuOptionRev = danmaku.optionRev;
          _danmakuChild = DanmakuScreen(
            createdController: (DanmakuController c) => danmaku.canvas = c,
            option: danmaku.option(),
          );
        }
        child = _danmakuChild;
        return child!;
      },
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
    Widget output = controller.usesCustomSubtitleLayer
        ? Stack(
            fit: StackFit.expand,
            children: [
              child,
              // 自绘字幕层：简繁转换后的文本 + 第二路副字幕。
              // IgnorePointer —— 字幕不能吃掉画面上的手势。
              Positioned.fill(
                child: IgnorePointer(child: _buildMpvSubtitleOverlay()),
              ),
            ],
          )
        : child;
    final ratio = _videoAspect;
    if (ratio != null) {
      // 4:3 / 16:9 这类具体比例：把画面裁成该比例居中显示。
      output = Center(
        child: AspectRatio(aspectRatio: ratio, child: output),
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

  /// mpv 路径的自绘字幕层。
  ///
  /// 字号缩放必须和 media_kit 的 `SubtitleView` 一致（按画面面积对 1080p
  /// 取 sqrt 比例），否则「一开简繁转换字幕就变大/变小」——那等于把一个
  /// 纯文本功能变成一次视觉回归。位置、描边、透明度沿用面板里的设置。
  Widget _buildMpvSubtitleOverlay() {
    final s = controller.subtitleSettings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.maxWidth * constraints.maxHeight;
        const referenceArea = 1920.0 * 1080.0;
        final factor = math.sqrt((area / referenceArea).clamp(0.0, 1.0));
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + s.verticalOffset * 2.6),
            child: _buildSubtitleLines(
              textScaler: TextScaler.linear(factor),
            ),
          ),
        );
      },
    );
  }

  /// 主 / 副字幕两行。两条内核共用一套样式，看起来是同一个播放器。
  ///
  /// [textScaler] 为 null 时不覆盖 TextScaler——AVPlayer 路径原来就是按
  /// 逻辑像素直出 30×缩放，这里保持原样，别顺手把它的字号也改了。
  Widget _buildSubtitleLines({
    TextScaler? textScaler,
    double fontSize = 30,
  }) {
    final s = controller.subtitleSettings;
    // mpv 的 sub-text 里换行是字面的 `\N`（ASS 转义），直接塞进 Text 会
    // 在画面上看到「\N」两个字符。这里统一还原成真正的换行。
    final primary = _cleanSubtitleText(controller.primarySubtitleText);
    final secondary = _cleanSubtitleText(controller.secondarySubtitleText);
    if (primary.isEmpty && secondary.isEmpty) {
      return const SizedBox.shrink();
    }
    final double opacity = s.opacity.clamp(0.0, 1.0);
    final double scale = s.scale.clamp(0.5, 2.0);
    // HDR 字幕亮度：调高时加深描边并铺一层半透明底板，让白字在 HDR
    // 高光场景里依然读得清。0 = 完全沿用原来的描边行为。
    final double hdr = s.hdrBrightness.clamp(0.0, 1.0);
    final Color ink = Colors.white.withValues(alpha: opacity);
    final Color halo = Colors.black.withValues(alpha: (0.62 + hdr * 0.3).clamp(0, 1) * opacity);
    final Color subtitleBg = hdr > 0
        ? Colors.black.withValues(alpha: hdr * 0.34 * opacity)
        : Colors.transparent;
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

    Widget line(String text, double size) => Text(
      text,
      textAlign: TextAlign.center,
      textScaler: textScaler,
      style: TextStyle(
        color: ink,
        fontSize: size * scale,
        height: 1.26,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        backgroundColor: subtitleBg,
        shadows: [
          for (final o in ring) Shadow(offset: o, blurRadius: 2.6, color: halo),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary.isNotEmpty) line(primary, fontSize),
        // 副字幕小一号压在下面：两行一样大在窄画面上会挤成一坨，
        // 而双字幕的用途就是「一眼分得清哪行是母语」。
        if (secondary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: line(secondary, fontSize * 0.86),
          ),
      ],
    );
  }

  /// mpv 的 `sub-text` 里显式换行是字面的 `\N`（ASS 转义），
  /// 直接塞进 Text 会在画面上看到「\N」这两个字符。
  String _cleanSubtitleText(String raw) {
    if (raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'\\[Nn]'), '\n')
        .replaceAll('\r', '')
        .trim();
  }

  /// AVPlayer 内核的画面层：系统 AVPlayerViewController（PlatformView）
  /// + 自绘字幕 overlay。
  /// 字幕样式刻意和 mpv 路径的 [_subtitleViewConfig] 保持同一套
  /// （透明底 + 八向描边 + 缩放 + 垂直偏移），两条路径看起来是一个播放器。
  Widget _buildAvSurface(int textureId) {
    final double w = controller.videoWidth.toDouble();
    final double h = controller.videoHeight.toDouble();
    // v2：渲染交给系统 AVPlayerViewController（resizeAspect 自动信箱），
    // 不再需要自研纹理按宽高比裁切——直接全屏铺即可。
    final Widget video = UiKitView(
      viewType: 'xl/avplayer_view',
      creationParams: {'id': textureId},
      creationParamsCodec: const StandardMessageCodec(),
    );

    final s = controller.subtitleSettings;
    final hasSubtitle =
        controller.primarySubtitleText.trim().isNotEmpty ||
        controller.secondarySubtitleText.trim().isNotEmpty;

    final Widget child = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          video,
          if (hasSubtitle)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  0,
                  22,
                  18 + s.verticalOffset * 2.6,
                ),
                child: _buildSubtitleLines(),
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

  /// 顶栏状态行的秒级刷新：
  ///   * 时间每秒重算，分钟变了才重绘；
  ///   * 网速每秒读一次 mpv 的 `cache-speed`（真实网络读取速度，
  ///     AV 内核读不到 → 不显示；控件收起时不读，省平台通道调用）；
  ///   * 电量每 30 秒查一次（拿不到就整块不显示，比如台式机）。
  Future<void> _onStatusTick(Timer timer) async {
    _statusTick++;
    final now = DateTime.now();
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 弹幕：按秒投喂 + 首次起播时自动匹配（dandanplay）。
    if (!controller.isAvBackend) {
      danmaku.tick(controller.position, playing: controller.playing);
      if (!danmaku.ready &&
          !danmaku.loading &&
          !danmaku.foreverDisabled &&
          controller.playing) {
        final item = controller.current;
        if (item != null) {
          unawaited(danmaku.autoMatch(
            (item.seriesName?.trim().isNotEmpty ?? false)
                ? item.seriesName!.trim()
                : item.name.trim(),
            controller.episodeLabel,
          ));
        }
      }
    }

    double? speed;
    if (controller.playing && _chromeShown) speed = await _readNetworkSpeed();

    // 帧率：mpv 的 estimated-vf-fps 是实时估算值，AV 内核拿不到 → 不显示。
    final String fpsText =
        controller.playing && _chromeShown
            ? (await _readFps())
            : '';

    int? level = _batteryLevel;
    bool charging = _batteryCharging;
    if (_statusTick % 30 == 1) {
      try {
        level = await _battery.batteryLevel;
        charging = await _battery.batteryState == BatteryState.charging;
      } catch (_) {
        // 无电池的设备（台式机等）：保持 null，状态行不显示电量。
      }
    }

    if (!mounted) return;
    final speedText = speed != null && speed > 0 ? formatSpeed(speed) : '';
    if (clock == _clockText &&
        speedText == _netSpeedText &&
        fpsText == _fpsText &&
        level == _batteryLevel &&
        charging == _batteryCharging) {
      return;
    }
    setState(() {
      _clockText = clock;
      _netSpeedText = speedText;
      _fpsText = fpsText;
      _batteryLevel = level;
      _batteryCharging = charging;
    });
  }

  /// mpv 实时估算帧率（estimated-vf-fps）。返回形如 "23.98fps"，
  /// 拿不到（AV 内核 / 值非法）返回空串。
  Future<String> _readFps() async {
    if (controller.isAvBackend) return '';
    final platform = controller.playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return '';
    try {
      final raw = await platform.getProperty('estimated-vf-fps');
      final fps = double.tryParse(raw) ?? 0;
      if (fps <= 0 || fps > 1000) return '';
      return '${fps.toStringAsFixed(fps >= 100 ? 0 : 1)}fps';
    } catch (_) {
      return '';
    }
  }

  /// mpv 内核的实时网络读取速度（bytes/s）。
  ///
  /// 优先 `cache-speed`（缓存激活时最准）；直连不缓存时它一直是 -1，退回
  /// `demuxer-cache-state` 里的 `reader-bytes` 累计值按秒做差。AV 内核拿
  /// 不到，返回 null。
  Future<double?> _readNetworkSpeed() async {
    if (controller.isAvBackend) return null;
    final platform = controller.playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return null;
    try {
      final value = double.tryParse(await platform.getProperty('cache-speed'));
      if (value != null && value > 0) return value;
    } catch (_) {}
    // 直连（无缓存）：reader-bytes 每秒差分。
    try {
      final raw = await platform.getProperty('demuxer-cache-state');
      final json = jsonDecode(raw);
      final total = (json['reader-bytes'] as num?)?.toDouble() ?? 0;
      final now = DateTime.now();
      final lastBytes = _lastReaderBytes;
      final lastAt = _lastReaderAt;
      _lastReaderBytes = total;
      _lastReaderAt = now;
      if (lastBytes == null || lastAt == null) return null;
      final dt = now.difference(lastAt).inMilliseconds / 1000.0;
      if (dt <= 0) return null;
      final delta = (total - lastBytes) / dt;
      return delta > 0 ? delta : null;
    } catch (_) {
      return null;
    }
  }

  double? _lastReaderBytes;
  DateTime? _lastReaderAt;

  IconData _batteryIcon(int level, bool charging) {
    if (charging) return Icons.battery_charging_full_rounded;
    if (level >= 95) return Icons.battery_full_rounded;
    if (level >= 85) return Icons.battery_6_bar_rounded;
    if (level >= 70) return Icons.battery_5_bar_rounded;
    if (level >= 55) return Icons.battery_4_bar_rounded;
    if (level >= 40) return Icons.battery_3_bar_rounded;
    if (level >= 25) return Icons.battery_2_bar_rounded;
    if (level >= 10) return Icons.battery_1_bar_rounded;
    return Icons.battery_0_bar_rounded;
  }

  /// 顶栏状态行：左「时间 · WiFi · 网速」，中「片名」，右「电量」。
  /// 标题用 Stack 绝对居中，两侧各留一段安全边距防重叠。
  Widget _buildTopStatusRow(String centerTitle) {
    final Color dim = Colors.white.withValues(alpha: 0.82);
    final TextStyle statusStyle = TextStyle(
      color: dim,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );

    final Widget left = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_clockText, style: statusStyle),
        if (_netSpeedText.isNotEmpty) ...[
          const SizedBox(width: 5),
          Icon(Icons.wifi_rounded, size: 13, color: dim),
          const SizedBox(width: 3),
          Text(_netSpeedText, style: statusStyle),
        ],
        if (_fpsText.isNotEmpty) ...[
          const SizedBox(width: 5),
          Icon(Icons.speed_rounded, size: 13, color: dim),
          const SizedBox(width: 3),
          Text(_fpsText, style: statusStyle),
        ],
      ],
    );

    final Widget? right = _batteryLevel == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_batteryLevel%', style: statusStyle),
              const SizedBox(width: 3),
              Icon(
                _batteryIcon(_batteryLevel!, _batteryCharging),
                size: 15,
                color: dim,
              ),
            ],
          );

    return SizedBox(
      height: 22,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _isDesktop ? 200 : 112,
                ),
                child: Text(
                  centerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(child: left),
          ),
          if (right != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: right),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: _chromeLayer(
        slide: -16,
        child: _topBarInner(),
      ),
    );
  }

  /// AVPlayer 内核（AVKit 系统控制条）下的 App 级功能层。
  ///
  /// AVKit 原生控制条负责播放控制（播放/进度/±10s/音轨字幕/画中画），但它
  /// 给不了返回、选集、详情、锁定、更多这些 App 级入口——这里在顶部补一层。
  /// 顶部唤起区（状态栏下一条）负责显隐本层：点它不会透给 AVKit，避免一次
  /// 点击同时把两套控件都拉出来；点画面其余区域仍是 AVKit 自己的控制条。
  Widget _buildAvAppChrome() {
    final double topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: topInset + 108,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (controller.locked) return;
          controller.setControlsVisible(!controller.controlsVisible);
        },
        child: _chromeLayer(
          child: _topBarInner(),
        ),
      ),
    );
  }

  /// 顶栏内容（标题状态行 + 按钮排），mpv 与 AV 两套内核共用。
  Widget _topBarInner() {
    final item = controller.current;
    final series = item?.seriesName?.trim();
    // 居中标题：剧集 =「剧名 S01E06 单集名」，电影 = 片名。
    final parts = <String>[
      if (series != null && series.isNotEmpty) series,
      if (controller.episodeLabel.isNotEmpty) controller.episodeLabel,
      if (item != null && item.isEpisode && item.name.trim().isNotEmpty)
        item.name.trim(),
    ];
    final centerTitle = parts.isNotEmpty
        ? parts.join(' ')
        : (item?.name ?? widget.launch.title);

    return SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _isDesktop ? 20 : 12,
              _isDesktop ? 14 : 6,
              _isDesktop ? 20 : 12,
              8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopStatusRow(centerTitle),
                SizedBox(height: _isDesktop ? 12 : 8),
                Row(
                  children: [
                    ..._rowWithGaps(<Widget>[
                      // 关闭：短按收起控件（长按返回手势开着时），长按才退出。
                      if (_shownButton('back'))
                        _CircleAction(
                          icon: Icons.close_rounded,
                          iconSize: 19,
                          onTap: _gesture.longPressExit
                              ? _toggleControls
                              : () => Navigator.of(context).maybePop(),
                          onLongPress: _gesture.longPressExit
                              ? () => Navigator.of(context).maybePop()
                              : null,
                        ),
                      // 投屏 / AirPlay：弹系统路由选择器。
                      if (_shownButton('cast'))
                        _CircleAction(
                          icon: Platform.isIOS
                              ? Icons.airplay
                              : Icons.cast_rounded,
                          iconSize: 17,
                          onTap: _openAirplay,
                        ),
                      // 画面比例 / 重新加载：mpv 内核专属（AV 走系统控制条）。
                      if (!controller.isAvBackend && _shownButton('aspect'))
                        _CircleAction(
                          icon: Icons.aspect_ratio_rounded,
                          iconSize: 16,
                          onTap: _openAspect,
                        ),
                      if (!controller.isAvBackend && _shownButton('reload'))
                        _CircleAction(
                          icon: Icons.refresh_rounded,
                          iconSize: 17,
                          onTap: _reloadStream,
                        ),
                    ]),
                    const Spacer(),
                    ..._rowWithGaps(<Widget>[
                      if (_pipSupported && _shownButton('pip'))
                        _CircleAction(
                          icon: Icons.picture_in_picture_alt_rounded,
                          iconSize: 17,
                          onTap: _togglePip,
                        ),
                      // 截图（mpv 才有取帧能力）。
                      if (!controller.isAvBackend && _shownButton('screenshot'))
                        _CircleAction(
                          icon: Icons.photo_camera_outlined,
                          iconSize: 17,
                          onTap: _openScreenshot,
                        ),
                      // 倍速。
                      if (!controller.isAvBackend && _shownButton('speed'))
                        _CircleAction(
                          icon: Icons.schedule_rounded,
                          iconSize: 18,
                          onTap: _openSpeed,
                        ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
      );
  }

  // ------------------------------------------------------------ 中央

  // ------------------------------------------------------------ 底栏

  Widget _buildBottomBar() {
    final Duration total = controller.duration;
    final Duration shown = _dragging ? _dragPosition : controller.position;
    final bool hasEpisodes = widget.launch.episodes.length > 1;

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
                // 进度条上方：左「媒体信息」，右「音轨 / 字幕 / 弹幕 / 更多」。
                // 每个按钮都能单独关；关掉后连间隔一起收起，不留空档。
                Row(
                  children: [
                    if (_shownButton('info'))
                      _OutlineAction(
                        icon: Icons.info_outline_rounded,
                        onTap: _openInfo,
                      ),
                    const Spacer(),
                    ..._rowWithGaps(<Widget>[
                      if (_shownButton('audio'))
                        _OutlineAction(
                          icon: Icons.multitrack_audio_rounded,
                          onTap: _openAudio,
                        ),
                      if (_shownButton('subtitle'))
                        _OutlineAction(
                          icon: Icons.subtitles_outlined,
                          onTap: _openSubtitle,
                        ),
                      if (_shownButton('danmaku'))
                        _OutlineAction.custom(
                          child: Text(
                            'D',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              color: Colors.white.withValues(
                                alpha: danmaku.on ? 0.94 : 0.4,
                              ),
                            ),
                          ),
                          onTap: _openDanmaku,
                        ),
                      if (_shownButton('more'))
                        _OutlineAction(
                          icon: Icons.more_horiz_rounded,
                          onTap: _openMore,
                        ),
                    ], gap: 9),
                  ],
                ),
                const SizedBox(height: 8),
                // 时间分列两端。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_fmt(shown), style: _timeStyle(Colors.white, 13.5)),
                    const Spacer(),
                    Text(
                      total == Duration.zero ? '--:--' : _fmt(total),
                      style: _timeStyle(Colors.white.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
                if (_shownButton('progress')) ...[
                  const SizedBox(height: 2),
                  _RexSeekBar(
                    position: shown,
                    duration: total,
                    buffer: controller.buffer,
                    // 「拖动进度条」关掉后只显示不让拖，防止横屏误触。
                    enabled: total > Duration.zero && _gesture.dragProgressBar,
                    onDragStart: () {
                      KazumiHaptics.tap();
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
                      KazumiHaptics.tap();
                      controller.seek(value);
                      _pauseAutoHide();
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                // 底行：锁定 | 上一集 / 播放暂停 / 下一集 | 选集。
                Row(
                  children: [
                    if (_shownButton('lock'))
                      _CircleAction(
                        icon: controller.locked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        iconSize: 17,
                        onTap: controller.toggleLock,
                      ),
                    const Spacer(),
                    ..._rowWithGaps(<Widget>[
                      if (_shownButton('prev'))
                        _BareAction(
                          icon: Icons.skip_previous_rounded,
                          // 和顶栏那排（iconSize 17~19）视觉同一档：上一集/下一集
                          // 取 20，主播放键 24，只比它们大半级，不再像两块大图标。
                          size: 20,
                          enabled: controller.hasPrevious,
                          onTap: controller.hasPrevious
                              ? controller.playPrevious
                              : null,
                        ),
                      if (_shownButton('play'))
                        _BareAction(
                          icon: controller.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 24,
                          onTap: controller.togglePlay,
                        ),
                      if (_shownButton('next'))
                        _BareAction(
                          icon: Icons.skip_next_rounded,
                          size: 20,
                          enabled: controller.hasNext,
                          onTap: controller.hasNext ? controller.playNext : null,
                        ),
                    ], gap: 20),
                    const Spacer(),
                    if (_shownButton('playlist'))
                      _CircleAction(
                        icon: Icons.format_list_bulleted_rounded,
                        iconSize: 18,
                        enabled: hasEpisodes,
                        onTap: hasEpisodes ? _openEpisodes : null,
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
      // 只看不改：松手不代表用户想把控制层叫出来。控制层本来就是收起的，
      // 长按倍速结束后也必须保持收起（之前无条件 pauseAutoHide，它会顺手
      // 把 controlsVisible 置 true，一松手整页控件全弹出来）。
      if (controller.controlsVisible) _pauseAutoHide();
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

/// 给一排按钮之间插入等宽间隔。
///
/// 按钮可以逐个关掉；如果还按固定位置写 SizedBox，关掉一个就会留下肉眼
/// 可见的空洞。这里只对「真正构建出来的」按钮插间隔。
List<Widget> _rowWithGaps(List<Widget> children, {double gap = 12}) {
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) out.add(SizedBox(width: gap));
    out.add(children[i]);
  }
  return out;
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
      dim: true,
      onTap: enabled && onTap != null
          ? () {
              _recordAnchor(context);
              onTap!();
            }
          : null,
      onLongPress: enabled ? onLongPress : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.32),
            // iOS 播放器的控件是**裸字形**：没有圆底板、没有描边，只靠一圈
            // 很淡的投影压在亮画面上。这里原来画的是 8% 白底 + 白描边的
            // 圆形「玻璃片」，那是 Material 的图标按钮语汇，系统播放器上
            // 从来不会出现。
            shadows: const [
              Shadow(
                color: Color(0x73000000),
                blurRadius: 7,
                offset: Offset(0, 1),
              ),
            ],
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
      padding: const EdgeInsets.only(right: 15),
      child: _PressScale(
        dim: true,
        onTap: () {
          _recordAnchor(context);
          onTap();
        },
        child: Padding(
          // 没有胶囊底板了，靠内边距撑出 44 高的点按区，手感不能跟着外观一起缩。
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: Colors.white.withValues(alpha: selected ? 1 : 0.88),
                shadows: const [
                  Shadow(
                    color: Color(0x73000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.88),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  shadows: const [
                    Shadow(
                      color: Color(0x73000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
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
    this.dim = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 长按（用来做「长按返回键退出播放器」这种二次确认的手势）。
  final VoidCallback? onLongPress;

  /// 按下时把内容调暗一档。iOS 的工具栏按钮/文字按钮就是这个反馈
  /// （系统播放器的控件没有底板，所以也没有「底变深」可以做）。
  final bool dim;

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
        onTapDown: enabled
            ? (_) {
                // 播放器里所有裸按钮共用这一条触感通道：轻触一下给短震，
                // 桌面端 KazumiHaptics 内部自动短路，不会报错。
                KazumiHaptics.tap();
                setState(() => _down = true);
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? _PressScale.scale : 1,
          // 按下要跟手（instant），松手带回弹（base + spring 过冲），
          // 和全局 KzPressable 用同一组时长/曲线，整 App 手感才一致。
          duration: _down ? KazumiMotion.instant : KazumiMotion.base,
          curve: _down ? Curves.easeOutCubic : KazumiMotion.spring,
          child: widget.dim
              ? AnimatedOpacity(
                  opacity: _down ? 0.45 : 1,
                  duration: KazumiMotion.fast,
                  curve: KazumiMotion.standard,
                  child: widget.child,
                )
              : widget.child,
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

/// 描边圆钮：进度条上方「音轨 / 字幕 / 弹幕 / 更多」那排的形态
///（白描边空心圆 + 细图标，参考 Infuse）。
class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.icon, this.onTap, this.iconSize = 14})
      : child = null;

  const _OutlineAction.custom({required this.child, this.onTap})
      : icon = null,
        iconSize = 0;

  final IconData? icon;
  final Widget? child;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      dim: true,
      onTap: onTap,
      child: Container(
        // 和顶栏那排裸图标同一档视觉尺寸：圆框 30、图标 14、细描边，
        // 不再是一排明显更大的「描边大圆」。
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 1.3,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 7,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: icon != null
              ? Icon(
                  icon,
                  size: iconSize,
                  color: Colors.white.withValues(alpha: 0.94),
                )
              : child,
        ),
      ),
    );
  }
}

/// 裸图标钮（无圆底无描边）：底行「上一集 / 播放暂停 / 下一集」的形态。
class _BareAction extends StatelessWidget {
  const _BareAction({
    required this.icon,
    required this.onTap,
    this.size = 30,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      dim: true,
      onTap: enabled && onTap != null ? onTap : null,
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: Center(
          child: Icon(
            icon,
            size: size,
            color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.32),
            shadows: const [
              Shadow(color: Color(0x73000000), blurRadius: 7, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 截图预览弹窗：左侧分享、右侧保存至相册。
class _ScreenshotDialog extends StatelessWidget {
  const _ScreenshotDialog({required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  String get _fileName =>
      'LU_${DateTime.now().millisecondsSinceEpoch}.png';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.black87,
      contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.contain, width: 320),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('分享'),
          onPressed: () async {
            try {
              await Share.shareXFiles(
                [
                  XFile.fromData(
                    bytes,
                    name: _fileName,
                    mimeType: 'image/png',
                  ),
                ],
              );
            } catch (_) {
              KazumiDialog.showToast(message: '分享失败');
            }
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: const Text('保存至相册'),
          onPressed: () async {
            try {
              final r = await SaverGallery.saveImage(
                bytes,
                fileName: _fileName,
                skipIfExists: false,
              );
              KazumiDialog.showToast(
                message: r.isSuccess ? '已保存到相册' : '保存失败',
              );
            } catch (_) {
              KazumiDialog.showToast(message: '保存失败');
            }
          },
        ),
      ],
    );
  }
}
