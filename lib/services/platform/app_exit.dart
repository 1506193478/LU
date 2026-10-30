import 'dart:io';

import 'package:XL/services/platform/tray_service.dart';

/// 统一的退出入口。
///
/// `lib` 下不要直接写 `exit(0)`：进程结束时不会 unwind widget tree，
/// 托盘插件收不到销毁通知，Windows 通知区会留下一个残图标
/// （见 [TrayService]）。这里先摘图标，再结束进程；
/// 清理失败也照样退出，不会因为清理出问题就卡在桌面上。
class AppExit {
  AppExit._();

  static Future<Never> quit() async {
    try {
      await TrayService.dispose();
    } finally {
      exit(0);
    }
  }
}
