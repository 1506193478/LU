import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/services/storage/storage.dart';

/// 视频笔记（对应 SenPlayer 的「视频笔记：截图 + 文字，点击跳时间点」）。
///
/// 一条笔记 = 截图文件 + 文字 + 时间点（秒）+ 影片标识。按影片分组存取，
/// 截图落到应用文档目录的 video_notes/ 下，元数据存设置里（一个 JSON 串）。
class EmbyVideoNote {
  const EmbyVideoNote({
    required this.id,
    required this.videoKey,
    required this.videoTitle,
    required this.positionMs,
    required this.note,
    this.imagePath,
    required this.createdAt,
  });

  final String id;
  final String videoKey;
  final String videoTitle;
  final int positionMs;
  final String note;
  final String? imagePath;
  final int createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'videoKey': videoKey,
    'videoTitle': videoTitle,
    'positionMs': positionMs,
    'note': note,
    if (imagePath != null) 'imagePath': imagePath,
    'createdAt': createdAt,
  };

  static EmbyVideoNote fromJson(Map<String, dynamic> m) => EmbyVideoNote(
    id: m['id']?.toString() ?? '',
    videoKey: m['videoKey']?.toString() ?? '',
    videoTitle: m['videoTitle']?.toString() ?? '',
    positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
    note: m['note']?.toString() ?? '',
    imagePath: m['imagePath']?.toString(),
    createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
  );

  String get positionLabel {
    final seconds = positionMs ~/ 1000;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:$mm:$ss'
        : '$mm:$ss';
  }
}

class EmbyVideoNotes {
  EmbyVideoNotes._() {
    _reload();
  }

  static final EmbyVideoNotes instance = EmbyVideoNotes._();

  static const SettingKey<String> _storeKey = SettingKey<String>(
    'lu.embyVideoNotes',
    '',
    group: SettingGroup.emby,
  );

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<EmbyVideoNote> _notes = <EmbyVideoNote>[];

  void _reload() {
    final raw = GStorage.getSetting(_storeKey);
    if (raw.isEmpty) {
      _notes = <EmbyVideoNote>[];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _notes = [
          for (final e in decoded)
            if (e is Map<String, dynamic>) EmbyVideoNote.fromJson(e),
        ];
      }
    } catch (_) {
      _notes = <EmbyVideoNote>[];
    }
  }

  void _save() {
    GStorage.putSetting(
      _storeKey,
      jsonEncode(_notes.map((EmbyVideoNote n) => n.toJson()).toList()),
    );
    revision.value = revision.value + 1;
  }

  List<EmbyVideoNote> notesFor(String videoKey) => _notes
      .where((EmbyVideoNote n) => n.videoKey == videoKey)
      .toList()
    ..sort((a, b) => a.positionMs.compareTo(b.positionMs));

  List<EmbyVideoNote> get all => List.unmodifiable(_notes);

  /// 添加一条笔记，截图字节可选（非空时落盘）。
  Future<EmbyVideoNote> add({
    required String videoKey,
    required String videoTitle,
    required Duration position,
    required String note,
    Uint8List? screenshot,
  }) async {
    String? imagePath;
    if (screenshot != null && screenshot.isNotEmpty) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final notesDir = Directory('${dir.path}/video_notes');
        if (!await notesDir.exists()) await notesDir.create(recursive: true);
        final fileName =
            'note_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File('${notesDir.path}/$fileName');
        await file.writeAsBytes(screenshot);
        imagePath = file.path;
      } catch (_) {
        imagePath = null;
      }
    }
    final entry = EmbyVideoNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      videoKey: videoKey,
      videoTitle: videoTitle,
      positionMs: position.inMilliseconds,
      note: note.trim(),
      imagePath: imagePath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _notes.add(entry);
    _save();
    return entry;
  }

  void remove(String id) {
    final note = _notes.where((EmbyVideoNote n) => n.id == id).firstOrNull;
    if (note?.imagePath != null) {
      try {
        final file = File(note!.imagePath!);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _notes.removeWhere((EmbyVideoNote n) => n.id == id);
    _save();
  }
}
