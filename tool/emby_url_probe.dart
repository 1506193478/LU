// Emby 地址拼接探针。
//
// 播放地址拼错一个 `?` 或者漏了 `api_key`，表现出来就是"点开一片黑"，
// 沙箱里跑不起来 GUI，只能靠这种纯 Dart 探针把关。
//
// 运行：
//   dart --packages=.dart_tool/package_config.json tool/emby_url_probe.dart
//
// 注意这份探针的来历：它最早把 `MediaSourceId=<条目 id>` 写成了期望值，
// 于是「拼错」这件事被测试锁死成了「正确」。真实服务器上 Emby 4.9+ 的媒体源 id
// 是 `mediasource_<itemId>`，拿条目 id 去请求直接 400
// `Value cannot be null. (Parameter 'mediaSource')`，播放整块不可用。
// 现在期望值改成：**没拿到真实媒体源 id 就一个都不写**。
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

void checkFalse(String label, bool value) {
  checkTrue(label, !value);
}

void main() {
  const String server = 'http://192.168.1.10:8096';
  const String token = 'abc123';
  const String itemId = 'f1e2d3c4';
  // Emby 4.9+ 真实媒体源 id 的形状。
  const String mediaSourceId = 'mediasource_f1e2d3c4';

  print('=== 直连：没拿到媒体源 id（必须整个参数不写） ===');
  final directPlain = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
  );
  check(
    '完整形态',
    directPlain,
    'http://192.168.1.10:8096/Videos/f1e2d3c4/stream?static=true&api_key=abc123',
  );
  checkFalse(
    '绝不把条目 id 当媒体源 id（这就是 400 的根因）',
    directPlain.contains('MediaSourceId'),
  );
  checkTrue('只有一个 ?', '?'.allMatches(directPlain).length == 1);
  checkTrue('带 static=true（不转码）', directPlain.contains('static=true'));
  checkTrue('带 api_key', directPlain.endsWith('api_key=$token'));
  checkTrue('没有空的 && 段', !directPlain.contains('&&'));
  checkTrue('没有裸的 & 结尾', !directPlain.endsWith('&'));

  print('=== 直连：拿到真实媒体源 id ===');
  final directReal = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    mediaSourceId: mediaSourceId,
  );
  checkTrue(
    '带的是 PlaybackInfo 给的真实 id',
    directReal.contains('MediaSourceId=$mediaSourceId'),
  );
  checkFalse(
    '不是条目 id',
    directReal.contains('MediaSourceId=$itemId&'),
  );
  checkTrue('路径里仍是条目 id', directReal.contains('/Videos/$itemId/stream'));

  print('=== 直连：空字符串等同于没拿到 ===');
  final directEmpty = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    mediaSourceId: '',
  );
  checkFalse('空 id 不写参数', directEmpty.contains('MediaSourceId'));
  check('空 id 与 null 完全等价', directEmpty, directPlain);

  print('=== 没 Token 时不留空参数 ===');
  final directNoToken = embyDirectStreamUrl(
    serverUrl: server,
    itemId: itemId,
  );
  check(
    '没 Token 的形态',
    directNoToken,
    'http://192.168.1.10:8096/Videos/f1e2d3c4/stream?static=true',
  );
  checkFalse('不出现 api_key', directNoToken.contains('api_key'));

  print('=== HLS 转码地址 ===');
  final hls = embyHlsStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    mediaSourceId: mediaSourceId,
  );
  checkTrue('指向 master.m3u8', hls.contains('/Videos/$itemId/master.m3u8'));
  checkTrue('带真实媒体源 id', hls.contains('MediaSourceId=$mediaSourceId'));
  checkTrue('指定 h264', hls.contains('VideoCodec=h264'));
  checkTrue('音频双编码', hls.contains('AudioCodec=aac,mp3'));
  checkTrue('指定 ts 分片', hls.contains('SegmentContainer=ts'));
  checkTrue('带 api_key', hls.contains('api_key=$token'));
  checkTrue('只有一个 ?', '?'.allMatches(hls).length == 1);

  final hlsPlain = embyHlsStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
  );
  checkFalse('没拿到 id 时 HLS 也不写 MediaSourceId',
      hlsPlain.contains('MediaSourceId'));
  checkTrue('直连和 HLS 是不同地址', directPlain != hlsPlain);

  print('=== HLS 画质上限（转码与串流页）===');
  final hlsCapped = embyHlsStreamUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    mediaSourceId: mediaSourceId,
    maxBitrateBps: 4000000,
  );
  checkTrue('带画质上限', hlsCapped.contains('MaxStreamingBitrate=4000000'));
  checkTrue('视频码率扣掉音频开销',
      hlsCapped.contains('VideoBitrate=3616000'));
  checkTrue('限制音频码率', hlsCapped.contains('AudioBitrate=192000'));
  checkFalse('不限码率时不写 MaxStreamingBitrate',
      hlsPlain.contains('MaxStreamingBitrate'));
  checkTrue('加了参数后仍然只有一个 ?', '?'.allMatches(hlsCapped).length == 1);

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
  checkFalse('没 tag 时不出现空 tag 参数', imageNoTag.contains('tag='));
  checkTrue('没 tag 时仍带 api_key', imageNoTag.contains('api_key=$token'));

  print('=== 背景大图 ===');
  final backdrop = embyBackdropUrl(
    serverUrl: server,
    itemId: itemId,
    accessToken: token,
    tag: 'bd-tag',
  );
  checkTrue('走 Backdrop 接口', backdrop.contains('/Images/Backdrop'));
  checkTrue('带 maxWidth', backdrop.contains('maxWidth=1600'));
  checkTrue('带 tag', backdrop.contains('tag=bd-tag'));

  print('=== 子路径安装 ===');
  const String subPath = 'https://media.example.com/emby';
  final subDirect = embyDirectStreamUrl(
    serverUrl: subPath,
    itemId: itemId,
    accessToken: token,
    mediaSourceId: mediaSourceId,
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
