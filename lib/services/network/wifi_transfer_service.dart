import 'dart:async';
import 'dart:io';

import 'package:XL/services/logging/logger.dart';
import 'package:XL/utils/file_system.dart';

/// 局域网 Wi-Fi 传文件：在本机起一个轻量 HTTP 服务，浏览器打开地址即可上传。
///
/// 对标 SenPlayer 的 GCDWebUploader，但用 dart:io 实现，零新增依赖、
/// 全平台可用。文件落到「下载目录/WiFi传输」，不会碰番剧下载库。
class WifiTransferService {
  WifiTransferService._();

  static final WifiTransferService instance = WifiTransferService._();

  HttpServer? _server;
  String? _lanAddress;
  int _uploaded = 0;
  final Set<String> _activeNames = <String>{};

  bool get isRunning => _server != null;

  /// 供浏览器访问的地址（http://192.168.x.x:端口）。
  String? get address => _lanAddress;

  int get uploadedCount => _uploaded;
  Set<String> get activeNames => Set<String>.unmodifiable(_activeNames);

  Future<String> start() async {
    if (_server != null) return address ?? '';
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    _uploaded = 0;
    _activeNames.clear();
    server.listen(_handle);

    final ip = await _findLanIp();
    _lanAddress = 'http://$ip:${server.port}';
    KazumiLogger().i('WiFi transfer started at $_lanAddress');
    return _lanAddress!;
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _lanAddress = null;
    await server.close(force: true);
    KazumiLogger().i('WiFi transfer stopped');
  }

  Future<String> _findLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final nic in interfaces) {
        for (final addr in nic.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      KazumiLogger().w('WiFi transfer: list interfaces failed', error: e);
    }
    return '127.0.0.1';
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    // 浏览器上传页同源，不需要 CORS；这里只保证 MIME 与缓存策略。
    request.response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');

    if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
      request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
      request.response.write(_uploadPage());
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && path == '/upload') {
      await _handleUpload(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not found');
    await request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    try {
      final filename = _safeName(
        request.uri.queryParameters['name'] ??
            request.headers.value('x-file-name') ??
            'upload.bin',
      );
      final dir = Directory('${await getDefaultDownloadDirectory()}/WiFi传输');
      if (!await dir.exists()) await dir.create(recursive: true);

      // 同名不覆盖：加时间戳后缀，避免多次上传丢文件。
      var target = File('${dir.path}/$filename');
      if (await target.exists()) {
        final dot = filename.lastIndexOf('.');
        final stem = dot > 0 ? filename.substring(0, dot) : filename;
        final ext = dot > 0 ? filename.substring(dot) : '';
        target = File('${dir.path}/${stem}_${DateTime.now().millisecondsSinceEpoch}$ext');
      }

      _activeNames.add(filename);
      final sink = target.openWrite();
      await request.fold<Future<void>>(Future.value(), (prev, chunk) async {
        await prev;
        sink.add(chunk as List<int>);
      });
      await sink.close();

      _uploaded += 1;
      request.response.headers.set('Content-Type', 'application/json');
      request.response.write(
        '{"ok":true,"saved":"${_jsonEscape(target.uri.pathSegments.last)}"}',
      );
      KazumiLogger().i('WiFi transfer: saved ${target.path}');
    } catch (e) {
      KazumiLogger().e('WiFi transfer: upload failed', error: e);
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.set('Content-Type', 'application/json');
      request.response.write('{"ok":false}');
    } finally {
      _activeNames.clear();
      await request.response.close();
    }
  }

  /// 去掉路径分隔符与危险字符，避免浏览器伪造文件名写到别处。
  String _safeName(String raw) {
    var name = raw.split(RegExp(r'[\\/]')).last.trim();
    name = name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'upload.bin';
    return name;
  }

  String _jsonEscape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  String _uploadPage() => '''
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LU Wi-Fi 传文件</title>
<style>
body{font-family:-apple-system,system-ui,sans-serif;background:#f4f3f6;color:#1a1a1c;margin:0;padding:24px}
.box{max-width:560px;margin:0 auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 4px 20px rgba(0,0,0,.06)}
h1{font-size:20px;margin:0 0 6px}p{color:#6b6b70;font-size:14px;line-height:1.5}
input[type=file]{display:block;width:100%;margin:18px 0;padding:14px;border:2px dashed #c6c6c8;border-radius:12px}
button{width:100%;padding:14px;border:0;border-radius:12px;background:#007aff;color:#fff;font-size:16px;font-weight:600}
button:disabled{opacity:.5}ul{list-style:none;padding:0;font-size:13px;color:#6b6b70}
li{padding:6px 0;border-bottom:1px solid #eee;display:flex;justify-content:space-between}
</style></head><body><div class="box">
<h1>LU · Wi-Fi 传文件</h1>
<p>选择文件后点「上传」，文件会存到设备的「下载目录 / WiFi传输」。上传时请保持本页打开。</p>
<input id="f" type="file" multiple>
<button id="b" onclick="go()">上传</button>
<ul id="log"></ul>
<script>
async function go(){
  const fs=document.getElementById('f').files;
  if(!fs.length)return;
  const b=document.getElementById('b');b.disabled=true;
  const log=document.getElementById('log');
  for(const f of fs){
    const li=document.createElement('li');
    li.innerHTML='<span>'+f.name+'</span><span>上传中…</span>';
    log.appendChild(li);
    try{
      const r=await fetch('/upload?name='+encodeURIComponent(f.name),
        {method:'POST',headers:{'Content-Type':'application/octet-stream'},body:f});
      const j=await r.json();
      li.lastChild.textContent=j.ok?'✓ 已保存':'✗ 失败';
    }catch(e){li.lastChild.textContent='✗ '+e.message}
  }
  b.disabled=false;
}
</script></div></body></html>
''';
}
