import 'dart:io';

import 'package:XL/services/player/avplayer_engine.dart';
import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 画中画偏好。目前只有 iOS 的 AVPlayer 内核吃这套设置（libmpv /
/// Android Emby 播放器暂时没有小窗），开关状态仍全局保存。
class EmbyPipPrefs {
  EmbyPipPrefs._();

  static const _autoEnterKey = SettingKey<bool>(
    'luPipAutoEnter',
    true,
    group: SettingGroup.emby,
  );

  /// 回主屏 / 切其他 App 时自动进画中画。
  static bool get autoEnter => GStorage.getSetting(_autoEnterKey);

  static Future<void> setAutoEnter(bool value) async {
    await GStorage.putSetting(_autoEnterKey, value);
    if (Platform.isIOS) {
      await AvPlayerEngine.setAutoPipEnabled(value);
    }
  }

  /// 起播时把当前设置同步给原生（open 会重建 PiP controller）。
  static Future<void> syncToEngine() async {
    if (Platform.isIOS) {
      await AvPlayerEngine.setAutoPipEnabled(autoEnter);
    }
  }
}
