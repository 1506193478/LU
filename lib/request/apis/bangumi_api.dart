import 'package:XL/services/logging/logger.dart';
import 'package:XL/request/config/api_endpoints.dart';
import 'package:XL/request/clients/bangumi_client.dart';
import 'package:XL/request/core/network_exception.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/bangumi/bangumi_relation.dart';
import 'package:XL/modules/comments/comment_response.dart';
import 'package:XL/modules/characters/characters_response.dart';
import 'package:XL/modules/bangumi/episode_item.dart';
import 'package:XL/modules/character/character_full_item.dart';
import 'package:XL/modules/staff/staff_response.dart';
import 'package:XL/modules/bangumi/bangumi_collection.dart';
import 'package:XL/modules/collect/collect_type.dart';
import 'package:XL/modules/collect/collect_type_mapper.dart';
import 'package:XL/modules/bangumi/bangumi_collection_type.dart';
import 'package:XL/modules/comments/comment_item.dart';
import 'package:XL/services/network/bangumi_acceleration.dart';
import 'package:XL/utils/search_parser.dart';
import 'package:XL/utils/async_rate_limiter.dart';

class BangumiSearchPage {
  const BangumiSearchPage({
    required this.items,
    required this.rawCount,
  });

  final List<BangumiItem> items;
  final int rawCount;
}

class BangumiApi {
  static final BangumiClient _client = BangumiClient.instance;
  static final AsyncRateLimiter _writeRateLimiter =
      AsyncRateLimiter(const Duration(milliseconds: 250));

