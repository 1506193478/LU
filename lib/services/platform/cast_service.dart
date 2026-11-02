import 'dart:io';

import 'package:flutter/services.dart';

/// 投屏：调起系统自带的投射入口。
///
/// - Android：打开系统的「投射」设置页（`Settings.ACTION_CAST_SETTINGS`），
///   部分 ROM 没有这个入口时退回「无线显示」设置页。
/// - iOS：弹系统 `AVRoutePickerView`（AirPlay 设备列表）。
/// - 桌面端没有系统投屏可用，直接抛 [CastUnsupported]。
class CastService {
  CastService._();

  static const MethodChannel _channel = MethodChannel('com.predidit.kazumi/cast');

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  /// 打开系统投屏面板。成功返回 true。
  static Future<bool> open() async {
    if (!supported) {
      throw const CastUnsupported('当前平台没有系统投屏可用');
    }
    try {
      final ok = await _channel.invokeMethod<bool>('openRoutePicker');
      return ok == true;
    } on MissingPluginException {
      throw const CastUnsupported('这台设备上没有接入系统投屏');
    } on PlatformException catch (e) {
      throw CastUnsupported(e.message ?? '打开系统投屏失败');
    }
  }
}

class CastUnsupported implements Exception {
  const CastUnsupported(this.message);

  final String message;

  @override
  String toString() => message;
}
