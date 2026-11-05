import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/storage/storage.dart';

/// 字幕的简繁转换方向。
///
/// 之所以要在播放器里做这件事：Emby 上的中文字幕一半来自字幕站，繁简混杂，
/// 用户看剧时经常遇到「这条是繁体但我不习惯」。以前只能靠服务端插件或者
/// 自己下一条新的，成本太高。这里在渲染前做一次字符级 + 词组级的映射，
/// 对两条播放内核（mpv / AVPlayer）都生效。
enum HanConvertMode {
  off('off', '不转换'),
  s2t('s2t', '简体 → 繁体'),
  t2s('t2s', '繁体 → 简体');

  const HanConvertMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static HanConvertMode parse(String? raw) => switch (raw) {
    's2t' => HanConvertMode.s2t,
    't2s' => HanConvertMode.t2s,
    _ => HanConvertMode.off,
  };
}

/// OpenCC 简繁映射的轻量运行时。
///
/// 词表来自 OpenCC（Apache-2.0），在构建时压成四份 JSON 放进
/// `assets/opencc/`：字符表负责兜底，词组表负责纠正「一词多形」——
/// 只有字符表的话「头发」会被翻成「頭發」，所以词组必须优先级更高。
///
/// 词表只在真的打开转换时懒加载，不转换的用户不付这份内存。
class HanConvert {
  HanConvert._();

  /// 词组最长按 12 个字匹配。OpenCC 原表最长 15 字，全是成语/专名，
  /// 字幕里几乎不会出现；截到 12 已经把常见词都盖住了，同时把每次
  /// 匹配的窗口数压到个位数。
  static const int _maxPhraseLength = 12;

  static HanConvertMode _mode = HanConvertMode.off;

  /// 已经加载好的方向表（off 不需要）。
  static final Map<HanConvertMode, _HanTable> _tables = {};

  /// 正在加载的方向，避免同一方向并发解析两遍。
  static final Set<HanConvertMode> _loading = {};

  /// 加载失败过的方向。没有这个集合的话，`apply` 每帧都会重新发起一次
  /// 资源加载（字幕每帧都会读一次文本），日志会被刷爆、还白白吃 CPU。
  static final Set<HanConvertMode> _failed = {};

  /// 上一次的转换结果。字幕每帧都会被读一次，而文本大概率没变，
  /// 加一层单条缓存把重复转换挡掉。
  static String _memoSource = '';
  static HanConvertMode _memoMode = HanConvertMode.off;
  static String _memoResult = '';

  static HanConvertMode get mode => _mode;

  /// 启动 / 进入播放器时调一次：把设置读进内存并按需预热词表。
  static void init() {
    _mode = HanConvertMode.parse(
      GStorage.getSetting(SettingsKeys.subtitleHanConvert),
    );
    _warmUp();
  }

  static Future<void> setMode(HanConvertMode value) async {
    _mode = value;
    _memoSource = '';
    if (value != HanConvertMode.off) {
      // 用户主动切到这个方向 = 允许重试一次（上次可能是资源还没就绪）。
      _failed.remove(value);
      await _ensureTable(value);
    }
    await GStorage.putSetting(
      SettingsKeys.subtitleHanConvert,
      value.storageValue,
    );
  }

  /// 对一段字幕文本做转换。词表还没就绪时原样返回——宁可这一帧不转，
  /// 也不能让播放卡在 await 上。
  static String apply(String text) {
    if (_mode == HanConvertMode.off || text.isEmpty) return text;
    if (text == _memoSource && _mode == _memoMode) return _memoResult;
    final table = _tables[_mode];
    if (table == null) {
      _warmUp();
      return text;
    }
    final converted = table.convert(text);
    _memoSource = text;
    _memoMode = _mode;
    _memoResult = converted;
    return converted;
  }

  static void _warmUp() {
    if (_mode == HanConvertMode.off) return;
    unawaited(_ensureTable(_mode));
  }

  static Future<void> _ensureTable(HanConvertMode mode) async {
    if (mode == HanConvertMode.off) return;
    if (_tables.containsKey(mode) ||
        _loading.contains(mode) ||
        _failed.contains(mode)) {
      return;
    }
    _loading.add(mode);
    try {
      final chars = await _loadMap(
        'assets/opencc/${mode.storageValue}_characters.json',
      );
      final phrases = await _loadMap(
        'assets/opencc/${mode.storageValue}_phrases.json',
      );
      _tables[mode] = _HanTable(
        chars: chars,
        phrases: phrases,
        maxPhraseLength: _maxPhraseLength,
      );
      KazumiLogger().i(
        'HanConvert: ${mode.storageValue} ready '
        '(${chars.length} chars / ${phrases.length} phrases)',
      );
    } catch (e) {
      _failed.add(mode);
      KazumiLogger().w('HanConvert: load ${mode.storageValue} failed', error: e);
    } finally {
      _loading.remove(mode);
    }
  }

  static Future<Map<String, String>> _loadMap(String asset) async {
    final raw = await rootBundle.loadString(asset);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }
}

/// 一份「字符表 + 词组表」的转换器。
class _HanTable {
  _HanTable({
    required this.chars,
    required this.phrases,
    required int maxPhraseLength,
  }) : _lengths = _phraseLengths(phrases, maxPhraseLength),
       _maxLength = _longest(phrases, maxPhraseLength);

  final Map<String, String> chars;
  final Map<String, String> phrases;

  /// 实际出现过的词组长度（降序），匹配时只试这几个长度，
  /// 比「从最长逐个往下试」少掉大量必然落空的 substring。
  final List<int> _lengths;
  final int _maxLength;

  static List<int> _phraseLengths(Map<String, String> phrases, int cap) {
    final lengths = <int>{};
    for (final key in phrases.keys) {
      if (key.length <= cap) lengths.add(key.length);
    }
    final sorted = lengths.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  static int _longest(Map<String, String> phrases, int cap) {
    var max = 1;
    for (final key in phrases.keys) {
      if (key.length > max && key.length <= cap) max = key.length;
    }
    return max;
  }

  String convert(String input) {
    if (_maxLength <= 1) return _convertChars(input);
    final out = StringBuffer();
    final total = input.length;
    var i = 0;
    while (i < total) {
      var matched = false;
      for (final length in _lengths) {
        if (i + length > total) continue;
        final phrase = input.substring(i, i + length);
        final hit = phrases[phrase];
        if (hit != null) {
          out.write(hit);
          i += length;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      final unit = input.codeUnitAt(i);
      // 代理对（扩展 B 区的生僻字）必须整对搬走，否则会切出半个字符。
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < total) {
        final next = input.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.write(input.substring(i, i + 2));
          i += 2;
          continue;
        }
      }
      final ch = input[i];
      out.write(chars[ch] ?? ch);
      i += 1;
    }
    return out.toString();
  }

  String _convertChars(String input) {
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      out.write(chars[ch] ?? ch);
    }
    return out.toString();
  }
}
