// 并发握手探针：App 里的封面是 20 个 CachedNetworkImage 同时起 TLS，
// 每个都是新连接。这里用「每次新建 HttpClient」复现同样的并发压力，
// 看服务端/中间链路会不会在握手阶段把连接掐掉。
//
//   dart --packages=.dart_tool/package_config.json tool/emby_handshake_probe.dart
import 'dart:io';

Future<String> one(String url, int index) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final sw = Stopwatch()..start();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final bytes = await res.fold<int>(0, (a, b) => a + b.length);
    client.close();
    return '#$index ${res.statusCode} ${sw.elapsedMilliseconds}ms ${bytes}B';
  } catch (e) {
    client.close(force: true);
    return '#$index FAIL ${sw.elapsedMilliseconds}ms $e';
  }
}

Future<void> main(List<String> args) async {
  final String base = args.isNotEmpty ? args.first : 'https://emby.bbqwq.com';
  // 走一个一定 400 的图片地址：我们只关心 TLS 握手能不能成。
  final String url =
      '$base/Items/ffffffffffffffffffffffffffffffff/Images/Primary?maxHeight=480';

  for (final batch in [1, 4, 12]) {
    stdout.writeln('--- 并发 $batch ---');
    final results = await Future.wait([
      for (var i = 0; i < batch; i++) one(url, i),
    ]);
    for (final r in results) {
      stdout.writeln('  $r');
    }
  }
  exit(0);
}
