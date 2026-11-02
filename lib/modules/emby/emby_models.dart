/// Emby / Jellyfin 服务端配置与媒体条目模型。
///
/// 没有用 Hive TypeAdapter：新增 adapter 要占 typeId 并重新生成 .g.dart，
/// 而服务器配置是低频小数据，整份 JSON 塞进一个 String 设置项更省事，
/// 以后加字段只要在 fromJson 里给默认值，不用动存储 schema。
class EmbyServer {
  const EmbyServer({
    required this.id,
    required this.name,
    required this.url,
    required this.userId,
    required this.userName,
    required this.accessToken,
    this.allowBadCertificate = false,
    this.backupUrls = const <String>[],
  });

  /// 本地生成的稳定标识，用于去重和"当前选中服务器"。
  final String id;

  /// 显示名，默认取服务器 host。
  final String name;

  /// 规范化后的基址：无尾斜杠，不含 /web/index.html 之类的界面路径。
  final String url;

  final String userId;
  final String userName;
  final String accessToken;

  /// 局域网自签证书的服务器要开这个，否则 dio 直接拒连。
  final bool allowBadCertificate;

  /// 备用线路的基址（主线路 [url] 连不上时按顺序顶上去）。
  ///
  /// 只存拼好的 base url，线路的名字/备注在 `LuVaultServer.backupLines`
  /// 里，两边用同一个 server id 关联。
  final List<String> backupUrls;

  /// 写进 [PlaybackHistoryIdentity.pluginName] 的适配器名。
  ///
  /// 历史按 adapterName 分档（`History.key => scopedKey(adapterName, ...)`），
  /// 所以用 `emby:<host:port>` 就能让 Emby 记录和插件记录互不覆盖。
  String get adapterName {
    final authority = Uri.tryParse(url)?.authority;
    return 'emby:${authority == null || authority.isEmpty ? id : authority}';
  }

  EmbyServer copyWith({
    String? id,
    String? name,
    String? url,
    String? userId,
    String? userName,
    String? accessToken,
    bool? allowBadCertificate,
    List<String>? backupUrls,
  }) {
    return EmbyServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      accessToken: accessToken ?? this.accessToken,
      allowBadCertificate: allowBadCertificate ?? this.allowBadCertificate,
      backupUrls: backupUrls ?? this.backupUrls,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'userId': userId,
        'userName': userName,
        'accessToken': accessToken,
        'allowBadCertificate': allowBadCertificate,
        'backupUrls': backupUrls,
      };

  factory EmbyServer.fromJson(Map<String, dynamic> json) => EmbyServer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        accessToken: json['accessToken']?.toString() ?? '',
        allowBadCertificate: json['allowBadCertificate'] == true,
        backupUrls: [
          for (final item in (json['backupUrls'] as List<dynamic>? ?? const []))
            if (item?.toString().trim().isNotEmpty ?? false) item.toString(),
        ],
      );
}

/// 媒体库（Emby 里叫 View）。`collectionType` 决定怎么取内容。
class EmbyLibrary {
  const EmbyLibrary({
    required this.id,
    required this.name,
    required this.collectionType,
    this.imageTag,
  });

  final String id;
  final String name;

  /// `movies` / `tvshows` / `music` / `boxsets` …，可能为空。
  final String collectionType;
  final String? imageTag;

  factory EmbyLibrary.fromJson(Map<String, dynamic> json) => EmbyLibrary(
        id: json['Id']?.toString() ?? '',
        name: json['Name']?.toString() ?? '',
        collectionType: json['CollectionType']?.toString() ?? '',
        imageTag: _imageTagOf(json),
      );
}

/// 服务器内容统计（`/Items/Counts`），媒体库页统计条用。
class EmbyItemCounts {
  const EmbyItemCounts({
    this.movies = 0,
    this.series = 0,
    this.episodes = 0,
  });

  final int movies;
  final int series;
  final int episodes;

  factory EmbyItemCounts.fromJson(Map<String, dynamic> json) => EmbyItemCounts(
        movies: (json['MovieCount'] as num?)?.toInt() ?? 0,
        series: (json['SeriesCount'] as num?)?.toInt() ?? 0,
        episodes: (json['EpisodeCount'] as num?)?.toInt() ?? 0,
      );
}

