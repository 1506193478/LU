/// HG 业务 API（从 HGhubX `src-tauri/src/api.rs` + `src/api.ts` 移植）。
///
/// 所有方法名和上游注释保持一致，方便两边对照。
library;

import 'package:XL/modules/hg/hg_lines.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_session.dart';

class HgApi {
  HgApi._();

  /// 严格安全模式（net.rs 的 strict_security 分支）：镜像线路仅供
  /// 游客浏览，登录/注册必须走固定线路或被发布页收录的镜像。
  static Future<void> _verifyAuthOrigin(String origin) async {
    if (!HgStore.prefs.strictSecurity) return;
    if (isFixedLine(origin) || isTrustedMirror(origin)) return;
    try {
      await mirrors(); // 刷新可信集合（带 30 秒缓存语义的上游等价物）。
    } catch (_) {}
    if (!isFixedLine(origin) && !isTrustedMirror(origin)) {
      throw const HgApiError(
          '镜像线路仅供游客浏览；登录/注册请切换到固定线路');
    }
  }

  /* ── 会话 ── */


  /// 用户名密码登录。成功后会话写入本地（按线路绑定）。
  static Future<HgUser> login(String username, String password) async {
    final origin = HgNet.base;
    await _verifyAuthOrigin(origin);
    final data = await HgNet.edge(
      'POST',
      '/api/account/loginByPassword',
      body: {'username': username, 'password': password},
    );
    return _saveAuth(origin, data);
  }

  static Future<HgUser> register(
    String username,
    String password,
    String email,
  ) async {
    final origin = HgNet.base;
    await _verifyAuthOrigin(origin);
    final body = <String, dynamic>{
      'username': username,
      'password': password,
      'confirm_password': password,
    };
    if (email.trim().isNotEmpty) body['email'] = email.trim();
    final data = await HgNet.edge(
      'POST',
      '/api/account/registerByPassword',
      body: body,
    );
    return _saveAuth(origin, data);
  }

  static Future<void> logout() async {
    try {
      await HgNet.edge('POST', '/api/account/logout');
    } catch (_) {
      // 就算上游登出失败，本地会话也要清。
    }
    await HgStore.clearSession();
  }

  static Future<HgUser?> me() async {
    final origin = HgNet.base;
    final data = await HgNet.edge('GET', '/api/account/me');
    final user = HgUser.fromJson(data);
    if (HgStore.session.loggedIn && HgStore.session.origin == origin) {
      await HgStore.setSession(origin, HgStore.session.token, user);
    }
    return user;
  }

