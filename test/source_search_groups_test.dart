import 'package:flutter_test/flutter_test.dart';
import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/pages/info/source_search_sheet_view.dart';

SearchItem _item(String name, String src) => SearchItem(name: name, src: src);

void main() {
  group('buildSourceSearchGroups', () {
    test('按来源顺序组装分组，缺失状态回落到 pending', () {
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A', '源B'],
        status: {'源A': PluginSearchStatus.success},
        responses: const [],
        keywordFor: (name) => 'kw-$name',
      );

      expect(groups.map((group) => group.name), ['源A', '源B']);
      expect(groups[0].status, PluginSearchStatus.success);
      expect(groups[1].status, PluginSearchStatus.pending);
      expect(groups[0].keyword, 'kw-源A');
      expect(groups[0].results, isEmpty);
    });

    test('检索结果按来源归位，重复 src 只保留一条', () {
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A', '源B'],
        status: {
          '源A': PluginSearchStatus.success,
          '源B': PluginSearchStatus.success,
        },
        responses: [
          PluginSearchResponse(
            pluginName: '源A',
            data: [_item('第1话', 'a1'), _item('第1话重复', 'a1')],
          ),
          PluginSearchResponse(
            pluginName: '源B',
            data: [_item('第2话', 'b1')],
          ),
        ],
        keywordFor: (name) => name,
      );

      expect(groups[0].results.map((item) => item.name), ['第1话']);
      expect(groups[1].results.map((item) => item.name), ['第2话']);
    });

    test('回归：分组里的结果列表必须可变，不能是 const 列表', () {
      // 早期版本在这里用了 `const <SearchItem>[]`，后续 add 结果时抛
      // UnsupportedError，整个「播放来源」弹层在 release 下变成一片灰色空板。
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A'],
        status: {'源A': PluginSearchStatus.success},
        responses: [
          PluginSearchResponse(pluginName: '源A', data: [_item('第1话', 'a1')]),
        ],
        keywordFor: (name) => name,
      );

      expect(() => groups.first.results.add(_item('第2话', 'a2')), returnsNormally);
      expect(groups.first.results.length, 2);
    });

    test('未知来源的响应被忽略，不会凭空多出分组', () {
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A'],
        status: const {},
        responses: [
          PluginSearchResponse(pluginName: '不存在的源', data: [_item('x', 'x1')]),
        ],
        keywordFor: (name) => name,
      );

      expect(groups.length, 1);
      expect(groups.first.name, '源A');
      expect(groups.first.results, isEmpty);
    });
  });

  group('firstResultSourceOf', () {
    test('返回第一个有结果的来源', () {
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A', '源B'],
        status: {
          '源A': PluginSearchStatus.success,
          '源B': PluginSearchStatus.success,
        },
        responses: [
          PluginSearchResponse(pluginName: '源A', data: [_item('第1话', 'a1')]),
          PluginSearchResponse(pluginName: '源B', data: [_item('第1话', 'b1')]),
        ],
        keywordFor: (name) => name,
      );

      expect(firstResultSourceOf(groups), '源A');
    });

    test('没有结果时返回 null', () {
      final groups = buildSourceSearchGroups(
        sourceNames: ['源A'],
        status: {'源A': PluginSearchStatus.noResult},
        responses: const [],
        keywordFor: (name) => name,
      );

      expect(firstResultSourceOf(groups), isNull);
    });
  });
}
