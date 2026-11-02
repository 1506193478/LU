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
import 'package:XL/modules/download/download_module.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/modules/search/search_config.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_service.dart';
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

  // ---------------------------------------------------------- 聚合搜索
  // 搜索原来只搜插件源（番剧），Emby 库里的和已经下载的在搜索结果里完全
  // 不存在 —— 一部番明明下过了，搜出来还是让你再挑一遍源。
  final List<EmbyItem> _embyHits = <EmbyItem>[];
  final List<DownloadRecord> _downloadHits = <DownloadRecord>[];
  int _othersToken = 0;

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
    // 番剧源和「其他来源」并行发：Emby / 本地库都是本地或局域网请求，
    // 不该让它们拖慢主列表。
    _loadOtherSources(SearchParser(query).toFilterState().keyword);
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

  Future<void> _openEmbyItem(EmbyItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EmbyDetailPage(item: item)),
    );
  }

  void _loadMore() {
    final query = _submittedQuery;
    if (query != null) _controller.searchBangumi(query);
  }

  /// 并行去 Emby 和本地已下载里找同一个关键词。
  ///
  /// 两路都做成「失败就当没有」，任何一路挂掉都不能影响搜索结果本身 ——
  /// 这个功能是附加信息，不是主路径。
  Future<void> _loadOtherSources(String keyword) async {
    final String q = keyword.trim().toLowerCase();
    final int token = ++_othersToken;
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _embyHits.clear();
        _downloadHits.clear();
      });
      return;
    }

    // 本地已下载：纯内存过滤，不涉及网络。
    final List<DownloadRecord> local = <DownloadRecord>[];
    try {
      final DownloadController downloads = inject<DownloadController>();
      if (downloads.records.isEmpty) {
        downloads.refreshRecords();
      }
      for (final DownloadRecord record in downloads.records) {
        if (record.bangumiName.toLowerCase().contains(q)) {
          local.add(record);
        }
      }
    } catch (_) {
      // 下载控制器没初始化也不影响搜索。
    }

    // Emby 只搜当前服务器：跨服搜一遍要等好几秒，搜索结果里挂个一直转圈
    // 的区块比没有更难受。
    List<EmbyItem> emby = const <EmbyItem>[];
    try {
      final EmbyService service = EmbyService.instance;
      final EmbyServer? active = service.activeServer;
      if (active != null) {
        emby = await service.clientFor(active).search(
              userId: active.userId,
              keyword: keyword.trim(),
              limit: 20,
              includeItemTypes: 'Movie,Series,BoxSet,Video',
            );
      }
    } catch (_) {
      emby = const <EmbyItem>[];
    }

    if (!mounted || token != _othersToken) return;
    setState(() {
      _embyHits
        ..clear()
        ..addAll(emby.where((EmbyItem item) => !item.isEpisode).take(12));
      _downloadHits
        ..clear()
        ..addAll(local.take(6));
    });
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
      _embyHits.clear();
      _downloadHits.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _searchField() {
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
          constraints: const BoxConstraints(minHeight: 56),
          elevation: const WidgetStatePropertyAll(0),
          // Pv 的搜索条：#EFEFF3 底、11 圆角、占位字 #8A8A8E。
          backgroundColor: WidgetStatePropertyAll(PvColors.searchFill(context)),
          hintStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 15, color: PvColors.searchHint(context)),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 15, color: PvColors.ink(context)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
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
      // 「其他来源」放在番剧源上面：已经下过的、Emby 里有的，往往比再去
      // 挑一个插件源更快。没有命中就整块不出现。
      if (_embyHits.isNotEmpty)
        SliverToBoxAdapter(
          child: _EmbyHitsSection(
            items: _embyHits,
            onTap: _openEmbyItem,
          ),
        ),
      if (_downloadHits.isNotEmpty)
        SliverToBoxAdapter(
          child: _DownloadHitsSection(
            records: _downloadHits,
            onTap: (_) => context.pushNamed('/settings/download/'),
          ),
        ),
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('番剧源',
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

/// 搜索结果里的「Emby 库」横向条。
class _EmbyHitsSection extends StatelessWidget {
  const _EmbyHitsSection({required this.items, required this.onTap});

  final List<EmbyItem> items;
  final ValueChanged<EmbyItem> onTap;

  @override
  Widget build(BuildContext context) {
    final EmbyServer? server = EmbyService.instance.activeServer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PvSectionHead('Emby 库', count: '${items.length}', topPadding: 4),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int i) {
              final EmbyItem item = items[i];
              final String url = server == null
                  ? ''
                  : embyImageUrl(
                      serverUrl: server.url,
                      itemId: item.coverItemId,
                      accessToken: server.accessToken,
                      maxHeight: 400,
                      tag: item.coverTag,
                    );
              return GestureDetector(
                onTap: () => onTap(item),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 88,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 88,
                          height: 116,
                          child: url.isEmpty
                              ? Container(
                                  color: PvColors.searchFill(context),
                                  child: Icon(Icons.movie_outlined,
                                      size: 22, color: PvColors.ink3(context)),
                                )
                              : EmbyImage(
                                  url: url,
                                  headers: embyAuthHeaders(server),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: PvColors.ink(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 搜索结果里的「已下载」区块。
class _DownloadHitsSection extends StatelessWidget {
  const _DownloadHitsSection({required this.records, required this.onTap});

  final List<DownloadRecord> records;
  final ValueChanged<DownloadRecord> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PvSectionHead('已下载', count: '${records.length}', topPadding: 6),
        PvGroup(
          children: [
            for (var i = 0; i < records.length; i++)
              _DownloadHitRow(
                record: records[i],
                showDivider: i > 0,
                onTap: () => onTap(records[i]),
              ),
          ],
        ),
      ],
    );
  }
}

class _DownloadHitRow extends StatelessWidget {
  const _DownloadHitRow({
    required this.record,
    required this.onTap,
    this.showDivider = true,
  });

  final DownloadRecord record;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final int done = record.episodes.values
        .where((DownloadEpisode e) => e.status == DownloadStatus.completed)
        .length;
    final String sub = <String>[
      if (done > 0) '已下 $done 集',
      if (record.pluginName.isNotEmpty) record.pluginName,
    ].join(' · ');

    final Widget row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 34,
                height: 46,
                child: record.bangumiCover.isEmpty
                    ? Container(
                        color: PvColors.searchFill(context),
                        child: Icon(Icons.download_done_rounded,
                            size: 16, color: PvColors.ink3(context)),
                      )
                    : NetworkImgLayer(
                        src: record.bangumiCover,
                        width: 34,
                        height: 46,
                      ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.bangumiName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PvText.rowTitle(context),
                  ),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PvText.rowSub(context).copyWith(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: PvColors.chev(context)),
          ],
        ),
      ),
    );

    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 60),
          color: PvColors.hair(context),
        ),
        row,
      ],
    );
  }
}
