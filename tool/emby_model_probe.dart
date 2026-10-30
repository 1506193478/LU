// Emby 模型层的纯 Dart 探针。
//
// 沙箱跑不了 `flutter test`（ech_http 的 native hook 会碰 reg.exe，
// 被安全策略拉黑），所以关键逻辑用 dart 直接跑，和
// `sticker_proto_probe.dart` / `light_mode_contrast_probe.dart` 是同一套路子。
//
// 运行：
//   dart --packages=.dart_tool/package_config.json tool/emby_model_probe.dart
import 'package:XL/modules/emby/emby_models.dart';

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
  print('=== normalizeEmbyUrl ===');
  check('带协议与端口', normalizeEmbyUrl('http://192.168.1.10:8096'),
      'http://192.168.1.10:8096');
  check('尾斜杠被去掉', normalizeEmbyUrl('http://192.168.1.10:8096/'),
      'http://192.168.1.10:8096');
  check('多个尾斜杠', normalizeEmbyUrl('http://host:8096///'),
      'http://host:8096');
  check('漏协议自动补 http', normalizeEmbyUrl('192.168.1.10:8096'),
      'http://192.168.1.10:8096');
  check('网页入口路径被砍掉',
      normalizeEmbyUrl('http://host:8096/web/index.html'), 'http://host:8096');
  check('只有 /web', normalizeEmbyUrl('http://host:8096/web'),
      'http://host:8096');
  check('子路径安装保留',
      normalizeEmbyUrl('https://media.example.com/emby/'),
      'https://media.example.com/emby');
  check('子路径 + 网页入口',
      normalizeEmbyUrl('https://media.example.com/emby/web/index.html'),
      'https://media.example.com/emby');
  check('查询串被丢掉',
      normalizeEmbyUrl('http://host:8096/?api_key=abc'), 'http://host:8096');
  check('空串', normalizeEmbyUrl('   '), '');
  check('只有协议没主机', normalizeEmbyUrl('http://'), '');
  check('前后空格被裁掉', normalizeEmbyUrl('  http://host:8096  '),
      'http://host:8096');

  print('=== embyBangumiId ===');
  final String seriesId = 'a1b2c3d4e5f60718a1b2c3d4e5f60718';
  final int id1 = embyBangumiId(seriesId);
  final int id2 = embyBangumiId(seriesId);
  check('同一 id 每次算出来一样', id1, id2);
  checkTrue('结果是正数', id1 > 0);
  checkTrue('不为 0', id1 != 0);
  checkTrue('落在 int 安全范围', id1 <= 0x7fffffff);
  checkTrue('不同剧集 id 不同',
      embyBangumiId('$seriesId-x') != embyBangumiId(seriesId));
  // 撞 id 会串历史，抽 5000 个 id 看有没有碰撞。
  final seen = <int>{};
  var collisions = 0;
  for (var i = 0; i < 5000; i++) {
    if (!seen.add(embyBangumiId('emby-item-$i'))) collisions++;
  }
  check('5000 个 id 无碰撞', collisions, 0);
  check('空串也给正数', embyBangumiId('') > 0, true);

  print('=== EmbyServer.adapterName ===');
  const base = EmbyServer(
    id: 'srv1',
    name: '家里的 NAS',
    url: 'http://192.168.1.10:8096',
    userId: 'u1',
    userName: 'me',
    accessToken: 'token',
  );
  check('默认取 host:port', base.adapterName, 'emby:192.168.1.10:8096');
  check('子路径不影响分档',
      base.copyWith(url: 'https://media.example.com/emby').adapterName,
      'emby:media.example.com');
  check('地址坏了退回 id',
      base.copyWith(url: '不是地址').adapterName, 'emby:srv1');

  print('=== EmbyServer JSON 往返 ===');
  final restored = EmbyServer.fromJson(base.toJson());
  check('id 保留', restored.id, base.id);
  check('url 保留', restored.url, base.url);
  check('token 保留', restored.accessToken, base.accessToken);
  check('自签开关保留', restored.allowBadCertificate, false);
  check('缺字段时用默认值',
      EmbyServer.fromJson(const {'id': 'x'}).allowBadCertificate, false);

  print('=== EmbyItem 解析 ===');
  final item = EmbyItem.fromJson(const {
    'Id': 'ep1',
    'Name': '第 3 集 出发',
    'Type': 'Episode',
    'IndexNumber': 3,
    'ParentIndexNumber': 1,
    'ProductionYear': 2021,
    'CommunityRating': 8.44,
    'RunTimeTicks': 14400000000,
    'ImageTags': {'Primary': 'tag-abc'},
  });
  check('id', item.id, 'ep1');
  check('集号', item.indexNumber, 3);
  check('季号', item.parentIndexNumber, 1);
  check('封面 tag', item.primaryImageTag, 'tag-abc');
  check('评分格式化', item.metaLine, '2021 · 8.4 分');
  check('时长换算（100ns 一格）', item.runTime, const Duration(minutes: 24));
  check('缺字段不炸', EmbyItem.fromJson(const {}).id, '');
  check('没有 ImageTags 时 tag 为空',
      EmbyItem.fromJson(const {'Id': 'x'}).primaryImageTag, null);
  check('Series 类型识别', EmbyItem.fromJson(const {'Type': 'Series'}).isSeries,
      true);
  check('Movie 类型识别', EmbyItem.fromJson(const {'Type': 'Movie'}).isMovie,
      true);

  print('=== EmbyLibrary 解析 ===');
  final library = EmbyLibrary.fromJson(const {
    'Id': 'lib1',
    'Name': '剧集',
    'CollectionType': 'tvshows',
  });
  check('库 id', library.id, 'lib1');
  check('库类型', library.collectionType, 'tvshows');

  print('');
  print('通过 $_pass 项，失败 $_fail 项');
  if (_fail > 0) {
    throw StateError('Emby 模型探针有 $_fail 项未通过');
  }
}
