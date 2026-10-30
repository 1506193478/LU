import 'dart:io';

import 'package:XL/services/storage/storage.dart';

abstract final class DesktopWindowConfig {
  /// Captured during window setup; preference changes apply on the next launch.
  static final bool showWindowButton = GStorage.getSetting(
    SettingsKeys.showWindowButton,
  );

  /// 无边框圆角窗口。只在 Windows 上启用：
  ///
  /// - macOS 有自己的交通灯按钮，再套一层自绘外壳会跟系统手势打架；
  /// - Linux 各家合成器对透明背景的处理不一致，不敢默认开。
  ///
  /// 同样只在启动时读一次，改了要重启。
  static final bool frameless =
      Platform.isWindows && GStorage.getSetting(SettingsKeys.framelessWindow);
}
