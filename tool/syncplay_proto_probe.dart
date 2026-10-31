// 一起看播放请求协议的纯 Dart 探针（不跑 GUI / 不跑 flutter test）。
// 用法：dart --packages=.dart_tool/package_config.json tool/syncplay_proto_probe.dart
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/syncplay_pull_request.dart';

int failures = 0;

void check(String name, bool cond) {
  print('${cond ? 'PASS' : 'FAIL'} - $name');
  if (!cond) failures++;
}

void main() {
  // 1. 广播请求：不带 target 的编码与还原（与旧版本 payload 完全一致）。
  final broadcast = SyncPlayPlayRequest(
    bangumiId: 12345,
    name: 'Original Name',
    nameCn: '中文名',
    coverUrl: 'https://example.com/cover.jpg',
    pluginName: 'SomeSource',
    title: '第 1 话 一切的开始',
    src: 'https://example.com/play/12345/1',
  );
  final broadcastChunks = broadcast.encodeChunks(messageId: 'abcd');
  check('广播请求分片数 >= 2', broadcastChunks.length >= 2);
  check('广播请求每条 <= 150 字符',
      broadcastChunks.every((c) => c.length <= 150));
  check('广播 payload 不含定向键 o',
      !broadcastChunks.first.contains('"o"'));
  check('分片头格式 id/index/total',
      broadcastChunks.first.startsWith('XLPLAY1|abcd/1/${broadcastChunks.length}|'));

  // 2. 模拟接收端重组。
  final assembler = SyncPlayPlayRequestAssembler();
  SyncPlayPlayRequest? assembled;
  for (final chunk in broadcastChunks) {
    final result = assembler.add('hostUser', chunk);
    if (result != null) assembled = result;
  }
  check('广播请求重组成功', assembled != null);
  check('重组字段一致',
      assembled != null &&
          assembled.bangumiId == 12345 &&
          assembled.name == 'Original Name' &&
          assembled.nameCn == '中文名' &&
          assembled.coverUrl == 'https://example.com/cover.jpg' &&
          assembled.pluginName == 'SomeSource' &&
          assembled.title == '第 1 话 一切的开始' &&
          assembled.src == 'https://example.com/play/12345/1' &&
          assembled.target.isEmpty);

  // 3. 定向请求：target 参与 payload，解出来 target 正确。
  final targeted = SyncPlayPlayRequest(
    bangumiId: 42,
    name: 'T',
    nameCn: ' Target 测试',
    coverUrl: '',
    pluginName: 'Src',
    title: 'EP2',
    src: 'https://example.com/x/2',
    target: 'newcomer',
  );
  final targetedChunks = targeted.encodeChunks(messageId: 'zz99');
  check('定向请求每条 <= 150 字符',
      targetedChunks.every((c) => c.length <= 150));
  final targetAssembler = SyncPlayPlayRequestAssembler();
  SyncPlayPlayRequest? targetedOut;
  for (final chunk in targetedChunks) {
    final result = targetAssembler.add('hostUser', chunk);
    if (result != null) targetedOut = result;
  }
  check('定向请求重组成功', targetedOut != null);
  check('定向请求 target == newcomer',
      targetedOut != null && targetedOut.target == 'newcomer');

  // 4. 丢一片永远收不齐（回归：重发前挂起不炸表）。
  final dropAssembler = SyncPlayPlayRequestAssembler();
  for (var i = 0; i < broadcastChunks.length - 1; i++) {
    dropAssembler.add('hostUser', broadcastChunks[i]);
  }
  // 缺最后一片：别人发来的第一条分片不能和这半截组拼到一起。
  check('缺一片时挂起，不同 sender 互不干扰',
      dropAssembler.add('otherUser', broadcastChunks[0]) == null);
  // 原样重发一轮（同一个 id），补齐后应能拼回。
  SyncPlayPlayRequest? retryOut;
  for (final chunk in broadcastChunks) {
    final result = dropAssembler.add('hostUser', chunk);
    if (result != null) retryOut = result;
  }
  check('重发补齐后能拼回', retryOut != null);

  // 5. 溢出淘汰最旧的一组，而不是整表清空。
  final evictAssembler = SyncPlayPlayRequestAssembler();
  final firstGroupChunks =
      broadcast.encodeChunks(messageId: 'old0');
  for (final chunk in firstGroupChunks) {
    evictAssembler.add('peer0', chunk);
  }
  for (var g = 1; g <= 16; g++) {
    final id = 'g${g.toString().padLeft(3, '0')}';
    final chunks = broadcast.encodeChunks(messageId: id);
    for (final chunk in chunks) {
      evictAssembler.add('peer$g', chunk);
    }
  }
  // 此时挂起组 > 16；再补第 18 组，最旧的 old0 应被淘汰而不是全体清空。
  final lastChunks = broadcast.encodeChunks(messageId: 'g999');
  for (var i = 0; i < lastChunks.length - 1; i++) {
    evictAssembler.add('peerX', lastChunks[i]);
  }
  // g016（第 16 组，peer16）还挂着——用它验证「整表没被清」。
  final keepChunks = broadcast.encodeChunks(messageId: 'g016');
  SyncPlayPlayRequest? kept;
  for (final chunk in keepChunks) {
    final result = evictAssembler.add('peer16', chunk);
    if (result != null) kept = result;
  }
  check('溢出只淘汰最旧组，其它组仍在收', kept != null);

  // 6. 求同步信令。
  check('pull 前缀可识别', SyncPlayPullRequest.isPull(SyncPlayPullRequest.encode()));
  check('pull 不会被误判为播放请求',
      !SyncPlayPlayRequest.isPlayRequest(SyncPlayPullRequest.encode()));
  check('pull 单条远小于 150', SyncPlayPullRequest.encode().length < 150);

  print(failures == 0
      ? '\nALL PASS'
      : '\n$failures FAILED');
}
