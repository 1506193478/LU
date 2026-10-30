import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:XL/modules/danmaku/danmaku_module.dart';
import 'package:XL/request/core/dio_factory.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/utils/bilibili_wbi.dart';
import 'package:XL/utils/danmaku.dart';
import 'package:XL/utils/title_match.dart';

/// B 站番剧（`pgc/view/web/season`）里的一个季度。
class BilibiliSeason {
  const BilibiliSeason({
    required this.seasonId,
    required this.title,
    required this.originalTitle,
    required this.episodeCount,
    required this.cover,
    required this.score,
  });

  final int seasonId;
  final String title;
  final String originalTitle;
  final int episodeCount;
  final String cover;
  final String score;
}

/// B 站番剧的一个正片剧集。
class BilibiliEpisode {
  const BilibiliEpisode({
    required this.number,
    required this.title,
    required this.longTitle,
    required this.cid,
  });

  final int number;
  final String title;
  final String longTitle;
  final int cid;

  String get displayTitle {
    if (longTitle.isEmpty) {
      return '第 $number 集';
    }
    return '第 $number 集 · $longTitle';
  }
}

/// 无凭据的 B 站弹幕源。
///
/// 三段式链路：
///   1. wbi 签名搜索番剧 → season_id
///   2. `pgc/view/web/season` → 每集的 cid
///   3. `x/v1/dm/list.so` → XML 弹幕
///
/// 这三个接口都不需要登录，只要求 `Referer: https://www.bilibili.com`。
class BilibiliDanmakuApi {
  BilibiliDanmakuApi._();

  static const String _apiHost = 'https://api.bilibili.com';

  static const Map<String, String> _headers = {
    'referer': 'https://www.bilibili.com',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };

  static const Duration _timeout = Duration(seconds: 15);

  /// 按番剧名搜索 B 站番剧季度。
  static Future<List<BilibiliSeason>> searchSeasons(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final query = await BilibiliWbi.signedQuery({
      'search_type': 'media_bangumi',
      'keyword': trimmed,
      'page': '1',
    });
    final response = await DioFactory.apiDio.get<dynamic>(
      '$_apiHost/x/web-interface/wbi/search/type?$query',
      options: Options(headers: _headers, receiveTimeout: _timeout),
    );
    final body = response.data;
    if (body is! Map) {
      throw StateError('Bilibili 搜索返回非 JSON，可能被风控');
    }
    if (body['code'] != 0) {
      throw StateError('Bilibili 搜索失败: ${body['message']}');
    }
    final data = body['data'];
    final result = data is Map ? data['result'] : null;
    if (result is! List) {
      return const [];
    }
    final seasons = <BilibiliSeason>[];
    for (final item in result) {
      if (item is! Map) {
        continue;
      }
      final seasonId =
          _asInt(item['season_id']) ?? _asInt(item['pgc_season_id']);
      if (seasonId == null || seasonId == 0) {
        continue;
      }
      seasons.add(
        BilibiliSeason(
          seasonId: seasonId,
          title: _stripHtml(item['title']?.toString() ?? ''),
          originalTitle: _stripHtml(item['org_title']?.toString() ?? ''),
          episodeCount: _asInt(item['ep_size']) ?? 0,
          cover: _normalizeUrl(item['cover']?.toString() ?? ''),
          score: _scoreText(item['media_score']),
        ),
      );
    }
    return seasons;
  }

  /// 取某个季度的全部正片剧集（含 cid）。
  static Future<List<BilibiliEpisode>> getEpisodes(int seasonId) async {
    final response = await DioFactory.apiDio.get<dynamic>(
      '$_apiHost/pgc/view/web/season',
      queryParameters: {'season_id': seasonId},
      options: Options(headers: _headers, receiveTimeout: _timeout),
    );
    final body = response.data;
    if (body is! Map || body['code'] != 0) {
      final message = body is Map ? body['message'] : null;
      throw StateError('Bilibili 剧集获取失败: $message');
    }
    final result = body['result'];
    final episodes = result is Map ? result['episodes'] : null;
    if (episodes is! List) {
      return const [];
    }
    final parsed = <BilibiliEpisode>[];
    var number = 0;
    for (final item in episodes) {
      if (item is! Map) {
        continue;
      }
      final cid = _asInt(item['cid']);
      if (cid == null || cid == 0) {
        continue;
      }
      number++;
      parsed.add(
        BilibiliEpisode(
          number: number,
          title: item['title']?.toString() ?? '$number',
          longTitle: item['long_title']?.toString() ?? '',
          cid: cid,
        ),
      );
    }
    return parsed;
  }