  static HgUser _saveAuth(String origin, dynamic data) {
    if (data is! Map) throw const HgApiError('登录返回缺少 token');
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) throw const HgApiError('登录返回缺少 token');
    final user = data['user'] == null ? null : HgUser.fromJson(data['user']);
    // 异步存，不阻塞返回。
    HgStore.setSession(origin, token, user);
    return user ?? const HgUser(id: 0, username: '');
  }

  /* ── 列表 ── */

  /// 竖滑流 / 推荐流。
  static Future<HgPaged<HgVideoCard>> feed({int page = 1, int size = 20}) =>
      _videos('/api/videos?page=$page&size=$size');

  static Future<HgPaged<HgVideoCard>> category(
    String cate, {
    int page = 1,
    int size = 20,
    String? sort,
  }) {
    final s = (sort != null && sort.trim().isNotEmpty) ? '&sort=$sort' : '';
    return _videos('/api/videos/category/$cate?page=$page&size=$size$s');
  }

  static Future<HgPaged<HgVideoCard>> tagVideos(
    String tag, {
    int page = 1,
    int size = 20,
  }) {
    final encoded = Uri.encodeComponent(tag);
    return _videos('/api/videos/tag/$encoded?page=$page&size=$size');
  }

  static Future<HgPaged<HgVideoCard>> following({int page = 1, int size = 20}) async {
    final data = await HgNet.edge(
      'GET',
      '/api/videos/following?page=$page&size=$size',
      authed: true,
    );
    return _toPaged(data);
  }

  /// 全站搜索（kind 为空搜短剧，'post' 搜吃瓜帖）。
  static Future<List<HgVideoCard>> search(
    String q, {
    int page = 1,
    int size = 20,
    String? kind,
  }) async {
    final encoded = Uri.encodeComponent(q);
    final scope = kind == 'post' ? '&type=post' : (kind == 'video' ? '&type=video' : '');
    final data = await HgNet.edge(
      'GET',
      '/api/search?q=$encoded&page=$page&size=$size$scope',
    );
    if (data is! Map) return const [];
    return _cardList(data['items'] ?? data);
  }

  static Future<List<HgRankItem>> rank(String kind) async {
    final k = (kind == 'recommend' || kind == 'potential') ? kind : 'hot';
    final data = await HgNet.edge('GET', '/api/ranks/$k');
    if (data is! Map) return const [];
    return (data['items'] as List? ?? const [])
        .map(HgRankItem.fromJson)
        .toList(growable: false);
  }

  /* ── 详情 / 播放 ── */

  static Future<HgDetail> video(int id) async {
    final data = await HgNet.edge('GET', '/api/videos/$id');
    return HgDetail.fromJson(data);
  }

  /// 取播放地址：优先新接口 playback，退回旧 play 接口（api.rs 的 api_play）。
  static Future<HgPlayInfo> play(int id, int ep) async {
    dynamic primary;
    var primaryError = '';
    try {
      primary = await HgNet.edge(
        'POST',
        '/api/videos/$id/episodes/$ep/playback',
        body: {},
      );
    } on HgApiError catch (e) {
      primaryError = e.message;
    }
    final info = HgPlayInfo.fromJson(primary);
    if (info.videoUrl.isNotEmpty) return info;
    try {
      final legacy = await HgNet.edge(
        'GET',
        '/api/videos/$id/play?ep=$ep&page_texts=0',
      );
      final legacyInfo = HgPlayInfo.fromJson(legacy);
      if (legacyInfo.videoUrl.isNotEmpty) return legacyInfo;
    } catch (_) {
      // 用新接口的错误兜底。
    }
    if (primaryError.isNotEmpty) throw HgApiError(primaryError);
    return info;
  }

  /* ── 评论 / 互动 ── */

  static Future<HgCommentPage> comments(
    int id,
    int ep, {
    int page = 1,
    int size = 20,
  }) async {
    final data = await HgNet.edge(
      'GET',
      '/api/videos/$id/comments?ep=$ep&page=$page&size=$size',
    );
    return HgCommentPage.fromJson(data);
  }

  static Future<void> commentSend(
    int id,
    int ep,
    String text, {
    int? replyId,
  }) async {
    final body = <String, dynamic>{'text': text};
    final path = (replyId != null && replyId > 0)
        ? '/api/videos/$id/comments'
        : '/api/videos/$id/comments?ep=$ep';
    if (replyId != null && replyId > 0) body['reply_id'] = replyId;
    await HgNet.edge('POST', path, body: body, authed: true);
  }

  /// 点赞/取消。返回上游响应（通常带最新计数）。
  static Future<dynamic> like(int id, int ep, bool on) => HgNet.edge(
        on ? 'POST' : 'DELETE',
        '/api/videos/$id/like?ep=$ep',
        authed: true,
      );

  static Future<dynamic> collect(int id, bool on) => HgNet.edge(
        on ? 'POST' : 'DELETE',
        '/api/videos/$id/collect',
        authed: true,
      );

  static Future<dynamic> follow(int uid, bool on) => HgNet.edge(
        on ? 'POST' : 'DELETE',
        '/api/users/$uid/follow',
        authed: true,
      );

  /// 相关推荐。
  static Future<List<HgVideoCard>> related(int id) async {
    final data = await HgNet.edge('GET', '/api/videos/$id/related');
    if (data is! Map) return const [];
    return _cardList(data['items']);
  }

  static Future<HgPaged<HgVideoCard>> userVideos(
    int id, {
    int page = 1,
    int size = 20,
  }) =>
      _videos('/api/videos/user/$id?page=$page&size=$size');

  /// 标签分组（/api/tags → data.categories[]）。
  static Future<List<HgTagGroup>> tags() async {
    final data = await HgNet.edge('GET', '/api/tags');
    if (data is! Map) return const [];
    final categories = data['categories'];
    if (categories is! List) return const [];
    return categories.map(HgTagGroup.fromJson).toList(growable: false);
  }

  /// 热搜榜（解析官网搜索页，返回 [{video_id, title, plays}]）。
  static Future<List<(int, String, String)>> searchHot() async {
    final data = await HgNet.edge('GET', '/api/search_hot');
    if (data is! Map) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    return [
      for (final it in items)
        if (it is Map)
          (
            (it['video_id'] as num?)?.toInt() ?? 0,
            it['title']?.toString() ?? '',
            it['plays']?.toString() ?? '',
          ),
    ];
  }

  /* ── 原创视频 ── */

  /// 原创（api_original_videos）：`all` 走 is_original=1 全量，
  /// 其余走对应分类加 is_original=1 过滤。
  static Future<HgPaged<HgVideoCard>> originalVideos(
    String cate, {
    int page = 1,
    int size = 20,
    String? sort,
  }) {
    final s = (sort != null && sort.trim().isNotEmpty) ? '&sort=$sort' : '';
    final path = cate == 'all'
        ? '/api/videos?is_original=1&page=$page&size=$size$s'
        : '/api/videos/category/$cate?is_original=1&page=$page&size=$size$s';
    return _videos(path);
  }

  /* ── 专题 ── */

  static Future<List<HgTopic>> topics() async {
    final data = await HgNet.edge('GET', '/api/topics?size=100');
    if (data is! Map) return const [];
    return (data['items'] as List? ?? const [])
        .map(HgTopic.fromJson)
        .toList(growable: false);
  }

  static Future<HgTopicDetail> topic(String slug) async {
    final encoded = Uri.encodeComponent(slug);
    final data = await HgNet.edge('GET', '/api/topics/$encoded');
    return HgTopicDetail.fromJson(data);
  }

  /* ── 吃瓜帖 ── */

  /// 帖子流（/api/posts）。sort 可空；上游常传 latest。
  static Future<HgPaged<HgPost>> posts({
    int page = 1,
    int size = 20,
    String? sort,
  }) =>
      _postPaged('/api/posts?page=$page&size=$size${_sortParam(sort)}');

  static Future<HgPost> post(int id) async {
    final data = await HgNet.edge('GET', '/api/posts/$id');
    return HgPost.fromJson(data);
  }

  /// 帖子视频地址：详情里 video_url 恒空，由 playback 下发（可能多段）。
  static Future<List<String>> postPlayback(int id) async {
    final data = await HgNet.edge(
      'POST',
      '/api/posts/$id/playback',
      body: {},
    );
    if (data is! Map) return const [];
    final videos = data['videos'];
    if (videos is! List) return const [];
    return [
      for (final v in videos)
        if (v is Map && v['url']?.toString().isNotEmpty == true)
          v['url'].toString(),
    ];
  }

  static Future<dynamic> postLike(int id, bool on) => HgNet.edge(
        on ? 'POST' : 'DELETE',
        '/api/posts/$id/like',
        authed: true,
      );

  static Future<dynamic> postCollect(int id, bool on) => HgNet.edge(
        on ? 'POST' : 'DELETE',
        '/api/posts/$id/collect',
        authed: true,
      );

  /// 帖子评论（上游只读，没有发帖评论的接口）。
  static Future<HgCommentPage> postComments(
    int id, {
    int page = 1,
    int size = 20,
  }) async {
    final data = await HgNet.edge(
      'GET',
      '/api/posts/$id/comments?page=$page&size=$size',
    );
    return HgCommentPage.fromJson(data);
  }

  static Future<List<HgPostCategory>> postCategories() async {
    final data = await HgNet.edge('GET', '/api/site/categories/post');
    if (data is! Map) return const [];
    return (data['items'] as List? ?? const [])
        .map(HgPostCategory.fromJson)
        .toList(growable: false);
  }

  static Future<HgPaged<HgPost>> postCategory(
    String route, {
    int page = 1,
    int size = 20,
    String? sort,
  }) {
    final encoded = Uri.encodeComponent(route);
    return _postPaged(
      '/api/posts/category/$encoded?page=$page&size=$size${_sortParam(sort)}',
    );
  }

  /// 搜吃瓜帖（必须显式 type=post，上游 issue #34）。
  static Future<List<HgPost>> searchPosts(
    String q, {
    int page = 1,
    int size = 20,
  }) async {
    final encoded = Uri.encodeComponent(q);
    final data = await HgNet.edge(
      'GET',
      '/api/search?q=$encoded&page=$page&size=$size&type=post',
    );
    if (data is! Map) return const [];
    return _postList(data['items']);
  }

  /* ── 用户主页 ── */

  /// 资料 + 统计合并成一次调用（两个接口，任一失败给空统计）。
  static Future<HgUserProfile> userProfile(int id) async {
    final profile = await HgNet.edge('GET', '/api/users/$id');
    dynamic stats;
    try {
      stats = await HgNet.edge('GET', '/api/users/$id/stats');
    } catch (_) {
      stats = null;
    }
    return HgUserProfile.fromJson(profile, stats);
  }

  /* ── 内部 ── */

  static String _sortParam(String? sort) {
    if (sort == null || sort.trim().isEmpty) return '';
    return '&sort=$sort';
  }

  static Future<HgPaged<HgPost>> _postPaged(String path) async {
    final data = await HgNet.edge('GET', path);
    if (data is! Map) {
      return HgPaged(items: const [], pagination: const HgPagination());
    }
    return HgPaged(
      items: _postList(data['items']),
      pagination: HgPagination.fromJson(data['pagination']),
    );
  }

  static List<HgPost> _postList(dynamic items) {
    if (items is! List) return const [];
    return items.map(HgPost.fromJson).toList(growable: false);
  }

  static Future<HgPaged<HgVideoCard>> _videos(String path) async {
    final data = await HgNet.edge('GET', path);
    return _toPaged(data);
  }

  static HgPaged<HgVideoCard> _toPaged(dynamic data) {
    if (data is! Map) {
      return HgPaged(
        items: const [],
        pagination: const HgPagination(),
      );
    }
    return HgPaged(
      items: _cardList(data['items']),
      pagination: HgPagination.fromJson(data['pagination']),
    );
  }

  static List<HgVideoCard> _cardList(dynamic items) {
    if (items is! List) return const [];
    return items.map(HgVideoCard.fromJson).toList(growable: false);
  }
}
