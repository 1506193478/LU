// ignore_for_file: avoid_print
// 验证「一起看」的跟播信令能真的经服务器转发到房间内另一台客户端。
//
// 这台机器跑不了 flutter test（native asset 编译要 reg.exe，被安全策略拦），
// 所以用纯 dart:io 的探针代替：开两条真实连接连官方服务器，A 发播放请求，
// B 分片重组 + 解码，逐字段比对。
//
// 运行：source E:/dev/env.sh
//       dart --packages=.dart_tool/package_config.json tool/syncplay_relay_probe.dart

import 'dart:async';

import 'package:XL/services/player/syncplay_client.dart';
import 'package:XL/services/player/syncplay_play_request.dart';

const String _endPoint = 'syncplay.pl:8996';

Future<void> main() async {
  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final room = 'xlprobe$suffix';
  final host = _endPoint.split(':').first;
  final port = int.parse(_endPoint.split(':').last);

  // 故意用长标题 + 长地址，逼出多分片的情况（真实场景里就是这种长度）。
  final request = SyncPlayPlayRequest(
    bangumiId: 402301,
    name: '元氣少女緣結神',
    nameCn: '元气少女缘结神',
    coverUrl: 'https://lain.bgm.tv/pic/cover/l/8f/6a/402301_Q0XrS.jpg',
    pluginName: '7sefun',
    title: '元气少女缘结神',
    src: 'https://www.7sefun.com/index.php/vod/detail/id/12345.html',
  );

  final a = SyncplayClient(host: host, port: port);
  final b = SyncplayClient(host: host, port: port);

  final aEcho = <String>[];
  final bInbox = <String>[];
  a.onChatMessage.listen((m) => aEcho.add('${m['username']}:${m['message']}'));
  b.onChatMessage.listen((m) => bInbox.add('${m['username']}:${m['message']}'));

  final aHello = Completer<void>();
  final bHello = Completer<void>();
  a.onGeneralMessage.listen((_) {
    if (!aHello.isCompleted) aHello.complete();
  });
  b.onGeneralMessage.listen((_) {
    if (!bHello.isCompleted) bHello.complete();
  });

  final chunks = request.encodeChunks(messageId: 't001');
  print('分片数 = ${chunks.length}，单条最长 = '
      '${chunks.map((c) => c.length).reduce((x, y) => x > y ? x : y)} 字符');

  var failed = false;
  try {
    await a.connect(enableTLS: true);
    await b.connect(enableTLS: true);
    await a.joinRoom(room, 'ProbeA');
    await b.joinRoom(room, 'ProbeB');
    await aHello.future.timeout(const Duration(seconds: 15));
    await bHello.future.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 2));

    for (final chunk in chunks) {
      await a.sendChatMessage(chunk);
    }
    await Future<void>.delayed(const Duration(seconds: 3));

    print('');
    print('A 收到的回显条数 = ${aEcho.length}（发送者自己也会收到，应被忽略）');
    print('B 收到的消息条数 = ${bInbox.length}');

    final assembler = SyncPlayPlayRequestAssembler();
    SyncPlayPlayRequest? decoded;
    var truncated = 0;
    for (final line in bInbox) {
      final sep = line.indexOf(':');
      final sender = line.substring(0, sep);
      final text = line.substring(sep + 1);
      if (!SyncPlayPlayRequest.isPlayRequest(text)) continue;
      if (text.length >= SyncPlayPlayRequest.maxChatLength) truncated++;
      decoded ??= assembler.add(sender, text);
    }

    if (decoded == null) {
      print('FAIL: 分片没有重组成完整请求');
      failed = true;
    } else {
      final item = decoded.toBangumiItem();
      final fieldsOk = decoded.pluginName == request.pluginName &&
          decoded.title == request.title &&
          decoded.src == request.src &&
          decoded.bangumiId == request.bangumiId &&
          decoded.name == request.name &&
          decoded.nameCn == request.nameCn &&
          decoded.coverUrl == request.coverUrl;
      final itemOk = item.id == request.bangumiId &&
          item.nameCn == request.nameCn &&
          item.images['large'] == request.coverUrl;
      print('');
      print('  plugin    = ${decoded.pluginName}');
      print('  title     = ${decoded.title}');
      print('  src       = ${decoded.src}');
      print('  bangumiId = ${decoded.bangumiId}');
      print('  cover     = ${decoded.coverUrl}');
      print('  触到 150 上限的分片数 = $truncated');
      print('');
      print(fieldsOk && itemOk
          ? 'PASS: 分片重组后字段完全一致，还原的番剧信息也正确'
          : 'FAIL: 字段不一致');
      failed = !(fieldsOk && itemOk);
    }
  } catch (e) {
    print('ERROR: $e');
    failed = true;
  } finally {
    await a.disconnect();
    await b.disconnect();
  }
  if (failed) {
    throw StateError('probe failed');
  }
}
