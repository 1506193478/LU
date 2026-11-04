import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 本地视频的封面缩略图：首帧截一张 jpg，落临时目录按路径哈希缓存。
///
/// video_thumbnail 只有 Android / iOS 实现；桌面端（Windows）会抛
/// MissingPluginException，统一吞掉返回 null，调用方显示占位图标。
///
/// 封面墙一屏能挂十几张卡，如果每个都直接调原生解码，Android 上很容易
/// 同时开十几个 `MediaMetadataRetriever`，内存瞬间冲顶——表现出来就是
/// 「偶尔闪退」。所以这里做两件事：
///   * 同一个视频的并发请求合并成一个 Future；
///   * 全局最多两个解码任务同时跑，其余排队。
class LuVideoThumb {
  LuVideoThumb._();

  static final Map<String, String?> _mem = <String, String?>{};
  static final Map<String, Future<String?>> _inflight =
      <String, Future<String?>>{};

  static const int _maxConcurrent = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiting = <Completer<void>>[];

  /// 返回缓存的封面文件路径；不是本地文件 / 平台不支持 / 失败都返回 null。
  static Future<String?> pathFor(String source) {
    if (_mem.containsKey(source)) return Future<String?>.value(_mem[source]);
    final running = _inflight[source];
    if (running != null) return running;
    final future = _run(source);
    _inflight[source] = future;
    return future;
  }

  static Future<String?> _run(String source) async {
    try {
      await _acquire();
      final path = await _generate(source);
      _mem[source] = path;
      return path;
    } catch (_) {
      _mem[source] = null;
      return null;
    } finally {
      _inflight.remove(source);
      _release();
    }
  }

  static Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      // 名额直接转交给排队中的下一个，_active 不变。
      _waiting.removeAt(0).complete();
      return;
    }
    if (_active > 0) _active--;
  }

  static Future<String?> _generate(String source) async {
    try {
      final file = File(source);
      if (!file.existsSync()) return null;
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/vault_thumbs');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final key = sha1.convert(utf8.encode(source)).toString().substring(0, 20);
      final out = File('${cacheDir.path}/$key.jpg');
      if (out.existsSync() && out.lengthSync() > 0) return out.path;
      final raw = await VideoThumbnail.thumbnailFile(
        video: source,
        thumbnailPath: cacheDir.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 480,
        quality: 78,
      );
      if (raw == null || raw.isEmpty) return null;
      if (raw != out.path) {
        await File(raw).rename(out.path);
      }
      return out.path;
    } catch (_) {
      return null;
    }
  }
}
