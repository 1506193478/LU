/// HG 本地取流代理（从 HGhubX `src-tauri/src/media.rs` 移植）。
///
/// 站点封面是 AES-128-CBC 密文、m3u8 分片/key 带防盗链，所以所有媒体
/// 都走本地代理：
///
/// * `/img?u=<封面地址>` → 下载 + 按需 AES 解密 + 类型识别；
/// * `/hls?u=<m3u8地址>` → 下载播放列表，把分片/key 地址改写到 `/seg`；
/// * `/seg?u=<分片地址>` → 透传字节；内层还是 m3u8 时继续改写。
///
/// 播放器（mpv/AVPlayer）直接播 `http://127.0.0.1:<port>/hls?u=…`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'package:XL/modules/hg/hg_net.dart';

class HgProxy {
  HgProxy._();

  static HttpServer? _server;
  static int _port = 0;

  /// 本地基址：`http://127.0.0.1:<port>`，m3u8 改写用它。
  static String get origin => 'http://127.0.0.1:$_port';

  /// 封面解密 key/IV（media.rs 的 IMG_KEY / IMG_IV，站点固定的）。
  static const List<int> _imgKey = [
    0x66, 0x35, 0x64, 0x39, 0x36, 0x35, 0x64, 0x66, // "f5d965df"
    0x37, 0x35, 0x33, 0x33, 0x36, 0x32, 0x37, 0x30, // "75336270"
  ];
  static const List<int> _imgIv = [
    0x39, 0x37, 0x62, 0x36, 0x30, 0x33, 0x39, 0x34, // "97b60394"
    0x61, 0x62, 0x63, 0x32, 0x66, 0x62, 0x65, 0x31, // "abc2fbe1"
  ];

  static final Map<String, Uint8List> _imgCache = {};
  static final Map<String, String> _playlistCache = {};
  static final Map<String, Uint8List> _keyCache = {};
  static final Map<String, Uint8List> _segCache = {};

  static const int _imgCacheMax = 240;
  static const int _playlistCacheMax = 60;
  static const int _keyCacheMax = 120;
  static const int _segCacheMax = 36;

  /// 启动本地代理服务（幂等）。
  static Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _port = _server!.port;
    _server!.listen((request) {
      _handle(request);
    });
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  static void clearCaches() {
    _imgCache.clear();
    _playlistCache.clear();
    _keyCache.clear();
    _segCache.clear();
  }

  /* ── 对外地址构造 ── */


  static String coverUrl(String? url) =>
      (url == null || url.isEmpty) ? '' : '$origin/img?u=${enc(url)}';

  /// m3u8 → 播放列表改写；其它（mp4 等）→ /seg 原样透传。
  static String mediaUrl(String url) =>
      RegExp(r'\.m3u8(\?|$)', caseSensitive: false).hasMatch(url)
          ? '$origin/hls?u=${enc(url)}'
          : '$origin/seg?u=${enc(url)}';

  /* ── 请求处理 ── */

  static Future<void> _handle(HttpRequest request) async {
    try {
      final target = request.uri.queryParameters['u'] ?? '';
      if (target.isEmpty) {
        await _respond(request, 400, 'text/plain', _textBytes('missing u'),
            cache: 'no-store');
        return;
      }
      switch (request.uri.path) {
        case '/img':
          await _handleImg(request, target);
        case '/hls':
          await _handlePlaylist(request, target);
        case '/seg':
          await _handleSegment(request, target);
        default:
          await _respond(request, 404, 'text/plain', _textBytes('not found'),
              cache: 'no-store');
      }
    } catch (e) {
      try {
        await _respond(request, 502, 'text/plain', _textBytes(e.toString()),
            cache: 'no-store');
      } catch (_) {
        // 客户端已断开，忽略。
      }
    }
  }

  static Future<void> _handleImg(HttpRequest request, String url) async {
    final hit = _imgCache[url];
    if (hit != null) {
      await _respond(request, 200, imageKind(hit) ?? 'image/jpeg', hit,
          cache: 'public, max-age=86400');
      return;
    }
    final (_, bytes) = await HgNet.fetchBytes(url);
    final plain = imageKind(bytes) != null ? bytes : stripPadding(aesCbcDecrypt(bytes));
    if (plain.isEmpty) throw '封面解密失败';
    _cachePut(_imgCache, url, plain, _imgCacheMax);
    await _respond(request, 200, imageKind(plain) ?? 'image/jpeg', plain,
        cache: 'public, max-age=86400');
  }

