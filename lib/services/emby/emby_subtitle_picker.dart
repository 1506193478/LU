import 'package:XL/modules/emby/emby_models.dart';

/// 起播时该自动挂哪一条字幕。
///
/// 单独抽出来是因为这段判断是纯函数：给它字幕流列表和偏好，它给一个下标，
/// 不需要播放器、也不需要服务端，能用 `dart run` 直接验。以前这块是空的——
/// 面板里明明列出了 Emby 自带的中文字幕，但起播后一条都不显示，用户必须先
/// 手动点开「字幕」再挑一次，观感上就是「字幕功能没有」。
///
/// 优先级（越靠前越优先）：
///   1. 首选语言 + 完整字幕（非 forced、非听障）
///   2. 首选语言 + 非听障
///   3. 首选语言（其余情况，比如只有 forced 或只有听障版）
///   4. 服务端标了 `IsDefault` 的非强制轨
///   5. 都没有 → 不挂（返回 null，面板里显示「禁用」）
///
/// 完整字幕排在 forced 前面是刻意的：`[Forced]` 只翻译画面上的外语和招牌，
/// 一部外语片上如果同时有「中文（简体）」和「中文（简体）[Forced]」，
/// 挂 forced 会让人以为字幕坏了。只有在没有完整字幕时才退到 forced。
///
/// 最后一条也是刻意的：外国片只有英文字幕时，很多播放器会自作主张挂上，
/// 中文用户看得很别扭。宁可空着，让用户自己挑。
int? pickDefaultSubtitleIndex({
  required List<EmbyMediaStream> streams,
  required String preferredLanguage,
  bool disabled = false,
}) {
  if (disabled) return null;
  final subtitles = <int>[
    for (var i = 0; i < streams.length; i++)
      if (streams[i].isSubtitle) i,
  ];
  if (subtitles.isEmpty) return null;

  final want = normalizeSubtitleLanguage(preferredLanguage);
  bool matches(int i) =>
      want.isNotEmpty && normalizeSubtitleLanguage(streams[i].language) == want;

  if (want.isNotEmpty) {
    for (final i in subtitles) {
      if (matches(i) && !streams[i].isForced && !streams[i].isHearingImpaired) {
        return i;
      }
    }
    for (final i in subtitles) {
      if (matches(i) && !streams[i].isHearingImpaired) return i;
    }
    for (final i in subtitles) {
      if (matches(i)) return i;
    }
  }

  for (final i in subtitles) {
    if (streams[i].isDefault && !streams[i].isForced) return i;
  }
  return null;
}

/// 把 Emby 可能给出的各种语言写法收敛成三字码。
///
/// 同一个「中文」，不同服务端会给 `chi` / `zho` / `zh` / `zh-CN` / `Chinese`，
/// 直接字符串比较永远匹配不上。
String normalizeSubtitleLanguage(String raw) {
  final v = raw.trim().toLowerCase();
  if (v.isEmpty) return '';
  if (v.startsWith('zh') || v.startsWith('chi') || v == 'chinese' || v == 'cmn') {
    return 'chi';
  }
  if (v.startsWith('en') || v.startsWith('eng') || v == 'english') return 'eng';
  if (v.startsWith('ja') || v.startsWith('jpn') || v == 'japanese') return 'jpn';
  if (v.startsWith('ko') || v.startsWith('kor') || v == 'korean') return 'kor';
  if (v.length == 2) {
    return switch (v) {
      'zh' => 'chi',
      'en' => 'eng',
      'ja' => 'jpn',
      'ko' => 'kor',
      _ => v,
    };
  }
  return v.length >= 3 ? v.substring(0, 3) : v;
}

/// 面板上那句话：「这条视频有 4 条字幕」/「没有内封字幕」。
String subtitleSummary(List<EmbyMediaStream> streams) {
  final count = streams.where((s) => s.isSubtitle).length;
  if (count == 0) return '这条视频没有内封字幕';
  return '$count 条字幕';
}
