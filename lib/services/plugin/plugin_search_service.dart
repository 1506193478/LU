import 'package:mobx/mobx.dart';

import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/plugin/rule_engine_models.dart';
import 'package:XL/utils/async_session.dart';

/// 并发检索所有规则源，并把结果写回给定的集合。
///
/// 结果容器由调用方提供，因此番剧详情页与「一起看」页可以各自持有一份
/// 检索状态，互不干扰。
class PluginSearchService {
  PluginSearchService({
    required this.searchStatus,
    required this.searchResponseList,
    required this.pluginsController,
  });

  /// 每个规则源的检索状态。
  final ObservableMap<String, PluginSearchStatus> searchStatus;

  /// 已完成的检索结果。
  final ObservableList<PluginSearchResponse> searchResponseList;

  final PluginsController pluginsController;
  final RuleCancelToken _cancelToken = RuleCancelToken();

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name == pluginName) {
        searchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        searchStatus[pluginName] = PluginSearchStatus.pending;
        await _queryPlugin(plugin, keyword);
        return;
      }
    }
  }

  /// Publishes the result page harvested by the captcha webview, skipping
  /// one network round trip. Returns false when the HTML does not parse
  /// into results; callers should fall back to [querySource].
  bool applyHarvestedSearchResult(String pluginName, String html) {
    if (_isCancelled) return false;
    for (final plugin in pluginsController.pluginList) {
      if (plugin.name != pluginName) continue;
      final result = plugin.parseHarvestedSearch(html);
      if (result == null) return false;
      searchResponseList.removeWhere(
        (response) => response.pluginName == pluginName,
      );
      searchStatus[pluginName] = PluginSearchStatus.success;
      pluginsController.validityTracker.markSearchValid(pluginName);
      searchResponseList.add(result);
      return true;
    }
    return false;
  }

  Future<void> queryAllSource(String keyword) async {
    searchResponseList.clear();
    searchStatus.clear();

    final plugins = List<Plugin>.of(pluginsController.pluginList);
    for (final plugin in plugins) {
      searchStatus[plugin.name] = PluginSearchStatus.pending;
    }
    await Future.wait(
      plugins.map((plugin) => _queryPlugin(plugin, keyword)),
    );
  }

  Future<void> _queryPlugin(Plugin plugin, String keyword) async {
    if (_isCancelled) return;
    final session = _querySessions
        .putIfAbsent(plugin.name, AsyncSessionOwner.new)
        .begin();
    try {
      final result = await plugin.queryBangumi(
        keyword,
        shouldRethrow: true,
        cancelToken: _cancelToken,
      );
      if (_isCancelled || session.isStale) return;
      searchStatus[plugin.name] = PluginSearchStatus.success;
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      searchResponseList.add(result);
    } catch (error) {
      if (_isCancelled || session.isStale) return;
      _handleSearchError(plugin, error);
    }
  }

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      KazumiLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      searchStatus[error.pluginName] = PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      KazumiLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      searchStatus[error.pluginName] = PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    KazumiLogger().w('PluginSearchService: search error for $name');
    searchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    _cancelToken.cancel();
  }
}
