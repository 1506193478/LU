import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// 一起看里把「自己的头像」传给房间里其他人用的控制消息。
///
/// 复用表情包那套分片思路：Syncplay 单条聊天硬截断到 150 字符，所以头像先
/// 压成很小的 JPEG 缩略图（base64 后通常 1~3KB），再按 150 字符一片发出去。
/// 收到的一方把这些分片拼回 base64、解码成内存图，聊天和成员区就能显示对方
/// 真实头像了（协议本身不传头像，这是走 Chat 通道自己带上的）。
class SyncPlayAvatarMessage {
  SyncPlayAvatarMessage(this.base64);

  final String base64;

  /// 协议标记；收到不认识的前缀一律当普通聊天处理。
  static const String prefix = 'LUSAV1|';
  static const int maxChatLength = 150;

  /// 分片头预留长度。
  ///
  /// 头是 `<id>/<序号>/<总数>|`，id 固定 4 字符，序号和总数各最多 2 位，
  /// 所以最长是 `abcd/99/99|` = 11 字符。**必须按 11 留，不能按 10**：
  /// 留 10 的话分片数 ≥10 时每条会到 151 字符，被服务端硬截断到 150，
  /// 每片末尾少一个字符，base64 就永远拼不回来（表现为头像一直不显示）。
  static const int _headerReserve = 12;
  static const int _chunkSize = maxChatLength - prefix.length - _headerReserve;

  /// 一次广播最多允许几片。
  ///
  /// 同步协议本来就不是传图片用的，一次性灌二三十条聊天消息会触发服务端的
  /// 刷屏保护并断开连接。超过这个数就干脆不广播，退回首字色块。
  static const int maxChunks = 8;

  /// 每片之间的间隔，避免瞬间洪水把连接冲断。
  static const Duration chunkInterval = Duration(milliseconds: 80);

  /// 切成若干条不超过 [maxChatLength] 的聊天消息。
  List<String> encodeChunks({String? messageId}) {
    final String id = messageId ?? _randomId();
    final int total = (base64.length / _chunkSize).ceil().clamp(1, 99);
    final List<String> chunks = [];
    for (var index = 0; index < total; index++) {
      final start = index * _chunkSize;
      final end = min(start + _chunkSize, base64.length);
      chunks.add(
        '$prefix$id/${index + 1}/$total|${base64.substring(start, end)}',
      );
    }
    return chunks;
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static bool isAvatar(String text) => text.startsWith(prefix);
}

class SyncPlayAvatarPart {
  const SyncPlayAvatarPart({
    required this.messageId,
    required this.index,
    required this.total,
    required this.payload,
  });

  final String messageId;
  final int index;
  final int total;
  final String payload;

  static SyncPlayAvatarPart? tryParse(String text) {
    if (!text.startsWith(SyncPlayAvatarMessage.prefix)) return null;
    final rest = text.substring(SyncPlayAvatarMessage.prefix.length);
    final headerEnd = rest.indexOf('|');
    if (headerEnd <= 0) return null;
    final header = rest.substring(0, headerEnd).split('/');
    if (header.length != 3) return null;
    final index = int.tryParse(header[1]);
    final total = int.tryParse(header[2]);
    if (index == null || total == null) return null;
    if (index < 1 || total < 1 || index > total || total > 99) return null;
    return SyncPlayAvatarPart(
      messageId: header[0],
      index: index,
      total: total,
      payload: rest.substring(headerEnd + 1),
    );
  }
}

/// 按发送者 + 消息 id 把分片拼回完整 base64；没收齐返回 null。
class SyncPlayAvatarAssembler {
  static const int _maxPendingGroups = 16;

  final Map<String, Map<int, String>> _parts = {};
  final Map<String, int> _totals = {};

  String? add(String sender, String text) {
    final part = SyncPlayAvatarPart.tryParse(text);
    if (part == null) return null;
    final key = '$sender#${part.messageId}';
    if (_parts.length >= _maxPendingGroups && !_parts.containsKey(key)) {
      _parts.clear();
      _totals.clear();
    }
    final buffer = _parts.putIfAbsent(key, () => {});
    _totals[key] = part.total;
    buffer[part.index] = part.payload;
    if (buffer.length < _totals[key]!) return null;
    final joined = StringBuffer();
    for (var index = 1; index <= _totals[key]!; index++) {
      final chunk = buffer[index];
      if (chunk == null) return null;
      joined.write(chunk);
    }
    _parts.remove(key);
    _totals.remove(key);
    final full = joined.toString();
    return full.isEmpty ? null : full;
  }

  void reset() {
    _parts.clear();
    _totals.clear();
  }
}

/// 把本机头像压成很小的 JPEG 缩略图并返回 base64；没有头像或解码失败返回 null。
///
/// 尺寸压到 32x32：聊天里的头像只有 22~32 px，这个尺寸足够清晰，而 base64
/// 能落在 1KB 以内 —— 按 131 字符一片算大约 5~8 片，既拼得回来又不会刷屏。
/// 之前用 64x64 会切出 20~30 片，一次性灌出去直接把连接冲断。
Future<String?> encodeLocalAvatar(String path) async {
  if (path.isEmpty) return null;
  final File file = File(path);
  if (!await file.exists()) return null;
  try {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(
      decoded,
      width: 32,
      height: 32,
      interpolation: img.Interpolation.average,
    );
    final jpg = img.encodeJpg(resized, quality: 40);
    return base64Encode(jpg);
  } catch (_) {
    return null;
  }
}
