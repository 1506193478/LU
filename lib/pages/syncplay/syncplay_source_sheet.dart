import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/roads/road_module.dart';
import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/pages/info/source_search_sheet_view.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/plugin/plugin_search_service.dart';
import 'package:XL/services/plugin/rule_engine_models.dart'
    show ChapterErrorException, RuleCancelToken;
import 'package:XL/utils/device.dart';
import 'package:XL/bean/widget/clay.dart';

/// 「一起看」的播放来源选择面板。
///
/// 与番剧详情页的来源面板共用同一套视图，但持有独立的检索状态，
/// 不会污染详情页的缓存，也不会改动「追番」收藏。
class SyncPlaySourceSheet extends StatefulWidget {
  const SyncPlaySourceSheet({
    super.key,
    required this.bangumiItem,
    required this.pluginsController,
    required this.onSelected,
  });

  final BangumiItem bangumiItem;
  final PluginsController pluginsController;

  /// 选中某个条目且成功取到剧集列表时回调。
  final void Function(Plugin plugin, SearchItem searchItem, List<Road> roads)
      onSelected;

  @override
  State<SyncPlaySourceSheet> createState() => _SyncPlaySourceSheetState();
}

class _SyncPlaySourceSheetState extends State<SyncPlaySourceSheet>
    with KazumiDialogOwner<SyncPlaySourceSheet> {
  final ObservableMap<String, PluginSearchStatus> _status = ObservableMap();
  final ObservableList<PluginSearchResponse> _responses = ObservableList();
  final Map<String, String> _sourceKeywords = {};

  late final String _keyword;
  late final PluginSearchService _searchService;

  @override
  void initState() {
    super.initState();
    final item = widget.bangumiItem;
    _keyword = item.nameCn.isEmpty ? item.name : item.nameCn;
    _searchService = PluginSearchService(
      searchStatus: _status,
      searchResponseList: _responses,
      pluginsController: widget.pluginsController,
    );
    _searchService.queryAllSource(_keyword);
  }

  @override
  void dispose() {
    _searchService.cancel();
    super.dispose();
  }

  String _keywordFor(String name) => _sourceKeywords[name] ?? _keyword;

  Plugin _pluginFor(String name) => widget.pluginsController.pluginList
      .firstWhere((plugin) => plugin.name == name);

  void _querySource(String keyword, String pluginName) {
    final trimmed = keyword.trim();
    if (!mounted || trimmed.isEmpty) return;
    setState(() => _sourceKeywords[pluginName] = trimmed);
    _searchService.querySource(trimmed, pluginName);
  }

  void _retry(String name) => _querySource(_keywordFor(name), name);

  Future<void> _openInBrowser(String name) async {
    final plugin = _pluginFor(name);
    final targetUrl = plugin.usesApiSearch
        ? plugin.baseUrl
        : plugin.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(_keywordFor(name)),
          );
    try {
      if (await launchUrl(Uri.parse(targetUrl),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (error) {
      KazumiLogger().w('SyncPlaySourceSheet: failed to open browser',
          error: error);
    }
    if (mounted) KazumiDialog.showError(message: '无法打开浏览器，请稍后重试');
  }

  Future<void> _play(String name, SearchItem searchItem) async {
    if (dialogs.isRunning) return;
    final plugin = _pluginFor(name);
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final roads = await task.loading(
        message: '正在获取播放列表',
        barrierDismissible: isDesktop(),
        onCancel: cancelToken.cancel,
        action: () => plugin.queryChapterRoads(searchItem.src,
            cancelToken: cancelToken),
      );
      if (roads.isEmpty) throw ChapterErrorException(plugin.name);
      widget.onSelected(plugin, searchItem, roads);
    }, onError: (error, stackTrace) {
      KazumiLogger()
          .w('SyncPlaySourceSheet: failed to query playlist', error: error);
      KazumiDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
    });
  }

  Future<void> _showCustomKeyword(String pluginName) async {
    final initial = _keywordFor(pluginName);
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ClayDialog(
        title: '修改「$pluginName」的检索词',
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入检索关键词'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          ClayButton(
            tone: ClayTone.subtle,
            height: 44,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          ClayButton(
            tone: ClayTone.accent,
            height: 44,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('检索'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    _querySource(result, pluginName);
  }

  Future<void> _showAliasPicker(String pluginName) async {
    final aliases = widget.bangumiItem.alias;
    if (aliases.isEmpty) {
      KazumiDialog.showToast(message: '无可用别名，试试修改检索关键词');
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('用别名检索「$pluginName」'),
        children: [
          for (final alias in aliases)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(alias),
              child: Text(alias),
            ),
        ],
      ),
    );
    if (result == null) return;
    _querySource(result, pluginName);
  }

  void _handleVerify(String name) {
    KazumiDialog.showToast(
      message: '该来源需要验证码，请点「在浏览器中打开」完成验证后重试',
    );
    _retry(name);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        // Snapshot observable values here; lazy list builders are not tracked.
        final groups = buildSourceSearchGroups(
          sourceNames: widget.pluginsController.pluginList
              .map((plugin) => plugin.name)
              .toList(),
          status: _status,
          responses: _responses,
          keywordFor: _keywordFor,
        );
        return SourceSearchSheetView(
          keyword: _keyword,
          groups: groups,
          firstResultSource: firstResultSourceOf(groups),
          onSourceSearch: _showCustomKeyword,
          onSourceAliasSearch: _showAliasPicker,
          onRetry: _retry,
          onVerify: _handleVerify,
          onOpenBrowser: _openInBrowser,
          onPlay: _play,
          onClose: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}
