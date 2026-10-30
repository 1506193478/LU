import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 表情包里的一张图。
///
/// 二选一：[asset] 是打进包里的本地图（内置表情包），[url] 是网络图。
class SyncPlaySticker {
  const SyncPlaySticker({required this.id, this.asset = '', this.url = ''});

  final String id;
  final String asset;
  final String url;

  bool get isAsset => asset.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (asset.isNotEmpty) 'asset': asset,
        if (url.isNotEmpty) 'url': url,
      };

  static SyncPlaySticker? fromJson(Map<dynamic, dynamic> json, {String base = ''}) {
    final String id = (json['id'] ?? '').toString();
    if (id.isEmpty) return null;
    final String asset = (json['asset'] ?? '').toString();
    final String url = _absolute((json['url'] ?? '').toString(), base);
    if (asset.isEmpty && url.isEmpty) return null;
    return SyncPlaySticker(id: id, asset: asset, url: url);
  }
}

/// 一套表情包。
class SyncPlayStickerPack {
  const SyncPlayStickerPack({
    required this.id,
    required this.name,
    this.stickers = const [],
    this.builtin = false,
  });

  final String id;
  final String name;
  final List<SyncPlaySticker> stickers;

  /// 内置包不可删除，也不需要写盘。
  final bool builtin;

  SyncPlaySticker? find(String stickerId) {
    for (final SyncPlaySticker sticker in stickers) {
      if (sticker.id == stickerId) return sticker;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'stickers': [for (final SyncPlaySticker sticker in stickers) sticker.toJson()],
      };

  /// 解析一份清单。
  ///
  /// 支持两种写法：
  /// 1. `{"name":"x","stickers":[{"id":"01","url":"https://.../01.png"}]}`
  /// 2. `{"name":"x","base":"https://cdn/pack/","ids":["01","02"],"ext":"png"}`
  static SyncPlayStickerPack? fromJson(
    Map<dynamic, dynamic> json, {
    String base = '',
    bool builtin = false,
  }) {
    final String name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final String manifestBase = _absolute((json['base'] ?? '').toString(), base);
    final List<SyncPlaySticker> stickers = [];

    final dynamic rawStickers = json['stickers'];
    if (rawStickers is List) {
      for (final dynamic entry in rawStickers) {
        if (entry is Map) {
          final SyncPlaySticker? sticker =
              SyncPlaySticker.fromJson(entry, base: manifestBase);
          if (sticker != null) stickers.add(sticker);
        } else if (entry is String && entry.isNotEmpty) {
          final String url = _absolute(entry, manifestBase);
          if (url.isNotEmpty) {
            stickers.add(SyncPlaySticker(id: entry, url: url));
          }
        }
      }
    } else {
      final dynamic ids = json['ids'];
      final String ext = (json['ext'] ?? 'png').toString();
      if (ids is List && manifestBase.isNotEmpty) {
        for (final dynamic id in ids) {
          final String value = id.toString();
          if (value.isEmpty) continue;
          stickers.add(
            SyncPlaySticker(
              id: value,
              url: '${manifestBase.endsWith('/') ? manifestBase : '$manifestBase/'}$value.$ext',
            ),
          );
        }
      }
    }

    if (stickers.isEmpty) return null;
    final String id = (json['id'] ?? '').toString().trim().isNotEmpty
        ? (json['id'] ?? '').toString().trim()
        : _slug(name);
    return SyncPlayStickerPack(
      id: id,
      name: name,
      stickers: stickers,
      builtin: builtin,
    );
  }

  static String _slug(String name) {
    final int hash =
        name.codeUnits.fold<int>(7, (acc, unit) => (acc * 31 + unit) & 0x7fffffff);
    return 'p${hash.toRadixString(36)}';
  }
}

/// 内置表情包「LU 小粘土」。
///
/// 12 张手绘 SVG，跟着粘土设计语言走；不联网、不占体积，双方同版本即可互通。
const SyncPlayStickerPack syncPlayBuiltinStickerPack = SyncPlayStickerPack(
  id: 'lu_clay',
  name: 'LU 小粘土',
  builtin: true,
  stickers: [
    SyncPlaySticker(id: 'happy', asset: 'assets/stickers/lu/happy.svg'),
    SyncPlaySticker(id: 'laugh', asset: 'assets/stickers/lu/laugh.svg'),
    SyncPlaySticker(id: 'cry', asset: 'assets/stickers/lu/cry.svg'),
    SyncPlaySticker(id: 'angry', asset: 'assets/stickers/lu/angry.svg'),
    SyncPlaySticker(id: 'speechless', asset: 'assets/stickers/lu/speechless.svg'),
    SyncPlaySticker(id: 'question', asset: 'assets/stickers/lu/question.svg'),
    SyncPlaySticker(id: 'love', asset: 'assets/stickers/lu/love.svg'),
    SyncPlaySticker(id: 'sleep', asset: 'assets/stickers/lu/sleep.svg'),
    SyncPlaySticker(id: 'cheer', asset: 'assets/stickers/lu/cheer.svg'),
    SyncPlaySticker(id: 'shock', asset: 'assets/stickers/lu/shock.svg'),
    SyncPlaySticker(id: 'popcorn', asset: 'assets/stickers/lu/popcorn.svg'),
    SyncPlaySticker(id: 'bye', asset: 'assets/stickers/lu/bye.svg'),
  ],
);

/// 已安装表情包的本地仓库。
///
/// 存在应用支持目录下的一个 JSON 文件里，不塞进设置项——设置是用户可见的
/// 开关，表情包是数据，混在一起会让设置同步多出一堆无意义的键。
class SyncPlayStickerStore extends ChangeNotifier {
  SyncPlayStickerStore._();

