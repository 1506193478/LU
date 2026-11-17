/// HG 竖滑流的单页播放器：media_kit（mpv）直用，播本地代理地址。
///
/// 每个当前页一个实例，滑走即销毁（上下滑场景下保活意义不大，
/// 上游 mpv 打开本地代理地址是秒级的）。
///
/// 交互对照 HGhubX Feed.tsx / PlayerControls.tsx：
/// * 单击暂停/播放；长按 2x 倍速（松手恢复）；
/// * 底部细进度条可拖动 seek（mobile_bar 语义）；
/// * 播放失败显示重试（重开 + 触发自动选线）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:XL/modules/hg/hg_diag.dart';
import 'package:XL/modules/hg/hg_lines.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_proxy.dart';

class HgFeedPlayer extends StatefulWidget {
  const HgFeedPlayer({
    super.key,
    required this.upstreamUrl,
    this.active = true,
    this.startPosition = Duration.zero,
    this.initialVolume = 1.0,
    this.initialMuted = false,
    this.onPosition,
  });

  /// 上游真实播放地址（接口返回的 video_url / streams.main；preferHevc
  /// 时页面直接传 hevc 地址）。
  final String upstreamUrl;

  /// false 时暂停（页面被盖住 / App 后台），true 恢复播放。
  /// 播放器保持挂载，暂停不丢缓冲进度。
  final bool active;

  /// 续播起点（观看记录）。
  final Duration startPosition;

  /// 初始音量（0..1，HgPrefs.volume）。
  final double initialVolume;

  /// 初始静音（HgPrefs.muteOnStartup / 记忆的静音态）。
  final bool initialMuted;

  /// 播放进度回调（节流由调用方决定），用于观看记录写回。
  final void Function(Duration position, Duration duration)? onPosition;

  @override
  State<HgFeedPlayer> createState() => _HgFeedPlayerState();
}

