// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SearchPageController on _SearchPageController, Store {
  late final _$isLoadingAtom = Atom(
    name: '_SearchPageController.isLoading',
    context: context,
  );

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$isTimeOutAtom = Atom(
    name: '_SearchPageController.isTimeOut',
    context: context,
  );

  @override
  bool get isTimeOut {
    _$isTimeOutAtom.reportRead();
    return super.isTimeOut;
  }

  @override
  set isTimeOut(bool value) {
    _$isTimeOutAtom.reportWrite(value, super.isTimeOut, () {
      super.isTimeOut = value;
    });
  }

  late final _$searchErrorAtom = Atom(
    name: '_SearchPageController.searchError',
    context: context,
  );

  @override
  String get searchError {
    _$searchErrorAtom.reportRead();
    return super.searchError;
  }

  @override
  set searchError(String value) {
    _$searchErrorAtom.reportWrite(value, super.searchError, () {
      super.searchError = value;
    });
  }

  late final _$notShowWatchedBangumisAtom = Atom(
    name: '_SearchPageController.notShowWatchedBangumis',
    context: context,
  );

  @override
  bool get notShowWatchedBangumis {
    _$notShowWatchedBangumisAtom.reportRead();
    return super.notShowWatchedBangumis;
  }

  @override
  set notShowWatchedBangumis(bool value) {
    _$notShowWatchedBangumisAtom.reportWrite(
      value,
      super.notShowWatchedBangumis,
      () {
        super.notShowWatchedBangumis = value;
      },
    );
  }

  late final _$notShowAbandonedBangumisAtom = Atom(
    name: '_SearchPageController.notShowAbandonedBangumis',
    context: context,
  );

  @override
  bool get notShowAbandonedBangumis {
    _$notShowAbandonedBangumisAtom.reportRead();
    return super.notShowAbandonedBangumis;
  }

  @override
  set notShowAbandonedBangumis(bool value) {
    _$notShowAbandonedBangumisAtom.reportWrite(
      value,
      super.notShowAbandonedBangumis,
      () {
        super.notShowAbandonedBangumis = value;
      },
    );
  }

  late final _$bangumiListAtom = Atom(
    name: '_SearchPageController.bangumiList',
    context: context,
  );

  @override
  ObservableList<BangumiItem> get bangumiList {
    _$bangumiListAtom.reportRead();
    return super.bangumiList;
  }

  @override
  set bangumiList(ObservableList<BangumiItem> value) {
    _$bangumiListAtom.reportWrite(value, super.bangumiList, () {
      super.bangumiList = value;
    });
  }

  late final _$searchHistoriesAtom = Atom(
    name: '_SearchPageController.searchHistories',
    context: context,
  );

  @override
  ObservableList<SearchHistory> get searchHistories {
    _$searchHistoriesAtom.reportRead();
    return super.searchHistories;
  }

  @override
  set searchHistories(ObservableList<SearchHistory> value) {
    _$searchHistoriesAtom.reportWrite(value, super.searchHistories, () {
      super.searchHistories = value;
    });
  }

  late final _$isImageSearchingAtom = Atom(
    name: '_SearchPageController.isImageSearching',
    context: context,
  );

  @override
  bool get isImageSearching {
    _$isImageSearchingAtom.reportRead();
    return super.isImageSearching;
  }

  @override
  set isImageSearching(bool value) {
    _$isImageSearchingAtom.reportWrite(value, super.isImageSearching, () {
      super.isImageSearching = value;
    });
  }

  late final _$imageSearchErrorAtom = Atom(
    name: '_SearchPageController.imageSearchError',
    context: context,
  );

  @override
  String get imageSearchError {
    _$imageSearchErrorAtom.reportRead();
    return super.imageSearchError;
  }

  @override
  set imageSearchError(String value) {
    _$imageSearchErrorAtom.reportWrite(value, super.imageSearchError, () {
      super.imageSearchError = value;
    });
  }

  late final _$imageSearchResultsAtom = Atom(
    name: '_SearchPageController.imageSearchResults',
    context: context,
  );

  @override
  ObservableList<ResultItem> get imageSearchResults {
    _$imageSearchResultsAtom.reportRead();
    return super.imageSearchResults;
  }

  @override
  set imageSearchResults(ObservableList<ResultItem> value) {
    _$imageSearchResultsAtom.reportWrite(value, super.imageSearchResults, () {
      super.imageSearchResults = value;
    });
  }

  late final _$defaultKeywordAtom = Atom(
    name: '_SearchPageController.defaultKeyword',
    context: context,
  );

  @override
  String get defaultKeyword {
    _$defaultKeywordAtom.reportRead();
    return super.defaultKeyword;
  }

  @override
  set defaultKeyword(String value) {
    _$defaultKeywordAtom.reportWrite(value, super.defaultKeyword, () {
      super.defaultKeyword = value;
    });
  }

  late final _$hotSearchItemsAtom = Atom(
    name: '_SearchPageController.hotSearchItems',
    context: context,
  );

  @override
  ObservableList<HotSearchItem> get hotSearchItems {
    _$hotSearchItemsAtom.reportRead();
    return super.hotSearchItems;
  }

  @override
  set hotSearchItems(ObservableList<HotSearchItem> value) {
    _$hotSearchItemsAtom.reportWrite(value, super.hotSearchItems, () {
      super.hotSearchItems = value;
    });
  }

  late final _$recommendationsAtom = Atom(
    name: '_SearchPageController.recommendations',
    context: context,
  );

  @override
  ObservableList<BangumiItem> get recommendations {
    _$recommendationsAtom.reportRead();
    return super.recommendations;
  }

  @override
  set recommendations(ObservableList<BangumiItem> value) {
    _$recommendationsAtom.reportWrite(value, super.recommendations, () {
      super.recommendations = value;
    });
  }

  late final _$latestAiredAtom = Atom(
    name: '_SearchPageController.latestAired',
    context: context,
  );

  @override
  ObservableList<BangumiItem> get latestAired {
    _$latestAiredAtom.reportRead();
    return super.latestAired;
  }

  @override
  set latestAired(ObservableList<BangumiItem> value) {
    _$latestAiredAtom.reportWrite(value, super.latestAired, () {
      super.latestAired = value;
    });
  }

  late final _$suggestionsAtom = Atom(
    name: '_SearchPageController.suggestions',
    context: context,
  );

  @override
  ObservableList<BangumiItem> get suggestions {
    _$suggestionsAtom.reportRead();
    return super.suggestions;
  }

  @override
  set suggestions(ObservableList<BangumiItem> value) {
    _$suggestionsAtom.reportWrite(value, super.suggestions, () {
      super.suggestions = value;
    });
  }

  late final _$isSuggestingAtom = Atom(
    name: '_SearchPageController.isSuggesting',
    context: context,
  );

  @override
  bool get isSuggesting {
    _$isSuggestingAtom.reportRead();
    return super.isSuggesting;
  }

  @override
  set isSuggesting(bool value) {
    _$isSuggestingAtom.reportWrite(value, super.isSuggesting, () {
      super.isSuggesting = value;
    });
  }

  late final _$isLoadingDiscoveryAtom = Atom(
    name: '_SearchPageController.isLoadingDiscovery',
    context: context,
  );

  @override
  bool get isLoadingDiscovery {
    _$isLoadingDiscoveryAtom.reportRead();
    return super.isLoadingDiscovery;
  }

  @override
  set isLoadingDiscovery(bool value) {
    _$isLoadingDiscoveryAtom.reportWrite(value, super.isLoadingDiscovery, () {
      super.isLoadingDiscovery = value;
    });
  }

  late final _$loadHotRankingAsyncAction = AsyncAction(
    '_SearchPageController.loadHotRanking',
    context: context,
  );

  @override
  Future<void> loadHotRanking({bool force = false}) {
    return _$loadHotRankingAsyncAction.run(
      () => super.loadHotRanking(force: force),
    );
  }

  late final _$loadRecommendationsAsyncAction = AsyncAction(
    '_SearchPageController.loadRecommendations',
    context: context,
  );

  @override
  Future<void> loadRecommendations({bool force = false}) {
    return _$loadRecommendationsAsyncAction.run(
      () => super.loadRecommendations(force: force),
    );
  }

  late final _$updateSuggestionsAsyncAction = AsyncAction(
    '_SearchPageController.updateSuggestions',
    context: context,
  );

  @override
  Future<void> updateSuggestions(String keyword) {
    return _$updateSuggestionsAsyncAction.run(
      () => super.updateSuggestions(keyword),
    );
  }

  late final _$searchBangumiAsyncAction = AsyncAction(
    '_SearchPageController.searchBangumi',
    context: context,
  );

  @override
  Future<void> searchBangumi(String input, {String type = 'add'}) {
    return _$searchBangumiAsyncAction.run(
      () => super.searchBangumi(input, type: type),
    );
  }

  late final _$deleteSearchHistoryAsyncAction = AsyncAction(
    '_SearchPageController.deleteSearchHistory',
    context: context,
  );

  @override
  Future<void> deleteSearchHistory(SearchHistory history) {
    return _$deleteSearchHistoryAsyncAction.run(
      () => super.deleteSearchHistory(history),
    );
  }

  late final _$clearSearchHistoryAsyncAction = AsyncAction(
    '_SearchPageController.clearSearchHistory',
    context: context,
  );

  @override
  Future<void> clearSearchHistory() {
    return _$clearSearchHistoryAsyncAction.run(
      () => super.clearSearchHistory(),
    );
  }

  late final _$searchImageByFileAsyncAction = AsyncAction(
    '_SearchPageController.searchImageByFile',
    context: context,
  );

  @override
  Future<void> searchImageByFile(File imageFile) {
    return _$searchImageByFileAsyncAction.run(
      () => super.searchImageByFile(imageFile),
    );
  }

  late final _$searchImageByUrlAsyncAction = AsyncAction(
    '_SearchPageController.searchImageByUrl',
    context: context,
  );

  @override
  Future<void> searchImageByUrl(String imageUrl) {
    return _$searchImageByUrlAsyncAction.run(
      () => super.searchImageByUrl(imageUrl),
    );
  }

  late final _$setNotShowWatchedBangumisAsyncAction = AsyncAction(
    '_SearchPageController.setNotShowWatchedBangumis',
    context: context,
  );

  @override
  Future<void> setNotShowWatchedBangumis(bool value) {
    return _$setNotShowWatchedBangumisAsyncAction.run(
      () => super.setNotShowWatchedBangumis(value),
    );
  }

  late final _$setNotShowAbandonedBangumisAsyncAction = AsyncAction(
    '_SearchPageController.setNotShowAbandonedBangumis',
    context: context,
  );

  @override
  Future<void> setNotShowAbandonedBangumis(bool value) {
    return _$setNotShowAbandonedBangumisAsyncAction.run(
      () => super.setNotShowAbandonedBangumis(value),
    );
  }

  late final _$_SearchPageControllerActionController = ActionController(
    name: '_SearchPageController',
    context: context,
  );

  @override
  void loadSearchHistories() {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
      name: '_SearchPageController.loadSearchHistories',
    );
    try {
      return super.loadSearchHistories();
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void requestSuggestions(String keyword) {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
      name: '_SearchPageController.requestSuggestions',
    );
    try {
      return super.requestSuggestions(keyword);
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearSuggestions() {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
      name: '_SearchPageController.clearSuggestions',
    );
    try {
      return super.clearSuggestions();
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearImageSearchState() {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
      name: '_SearchPageController.clearImageSearchState',
    );
    try {
      return super.clearImageSearchState();
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isLoading: ${isLoading},
isTimeOut: ${isTimeOut},
searchError: ${searchError},
notShowWatchedBangumis: ${notShowWatchedBangumis},
notShowAbandonedBangumis: ${notShowAbandonedBangumis},
bangumiList: ${bangumiList},
searchHistories: ${searchHistories},
isImageSearching: ${isImageSearching},
imageSearchError: ${imageSearchError},
imageSearchResults: ${imageSearchResults},
defaultKeyword: ${defaultKeyword},
hotSearchItems: ${hotSearchItems},
recommendations: ${recommendations},
latestAired: ${latestAired},
suggestions: ${suggestions},
isSuggesting: ${isSuggesting},
isLoadingDiscovery: ${isLoadingDiscovery}
    ''';
  }
}
