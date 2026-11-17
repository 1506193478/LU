/// Emby 播放器的弹幕支持（dandanplay 自动匹配 + 本地 XML 导入）。
///
/// 主播放器的弹幕链路和 Bangumi/下载缓存耦合很深，这里做一个独立轻量版：
///   * 自动匹配：按剧名/片名搜 dandanplay，按集号取对应剧集弹幕；
///   * 本地导入：选 XML（BiliBili 格式）解析成弹幕；
///   * 渲染复用 canvas_danmaku（DanmakuScreen + DanmakuController），
///     显示设置（透明度/字号/位置/描边）直接读全局弹幕设置键，
///     和主播放器的「弹幕设置」页共用一套数据。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:XL/modules/danmaku/danmaku_module.dart';
import 'package:XL/request/apis/danmaku_api.dart';
import 'package:XL/services/storage/storage.dart';

class EmbyDanmakuController extends ChangeNotifier {
  DanmakuController? canvas;

  /// 会话开关（「禁用弹幕」）。「永久禁用」看 [foreverDisabled]。
  bool sessionOn = true;

  bool loading = false;
  String status = '';
  String matchedTitle = '';

  List<DanmakuEntry> entries = <DanmakuEntry>[];
  final Map<int, List<DanmakuEntry>> _bySecond = <int, List<DanmakuEntry>>{};
  int _lastSecond = -1;

  /// 选项版本号：显示设置变化时 +1，页面据此重建 DanmakuScreen。
  int optionRev = 0;

  bool get foreverDisabled =>
      GStorage.getSetting(SettingsKeys.embyDanmakuForeverDisabled);

  /// 综合开关（按钮高亮用）：会话开着且未永久禁用。
  bool get on => sessionOn && !foreverDisabled;

  bool get ready => entries.isNotEmpty;

  int get count => entries.length;

  // ------------------------------------------------------------ 选项

  DanmakuOption option() {
    return DanmakuOption(
      hideTop: !GStorage.getSetting(SettingsKeys.danmakuTop),
      hideScroll: !GStorage.getSetting(SettingsKeys.danmakuScroll),
      hideBottom: !GStorage.getSetting(SettingsKeys.danmakuBottom),
      opacity: GStorage.getSetting(SettingsKeys.danmakuOpacity).clamp(0.1, 1.0),
      fontSize: GStorage.getSetting(SettingsKeys.danmakuFontSize),
      strokeWidth:
          GStorage.getSetting(SettingsKeys.danmakuBorder)
              ? GStorage.getSetting(SettingsKeys.danmakuBorderSize)
              : 0.0,
      duration: 8.0,
      massiveMode: GStorage.getSetting(SettingsKeys.danmakuMassive),
    );
  }

  Future<void> toggleSettingAndBump() async {
    optionRev++;
    notifyListeners();
  }

  void setSessionOn(bool value) {
    sessionOn = value;
    if (!value) {
      _lastSecond = -1;
      canvas?.clear();
    }
    notifyListeners();
  }

  Future<void> setForeverDisabled(bool value) async {
    await GStorage.putSetting(SettingsKeys.embyDanmakuForeverDisabled, value);
    if (value) {
      sessionOn = false;
      canvas?.clear();
    }
    notifyListeners();
  }

  void bumpOption() {
    optionRev++;
    notifyListeners();
  }

  /// 切换一类弹幕的显示/隐藏（滚动 / 顶部 / 底部），写全局设置键。
  Future<void> togglePosition(String kind) async {
    switch (kind) {
      case 'scroll':
        await GStorage.putSetting(SettingsKeys.danmakuScroll,
            !GStorage.getSetting(SettingsKeys.danmakuScroll));
      case 'top':
        await GStorage.putSetting(SettingsKeys.danmakuTop,
            !GStorage.getSetting(SettingsKeys.danmakuTop));
      case 'bottom':
        await GStorage.putSetting(SettingsKeys.danmakuBottom,
            !GStorage.getSetting(SettingsKeys.danmakuBottom));
    }
    bumpOption();
  }

  // ------------------------------------------------------------ 数据

