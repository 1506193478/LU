import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/roads/road_module.dart';
import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/pages/syncplay/syncplay_source_sheet.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:XL/services/plugin/rule_engine_models.dart';

/// 只回放固定检索结果的假规则源，避免测试联网。
class _FakePlugin extends Plugin {
  _FakePlugin(this.fakeName)
      : super(
          api: '1',
          type: 'anime',
          name: fakeName,
          version: '1',
          muliSources: true,
          useWebview: false,
          useNativePlayer: true,
          usePost: false,
          useLegacyParser: false,
          adBlocker: false,
          userAgent: '',
          baseUrl: 'https://example.com',
          searchURL: '',
          searchList: '',
          searchName: '',
          searchResult: '',
          chapterRoads: '',
          chapterResult: '',
          referer: '',
        );

  final String fakeName;

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    return PluginSearchResponse(
      pluginName: fakeName,
      data: [SearchItem(name: '第1话 假片源', src: 'https://example.com/ep1')],
    );
  }

  @override
  Future<List<Road>> queryChapterRoads(
    String source, {
    RuleCancelToken? cancelToken,
  }) async {
    return const [];
  }
}

BangumiItem _bangumiItem() => BangumiItem(
      id: 1,
      type: 2,
      name: 'Fake Bangumi',
      nameCn: '元氣少女',
      summary: '',
      airDate: '2026-01-01',
      airWeekday: 1,
      rank: 1,
      images: const {},
      tags: const [],
      alias: const ['元气少女'],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );

void main() {
  testWidgets('一起看的「播放来源」面板能渲染出检索结果', (tester) async {
    final pluginsController = PluginsController();
    pluginsController.pluginList.add(_FakePlugin('测试来源'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncPlaySourceSheet(
            bangumiItem: _bangumiItem(),
            pluginsController: pluginsController,
            onSelected: (plugin, searchItem, roads) {},
          ),
        ),
      ),
    );

    // 检索是异步的，等它跑完并重建。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // 之前这里会抛 UnsupportedError（const 列表不可写），
    // release 下整块弹层变成灰色空板。
    expect(tester.takeException(), isNull);

    expect(find.text('播放来源'), findsOneWidget);
    expect(find.text('测试来源'), findsOneWidget);
    expect(find.text('第1话 假片源'), findsOneWidget);
  });

  testWidgets('来源没有结果时给出空状态而不是空白', (tester) async {
    final pluginsController = PluginsController();
    pluginsController.pluginList.add(_EmptyPlugin('空来源'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncPlaySourceSheet(
            bangumiItem: _bangumiItem(),
            pluginsController: pluginsController,
            onSelected: (plugin, searchItem, roads) {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('空来源'), findsOneWidget);
  });
}

class _EmptyPlugin extends Plugin {
  _EmptyPlugin(this.fakeName)
      : super(
          api: '1',
          type: 'anime',
          name: fakeName,
          version: '1',
          muliSources: true,
          useWebview: false,
          useNativePlayer: true,
          usePost: false,
          useLegacyParser: false,
          adBlocker: false,
          userAgent: '',
          baseUrl: 'https://example.com',
          searchURL: '',
          searchList: '',
          searchName: '',
          searchResult: '',
          chapterRoads: '',
          chapterResult: '',
          referer: '',
        );

  final String fakeName;

  @override
  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
    RuleCancelToken? cancelToken,
  }) async {
    return PluginSearchResponse(pluginName: fakeName, data: const []);
  }
}
