import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

/// 托盘图标的登记与摘除。
///
/// 托盘图标由 shell（Windows 通知区）持有，`tray_manager` 只在收到
/// `WM_DESTROY` 时才去摘。而 `dart:io` 的 `exit()` 不会 unwind widget tree，
/// 插件根本收不到那次 destroy 调用，进程没了、图标还留在通知区，
/// 而且每重启一次就多一个。
///
/// 所以退出必须走 [AppExit.quit]，由它先调 [dispose] 再结束进程。
class TrayService {
  TrayService._();

  /// 图标是否真的挂上去了。
  ///
  /// 没挂过就不需要摘：`tray_manager` 的 destroy 假设图标已设置，
  /// 在没有图标时调用它会走一条没意义的清理路径。
  static bool _iconSet = false;

  static Future<void> initialize() async {
    if (Platform.isWindows) {
      await trayManager.setIcon('assets/images/logo/logo_lanczos.ico');
    } else if (Platform.environment.containsKey('FLATPAK_ID') ||
        Platform.environment.containsKey('SNAP')) {
      await trayManager.setIcon('io.github.Predidit.Kazumi');
    } else {
      await trayManager.setIcon('assets/images/logo/logo_rounded.png');
    }
    _iconSet = true;

    if (!Platform.isLinux) {
      await trayManager.setToolTip('LU');
    }

    Menu trayMenu = Menu(items: [
      MenuItem(key: 'show_window', label: '显示窗口'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出 LU')
    ]);
    await trayManager.setContextMenu(trayMenu);
  }

  /// 必须在 `exit()` 之前跑：插件只在 `WM_DESTROY` 时摘 Windows 的图标，
  /// 而它的 destroy 又假定图标已经设置过。
  static Future<void> dispose() async {
    if (!_iconSet) return;
    _iconSet = false;
    // 本机加固：插件与 shell 通信理论上可能卡住，卡住就永远等不到 exit()，
    // 进程反而退不掉，比"图标残留"更糟。给个上限，超时就直接放弃清理。
    await trayManager
        .destroy()
        .timeout(const Duration(seconds: 2), onTimeout: () async {});
  }
}