  static Future<void> _handlePlaylist(HttpRequest request, String url) async {
    final cached = _playlistCache[url];
    if (cached != null) {
      await _respond(request, 200, 'application/vnd.apple.mpegurl',
          _textBytes(cached), cache: 'no-store');
      return;
    }
    final (_, bytes) = await HgNet.fetchBytes(url);
    final text = utf8.decode(bytes, allowMalformed: true)
        .replaceFirst('\u{FEFF}', '');
    if (!text.trimLeft().startsWith('#EXTM3U')) throw '响应不是 HLS 播放列表';
    final rewritten = rewritePlaylist(url, text);
    _cachePut(_playlistCache, url, rewritten, _playlistCacheMax);
    await _respond(request, 200, 'application/vnd.apple.mpegurl',
        _textBytes(rewritten), cache: 'no-store');
  }

  static Future<void> _handleSegment(HttpRequest request, String url) async {
    final keyHit = _keyCache[url];
    if (keyHit != null) {
      await _respond(request, 200, mimeOf(url, null), keyHit,
          cache: 'public, max-age=3600');
      return;
    }
    final segHit = _segCache[url];
    if (segHit != null) {
      await _respond(request, 200, mimeOf(url, null), segHit,
          cache: 'public, max-age=3600');
      return;
    }
    final (ctype, bytes) = await HgNet.fetchBytes(url);
    // 主清单的子清单也经 /seg 返回：必须继续改写，不能把内层 URL 原样交给播放器。
    final isPlaylist = (ctype ?? '').toLowerCase().contains('mpegurl') ||
        _looksLikeM3u8(bytes);
    if (isPlaylist) {
      final text = utf8.decode(bytes, allowMalformed: true)
          .replaceFirst('\u{FEFF}', '');
      final rewritten = rewritePlaylist(url, text);
      await _respond(request, 200, 'application/vnd.apple.mpegurl',
          _textBytes(rewritten), cache: 'public, max-age=3600');
      return;
    }
    final mime = mimeOf(url, ctype);
    if (bytes.length <= 65536) {
      _cachePut(_keyCache, url, bytes, _keyCacheMax);
    } else if (bytes.length <= 4 * 1024 * 1024) {
      _cachePut(_segCache, url, bytes, _segCacheMax);
    }
    await _respond(request, 200, mime, bytes, cache: 'public, max-age=3600');
  }

  /* ── HLS 改写 ── */

