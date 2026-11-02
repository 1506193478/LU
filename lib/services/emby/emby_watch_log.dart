import 'dart:convert';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 一条播放记录。
///
/// 「我的 → 播放列表」和「继续观看」都从这里取数。本地文件 / 相册视频 /
/// 网络链接这些没有 itemId 的，靠 [source] 直接重开。
class EmbyWatchRecord {
  const EmbyWatchRecord({
    required this.key,
    required this.title,
    this.subtitle = '',
    this.itemId = '',
    this.serverId = '',
    this.serverName = '',
    this.source = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.playedAt = 0,
    this.imageUrl = '',
  });

  /// 去重用的键：Emby 条目用 itemId，本地用 source。
  final String key;
  final String title;
  final String subtitle;

  final String itemId;
  final String serverId;
  final String serverName;

  /// 本地文件路径 / 网络直链（本地播放时用）。
  final String source;

  final int positionMs;
  final int durationMs;
  final int playedAt;
  final String imageUrl;

  bool get finished =>
      durationMs > 0 && positionMs >= durationMs * 0.92;

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'subtitle': subtitle,
        'itemId': itemId,
        'serverId': serverId,
        'serverName': serverName,
        'source': source,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'playedAt': playedAt,
        'imageUrl': imageUrl,
      };

  factory EmbyWatchRecord.fromJson(Map<String, dynamic> json) =>
      EmbyWatchRecord(
        key: json['key']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        subtitle: json['subtitle']?.toString() ?? '',
        itemId: json['itemId']?.toString() ?? '',
        serverId: json['serverId']?.toString() ?? '',
        serverName: json['serverName']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        playedAt: (json['playedAt'] as num?)?.toInt() ?? 0,
        imageUrl: json['imageUrl']?.toString() ?? '',
      );
}

/// 播放记录本。存设置盒里（JSON），最多留 300 条，超出丢最旧的。
class EmbyWatchLog {
  EmbyWatchLog._();

  static final EmbyWatchLog instance = EmbyWatchLog._();

  static const int _max = 300;

  static const _key = SettingKey<String>(
    'embyWatchLog',
    '[]',
    group: SettingGroup.emby,
  );

  List<EmbyWatchRecord> _items = const <EmbyWatchRecord>[];
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = GStorage.getSetting(_key);
      _items = (jsonDecode(raw) as List<dynamic>? ?? [])
          .map((e) => EmbyWatchRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = const <EmbyWatchRecord>[];
    }
  }

  /// 最近播放，新的在前。
  List<EmbyWatchRecord> get records {
    _ensureLoaded();
    final list = List<EmbyWatchRecord>.from(_items)
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return list;
  }

  Future<void> put(EmbyWatchRecord record) async {
    _ensureLoaded();
    final list = List<EmbyWatchRecord>.from(_items)
      ..removeWhere((r) => r.key == record.key);
    list.add(record);
    list.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    _items = list.take(_max).toList();
    await GStorage.putSetting(
      _key,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> remove(String key) async {
    _ensureLoaded();
    _items = List.of(_items)..removeWhere((r) => r.key == key);
    await GStorage.putSetting(
      _key,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    _items = const <EmbyWatchRecord>[];
    await GStorage.putSetting(_key, '[]');
  }
}
