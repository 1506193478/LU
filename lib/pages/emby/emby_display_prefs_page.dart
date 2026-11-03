import 'package:flutter/material.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/settings/settings_dropdown_tile.dart';
import 'package:XL/bean/settings/settings_list.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';

/// Emby 播放器 → 屏幕方向。
///
/// 只做三件事：进播放器时的方向、换集后的方向、横屏倒向哪一侧。退出播放器
/// 都会还原成进来之前的方向，不会把竖屏的列表页卡成横的。
class EmbyDisplayPrefsPage extends StatefulWidget {
  const EmbyDisplayPrefsPage({super.key});

  @override
  State<EmbyDisplayPrefsPage> createState() => _EmbyDisplayPrefsPageState();
}

class _EmbyDisplayPrefsPageState extends State<EmbyDisplayPrefsPage> {
  late EmbyOrientationMode _enter = EmbyDisplayPrefs.enter;
  late EmbyOrientationMode _onSwitch = EmbyDisplayPrefs.onSwitch;
  late EmbyLandscapeSide _side = EmbyDisplayPrefs.side;

  static const Map<EmbyOrientationMode, String> _orientationOptions = {
    EmbyOrientationMode.auto: '适应宽高',
    EmbyOrientationMode.keep: '无变化',
    EmbyOrientationMode.landscape: '强制横屏',
    EmbyOrientationMode.portrait: '强制竖屏',
  };

  static const Map<EmbyLandscapeSide, String> _sideOptions = {
    EmbyLandscapeSide.auto: '自动',
    EmbyLandscapeSide.left: '摄像头在左',
    EmbyLandscapeSide.right: '摄像头在右',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('屏幕方向'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('进入播放器'),
            tiles: [
              SettingsDropdownTile<EmbyOrientationMode>(
                leading: Icons.screen_rotation_rounded,
                title: const Text('屏幕方向'),
                description: const Text('打开一集、播放器刚出来时的方向'),
                value: _enter,
                options: _orientationOptions,
                onChanged: (v) async {
                  setState(() => _enter = v);
                  await EmbyDisplayPrefs.setEnter(v);
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('切换视频后'),
            tiles: [
              SettingsDropdownTile<EmbyOrientationMode>(
                leading: Icons.skip_next_rounded,
                title: const Text('屏幕方向'),
                description: const Text('自动连播 / 手动换集时的方向'),
                value: _onSwitch,
                options: _orientationOptions,
                onChanged: (v) async {
                  setState(() => _onSwitch = v);
                  await EmbyDisplayPrefs.setOnSwitch(v);
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('横屏方向'),
            tiles: [
              SettingsDropdownTile<EmbyLandscapeSide>(
                leading: Icons.phone_android_rounded,
                title: const Text('设备横屏方向'),
                description: const Text('躺着看时选摄像头在哪边，机身跟着你转'),
                value: _side,
                options: _sideOptions,
                onChanged: (v) async {
                  setState(() => _side = v);
                  await EmbyDisplayPrefs.setSide(v);
                },
              ),
            ],
            bottomInfo: const Text(
              '「适应宽高」会按视频比例决定横竖：2.35:1 的电影横屏，竖屏短剧保持竖屏。\n'
              '退出播放器会还原进入前的方向，不会把列表页卡成横屏。\n'
              '桌面端（Windows / macOS / Linux）不锁定方向，这一页只在手机上生效。',
            ),
          ),
        ],
      ),
    );
  }
}
