import 'package:flutter/material.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/settings/settings_dropdown_tile.dart';
import 'package:XL/bean/settings/settings_list.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';

/// Emby 播放器 → 播放手势。
///
/// 入口在「Emby 我的 → 播放手势」。这一页只改 `EmbyGesturePrefs`，播放器每次
/// 起播读一次，所以改完不用重启 App，下一次进播放器就是新行为。
///
/// 为什么做成独立一页而不是塞进播放器里的「更多」：这些是**一次性配好**的
/// 偏好，放在播放器里每次都要点三层才能到；而误触双击跳进度这种事，用户
/// 通常是在看得正爽时才发现，得能立刻关掉。
class EmbyGestureSettingsPage extends StatefulWidget {
  const EmbyGestureSettingsPage({super.key});

  @override
  State<EmbyGestureSettingsPage> createState() =>
      _EmbyGestureSettingsPageState();
}

class _EmbyGestureSettingsPageState extends State<EmbyGestureSettingsPage> {
  late EmbyGesturePrefs _prefs = EmbyGesturePrefs.current;

  /// 「画面缩放」这组默认收起：它只有一个开关和一个说明，展开只是为了让
  /// 「记住缩放」这件事有个解释的地方，不展开也不影响使用。
  bool _zoomExpanded = false;

  Future<void> _update(EmbyGesturePrefs next) async {
    setState(() => _prefs = next);
    await EmbyGesturePrefs.save(next);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('播放手势'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('滑动'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.brightness_6_rounded,
                title: const Text('左侧上下滑动调节亮度'),
                description: const Text('在画面左半边上下滑，按屏幕高度换算亮度'),
                initialValue: _prefs.brightness,
                onToggle: (v) =>
                    _update(_prefs.copyWith(brightness: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.volume_up_rounded,
                title: const Text('右侧上下滑动调节音量'),
                description: const Text('在画面右半边上下滑，调的是播放器音量'),
                initialValue: _prefs.volume,
                onToggle: (v) => _update(_prefs.copyWith(volume: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.swap_horiz_rounded,
                title: const Text('左右滑动调节进度'),
                description: const Text('横滑画面快进快退，松手才真正跳转'),
                initialValue: _prefs.seekByDrag,
                onToggle: (v) =>
                    _update(_prefs.copyWith(seekByDrag: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.linear_scale_rounded,
                title: const Text('拖动进度条'),
                description: const Text('关掉后底部进度条只能看不能拖，防止误触'),
                initialValue: _prefs.dragProgressBar,
                onToggle: (v) =>
                    _update(_prefs.copyWith(dragProgressBar: v ?? false)),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('点击'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.touch_app_rounded,
                title: const Text('单击显示或隐藏控件'),
                initialValue: _prefs.tapToggleControls,
                onToggle: (v) =>
                    _update(_prefs.copyWith(tapToggleControls: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.fast_forward_rounded,
                title: const Text('双击左右快进快退'),
                description: const Text('双击画面左 / 右三分之一'),
                initialValue: _prefs.doubleTapSeek,
                onToggle: (v) =>
                    _update(_prefs.copyWith(doubleTapSeek: v ?? false)),
              ),
              SettingsDropdownTile<int>(
                leading: Icons.timer_outlined,
                title: const Text('双击跳转时长'),
                value: _prefs.doubleTapSeconds,
                options: const {5: '5 秒', 10: '10 秒', 15: '15 秒', 30: '30 秒'},
                enabled: _prefs.doubleTapSeek,
                onChanged: (v) => _update(_prefs.copyWith(doubleTapSeconds: v)),
              ),
              SettingsTile.switchTile(
                leading: Icons.play_circle_outline_rounded,
                title: const Text('双击中间播放或暂停'),
                initialValue: _prefs.doubleTapPlayPause,
                onToggle: (v) =>
                    _update(_prefs.copyWith(doubleTapPlayPause: v ?? false)),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('长按'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.speed_rounded,
                title: const Text('长按画面倍速播放'),
                description: const Text('按住加速，松手回到原速'),
                initialValue: _prefs.longPressSpeed,
                onToggle: (v) =>
                    _update(_prefs.copyWith(longPressSpeed: v ?? false)),
              ),
              SettingsDropdownTile<double>(
                leading: Icons.fast_rewind_rounded,
                title: const Text('长按倍率'),
                value: _prefs.longPressRate,
                // double 当 map key 不能用 const（== 被重写过），这里去掉 const。
                options: {1.5: '1.5×', 2.0: '2.0×', 3.0: '3.0×', 4.0: '4.0×'},
                enabled: _prefs.longPressSpeed,
                onChanged: (v) => _update(_prefs.copyWith(longPressRate: v)),
              ),
              SettingsTile.switchTile(
                leading: Icons.exit_to_app_rounded,
                title: const Text('长按左上角返回键退出播放器'),
                description: const Text('短按只收起控件，长按才真的退出'),
                initialValue: _prefs.longPressExit,
                onToggle: (v) =>
                    _update(_prefs.copyWith(longPressExit: v ?? false)),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('画面缩放'),
            tiles: [
              SettingsTile(
                leading: Icons.zoom_out_map_rounded,
                title: const Text('缩放与记忆'),
                description: const Text('双指缩放画面；展开可设置是否记住倍率'),
                value: Text(_zoomExpanded ? '收起' : '展开'),
                trailing: Icon(
                  _zoomExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                onPressed: (_) =>
                    setState(() => _zoomExpanded = !_zoomExpanded),
              ),
              if (_zoomExpanded) ...[
                SettingsTile.switchTile(
                  leading: Icons.pinch_rounded,
                  title: const Text('双指缩放画面'),
                  description: const Text('双指捏合放大，拖动移动画面，双击复位'),
                  initialValue: _prefs.pinchZoom,
                  onToggle: (v) =>
                      _update(_prefs.copyWith(pinchZoom: v ?? false)),
                ),
                SettingsTile.switchTile(
                  leading: Icons.bookmark_added_outlined,
                  title: const Text('记住缩放大小'),
                  description: const Text('开：按影片记住倍率，重启 App 后还在；关：每次起播回到 100%'),
                  initialValue: _prefs.rememberZoom,
                  onToggle: (v) async {
                    final next = _prefs.copyWith(rememberZoom: v ?? false);
                    // 关掉的瞬间就把老记录清掉，不然「关了还记着」会让人困惑。
                    if (!next.rememberZoom) {
                      await EmbyZoomMemory.clear();
                    }
                    await _update(next);
                  },
                ),
              ],
            ],
          ),
          SettingsSection(
            title: const Text('震动反馈'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.vibration_rounded,
                title: const Text('长按屏幕'),
                initialValue: _prefs.hapticLongPress,
                onToggle: (v) =>
                    _update(_prefs.copyWith(hapticLongPress: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.swipe_rounded,
                title: const Text('滑动调节进度'),
                initialValue: _prefs.hapticSeek,
                onToggle: (v) =>
                    _update(_prefs.copyWith(hapticSeek: v ?? false)),
              ),
              SettingsTile.switchTile(
                leading: Icons.tune_rounded,
                title: const Text('拖动进度条'),
                initialValue: _prefs.hapticProgress,
                onToggle: (v) =>
                    _update(_prefs.copyWith(hapticProgress: v ?? false)),
              ),
            ],
            bottomInfo: const Text(
              '震动只在 Android / iOS 上有；桌面端会自动忽略。\n'
              '手势之间会互相避让：双指按下时不再触发亮度 / 音量。',
            ),
          ),
        ],
      ),
    );
  }
}
