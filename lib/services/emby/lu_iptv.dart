import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:XL/services/storage/storage.dart';

/// IPTV 订阅（M3U / M3U8 / TXT）解析与存储。
///
/// 对应 SenPlayer 的 IPTV：在线订阅、频道分组、更新订阅源。频道列表缓存
/// 在设置里（一个 JSON 字符串），下次进来秒开，点「更新」才重新拉。
class LuIptvChannel {
  const LuIptvChannel({
    required this.name,
    required this.url,
    this.group = '默认',
    this.logo,
  });

  final String name;
  final String url;
  final String group;
  final String? logo;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'url': url,
    'group': group,
    if (logo != null && logo!.isNotEmpty) 'logo': logo,
  };

  static LuIptvChannel fromJson(Map<String, dynamic> m) => LuIptvChannel(
    name: m['name']?.toString() ?? '',
    url: m['url']?.toString() ?? '',
    group: m['group']?.toString() ?? '默认',
    logo: m['logo']?.toString(),
  );
}

class LuIptvSubscription {
  const LuIptvSubscription({
    required this.name,
    required this.url,
    this.channelCount = 0,
  });

  final String name;
  final String url;
  final int channelCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'url': url,
    'count': channelCount,
  };

  static LuIptvSubscription fromJson(Map<String, dynamic> m) =>
      LuIptvSubscription(
        name: m['name']?.toString() ?? m['url']?.toString() ?? '订阅',
        url: m['url']?.toString() ?? '',
        channelCount: (m['count'] as num?)?.toInt() ?? 0,
      );
}

class LuIptv {
  LuIptv._() {
    _load();
  }

  static final LuIptv instance = LuIptv._();

  static const SettingKey<String> _subsKey = SettingKey<String>(
    'lu.iptvSubs',
    '',
    group: SettingGroup.emby,
  );
  static const SettingKey<String> _cacheKey = SettingKey<String>(
    'lu.iptvChannels',
    '',
    group: SettingGroup.emby,
  );

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      headers: <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124 Mobile Safari/537.36',
      },
    ),
  );

  List<LuIptvSubscription> _subs = <LuIptvSubscription>[];
  List<LuIptvChannel> _channels = <LuIptvChannel>[];

  List<LuIptvSubscription> get subscriptions => List.unmodifiable(_subs);
  List<LuIptvChannel> get channels => List.unmodifiable(_channels);

  /// 按分组归拢的频道（保序）。
  Map<String, List<LuIptvChannel>> get grouped {
    final result = <String, List<LuIptvChannel>>{};
    for (final c in _channels) {
      (result.putIfAbsent(c.group, () => <LuIptvChannel>[])).add(c);
    }
    return result;
  }

  void _load() {
    _subs = _decodeSubs(GStorage.getSetting(_subsKey));
    _channels = _decodeChannels(GStorage.getSetting(_cacheKey));
  }

  static List<LuIptvSubscription> _decodeSubs(String raw) {
    if (raw.isEmpty) return <LuIptvSubscription>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map<String, dynamic>) LuIptvSubscription.fromJson(e),
        ];
      }
    } catch (_) {}
    return <LuIptvSubscription>[];
  }

  static List<LuIptvChannel> _decodeChannels(String raw) {
    if (raw.isEmpty) return <LuIptvChannel>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map<String, dynamic>) LuIptvChannel.fromJson(e),
        ];
      }
    } catch (_) {}
    return <LuIptvChannel>[];
  }

  void _saveSubs() {
    GStorage.putSetting(
      _subsKey,
      jsonEncode(_subs.map((LuIptvSubscription s) => s.toJson()).toList()),
    );
  }

  void _saveChannels() {
    GStorage.putSetting(
      _cacheKey,
      jsonEncode(_channels.map((LuIptvChannel c) => c.toJson()).toList()),
    );
  }

  /// 解析 M3U 文本。#EXTINF:-1,频道名 / #EXTGRP:分组 / #KODIPROP / 其余行是 URL。
  static List<LuIptvChannel> parseM3u(String text) {
    final channels = <LuIptvChannel>[];
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
    String name = '';
    String group = '默认';
    String? logo;
    for (final line in lines) {
      if (line.startsWith('#EXTINF:')) {
        final body = line.substring(8);
        final comma = body.indexOf(',');
        final attrs = comma >= 0 ? body.substring(0, comma) : body;
        name = comma >= 0 ? body.substring(comma + 1).trim() : '';
        final g = _attr(attrs, 'group-title');
        if (g != null && g.isNotEmpty) group = g;
        final l = _attr(attrs, 'tvg-logo');
        logo = (l == null || l.isEmpty) ? null : l;
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        final g = line.substring(8).trim();
        if (g.isNotEmpty) group = g;
        continue;
      }
      if (line.startsWith('#')) continue;
      final uri = line;
      if (!uri.startsWith('http') && !uri.startsWith('file')) continue;
      channels.add(
        LuIptvChannel(
          name: name.isEmpty ? uri.split('/').last : name,
          url: uri,
          group: group,
          logo: logo,
        ),
      );
      name = '';
      logo = null;
      group = '默认';
    }
    return channels;
  }

  static String? _attr(String attrs, String key) {
    final match = RegExp('$key="([^"]*)"').firstMatch(attrs);
    return match?.group(1);
  }

  /// 添加一个订阅并立即拉取频道。返回拉到的频道数；失败抛异常。
  Future<int> addSubscription({required String url, String? name}) async {
    final text = await _fetch(url);
    final parsed = parseM3u(text);
    final sub = LuIptvSubscription(
      name: (name != null && name.isNotEmpty)
          ? name
          : url.split('/').last,
      url: url,
      channelCount: parsed.length,
    );
    _subs.removeWhere((LuIptvSubscription s) => s.url == url);
    _subs.add(sub);
    _channels = parsed;
    _saveSubs();
    _saveChannels();
    return parsed.length;
  }

  /// 更新全部订阅的频道（合并，后订阅覆盖同名 URL 的频道）。
  Future<int> refreshAll() async {
    final all = <LuIptvChannel>[];
    for (final sub in _subs) {
      try {
        final parsed = parseM3u(await _fetch(sub.url));
        all.addAll(parsed);
      } catch (_) {
        // 单个订阅失败不影响其余，保留该订阅原来的频道。
      }
    }
    if (all.isNotEmpty) _channels = all;
    _saveChannels();
    return _channels.length;
  }

  void removeSubscription(String url) {
    _subs.removeWhere((LuIptvSubscription s) => s.url == url);
    _channels.clear();
    _saveSubs();
    _saveChannels();
  }

  Future<String> _fetch(String url) async {
    if (url.startsWith('file://')) {
      return await File(Uri.parse(url).toFilePath()).readAsString();
    }
    final res = await _dio.get<String>(url);
    return res.data ?? '';
  }
}
