import 'dart:async';
import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/collect/collect_type.dart';
import 'package:XL/modules/search/image_search_module.dart';
import 'package:XL/modules/search/search_config.dart';
import 'package:XL/modules/search/search_history_module.dart';
import 'package:XL/repositories/collect_repository.dart';
import 'package:XL/repositories/search_history_repository.dart';
import 'package:XL/request/apis/bangumi_api.dart';
import 'package:XL/request/apis/trace_api.dart';
import 'package:XL/utils/search_parser.dart';
import 'package:XL/utils/title_match.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  static const int _searchPageSize = 20;
  static const int _maxPagesPerSearch = 3;

  /// 单次搜索请求的总超时。
  ///
  /// 网络层是 15s 连接 + 30s 接收，镜像模式下还会先镜像后直连重试一次，
  /// 最坏能拖到一分多钟。超过 15s 还没有结果，用户已经认定它卡死了，
  /// 不如直接报超时让人去换加速方式。
  static const Duration _searchTimeout = Duration(seconds: 15);
  static const String _searchTimeoutMessage = '搜索超时，请检查网络或 Bangumi 加速设置';

  _SearchPageController(
    this._collectRepository,
    this._searchHistoryRepository,
  );

  final ICollectRepository _collectRepository;
  final ISearchHistoryRepository _searchHistoryRepository;

  /// 输入联想的防抖间隔。参考客户端把联想请求发到自建服务的
  /// `searchSuggest` 接口，Bangumi 只能用完整搜索接口顶替，所以必须防抖，
  /// 否则每敲一个字就打一次 `/v0/search/subjects`。
  static const Duration _suggestionDebounce = Duration(milliseconds: 280);
  static const int _suggestionLimit = 6;

  int _searchOffset = 0;
  int _searchGeneration = 0;
  int _suggestionGeneration = 0;
  Timer? _suggestionTimer;
  Map<int, int> _previousHotRanks = const {};
  bool _hotRankingLoaded = false;
  bool _recommendationsLoaded = false;

  bool hasMoreSearchResults = true;

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  /// 搜索请求整体失败时的提示。
  ///
  /// 之前请求失败和「确实没有结果」都只表现为一片空白，无法区分。
  /// 有了这个字段，网络或镜像签名出问题时界面能直接说明。
  @observable
  String searchError = '';

  @observable
  bool notShowWatchedBangumis = false;

  @observable
  bool notShowAbandonedBangumis = false;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  @observable
  bool isImageSearching = false;

  @observable
  String imageSearchError = '';

  @observable
  ObservableList<ResultItem> imageSearchResults = ObservableList.of([]);

  /// 搜索框占位提示词，对应参考实现的 `SearchConfigApiData.defaultKeyword`。
  @observable
  String defaultKeyword = '';

  /// 热搜榜，对应 `HotSearchDataApi.items`。
  @observable
  ObservableList<HotSearchItem> hotSearchItems = ObservableList.of([]);

  /// 空结果页与发现页的「为你推荐」。
  @observable
  ObservableList<BangumiItem> recommendations = ObservableList.of([]);

  /// 发现页与空结果页的「最新上线」。
  @observable
  ObservableList<BangumiItem> latestAired = ObservableList.of([]);

  /// 输入联想结果。
  @observable
  ObservableList<BangumiItem> suggestions = ObservableList.of([]);

  @observable
  bool isSuggesting = false;

  /// 热搜榜 / 推荐位是否正在加载。
  @observable
  bool isLoadingDiscovery = false;

  bool get hasSuggestions => suggestions.isNotEmpty;

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  /// 拉取热搜榜。
  ///
  /// 对应参考实现的 `getSearchConfig()`：一次拿到默认搜索词与热搜榜。
  /// 榜单结果会被缓存，重复进入搜索页不会反复打接口；`force` 用于下拉刷新。
  @action
  Future<void> loadHotRanking({bool force = false}) async {
    if (_hotRankingLoaded && !force) return;
    _hotRankingLoaded = true;
    isLoadingDiscovery = true;
    final ranking = await BangumiApi.getBangumiHotRanking();
    final items = buildHotSearchItems(
      ranking,
      previousRanks: _previousHotRanks.isEmpty ? null : _previousHotRanks,
    );
    _previousHotRanks = hotSearchRankSnapshot(items);
    hotSearchItems.clear();
    hotSearchItems.addAll(items);
    defaultKeyword = items.isEmpty ? '' : items.first.title;
    isLoadingDiscovery = false;
  }

  /// 拉取「为你推荐」与「最新上线」。
  @action
  Future<void> loadRecommendations({bool force = false}) async {
    if (_recommendationsLoaded && !force) return;
    _recommendationsLoaded = true;
    isLoadingDiscovery = true;
    // 热搜榜已经拉过一次榜单时直接复用，避免开屏连打两次同一个接口。
    if (hotSearchItems.isNotEmpty && !force) {
      recommendations.clear();
      recommendations.addAll(hotSearchItems.map((item) => item.bangumiItem));
    } else {
      recommendations.clear();
      recommendations.addAll(await BangumiApi.getBangumiHotRanking(limit: 12));
    }
    latestAired.clear();
    latestAired.addAll(await BangumiApi.getBangumiLatestAired(limit: 12));
    isLoadingDiscovery = false;
  }

  /// 输入联想（防抖）。
  ///
  /// 参考实现的联想是独立的轻量接口，Bangumi 侧只能用完整搜索接口顶替，
  /// 因此在 [requestSuggestions] 里做防抖，只保留最后一次输入的结果。
  @action
  void requestSuggestions(String keyword) {
    _suggestionTimer?.cancel();
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      clearSuggestions();
      return;
    }
    isSuggesting = true;
    _suggestionTimer =
        Timer(_suggestionDebounce, () => updateSuggestions(trimmed));
  }

  @action
  void clearSuggestions() {
    _suggestionTimer?.cancel();
    _suggestionGeneration++;
    isSuggesting = false;
    suggestions.clear();
  }

  @action
  Future<void> updateSuggestions(String keyword) async {
    final generation = ++_suggestionGeneration;
    isSuggesting = true;
    final items = await BangumiApi.getBangumiSearchSuggestions(keyword);
    // 输入已经变了，丢弃这次迟到的响应。
    if (generation != _suggestionGeneration) return;
    suggestions.clear();
    suggestions
        .addAll(_rankByRelevance(items, keyword).take(_suggestionLimit));
    isSuggesting = false;
  }

  @action
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    if (type == 'add' && (isLoading || !hasMoreSearchResults)) return;
    final generation = type == 'add' ? _searchGeneration : ++_searchGeneration;
    isLoading = true;
    isTimeOut = false;
    var timedOut = false;
    try {
      if (type != 'add') {
        bangumiList.clear();
        searchError = '';
        _searchOffset = 0;
        hasMoreSearchResults = true;
        if (!_collectRepository.getPrivateMode() && input.trim().isNotEmpty) {
          await _searchHistoryRepository.deleteDuplicates(input);
          if (_searchHistoryRepository.isHistoryFull(10)) {
            await _searchHistoryRepository.deleteOldest();
          }
          await _searchHistoryRepository.saveHistory(input);
          loadSearchHistories();
        }
      }
      if (generation != _searchGeneration) return;
      final filterState = SearchParser(input).toFilterState();
      final id = int.tryParse(filterState.id);
      if (id != null) {
        BangumiItem? item;
        try {
          item = await BangumiApi.getBangumiInfoByID(id).timeout(
                _searchTimeout,
              );
        } on TimeoutException {
          timedOut = true;
        }
        if (generation != _searchGeneration) return;
        if (item != null) {
          bangumiList.add(item);
        }
        hasMoreSearchResults = false;
        isTimeOut = bangumiList.isEmpty;
        if (timedOut) {
          searchError = _searchTimeoutMessage;
        }
        return;
      }
      var pagesFetched = 0;
      do {
        BangumiSearchPage? page;
        try {
          // 网络层本身只有 15s 连接 / 30s 接收超时，而且镜像模式下会先打
          // 镜像、失败再直连重试一次，最坏要等一分多钟。用户看到的「正在
          // 搜索番剧」一直转就是这么来的，这里再套一层总超时兜住。
          page = await BangumiApi.bangumiSearch(
            filterState.keyword,
            tags: filterState.tags,
            limit: _searchPageSize,
            offset: _searchOffset,
            sort: filterState.sort,
            dateRange: filterState.effectiveDateRange,
            rankRange: filterState.rankRange,
            scoreRange: filterState.scoreRange,
            weekdays: filterState.weekdays,
          ).timeout(_searchTimeout);
        } on TimeoutException {
          timedOut = true;
          break;
        }
        // Discard stale responses before mutating the current search.
        if (generation != _searchGeneration) return;
        if (page == null) {
          break;
        }
        pagesFetched++;
        _searchOffset += page.rawCount;
        hasMoreSearchResults = page.rawCount == _searchPageSize;
        final existingIds = bangumiList.map((item) => item.id).toSet();
        final newItems = _rankByRelevance(
          page.items.where((item) => existingIds.add(item.id)).toList(),
          filterState.keyword,
        );
        if (newItems.isNotEmpty) {
          bangumiList.addAll(newItems);
          break;
        }
      } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
      isTimeOut =
          bangumiList.isEmpty && (pagesFetched == 0 || !hasMoreSearchResults);
      // 一页都没取到说明请求本身失败，不是「没有匹配的番剧」。
      if (bangumiList.isEmpty && pagesFetched == 0) {
        searchError =
            timedOut ? _searchTimeoutMessage : '搜索失败，请检查网络或 Bangumi 加速设置';
      }
    } finally {
      // 任何一条提前 return 或异常都不能把 loading 留在 true，否则界面会
      // 一直停在「正在搜索番剧」，看起来就像点不动。
      if (generation == _searchGeneration) {
        isLoading = false;
      }
    }
  }

  /// 把标题命中度高的条目提到前面。
  ///
  /// Bangumi 的 `/v0/search/subjects` 默认按热度排，搜「孤独摇滚」时正片
  /// 可能排在一堆衍生条目后面。这里按标题相似度做一次稳定重排，只在确实
  /// 存在明显更强的匹配（≥60 分）时才动顺序，否则保留服务端热度序。
  List<BangumiItem> _rankByRelevance(List<BangumiItem> items, String keyword) {
    if (items.length < 2 || keyword.trim().isEmpty) {
      return items;
    }
    final scores = <int>[];
    var maxScore = 0;
    for (final item in items) {
      final score = bestTitleScore(keyword, [
        item.nameCn,
        item.name,
        ...item.alias,
      ]);
      scores.add(score);
      if (score > maxScore) {
        maxScore = score;
      }
    }
    if (maxScore < 60) {
      return items;
    }
    final order = List<int>.generate(items.length, (index) => index);
    order.sort((a, b) {
      final byScore = scores[b].compareTo(scores[a]);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
    return [for (final index in order) items[index]];
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  void clearImageSearchState() {
    isImageSearching = false;
    imageSearchError = '';
    imageSearchResults.clear();
  }

  @action
  Future<void> searchImageByFile(File imageFile) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageFile(imageFile);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> searchImageByUrl(String imageUrl) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageUrl(imageUrl);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请检查图片地址或稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }
}
