import 'dart:convert';
import 'dart:math';

import 'package:XL/modules/bangumi/bangumi_item.dart';

/// 房主点「开始一起看」时，通过房间聊天通道广播给其他成员的播放请求。
///
/// Syncplay 协议只有 `Hello` / `State` / `Set` / `Chat` 四种消息，没有
/// 「我要播这个」这种语义，但 `Chat` 会被服务端原样转发给房间内所有人，
/// 所以借它当载体：固定前缀 + 分片序号 + JSON 正文。
///
/// 为什么必须分片：官方服务器把单条聊天**硬截断到 150 个字符**（实测
/// 288 字符的消息收到时只剩 150 字符，base64 直接解不开），而一条完整的
/// 播放请求（含剧集地址、封面地址、中/日文标题）通常 200~400 字符。
class SyncPlayPlayRequest {
  const SyncPlayPlayRequest({
    required this.bangumiId,
    required this.name,
    required this.nameCn,
    required this.coverUrl,
    required this.pluginName,
    required this.title,
    required this.src,
    this.target = '',
  });

  /// 协议标记，改版本时改这里；收到不认识的前缀一律当普通聊天忽略。
  static const String prefix = 'XLPLAY1|';

  /// 官方服务器对单条聊天内容的长度上限（字符数，非字节数）。
  static const int maxChatLength = 150;

  /// 分片之间的发送间隔。服务端有刷屏保护，一次灌太快整批消息会被丢，
  /// 接收方凑不齐分片就永远拉不起播放器（和头像广播共用同一个节拍）。
  static const Duration chunkInterval = Duration(milliseconds: 80);

  /// 分片头 `id/序号/总数|` 预留的长度：4 位 id + 两位数字 + 分隔符。
  /// 分片头 `<id>/<序号>/<总数>|` 最长 11 字符，必须按 11 以上留。
  /// 留 10 的话分片数 ≥10 时每条会到 151 字符被服务端截断，末尾丢字符。
  static const int _headerReserve = 12;

  static const int _chunkSize = maxChatLength - prefix.length - _headerReserve;

  final int bangumiId;
  final String name;
  final String nameCn;
  final String coverUrl;

  /// 规则源名称，接收方按名字在自己已装的规则里找同一个源。
  final String pluginName;

  /// 条目名（通常就是剧集标题）。
  final String title;

  /// 条目地址，接收方据此重新拉取剧集列表。
  final String src;

  /// 定向接收者的用户名；空串表示广播给全房间。
  ///
  /// 「后来的人点『拉取正在播放』」时，正在播放的成员把当前番剧**定向**
  /// 回给请求者，其他成员（往往也在看同一部）不该被这条请求拽着重新拉起
  /// 播放器。聊天通道本身是广播的，定向只能靠 payload 里带上对方名字，
  /// 收到的人自己判断这条是不是发给自己的。
  final String target;

