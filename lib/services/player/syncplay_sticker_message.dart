import 'dart:convert';
import 'dart:math';

/// 一起看聊天里的一条表情包消息。
///
/// 复用播放请求那套思路：Syncplay 的 `Chat` 通道把单条消息**硬截断到 150
/// 字符**，图片本身塞不进去，所以只传「包 id + 表情 id + 图片地址」。
/// 内置包不带地址，接收方直接读本地 asset；网络包带地址，接收方按地址取图。
class SyncPlayStickerMessage {
  const SyncPlayStickerMessage({
    required this.packId,
    required this.stickerId,
    this.url = '',
  });

  /// 协议标记，改版本时改这里；收到不认识的前缀一律当普通聊天处理。
  static const String prefix = 'LUSTK1|';

  /// 官方服务器对单条聊天内容的长度上限（字符数，非字节数）。
  static const int maxChatLength = 150;

  /// 分片头 `id/序号/总数|` 预留的长度。
  static const int _headerReserve = 10;

  static const int _chunkSize = maxChatLength - prefix.length - _headerReserve;

  final String packId;
  final String stickerId;

  /// 图片地址；内置表情包为空。
  final String url;

  bool get isBuiltin => url.isEmpty;

  Map<String, dynamic> _toJson() => {
        'p': packId,
        'i': stickerId,
        if (url.isNotEmpty) 'u': url,
      };

  /// 切成若干条不超过 [maxChatLength] 的聊天消息。
  List<String> encodeChunks({String? messageId}) {
    final payload = jsonEncode(_toJson());
    final id = messageId ?? _randomId();
    final total = (payload.length / _chunkSize).ceil().clamp(1, 99);
    final chunks = <String>[];
    for (var index = 0; index < total; index++) {
      final start = index * _chunkSize;
      final end = min(start + _chunkSize, payload.length);
      chunks.add(
        '$prefix$id/${index + 1}/$total|${payload.substring(start, end)}',
      );
    }
    return chunks;
  }

  /// 本地回显用的单条形式：不管发出去切了几片，聊天列表里只留一条。
  String encodeSingle() => '${prefix}1/1/1|${jsonEncode(_toJson())}';

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static bool isSticker(String text) => text.startsWith(prefix);

  static SyncPlayStickerMessage? tryDecodePayload(String payload) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      final pack = json['p']?.toString() ?? '';
      final sticker = json['i']?.toString() ?? '';
      if (pack.isEmpty || sticker.isEmpty) return null;
      return SyncPlayStickerMessage(
        packId: pack,
        stickerId: sticker,
        url: json['u']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析一条完整的（单片的）表情包聊天。
  static SyncPlayStickerMessage? tryDecodeChat(String text) {
    final part = SyncPlayStickerPart.tryParse(text);
    if (part == null || part.index != 1 || part.total != 1) return null;
    return tryDecodePayload(part.payload);
  }
}

/// 一个分片消息的解析结果。
class SyncPlayStickerPart {
  const SyncPlayStickerPart({
    required this.messageId,
    required this.index,
    required this.total,
    required this.payload,
  });

  final String messageId;
  final int index;
  final int total;
  final String payload;

  static SyncPlayStickerPart? tryParse(String text) {
    if (!text.startsWith(SyncPlayStickerMessage.prefix)) return null;
    final rest = text.substring(SyncPlayStickerMessage.prefix.length);
    final headerEnd = rest.indexOf('|');
    if (headerEnd <= 0) return null;
    final header = rest.substring(0, headerEnd).split('/');
    if (header.length != 3) return null;
    final index = int.tryParse(header[1]);
    final total = int.tryParse(header[2]);
    if (index == null || total == null) return null;
    if (index < 1 || total < 1 || index > total || total > 99) return null;
    return SyncPlayStickerPart(
      messageId: header[0],
      index: index,
      total: total,
      payload: rest.substring(headerEnd + 1),
    );
  }
}

/// 按发送者 + 消息 id 把分片拼回完整表情包消息。
class SyncPlayStickerAssembler {
  static const int _maxPendingGroups = 16;

  final Map<String, Map<int, String>> _parts = {};
  final Map<String, int> _totals = {};

  SyncPlayStickerMessage? add(String sender, String text) {
    final part = SyncPlayStickerPart.tryParse(text);
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
    return SyncPlayStickerMessage.tryDecodePayload(joined.toString());
  }

  void reset() {
    _parts.clear();
    _totals.clear();
  }
}
