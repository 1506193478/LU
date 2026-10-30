// 验证 MacCMS(provide/vod) 源在 LU 的 api 规则引擎下真能跑通。
//
// 用真实抓下来的响应做输入（tool/fixtures/*.json），跑的是线上同一套
// ApiRuleStrategy，不是另写一份解析：规则写错这里就会红。
//
// 跑法：
//   dart tool/maccms_rule_probe.dart --packages=.dart_tool/package_config.json
import 'dart:convert';
import 'dart:io';

import 'package:XL/plugins/api_rule_config.dart';
import 'package:XL/services/plugin/api_rule_strategy.dart';

int _passed = 0;
final List<String> _failures = <String>[];

void check(String label, bool ok, [String detail = '']) {
  if (ok) {
    _passed++;
  } else {
    _failures.add('$label${detail.isEmpty ? '' : ' — $detail'}');
  }
}

void expectEq(String label, Object? actual, Object? expected) {
  check(label, actual == expected, '期望 $expected，实际 $actual');
}

Map<String, dynamic> loadJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('缺少 fixture: $path');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  const ApiRuleStrategy strategy = ApiRuleStrategy();

  final seedRaw = File('assets/video_sources/maccms_seed.json');
  if (!seedRaw.existsSync()) {
    throw StateError('缺少 assets/video_sources/maccms_seed.json');
  }
  final seed = jsonDecode(seedRaw.readAsStringSync()) as List<dynamic>;
  check('种子文件非空', seed.isNotEmpty, '条数 ${seed.length}');

  // Plugin.fromJson 会读的字段，缺了规则就会静默退化成空串。
  const requiredKeys = <String>['api', 'type', 'name', 'baseURL', 'searchMode'];
  for (var i = 0; i < seed.length; i++) {
    final item = seed[i] as Map<String, dynamic>;
    final name = item['name'] as String? ?? '#$i';
    for (final key in requiredKeys) {
      check('[$name] 含字段 $key', item.containsKey(key));
    }
    check('[$name] api 不高于 9（否则被判需更高版本客户端）',
        int.parse(item['api'].toString()) <= 9);
    check('[$name] searchMode=api', item['searchMode'] == 'api');
    check('[$name] chapterMode=api', item['chapterMode'] == 'api');
  }

  // 名字必须唯一：LU 按名字去重/覆盖，重名会互相吃掉。
  final names = seed
      .map((e) => (e as Map<String, dynamic>)['name'].toString().toLowerCase())
      .toList();
  check('规则名唯一（LU 按名去重）', names.length == names.toSet().length,
      '重名 ${names.length - names.toSet().length} 个');

  final searchJson = loadJson('tool/fixtures/maccms_search.json');
  final detailJson = loadJson('tool/fixtures/maccms_detail.json');

  final first = seed.first as Map<String, dynamic>;
  final searchConfig = ApiSearchConfig.fromJson(
    Map<String, dynamic>.from(first['searchApiConfig'] as Map),
  );
  final chapterConfig = ApiChapterConfig.fromJson(
    Map<String, dynamic>.from(first['chapterApiConfig'] as Map),
  );

  // ---- 搜索请求 ----
  final searchRequest = strategy.prepareRequest(
    searchConfig.request,
    <String, Object?>{'keyword': '凡人'},
  );
  check('搜索请求带 wd=关键词', searchRequest.query['wd'] == '凡人',
      'query=${searchRequest.query}');
  check('搜索请求带 ac=videolist', searchRequest.query['ac'] == 'videolist');
  check('搜索 URL 是完整地址', searchRequest.url.startsWith('http'),
      searchRequest.url);

  // ---- 搜索响应解析（真实响应）----
  final parsedSearch = strategy.parseSearch(
    jsonEncode(searchJson),
    searchConfig,
  );
  check('搜索解析出结果', parsedSearch.items.isNotEmpty,
      '诊断=${parsedSearch.diagnostics}');
  expectEq('搜索结果条数', parsedSearch.items.length,
      (searchJson['list'] as List).length);
  check('首条名称正确', parsedSearch.items.first.name == '凡人修仙传',
      parsedSearch.items.first.name);

  // vod_id 是数字，必须能当 src 用（_stringValue 走 toString）。
  final firstId = (searchJson['list'] as List).first['vod_id'];
  expectEq('src 取到 vod_id', parsedSearch.items.first.src, firstId.toString());

  // ---- 章节请求 ----
  final chapterRequest = strategy.prepareRequest(
    chapterConfig.request,
    <String, Object?>{'source': firstId.toString()},
  );
  check('章节请求带 ids=来源 id', chapterRequest.query['ids'] == firstId.toString(),
      'query=${chapterRequest.query}');
  check('章节请求带 ac=detail', chapterRequest.query['ac'] == 'detail');

  // ---- 章节响应解析（真实响应，分隔符格式）----
  final parsedChapters = strategy.parseChapters(
    jsonEncode(detailJson),
    chapterConfig,
    source: firstId.toString(),
    baseUrl: first['baseURL'] as String,
  );
  check('解析出线路', parsedChapters.roads.isNotEmpty,
      '诊断=${parsedChapters.diagnostics}');
  final playUrl =
      (detailJson['list'] as List).first['vod_play_url'] as String? ?? '';
  final expectedEpisodes = playUrl.split('#').where((e) => e.trim().isNotEmpty).length;
  expectEq('剧集数（按 # 切分）', parsedChapters.roads.first.data.length,
      expectedEpisodes);
  check('首集名正确', parsedChapters.roads.first.identifier.first == '第01集',
      parsedChapters.roads.first.identifier.first);
  check('首集 URL 是 http 地址',
      parsedChapters.roads.first.data.first.startsWith('http'),
      parsedChapters.roads.first.data.first);

  // ---- 分隔符边界：多线路（$$$）也能切开 ----
  final multiRoad = <String, dynamic>{
    'list': <dynamic>[
      <String, dynamic>{
        'vod_play_from': '线路A\$\$\$线路B',
        'vod_play_url': '第1集\$http://a/1.m3u8#第2集\$http://a/2.m3u8'
            '\$\$\$第1集\$http://b/1.m3u8',
      },
    ],
  };
  final multiParsed = strategy.parseChapters(
    jsonEncode(multiRoad),
    chapterConfig,
    source: '1',
    baseUrl: first['baseURL'] as String,
  );
  expectEq('多线路切出 2 条线路', multiParsed.roads.length, 2);
  expectEq('线路名取自 vod_play_from', multiParsed.roads.first.name, '线路A');
  expectEq('第二条线路剧集数', multiParsed.roads[1].data.length, 1);

  // ---- 每条规则的 JSONPath 都要能过校验 ----
  for (var i = 0; i < seed.length; i++) {
    final item = seed[i] as Map<String, dynamic>;
    final name = item['name'].toString();
    try {
      strategy.validateSearchConfig(ApiSearchConfig.fromJson(
        Map<String, dynamic>.from(item['searchApiConfig'] as Map),
      ));
      strategy.validateChapterConfig(ApiChapterConfig.fromJson(
        Map<String, dynamic>.from(item['chapterApiConfig'] as Map),
      ));
      _passed++;
    } catch (error) {
      _failures.add('[$name] JSONPath 校验失败 — $error');
    }
  }

  stdout.writeln('通过 $_passed 项');
  if (_failures.isEmpty) {
    stdout.writeln('全部通过（规则 ${seed.length} 条）');
  } else {
    stdout.writeln('失败 ${_failures.length} 项：');
    for (final failure in _failures) {
      stdout.writeln('  ✗ $failure');
    }
    exit(1);
  }
}
