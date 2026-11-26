import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// Emby「预览缩略图」（Trickplay）客户端实现。
///
/// 服务端在仪表盘里开了「预览缩略图」之后，每个条目会生成一套每 10 秒
/// 一帧的截图，打包成一个 Roku BIF 文件（`/Videos/{id}/index.bif`）。
/// BIF 的结构：
///   * 8 字节签名 + 版本 + 帧数 + 帧间隔（×0.1ms）+ 24 字节保留；
///   * TOC：每帧 8 字节（时间戳毫秒 + 数据偏移），最后一条是终止条目
///     （时间戳 0xFFFFFFFF、偏移 = 文件大小）；
///   * 之后就是一帧帧独立的 JPEG。
///
/// 解析后拖进度条时按位置二分到最近的帧，解出 [ui.Image] 给预览浮层。
/// 三级缓存：会话内 Future 合并 → 磁盘临时目录（按首帧 ImageTag 当版本）
/// → 服务端本身。解析失败会在会话内记 null，不再反复打服务器。
class EmbyTrickplay {
  EmbyTrickplay._(this._data, this._times, this._offsets, this.intervalMs);

  final Uint8List _data;
  final Int32List _times; // 每帧时间戳（毫秒），升序
  final Int32List _offsets; // 每帧 JPEG 在文件里的起始偏移
  final int intervalMs;

  static final Map<String, Future<EmbyTrickplay?>> _pending = {};
  static final Map<String, EmbyTrickplay?> _ready = {};

  /// 会话内只留最近 [maxReadyItems] 个条目的 BIF + 帧缓存。
  ///
  /// 以前这里无限增长：每看一部带缩略图的片子就常驻一份 Uint8List +
  /// 两张 Int32List + 16 张解码图（GPU 纹理）。连看几十集后内存/显存
  /// 阶梯上涨，App 和视频一起变卡。按插入顺序淘汰最旧的即可。
  static const int maxReadyItems = 12;

  /// 解出的帧缓存（LRU，最多 [maxFrameCache] 张）。
  final Map<int, ui.Image> _frames = {};
  final Map<int, Future<ui.Image?>> _decoding = {};
  static const int maxFrameCache = 16;
  bool _disposed = false;

  /// 加载条目的预览缩略图；服务端没生成 / 加载失败都返回 null。
  static Future<EmbyTrickplay?> forItem(
    EmbyServer server,
    String itemId,
  ) {
    if (itemId.isEmpty) return Future.value(null);
    final key = '${server.id}_$itemId';
    final hit = _ready[key];
    if (hit != null || _ready.containsKey(key)) {
      // 命中即提到末尾，让淘汰真正按「最近使用」而不是「最早加载」。
      // 同一条目会反复重进（切集、返回详情），不提升会把正在用的包淘汰掉。
      _ready.remove(key);
      _ready[key] = hit;
      return Future.value(hit);
    }
    return _pending.putIfAbsent(key, () => _load(server, itemId, key));
  }

  /// 淘汰最旧的条目，并释放它持有的所有 GPU 纹理。
  static void _trimReady() {
    while (_ready.length > maxReadyItems) {
      final oldest = _ready.keys.first;
      _ready.remove(oldest)?.dispose();
    }
  }

