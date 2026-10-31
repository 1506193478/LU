import 'dart:convert';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/network/rules_mirror.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/request/config/api_endpoints.dart';
import 'package:XL/request/clients/rules_repo_client.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/modules/plugin/plugin_http_module.dart';

class PluginCatalogApi {
  static final RulesRepoClient _client = RulesRepoClient.instance;

  /// 规则目录的候选源，按优先级排列。
  ///
  /// 第三方镜像的同步是滞后的：GitCode 那份 index.json 长期停在 17 条，
  /// 少的是 `TvTFun`（连对应的 json 都没同步过去）。用户看到的就是
  /// 「官方说 18 条，我这儿只有 17 条」，而且少的那条在商店里根本不存在，
  /// 换什么镜像都装不上。
  ///
  /// 所以这里不再「只认一个源」：把当前选择 + gh-proxy + GitCode 都拉一遍，
  /// 按规则名合并、取 `lastUpdate` 最新的那条。任何一个源活着就不会丢规则。
  ///
  /// 用户自己填了自定义仓库时只认那一个——那是明确指定，不该被掺沙子。
  static List<String> catalogSources() {
    final custom = GStorage.getSetting(SettingsKeys.rulesRepoUrl).trim();
    if (custom.isNotEmpty) {
      return [custom.endsWith('/') ? custom : '$custom/'];
    }
    final selected = switch (RulesMirror.current) {
      RulesMirror.direct => ApiEndpoints.pluginShop,
      RulesMirror.ghProxy =>
        ApiEndpoints.ghProxyMirror + ApiEndpoints.pluginShop,
      RulesMirror.ghfast =>
        ApiEndpoints.ghfastMirror + ApiEndpoints.pluginShop,
      RulesMirror.gitcode => ApiEndpoints.gitcodeMirror,
    };
    // Set 去重，同时保住插入顺序（第一个是用户选的那个源）。
    return <String>{
      selected,
      ApiEndpoints.ghProxyMirror + ApiEndpoints.pluginShop,
      ApiEndpoints.gitcodeMirror,
    }.toList(growable: false);
  }

  static Future<List<PluginHTTPItem>> getPluginList() async {
    final sources = catalogSources();
    final errors = <Object>[];

    final results = await Future.wait<PluginCatalogParseResult?>([
      for (final base in sources)
        _client
            .getText('${base}index.json')
            .then<PluginCatalogParseResult?>(parsePluginList)
            .catchError((Object error) {
          // 单个源挂掉不该让整个目录不可用。
          errors.add(error);
          KazumiLogger().w('Plugin: rule catalog source failed: $base');
          return null;
        }),
    ]);

    final merged = <String, PluginHTTPItem>{};
    var skippedItems = 0;
    var liveSources = 0;
    for (final result in results) {
      if (result == null) continue;
      liveSources++;
      skippedItems += result.skippedItems;
      for (final item in result.items) {
        final key = pluginNameKey(item.name);
        final previous = merged[key];
        if (previous == null || _isNewer(item, previous)) {
          merged[key] = item;
        }
      }
    }

    if (skippedItems > 0) {
      KazumiLogger().w(
        'Plugin: skipped $skippedItems invalid rule catalog item(s)',
      );
    }
    if (liveSources == 0) {
      // 全挂：把第一个真实错误抛出去，调用方才知道是网络问题。
      if (errors.isNotEmpty) throw errors.first;
      throw const FormatException('Rule catalog is unreachable');
    }
    return List<PluginHTTPItem>.unmodifiable(merged.values);
  }

  /// 同名规则谁更新：先比 `lastUpdate`，再退回版本号。
  static bool _isNewer(PluginHTTPItem candidate, PluginHTTPItem current) {
    if (candidate.lastUpdate != current.lastUpdate) {
      return candidate.lastUpdate > current.lastUpdate;
    }
    return _compareVersion(candidate.version, current.version) > 0;
  }

  static int _compareVersion(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
      final r = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static PluginCatalogParseResult parsePluginList(String raw) {
    final jsonData = json.decode(raw);
    if (jsonData is! List) {
      throw const FormatException('Rule catalog root must be a JSON array');
    }
    final items = <PluginHTTPItem>[];
    var skippedItems = 0;
    for (var index = 0; index < jsonData.length; index++) {
      try {
        items.add(_parsePluginListItem(jsonData[index], index));
      } on FormatException {
        skippedItems++;
      }
    }
    if (jsonData.isNotEmpty && items.isEmpty) {
      throw const FormatException('Rule catalog contains no valid items');
    }
    return PluginCatalogParseResult(
      items: List.unmodifiable(items),
      skippedItems: skippedItems,
    );
  }

  static PluginHTTPItem _parsePluginListItem(Object? value, int index) {
    if (value is! Map) {
      throw FormatException('Rule catalog item $index must be an object');
    }
    try {
      return PluginHTTPItem.fromJson(Map<String, dynamic>.from(value));
    } catch (error) {
      throw FormatException('Invalid rule catalog item $index: $error');
    }
  }

  /// 下载单条规则。
  ///
  /// 也要走多源：目录合并后可能列出镜像上根本没有的规则（GitCode 缺
  /// `TvTFun`），只认一个源的话点安装就是 404。
  static Future<Plugin> getPlugin(String name) async {
    Object? lastError;
    for (final base in catalogSources()) {
      try {
        final raw = await _client.getText('$base$name.json');
        final jsonData = json.decode(raw);
        if (jsonData is! Map) {
          throw FormatException('Rule $name must be a JSON object');
        }
        return Plugin.fromJson(Map<String, dynamic>.from(jsonData));
      } catch (error) {
        lastError = error;
        KazumiLogger().w('Plugin: rule $name not available from $base');
      }
    }
    throw lastError ?? FormatException('Rule $name is unreachable');
  }
}

class PluginCatalogParseResult {
  const PluginCatalogParseResult({
    required this.items,
    required this.skippedItems,
  });

  final List<PluginHTTPItem> items;
  final int skippedItems;
}