  static Future<List<List<BangumiItem>>> getCalendar() async {
    List<List<BangumiItem>> bangumiCalendar = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiCalendar,
      );
      for (int i = 1; i <= 7; i++) {
        List<BangumiItem> bangumiList = [];
        final jsonList = jsonData['$i'];
        for (dynamic jsonItem in jsonList) {
          try {
            BangumiItem bangumiItem = BangumiItem.fromJson(jsonItem['subject']);
            bangumiList.add(bangumiItem);
          } catch (_) {}
        }
        bangumiCalendar.add(bangumiList);
      }
    } catch (e) {
      KazumiLogger().e('Resolve calendar failed', error: e);
    }
    return bangumiCalendar;
  }

  // Official fallback for season switching. Mirror mode uses the cached
  // /kazumi/v1/calendar/season endpoint instead of Bangumi search.
  static Future<List<List<BangumiItem>>> getCalendarBySearch(
      List<String> dateRange, int limit, int offset) async {
    List<BangumiItem> bangumiList = [];
    List<List<BangumiItem>> bangumiCalendar = [];
    var params = <String, dynamic>{
      "keyword": "",
      "sort": "rank",
      "filter": {
        "type": [2],
        "tag": ["日本"],
        "air_date": [">=${dateRange[0]}", "<${dateRange[1]}"],
        "rank": [">0", "<=99999"],
        "nsfw": true
      }
    };
    try {
      final url = ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
          [limit, offset]);
      final jsonData = await _client.post(
        url,
        data: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger().e('Resolve bangumi list failed', error: e);
    }
    try {
      for (int weekday = 1; weekday <= 7; weekday++) {
        List<BangumiItem> bangumiDayList = [];
        for (BangumiItem bangumiItem in bangumiList) {
          if (bangumiItem.airWeekday == weekday) {
            bangumiDayList.add(bangumiItem);
          }
        }
        bangumiCalendar.add(bangumiDayList);
      }
    } catch (e) {
      KazumiLogger()
          .e('Network: fetch bangumi item to calendar failed', error: e);
    }
    return bangumiCalendar;
  }

  static String buildBangumiMirrorSeasonCalendarPath(List<String> dateRange) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorSeasonCalendar,
      queryParameters: {
        'start': dateRange[0],
        'end': dateRange[1],
      },
    ).toString();
  }

  static Future<List<List<BangumiItem>>> getBangumiMirrorSeasonCalendar(
      List<String> dateRange) async {
    List<List<BangumiItem>> bangumiCalendar = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiMirrorDomain +
            buildBangumiMirrorSeasonCalendarPath(dateRange),
      );
      for (int i = 1; i <= 7; i++) {
        List<BangumiItem> bangumiList = [];
        final jsonList = jsonData['$i'] ?? [];
        for (dynamic jsonItem in jsonList) {
          try {
            final subject =
                jsonItem is Map<String, dynamic> ? jsonItem['subject'] : null;
            if (subject is Map<String, dynamic>) {
              bangumiList.add(BangumiItem.fromJson(subject));
            }
          } catch (_) {}
        }
        bangumiCalendar.add(bangumiList);
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi mirror season calendar failed',
          error: e);
    }
    return bangumiCalendar;
  }

  static Future<List<BangumiItem>> getBangumiList(
      {int rank = 2, String tag = ''}) async {
    List<BangumiItem> bangumiList = [];
    late Map<String, dynamic> params;
    if (tag == '') {
      params = <String, dynamic>{
        'keyword': '',
        'sort': 'rank',
        "filter": {
          "type": [2],
          "tag": ["日本"],
          "rank": [">$rank", "<=1050"],
          "nsfw": false
        },
      };
    } else {
      params = <String, dynamic>{
        'keyword': '',
        'sort': 'rank',
        "filter": {
          "type": [2],
          "tag": [tag],
          "rank": [">$rank", "<=99999"],
          "nsfw": false
        },
      };
    }
    try {
      final jsonData = await _client.post(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
            [100, 0]),
        data: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi list failed', error: e);
    }
    return bangumiList;
  }

  static Future<List<BangumiItem>> getBangumiTrendsList(
      {int type = 2, int limit = 24, int offset = 0}) async {
    List<BangumiItem> bangumiList = [];
    var params = <String, dynamic>{
      'type': type,
      'limit': limit,
      'offset': offset,
    };
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPINextDomain + ApiEndpoints.bangumiTrendsNext,
        queryParameters: params,
      );
      final jsonList = jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem['subject']));
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi trends list failed', error: e);
    }
    return bangumiList;
  }

  static String buildBangumiMirrorPopularPath({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorPopularSubjects,
      queryParameters: {
        if (tag.isNotEmpty) 'tag': tag,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    ).toString();
  }

  static Future<List<BangumiItem>> getBangumiMirrorPopularSubjects({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) async {
    List<BangumiItem> bangumiList = [];
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiMirrorDomain +
            buildBangumiMirrorPopularPath(
              tag: tag,
              limit: limit,
              offset: offset,
            ),
      );
      final jsonList = jsonData is List ? jsonData : jsonData['data'];
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          bangumiList.add(BangumiItem.fromJson(jsonItem));
        }
      }
    } catch (e) {
      KazumiLogger()
          .e('Network: resolve bangumi mirror popular list failed', error: e);
    }
    return bangumiList;
  }

  /// 热搜榜数据源。
  ///
  /// 参考客户端的热搜榜由自建服务端 `/api/v1/app/client/video/searchConfig`
  /// 一次下发，带真实播放量与名次变化；Bangumi 侧没有等价接口，这里用
  /// 「趋势接口 → Kazumi 镜像榜单 → 排名搜索」三级回退拼出同样形状的数据，
  /// 任一级失败都不会让搜索页开天窗。
  static Future<List<BangumiItem>> getBangumiHotRanking(
      {int limit = 12}) async {
    final trends = await getBangumiTrendsList(limit: limit);
    if (trends.isNotEmpty) return trends;
    final popular = await getBangumiMirrorPopularSubjects(limit: limit);
    if (popular.isNotEmpty) return popular;
    return getBangumiList(rank: 0);
  }

  /// 最新上线（本季新番）。
  ///
  /// 对应参考客户端排序维度里的「最新上线」。Bangumi 搜索的 `sort=date`
  /// 不在官方枚举里，改用更可靠的每日放送接口，按当前星期取当天与临近几天。
  static Future<List<BangumiItem>> getBangumiLatestAired({int limit = 12}) async {
    final calendar = await getCalendar();
    if (calendar.isEmpty) return <BangumiItem>[];
    final today = DateTime.now().weekday;
    final ordered = <BangumiItem>[];
    final seen = <int>{};
    for (var offset = 0; offset < 7 && ordered.length < limit; offset++) {
      final day = calendar[(today - 1 + offset) % 7];
      for (final item in day) {
        if (ordered.length >= limit) break;
        if (seen.add(item.id)) ordered.add(item);
      }
    }
    return ordered;
  }

  /// 输入联想。
  ///
  /// 参考客户端有专门的 `/api/v1/app/client/video/searchSuggest` 接口，
  /// Bangumi 只有通用搜索，这里用小分页 + `sort=match` 做近似：
  /// 只取第一页最相关的少数条目，避免在输入过程中打爆搜索接口。
  static Future<List<BangumiItem>> getBangumiSearchSuggestions(
    String keyword, {
    int limit = 8,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return <BangumiItem>[];
    final page = await bangumiSearch(
      trimmed,
      limit: limit,
      offset: 0,
      sort: 'match',
    );
    return page?.items ?? <BangumiItem>[];
  }

  static List<String> _buildNumberFilter<T extends num>(T? min, T? max) {
    return [
      if (min != null) '>=$min',
      if (max != null) '<=$max',
    ];
  }

  static Map<String, dynamic> buildBangumiSearchParams(
    String keyword, {
    List<String> tags = const [],
    String sort = 'heat',
    SearchDateRange? dateRange,
    SearchIntRange? rankRange,
    SearchDoubleRange? scoreRange,
    List<int> weekdays = const [],
  }) {
    final rankFilter = rankRange?.isValid == true
        ? _buildNumberFilter<int>(rankRange!.min, rankRange.max)
        : (sort == 'rank')
            ? [">0", "<=99999"]
            : [">=0", "<=99999"];

    final filter = <String, dynamic>{
      "type": [2],
      "tag": tags,
      "rank": rankFilter,
      "nsfw": false
    };

    if (dateRange?.isValid == true) {
      filter["air_date"] = [">=${dateRange!.start}", "<${dateRange.end}"];
    }
    if (scoreRange?.isValid == true) {
      filter["rating"] =
          _buildNumberFilter<double>(scoreRange!.min, scoreRange.max);
    }
    if (weekdays.isNotEmpty) {
      filter["air_weekday"] = weekdays.toSet().toList()..sort();
    }

    return <String, dynamic>{
      'keyword': keyword,
      'sort': sort,
      "filter": filter,
    };
  }

  static BangumiSearchPage _parseSearchPage(dynamic jsonData) {
    List<BangumiItem> bangumiList = [];
    final jsonList = jsonData['data'] ?? const [];
    for (dynamic jsonItem in jsonList) {
      if (jsonItem is Map<String, dynamic>) {
        try {
          BangumiItem bangumiItem = BangumiItem.fromJson(jsonItem);
          if (bangumiItem.nameCn != '') {
            bangumiList.add(bangumiItem);
          }
        } catch (e) {
          KazumiLogger()
              .e('Network: resolve search results failed', error: e);
        }
      }
    }
    return BangumiSearchPage(
      items: bangumiList,
      rawCount: jsonList.length,
    );
  }

  static Future<BangumiSearchPage?> bangumiSearch(String keyword,
      {List<String> tags = const [],
      int limit = 20,
      int offset = 0,
      String sort = 'heat',
      SearchDateRange? dateRange,
      SearchIntRange? rankRange,
      SearchDoubleRange? scoreRange,
      List<int> weekdays = const []}) async {
    final params = buildBangumiSearchParams(
      keyword,
      tags: tags,
      sort: sort,
      dateRange: dateRange,
      rankRange: rankRange,
      scoreRange: scoreRange,
      weekdays: weekdays,
    );
    final url = ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRankSearch,
        [limit, offset]);

    // 镜像模式下受保护接口要签名，签名被拒或镜像不可用会让搜索一直返回空。
    // 这里先按当前加速方式请求，失败后退回直连再试一次；本来就是直连时
    // 只请求一次。
    final attempts = BangumiAcceleration.current == BangumiAcceleration.direct
        ? const [true]
        : const [false, true];
    for (var index = 0; index < attempts.length; index++) {
      final forceDirect = attempts[index];
      try {
        final jsonData = await _client.post(
          url,
          data: params,
          // 直连时带上用户 token，Bangumi 对未登录请求的限流更紧。
          requiresAuth: forceDirect,
          forceDirect: forceDirect,
        );
        return _parseSearchPage(jsonData);
      } catch (e) {
        KazumiLogger().e(
            'Network: unknown search problem (attempt ${index + 1}'
            '/${attempts.length}, forceDirect=$forceDirect)',
            error: e);
      }
    }
    return null;
  }

  static Future<BangumiItem?> getBangumiInfoByID(int id) async {
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPINextDomain +
                ApiEndpoints.bangumiInfoByIDNext,
            [id]),
      );
      return BangumiItem.fromJson(jsonData);
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi item failed', error: e);
      return null;
    }
  }

  static Future<List<BangumiRelation>> getBangumiRelationsByID(int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
        ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiRelationsByID,
        [id],
      ),
    );
    if (jsonData is! List) {
      throw const FormatException('Bangumi relations response must be a list');
    }

    final relations = <BangumiRelation>[];
    for (final jsonItem in jsonData) {
      try {
        if (jsonItem is! Map) {
          throw const FormatException('Bangumi relation must be an object');
        }
        relations.add(
          BangumiRelation.fromJson(Map<String, dynamic>.from(jsonItem)),
        );
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'BangumiApi: skipped malformed relation item',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    return relations;
  }

  static Future<EpisodeInfo> getBangumiEpisodeByID(int id, int episode) async {
    EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();
    var params = <String, dynamic>{
      'subject_id': id,
      'offset': episode - 1,
      'limit': 1
    };
    try {
      final jsonData = await _client.get(
        ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiEpisodeByID,
        queryParameters: params,
      );
      episodeInfo = EpisodeInfo.fromJson(jsonData['data'][0]);
    } catch (e) {
      KazumiLogger().e('Network: resolve bangumi episode failed', error: e);
    }
    return episodeInfo;
  }

  static Future<List<EpisodeInfo>> getBangumiEpisodesByID(int id) async {
    final List<EpisodeInfo> episodeList = [];
    const int limit = 100;
    int offset = 0;
    int? total;
    try {
      do {
        final params = <String, dynamic>{
          'subject_id': id,
          'offset': offset,
          'limit': limit,
        };
        final jsonData = await _client.get(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiEpisodeByID,
          queryParameters: params,
        );
        total ??= jsonData['total'] as int?;
        final data = jsonData['data'] as List<dynamic>? ?? [];
        if (data.isEmpty) {
          break;
        }
        episodeList.addAll(data
            .whereType<Map<String, dynamic>>()
            .map((jsonItem) => EpisodeInfo.fromJson(jsonItem)));
        offset += data.length;
      } while (total == null || offset < total);
    } catch (e) {
      KazumiLogger()
          .e('Network: resolve bangumi episode list failed', error: e);
    }
    return episodeList;
  }

  static Future<CommentResponse> getBangumiCommentsByID(int id,
      {int offset = 0}) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPINextDomain +
              ApiEndpoints.bangumiCommentsByIDNext,
          [id, 20, offset]),
    );
    return CommentResponse.fromJson(jsonData);
  }

  static Future<EpisodeCommentResponse> getBangumiCommentsByEpisodeID(
      int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPINextDomain +
              ApiEndpoints.bangumiEpisodeCommentsByIDNext,
          [id]),
    );
    return EpisodeCommentResponse.fromJson(jsonData);
  }

  static Future<CharacterCommentResponse> getCharacterCommentsByCharacterID(
      int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPINextDomain +
              ApiEndpoints.bangumiCharacterCommentsByIDNext,
          [id]),
    );
    return CharacterCommentResponse.fromJson(jsonData);
  }

  static Future<StaffResponse> getBangumiStaffByID(int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiStaffByID, [id]),
    );
    return StaffResponse.fromJson(jsonData);
  }

  static Future<CharactersResponse> getCharatersByBangumiID(int id) async {
    final jsonData = await _client.get(
      ApiEndpoints.formatUrl(
          ApiEndpoints.bangumiAPIDomain + ApiEndpoints.bangumiCharacterByID,
          [id]),
    );
    return CharactersResponse.fromJson(jsonData);
  }

  static Future<CharacterFullItem> getCharacterByCharacterID(int id) async {
    CharacterFullItem characterFullItem = CharacterFullItem.fromTemplate();
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAPINextDomain +
                ApiEndpoints.bangumiCharacterInfoByCharacterIDNext,
            [id]),
      );
      characterFullItem = CharacterFullItem.fromJson(jsonData);
    } catch (e) {
      KazumiLogger().e('Network: resolve character info failed', error: e);
    }
    return characterFullItem;
  }

  static Future<User?> getCurrentUser({String? accessToken}) async {
    try {
      final jsonData = await _client.get(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAuthAPIMirrorDomain +
                ApiEndpoints.bangumiUsernameByToken,
            []),
        requiresAuth: true,
        accessToken: accessToken,
      );
      if (jsonData['id'] != null) {
        return User.fromJson(Map<String, dynamic>.from(jsonData));
      }
    } catch (e) {
      KazumiLogger().e('Network: get current user failed', error: e);
      rethrow;
    }
    return null;
  }

  static Future<List<BangumiCollection>> getBangumiCollectibles({
    List<BangumiCollectionType> includeBangumiTypes = const [
      BangumiCollectionType.planToWatch,
      BangumiCollectionType.watched,
      BangumiCollectionType.watching,
      BangumiCollectionType.onHold,
      BangumiCollectionType.abandoned,
    ],
    required String username,
    int limit = 50,
    void Function(String message, int current, int total)? onProgress,
  }) async {
    final List<BangumiCollection> bangumiCollection = [];
    int failedItemCount = 0;
    int progressCurrent = 0;
    int progressTotal = 0;

    try {
      final rateLimiter = AsyncRateLimiter(const Duration(milliseconds: 200));
      const int concurrency = 3;

      Future<Map> fetchPageData(int offset, int pageLimit) async {
        await rateLimiter.acquire();
        final url = ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAuthAPIMirrorDomain +
                ApiEndpoints.bangumiGetAllCollections,
            [username, pageLimit, offset]);
        final jsonData = await _client.get(
          url,
          requiresAuth: true,
        );
        if (jsonData is! Map || jsonData['data'] is! List) {
          KazumiLogger().e(
            'BangumiApi: invalid collection response format at offset=$offset',
          );
          throw const FormatException(
              'BangumiApi: Invalid collection response format');
        }
        return jsonData;
      }

      List<BangumiCollection> parsePageItems(List<dynamic> jsonList) {
        final List<BangumiCollection> items = [];
        for (dynamic jsonItem in jsonList) {
          if (jsonItem is Map) {
            try {
              final collection = BangumiCollection.fromJson(jsonItem);
              if (includeBangumiTypes.contains(collection.type)) {
                items.add(collection);
              }
            } catch (e) {
              KazumiLogger().e(
                'BangumiApi: parse collection item failed: ${e.toString()}',
                error: e,
              );
              failedItemCount++;
            }
          }
        }
        return items;
      }

      final firstPageJson = await fetchPageData(0, limit);
      final int? rawTotal = firstPageJson['total'] as int?;
      final serverLimit = (firstPageJson['limit'] as int?) ?? limit;
      final effectiveLimit = (serverLimit > 0) ? serverLimit : limit;
      final List<dynamic> firstPageList =
          firstPageJson['data'] as List<dynamic>;

      if (rawTotal == null) {
        KazumiLogger().e(
          'BangumiApi: missing or invalid total in collection response',
        );
        throw const FormatException(
            'BangumiApi: missing total in collection response');
      }
      final int total = rawTotal;

      final firstPageReceivedCount = firstPageList.length;
      final firstPageItems = parsePageItems(firstPageList);
      bangumiCollection.addAll(firstPageItems);
      progressCurrent += firstPageList.length;

      if (total > 0 && firstPageReceivedCount == 0) {
        KazumiLogger().e(
          'BangumiApi: received empty data on first page while total > 0 (total=$total)',
        );
        throw const FormatException(
            'BangumiApi: received empty data on first page while total > 0');
      }
      progressTotal = total;
      onProgress?.call(
        '正在拉取 Bangumi 收藏',
        progressCurrent,
        progressTotal,
      );

      if (total == 0 || firstPageReceivedCount >= total) {
        KazumiLogger()
            .d('get Bangumi collection count: ${bangumiCollection.length}');
        KazumiLogger().d('get item failed count: $failedItemCount');
        return bangumiCollection;
      }

      final remainingOffsets = <int>[];
      for (int off = effectiveLimit; off < total; off += effectiveLimit) {
        remainingOffsets.add(off);
      }

      final Map<int, List<BangumiCollection>> pageResults = {};
      final offsetsQueue = List<int>.from(remainingOffsets);

      Future<void> worker() async {
        while (offsetsQueue.isNotEmpty) {
          final offset = offsetsQueue.removeAt(0);
          final pageJson = await fetchPageData(offset, effectiveLimit);
          final List<dynamic> jsonList = pageJson['data'] as List<dynamic>;
          final items = parsePageItems(jsonList);
          pageResults[offset] = items;

          progressCurrent += jsonList.length;
          onProgress?.call(
            '正在拉取 Bangumi 收藏',
            progressCurrent > progressTotal ? progressTotal : progressCurrent,
            progressTotal,
          );

          if (jsonList.length < serverLimit &&
              offset + jsonList.length >= total) {
            offsetsQueue.clear();
            break;
          }
        }
      }

      final workerCount = remainingOffsets.length < concurrency
          ? remainingOffsets.length
          : concurrency;
      await Future.wait(List.generate(workerCount, (_) => worker()));

      final Set<int> seenBangumiIds =
          bangumiCollection.map((e) => e.bangumiId).toSet();
      for (final offset in remainingOffsets) {
        final items = pageResults[offset];
        if (items != null) {
          for (final item in items) {
            if (seenBangumiIds.add(item.bangumiId)) {
              bangumiCollection.add(item);
            }
          }
        }
      }
    } catch (e) {
      KazumiLogger().e('Network: get bangumi collection failed', error: e);
      rethrow;
    }
    KazumiLogger()
        .d('get Bangumi collection count: ${bangumiCollection.length}');
    KazumiLogger().d('get item failed count: $failedItemCount');
    return bangumiCollection;
  }

  static Future<bool> updateBangumiById(
      int id, Map<String, dynamic> data) async {
    await _writeRateLimiter.acquire();
    try {
      await _client.post(
        ApiEndpoints.formatUrl(
            ApiEndpoints.bangumiAuthAPIMirrorDomain +
                ApiEndpoints.bangumiSetCollection,
            [id]),
        data: data,
        requiresAuth: true,
      );
      KazumiLogger().d('Update to Bangumi: Id: $id');
      return true;
    } on NetworkException catch (e) {
      String str;
      switch (e.statusCode) {
        case 400:
          str = 'Validation Error 验证错误';
          break;
        case 401:
          str = 'Unauthorized 未经授权';
          break;
        case 404:
          str = 'User not found 用户不存在';
          break;
        default:
          str = 'Error $e';
      }
      KazumiLogger().e('BangumiApi: $str', error: e);
      return false;
    } catch (e) {
      KazumiLogger().e('Network: update bangumi collection failed', error: e);
      rethrow;
    }
  }

  static Future<bool> updateBangumiByType(int id, int localType) async {
    final type = CollectType.fromValue(localType).toBangumiCollectionType();
    if (type == null) {
      return false;
    }
    return await updateBangumiById(id, {'type': type.value});
  }

  static Future<bool> addOrUpdateBangumiEvaluationBySubjectID(
    int subjectID,
    int localType, {
    String? comment,
    int? rate,
    List<String>? tags,
  }) async {
    final bangumiType =
        CollectType.fromValue(localType).toBangumiCollectionType();
    if (bangumiType == null) {
      return false;
    }
    final data = <String, dynamic>{'type': bangumiType.value};
    if (comment != null) data['comment'] = comment;
    if (rate != null) data['rate'] = rate;
    if (tags != null) data['tags'] = tags;
    return updateBangumiById(subjectID, data);
  }
}
