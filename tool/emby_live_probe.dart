// 临时联调脚本：用真实 Emby 服务器验证新加接口的 JSON 解析。
//
// 凭据从环境变量读，不写死在仓库里：
//   EMBY_URL / EMBY_TOKEN / EMBY_USER
//
// 跑法：
//   EMBY_URL=... EMBY_TOKEN=... EMBY_USER=... \
//   dart --packages=.dart_tool/package_config.json tool/emby_live_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:XL/modules/emby/emby_models.dart';

Future<dynamic> getJson(String url) async {
  final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('Accept', 'application/json');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  client.close();
  if (response.statusCode >= 400) {
    throw StateError('HTTP ${response.statusCode}: $body');
  }
  return jsonDecode(body);
}

int pass = 0;
int fail = 0;

void check(String label, bool ok, [String detail = '']) {
  if (ok) {
    pass++;
    print('  ok   $label');
  } else {
    fail++;
    print('  FAIL $label $detail');
  }
}

Future<void> main() async {
  final base = Platform.environment['EMBY_URL'] ?? '';
  final token = Platform.environment['EMBY_TOKEN'] ?? '';
  final user = Platform.environment['EMBY_USER'] ?? '';
  if (base.isEmpty || token.isEmpty || user.isEmpty) {
    stderr.writeln('缺少 EMBY_URL / EMBY_TOKEN / EMBY_USER');
    exit(2);
  }

  print('=== 继续观看（Resume） ===');
  final resumeRaw = await getJson('$base/Users/$user/Items/Resume?Limit=6&MediaTypes=Video&Recursive=true&Fields=ProductionYear,CommunityRating,Overview,ImageTags,BackdropImageTags,RunTimeTicks,UserData,Genres,OfficialRating,SeriesName,ChildCount,ParentIndexNumber,IndexNumber&api_key=$token');
  final resumeItems = [
    for (final item in (resumeRaw['Items'] as List))
      EmbyItem.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
  check('拿到条目', resumeItems.isNotEmpty, '数量=${resumeItems.length}');
  if (resumeItems.isNotEmpty) {
    final first = resumeItems.first;
    check('有名字', first.name.isNotEmpty, first.name);
    check('解析出 UserData 进度', first.playbackPositionTicks != null,
        '${first.playbackPositionTicks}');
    check('进度比例在 0~1', first.watchedRatio >= 0 && first.watchedRatio <= 1,
        '${first.watchedRatio}');
    check('有主图 tag', first.primaryImageTag != null);
    print('       样本: ${first.name} | ${first.cardSubtitle} | '
        '${(first.watchedRatio * 100).toStringAsFixed(1)}%');
  }

  print('=== 最新入库（Latest，返回的是裸数组） ===');
  final latestRaw = await getJson('$base/Users/$user/Items/Latest?Limit=8&Fields=ProductionYear,ImageTags,BackdropImageTags,UserData&api_key=$token');
  final latestList = latestRaw is List ? latestRaw : (latestRaw as Map)['Items'];
  check('Latest 返回数组', latestList is List, '类型=${latestRaw.runtimeType}');
  if (latestList is List && latestList.isNotEmpty) {
    final first = EmbyItem.fromJson(
        Map<String, dynamic>.from(latestList.first as Map));
    check('能解析成条目', first.id.isNotEmpty && first.name.isNotEmpty, first.name);
    print('       样本: ${first.name}');
  }

  print('=== PlaybackInfo（媒体源 id 的关键） ===');
  // 不写死库 id：先问服务器有哪些库，挑第一个剧集库。
  final views = await getJson('$base/Users/$user/Views?api_key=$token');
  final libraries = (views['Items'] as List).cast<Map>();
  final tvLibrary = libraries.firstWhere(
    (v) => v['CollectionType'] == 'tvshows',
    orElse: () => libraries.first,
  );
  final seriesRaw = await getJson(
      '$base/Users/$user/Items?ParentId=${tvLibrary['Id']}&IncludeItemTypes=Series&Recursive=true&Limit=1&api_key=$token');
  final seriesId = ((seriesRaw['Items'] as List).first as Map)['Id'].toString();
  final episodesRaw = await getJson('$base/Shows/$seriesId/Episodes?UserId=$user&api_key=$token');
  final episodeId =
      ((episodesRaw['Items'] as List).first as Map)['Id'].toString();
  final info = await getJson('$base/Items/$episodeId/PlaybackInfo?UserId=$user&api_key=$token');
  final sources = info['MediaSources'] as List;
  final source = EmbyMediaSource.fromJson(
      Map<String, dynamic>.from(sources.first as Map));
  check('拿到媒体源', source.id.isNotEmpty, source.id);
  check('媒体源 id 不等于条目 id（这就是 400 的根因）',
      source.id != episodeId, 'item=$episodeId source=${source.id}');
  check('容器非空', source.container.isNotEmpty, source.container);
  check('音轨/字幕轨解析', source.mediaStreams.isNotEmpty,
      '共 ${source.mediaStreams.length} 条，音轨 ${source.audioStreams.length}，字幕 ${source.subtitleStreams.length}');
  for (final s in source.mediaStreams.take(6)) {
    print('       轨道 ${s.index}: ${s.type} ${s.label}');
  }

  print('=== 搜索 ===');
  final searchRaw = await getJson('$base/Users/$user/Items?SearchTerm=${Uri.encodeComponent('19')}&Recursive=true&IncludeItemTypes=Movie,Series,Episode&Limit=10&api_key=$token');
  final searchItems = [
    for (final item in (searchRaw['Items'] as List))
      EmbyItem.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
  check('搜到结果', searchItems.isNotEmpty, '${searchItems.length} 条');

  print('=== 相关推荐（Similar） ===');
  final similarRaw = await getJson('$base/Items/$seriesId/Similar?UserId=$user&Limit=6&api_key=$token');
  final similarItems = [
    for (final item in (similarRaw['Items'] as List))
      EmbyItem.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
  check('拿到相关推荐', similarItems.isNotEmpty, '${similarItems.length} 条');

  print('=== 季列表（Seasons） ===');
  final seasonsRaw = await getJson('$base/Shows/$seriesId/Seasons?UserId=$user&api_key=$token');
  final seasons = [
    for (final item in (seasonsRaw['Items'] as List))
      EmbyItem.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
  check('拿到季', seasons.isNotEmpty, '${seasons.length} 季');

  print('');
  print('通过 $pass 项，失败 $fail 项');
  if (fail > 0) exit(1);
}
