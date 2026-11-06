import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:flutter/material.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/clay.dart';
import 'package:XL/services/logging/logger.dart';

/// DLNA 投屏（上游 2.4.3 的三连修，2026-11 移植）：
///
/// 1. **只列真正能投的设备**——`DLNADevice.controlURL` 会把所有控制请求
///    路由到 AVTransport 服务，没有这个服务的设备（打印机、网关、灯泡）
///    点了只会报错，直接在列表里过滤掉；
/// 2. **设备流是单订阅的**——以前每次点「搜索」都 listen 一次，第二次就抛
///    `Stream has already been listened to`，所以搜索按钮看起来会「失灵」；
///    现在订阅只建一次，并记录已见设备避免日志刷屏；
/// 3. **投的是元数据里带片名的 URL**（`setUrl(video, title: title)`，
///    dlna_dart 0.1.1 起支持）——电视端会显示「番剧名 · 第 N 集」，
///    不再是裸 URL。
class RemotePlay {
  Future<void> castVideo(String video, {required String title}) async {
    final searcher = DLNAManager();
    final dlna = await searcher.start();
    StreamSubscription<Map<String, DLNADevice>>? subscription;
    final loggedDevices = <String>{};
    List<Widget> dlnaDevice = [];
    await KazumiDialog.show(
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ClayDialog(
              title: '远程投屏',
              icon: Icons.cast_rounded,
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: dlnaDevice,
                  ),
                ),
              ),
              actions: [
                ClayButton(
                  tone: ClayTone.subtle,
                  height: 44,
                  onPressed: () {
                    KazumiDialog.dismiss();
                  },
                  child: const Text('退出'),
                ),
                ClayButton(
                  tone: ClayTone.accent,
                  height: 44,
                  onPressed: () {
                    KazumiDialog.showToast(message: '开始搜索');
                    // 设备流是单订阅的：订阅只建一次，重复点「搜索」
                    // 只是让已建的订阅继续收新设备。
                    subscription ??= dlna.devices.stream.listen((deviceList) {
                      final tiles = <Widget>[];
                      deviceList.forEach((key, value) {
                        final castable = _supportsAVTransport(value);
                        if (loggedDevices.add(key)) {
                          KazumiLogger().i(
                            'RemotePlay: found ${value.info.friendlyName} ${value.info.deviceType}${castable ? '' : ', skipped without AVTransport'}',
                          );
                        }
                        if (!castable) {
                          return;
                        }
                        final typeName = _deviceTypeName(value.info.deviceType);
                        tiles.add(
                          ListTile(
                            leading: _deviceUPnPIcon(typeName),
                            title: Text(value.info.friendlyName),
                            subtitle: Text(typeName),
                            onTap: () async {
                              try {
                                KazumiDialog.showToast(
                                  message: '尝试投屏至 ${value.info.friendlyName}',
                                );
                                await value.setUrl(video, title: title);
                                await value.play();
                              } catch (e) {
                                KazumiLogger().e(
                                  'RemotePlay: failed to cast to device',
                                  error: e,
                                );
                                KazumiDialog.showError(
                                  message: 'DLNA 异常: $e \n尝试重新进入 DLNA 投屏或切换设备',
                                );
                              }
                            },
                          ),
                        );
                      });
                      // 空列表也重建：设备消失后要让它从列表里移除。
                      setState(() {
                        dlnaDevice = tiles;
                      });
                    });
                  },
                  child: const Text('搜索'),
                ),
              ],
            );
          },
        );
      },
      onDismiss: () {
        unawaited(subscription?.cancel());
        searcher.stop();
      },
    );
  }

  /// DLNADevice 的所有控制请求都经 controlURL 走 AVTransport 服务，
  /// 没有它的设备（MediaServer 只能被拉流、打印机、网关等）投不动。
  bool _supportsAVTransport(DLNADevice device) {
    return device.info.serviceList.any(
      (service) => '${service['serviceId']}'.contains('AVTransport'),
    );
  }

  String _deviceTypeName(String deviceType) {
    final parts = deviceType.split(':');
    return parts.length > 3 ? parts[3] : deviceType;
  }

  Icon _deviceUPnPIcon(String deviceType) {
    switch (deviceType) {
      case 'MediaRenderer':
        return const Icon(Icons.cast_connected);
      case 'MediaServer':
        return const Icon(Icons.cast_connected);
      case 'InternetGatewayDevice':
        return const Icon(Icons.router);
      case 'BasicDevice':
        return const Icon(Icons.device_hub);
      case 'DimmableLight':
        return const Icon(Icons.lightbulb);
      case 'WLANAccessPoint':
        return const Icon(Icons.lan);
      case 'WLANConnectionDevice':
        return const Icon(Icons.wifi_tethering);
      case 'Printer':
        return const Icon(Icons.print);
      case 'Scanner':
        return const Icon(Icons.scanner);
      case 'DigitalSecurityCamera':
        return const Icon(Icons.camera_enhance_outlined);
      default:
        return const Icon(Icons.question_mark);
    }
  }
}