/// 媒体条目：剧集（Series）、电影（Movie）、单集（Episode）都用它。
class EmbyItem {
  const EmbyItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesId,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
    this.productionYear,
    this.overview,
    this.communityRating,
    this.primaryImageTag,
    this.backdropImageTag,
    this.parentId,
    this.seriesPrimaryImageTag,
    this.parentPrimaryImageTag,
    this.runTimeTicks,
    this.genres = const [],
    this.officialRating,
    this.played = false,
    this.playbackPositionTicks,
    this.isFavorite = false,
    this.childCount,
    this.directUrl,
  });

  /// 直接可播的地址（本地文件、相册视频、网络链接、网盘直链）。
  ///
  /// 这不是 Emby 返回的字段，只在本地构造条目时填。填了它，播放器就跳过
  /// 服务端的 PlaybackInfo 解析，直接拿这个地址起播。
  final String? directUrl;

  final String id;
  final String name;

  /// `Series` / `Movie` / `Episode` / `Season` / `Video` …
  final String type;
  final String? seriesId;

  /// 所属剧名（Episode 才有），列表里做副标题用。
  final String? seriesName;

  /// 集号（Episode 才有）。
  final int? indexNumber;

  /// 季号（Episode 才有）。
  final int? parentIndexNumber;
  final int? productionYear;
  final String? overview;
  final double? communityRating;
  final String? primaryImageTag;

  /// 背景大图。详情页主视觉用，没有时退回封面。
  final String? backdropImageTag;

  /// 上一级条目 id（Season 的剧、Episode 的季）。
  final String? parentId;

  /// 剧集自己没有封面时，服务端会给这两样——它们属于**上一级条目**，
  /// 必须配上级 id 去取，配自己的 id 一定是 404。
  final String? seriesPrimaryImageTag;
  final String? parentPrimaryImageTag;

  /// Emby 的时长单位是 100 纳秒一格。
  final int? runTimeTicks;

  final List<String> genres;

  /// 分级，例如 `US-13`、`JP-15`。
  final String? officialRating;

  /// 服务端记录的「已看完」。
  final bool played;

  /// 服务端记录的播放进度（100 纳秒一格）。续播就靠它。
  final int? playbackPositionTicks;

  final bool isFavorite;

  /// 季/剧下的子项数量（Series 返回集数，Season 返回集数）。
  final int? childCount;

  bool get isSeries => type == 'Series';
  bool get isMovie => type == 'Movie';
  bool get isEpisode => type == 'Episode';
  bool get isSeason => type == 'Season';

  /// 这个条目自己有没有封面。
  bool get hasOwnCover => (primaryImageTag ?? '').isNotEmpty;

  /// 封面该去哪个条目取。
  ///
  /// 单集（Episode）和季（Season）经常**没有自己的 Primary 图**：服务端只
  /// 返回 `SeriesPrimaryImageTag` / `ParentPrimaryImageTag`，而这两样属于
  /// **上一级条目**。以前一律拿自己的 id 去请求 `/Items/{自己}/Images/Primary`，
  /// 服务端 404，界面就是一屏灰块——「很多剧的封面都不加载」就是这么来的。
  ///
  /// 顺序：自己的图 > 所属剧 > 上一级 > 自己（让服务端决定）。
  String get coverItemId {
    if (hasOwnCover) return id;
    final String sid = seriesId ?? '';
    if ((seriesPrimaryImageTag ?? '').isNotEmpty && sid.isNotEmpty) return sid;
    final String pid = parentId ?? '';
    if ((parentPrimaryImageTag ?? '').isNotEmpty && pid.isNotEmpty) return pid;
    return id;
  }

  /// 配套的 tag；都没有就返回 null（让地址里不带 tag，服务端取最新）。
  String? get coverTag {
    if (hasOwnCover) return primaryImageTag;
    if ((seriesPrimaryImageTag ?? '').isNotEmpty) return seriesPrimaryImageTag;
    if ((parentPrimaryImageTag ?? '').isNotEmpty) return parentPrimaryImageTag;
    return null;
  }

  /// 能直接起播的条目（电影 / 单集 / 散装视频）。
  bool get isPlayable =>
      type == 'Movie' || type == 'Episode' || type == 'Video';

  /// 详情页标题用的副标题，例如「2021 · 8.4 分」。
  String get metaLine {
    final parts = <String>[
      if (productionYear != null) '$productionYear',
      if (communityRating != null) '${communityRating!.toStringAsFixed(1)} 分',
    ];
    return parts.join(' · ');
  }

  Duration? get runTime {
    final ticks = runTimeTicks;
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: ticks ~/ 10);
  }

  /// 续播位置；没看过或已看完时返回 null。
  Duration? get resumePosition {
    final ticks = playbackPositionTicks;
    if (ticks == null || ticks <= 0) return null;
    return Duration(microseconds: ticks ~/ 10);
  }

  /// 观看进度 0~1，用于卡片底部的细进度条。
  double get watchedRatio {
    final total = runTimeTicks;
    final position = playbackPositionTicks;
    if (total == null || position == null || total <= 0) return 0;
    final ratio = position / total;
    if (ratio.isNaN) return 0;
    return ratio.clamp(0.0, 1.0);
  }

  /// 有进度但没看完——「继续观看」的判定条件。
  bool get isInProgress => !played && watchedRatio > 0.01 && watchedRatio < 0.98;

  /// 卡片副标题：电影给年份，单集给「S01E03 · 剧名」。
  String get cardSubtitle {
    if (isEpisode) {
      final season = parentIndexNumber;
      final episode = indexNumber;
      final code = (season != null && episode != null)
          ? 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
          : '';
      final name = seriesName?.trim() ?? '';
      if (code.isEmpty) return name;
      return name.isEmpty ? code : '$code · $name';
    }
    final year = productionYear;
    return year == null ? '' : '$year';
  }

  factory EmbyItem.fromJson(Map<String, dynamic> json) {
    final userData = json['UserData'];
    final genres = json['Genres'];
    return EmbyItem(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      type: json['Type']?.toString() ?? '',
      seriesId: json['SeriesId']?.toString(),
      seriesName: json['SeriesName']?.toString(),
      indexNumber: _intOrNull(json['IndexNumber']),
      parentIndexNumber: _intOrNull(json['ParentIndexNumber']),
      productionYear: _intOrNull(json['ProductionYear']),
      overview: json['Overview']?.toString(),
      communityRating: _doubleOrNull(json['CommunityRating']),
      primaryImageTag: _imageTagOf(json),
      backdropImageTag: _imageTagOf(json, type: 'Backdrop'),
      parentId: json['ParentId']?.toString(),
      seriesPrimaryImageTag: _nonEmpty(json['SeriesPrimaryImageTag']),
      parentPrimaryImageTag: _nonEmpty(json['ParentPrimaryImageTag']),
      runTimeTicks: _intOrNull(json['RunTimeTicks']),
      genres: genres is List
          ? [for (final g in genres) g.toString()].where((g) => g.isNotEmpty).toList()
          : const [],
      officialRating: json['OfficialRating']?.toString(),
      played: userData is Map && userData['Played'] == true,
      playbackPositionTicks:
          userData is Map ? _intOrNull(userData['PlaybackPositionTicks']) : null,
      isFavorite: userData is Map && userData['IsFavorite'] == true,
      childCount: _intOrNull(json['ChildCount']) ?? _intOrNull(json['RecursiveItemCount']),
    );
  }
}

