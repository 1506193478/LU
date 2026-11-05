import 'dart:async';

import 'package:XL/services/logging/logger.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/services/network/metered_network_service.dart';
import 'package:XL/services/player/cache_profile.dart';
import 'package:XL/services/player/low_memory_mode.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
  }) : _isLocalPlayback = isLocalPlayback,
       _currentPlayer = currentPlayer;

  static const int _lowMemoryBufferSize = 2 * 1024 * 1024;

  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;
  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      LowMemoryMode.current == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      MeteredNetworkService.isMetered;

  /// 用户选的档位（设置 → 转码与串流 → 播放缓存）。
  PlaybackCacheProfile get profile => PlaybackCacheProfile.current;

  int get bufferSize {
    if (LowMemoryMode.current.isEnabled(
      isMetered: MeteredNetworkService.isMetered,
      isLocalPlayback: _isLocalPlayback(),
    )) {
      return _lowMemoryBufferSize;
    }
    // iOS 的数值整体小一个量级，理由见 [PlaybackCacheProfile] 的注释：
    // iPhone 单进程内存上限只有 2GB 出头，前向缓存给大了就是等系统来杀。
    return kIsCupertinoPlatform
        ? profile.forwardBytes
        : DesktopCacheProfile.forwardBytes(profile);
  }

  /// 回拖缓存上限。iOS 上必须比前向更小——它保留的是「已经播过」的
  /// 数据，只是给往回拖用，给到和前向一样大纯属浪费内存。
  int get backBufferSize => kIsCupertinoPlatform
      ? profile.backBytes
      : DesktopCacheProfile.backBytes(profile);

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = GStorage.watchSettings([
      SettingsKeys.lowMemoryPolicy,
      SettingsKeys.lowMemoryMode,
      SettingsKeys.playbackCacheProfile,
    ]).listen((_) => _onChanged());
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
