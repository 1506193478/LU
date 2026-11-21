import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 通知分类（对应 Animeko 通知中心的「互动 / 系统 / 更新」语义）。
/// 本工程没有消息后端，通知全部来自本地事件（下载完成、更新、播放等）。
enum LuNotificationCategory {
  system('system', '系统', 0xFF0A84FF),
  update('update', '更新', 0xFF30D158),
  download('download', '下载', 0xFFFF9F0A),
  playback('playback', '播放', 0xFFAF52DE);

  const LuNotificationCategory(this.id, this.label, this.color);

  final String id;
  final String label;
  final int color;

  static LuNotificationCategory fromId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return system;
  }
}

/// 一条本地通知。
class LuNotification {
  LuNotification({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
    this.route,
  });

  final String id;
  final String categoryId;
  final String title;
  final String body;
  final int timestamp;
  final bool read;
  final String? route;

  LuNotificationCategory get category =>
      LuNotificationCategory.fromId(categoryId);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'cat': categoryId,
        'title': title,
        'body': body,
        'ts': timestamp,
        'read': read,
        'route': route,
      };

  factory LuNotification.fromJson(Map<String, dynamic> json) => LuNotification(
        id: json['id']?.toString() ?? '',
        categoryId: json['cat']?.toString() ?? 'system',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        timestamp: (json['ts'] as num?)?.toInt() ?? 0,
        read: json['read'] == true,
        route: json['route']?.toString(),
      );
}

/// 本地通知中心：持久化在设置 box 的单个 JSON 键里（条目量小，单键读写最省事）。
/// 与 Animeko 的「通知中心 + 分类设置」语义对齐，但不依赖任何消息后端。
class LuNotificationCenter {
  LuNotificationCenter._() {
    _reload();
  }

  static final LuNotificationCenter instance = LuNotificationCenter._();

  static const SettingKey<String> _itemsKey = SettingKey<String>(
    'lu.notifications',
    '',
    group: SettingGroup.misc,
  );

  static const SettingKey<String> _categoriesKey = SettingKey<String>(
    'lu.notificationCategories',
    '',
    group: SettingGroup.misc,
  );

  static const SettingKey<int> _seededVersionKey = SettingKey<int>(
    'lu.notificationSeeded',
    0,
    group: SettingGroup.misc,
  );

  /// 通知列表变更 / 已读状态变更都会 +1。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<LuNotification> _items = <LuNotification>[];
  final Map<String, bool> _categoryEnabled = <String, bool>{};

  void _reload() {
    _items = <LuNotification>[];
    try {
      final raw = GStorage.getSetting(_itemsKey);
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              _items.add(LuNotification.fromJson(e));
            }
          }
        }
      }
    } catch (_) {
      _items = <LuNotification>[];
    }
    _items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _categoryEnabled.clear();
    for (final c in LuNotificationCategory.values) {
      _categoryEnabled[c.id] = true;
    }
    try {
      final raw = GStorage.getSetting(_categoriesKey);
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (_categoryEnabled.containsKey(key)) {
              _categoryEnabled[key] = value == true;
            }
          });
        }
      }
    } catch (_) {}
  }

  List<LuNotification> get all => List<LuNotification>.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.read).length;

  bool categoryEnabled(LuNotificationCategory c) =>
      _categoryEnabled[c.id] ?? true;

  Future<void> setCategoryEnabled(
      LuNotificationCategory c, bool enabled) async {
    _categoryEnabled[c.id] = enabled;
    await _persistCategories();
    revision.value++;
  }

  Future<void> _persistItems() async {
    await GStorage.putSetting(
      _itemsKey,
      jsonEncode(_items.map((n) => n.toJson()).toList()),
    );
  }

  Future<void> _persistCategories() async {
    await GStorage.putSetting(_categoriesKey, jsonEncode(_categoryEnabled));
  }

  /// 新增一条通知。分类被用户关闭时不入库，尊重分类设置。
  Future<void> add({
    required LuNotificationCategory category,
    required String title,
    required String body,
    String? id,
    String? route,
  }) async {
    if (!categoryEnabled(category)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _items.insert(
      0,
      LuNotification(
        id: id ?? '$now-${_items.length}',
        categoryId: category.id,
        title: title,
        body: body,
        timestamp: now,
        route: route,
      ),
    );
    await _persistItems();
    revision.value++;
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index < 0 || _items[index].read) return;
    final old = _items[index];
    _items[index] = LuNotification(
      id: old.id,
      categoryId: old.categoryId,
      title: old.title,
      body: old.body,
      timestamp: old.timestamp,
      read: true,
      route: old.route,
    );
    await _persistItems();
    revision.value++;
  }

  Future<void> markAllRead() async {
    if (_items.every((n) => n.read)) return;
    _items = _items
        .map(
          (n) => LuNotification(
            id: n.id,
            categoryId: n.categoryId,
            title: n.title,
            body: n.body,
            timestamp: n.timestamp,
            read: true,
            route: n.route,
          ),
        )
        .toList();
    await _persistItems();
    revision.value++;
  }

  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    await _persistItems();
    revision.value++;
  }

  Future<void> clear() async {
    _items = <LuNotification>[];
    await _persistItems();
    revision.value++;
  }

  /// 首次安装播一条欢迎通知，让通知中心不至于永远空着。
  /// 用版本化的 seed 标记，升级后可再播一次。
  Future<void> seedIfNeeded(int appVersion) async {
    if (GStorage.getSetting(_seededVersionKey) >= appVersion) return;
    await GStorage.putSetting(_seededVersionKey, appVersion);
    await add(
      category: LuNotificationCategory.system,
      title: '欢迎使用 LU',
      body: '通知中心会集中展示下载、更新和播放相关的本地消息。',
      id: 'welcome-$appVersion',
    );
  }
}