  static final SyncPlayStickerStore instance = SyncPlayStickerStore._();

  static const String _fileName = 'syncplay_stickers.json';

  List<SyncPlayStickerPack> _installed = const [];
  bool _loaded = false;

  /// 内置包永远排在最前面。
  List<SyncPlayStickerPack> get packs =>
      [syncPlayBuiltinStickerPack, ..._installed];

  List<SyncPlayStickerPack> get installed => _installed;

  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final File file = await _storageFile();
      if (!file.existsSync()) return;
      final dynamic json = jsonDecode(await file.readAsString());
      if (json is! List) return;
      _installed = [
        for (final dynamic entry in json)
          if (entry is Map)
            SyncPlayStickerPack.fromJson(entry, builtin: false),
      ].whereType<SyncPlayStickerPack>().toList();
      notifyListeners();
    } catch (e) {
      debugPrint('SyncPlay stickers: load failed $e');
    }
  }

  /// 从地址或粘贴的 JSON 导入一套表情包。
  ///
  /// 返回导入的包；解析不出表情时抛 [FormatException]。
  Future<SyncPlayStickerPack> importFrom(String input) async {
    final String raw = input.trim();
    if (raw.isEmpty) {
      throw const FormatException('内容为空');
    }
    String body = raw;
    String base = '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final http.Response response =
          await http.get(Uri.parse(raw)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw FormatException('请求失败：HTTP ${response.statusCode}');
      }
      body = utf8.decode(response.bodyBytes);
      final int slash = raw.lastIndexOf('/');
      base = slash > 8 ? raw.substring(0, slash + 1) : raw;
    }
    final dynamic json = jsonDecode(body);
    if (json is! Map) {
      throw const FormatException('清单不是 JSON 对象');
    }
    final SyncPlayStickerPack? pack =
        SyncPlayStickerPack.fromJson(json, base: base);
    if (pack == null) {
      throw const FormatException('清单里没有可用的表情');
    }
    await _upsert(pack);
    return pack;
  }

  Future<void> _upsert(SyncPlayStickerPack pack) async {
    _installed = [
      pack,
      for (final SyncPlayStickerPack existing in _installed)
        if (existing.id != pack.id) existing,
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String packId) async {
    if (packId == syncPlayBuiltinStickerPack.id) return;
    _installed = [
      for (final SyncPlayStickerPack pack in _installed)
        if (pack.id != packId) pack,
    ];
    notifyListeners();
    await _persist();
  }

  /// 按包 id + 表情 id 找回贴图；找不到返回 null（对方装了我没装的包）。
  SyncPlaySticker? resolve(String packId, String stickerId) {
    for (final SyncPlayStickerPack pack in packs) {
      if (pack.id != packId) continue;
      return pack.find(stickerId);
    }
    return null;
  }

  /// 把一条收到的表情包消息还原成可渲染的贴图。
  ///
  /// 优先用本地包（同版本、或自己装过同一个包），本地没有才退回消息里带的地址。
  SyncPlaySticker? resolveMessage(String packId, String stickerId, String url) {
    final SyncPlaySticker? local = resolve(packId, stickerId);
    if (local != null) return local;
    if (url.isEmpty) return null;
    return SyncPlaySticker(id: stickerId, url: url);
  }

  SyncPlayStickerPack? packOf(String packId) {
    for (final SyncPlayStickerPack pack in packs) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  Future<void> _persist() async {
    try {
      final File file = await _storageFile();
      await file.writeAsString(
        jsonEncode([for (final SyncPlayStickerPack pack in _installed) pack.toJson()]),
      );
    } catch (e) {
      debugPrint('SyncPlay stickers: save failed $e');
    }
  }

  Future<File> _storageFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}

String _absolute(String url, String base) {
  final String value = url.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('//')) return 'https:$value';
  if (base.isEmpty) return value;
  if (value.startsWith('/')) {
    final Uri? uri = Uri.tryParse(base);
    if (uri == null) return value;
    return '${uri.scheme}://${uri.host}$value';
  }
  return '${base.endsWith('/') ? base : '$base/'}$value';
}
