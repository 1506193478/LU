// Emby 地址拼接探针。
//
// 播放地址拼错一个 `?` 或者漏了 `api_key`，表现出来就是"点开一片黑"，
// 沙箱里跑不起来 GUI，只能靠这种纯 Dart 探针把关。
//
// 运行：
//   dart --packages=.dart_tool/package_config.json tool/emby_url_probe.dart
import 'package:XL/modules/emby/emby_urls.dart';

int _pass = 0;
int _fail = 0;

void check(String label, Object? actual, Object? expected) {
  if (actual == expected) {
    _pass++;
    return;
  }
  _fail++;
  print('FAIL  $label\n      期望: $expected\n      实际: $actual');
}

void checkTrue(String label, bool value) {
  if (value) {
    _pass++;
    return;
  }
  _fail++;
  print('FAIL  $label（期望为真）');
}

void main() {
  const String server = 'http://192.168.1.10:8096';
  const String token = 'abc123';
  const String itemId = 'f1e2d3c4';

  print('=== 直连播放地址 ===');
  final direct = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
  );
  check(
    '完整形态',
    direct,
    'http://192.168.1.10:8096/Videos/f1e2d3c4/stream'
    '?static=true&MediaSourceId=f1e2d3c4&api_key=abc123',
  );
  checkTrue('只有一个 ?', '?'.allMatches(direct).length == 1);
  checkTrue('带 static=true（不转码）', direct.contains('static=true'));
  checkTrue('带 MediaSourceId', direct.contains('MediaSourceId=$itemId'));
  checkTrue('带 api_key', direct.endsWith('api_key=$token'));
  checkTrue('没有空的 && 段', !direct.contains('&&'));
  checkTrue('没有裸的 & 结尾', !direct.endsWith('&'));

  final directNoToken = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
  );
  check(
    '没 Token 时不留空参数',
    directNoToken,
    'http://192.168.1.10:8096/Videos/f1e2d3c4/stream'
    '?static=true&MediaSourceId=f1e2d3c4',
  );
  checkTrue('没 Token 时不出现 api_key', !directNoToken.contains('api_key'));

  print('=== HLS 转码地址 ===');
  final hls = embyHlsStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
  );
  checkTrue('指向 master.m3u8', hls.contains('/Videos/$itemId/master.m3u8'));
  checkTrue('指定 h264', hls.contains('VideoCodec=h264'));
  checkTrue('音频双编码', hls.contains('AudioCodec=aac,mp3'));
  checkTrue('指定 ts 分片', hls.contains('SegmentContainer=ts'));
  checkTrue('带 api_key', hls.contains('api_key=$token'));
  checkTrue('只有一个 ?', '?'.allMatches(hls).length == 1);
  checkTrue('直连和 HLS 是不同地址', direct != hls);

  print('=== 封面地址 ===');
  final image = embyImageUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    maxHeight: 480,
    tag: 'tag-xyz',
  );
  check(
    '完整形态',
    image,
    'http://192.168.1.10:8096/Items/f1e2d3c4/Images/Primary'
    '?maxHeight=480&quality=90&tag=tag-xyz&api_key=abc123',
  );
  checkTrue('带 tag（服务端缓存键）', image.contains('tag=tag-xyz'));
  checkTrue('带尺寸', image.contains('maxHeight=480'));

  final imageNoTag = embyImageUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
  );
  checkTrue('没 tag 时不出现空 tag 参数', !imageNoTag.contains('tag='));
  checkTrue('没 tag 时仍带 api_key', imageNoTag.contains('api_key=$token'));

  print('=== 子路径安装 ===');
  const String subPath = 'https://media.example.com/emby';
  final subDirect = embyDirectStreamUrl(
    serverUrl: subPath,
    itemId: itemId,
    accessToken: token,
  );
  checkTrue(
    '子路径被保留',
    subDirect.startsWith('https://media.example.com/emby/Videos/'),
  );
  checkTrue('子路径下依然只有一个 ?', '?'.allMatches(subDirect).length == 1);

  print('=== 特殊字符 ===');
  // Emby 的 item id 是十六进制 GUID，但 Token 里可能出现 + / = 这类字符。
  const String weirdToken = 'a+b/c=d';
  final weird = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: weirdToken,
  );
  checkTrue('特殊字符 Token 原样拼上', weird.endsWith('api_key=$weirdToken'));

  print('');
  print('通过 $_pass 项，失败 $_fail 项');
  if (_fail > 0) {
    throw StateError('Emby 地址探针有 $_fail 项未通过');
  }
}
