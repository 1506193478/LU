import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:XL/utils/motion.dart';

/// 开屏动画的底色。
///
/// 取的是视频首帧的平均色（ffmpeg 把首帧缩到 1x1 采样得到 `#C4C8CD`）。
/// 三处必须一致，否则启动时会闪一下：
/// 1. Android 原生 `launch_background`（进程起来到 Flutter 画第一帧之间）
/// 2. 这里的 `ColoredBox`（Flutter 起来了、但视频还没解出第一帧）
/// 3. `Video(fill:)`（解码器还没吐出画面的空窗）
const Color kSplashBackground = Color(0xFFC4C8CD);

/// 视频播完后的停留时间，让最后一帧（画面里的 "Meet you"）站住一下。
const Duration _kSplashHold = Duration(milliseconds: 160);

/// 交叉淡出时长。首页在底下早就建好了，所以这里是"揭幕"而不是"切页"。
const Duration _kSplashFade = Duration(milliseconds: 560);

/// 兜底超时：视频流万一不触发 completed，也不能把启动卡住。
const Duration _kSplashWatchdog = Duration(milliseconds: 9500);

/// 开屏动画闸门。
/// 用法是把整个 App 套进去：
///
/// ```dart
/// MaterialApp.router(builder: (context, child) => AppSplashGate(child: child!))
/// ```
///
/// 关键点是**首页在底下照常构建**（网络请求、Hive 读取都在跑），
/// 视频只是在最上面盖了一层。播完把这一层淡掉，首页已经就位，
/// 所以过渡是"揭幕"而不是"黑屏 → 重建"。
class AppSplashGate extends StatefulWidget {
  const AppSplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppSplashGate> createState() => _AppSplashGateState();
}

class _AppSplashGateState extends State<AppSplashGate> {
  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _watchdog;
  bool _fading = false;
  bool _done = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开了"减少动态效果"就直接跳过，不给用户放 8 秒动画。
    if (!_reducedMotion && MediaQuery.disableAnimationsOf(context)) {
      _reducedMotion = true;
      _skip();
    }
  }

  Future<void> _start() async {
    try {
      final Player player = Player();
      final VideoController controller = VideoController(player);
      _player = player;
      _controller = controller;
      if (mounted) setState(() {});
      // 视频本身是静音的，这里再兜一层，避免某些设备上 mpv 忘记 mute。
      await player.setVolume(0);
      _subscriptions.add(
        player.stream.completed.listen((completed) {
          if (completed) _finish();
        }),
      );
      _subscriptions.add(player.stream.error.listen((_) => _skip()));
      await player.open(
        Media('asset:///assets/splash/splash.mp4'),
        play: true,
      );
      _watchdog = Timer(_kSplashWatchdog, _skip);
    } catch (_) {
      // 解码器起不来就静默跳过，开屏不该挡住进 App。
      _skip();
    }
  }

  /// 正常播完：停一下，再淡出。
  Future<void> _finish() async {
    if (_fading || _done) return;
    _watchdog?.cancel();
    await Future<void>.delayed(_kSplashHold);
    if (!mounted || _fading || _done) return;
    _fadeOut();
  }

  /// 跳过（点了、出错、减少动态效果）：立刻淡出。
  void _skip() {
    if (_fading || _done) return;
    _watchdog?.cancel();
    _fadeOut();
  }

  void _fadeOut() {
    if (_fading || _done || !mounted) return;
    setState(() => _fading = true);
    Future<void>.delayed(_kSplashFade, () {
      if (!mounted) return;
      setState(() => _done = true);
      // 等这一帧把 Video 从树上摘掉再销毁播放器，否则正在被引用的
      // controller 会被提前释放。
      WidgetsBinding.instance.addPostFrameCallback((_) => _disposePlayer());
    });
  }

  void _disposePlayer() {
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    final VideoController? controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _fading,
          child: GestureDetector(
            // 8 秒对老用户有点长，点一下就走。
            onTap: _skip,
            behavior: HitTestBehavior.opaque,
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: _kSplashFade,
              curve: KazumiMotion.standard,
              child: AnimatedScale(
                // 淡出的同时轻微推近，观感上像镜头往画面里走了一步。
                scale: _fading ? 1.06 : 1,
                duration: _kSplashFade,
                curve: KazumiMotion.emphasized,
                child: ColoredBox(
                  color: kSplashBackground,
                  child: controller == null
                      ? const SizedBox.shrink()
                      : Video(
                          controller: controller,
                          fit: BoxFit.cover,
                          fill: kSplashBackground,
                          controls: NoVideoControls,
                          wakelock: false,
                          pauseUponEnteringBackgroundMode: false,
                        ),
                ),
              ),
            ),
          ),
        ),
        // 跳过按钮单独一层，压在视频之上；淡出时和视频一起消失。
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: KazumiMotion.fast,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: _SplashSkipButton(onTap: _skip),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 开屏右上角的「跳过」。
///
/// 视频本身是浅色的雨天插画，所以用半透明黑胶囊 + 白字，比玻璃或白底更稳。
class _SplashSkipButton extends StatelessWidget {
  const _SplashSkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.26),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          KazumiHaptics.tap();
          onTap();
        },
        child: const Padding(
          padding: EdgeInsets.fromLTRB(14, 7, 10, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '跳过',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFFFFFFF),
                ),
              ),
              SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                size: 17,
                color: Color(0xFFFFFFFF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
