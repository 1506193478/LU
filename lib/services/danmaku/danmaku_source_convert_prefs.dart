import 'dart:convert';

import 'package:XL/modules/danmaku/danmaku_module.dart';
import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/subtitle/han_convert.dart';

/// 弹幕来源（对应 DanmakuEntry.source 的分类）。
/// 弹弹play 的 p 串第 4 段可能是 BiliBili / Gamer / 其它任意值，
/// 本地导入固定是 Local。这里归成四桶，未识别的都进「其它」。
enum DanmakuSrc {
  bilibili('BiliBili', '哔哩哔哩'),
  gamer('Gamer', '游戏弹幕'),
  dandan('DanDan', '弹弹play'),
  other('Other', '其它来源');

  const DanmakuSrc(this.id, this.label);

  final String id;
  final String label;

  static DanmakuSrc fromSource(String source) {
    final s = source.toLowerCase();
    if (s.contains('bilibili') || s.contains('bili')) return bilibili;
    if (s.contains('gamer')) return gamer;
    if (s.contains('dandan') || s.contains('弹弹')) return dandan;
    return other;
  }
}

/// 弹幕「按来源简繁转换」偏好。
///
/// 每个来源独立配置 s2t / t2s / off，默认全部 off（不改现有行为）。
/// 存储成一个 JSON 字符串：{ bilibili: 's2t', gamer: '', ... }。
class DanmakuSourceConvertPrefs {
  DanmakuSourceConvertPrefs._() {
    _reload();
  }

  static final DanmakuSourceConvertPrefs instance =
      DanmakuSourceConvertPrefs._();

  static const SettingKey<String> _storeKey = SettingKey<String>(
    'lu.danmakuSourceConvert',
    '',
    group: SettingGroup.danmaku,
  );

  final Map<String, String> _modes = <String, String>{};

  void _reload() {
    _modes.clear();
    for (final s in DanmakuSrc.values) {
      _modes[s.id] = HanConvertMode.off.storageValue;
    }
    final raw = GStorage.getSetting(_storeKey);
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.forEach((key, value) {
          if (_modes.containsKey(key) && value is String) {
            _modes[key] = HanConvertMode.parse(value).storageValue;
          }
        });
      }
    } catch (_) {}
  }

  HanConvertMode modeOf(DanmakuSrc src) =>
      HanConvertMode.parse(_modes[src.id]);

  /// 按来源字符串取转换方向。
  HanConvertMode modeForSource(String source) => modeOf(DanmakuSrc.fromSource(source));

  Future<void> setMode(DanmakuSrc src, HanConvertMode mode) async {
    _modes[src.id] = mode.storageValue;
    if (mode != HanConvertMode.off) await HanConvert.ensureMode(mode);
    await GStorage.putSetting(_storeKey, jsonEncode(_modes));
  }

  /// 预热所有已启用的方向，进播放器时调一次。
  Future<void> warmUpEnabled() async {
    for (final s in DanmakuSrc.values) {
      final mode = modeOf(s);
      if (mode != HanConvertMode.off) await HanConvert.ensureMode(mode);
    }
  }

  /// 对一批弹幕按各自来源做转换，原地改写 message。
  /// 两个汇聚点（主播放器 addDanmakus / Emby _apply）共用，
  /// 这样无论弹幕来自 B站、弹弹play、本地还是缓存，都走同一套规则。
  List<DanmakuEntry> convertAll(List<DanmakuEntry> entries) {
    for (final e in entries) {
      final mode = modeForSource(e.source);
      final converted = HanConvert.applyWithMode(e.message, mode);
      if (converted != e.message) e.message = converted;
    }
    return entries;
  }
}
