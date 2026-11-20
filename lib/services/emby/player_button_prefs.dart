import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:XL/services/storage/storage.dart';

/// 播放器按钮的逐个显示开关，对应 SenPlayer 的 `kShowPlayerXxxButton`。
///
/// 每个按钮一个稳定 id，默认全部显示。存成一个 JSON 串（布尔表），
/// 改完 revision +1，播放器监听它即时刷新控制栏。会员/PRO 相关按钮不在此列。
class PlayerButtonPrefs {
  PlayerButtonPrefs._() {
    _reload();
  }

  static final PlayerButtonPrefs instance = PlayerButtonPrefs._();

  static const SettingKey<String> _storeKey = SettingKey<String>(
    'lu.playerButtons',
    '',
    group: SettingGroup.player,
  );

  /// 可开关的按钮。id 稳定，label 用于设置页展示。
  static const List<({String id, String label, String group})> buttons =
      <({String id, String label, String group})>[
        (id: 'lock', label: '锁定', group: '底栏'),
        (id: 'prev', label: '上一个', group: '底栏'),
        (id: 'play', label: '播放/暂停', group: '底栏'),
        (id: 'next', label: '下一个', group: '底栏'),
        (id: 'playlist', label: '选集', group: '底栏'),
        (id: 'progress', label: '进度条', group: '底栏'),
        (id: 'info', label: '媒体信息', group: '工具行'),
        (id: 'audio', label: '音轨', group: '工具行'),
        (id: 'subtitle', label: '字幕', group: '工具行'),
        (id: 'danmaku', label: '弹幕', group: '工具行'),
        (id: 'more', label: '更多', group: '工具行'),
        (id: 'back', label: '返回', group: '顶栏'),
        (id: 'cast', label: '投屏', group: '顶栏'),
        (id: 'aspect', label: '画面比例', group: '顶栏'),
        (id: 'reload', label: '重新加载', group: '顶栏'),
        (id: 'pip', label: '画中画', group: '顶栏'),
        (id: 'screenshot', label: '截图', group: '顶栏'),
        (id: 'speed', label: '倍速', group: '顶栏'),
      ];

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, bool> _shown = <String, bool>{};

  void _reload() {
    _shown.clear();
    for (final button in buttons) {
      _shown[button.id] = true;
    }
    final raw = GStorage.getSetting(_storeKey);
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final MapEntry<String, dynamic> e in decoded.entries) {
          if (_shown.containsKey(e.key) && e.value is bool) {
            _shown[e.key] = e.value as bool;
          }
        }
      }
    } catch (_) {}
  }

  void _save() {
    GStorage.putSetting(_storeKey, jsonEncode(_shown));
    revision.value = revision.value + 1;
  }

  bool shown(String id) => _shown[id] ?? true;

  void setShown(String id, bool value) {
    if (!_shown.containsKey(id) || _shown[id] == value) return;
    // 播放/暂停不能隐藏——藏了就没法控制播放了。
    if (id == 'play' && !value) return;
    _shown[id] = value;
    _save();
  }

  void resetAll() {
    for (final button in buttons) {
      _shown[button.id] = true;
    }
    _save();
  }
}