  Map<String, dynamic> _toJson() => {
        'b': bangumiId,
        'n': name,
        'c': nameCn,
        'i': coverUrl,
        'p': pluginName,
        't': title,
        's': src,
        // 只在定向时写这个键，普通广播的 payload 和旧版本完全一致。
        if (target.isNotEmpty) 'o': target,
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

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// 生成一个随机的消息 id。发送方先生成 id、用同一个 id 发两轮（原样重发），
  /// 接收方按 `sender#id` 归位，重发正好把可能丢掉的分片补上。
  static String randomMessageId() => _randomId();

  /// 不是播放请求（或者是别的版本）时返回 null。
  static SyncPlayPlayRequest? tryDecodePayload(String payload) {
    try {
      final json = jsonDecode(payload);
      if (json is! Map) return null;
      final plugin = json['p']?.toString() ?? '';
      final src = json['s']?.toString() ?? '';
      if (plugin.isEmpty || src.isEmpty) return null;
      return SyncPlayPlayRequest(
        bangumiId: (json['b'] as num?)?.toInt() ?? 0,
        name: json['n']?.toString() ?? '',
        nameCn: json['c']?.toString() ?? '',
        coverUrl: json['i']?.toString() ?? '',
        pluginName: plugin,
        title: json['t']?.toString() ?? '',
        src: src,
        target: json['o']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static bool isPlayRequest(String text) => text.startsWith(prefix);

  /// 接收方据此还原出播放器需要的番剧信息。
  ///
  /// 播放器只用到 id / name / nameCn / images['large']，其余字段给默认值，
  /// 免得为了一个封面再去请求一次 Bangumi 详情接口。
  BangumiItem toBangumiItem() => BangumiItem(
        id: bangumiId,
        type: 2,
        name: name,
        nameCn: nameCn,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: coverUrl.isEmpty ? const {} : {'large': coverUrl},
        tags: const [],
        alias: const [],
        ratingScore: 0,
        votes: 0,
        votesCount: const [],
        info: '',
      );
}

/// 一个分片消息的解析结果。
class SyncPlayPlayRequestPart {
  const SyncPlayPlayRequestPart({
    required this.messageId,
    required this.index,
    required this.total,
    required this.payload,
  });

  final String messageId;
  final int index;
  final int total;
  final String payload;

  /// 从一条聊天文本里拆出分片头；不是本协议的消息返回 null。
  static SyncPlayPlayRequestPart? tryParse(String text) {
    if (!text.startsWith(SyncPlayPlayRequest.prefix)) return null;
    final rest = text.substring(SyncPlayPlayRequest.prefix.length);
    final headerEnd = rest.indexOf('|');
    if (headerEnd <= 0) return null;
    final header = rest.substring(0, headerEnd).split('/');
    if (header.length != 3) return null;
    final index = int.tryParse(header[1]);
    final total = int.tryParse(header[2]);
    if (index == null || total == null) return null;
    if (index < 1 || total < 1 || index > total || total > 99) return null;
    return SyncPlayPlayRequestPart(
      messageId: header[0],
      index: index,
      total: total,
      payload: rest.substring(headerEnd + 1),
    );
  }
}

/// 按发送者 + 消息 id 把分片拼回完整请求。
///
/// 房间内的聊天由同一条 TCP 连接按序送达，所以分片顺序本身是有保证的，
/// 这里只是按序号归位，避免某条消息被服务端丢弃时拼出错乱的内容。
class SyncPlayPlayRequestAssembler {
  /// 最多同时跟踪的分片组数量，防止异常流量把内存撑爆。
  static const int _maxPendingGroups = 16;

  /// 一组分片最多等多久。正常一轮分片 80ms 一条、几条就收完；
  /// 超过这个时间还收不齐，说明中间的分片被服务端丢了，而发送方的
  /// 重发窗口（约 1.2s 后原样重发一轮）也早就过了，再挂着没意义。
  static const Duration _pendingTimeout = Duration(seconds: 10);

  final Map<String, Map<int, String>> _parts = {};
  final Map<String, int> _totals = {};
  final Map<String, DateTime> _createdAt = {};

  /// 清掉等了太久的挂起分组。之前是溢出时整表清空——那会把正在慢慢
  /// 收分片的组也一起扔掉，等于别人正常广播到一半被一句话全作废。
  void _pruneStale() {
    final DateTime now = DateTime.now();
    for (final String key in List<String>.of(_createdAt.keys)) {
      final DateTime at = _createdAt[key]!;
      if (now.difference(at) > _pendingTimeout) {
        _parts.remove(key);
        _totals.remove(key);
        _createdAt.remove(key);
      }
    }
  }

  /// 挂起分组满了就淘汰最早创建的一组，而不是整表清空。
  void _evictOldest() {
    String? oldestKey;
    DateTime? oldestAt;
    for (final MapEntry<String, DateTime> entry in _createdAt.entries) {
      if (oldestAt == null || entry.value.isBefore(oldestAt)) {
        oldestAt = entry.value;
        oldestKey = entry.key;
      }
    }
    if (oldestKey != null) {
      _parts.remove(oldestKey);
      _totals.remove(oldestKey);
      _createdAt.remove(oldestKey);
    }
  }

  /// 收齐一个完整请求时返回它，否则返回 null。
  SyncPlayPlayRequest? add(String sender, String text) {
    final part = SyncPlayPlayRequestPart.tryParse(text);
    if (part == null) return null;
    final key = '$sender#${part.messageId}';
    _pruneStale();
    if (_parts.length >= _maxPendingGroups && !_parts.containsKey(key)) {
      _evictOldest();
    }
    _createdAt.putIfAbsent(key, () => DateTime.now());
    final buffer = _parts.putIfAbsent(key, () => {});
    _totals[key] = part.total;
    buffer[part.index] = part.payload;
    final total = _totals[key]!;
    if (buffer.length < total) return null;
    final joined = StringBuffer();
    for (var index = 1; index <= total; index++) {
      final chunk = buffer[index];
      if (chunk == null) return null;
      joined.write(chunk);
    }
    _parts.remove(key);
    _totals.remove(key);
    _createdAt.remove(key);
    return SyncPlayPlayRequest.tryDecodePayload(joined.toString());
  }

  void reset() {
    _parts.clear();
    _totals.clear();
    _createdAt.clear();
  }
}
