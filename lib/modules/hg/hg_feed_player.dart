/// HG 竖滑流的单页播放器：media_kit（mpv）直用，播本地代理地址。
///
/// 每个当前页一个实例，滑走即销毁（上下滑场景下保活意义不大，
/// 上游 mpv 打开本地代理地址是秒级的）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:XL/modules/hg/hg_proxy.dart';

class HgFeedPlayer extends StatefulWidget {
  const HgFeedPlayer({
    super.key,
    required this.upstreamUrl,
    this.active = true,
  });

  /// 上游真实播放地址（接口返回的 video_url / streams.main）。
  final String upstreamUrl;

  /// false 时暂停（页面被盖住 / App 后台），true 恢复播放。
  /// 播放器保持挂载，暂停不丢缓冲进度。
  final bool active;

  @override
  State<HgFeedPlayer> createState() => _HgFeedPlayerState();
}

class _HgFeedPlayerState extends State<HgFeedPlayer> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  bool _buffering = true;
  bool _failed = false;
  bool _paused = false;
  /// _open 的序号：异步打开期间又触发新 _open 时，旧调用的后续
  /// setState 一律作废，防止旧播放器状态覆盖新播放器。
  int _openSeq = 0;
  /// 变为 inactive 前是否在播放（恢复时据此决定要不要续播）。
  bool _wasPlaying = true;

  @override
  void initState() {
    super.initState();
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
    _player?.dispose();
    final player = Player();
    final controller = VideoController(player);
    setState(() {
      _player = player;
      _controller = controller;
      _buffering = true;
      _failed = false;
      _paused = false;
    });
    // 订阅状态要在 open 之前，否则首帧事件可能错过。
    _bufferingSub = player.stream.buffering.listen((buffering) {
      if (mounted && seq == _openSeq) setState(() => _buffering = buffering);
    });
    _errorSub = player.stream.error.listen((error) {
      if (mounted && seq == _openSeq && !_failed) {
        setState(() {
          _failed = true;
          _buffering = false;
        });
      }
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
      await player.setVolume(100);
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

  @override
  void dispose() {
    _bufferingSub?.cancel();
    _errorSub?.cancel();
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
              onTap: _togglePlay,
              child: Video(
                controller: controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),
            ),
          ),
        if (_failed)
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
              SizedBox(height: 10),
              Text(
                '视频加载失败，下滑重试或切换线路',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          )
        else if (_buffering)
          const CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.4),
        if (_paused && !_failed && !_buffering)
          Icon(
            Icons.play_arrow_rounded,
            color: Colors.white.withValues(alpha: 0.85),
            size: 72,
          ),
      ],
    );
  }
}
