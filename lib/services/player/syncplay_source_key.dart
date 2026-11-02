/// 一起看「是不是在看同一集」的判定。
///
/// 原来拿两个人的 `file.name` 直接做字符串相等比较，两端都可能出问题：
/// - LU 客户端上传的是 `番剧id[集数]`，官方 Syncplay 客户端上传的是真实文件名，
///   两者永不相等 —— 只要房间里混进一个别的客户端，就误报「有人在看别的」；
/// - 同一个源换个清晰度（1080p / 720p）文件名不同，也被判成不同；
/// - 反过来，两个不同作品恰好同名，又会被当成同一集而漏报。
///
/// 这里把两边都归一成 `(类型, 标题或番剧 id, 集数)` 再比：能明确判定不同才报，
/// 判不出来就不报 —— 「没提示但画面在同步」比「提示错了」危害小得多。
library;

/// 归一后的片源标识。
class SyncPlaySourceKey {
  const SyncPlaySourceKey._({
    required this.kind,
    required this.title,
    required this.episode,
  });

  /// `lu` = `番剧id[集数]` 标记；`file` = 真实文件名。
  final String kind;

  /// `lu` 时是番剧 id，`file` 时是剥掉画质/字幕组/扩展名之后的主标题。
  final String title;

  /// 集数，抽不出来是 null。
  final int? episode;

  bool get isEmpty => title.isEmpty && episode == null;

  @override
  String toString() => '$kind:$title#${episode ?? '-'}';
}

/// 归一化一个 `file.name`。认不出来返回 null。
SyncPlaySourceKey? syncPlaySourceKey(String? raw) {
  if (raw == null) return null;
  final String text = raw.trim();
  if (text.isEmpty) return null;

  // LU 自己的标记：`12345[3]`。
  final Match? lu = RegExp(r'^(\d+)\[(\d+)\]$').firstMatch(text);
  if (lu != null) {
    return SyncPlaySourceKey._(
      kind: 'lu',
      title: lu.group(1)!,
      episode: int.tryParse(lu.group(2)!),
    );
  }

  // 真实文件名：先抽集数（要在剥括号之前做，`[02]` 这种标记就在括号里），
  // 再剥掉图片相关的噪音，剩下的当标题。
  final String lower = text.toLowerCase();
  final int? episode = _episodeOf(lower);
  final String title = _titleOf(lower);
  if (title.isEmpty && episode == null) return null;
  return SyncPlaySourceKey._(kind: 'file', title: title, episode: episode);
}

/// 两边是不是「不同的东西」。
///
/// 只有能确定不同时才返回 true；任何一边解析不出来、或者信息不足以比较，
/// 都返回 false（宁可漏报）。
bool syncPlaySourcesDiffer(String? mine, String? theirs) {
  final SyncPlaySourceKey? a = syncPlaySourceKey(mine);
  final SyncPlaySourceKey? b = syncPlaySourceKey(theirs);
  if (a == null || b == null) return false;
  if (a.kind == b.kind && a.title == b.title && a.episode == b.episode) {
    return false;
  }

  // 集数是最硬的证据：两边都抽到了集数，不同就是不同。
  if (a.episode != null && b.episode != null && a.episode != b.episode) {
    return true;
  }

  // 两个都是 LU 标记：番剧 id 不同 = 不同作品。
  if (a.kind == 'lu' && b.kind == 'lu') {
    return a.title != b.title;
  }

  // 一个是 LU 标记一个是文件名：标题无从对齐，只能靠集数，已经比过了。
  if (a.kind != b.kind) return false;

  if (a.title.isEmpty || b.title.isEmpty) return false;
  return !_titlesMatch(a.title, b.title);
}

/// 画质 / 编码 / 字幕组这类跟「放的是不是同一集」无关的片段。
const List<String> _noiseTokens = <String>[
  '1080p', '720p', '2160p', '480p', '4k', '8k', 'hdr', 'hdr10', 'dolby',
  'hevc', 'avc', 'x265', 'x264', 'h265', 'h264', '10bit', '8bit', 'hi10p',
  'webdl', 'web-dl', 'webrip', 'web', 'bluray', 'blu-ray', 'bdrip', 'bd',
  'dvdrip', 'hdtv', 'remux', 'aac', 'flac', 'opus', 'ac3', 'dts', 'eac3',
  'mkv', 'mp4', 'avi', 'ass', 'srt', 'chs', 'cht', 'gb', 'big5', 'jpn',
  '简体', '繁体', '简繁', '中字', '内嵌', '外挂', '字幕', '国语', '日语',
  '修复版', '完整版', '合集', 'uncensored', 'repack', 'proper',
];

int? _episodeOf(String lower) {
  // S01E02 / s1e2
  final Match? se = RegExp(r's(\d{1,2})[\s._-]*e(\d{1,4})').firstMatch(lower);
  if (se != null) return int.tryParse(se.group(2)!);
  // 第 2 集 / 第2话
  final Match? cn =
      RegExp(r'第\s*(\d{1,4})\s*[集话話期]').firstMatch(lower);
  if (cn != null) return int.tryParse(cn.group(1)!);
  // [02] / (02) / 【02】
  for (final RegExp re in <RegExp>[
    RegExp(r'[\[\(【]\s*0*(\d{1,4})(?:v\d)?\s*[\]\)】]'),
    RegExp(r'\bep?\s*0*(\d{1,4})\b'),
    RegExp(r'[\s._-]0*(\d{1,4})(?:v\d)?(?=[\s._\-\[]|$)'),
  ]) {
    final Match? m = re.firstMatch(lower);
    if (m == null) continue;
    final int? value = int.tryParse(m.group(1)!);
    // 2000 以上基本是年份/分辨率/码率，不当集数。
    if (value != null && value > 0 && value < 2000) return value;
  }
  return null;
}

String _titleOf(String lower) {
  String t = lower;
  // 扩展名
  t = t.replaceAll(RegExp(r'\.(mkv|mp4|avi|rmvb|flv|mov|ts|m2ts|webm)$'), '');
  // 所有括号组（字幕组、画质标记、集数标记都在里面）
  t = t.replaceAll(RegExp(r'[\[\(【{][^\]\)】}]*[\]\)】}]'), ' ');
  // 剩下的噪音词
  t = t.replaceAll(RegExp(r'[._\-]+'), ' ');
  final List<String> kept = <String>[];
  for (final String token in t.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (_noiseTokens.contains(token)) continue;
    if (RegExp(r'^\d+$').hasMatch(token)) continue;
    kept.add(token);
  }
  return kept.join(' ').trim();
}

bool _titlesMatch(String a, String b) {
  if (a == b) return true;
  if (a.isEmpty || b.isEmpty) return false;
  final Set<String> sa = a.split(' ').where((String s) => s.isNotEmpty).toSet();
  final Set<String> sb = b.split(' ').where((String s) => s.isNotEmpty).toSet();
  if (sa.isEmpty || sb.isEmpty) return false;
  final int shared = sa.intersection(sb).length;
  // 分母取两边较大的那个：用「包含」判断会把续作当成同一部
  // （`Sword Art Online` 和 `Sword Art Online II` 是两部番）。
  final int denom = sa.length > sb.length ? sa.length : sb.length;
  return shared / denom >= 0.8;
}
