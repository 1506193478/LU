// 从 mp4 里抽帧。本机没有 ffmpeg，用无头 Edge + CDP 顶替：
// 起一个 <video>，逐点 seek，然后 Page.captureScreenshot 拿 PNG。
//
//   dart tool/video_frames.dart <video> <outDir> [stepSec]
//
// 只依赖 dart:io / dart:convert，不需要 package_config。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int _port = 9333;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: video_frames.dart <video> <outDir> [stepSec]');
    exit(2);
  }
  final video = File(args[0]).absolute;
  final outDir = Directory(args[1])..createSync(recursive: true);
  final double step = args.length > 2 ? double.parse(args[2]) : 2.0;

  final work = Directory('${outDir.path}/_page')..createSync(recursive: true);
  final page = File('${work.path}/page.html');
  page.writeAsStringSync('''
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:#000;overflow:hidden}
video{display:block;width:100vw;height:100vh;object-fit:contain}
</style></head><body>
<video id="v" src="${Uri.file(video.path)}" preload="auto" muted playsinline></video>
<script>
window.__ready=false;
const v=document.getElementById('v');
v.addEventListener('loadeddata',()=>{window.__ready=true;});
window.seekTo=function(t){return new Promise(res=>{
  const done=()=>{v.removeEventListener('seeked',done);
    requestAnimationFrame(()=>requestAnimationFrame(res));};
  v.addEventListener('seeked',done);
  if (Math.abs(v.currentTime-t)<0.02) { done(); return; }
  v.currentTime=t;
});};
window.videoInfo=()=>({w:v.videoWidth,h:v.videoHeight,d:v.duration,ready:window.__ready});
</script></body></html>''');

  final profile = Directory('${work.path}/profile');
  final edge = await Process.start(_findEdge(), [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--mute-audio',
    '--allow-file-access-from-files',
    '--autoplay-policy=no-user-gesture-required',
    '--remote-debugging-port=$_port',
    '--user-data-dir=${profile.path}',
    '--window-size=520,1100',
    '--no-first-run',
    '--no-default-browser-check',
    Uri.file(page.path).toString(),
  ], mode: ProcessStartMode.detachedWithStdio);
  edge.stdout.drain<void>();
  edge.stderr.drain<void>();

  WebSocket? ws;
  try {
    final target = await _waitForTarget();
    ws = await WebSocket.connect(target);
    final cdp = _Cdp(ws);

    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');

    // 等视频元数据。
    Map<String, dynamic> info = {};
    for (var i = 0; i < 60; i++) {
      final r = await cdp.eval('JSON.stringify(window.videoInfo())');
      final raw = r?['result']?['value'];
      if (raw is String) {
        info = jsonDecode(raw) as Map<String, dynamic>;
        if (info['ready'] == true && (info['d'] as num? ?? 0) > 0) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final double duration = (info['d'] as num? ?? 0).toDouble();
    final int vw = (info['w'] as num? ?? 1080).toInt();
    final int vh = (info['h'] as num? ?? 1920).toInt();
    stdout.writeln('video ${vw}x$vh  ${duration.toStringAsFixed(2)}s');

    await cdp.send('Emulation.setDeviceMetricsOverride', {
      'width': vw,
      'height': vh,
      'deviceScaleFactor': 1,
      'mobile': true,
    });

    var t = 0.0;
    var index = 0;
    while (t <= duration + 0.01) {
      await cdp.eval('window.seekTo($t).then(()=>1)');
      await Future<void>.delayed(const Duration(milliseconds: 260));
      final shot = await cdp.send('Page.captureScreenshot', {
        'format': 'png',
        'fromSurface': true,
      });
      final data = shot?['data'] as String?;
      if (data != null) {
        final name =
            'f${index.toString().padLeft(3, '0')}_${t.toStringAsFixed(1)}s.png';
        File('${outDir.path}/$name').writeAsBytesSync(base64Decode(data));
        stdout.writeln('  $name');
      }
      index++;
      t += step;
    }
  } finally {
    try {
      await ws?.close();
    } catch (_) {}
    edge.kill(ProcessSignal.sigkill);
  }
  exit(0);
}

String _findEdge() {
  const candidates = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError('找不到 msedge.exe');
}

Future<String> _waitForTarget() async {
  final client = HttpClient();
  try {
    for (var i = 0; i < 80; i++) {
      try {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$_port/json'));
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final list = jsonDecode(body);
        if (list is List) {
          for (final item in list) {
            if (item is Map && item['type'] == 'page') {
              final url = item['url']?.toString() ?? '';
              final wsUrl = item['webSocketDebuggerUrl']?.toString() ?? '';
              if (url.contains('page.html') && wsUrl.isNotEmpty) return wsUrl;
            }
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  } finally {
    client.close(force: true);
  }
  throw StateError('CDP target 一直没出现');
}

class _Cdp {
  _Cdp(this._ws) {
    _ws.listen((data) {
      final msg = jsonDecode(data as String);
      if (msg is! Map) return;
      final id = msg['id'];
      if (id is! int) return;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (msg['error'] != null) {
        completer.completeError(StateError('${msg['error']}'));
      } else {
        completer.complete((msg['result'] as Map?)?.cast<String, dynamic>());
      }
    });
  }

  final WebSocket _ws;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  int _next = 0;

  Future<Map<String, dynamic>?> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++_next;
    final completer = Completer<Map<String, dynamic>?>();
    _pending[id] = completer;
    _ws.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
  }

  Future<Map<String, dynamic>?> eval(String expression) => send(
        'Runtime.evaluate',
        {
          'expression': expression,
          'awaitPromise': true,
          'returnByValue': true,
        },
      );
}
