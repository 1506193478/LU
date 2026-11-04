import 'dart:async';
import 'dart:convert';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 用户手动标记的片头 / 片尾，按「剧集」持久化。
///
/// 之前这两个标记只存在 [EmbyPlayerController] 的内存字段里，换集就被
/// 服务端数据覆盖掉了——用户在第一集标好片头片尾，第二集完全不生效。
///
/// 键的层级：
///   * `s:<seriesId>` —— 整部剧通用（标记一集，后面每集都吃这套规则）；
///   * `i:<itemId>`   —— 单集专属（用户单独为某一集调过）。
/// 读取时单集优先，没有再退回整部剧。
class EmbySkipMarks {
  EmbySkipMarks._();

  static const _key = SettingKey<String>(
    'emby.skipMarks',
    '',
    group: SettingGroup.emby,
  );

  /// 一条标记：起点 / 终点都是秒。
  static const String seriesPrefix = 's:';
  static const String itemPrefix = 'i:';

  static Map<String, dynamic> _load() {
    final raw = GStorage.getSetting(_key);
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static void _save(Map<String, dynamic> data) {
    unawaited(GStorage.putSetting(_key, jsonEncode(data)));
  }

  /// 当前条目对应的两个键（单集 + 整剧）。
  static List<String> keysFor({String? seriesId, required String itemId}) {
    return <String>[
      if (itemId.isNotEmpty) '$itemPrefix$itemId',
      if (seriesId != null && seriesId.isNotEmpty) '$seriesPrefix$seriesId',
    ];
  }

  /// 读一条标记；没有就返回 null。
  static EmbySkipMark? read({String? seriesId, required String itemId}) {
    final data = _load();
    for (final k in keysFor(seriesId: seriesId, itemId: itemId)) {
      final v = data[k];
      if (v is Map) {
        return EmbySkipMark(
          introStart: _seconds(v['introStart']),
          introEnd: _seconds(v['introEnd']),
          outroStart: _seconds(v['outroStart']),
        );
      }
    }
    return null;
  }

  /// 写一条标记。会同时写到单集键和整剧键——用户在一部剧的某一集里标了
  /// 片头，默认意图是「这部剧的片头就在这儿」。
  static void write({
    String? seriesId,
    required String itemId,
    int? introStart,
    int? introEnd,
    int? outroStart,
  }) {
    final data = _load();
    final entry = <String, dynamic>{
      if (introStart != null) 'introStart': introStart,
      if (introEnd != null) 'introEnd': introEnd,
      if (outroStart != null) 'outroStart': outroStart,
    };
    if (entry.isEmpty) return;
    for (final k in keysFor(seriesId: seriesId, itemId: itemId)) {
      final old = data[k];
      final merged = <String, dynamic>{
        if (old is Map) ...old.cast<String, dynamic>(),
        ...entry,
      };
      data[k] = merged;
    }
    _save(data);
  }

  static Duration? _seconds(Object? value) {
    final n = value is int ? value : int.tryParse('$value');
    if (n == null || n <= 0) return null;
    return Duration(seconds: n);
  }
}

/// [EmbySkipMarks] 读出来的标记（时间点，可能只有一部分）。
class EmbySkipMark {
  const EmbySkipMark({this.introStart, this.introEnd, this.outroStart});

  final Duration? introStart;
  final Duration? introEnd;
  final Duration? outroStart;

  bool get isEmpty =>
      introStart == null && introEnd == null && outroStart == null;
}
