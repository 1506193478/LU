import 'package:XL/services/storage/storage.dart';

/// Emby 的「怎么出流」偏好：直连、转码、以及转码时的画质上限。
///
/// 之前这件事只有 [SettingsKeys.embyDirectPlay] 一个布尔值，能表达的只有
/// 「尽量直连 / 优先转码」。真正遇到「宽带只有 10M，20G 的原盘一放就卡」或者
/// 「这台电视的 mpv 解不了 HEVC」时，用户没有可调的东西，只能干等它自己
/// 探测失败再回落。这里把三个维度拆开：方式、码率、字幕语言（字幕那部分
/// 见 `EmbyStreamPrefs.subtitleLanguage`）。
enum EmbyStreamMode {
  /// 先直连，探不通再让服务端转码（老行为，绝大多数情况最合适）。
  auto,

  /// 只走原盘直连，绝不转码。服务端不给直连就报错，不偷偷降级。
  direct,

  /// 只走服务端转码（HLS）。宽带不够、或者本地解不了源编码时用。
  transcode;

  String get label => switch (this) {
        EmbyStreamMode.auto => '自动',
        EmbyStreamMode.direct => '直连',
        EmbyStreamMode.transcode => '转码',
      };

  String get description => switch (this) {
        EmbyStreamMode.auto => '优先原盘直连，不行再让服务器转码',
        EmbyStreamMode.direct => '只放原盘，服务器不转码（最省服务器）',
        EmbyStreamMode.transcode => '全部交给服务器转码（最吃服务器 CPU）',
      };

  static EmbyStreamMode parse(String raw) => switch (raw) {
        'direct' => EmbyStreamMode.direct,
        'transcode' => EmbyStreamMode.transcode,
        _ => EmbyStreamMode.auto,
      };

  String get storageValue => switch (this) {
        EmbyStreamMode.auto => 'auto',
        EmbyStreamMode.direct => 'direct',
        EmbyStreamMode.transcode => 'transcode',
      };
}

/// 画质上限的可选档位（Mbps）。0 = 不限制，直接给原始码率。
const List<int> embyBitratePresets = <int>[0, 40, 20, 12, 8, 4, 2];

String embyBitrateLabel(int mbps) => mbps <= 0 ? '原始画质' : '$mbps Mbps';

class EmbyStreamPrefs {
  EmbyStreamPrefs._();

  static EmbyStreamMode get mode =>
      EmbyStreamMode.parse(GStorage.getSetting(SettingsKeys.embyStreamMode));

  static Future<void> setMode(EmbyStreamMode value) =>
      GStorage.putSetting(SettingsKeys.embyStreamMode, value.storageValue);

  /// 转码画质上限，Mbps；0 表示不限。
  static int get bitrateMbps => GStorage.getSetting(SettingsKeys.embyStreamBitrate);

  static Future<void> setBitrateMbps(int value) =>
      GStorage.putSetting(SettingsKeys.embyStreamBitrate, value);

  /// 首选字幕语言（Emby 用三字码：chi / eng / jpn …），空串表示不指定。
  static String get subtitleLanguage =>
      GStorage.getSetting(SettingsKeys.embySubtitleLanguage);

  static Future<void> setSubtitleLanguage(String value) =>
      GStorage.putSetting(SettingsKeys.embySubtitleLanguage, value);

  /// 「永久禁用字幕」记的是条目 id，逗号分隔。
  static Set<String> get subtitleDisabledIds {
    final raw = GStorage.getSetting(SettingsKeys.embySubtitleDisabledIds);
    if (raw.trim().isEmpty) return <String>{};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static bool isSubtitleDisabled(String itemId) =>
      subtitleDisabledIds.contains(itemId);

  static Future<void> setSubtitleDisabled(String itemId, bool disabled) async {
    if (itemId.isEmpty) return;
    final ids = subtitleDisabledIds;
    if (disabled) {
      ids.add(itemId);
    } else {
      ids.remove(itemId);
    }
    // 只留最近 200 条，避免这个字符串无限长。
    final kept = ids.length > 200 ? ids.toList().sublist(ids.length - 200) : ids.toList();
    await GStorage.putSetting(
      SettingsKeys.embySubtitleDisabledIds,
      kept.join(','),
    );
  }
}