String? _nonEmpty(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _imageTagOf(Map<String, dynamic> json, {String type = 'Primary'}) {
  final tags = json['ImageTags'];
  if (tags is Map) {
    final primary = tags[type]?.toString();
    if (primary != null && primary.isNotEmpty) return primary;
  }
  if (type == 'Backdrop') {
    final backdrops = json['BackdropImageTags'];
    if (backdrops is List && backdrops.isNotEmpty) {
      final first = backdrops.first?.toString();
      if (first != null && first.isNotEmpty) return first;
    }
  }
  return null;
}

/// 媒体源。`PlaybackInfo` 返回的核心部分。
///
/// [id] 才是 `MediaSourceId` 该用的值——不是条目 id。Emby 4.9 之后
/// 它是 `mediasource_<itemId>` 形式，直接拿条目 id 去请求会 400。
/// Emby 的章节标记（用于「章节」面板）。
class EmbyChapter {
  const EmbyChapter({required this.name, required this.startTicks});

  final String name;
  final int startTicks;

  factory EmbyChapter.fromJson(Map<String, dynamic> json) => EmbyChapter(
        name: json['Name']?.toString() ?? '章节',
        startTicks: _intOrNull(json['StartPositionTicks']) ?? 0,
      );

  Duration get start => Duration(microseconds: startTicks ~/ 10);
}

class EmbyMediaSource {
  const EmbyMediaSource({
    required this.id,
    this.container = '',
    this.supportsDirectPlay = false,
    this.supportsDirectStream = false,
    this.runTimeTicks,
    this.introStartTicks,
    this.introEndTicks,
    this.outroStartTicks,
    this.chapters = const [],
    this.mediaStreams = const [],
  });

  final String id;
  final String container;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final int? runTimeTicks;

  /// 片头区间（Emby 4.x 在 PlaybackInfo 的 MediaSource 上给出）。
  final int? introStartTicks;
  final int? introEndTicks;

  /// 片尾开始（EndCreditsStartPositionTicks），用于自动跳过片尾。
  final int? outroStartTicks;

  final List<EmbyChapter> chapters;
  final List<EmbyMediaStream> mediaStreams;

  List<EmbyMediaStream> get audioStreams =>
      mediaStreams.where((s) => s.isAudio).toList();

  /// 复制一份、只换掉媒体流列表。
  ///
  /// 用在「PlaybackInfo 没给 MediaStreams、条目详情给了」这种情况：容器、
  /// 时长、章节还是 PlaybackInfo 那份（它有真实的媒体源 id），只有流补进来。
  EmbyMediaSource withStreamsFrom(EmbyMediaSource other) => EmbyMediaSource(
        id: id,
        container: container.isEmpty ? other.container : container,
        supportsDirectPlay: supportsDirectPlay || other.supportsDirectPlay,
        supportsDirectStream: supportsDirectStream || other.supportsDirectStream,
        runTimeTicks: runTimeTicks ?? other.runTimeTicks,
        introStartTicks: introStartTicks,
        introEndTicks: introEndTicks,
        outroStartTicks: outroStartTicks,
        chapters: chapters.isEmpty ? other.chapters : chapters,
        mediaStreams: other.mediaStreams,
      );

  List<EmbyMediaStream> get subtitleStreams =>
      mediaStreams.where((s) => s.isSubtitle).toList();

  Duration? get introStart => introStartTicks == null
      ? null
      : Duration(microseconds: introStartTicks! ~/ 10);
  Duration? get introEnd =>
      introEndTicks == null ? null : Duration(microseconds: introEndTicks! ~/ 10);
  Duration? get outroStart => outroStartTicks == null
      ? null
      : Duration(microseconds: outroStartTicks! ~/ 10);

  factory EmbyMediaSource.fromJson(Map<String, dynamic> json) {
    final streams = json['MediaStreams'];
    final chapters = json['Chapters'];
    final parsedChapters = chapters is List
        ? [
            for (final c in chapters)
              if (c is Map)
                EmbyChapter.fromJson(Map<String, dynamic>.from(c)),
          ]
        : const <EmbyChapter>[];
    return EmbyMediaSource(
      id: json['Id']?.toString() ?? '',
      container: json['Container']?.toString() ?? '',
      supportsDirectPlay: json['SupportsDirectPlay'] == true,
      supportsDirectStream: json['SupportsDirectStream'] == true,
      runTimeTicks: _intOrNull(json['RunTimeTicks']),
      introStartTicks: _intOrNull(json['IntroStartPositionTicks']),
      introEndTicks: _intOrNull(json['IntroEndPositionTicks']),
      outroStartTicks: _intOrNull(json['EndCreditsStartPositionTicks']),
      chapters: parsedChapters,
      mediaStreams: streams is List
          ? [
              for (final s in streams)
                if (s is Map) EmbyMediaStream.fromJson(Map<String, dynamic>.from(s)),
            ]
          : const [],
    );
  }
}

/// 一条音轨 / 字幕轨 / 视频轨。
class EmbyMediaStream {
  const EmbyMediaStream({
    required this.index,
    required this.type,
    this.codec = '',
    this.language = '',
    this.displayTitle = '',
    this.isDefault = false,
    this.isExternal = false,
    this.isForced = false,
    this.isHearingImpaired = false,
    this.isTextSubtitle,
  });

  final int index;

  /// `Video` / `Audio` / `Subtitle`。
  final String type;
  final String codec;
  final String language;
  final String displayTitle;
  final bool isDefault;
  final bool isExternal;

  /// 强制字幕（`[Forced]`，通常只翻译画面上的外语/招牌）。
  final bool isForced;

  /// 听障字幕（带音效描述）。
  final bool isHearingImpaired;

  /// 服务端明确说这是不是「文本字幕」。
  ///
  /// 文本字幕可以由服务端转成 srt/ass 给 mpv；图形字幕（PGS / DVD sub）
  /// 不能转，只能原样 `Stream.sup` 交给 mpv 自己解，个别设备解不了。
  final bool? isTextSubtitle;

  bool get isAudio => type == 'Audio';
  bool get isSubtitle => type == 'Subtitle';

  /// 文本字幕：`IsTextSubtitleStream` 有就用，没有就按编码猜。
  bool get textLike {
    if (isTextSubtitle != null) return isTextSubtitle!;
    const text = {'subrip', 'srt', 'ass', 'ssa', 'webvtt', 'vtt', 'mov_text', 'mp4', 'text'};
    return text.contains(codec.toLowerCase());
  }

  /// 界面上那一行的标题：优先用服务端给的名字，退化成「语言 · 编码」。
  String get label {
    if (displayTitle.isNotEmpty) return displayTitle;
    final parts = <String>[
      if (language.isNotEmpty) language,
      if (codec.isNotEmpty) codec.toUpperCase(),
    ];
    return parts.isEmpty ? '轨道 ${index + 1}' : parts.join(' · ');
  }

  factory EmbyMediaStream.fromJson(Map<String, dynamic> json) => EmbyMediaStream(
        index: _intOrNull(json['Index']) ?? 0,
        type: json['Type']?.toString() ?? '',
        codec: json['Codec']?.toString() ?? '',
        language: json['Language']?.toString() ?? '',
        displayTitle: (json['DisplayTitle'] ?? json['Title'] ?? '').toString(),
        isDefault: json['IsDefault'] == true,
        isExternal: json['IsExternal'] == true,
        isForced: json['IsForced'] == true,
        isHearingImpaired: json['IsHearingImpaired'] == true,
        isTextSubtitle: json['IsTextSubtitleStream'] is bool
            ? json['IsTextSubtitleStream'] as bool
            : null,
      );
}

/// 服务端替我们找到的一条外挂字幕（OpenSubtitles 之类的插件给的）。
class EmbyRemoteSubtitle {
  const EmbyRemoteSubtitle({
    required this.id,
    this.name = '',
    this.language = '',
    this.format = '',
    this.providerName = '',
    this.downloadCount = 0,
    this.isHashMatch = false,
    this.comment = '',
  });

  final String id;
  final String name;
  final String language;
  final String format;
  final String providerName;
  final int downloadCount;
  final bool isHashMatch;
  final String comment;

  factory EmbyRemoteSubtitle.fromJson(Map<String, dynamic> json) =>
      EmbyRemoteSubtitle(
        id: (json['Id'] ?? json['SubtitleId'] ?? '').toString(),
        name: (json['Name'] ?? '').toString(),
        language: (json['Language'] ?? json['ThreeLetterISOLanguageName'] ?? '')
            .toString(),
        format: (json['Format'] ?? '').toString(),
        providerName: (json['ProviderName'] ?? '').toString(),
        downloadCount: _intOrNull(json['DownloadCount']) ?? 0,
        isHashMatch: json['IsHashMatch'] == true,
        comment: (json['Comment'] ?? '').toString(),
      );
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleOrNull(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

/// 把 Emby 的字符串 id 折成一个稳定的正整数，喂给 [PlaybackInitParams.bangumiId]。
///
/// 播放器和历史都要求 int 型 bangumiId，而 Emby 用 GUID。这里用 FNV-1a
/// 取 31 位，保证同一部剧每次算出来一样（历史才能命中），也不会溢出 int。
int embyBangumiId(String itemId) {
  var hash = 0x811c9dc5;
  for (final unit in itemId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  // 0 会让部分历史逻辑当成"无效条目"，避一下。
  return hash == 0 ? 1 : hash;
}

/// 规范化用户填进来的服务器地址。
///
/// 用户经常直接粘贴 Emby 网页地址（带 /web/index.html），或者漏了协议。
/// 这里统一成 `scheme://host:port[/子路径]`，去掉查询串和界面路径。
String normalizeEmbyUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  if (!text.contains('://')) {
    text = 'http://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return '';
  var path = uri.path;
  // 砍掉 Emby 网页端的入口路径。
  final webIndex = path.indexOf('/web/');
  if (webIndex >= 0) path = path.substring(0, webIndex);
  if (path.endsWith('/web')) path = path.substring(0, path.length - 4);
  // 用户手打的地址常有 `host:8096//` 这种，一个 endsWith 只能砍一层。
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '${uri.scheme}://${uri.authority}$path';
}
