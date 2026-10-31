// Windows 无边框窗口的系统圆角。
//
// 去掉系统标题栏（frameless）之后，Win11 默认不再给窗口画圆角，四个角
// 变成直角；四周那一圈留白底色一到角上就露出一个发白的直角块，非常扎眼。
//
// 修法是让 DWM 自己来画圆角：给窗口设 `DWMWA_WINDOW_CORNER_PREFERENCE`
// 为 `DWMWCP_ROUND`，效果和资源管理器 / 其它系统应用的圆角完全一致，
// 抗锯齿由系统负责，Flutter 层零开销。
//
// Win10 没有这个属性（调用返回错误码），静默忽略、保持直角，不影响启动。
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// DWMWA_WINDOW_CORNER_PREFERENCE：告诉 DWM 窗口四角怎么处理。
const int _dwmwaWindowCornerPreference = 33;

/// DWMWCP_ROUND：按系统主题画圆角。
const int _dwmwcpRound = 2;

/// Flutter 桌面主窗口的 Win32 类名（flutter_runner 固定值）。
const String _flutterWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// 给主窗口申请系统圆角。只处理 Windows；其它平台直接忽略。
void applyWindowRoundCorner() {
  if (!Platform.isWindows) return;
  final Pointer<Utf16> className = TEXT(_flutterWindowClass);
  final int hwnd = FindWindow(className, nullptr);
  calloc.free(className);
  // 窗口还没建好 / 类名对不上就算了，别为圆角操心启动。
  if (hwnd == 0) return;
  final Pointer<Int32> pref = calloc<Int32>()..value = _dwmwcpRound;
  try {
    DwmSetWindowAttribute(
      hwnd,
      _dwmwaWindowCornerPreference,
      pref,
      sizeOf<Int32>(),
    );
  } catch (_) {
    // 旧系统没有 attribute 33，保持直角就好。
  } finally {
    calloc.free(pref);
  }
}
