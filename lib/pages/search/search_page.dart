import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/appbar/sys_app_bar.dart';
import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/bean/dialog/material_bottom_sheet.dart';
import 'package:XL/bean/widget/kazumi_menu.dart';
import 'package:XL/bean/widget/loading_indicator.dart';
import 'package:XL/bean/widget/skeleton_card.dart';
import 'package:XL/bean/widget/empty_state_widget.dart';
import 'package:XL/bean/widget/state_presentation.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/search/search_config.dart';
import 'package:XL/pages/search/search_controller.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/constants.dart';
import 'package:XL/utils/date_time.dart';
import 'package:XL/utils/search_parser.dart';

part 'search_filter_sheet.dart';
part 'search_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final SearchPageController controller;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  // Preserve the input subtree when the header moves in or out of the scroll view.
  final _searchHeaderKey = GlobalKey();
  String? _submittedQuery;
  bool _managingHistory = false;

  SearchPageController get _controller => widget.controller;
  bool get _hasSearched => _submittedQuery != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreOnScroll);
    _inputFocus.addListener(_syncFocus);
    _controller.loadSearchHistories();
    // 热搜榜与推荐位先于用户输入加载，进入搜索页就有内容可看。
    _controller.loadHotRanking();
    _controller.loadRecommendations();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(widget.initialQuery);
      });
    }
  }

  void _syncFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_syncFocus);
    _controller.clearSuggestions();
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _writeInput(String value) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _submit(String value) async {
    final filters = SearchParser(value).toFilterState();
    final query = SearchParser.fromFilterState(filters);
    _inputFocus.unfocus();
    _writeInput(query);
    // _writeInput 会触发 onChanged 并排一次联想请求，这里立刻取消掉。
    _controller.clearSuggestions();
    setState(() => _submittedQuery = query);
    final request = _controller.searchBangumi(query, type: 'init');
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await request;
  }

  Future<void> _applyFilters(SearchFilterState filters) =>
      _submit(SearchParser.fromFilterState(filters));

  void _loadMoreOnScroll() {
    if (!_scroll.hasClients || _scroll.position.extentAfter > 360) return;
    _loadMore();
  }

  void _loadMore() {
    final query = _submittedQuery;
    if (query != null) _controller.searchBangumi(query);
  }

  Future<void> _showFilters() async {
    _inputFocus.unfocus();
    final result = await showAdaptiveBottomSheet<_SearchFilterResult>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => _SearchFilterSheet(
        initialState: SearchParser(_input.text).toFilterState(),
        initialNotShowWatched: _controller.notShowWatchedBangumis,
        initialNotShowAbandoned: _controller.notShowAbandonedBangumis,
      ),
    );
    if (!mounted || result == null) return;
    await _controller.setNotShowWatchedBangumis(result.notShowWatched);
    await _controller.setNotShowAbandonedBangumis(result.notShowAbandoned);
    if (!mounted) return;
    await _applyFilters(result.filterState);
  }

  Future<void> _imageSearch() async {
    _inputFocus.unfocus();
    final result = await context.pushNamed('/search/image');
    if (!mounted || result is! String || result.isEmpty) return;
    await _submit(result);
  }

  void _clearSearch() {
    _inputFocus.unfocus();
    _writeInput('');
    _controller.clearSuggestions();
    setState(() {
      _submittedQuery = null;
      _managingHistory = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _searchField() {
    final colors = Theme.of(context).colorScheme;
    return Observer(builder: (_) {
      // 占位提示词跟随热搜榜第一名，对应参考实现下发的 defaultKeyword。
      final hint = _controller.defaultKeyword.isEmpty
          ? '搜索番剧名称'
          : '试试「${_controller.defaultKeyword}」';
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: _input,
        builder: (context, value, child) => SearchBar(
          controller: _input,
          focusNode: _inputFocus,
          hintText: hint,
          textInputAction: TextInputAction.search,
          constraints: const BoxConstraints(minHeight: 64),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
          leading: IconButton(
            tooltip: '搜索',
            onPressed: () => _submit(_input.text),
            icon: const Icon(Icons.search_rounded),
          ),
          trailing: [
            if (value.text.isNotEmpty || _hasSearched)
              IconButton(
                  tooltip: '清空搜索',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded)),
            IconButton(
              tooltip: '以图搜番',
              onPressed: _imageSearch,
              icon: const Icon(Icons.image_search_rounded),
            ),
          ],
          onChanged: _controller.requestSuggestions,
          onSubmitted: _submit,
        ),
      );
    });
  }

  /// 输入联想面板，只在「已聚焦、有输入、还没进入结果页」时出现。
  Widget _suggestionPanel() {
    if (_hasSearched) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final keyword = value.text.trim();
        if (!_inputFocus.hasFocus || keyword.isEmpty) {
          return const SizedBox.shrink();
        }
        return Observer(
          // 关键：把建议面板圈进 TextFieldTapRegion。
          //
          // 桌面端点 TextField 之外的地方时，Flutter 在**指针按下那一刻**就
          // 会 unfocus（移动端只是收键盘）。而上面那个 `!hasFocus` 判断会
          // 立刻把整个面板从树上摘掉，指针抬起时 InkWell 已经不存在了，
          // onTap 永远不会触发 —— 表现就是「点了没反应，列表还闪一下」。
          //
          // TextFieldTapRegion 告诉输入框「这块区域不算外部」，按下不再失焦，
          // 面板就能活到 onTap 执行完。
          builder: (_) => TextFieldTapRegion(
            child: _SearchSuggestionPanel(
              keyword: keyword,
              items: _controller.suggestions.toList(),
              busy: _controller.isSuggesting,
              onSubmit: _submit,
              onOpen: (item) {
                // 先把页面推出去，再收拾输入框状态。反过来的话，unfocus 会
                // 抢在导航之前把面板拆掉（虽然已经不会丢点击了，但先导航
                // 在语义上也更稳：用户点的是「进详情」，不是「收起键盘」）。
                context.pushNamed('/info/', arguments: item);
                _inputFocus.unfocus();
                _controller.clearSuggestions();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Padding(
        key: _searchHeaderKey,
        padding: EdgeInsets.only(top: _hasSearched ? 8 : 24, bottom: 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchField(),
              _suggestionPanel(),
            ]),
      );

  Widget _discovery() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
          type: MaterialType.transparency,
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.tune_rounded),
            title: const Text('按条件查找'),
            subtitle: const Text('题材、放送时间与评分'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showFilters,
          )),
      const SizedBox(height: 28),
      Observer(builder: (_) {
        final hotItems = _controller.hotSearchItems.toList();
        if (hotItems.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: _HotSearchBoard(items: hotItems, onPick: _submit),
        );
      }),
      Observer(builder: (_) {
        final latest = _controller.latestAired.toList();
        if (latest.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: _BangumiRail(title: '最新上线', items: latest),
        );
      }),
      Observer(builder: (_) {
        final histories = _controller.searchHistories.toList();
        if (histories.isEmpty) return const SizedBox.shrink();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text('最近搜索',
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant))),
                    if (_managingHistory)
                      TextButton(
                          onPressed: () async {
                            await _controller.clearSearchHistory();
                            if (mounted) {
                              setState(() => _managingHistory = false);
                            }
                          },
                          child: const Text('清空')),
                    TextButton(
                        onPressed: () => setState(
                            () => _managingHistory = !_managingHistory),
                        child: Text(_managingHistory ? '完成' : '管理')),
                  ])),
              for (final history in histories.take(10))
                Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      leading: Icon(Icons.history_rounded,
                          color: theme.colorScheme.onSurfaceVariant, size: 22),
                      title: Text(_readableQuery(history.keyword),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: _managingHistory
                          ? IconButton(
                              tooltip: '删除这条搜索记录',
                              onPressed: () =>
                                  _controller.deleteSearchHistory(history),
                              icon: const Icon(Icons.close_rounded, size: 20))
                          : Icon(Icons.north_west_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                      onTap: () => _submit(history.keyword),
                    )),
            ]);
      }),
    ]);
  }

  List<Widget> _resultSlivers(double width) {
    final allItems = _controller.bangumiList.toList();
    final watched = _controller.notShowWatchedBangumis
        ? _controller.loadWatchedBangumiIds()
        : <int>{};
    final abandoned = _controller.notShowAbandonedBangumis
        ? _controller.loadAbandonedBangumiIds()
        : <int>{};
    final items = allItems
        .where((item) =>
            !watched.contains(item.id) && !abandoned.contains(item.id))
        .toList();
    final busy = _controller.isLoading;
    final failed = _controller.isTimeOut;
    final submitted = SearchParser(_submittedQuery!).toFilterState();
    final summary = _filterSummary(submitted);

    return [
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('搜索结果',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600))),
            if (!submitted.isIdSearch)
              _SearchSortMenu(
                  value: submitted.sort,
                  onChanged: (sort) =>
                      _applyFilters(submitted.copyWith(sort: sort))),
            IconButton(
              tooltip: '筛选番剧',
              onPressed: _showFilters,
              icon: Badge(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  isLabelVisible: submitted.hasAdvancedFilters ||
                      _controller.notShowWatchedBangumis ||
                      _controller.notShowAbandonedBangumis,
                  smallSize: 6,
                  child: const Icon(Icons.tune_rounded)),
            ),
          ]),
          Text(
              busy
                  ? '正在搜索…'
                  : '${items.length} 部番剧${items.length < allItems.length ? ' · 隐藏 ${allItems.length - items.length} 部' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ]),
      )),
      if (busy && allItems.isEmpty)
        _SearchSkeletonGrid(width: width)
      else if (_controller.searchError.isNotEmpty)
        SliverToBoxAdapter(
          child: GeneralEmptyState(
            compact: true,
            icon: Icons.wifi_off_rounded,
            title: _controller.searchError,
            actions: [
              StateActionButton.tonal(
                onPressed: () => _controller.searchBangumi(_submittedQuery!,
                    type: 'init'),
                icon: Icons.refresh_rounded,
                text: '重试',
              ),
            ],
          ),
        )
      else if (allItems.isEmpty)
        SliverToBoxAdapter(
          child: _SearchEmptyState(
            keyword: submitted.keyword,
            recommendations: _controller.recommendations.toList(),
            hasFilters: submitted.hasAdvancedFilters,
            onClearFilters: () {
              _applyFilters(SearchFilterState(keyword: submitted.keyword));
            },
          ),
        )
      else if (items.isEmpty)
        SliverToBoxAdapter(
            child: GeneralEmptyState(
          icon: Icons.filter_alt_off_rounded,
          title: '这些番剧被筛选隐藏了',
          actions: [
            StateActionButton.tonal(
              onPressed: () async {
                await _controller.setNotShowWatchedBangumis(false);
                await _controller.setNotShowAbandonedBangumis(false);
              },
              icon: Icons.visibility_outlined,
              text: '显示全部',
            ),
          ],
        ))
      else
        _SearchResultGrid(
          items: items,
          width: width,
          showRating: GStorage.getSetting(SettingsKeys.showRating),
        ),
      if (allItems.isNotEmpty || !failed)
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: busy
                      ? (allItems.isEmpty
                          ? const SizedBox.shrink()
                          : const LoadingIndicator(size: 32))
                      : _controller.hasMoreSearchResults
                          ? TextButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more_rounded),
                              label: const Text('加载更多'))
                          : Text('已经看到全部结果',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                ))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
          backgroundColor: Colors.transparent, title: Text('番剧搜索')),
      body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 700 ? 32.0 : 20.0;
            final width = math.min(_hasSearched ? 1120.0 : 760.0,
                constraints.maxWidth - horizontal * 2);
            final inset = (constraints.maxWidth - width) / 2;
            final pinSearch = _hasSearched &&
                constraints.maxHeight >= 420 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            Widget scrollView(List<Widget> slivers) => CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 24),
                      sliver: SliverMainAxisGroup(slivers: slivers),
                    )
                  ],
                );
            return Column(children: [
              if (pinSearch)
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: _header()),
              Expanded(
                  child: _hasSearched
                      ? Observer(
                          builder: (_) => scrollView([
                                if (!pinSearch)
                                  SliverToBoxAdapter(child: _header()),
                                ..._resultSlivers(width),
                              ]))
                      : scrollView([
                          SliverToBoxAdapter(child: _header()),
                          SliverToBoxAdapter(child: _discovery()),
                        ])),
            ]);
          })),
    );
  }
}