  /// dandanplay 自动匹配：[title] 剧名（剧集）或片名（电影），
  /// [episodeLabel] 形如 `S01E06`（可为空 = 直接按片名搜第一集）。
  Future<bool> autoMatch(String title, String episodeLabel) async {
    if (loading || ready || foreverDisabled) return false;
    final keyword = title.trim();
    if (keyword.isEmpty) return false;
    loading = true;
    status = '正在匹配弹幕…';
    notifyListeners();
    try {
      final epNum = RegExp(r'E(\d{1,3})', caseSensitive: false)
          .firstMatch(episodeLabel)
          ?.group(1);
      final ep = int.tryParse(epNum ?? '') ?? 1;
      final search = await DanmakuApi.searchAnimes(keyword);
      for (final anime in search.animes.take(3)) {
        final detail =
            await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(anime.animeId);
        if (!detail.success || detail.episodes.isEmpty) continue;
        final idx = ep - 1;
        if (idx >= detail.episodes.length) continue;
        final episodeId = detail.episodes[idx].episodeId;
        final list = await DanmakuApi.getDanDanmakuByEpisodeID(episodeId);
        if (list.isEmpty) continue;
        _apply(list, label: '${anime.animeTitle} · ${detail.episodes[idx].episodeTitle}');
        return true;
      }
      status = '没找到匹配的弹幕源';
      return false;
    } catch (e) {
      status = '弹幕匹配失败';
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 本地导入 XML（BiliBili 格式）。返回导入条数。
  Future<int> importLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml', 'json'],
      lockParentWindow: true,
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return 0;
    try {
      final raw = await File(path).readAsString();
      final list = <DanmakuEntry>[];
      if (raw.trimLeft().startsWith('<')) {
        // BiliBili XML：<d p="时间,模式,字号,颜色,时间戳,池,用户,弹幕ID">
        final re = RegExp(
          r'<d p="([^"]+)"[^>]*>([^<]+)</d>',
          multiLine: true,
        );
        for (final m in re.allMatches(raw)) {
          final parts = m.group(1)!.split(',');
          if (parts.length < 4) continue;
          final time = double.tryParse(parts[0]);
          final type = int.tryParse(parts[1]) ?? 1;
          final colorValue = int.tryParse(parts[2]) ?? 0xFFFFFF;
          final text = m.group(2)!;
          if (time == null || text.trim().isEmpty) continue;
          list.add(DanmakuEntry(
            time: time,
            message: text.trim(),
            type: type,
            color: Color((colorValue | 0xFF000000)),
            source: 'Local',
          ));
        }
      } else {
        // dandanplay JSON 数组（含 m/p 字段）。
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item['m'] != null && item['p'] != null) {
              list.add(DanmakuEntry.fromJson(
                Map<String, dynamic>.from(item),
              ));
            }
          }
        }
      }
      if (list.isEmpty) return 0;
      _apply(list, label: path.split('/').last.split('\\').last);
      return list.length;
    } catch (_) {
      return 0;
    }
  }

  void _apply(List<DanmakuEntry> list, {required String label}) {
    entries = list;
    matchedTitle = label;
    _bySecond.clear();
    for (final e in entries) {
      (_bySecond[e.time.toInt()] ??= <DanmakuEntry>[]).add(e);
    }
    _lastSecond = -1;
    status = '';
    notifyListeners();
  }

  void clear() {
    entries = [];
    matchedTitle = '';
    _bySecond.clear();
    _lastSecond = -1;
    notifyListeners();
  }

  // ------------------------------------------------------------ 投喂

  /// 每秒一跳：把当前这一秒（含漏拍补发）的弹幕送上画布。
  void tick(Duration position, {required bool playing}) {
    if (canvas == null ||
        entries.isEmpty ||
        foreverDisabled ||
        !sessionOn ||
        !playing) {
      return;
    }
    final second = position.inSeconds;
    if (second == _lastSecond) return;
    final int from;
    if (_lastSecond < 0 || second <= _lastSecond || second - _lastSecond > 3) {
      from = second; // 刚起播 / 拖了进度条：只发当前秒，别炸屏。
    } else {
      from = _lastSecond + 1;
    }
    _lastSecond = second;
    for (var s = from; s <= second; s++) {
      _emitAt(s);
    }
  }

  void _emitAt(int second) {
    final list = _bySecond[second];
    if (list == null || canvas == null) return;
    for (final entry in list) {
      try {
        canvas!.addDanmaku(DanmakuContentItem(
          entry.message,
          color: entry.color,
          type: _typeOf(entry.type),
        ));
      } catch (_) {}
    }
  }

  DanmakuItemType _typeOf(int type) {
    if (type == 4) return DanmakuItemType.bottom;
    if (type == 5) return DanmakuItemType.top;
    return DanmakuItemType.scroll;
  }
}

