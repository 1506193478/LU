/// 极简 SRT / WebVTT 解析（AVPlayer 路径的外挂字幕）。
///
/// 为什么需要它：AVPlayer 不吃 srt/ass 挂载（mpv 才行），Emby 服务端的字幕
/// 下载地址可以强制 `Stream.srt` 交付格式（服务端会转换），拉回来是纯文本，
/// 在 Dart 里按时间轴切开、跟着 position 显示即可。ASS 的排版指令不解析——
/// 转码场景下字幕本来就是陪跑，能看比好看重要。
class SrtCue {
  const SrtCue({required this.start, required this.end, required this.text});

  final Duration start;
  final Duration end;
  final String text;
}

/// 解析 SRT（或 VTT，时间轴格式一样）。解析失败返回空列表，不让播放器崩。
List<SrtCue> parseSrt(String raw) {
  final text = raw
      .replaceAll('\r\n', '\n')
      .replaceFirst(RegExp(r'^WEBVTT.*\n', multiLine: false), '')
      .trim();
  if (text.isEmpty) return const [];
  final cues = <SrtCue>[];
  for (final block in text.split(RegExp(r'\n{2,}'))) {
    final lines = block
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) continue;
    // 第一行可能是序号，找到带时间轴的那行。
    var timeIndex = lines.indexWhere((l) => l.contains('-->'));
    if (timeIndex < 0) continue;
    final match = RegExp(
      r'(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)',
    ).firstMatch(lines[timeIndex]);
    if (match == null) continue;
    final start = _time(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
    final end = _time(
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
      int.parse(match.group(7)!),
      int.parse(match.group(8)!),
    );
    final body = lines.skip(timeIndex + 1).join('\n');
    if (body.isEmpty) continue;
    cues.add(SrtCue(start: start, end: end, text: _stripTags(body)));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

Duration _time(int h, int m, int s, int ms) =>
    Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);

/// 去掉 `<i>` 这类内联标签和 VTT 的行定位指令，保留纯文本。
String _stripTags(String input) => input
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll(RegExp(r'^\{\\[^}]*\}', multiLine: true), '')
    .trim();

/// 找 [position]（已含字幕延迟偏移）命中的字幕；没有返回 null。
SrtCue? srtCueAt(List<SrtCue> cues, Duration position) {
  if (cues.isEmpty) return null;
  // 双分区都在线外时二分第一个 start > position 的位置再回退一格。
  int lo = 0;
  int hi = cues.length - 1;
  int candidate = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= position) {
      candidate = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (candidate < 0) return null;
  final cue = cues[candidate];
  return position <= cue.end ? cue : null;
}
