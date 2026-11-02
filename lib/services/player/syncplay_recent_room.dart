import 'dart:convert';

import 'package:XL/services/storage/storage.dart';

/// 一个进过的房间，供大厅「最近」列表一键重回。
///
/// 只存房间号、服务器和当时的片名。不存 token、不存成员名单 —— 房间号本身
/// 就是唯一的凭证，多存一份只是多一个泄露面。
class SyncPlayRecentRoom {
  const SyncPlayRecentRoom({
    required this.room,
    required this.endPoint,
    required this.title,
    required this.at,
  });

  final String room;
  final String endPoint;
  final String title;
  final DateTime at;

  /// 列表里最多留几条。再多也没人往下翻。
  static const int maxEntries = 5;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'r': room,
        'e': endPoint,
        't': title,
        'a': at.millisecondsSinceEpoch,
      };

  static SyncPlayRecentRoom? tryParse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final String room = json['r']?.toString() ?? '';
    if (room.isEmpty) {
      return null;
    }
    final int at = (json['a'] as num?)?.toInt() ?? 0;
    return SyncPlayRecentRoom(
      room: room,
      endPoint: json['e']?.toString() ?? '',
      title: json['t']?.toString() ?? '',
      at: at <= 0
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// 读最近的房间，最新的在前。
  static List<SyncPlayRecentRoom> load() {
    final String raw =
        GStorage.getSetting<String>(SettingsKeys.syncPlayRecentRooms);
    if (raw.trim().isEmpty) {
      return const <SyncPlayRecentRoom>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SyncPlayRecentRoom>[];
      }
      return <SyncPlayRecentRoom>[
        for (final Object? item in decoded) ?SyncPlayRecentRoom.tryParse(item),
      ];
    } catch (_) {
      // 存坏了就当没有，别让一条脏数据把大厅整个卡住。
      return const <SyncPlayRecentRoom>[];
    }
  }

  /// 记一条并落盘，返回更新后的列表。
  ///
  /// 同一个房间号重复进只保留最新那条，不会堆出一串同名房间。
  static List<SyncPlayRecentRoom> record({
    required String room,
    required String endPoint,
    required String title,
  }) {
    if (room.isEmpty) {
      return load();
    }
    final List<SyncPlayRecentRoom> next = <SyncPlayRecentRoom>[
      SyncPlayRecentRoom(
        room: room,
        endPoint: endPoint,
        title: title,
        at: DateTime.now(),
      ),
      ...load().where((SyncPlayRecentRoom item) => item.room != room),
    ];
    final List<SyncPlayRecentRoom> trimmed =
        next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    GStorage.putSetting<String>(
      SettingsKeys.syncPlayRecentRooms,
      jsonEncode(<Map<String, dynamic>>[
        for (final SyncPlayRecentRoom item in trimmed) item.toJson(),
      ]),
    );
    return trimmed;
  }

  static List<SyncPlayRecentRoom> clear() {
    GStorage.putSetting<String>(SettingsKeys.syncPlayRecentRooms, '[]');
    return const <SyncPlayRecentRoom>[];
  }

  /// 删掉一条，返回剩下的（最新的在前）。
  ///
  /// 「最近进过」原来只有进、没有删：进错房、或者房号早就作废的那些会一直挂在
  /// 列表最上面，只能靠再进五次新房把它们挤下去。
  static List<SyncPlayRecentRoom> remove(String room) {
    if (room.isEmpty) {
      return load();
    }
    final List<SyncPlayRecentRoom> left = <SyncPlayRecentRoom>[
      ...load().where((SyncPlayRecentRoom item) => item.room != room),
    ];
    GStorage.putSetting<String>(
      SettingsKeys.syncPlayRecentRooms,
      jsonEncode(<Map<String, dynamic>>[
        for (final SyncPlayRecentRoom item in left) item.toJson(),
      ]),
    );
    return left;
  }
}
