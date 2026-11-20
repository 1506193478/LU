import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:XL/services/storage/storage.dart';

/// SenPlayer 式二级导航（Emby 模块内）的模块配置。
///
/// 参照 SenPlayer 6.1.8 的「可配置 Tab」：七个模块可独立显隐、可排序，
/// 并可指定进入 Emby 模块时的默认落地页。所有 id 都是稳定字符串，
/// 隐藏/排序后不会像数字索引那样错位。
///
/// 存储成一个 JSON 字符串（条目只有七个，单键读写最省事）：
///   order  全量 id 的显示顺序
///   hidden 被隐藏的 id 列表
///   default 默认 Tab id
///   dock   导航胶囊位置：bottom（默认）/ top
class SenTabPrefs {
  SenTabPrefs._() {
    _reload();
  }

  static final SenTabPrefs instance = SenTabPrefs._();

  static const SettingKey<String> _storeKey = SettingKey<String>(
    'lu.senTabs',
    '',
    group: SettingGroup.emby,
  );

  /// Tab 元数据：稳定 id → 文案 / 图标。顺序即出厂默认顺序。
  static const List<SenTabMeta> all = <SenTabMeta>[
    SenTabMeta('home', '首页', Icons.home_rounded),
    SenTabMeta('resources', '资源库', Icons.dns_rounded),
    SenTabMeta('files', '文件', Icons.folder_open_rounded),
    SenTabMeta('library', '媒体库', Icons.grid_view_rounded),
    SenTabMeta('records', '记录', Icons.history_rounded),
    SenTabMeta('search', '搜索', Icons.search_rounded),
    SenTabMeta('settings', '设置', Icons.tune_rounded),
  ];

  /// IndexedStack 的槽位顺序——恒定等于出厂顺序，不随用户排序变化。
  /// 这样 children 长度和位置永不变，只是显示的 index 按稳定 id 换算。
  static List<String> get allIds => all.map((SenTabMeta m) => m.id).toList();

  static SenTabMeta? metaOf(String id) {
    for (final SenTabMeta m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 任何配置变更都会 +1，导航条与当前选中项监听它刷新。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<String> _order = allIds;
  final Set<String> _hidden = <String>{};
  String _defaultTab = 'home';
  String _dock = 'bottom';

  void _reload() {
    final String raw = GStorage.getSetting(_storeKey);
    _order = allIds;
    _hidden.clear();
    _defaultTab = 'home';
    _dock = 'bottom';
    if (raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final Object? order = decoded['order'];
      if (order is List) {
        final List<String> restored = <String>[];
        for (final Object? id in order) {
          if (id is String && allIds.contains(id) && !restored.contains(id)) {
            restored.add(id);
          }
        }
        // 补齐新增的 Tab（版本升级后出现新模块时不会丢）。
        for (final String id in allIds) {
          if (!restored.contains(id)) restored.add(id);
        }
        _order = restored;
      }

      final Object? hidden = decoded['hidden'];
      if (hidden is List) {
        for (final Object? id in hidden) {
          if (id is String && allIds.contains(id)) _hidden.add(id);
        }
      }

      final Object? def = decoded['default'];
      if (def is String && allIds.contains(def)) _defaultTab = def;

      final Object? dock = decoded['dock'];
      if (dock is String && (dock == 'top' || dock == 'bottom')) _dock = dock;
    } catch (_) {
      // 脏数据不打断模块——回落到出厂配置。
    }
  }

  void _save() {
    GStorage.putSetting(
      _storeKey,
      jsonEncode(<String, Object>{
        'order': _order,
        'hidden': _hidden.toList(),
        'default': _defaultTab,
        'dock': _dock,
      }),
    );
    revision.value = revision.value + 1;
  }

  // ---- 读取 ----------------------------------------------------------

  /// 当前可见 Tab 的 id（按用户排序）。
  List<String> get visibleIds =>
      _order.where((String id) => !_hidden.contains(id)).toList();

  /// 出厂顺序下的槽位（给 IndexedStack.index 用）。
  int slotOf(String id) {
    final int i = allIds.indexOf(id);
    return i < 0 ? 0 : i;
  }

  bool isVisible(String id) => !_hidden.contains(id);

  bool get allHidden => _hidden.length >= all.length;

  String get defaultTab => _defaultTab;

  String get dock => _dock;

  bool get dockAtTop => _dock == 'top';

  // ---- 修改 ----------------------------------------------------------

  void setVisible(String id, bool value) {
    if (!allIds.contains(id)) return;
    final bool changed = value ? _hidden.remove(id) : _hidden.add(id);
    if (!changed) return;
    // 不允许把最后一个可见 Tab 藏掉，否则模块进去是空的。
    if (_hidden.length >= all.length) {
      _hidden.remove(id);
      return;
    }
    // 默认 Tab 被隐藏时，落到第一个可见项。
    if (!value && _defaultTab == id) {
      _defaultTab = _order.firstWhere(
        (String x) => !_hidden.contains(x),
        orElse: () => allIds.first,
      );
    }
    _save();
  }

  /// 按「可见列表」的索引重排（对应 ReorderableListView.onReorderItem 语义：
  /// [newIndex] 已经是移除 oldIndex 元素之后的目标位置，无需再 -1）。
  /// [visible] 是当前可见 id 的顺序。
  void reorderVisible(List<String> visible, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    int target = newIndex;
    if (target < 0) target = 0;
    if (target > visible.length) target = visible.length;

    final String movedId = visible[oldIndex];
    _order.remove(movedId);

    int fullNew;
    if (target >= visible.length) {
      fullNew = _order.length;
    } else {
      final String targetId = visible[target];
      fullNew = _order.indexOf(targetId);
      if (fullNew < 0) fullNew = _order.length;
    }
    if (fullNew > _order.length) fullNew = _order.length;
    _order.insert(fullNew, movedId);
    _save();
  }

  void setDefaultTab(String id) {
    if (!allIds.contains(id) || _hidden.contains(id)) return;
    if (_defaultTab == id) return;
    _defaultTab = id;
    _save();
  }

  void setDockAtTop(bool value) {
    final String next = value ? 'top' : 'bottom';
    if (_dock == next) return;
    _dock = next;
    _save();
  }

  /// 恢复出厂配置。
  void reset() {
    _order = allIds;
    _hidden.clear();
    _defaultTab = 'home';
    _dock = 'bottom';
    _save();
  }
}

/// 一个 Tab 的展示元数据。
class SenTabMeta {
  const SenTabMeta(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}