  static Future<EmbyTrickplay?> _load(
    EmbyServer server,
    String itemId,
    String key,
  ) async {
    try {
      final client = EmbyService.instance.clientFor(server);
      // 先要缩略图信息：空表示服务端根本没生成，bif 一定 404，省一次请求。
      final meta = await client.fetchThumbnailset(itemId);
      final thumbs = meta?['Thumbnails'];
      if (thumbs is! List || thumbs.isEmpty) return null;
      final first = thumbs.first;
      final tag = first is Map
          ? (first['ImageTag']?.toString() ?? '')
          : '';

      final cached = await _readDiskCache(itemId, tag);
      Uint8List? data = cached;
      if (data == null) {
        final fetched = await client.fetchThumbnailBif(itemId);
        if (fetched == null) return null;
        data = Uint8List.fromList(fetched);
        if (tag.isNotEmpty) {
          unawaited(_writeDiskCache(itemId, tag, data));
        }
      }

      final parsed = _parseBif(data);
      if (parsed == null) {
        KazumiLogger().w('Emby trickplay: bif parse failed for $itemId');
        return null;
      }
      final result = parsed;
      _ready[key] = result;
      _trimReady();
      return result;
    } catch (e) {
      KazumiLogger().w('Emby trickplay: load failed for $itemId', error: e);
      _ready[key] = null;
      _trimReady();
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  // ------------------------------------------------------------ BIF 解析

  static const List<int> _signature = <int>[
    0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A,
  ];

  static EmbyTrickplay? _parseBif(Uint8List data) {
    if (data.length < 52) return null;
    for (var i = 0; i < _signature.length; i++) {
      if (data[i] != _signature[i]) return null;
    }
    final count = _le32(data, 12);
    if (count == 0 || count > 30000) return null;
    // 帧间隔单位是 0.1ms：10 秒一帧 → 100000 → 10000ms。
    final intervalMs = _le32(data, 16) ~/ 10;
    final tocStart = 44;
    if (tocStart + (count + 1) * 8 > data.length) return null;

    final times = Int32List(count);
    final offsets = Int32List(count);
    var lastOffset = -1;
    var valid = 0;
    for (var i = 0; i < count; i++) {
      final base = tocStart + i * 8;
      final t = _le32(data, base);
      final off = _le32(data, base + 4);
      if (t == 0xFFFFFFFF) break; // 终止条目：后面没有了
      // 偏移必须单调、落在 TOC 之后：坏条目直接丢。
      if (off <= lastOffset || off >= data.length) continue;
      times[valid] = t;
      offsets[valid] = off;
      lastOffset = off;
      valid++;
    }
    if (valid == 0) return null;
    return EmbyTrickplay._(
      data,
      Int32List.sublistView(times, 0, valid),
      Int32List.sublistView(offsets, 0, valid),
      intervalMs > 0 ? intervalMs : 10000,
    );
  }

  static int _le32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  // ------------------------------------------------------------ 取帧

  /// 位置对应的帧下标（取「最后一个 <= 位置」的帧）。
  int indexOf(Duration position) {
    final ms = position.inMilliseconds;
    var lo = 0;
    var hi = _times.length - 1;
    if (ms <= _times.first) return 0;
    if (ms >= _times[hi]) return hi;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 解码位置上的帧。同一帧的并发请求会合并；解码完由调用方负责 setState。
  Future<ui.Image?> imageAt(Duration position) {
    final index = indexOf(position);
    final hit = _frames[index];
    if (hit != null) return Future.value(hit);
    return _decoding.putIfAbsent(index, () => _decode(index));
  }

  Future<ui.Image?> _decode(int index) async {
    try {
      final start = _offsets[index];
      final end = index + 1 < _offsets.length
          ? _offsets[index + 1]
          : _data.length;
      if (start < 0 || end <= start || end > _data.length) return null;
      final bytes = Uint8List.sublistView(_data, start, end);
      final image = await decodeImageFromList(bytes);
      // 条目刚被 LRU 淘汰：在途解码结果直接丢弃，别再写回造成泄漏。
      if (_disposed) {
        image.dispose();
        return null;
      }
      // LRU：满了先移除最旧的。ui.Image 持有 GPU 纹理，只从 Map 里移除
      // 不会释放显存——必须 dispose，否则每拖一次进度条就漏一张图。
      if (_frames.length >= maxFrameCache) {
        _frames.remove(_frames.keys.first)?.dispose();
      }
      _frames.remove(index)?.dispose();
      _frames[index] = image;
      return image;
    } catch (e) {
      KazumiLogger().w('Emby trickplay: decode frame $index failed', error: e);
      return null;
    } finally {
      _decoding.remove(index);
    }
  }

  /// 释放已解码的帧，但保留 BIF 数据与 index 表。
  ///
  /// 播放器页退出时调用：纹理立刻还回去，下次再进同一条目只重解码，
  /// 不用重新下载/解析 BIF。
  void releaseFrames() {
    for (final image in _frames.values) {
      image.dispose();
    }
    _frames.clear();
    // 让在途解码回包不再写回缓存。
    _decoding.clear();
  }

  /// 整份条目被 LRU 淘汰时调用：帧 + BIF 数据一并释放。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseFrames();
  }

  // ------------------------------------------------------------ 磁盘缓存

  /// 缓存名带首帧 ImageTag：刮削重建后 tag 会变，旧缓存自然失效。
  static Future<File?> _cacheFile(String itemId, String tag) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/emby_trickplay');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File('${dir.path}/${itemId}_$tag.bif');
    } catch (e) {
      KazumiLogger().w('Emby trickplay: cache dir failed', error: e);
      return null;
    }
  }

  static Future<Uint8List?> _readDiskCache(String itemId, String tag) async {
    if (tag.isEmpty) return null;
    try {
      final file = await _cacheFile(itemId, tag);
      if (file == null || !await file.exists()) return null;
      // 七天以上的旧包重新拉，避免「服务端重建过但 tag 恰好没变」的死角。
      final modified = await file.lastModified();
      if (DateTime.now().difference(modified) > const Duration(days: 7)) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDiskCache(
    String itemId,
    String tag,
    Uint8List data,
  ) async {
    if (tag.isEmpty) return;
    try {
      final file = await _cacheFile(itemId, tag);
      await file?.writeAsBytes(data, flush: true);
      // 只留最近 24 个包，防止缓存目录无限膨胀。
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/emby_trickplay');
      if (await dir.exists()) {
        final files = await dir.list().toList();
        if (files.length > 24) {
          final sorted = files
              .whereType<File>()
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final f in sorted.take(files.length - 24)) {
            try {
              f.deleteSync();
            } catch (_) {
              // 单个删不掉就留着，下次再清。
            }
          }
        }
      }
    } catch (_) {
      // 缓存写失败不影响功能。
    }
  }
}
