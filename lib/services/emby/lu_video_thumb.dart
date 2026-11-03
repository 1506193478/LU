import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 本地视频的封面缩略图：首帧截一张 jpg，落临时目录按路径哈希缓存。
///
/// video_thumbnail 只有 Android / iOS 实现；桌面端（Windows）会抛
/// MissingPluginException，统一吞掉返回 null，调用方显示占位图标。
class LuVideoThumb {
  LuVideoThumb._();

  static final Map<String, String?> _mem = <String, String?>{};

  /// 返回缓存的封面文件路径；不是本地文件 / 平台不支持 / 失败都返回 null。
  static Future<String?> pathFor(String source) async {
    if (_mem.containsKey(source)) return _mem[source];
    final path = await _generate(source);
    _mem[source] = path;
    return path;
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
