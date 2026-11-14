/// HG 短剧数据模型（从 HGhubX `src/types.ts` 移植）。
///
/// 字段与上游接口返回一一对应，方便对照排查；解析全部宽容——
/// 字段缺失返回空值而不是抛异常，上游改版不至于整页崩掉。
library;

class HgAuthor {
  final int id;
  final String name;
  final String avatar;
  final int followers;

  const HgAuthor({
    required this.id,
    required this.name,
    this.avatar = '',
    this.followers = 0,
  });

  factory HgAuthor.fromJson(dynamic json) {
    if (json is! Map) return const HgAuthor(id: 0, name: '');
    return HgAuthor(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      followers: (json['followers'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 竖滑流 / 列表里的视频卡。like/collect/comment 三个计数
/// 就是右下角操作栏要显示的真实数据。
class HgVideoCard {
  final int id;
  final String title;
  final String cover;
  final String description;
  final List<String> tags;
  final double score;
  final int episodeCount;
  final int totalEpisodes;
  final String duration;
  final int hot;
  final int likeCount;
  final int collectCount;
  final int commentCount;
  final bool isFinished;
  final bool isOriginal;
  final HgAuthor? author;

  const HgVideoCard({
    required this.id,
    required this.title,
    this.cover = '',
    this.description = '',
    this.tags = const [],
    this.score = 0,
    this.episodeCount = 0,
    this.totalEpisodes = 0,
    this.duration = '',
    this.hot = 0,
    this.likeCount = 0,
    this.collectCount = 0,
    this.commentCount = 0,
    this.isFinished = false,
    this.isOriginal = false,
    this.author,
  });

  factory HgVideoCard.fromJson(dynamic json) {
    if (json is! Map) {
      return const HgVideoCard(id: 0, title: '');
    }
    return HgVideoCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      score: (json['score'] as num?)?.toDouble() ?? 0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['total_episodes'] as num?)?.toInt() ?? 0,
      duration: json['duration']?.toString() ?? '',
      hot: (json['hot'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      collectCount: (json['collect_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      isFinished: json['is_finished'] == true,
      isOriginal: ((json['is_original'] as num?)?.toInt() ?? 0) == 1,
      author: json['author'] == null ? null : HgAuthor.fromJson(json['author']),
    );
  }
}

class HgPagination {
  final int page;
  final int pages;
  final int size;
  final int total;

  const HgPagination({
    this.page = 1,
    this.pages = 1,
    this.size = 20,
    this.total = 0,
  });

  factory HgPagination.fromJson(dynamic json) {
    if (json is! Map) return const HgPagination();
    return HgPagination(
      page: (json['page'] as num?)?.toInt() ?? 1,
      pages: (json['pages'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class HgPaged<T> {
  final List<T> items;
  final HgPagination pagination;

  const HgPaged({required this.items, required this.pagination});
}

class HgEpisode {
  final int epNum;
  final String title;
  final int duration;
  final int status;

  const HgEpisode({
    required this.epNum,
    required this.title,
    this.duration = 0,
    this.status = 0,
  });

  factory HgEpisode.fromJson(dynamic json) {
    if (json is! Map) return const HgEpisode(epNum: 0, title: '');
    return HgEpisode(
      epNum: (json['ep_num'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 详情页数据。counts 是点赞/收藏/评论的真实数量来源，
/// interaction 是「我有没有点过赞 / 收藏过」。
class HgDetail {
  final int id;
  final String title;
  final String description;
  final String cover;
  final List<String> tags;
  final double score;
  final int episodeCount;
  final int totalEpisodes;
  final List<HgEpisode> episodes;
  final int likeCount;
  final int collectCount;
  final int commentCount;
  final int hot;
  final HgAuthor? author;
  final bool liked;
  final bool collected;
  final bool isFinished;
  final bool isOriginal;

  const HgDetail({
    required this.id,
    required this.title,
    this.description = '',
    this.cover = '',
    this.tags = const [],
    this.score = 0,
    this.episodeCount = 0,
    this.totalEpisodes = 0,
    this.episodes = const [],
    this.likeCount = 0,
    this.collectCount = 0,
    this.commentCount = 0,
    this.hot = 0,
    this.author,
    this.liked = false,
    this.collected = false,
    this.isFinished = false,
    this.isOriginal = false,
  });

  factory HgDetail.fromJson(dynamic json) {
    if (json is! Map) return const HgDetail(id: 0, title: '');
    final counts = json['counts'];
    final interaction = json['interaction'];
    return HgDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      score: (json['score'] as num?)?.toDouble() ?? 0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['total_episodes'] as num?)?.toInt() ?? 0,
      episodes: (json['episodes'] as List?)
              ?.map(HgEpisode.fromJson)
              .toList(growable: false) ??
          const [],
      likeCount: counts is Map ? (counts['like'] as num?)?.toInt() ?? 0 : 0,
      collectCount:
          counts is Map ? (counts['collect'] as num?)?.toInt() ?? 0 : 0,
      commentCount:
          counts is Map ? (counts['comment'] as num?)?.toInt() ?? 0 : 0,
      hot: counts is Map ? (counts['hot'] as num?)?.toInt() ?? 0 : 0,
      author: json['author'] == null ? null : HgAuthor.fromJson(json['author']),
      liked: interaction is Map && interaction['liked'] == true,
      collected: interaction is Map && interaction['collected'] == true,
      isFinished: json['is_finished'] == true,
      isOriginal: ((json['is_original'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}

/// 播放信息：video_url 是上游真实地址（要再套一层本地代理）。
class HgPlayInfo {
  final int id;
  final int epNum;
  final int duration;
  final String title;
  final String videoUrl;
  final String videoUrlHevc;

  const HgPlayInfo({
    required this.id,
    required this.epNum,
    this.duration = 0,
    this.title = '',
    this.videoUrl = '',
    this.videoUrlHevc = '',
  });

  factory HgPlayInfo.fromJson(dynamic json) {
    if (json is! Map) {
      return const HgPlayInfo(id: 0, epNum: 0);
    }
    String pick(String oldField, String streamKey) {
      final s = json['streams'];
      final stream = s is Map ? s[streamKey]?.toString() ?? '' : '';
      if (stream.isNotEmpty) return stream;
      return json[oldField]?.toString() ?? '';
    }

    return HgPlayInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      epNum: (json['ep_num'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      videoUrl: pick('video_url', 'main'),
      videoUrlHevc: pick('video_url_hevc', 'hevc'),
    );
  }
}

class HgComment {
  final int id;
  final int userId;
  final String nickname;
  final String avatar;
  final String text;
  final String time;
  final int likeCount;
  final bool liked;
  final int replyCount;
  final int replyId;
  final bool isPinned;
  final String ipRegion;
  final List<HgComment> replyList;

  const HgComment({
    required this.id,
    this.userId = 0,
    this.nickname = '',
    this.avatar = '',
    this.text = '',
    this.time = '',
    this.likeCount = 0,
    this.liked = false,
    this.replyCount = 0,
    this.replyId = 0,
    this.isPinned = false,
    this.ipRegion = '',
    this.replyList = const [],
  });

  factory HgComment.fromJson(dynamic json) {
    if (json is! Map) return const HgComment(id: 0);
    return HgComment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      time: (json['time'] ?? json['created_at'])?.toString() ?? '',
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      liked: json['liked'] == true,
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      replyId: (json['reply_id'] as num?)?.toInt() ?? 0,
      isPinned: json['is_pinned'] == true,
      ipRegion: json['ip_region']?.toString() ?? '',
      replyList: (json['reply_list'] as List?)
              ?.map(HgComment.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }
}

class HgCommentPage {
  final int ep;
  final List<HgComment> items;
  final HgPagination pagination;

  const HgCommentPage({
    this.ep = 0,
    this.items = const [],
    this.pagination = const HgPagination(),
  });

  factory HgCommentPage.fromJson(dynamic json) {
    if (json is! Map) return const HgCommentPage();
    return HgCommentPage(
      ep: (json['ep'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List?)
              ?.map(HgComment.fromJson)
              .toList(growable: false) ??
          const [],
      pagination: HgPagination.fromJson(json['pagination']),
    );
  }
}

class HgRankItem {
  final int rank;
  final int videoId;
  final String title;
  final String cover;
  final String cateName;
  final int episodeCount;
  final bool isFinished;
  final String metricLabel;
  final int metricValue;

  const HgRankItem({
    required this.rank,
    required this.videoId,
    required this.title,
    this.cover = '',
    this.cateName = '',
    this.episodeCount = 0,
    this.isFinished = false,
    this.metricLabel = '',
    this.metricValue = 0,
  });

  factory HgRankItem.fromJson(dynamic json) {
    if (json is! Map) return const HgRankItem(rank: 0, videoId: 0, title: '');
    return HgRankItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      videoId: (json['video_id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      cateName: json['cate_name']?.toString() ?? '',
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      isFinished: json['is_finished'] == true,
      metricLabel: json['metric_label']?.toString() ?? '',
      metricValue: (json['metric_value'] as num?)?.toInt() ?? 0,
    );
  }
}

class HgUser {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final String avatarColor;
  final String sign;
  final String desc;

  const HgUser({
    required this.id,
    required this.username,
    this.nickname = '',
    this.avatar = '',
    this.avatarColor = '',
    this.sign = '',
    this.desc = '',
  });

  factory HgUser.fromJson(dynamic json) {
    if (json is! Map) return const HgUser(id: 0, username: '');
    return HgUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      avatarColor: json['avatar_color']?.toString() ?? '',
      sign: json['sign']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'avatar': avatar,
        'avatar_color': avatarColor,
        'sign': sign,
        'desc': desc,
      };
}

class HgTagItem {
  final String name;
  final String slug;

  const HgTagItem({required this.name, this.slug = ''});

  factory HgTagItem.fromJson(dynamic json) {
    if (json is! Map) return const HgTagItem(name: '');
    return HgTagItem(
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
    );
  }
}

class HgTagGroup {
  final String name;
  final List<HgTagItem> tags;

  const HgTagGroup({required this.name, this.tags = const []});

  factory HgTagGroup.fromJson(dynamic json) {
    if (json is! Map) return const HgTagGroup(name: '');
    return HgTagGroup(
      name: json['name']?.toString() ?? '',
      tags: (json['tags'] as List?)?.map(HgTagItem.fromJson).toList(growable: false) ?? const [],
    );
  }
}

/// 吃瓜帖（HGhubX `Post`）。详情接口额外给 content；视频地址恒空，
/// 要再调 playback 接口拿（可能多段）。
class HgPost {
  final int id;
  final String title;
  final String desc;
  final String content;
  final String cover;
  final List<String> tags;
  final int hot;
  final String videoUrl;
  final int videoId;
  final HgAuthor? author;
  final int likeCount;
  final int commentCount;
  final int collectCount;
  final int shareCount;
  final String createdAt;

  const HgPost({
    required this.id,
    required this.title,
    this.desc = '',
    this.content = '',
    this.cover = '',
    this.tags = const [],
    this.hot = 0,
    this.videoUrl = '',
    this.videoId = 0,
    this.author,
    this.likeCount = 0,
    this.commentCount = 0,
    this.collectCount = 0,
    this.shareCount = 0,
    this.createdAt = '',
  });

  factory HgPost.fromJson(dynamic json) {
    if (json is! Map) return const HgPost(id: 0, title: '');
    final counts = json['counts'];
    int count(String k) => counts is Map ? (counts[k] as num?)?.toInt() ?? 0 : 0;
    return HgPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      desc: (json['desc'] ?? json['description'])?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      tags: (json['tags'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      hot: (json['hot'] as num?)?.toInt() ?? 0,
      videoUrl: json['video_url']?.toString() ?? '',
      videoId: (json['video_id'] as num?)?.toInt() ?? 0,
      author: json['author'] == null ? null : HgAuthor.fromJson(json['author']),
      likeCount: count('like'),
      commentCount: count('comment'),
      collectCount: count('collect'),
      shareCount: count('share'),
      createdAt:
          (json['publish_time'] ?? json['created_at'])?.toString() ?? '',
    );
  }
}

/// 吃瓜帖分类（/api/site/categories/post → data.items）。
class HgPostCategory {
  final int id;
  final String name;
  final String route;
  final String intro;

  const HgPostCategory({
    required this.id,
    required this.name,
    this.route = '',
    this.intro = '',
  });

  factory HgPostCategory.fromJson(dynamic json) {
    if (json is! Map) return const HgPostCategory(id: 0, name: '');
    return HgPostCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      intro: json['intro']?.toString() ?? '',
    );
  }
}

/// 专题（/api/topics → data.items）。
class HgTopic {
  final int id;
  final String title;
  final String slug;
  final String cover;
  final String intro;
  final int videoCount;

  const HgTopic({
    required this.id,
    required this.title,
    this.slug = '',
    this.cover = '',
    this.intro = '',
    this.videoCount = 0,
  });

  factory HgTopic.fromJson(dynamic json) {
    if (json is! Map) return const HgTopic(id: 0, title: '');
    return HgTopic(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      intro: json['intro']?.toString() ?? '',
      videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 专题详情（/api/topics/{slug} → {topic, videos, related}）。
class HgTopicDetail {
  final HgTopic topic;
  final HgPaged<HgVideoCard> videos;
  final List<HgTopic> related;

  const HgTopicDetail({
    required this.topic,
    required this.videos,
    this.related = const [],
  });

  factory HgTopicDetail.fromJson(dynamic json) {
    if (json is! Map) {
      return HgTopicDetail(
        topic: const HgTopic(id: 0, title: ''),
        videos: HgPaged(items: const [], pagination: const HgPagination()),
      );
    }
    return HgTopicDetail(
      topic: HgTopic.fromJson(json['topic']),
      videos: HgPaged(
        items: (json['videos'] is Map
                ? (json['videos']['items'] as List? ?? const [])
                : const [])
            .map(HgVideoCard.fromJson)
            .toList(growable: false),
        pagination: HgPagination.fromJson(
            json['videos'] is Map ? json['videos']['pagination'] : null),
      ),
      related: (json['related'] as List?)
              ?.map(HgTopic.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }
}

/// 用户主页（/api/users/{id} + /api/users/{id}/stats 合并）。
class HgUserProfile {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final String avatarColor;
  final String sign;
  final String desc;
  final int followers;
  final int following;
  final int likeCount;
  final int videoCount;
  final int postCount;

  const HgUserProfile({
    required this.id,
    required this.username,
    this.nickname = '',
    this.avatar = '',
    this.avatarColor = '',
    this.sign = '',
    this.desc = '',
    this.followers = 0,
    this.following = 0,
    this.likeCount = 0,
    this.videoCount = 0,
    this.postCount = 0,
  });

  factory HgUserProfile.fromJson(dynamic profile, dynamic stats) {
    if (profile is! Map) {
      return const HgUserProfile(id: 0, username: '');
    }
    return HgUserProfile(
      id: (profile['id'] as num?)?.toInt() ?? 0,
      username: profile['username']?.toString() ?? '',
      nickname: profile['nickname']?.toString() ?? '',
      avatar: profile['avatar']?.toString() ?? '',
      avatarColor: profile['avatar_color']?.toString() ?? '',
      sign: profile['sign']?.toString() ?? '',
      desc: profile['desc']?.toString() ?? '',
      followers:
          stats is Map ? (stats['followers'] as num?)?.toInt() ?? 0 : 0,
      following:
          stats is Map ? (stats['following'] as num?)?.toInt() ?? 0 : 0,
      likeCount:
          stats is Map ? (stats['like_count'] as num?)?.toInt() ?? 0 : 0,
      videoCount:
          stats is Map ? (stats['video_count'] as num?)?.toInt() ?? 0 : 0,
      postCount: stats is Map ? (stats['post_count'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  String get displayName => nickname.isNotEmpty ? nickname : username;
}

/// 1万 → 1w 风格的中文缩写（HGhubX `fmt` 的移植）。
String hgFmtCount(num? n) {
  final v = n ?? 0;
  if (v >= 100000000) {
    final s = (v / 100000000).toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}亿';
  }
  if (v >= 10000) {
    final s = (v / 10000).toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
  }
  if (v == v.truncateToDouble()) {
    return v.truncate().toString();
  }
  return v.toString();
}
