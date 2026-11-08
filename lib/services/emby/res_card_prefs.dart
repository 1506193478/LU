import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:XL/services/storage/storage.dart';

/// 资源库卡片的个性化状态。
///
/// 每张卡有一个稳定 key（本地卡 `local:files` 等；服务器卡
/// `emby:<id>` / `vault:<id>` / `cloud:<id>`），对应一条覆盖配置：
///
///   hidden      隐藏（「隐藏」直接藏；「加密」= hidden + locked）
///   locked      隐藏时需要过面容/密码才能由顶栏锁按钮显示
///   aggregated  是否参与聚合搜索（默认 true）
///   icon        自定义图标（图标库里的名字，null = 默认）
///
/// 另有 [defaultHome]：长按「设为默认首页」记录的 key，进 Emby 模块时
/// 直接落在那台服务器（媒体库）或那个本地库上。
///
/// 整包存成一个 JSON 字符串：条目最多几十个，单键读写比逐键开 Hive
/// 字段省事，而且一次性拿全量不会出现「半张卡是新配置」的中间态。
class ResCardPrefs {
  ResCardPrefs._() {
    _reload();
  }

  static final ResCardPrefs instance = ResCardPrefs._();

  static const SettingKey<String> _storeKey = SettingKey<String>(
    'lu.resCards',
    '',
    group: SettingGroup.emby,
  );

  static const SettingKey<String> _homeKey = SettingKey<String>(
    'lu.resHome',
    '',
    group: SettingGroup.emby,
  );

  /// 任何变更都会 +1；资源库页监听它刷新网格与顶栏锁按钮。
  final ValueNotifier<int> revision = ValueNotifier(0);

  Map<String, Map<String, dynamic>> _data = <String, Map<String, dynamic>>{};

  void _reload() {
    final String raw = GStorage.getSetting(_storeKey);
    if (raw.isEmpty) {
      _data = <String, Map<String, dynamic>>{};
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _data = decoded.map(
          (String k, Object? v) =>
              MapEntry(k, v is Map<String, dynamic> ? v : <String, dynamic>{}),
        );
      }
    } catch (_) {
      // 解析失败就当没配过——脏数据不该把整个资源库打挂。
      _data = <String, Map<String, dynamic>>{};
    }
  }

  void _save() {
    GStorage.putSetting(_storeKey, jsonEncode(_data));
    revision.value = revision.value + 1;
  }

  Map<String, dynamic> _entry(String key) => _data[key] ?? <String, dynamic>{};

  // ---- 隐藏 / 加密 ---------------------------------------------------

  bool hidden(String key) => _entry(key)['hidden'] == true;

  /// 加密卡：隐藏且显示时需要过生物识别 / 密码。
  bool locked(String key) => _entry(key)['locked'] == true;

  void setHidden(String key, bool value) {
    final Map<String, dynamic> e = _entry(key);
    e['hidden'] = value;
    if (!value) e['locked'] = false;
    _data[key] = e;
    _save();
  }

  /// 「加密」：隐藏 + 需要验证。
  void setLocked(String key, bool value) {
    final Map<String, dynamic> e = _entry(key);
    e['locked'] = value;
    e['hidden'] = value;
    _data[key] = e;
    _save();
  }

  /// 顶栏锁按钮验证通过后：全部显示出来（隐藏/加密一起清）。
  void revealAll() {
    bool changed = false;
    for (final MapEntry<String, Map<String, dynamic>> e in _data.entries) {
      if (e.value['hidden'] == true || e.value['locked'] == true) {
        e.value['hidden'] = false;
        e.value['locked'] = false;
        changed = true;
      }
    }
    if (changed) _save();
  }

  int get hiddenCount => _data.values
      .where((Map<String, dynamic> e) => e['hidden'] == true)
      .length;

  bool get hasLocked =>
      _data.values.any((Map<String, dynamic> e) => e['locked'] == true);

  // ---- 聚合 ----------------------------------------------------------

  /// 是否参与聚合搜索。没配置过 = 参与。
  bool aggregated(String key) => _entry(key)['aggregated'] != false;

  void setAggregated(String key, bool value) {
    final Map<String, dynamic> e = _entry(key);
    e['aggregated'] = value;
    _data[key] = e;
    _save();
  }

  // ---- 自定义图标 ----------------------------------------------------

  String? icon(String key) => _entry(key)['icon'] as String?;

  void setIcon(String key, String? value) {
    final Map<String, dynamic> e = _entry(key);
    if (value == null || value.isEmpty) {
      e.remove('icon');
    } else {
      e['icon'] = value;
    }
    if (e.isEmpty) {
      _data.remove(key);
    } else {
      _data[key] = e;
    }
    _save();
  }

  // ---- 默认首页 ------------------------------------------------------

  String? get defaultHome {
    final String v = GStorage.getSetting(_homeKey);
    return v.isEmpty ? null : v;
  }

  void setDefaultHome(String? key) {
    GStorage.putSetting(_homeKey, key ?? '');
    revision.value = revision.value + 1;
  }
}
