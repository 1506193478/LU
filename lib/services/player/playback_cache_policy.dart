import 'dart:async';

import 'package:XL/services/logging/logger.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/services/network/metered_network_service.dart';
import 'package:XL/services/player/low_memory_mode.dart';
import 'package:XL/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
  }) : _isLocalPlayback = isLocalPlayback,
       _currentPlayer = currentPlayer;

  static const int _lowMemoryBufferSize = 2 * 1024 * 1024;
  static const int _defaultBufferSize = 1500 * 1024 * 1024;

  /// iOS 单独一组上限。
  ///
  /// 原来这里对**所有平台**都用 1500MB：`demuxer-max-bytes` 和
  /// `demuxer-max-back-bytes` 各 1500MB，等于允许 mpv 吃掉 3GB。
  /// 桌面端无所谓，但 iPhone 上单进程内存上限通常只有 2GB 出头——
  /// 4K HEVC 的解码帧缓冲（几十帧 × 每帧十几 MB）再叠上去，几十秒就
  /// 被系统 jetsam 杀掉，表现就是「看不了一分钟就闪退」，而且因为是被
  /// 系统杀的，Dart 侧连日志都留不下。
  ///
  /// 前向 96MB 对 HLS 和直连都够用（4K 大约能缓 20 秒），
  /// 后向 48MB 够回拖一小段；再大纯粹是拿内存换用不上的缓冲。
  static const int _iosForwardBufferSize = 96 * 1024 * 1024;
  static const int _iosBackBufferSize = 48 * 1024 * 1024;

  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;
  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      LowMemoryMode.current == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      MeteredNetworkService.isMetered;

  int get bufferSize {
    if (LowMemoryMode.current.isEnabled(
      isMetered: MeteredNetworkService.isMetered,
      isLocalPlayback: _isLocalPlayback(),
    )) {
      return _lowMemoryBufferSize;
    }
    // iOS 走独立上限，理由见 _iosForwardBufferSize 的注释。
    if (kIsCupertinoPlatform) return _iosForwardBufferSize;
    return _defaultBufferSize;
  }

  /// 回拖缓存上限。iOS 上必须比前向更小——它保留的是「已经播过」的
  /// 数据，只是给往回拖用，给到和前向一样大纯属浪费内存。
  int get backBufferSize => kIsCupertinoPlatform
      ? _iosBackBufferSize
      : bufferSize;

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = LowMemoryMode.watch().listen((_) => _onChanged());
    MeteredNetworkService.listenable.addListener(_onChanged);
  }

  void stopWatching() {
    MeteredNetworkService.listenable.removeListener(_onChanged);
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = null;
  }

  Future<void> apply() async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = player.platform as NativePlayer;
      // A stale player's initialization must not block its replacement's writes.
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        await pp.setProperty('demuxer-max-bytes', bufferSize.toString());
        await pp.setProperty(
          'demuxer-max-back-bytes',
          backBufferSize.toString(),
        );
      });
    } catch (e) {
      KazumiLogger().w(
        'PlaybackCachePolicy: failed to apply demuxer cache size',
        error: e,
      );
    }
  }

  void _onChanged() {
    unawaited(apply());
  }
}
