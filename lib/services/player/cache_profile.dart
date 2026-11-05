import 'package:XL/services/storage/storage.dart';

/// 播放缓存档位。
///
/// 背景：iOS 上 `demuxer-max-bytes + demuxer-max-back-bytes` 原来固定 1.5G×2，
/// 4K HEVC 的解码帧缓冲叠上去就被 jetsam 杀掉（表现为「看一分钟闪退」）；
/// 3.9.55 把它压到 96/48MB 之后不闪退了，但又有用户反馈弱网下缓冲不够、
/// 拖动后要等。这个档位就是把「内存」和「缓冲」的取舍交给用户：
///
///   * 省内存 —— 更容易被杀后台的低内存设备 / 4K 原盘；
///   * 均衡   —— 默认，等同 3.9.55 的取值（iOS 96/48MB）；
///   * 流畅   —— 弱网、跨城/跨境线路，愿意多占一点内存换少卡顿；
///   * 极致   —— 局域网直连原盘，内存充足时尽量多缓。
///
/// 桌面端/Android 的「均衡」刻意保持原来的 1500/1500MB 不变——它们没有被
/// 系统杀过，没有理由为了统一视觉去动一个已经跑了很多版本的数值。
enum PlaybackCacheProfile {
  saver('saver', '省内存'),
  balanced('balanced', '均衡'),
  smooth('smooth', '流畅'),
  max('max', '极致');

  const PlaybackCacheProfile(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static PlaybackCacheProfile get current => parse(
    GStorage.getSetting(SettingsKeys.playbackCacheProfile),
  );

  static PlaybackCacheProfile parse(String? raw) => switch (raw) {
    'saver' => PlaybackCacheProfile.saver,
    'smooth' => PlaybackCacheProfile.smooth,
    'max' => PlaybackCacheProfile.max,
    _ => PlaybackCacheProfile.balanced,
  };

  Future<void> save() => GStorage.putSetting(
    SettingsKeys.playbackCacheProfile,
    storageValue,
  );

  /// 前向缓存（还没播到的部分），字节。
  int get forwardBytes => switch (this) {
    PlaybackCacheProfile.saver => 48 * _mb,
    PlaybackCacheProfile.balanced => 96 * _mb,
    PlaybackCacheProfile.smooth => 192 * _mb,
    PlaybackCacheProfile.max => 384 * _mb,
  };

  /// 回拖缓存（已经播过的部分），字节。
  int get backBytes => switch (this) {
    PlaybackCacheProfile.saver => 16 * _mb,
    PlaybackCacheProfile.balanced => 48 * _mb,
    PlaybackCacheProfile.smooth => 64 * _mb,
    PlaybackCacheProfile.max => 128 * _mb,
  };

  String get description => switch (this) {
    PlaybackCacheProfile.saver => '缓存最少，最不容易被系统回收；弱网下起播会慢一点',
    PlaybackCacheProfile.balanced => '默认档，缓冲和内存各让一步',
    PlaybackCacheProfile.smooth => '多缓一倍多的数据，弱网/跨境线路更不容易卡',
    PlaybackCacheProfile.max => '尽量多缓，局域网直连原盘最舒服',
  };

  String get summary {
    final f = forwardBytes ~/ _mb;
    final b = backBytes ~/ _mb;
    return '$f MB 前向 / $b MB 回拖';
  }

  static const int _mb = 1024 * 1024;
}

/// 桌面端 / Android 的缓存档位。数值和 [PlaybackCacheProfile] 不是一套：
/// 这些平台单进程能拿到的内存大得多，用 iOS 那套「几十 MB」会让 4K 原盘
/// 一直卡在缓冲上。均衡档刻意等于历史默认值（1500/1500MB）。
class DesktopCacheProfile {
  const DesktopCacheProfile._();

  static int forwardBytes(PlaybackCacheProfile profile) => switch (profile) {
    PlaybackCacheProfile.saver => 128 * _mb,
    PlaybackCacheProfile.balanced => 1500 * _mb,
    PlaybackCacheProfile.smooth => 3000 * _mb,
    PlaybackCacheProfile.max => 4500 * _mb,
  };

  static int backBytes(PlaybackCacheProfile profile) => switch (profile) {
    PlaybackCacheProfile.saver => 64 * _mb,
    PlaybackCacheProfile.balanced => 1500 * _mb,
    PlaybackCacheProfile.smooth => 2048 * _mb,
    PlaybackCacheProfile.max => 3072 * _mb,
  };

  static const int _mb = 1024 * 1024;
}