  /// 拉取某个 cid 下的全部弹幕。
  ///
  /// 响应固定带 `Content-Encoding: deflate`，且是裸 deflate（无 zlib 头），
  /// 所以这里按字节取回后自己解压，Dio 的自动解压对裸 deflate 不一定生效。
  static Future<List<DanmakuEntry>> getDanmaku(int cid) async {
    if (cid == 0) {
      return const [];
    }
    final response = await DioFactory.apiDio.get<List<int>>(
      '$_apiHost/x/v1/dm/list.so',
      queryParameters: {'oid': cid},
      options: Options(
        headers: _headers,
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final bytes = response.data ?? const <int>[];
    final xml = _decodeBody(bytes);
    final entries = _parseXml(xml);
    KazumiLogger().i('Danmaku: bilibili cid $cid -> ${entries.length} entries');
    return entries;
  }

  /// 自动匹配：番剧名 + 集号 → 弹幕。
  ///
  /// 返回空列表表示搜不到番剧、或该集没有 cid，调用方据此提示用户手动检索。
  static Future<List<DanmakuEntry>> fetchByTitleAndEpisode({
    required String title,
    required int episode,
    String? originalTitle,
  }) async {
    final seasons = await searchSeasons(title);
    final season = pickBestSeason(
      seasons,
      title: title,
      originalTitle: originalTitle,
    );
    if (season == null) {
      KazumiLogger().i('Danmaku: no bilibili season matched "$title"');
      return const [];
    }
    final episodes = await getEpisodes(season.seasonId);
    if (episodes.isEmpty) {
      return const [];
    }
    final index = episode - 1;
    if (index < 0 || index >= episodes.length) {
      KazumiLogger().i(
        'Danmaku: episode $episode out of range '
        '(${episodes.length} episodes) for ${season.title}',
      );
      return const [];
    }
    return getDanmaku(episodes[index].cid);
  }

  /// 从候选里挑出最可能是同一部番的季度。
  ///
  /// 中文名与原名分别打分取高者，原名略降权，这样同分时中文精确匹配优先。
  /// 另外对配音版、剧场版这类同 IP 变体降权，避免抢走正片。
  static BilibiliSeason? pickBestSeason(
    List<BilibiliSeason> seasons, {
    required String title,
    String? originalTitle,
  }) {
    if (seasons.isEmpty) {
      return null;
    }
    final cnTargets = <String>[normalizeTitle(title)]
      ..removeWhere((value) => value.isEmpty);
    final orgTargets = <String>[
      if (originalTitle != null && originalTitle.trim().isNotEmpty)
        normalizeTitle(originalTitle),
    ]..removeWhere((value) => value.isEmpty);
    if (cnTargets.isEmpty && orgTargets.isEmpty) {
      return seasons.first;
    }

    BilibiliSeason? best;
    var bestScore = 0;
    for (final season in seasons) {
      final score = _seasonScore(season, cnTargets, orgTargets);
      if (score > bestScore) {
        bestScore = score;
        best = season;
      }
    }
    // 低于 60 分视为不可信，宁可让用户手动选也不要串番。
    return bestScore >= 60 ? best : null;
  }

  /// 配音版/剧场版等同 IP 变体的标题标记。
  static const List<String> _dubMarkers = [
    '中配版', '中配', '国语', '普通话', '粤语', '台配',
  ];
  static const List<String> _movieMarkers = ['剧场版', '总集篇', '电影'];

  static int _seasonScore(
    BilibiliSeason season,
    List<String> cnTargets,
    List<String> orgTargets,
  ) {
    final cnTitle = normalizeTitle(season.title);
    final orgTitle = normalizeTitle(season.originalTitle);
    var score = 0;
    if (cnTitle.isNotEmpty) {
      for (final target in cnTargets) {
        final value = titleSimilarity(target, cnTitle);
        if (value > score) {
          score = value;
        }
      }
    }
    if (orgTitle.isNotEmpty) {
      for (final target in orgTargets) {
        // 原名只作补充，同分时让中文精确匹配胜出。
        final value = titleSimilarity(target, orgTitle) * 95 ~/ 100;
        if (value > score) {
          score = value;
        }
      }
    }
    if (score == 0) {
      return 0;
    }
    final requested = [...cnTargets, ...orgTargets].join('|');
    for (final marker in _dubMarkers) {
      if (season.title.contains(marker) &&
          !requested.contains(normalizeTitle(marker))) {
        score -= 12;
      }
    }
    for (final marker in _movieMarkers) {
      if (season.title.contains(marker) &&
          !requested.contains(normalizeTitle(marker))) {
        score -= 8;
      }
    }
    return score < 0 ? 0 : score;
  }

  static String _decodeBody(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }
    // 已经解压过的响应第一字节就是 '<'
    if (bytes[0] == 0x3C) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return utf8.decode(zlib.decode(bytes), allowMalformed: true);
    } catch (_) {
      // 裸 deflate，没有 zlib 头
    }
    try {
      return utf8.decode(
        ZLibDecoder(raw: true).convert(bytes),
        allowMalformed: true,
      );
    } catch (_) {
      // 落到最后的兜底
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static final RegExp _entryPattern =
      RegExp(r'<d p="([^"]*)"[^>]*>(.*?)</d>', dotAll: true);
  static final RegExp _entityPattern = RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos);');

  static List<DanmakuEntry> _parseXml(String xml) {
    if (xml.isEmpty) {
      return const [];
    }
    final entries = <DanmakuEntry>[];
    for (final match in _entryPattern.allMatches(xml)) {
      final parts = match.group(1)!.split(',');
      if (parts.length < 4) {
        continue;
      }
      final time = double.tryParse(parts[0]);
      final mode = int.tryParse(parts[1]);
      final colorValue = int.tryParse(parts[3]);
      if (time == null || mode == null || colorValue == null) {
        continue;
      }
      final message = _unescape(match.group(2)!).trim();
      if (message.isEmpty) {
        continue;
      }
      entries.add(
        DanmakuEntry(
          message: message,
          time: time,
          type: _mapMode(mode),
          color: generateDanmakuColor(colorValue),
          source: 'BiliBili',
        ),
      );
    }
    return entries;
  }

  /// B 站模式值：1/2/3 滚动，4 底部，5 顶部，6 逆向，7 高级，8 代码，9 BAS。
  /// 播放器只支持 1/4/5，其余一律按滚动处理。
  static int _mapMode(int mode) {
    return switch (mode) {
      4 => 4,
      5 => 5,
      _ => 1,
    };
  }

  static String _unescape(String input) {
    if (!input.contains('&')) {
      return input;
    }
    return input.replaceAllMapped(_entityPattern, (match) {
      final entity = match.group(1)!;
      switch (entity) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final isHex = entity.startsWith('#x') || entity.startsWith('#X');
      final digits = entity.substring(isHex ? 2 : 1);
      final code = int.tryParse(digits, radix: isHex ? 16 : 10);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    });
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  /// 搜索结果里的标题带 `<em class="keyword">` 高亮，需要剥掉。
  static String _stripHtml(String input) {
    if (input.isEmpty) {
      return '';
    }
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static String _normalizeUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    return url;
  }

  static String _scoreText(Object? mediaScore) {
    if (mediaScore is! Map) {
      return '';
    }
    final score = mediaScore['score'];
    if (score == null) {
      return '';
    }
    final value = score is num ? score : double.tryParse(score.toString());
    if (value == null || value <= 0) {
      return '';
    }
    return value.toStringAsFixed(1);
  }
}
