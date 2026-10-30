/// 一起看里两条「轻量房间信号」：置顶公告和敲一敲。
///
/// 和播放请求一样借 Chat 通道发，但都很短，不需要分片。前缀统一用 `XL` +
/// 一个大写字母 + `1|`，避免和播放请求（`XLPLAY1|`）、表情包（`LUSTK1|`）、
/// 反应（`XLR1|`）、倒计时（`XLC1|`）撞车 —— 撞车的后果是一种消息被另一种
/// 先截走，而且很难查。
library;

/// 置顶公告：房主把一句话钉在房间卡片顶部。
class SyncPlayPin {
  const SyncPlayPin._();

  static const String prefix = 'XLP1|';

  /// 公告长度上限。
  ///
  /// 服务端单条聊天硬截断 150 字符，这里留足余量，也免得有人把一整段
  /// 小作文钉在别人屏幕顶上。
  static const int maxLength = 80;

  static String encode(String text) {
    final String cleaned = _clean(text);
    if (cleaned.length > maxLength) {
      return '$prefix${cleaned.substring(0, maxLength)}';
    }
    return '$prefix$cleaned';
  }

  static bool isPin(String text) => text.startsWith(prefix);

  /// 解析出公告正文；空内容或不是本协议时返回 null。
  static String? tryParse(String text) {
    if (!isPin(text)) {
      return null;
    }
    final String body = _clean(text.substring(prefix.length));
    return body.isEmpty ? null : body;
  }

  /// 换行会把「一行公告」撑成一大块，统一压成空格。
  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 敲一敲：提醒某个成员「跟上 / 看这里」。
class SyncPlayNudge {
  const SyncPlayNudge._();

  static const String prefix = 'XLN1|';

  /// 用户名长度上限，和服务端允许的昵称长度对齐还留了余量。
  static const int maxNameLength = 32;

  static String encode(String target) => '$prefix${target.trim()}';

  static bool isNudge(String text) => text.startsWith(prefix);

  /// 解析出被敲的人；空名字、含分隔符、过长都算非法。
  static String? tryParse(String text) {
    if (!isNudge(text)) {
      return null;
    }
    final String target = text.substring(prefix.length).trim();
    if (target.isEmpty || target.length > maxNameLength) {
      return null;
    }
    // 名字里不该有竖线，出现就说明这条消息是拼出来的。
    if (target.contains('|')) {
      return null;
    }
    return target;
  }
}

/// 共享播放队列：房间里「接下来看哪几集」。
///
/// 整份列表一起发、谁发谁覆盖（last write wins）。排片这种低冲突操作没必要
/// 做 CRDT，房间人数也就几个，冲突了顶多是谁后点谁算。
///
/// 用逗号分隔的集数：`XLQ1|3,4,5`。服务端单条聊天 150 字符硬截断，
/// [maxEntries] 就是按这个上限留足余量定的。
class SyncPlayQueue {
  const SyncPlayQueue._();

  static const String prefix = 'XLQ1|';

  /// 队列最多几集。
  static const int maxEntries = 12;

  static String encode(List<int> episodes) =>
      '$prefix${normalize(episodes).join(',')}';

  static bool isQueue(String text) => text.startsWith(prefix);

  /// 解析成集数列表；不是本协议或内容为空时返回空列表（等于「清空队列」）。
  static List<int> tryParse(String text) {
    if (!isQueue(text)) {
      return const <int>[];
    }
    final String body = text.substring(prefix.length).trim();
    if (body.isEmpty) {
      return const <int>[];
    }
    return normalize(
      body.split(',').map((String part) => int.tryParse(part.trim()) ?? 0),
    );
  }

  /// 只留正数、去重、保持顺序、截到上限。
  ///
  /// 解析别人的消息时也必须过这一遍：对方客户端可能被改过，不能把
  /// 0 / 负数 / 上千集直接塞进列表。
  static List<int> normalize(Iterable<int> episodes) {
    final Set<int> seen = <int>{};
    final List<int> result = <int>[];
    for (final int episode in episodes) {
      if (episode <= 0 || !seen.add(episode)) {
        continue;
      }
      result.add(episode);
      if (result.length >= maxEntries) {
        break;
      }
    }
    return result;
  }
}

/// 「等我一下」：全房间暂停 N 秒再一起继续。
///
/// 和置顶公告、敲一敲一样借聊天通道发一条短信号。传「暂停多少秒」而不是
/// 绝对时间戳 —— 各人本机时钟不可信，秒数才是共识。
class SyncPlayStall {
  const SyncPlayStall._();

  static const String prefix = 'XLS1|';

  /// 默认等多久。30 秒大约是一次缓冲 + 手动重连的时间。
  static const int defaultSeconds = 30;

  /// 允许的范围：太短没意义，太长等于把房间冻住。
  static const int minSeconds = 5;
  static const int maxSeconds = 120;

  static String encode(int seconds) => '$prefix${clampSeconds(seconds)}';

  static bool isStall(String text) => text.startsWith(prefix);

  /// 解析出要等的秒数；非法或不是本协议时返回 null。
  static int? tryParse(String text) {
    if (!isStall(text)) {
      return null;
    }
    final int? seconds = int.tryParse(text.substring(prefix.length).trim());
    if (seconds == null) {
      return null;
    }
    return clampSeconds(seconds);
  }