  /// m3u8 每行处理（rewrite_playlist 的移植）：
  /// 注释行里的 URI="…" 属性改写到 /seg；分片行绝对化后改写到 /seg。
  static String rewritePlaylist(String url, String text) {
    final out = StringBuffer();
    for (var raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.writeln();
        continue;
      }
      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-CONTENT-STEERING:')) continue;
        if (line.startsWith('#EXT-X-DATERANGE:')) {
          // 保留时间线/SCTE 元数据，丢弃可派生外部请求的属性。
          final attrs = hlsAttributes(line);
          final safe = attrs.$2.where((a) {
            final key =
                a.split('=').first.trim().toUpperCase();
            return !key.contains('URI') && key != 'X-ASSET-LIST';
          }).toList();
          out.writeln('${attrs.$1}:${safe.join(',')}');
          continue;
        }
        if (line.contains('URI="')) {
          final absolute = mapUriAttributes(line, (uri) => absolutize(url, uri));
          out.writeln(
              mapUriAttributes(absolute, (uri) => '$origin/seg?u=${enc(uri)}'));
        } else {
          out.writeln(line);
        }
      } else {
        out.writeln('$origin/seg?u=${enc(absolutize(url, line))}');
      }
    }
    return out.toString();
  }

  /// 返回 (tag, 属性列表)。属性里引号内的逗号不能当分隔符。
  static (String, List<String>) hlsAttributes(String line) {
    final i = line.indexOf(':');
    if (i < 0) return (line, const []);
    final rest = line.substring(i + 1);
    final attributes = <String>[];
    var quoted = false;
    var start = 0;
    for (var j = 0; j < rest.length; j++) {
      final ch = rest[j];
      if (ch == '"') quoted = !quoted;
      if (ch == ',' && !quoted) {
        attributes.add(rest.substring(start, j));
        start = j + 1;
      }
    }
    attributes.add(rest.substring(start));
    return (line.substring(0, i), attributes);
  }

  /// 对属性列表里每个 URI="…" 的值应用 rewrite，重建整行。
  static String mapUriAttributes(
    String line,
    String Function(String) rewrite,
  ) {
    final (tag, attributes) = hlsAttributes(line);
    final mapped = attributes.map((attribute) {
      final eq = attribute.indexOf('=');
      if (eq < 0) return attribute;
      final key = attribute.substring(0, eq).trim();
      final value = attribute.substring(eq + 1).trim();
      if (key == 'URI' && value.startsWith('"') && value.endsWith('"')) {
        final uri = value.substring(1, value.length - 1);
        return 'URI="${rewrite(uri)}"';
      }
      return attribute;
    }).toList();
    return '$tag:${mapped.join(',')}';
  }

  /// 相对地址 → 绝对地址（url::Url::join 的等价实现）。
  static String absolutize(String base, String target) {
    if (target.startsWith('http://') || target.startsWith('https://')) {
      return target;
    }
    try {
      return Uri.parse(base).resolve(target).toString();
    } catch (_) {
      return target;
    }
  }

  /* ── AES / 缓存 / 杂项 ── */

  /// AES-128-CBC 解密：固定 key/IV，用 ECB 引擎逐块解密后手动异或前块
  /// （与 media.rs 的 aes_cbc_decrypt 完全一致，避免 CBC 实例状态复用问题）。
  static Uint8List aesCbcDecrypt(Uint8List data) {
    if (data.isEmpty || data.length % 16 != 0) return Uint8List(0);
    final engine = pc.AESEngine()
      ..init(false, pc.KeyParameter(Uint8List.fromList(_imgKey)));
    final out = BytesBuilder();
    var prev = Uint8List.fromList(_imgIv);
    for (var i = 0; i < data.length; i += 16) {
      final block = Uint8List.sublistView(data, i, i + 16);
      final decrypted = Uint8List(16);
      engine.processBlock(block, 0, decrypted, 0);
      final plain = Uint8List(16);
      for (var j = 0; j < 16; j++) {
        plain[j] = decrypted[j] ^ prev[j];
      }
      out.add(plain);
      prev = Uint8List.fromList(block);
    }
    return out.takeBytes();
  }

  /// 去 PKCS7 填充（media.rs 的 strip_padding）。
  static Uint8List stripPadding(Uint8List buf) {
    if (buf.isEmpty) return buf;
    final pad = buf.last;
    if (pad > 0 && pad <= 16 && buf.length >= pad) {
      var valid = true;
      for (var i = buf.length - pad; i < buf.length; i++) {
        if (buf[i] != pad) valid = false;
      }
      if (valid) return Uint8List.sublistView(buf, 0, buf.length - pad);
    }
    return buf;
  }

  /// 字节内容是不是 m3u8（裸内容或带 BOM）。
  static bool _looksLikeM3u8(Uint8List bytes) {
    var head = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      head = Uint8List.sublistView(bytes, 3);
    }
    const magic = [0x23, 0x45, 0x58, 0x54, 0x4D, 0x33, 0x55]; // "#EXTM3U"
    if (head.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[i] != magic[i]) return false;
    }
    return true;
  }

  static String? imageKind(Uint8List buf) {
    if (buf.length < 12) return null;
    if (buf[0] == 0xFF && buf[1] == 0xD8) return 'image/jpeg';
    if (buf[0] == 0x89 && buf[1] == 0x50 && buf[2] == 0x4E && buf[3] == 0x47) {
      return 'image/png';
    }
    if (buf[0] == 0x47 && buf[1] == 0x49 && buf[2] == 0x46 && buf[3] == 0x38) {
      return 'image/gif';
    }
    if (buf[0] == 0x52 && buf[1] == 0x49 && buf[2] == 0x46 && buf[3] == 0x46) {
      if (buf[8] == 0x57 && buf[9] == 0x45 && buf[10] == 0x42 && buf[11] == 0x50) {
        return 'image/webp';
      }
    }
    return null;
  }

  static String mimeOf(String url, String? ctype) {
    if (ctype != null && ctype.isNotEmpty) return ctype;
    final p = url.split('?').first.toLowerCase();
    if (p.endsWith('.ts')) return 'video/mp2t';
    if (p.endsWith('.m4s') || p.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  /// 百分号编码：除 ASCII 字母数字外全部编码（NON_ALPHANUMERIC 等价）。
  /// 注意按 UTF-8 字节编码，中文等非 ASCII 才不会出错。
  static String enc(String s) {
    final bytes = Uint8List.fromList(utf8.encode(s));
    final out = StringBuffer();
    for (final c in bytes) {
      final isAlnum = (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A) ||
          (c >= 0x30 && c <= 0x39);
      if (isAlnum) {
        out.writeCharCode(c);
      } else {
        out
          ..write('%')
          ..write(c.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return out.toString();
  }

  static void _cachePut<V>(Map<String, V> map, String key, V val, int max) {
    if (map.length >= max && map.isNotEmpty) {
      map.remove(map.keys.first);
    }
    map[key] = val;
  }

  static Uint8List _textBytes(String s) => Uint8List.fromList(utf8.encode(s));

  static Future<void> _respond(
    HttpRequest request,
    int status,
    String contentType,
    Uint8List data, {
    required String cache,
  }) async {
    request.response
      ..statusCode = status
      ..headers.set('Content-Type', contentType)
      ..headers.set('Content-Length', data.length.toString())
      ..headers.set('Accept-Ranges', 'bytes')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..headers.set('Cache-Control', cache);
    await request.response.addStream(Stream.value(data));
    await request.response.close();
  }
}
