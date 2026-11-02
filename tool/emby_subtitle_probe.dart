// 临时探针：验 pickDefaultSubtitleIndex 的挑轨逻辑（不受沙箱 flutter test 限制）。
import 'dart:convert';
import 'dart:io';

import '../lib/modules/emby/emby_models.dart';
import '../lib/services/emby/emby_subtitle_picker.dart';

int pass = 0;
int fail = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (ok) {
    pass++;
  } else {
    fail++;
    stdout.writeln('FAIL $name -> got $actual, want $expected');
  }
}

/// 按 Emby PlaybackInfo 的真实 JSON 形状造一条字幕流。
EmbyMediaStream sub({
  required int index,
  String lang = '',
  String title = '',
  bool forced = false,
  bool isDefault = false,
  bool hi = false,
  String codec = 'subrip',
}) =>
    EmbyMediaStream.fromJson(<String, dynamic>{
      'Index': index,
      'Type': 'Subtitle',
      'Codec': codec,
      'Language': lang,
      'DisplayTitle': title,
      'IsForced': forced,
      'IsDefault': isDefault,
      'IsHearingImpaired': hi,
      'IsTextSubtitleStream': codec == 'subrip' || codec == 'ass',
    });

void main() {
  // 真实场景：一部剧内封 4 条中/英字幕，服务端把简体标成默认。
  final streams = [
    sub(index: 2, lang: 'chi', title: '中文（简体）', isDefault: true),
    sub(index: 3, lang: 'chi', title: '中文（简体）[Forced]', forced: true),
    sub(index: 4, lang: 'zh-TW', title: '中文（繁體）'),
    sub(index: 5, lang: 'eng', title: 'English'),
  ];

  check('首选中文 → 完整简体', pickDefaultSubtitleIndex(streams: streams, preferredLanguage: 'chi'), 0);
  // 简繁不区分：都归到 chi，命中第一条中文字幕（服务端标了 default 的简体）。
  check('zh-Hant 归一到 chi', normalizeSubtitleLanguage('zh-Hant'), 'chi');
  check('首选 zh-Hant 命中中文轨', pickDefaultSubtitleIndex(streams: streams, preferredLanguage: 'zh-Hant'), 0);
  check('首选英文', pickDefaultSubtitleIndex(streams: streams, preferredLanguage: 'eng'), 3);
  check('永久禁用', pickDefaultSubtitleIndex(streams: streams, preferredLanguage: 'chi', disabled: true), null);

  // 只有 forced 中文时，才退到 forced。
  final forcedOnly = [
    sub(index: 2, lang: 'chi', title: '中文（简体）[Forced]', forced: true),
    sub(index: 3, lang: 'eng', title: 'English'),
  ];
  check('只有 forced 中文', pickDefaultSubtitleIndex(streams: forcedOnly, preferredLanguage: 'chi'), 0);

  // 只有英文字幕：不自动挂（返回 null，面板里显示「禁用」）。
  final engOnly = [sub(index: 2, lang: 'eng', title: 'English')];
  check('只有英文不自动挂', pickDefaultSubtitleIndex(streams: engOnly, preferredLanguage: 'chi'), null);

  // 服务端标了 default 的英文轨：认这个信号。
  final engDefault = [sub(index: 2, lang: 'eng', title: 'English', isDefault: true)];
  check('服务端默认英文轨', pickDefaultSubtitleIndex(streams: engDefault, preferredLanguage: 'chi'), 0);

  // 听障版排在同语言的普通版后面。
  final hi = [
    sub(index: 2, lang: 'chi', title: '中文（简体）[HI]', hi: true),
    sub(index: 3, lang: 'chi', title: '中文（简体）'),
  ];
  check('跳过听障版', pickDefaultSubtitleIndex(streams: hi, preferredLanguage: 'chi'), 1);

  check('没有字幕轨', pickDefaultSubtitleIndex(streams: const [], preferredLanguage: 'chi'), null);

  // 图形字幕（PGS）也算一条可选字幕，只是 textLike 为 false。
  final pgs = sub(index: 7, lang: 'chi', title: '中文（简体）', codec: 'pgssub');
  check('PGS 文本判定', pgs.textLike, false);
  check('PGS 仍可被选中', pickDefaultSubtitleIndex(streams: [pgs], preferredLanguage: 'chi'), 0);

  // 解析真实 PlaybackInfo 片段：MediaStreams → 字幕轨。
  final json = jsonDecode('''
  {
    "Id": "mediasource_abc",
    "Container": "mkv",
    "MediaStreams": [
      {"Index": 0, "Type": "Video", "Codec": "hevc"},
      {"Index": 1, "Type": "Audio", "Codec": "aac", "Language": "jpn"},
      {"Index": 2, "Type": "Subtitle", "Codec": "ass", "Language": "chi",
       "DisplayTitle": "中文（简体）", "IsDefault": true, "IsTextSubtitleStream": true},
      {"Index": 3, "Type": "Subtitle", "Codec": "pgssub", "Language": "chi",
       "DisplayTitle": "中文（繁体）[Forced]", "IsForced": true, "IsTextSubtitleStream": false}
    ]
  }
  ''') as Map<String, dynamic>;
  final source = EmbyMediaSource.fromJson(json);
  check('媒体源 id', source.id, 'mediasource_abc');
  check('字幕轨数量', source.subtitleStreams.length, 2);
  check('字幕第一行标题', source.subtitleStreams.first.label, '中文（简体）');
  check('forced 解析', source.subtitleStreams[1].isForced, true);
  check('图形字幕 textLike', source.subtitleStreams[1].textLike, false);
  check('摘要', subtitleSummary(source.mediaStreams), '2 条字幕');

  // withStreamsFrom：PlaybackInfo 只给壳、条目详情给流时的合并。
  final shell = EmbyMediaSource.fromJson({'Id': 'mediasource_x', 'Container': 'mkv'});
  final merged = shell.withStreamsFrom(source);
  check('合并后仍有 id', merged.id, 'mediasource_x');
  check('合并后字幕数', merged.subtitleStreams.length, 2);

  stdout.writeln('\nPASS=$pass FAIL=$fail');
  exit(fail == 0 ? 0 : 1);
}