  static int clampSeconds(int seconds) =>
      seconds.clamp(minSeconds, maxSeconds);
}

/// 投票要决定的事。
enum SyncPlayVoteKind { pause, resume, episode }

/// 房间投票：有人想暂停 / 继续 / 换集，过半自动执行，房主一票否决。
///
/// 消息格式：`XLV1|<id>|<kind>|<value>|<stance>`，stance ∈ start / yes / no。
/// 每台客户端都收得到全部表态，各自本地算票，不依赖「谁负责计票」——
/// 计票人掉线就全废，那是设计事故。
class SyncPlayVote {
  const SyncPlayVote._();

  static const String prefix = 'XLV1|';

  /// 一次投票最多活多久。到点没结果就当没提过。
  static const Duration lifetime = Duration(seconds: 30);

  static String encode({
    required String id,
    required SyncPlayVoteKind kind,
    required int value,
    required String stance,
  }) =>
      '$prefix$id|${_kindCode(kind)}|$value|$stance';

  static bool isVote(String text) => text.startsWith(prefix);

  /// 解析一条投票消息；格式不对返回 null（宁可当没收到）。
  static SyncPlayVoteMessage? tryParse(String text) {
    if (!isVote(text)) {
      return null;
    }
    final List<String> parts = text.substring(prefix.length).split('|');
    if (parts.length != 4) {
      return null;
    }
    final String id = parts[0].trim();
    final SyncPlayVoteKind? kind = _kindFromCode(parts[1].trim());
    final int? value = int.tryParse(parts[2].trim());
    final String stance = parts[3].trim();
    if (id.isEmpty || kind == null || value == null) {
      return null;
    }
    if (stance != 'start' && stance != 'yes' && stance != 'no') {
      return null;
    }
    return SyncPlayVoteMessage(
      id: id,
      kind: kind,
      value: value,
      stance: stance,
    );
  }

  /// 票数够了没有。
  ///
  /// 条件写成 `yes * 2 >= total && yes > no`：
  /// - 两个人时，一人同意、没人反对就算过（真按「严格过半」两人房永远过不了）；
  /// - 四个人时要 2 票；
  /// - 有人反对就必须比反对多。
  static bool isPassed({
    required int yes,
    required int no,
    required int totalMembers,
  }) {
    final int total = totalMembers <= 0 ? yes + no : totalMembers;
    if (yes == 0) {
      return false;
    }
    return yes * 2 >= total && yes > no;
  }

  static String _kindCode(SyncPlayVoteKind kind) => switch (kind) {
        SyncPlayVoteKind.pause => 'p',
        SyncPlayVoteKind.resume => 'r',
        SyncPlayVoteKind.episode => 'e',
      };

  static SyncPlayVoteKind? _kindFromCode(String code) => switch (code) {
        'p' => SyncPlayVoteKind.pause,
        'r' => SyncPlayVoteKind.resume,
        'e' => SyncPlayVoteKind.episode,
        _ => null,
      };
}

class SyncPlayVoteMessage {
  const SyncPlayVoteMessage({
    required this.id,
    required this.kind,
    required this.value,
    required this.stance,
  });

  final String id;
  final SyncPlayVoteKind kind;

  /// 只有 [SyncPlayVoteKind.episode] 用得上：目标集数。
  final int value;

  /// start / yes / no。
  final String stance;
}

/// 片源指纹：我这边用的是哪个插件的哪条线路。
///
/// 一起看最常见的「不同步」不是网速，是两个人根本不是同一个片源：
/// 时长不同、集数编号不同，怎么对齐都对不上。把指纹广播出来，
/// 对方至少知道该切哪条线路（同插件时能一键切，跨插件只能提示）。
class SyncPlaySourceTag {
  const SyncPlaySourceTag._();

  static const String prefix = 'XLF1|';

  static const int maxNameLength = 40;

  static String encode({
    required String pluginName,
    required int road,
    required String roadName,
  }) =>
      '$prefix${_clean(pluginName)}|$road|${_clean(roadName)}';

  static bool isSourceTag(String text) => text.startsWith(prefix);

  static SyncPlaySourceInfo? tryParse(String text) {
    if (!isSourceTag(text)) {
      return null;
    }
    final List<String> parts = text.substring(prefix.length).split('|');
    if (parts.length != 3) {
      return null;
    }
    final String plugin = parts[0].trim();
    final int? road = int.tryParse(parts[1].trim());
    final String roadName = parts[2].trim();
    if (plugin.isEmpty || road == null || road < 0) {
      return null;
    }
    return SyncPlaySourceInfo(
      pluginName: plugin,
      road: road,
      roadName: roadName,
    );
  }

  /// 竖线是分隔符，名字里带竖线会把消息拼坏，统一换成空格并截断。
  static String _clean(String name) {
    final String cleaned = name.replaceAll('|', ' ').trim();
    return cleaned.length > maxNameLength
        ? cleaned.substring(0, maxNameLength)
        : cleaned;
  }
}

class SyncPlaySourceInfo {
  const SyncPlaySourceInfo({
    required this.pluginName,
    required this.road,
    required this.roadName,
  });

  final String pluginName;
  final int road;
  final String roadName;
}