class _HgFeedPlayerState extends State<HgFeedPlayer> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  bool _buffering = true;
  bool _failed = false;
  bool _paused = false;
  bool _muted = false;
  double _volume = 1.0;
  bool _doubleSpeed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _scrubbing = false;
  /// _open 的序号：异步打开期间又触发新 _open 时，旧调用的后续
  /// setState 一律作废，防止旧播放器状态覆盖新播放器。
  int _openSeq = 0;
  /// 变为 inactive 前是否在播放（恢复时据此决定要不要续播）。
  bool _wasPlaying = true;

  @override
  void initState() {
    super.initState();
    _muted = widget.initialMuted;
    _volume = widget.initialVolume.clamp(0.0, 1.0);
    _open();
  }

  @override
  void didUpdateWidget(covariant HgFeedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upstreamUrl != widget.upstreamUrl) {
      _open();
      return;
    }
    if (oldWidget.active != widget.active) {
      final player = _player;
      if (player == null) return;
      if (widget.active) {
        // 只有暂停前在播才恢复（用户手动暂停的保持暂停）。
        if (_wasPlaying && !_paused) {
          player.play();
        }
      } else {
        _wasPlaying = !_paused;
        player.pause();
      }
    }
  }

  Future<void> _open() async {
    final upstream = widget.upstreamUrl;
    final seq = ++_openSeq;
    if (upstream.isEmpty) {
      setState(() {
        _failed = true;
        _buffering = false;
      });
      return;
    }
    // 先取消旧订阅再销毁旧播放器，避免 _open 被重复调用时泄漏监听器。
    await _bufferingSub?.cancel();
    await _errorSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    _player?.dispose();
    final player = Player();
    final controller = VideoController(player);
    setState(() {
      _player = player;
      _controller = controller;
      _buffering = true;
      _failed = false;
      _paused = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _doubleSpeed = false;
      _scrubbing = false;
    });
    // 订阅状态要在 open 之前，否则首帧事件可能错过。
    _bufferingSub = player.stream.buffering.listen((buffering) {
      if (mounted && seq == _openSeq) setState(() => _buffering = buffering);
    });
    _errorSub = player.stream.error.listen((error) {
      if (mounted && seq == _openSeq && !_failed) {
        HgDiag.trace('play.fail', {
          'line': HgNet.base,
          'upstream': upstream,
          'error': error.toString(),
        });
        setState(() {
          _failed = true;
          _buffering = false;
        });
      }
    });
    _positionSub = player.stream.position.listen((p) {
      if (mounted && seq == _openSeq && !_scrubbing) {
        setState(() => _position = p);
        if (!_paused) widget.onPosition?.call(p, _duration);
      }
    });
    _durationSub = player.stream.duration.listen((d) {
      if (mounted && seq == _openSeq) setState(() => _duration = d);
    });
    _playingSub = player.stream.playing.listen((playing) {
      if (mounted && seq == _openSeq) setState(() => _paused = !playing);
    });
    try {
      // 走本地代理：解密 key / 改写分片 / 带防盗链 Referer。
      final url = HgProxy.mediaUrl(upstream);
      await player.open(Media(url));
      if (seq != _openSeq) {
        // 打开期间已换新地址：这个播放器已作废，直接释放。
        await player.dispose();
        return;
      }
      await HgDiag.trace('play.open', {
        'line': HgNet.base,
        'upstream': upstream,
      });
      await player.setVolume(_muted ? 0 : _volume * 100);
      await player.setRate(_doubleSpeed ? 2.0 : 1.0);
      if (widget.startPosition > const Duration(seconds: 1) &&
          widget.startPosition < (_duration - const Duration(seconds: 3))) {
        await player.seek(widget.startPosition);
      }
      await player.play();
    } catch (_) {
      if (mounted && seq == _openSeq) {
        setState(() {
          _failed = true;
          _buffering = false;
        });
      }
    }
  }

  Future<void> _retry() async {
    // 重试前先触发一次自动选线（线路挂了会切到新镜像）。
    await HgDiag.trace('play.retry', {'line': HgNet.base});
    if (HgAutoLine.enabled) {
      await HgAutoLine.pickLine('retry', force: true);
    }
    _open();
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (_paused) {
      await player.play();
      if (mounted) setState(() => _paused = false);
    } else {
      await player.pause();
      if (mounted) setState(() => _paused = true);
    }
  }

  void _setDoubleSpeed(bool on) {
    final player = _player;
    if (player == null) return;
    _doubleSpeed = on;
    player.setRate(on ? 2.0 : 1.0);
    if (on) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('2.0x 倍速播放中'),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _seekTo(double ratio) async {
    final player = _player;
    if (player == null || _duration == Duration.zero) return;
    final target = _duration * ratio.clamp(0.0, 1.0);
    await player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  @override
  void dispose() {
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      alignment: Alignment.center,
      children: [
        const Positioned.fill(
          child: ColoredBox(color: Colors.black),
        ),
        if (controller != null && !_failed)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              onLongPressStart: (_) => _setDoubleSpeed(true),
              onLongPressEnd: (_) => _setDoubleSpeed(false),
              onLongPressCancel: () => _setDoubleSpeed(false),
              child: Video(
                controller: controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),
            ),
          ),
        if (_failed)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 40),
              const SizedBox(height: 10),
              const Text(
                '视频加载失败，可重试或切换线路',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: const Text('重试'),
              ),
            ],
          )
        else if (_buffering)
          const CircularProgressIndicator(
              color: Colors.white70, strokeWidth: 2.4),
        if (_paused && !_failed && !_buffering)
          const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 72,
          ),
        if (_doubleSpeed && !_failed && !_buffering)
          const Positioned(
            top: 12,
            child: IgnorePointer(
              child: Text(
                '2.0x',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ),
        // 底部可拖动进度条（mobile_bar 语义：拖动中暂停 tick 更新，
        // 抬手 seek）。点击视频区域的 GestureDetector 在上层，进度条
        // 放在 Stack 更靠后的位置即不被误触。
        if (!_failed && _duration > Duration.zero)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 4,
            child: IgnorePointer(
              ignoring: false,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 18,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2.4,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 10),
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.28),
                          activeTrackColor: Colors.white,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: _scrubbing
                              ? _position.inMilliseconds.toDouble()
                              : _position.inMilliseconds
                                  .clamp(0, _duration.inMilliseconds)
                                  .toDouble(),
                          max: _duration.inMilliseconds
                              .toDouble()
                              .clamp(1, double.maxFinite),
                          onChanged: (v) {
                            setState(() {
                              _scrubbing = true;
                              _position =
                                  Duration(milliseconds: v.round());
                            });
                          },
                          onChangeEnd: (v) {
                            _seekTo(
                                v / _duration.inMilliseconds.toDouble());
                            setState(() => _scrubbing = false);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_fmt(_position)} / ${_fmt(_duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
