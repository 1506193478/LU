/// HG 短剧·发现页：搜索 / 分类 / 排行。
///
/// 从 Feed 顶栏进入。卡片点击 → 以该视频为起点打开竖滑流。

library;

import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_api.dart';
import 'package:XL/modules/hg/hg_models.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_post_page.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_feed_page.dart';

class HgDiscoverPage extends StatefulWidget {
  const HgDiscoverPage({super.key});

  @override
  State<HgDiscoverPage> createState() => _HgDiscoverPageState();
}

class _HgDiscoverPageState extends State<HgDiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          tabs: const [Tab(text: '分类'), Tab(text: '吃瓜'), Tab(text: '专题'), Tab(text: '排行')],
        ),
        actions: [
          IconButton(
            tooltip: '切换线路',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => _openLineSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _openSearch(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CategoryPane(),
          _PostsPane(),
          _TopicsPane(),
          _RankPane(),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _HgSearchPage()),
    );
  }

  /// 线路切换（三期线路管理的手机端最小形态）：固定线路列表 + 当前高亮。
  ///
  /// 会话按线路 origin 绑定，切换后需要重新登录——弹层里明确提示。
  void _openLineSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var current = HgNet.base;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择线路', style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      '登录状态按线路保存，切换后需要重新登录。',
                      style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                            color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 10),
                    RadioGroup<String>(
                      groupValue: current,
                      onChanged: (v) {
                        if (v == null || v == current) return;
                        HgNet.setBase(v);
                        setSheetState(() => current = v);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已切换到线路 $v')),
                          );
                        }
                      },
                      child: Column(
                        children: [
                          for (final (name, url) in kHgFixedLines)
                            RadioListTile<String>(
                              value: url,
                              title: Text(name),
                              subtitle: Text(url.replaceFirst('https://', '')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/* ═════════════════════════ 分类 ═════════════════════════ */

class _CategoryPane extends StatefulWidget {
  const _CategoryPane();

  @override
  State<_CategoryPane> createState() => _CategoryPaneState();
}

class _CategoryPaneState extends State<_CategoryPane>
    with AutomaticKeepAliveClientMixin {
  List<HgTagGroup> _groups = [];
  String? _selectedTag;
  String _sort = 'latest';
  final List<HgVideoCard> _items = [];
  int _page = 0;
  int _pages = 1;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final data = await HgApi.tags();
      if (!mounted) return;
      setState(() {
        _groups = data;
        // 默认选第一个标签，进来就有内容。
        for (final g in data) {
          if (g.tags.isNotEmpty) {
            _selectedTag = g.tags.first.name;
            break;
          }
        }
      });
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _reload() async {
    if (_selectedTag == null) return;
    setState(() {
      _items.clear();
      _page = 0;
      _pages = 1;
      _error = null;
      _loading = true;
    });
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    if (_loading || _selectedTag == null || page > _pages) return;
    _loading = true;
    try {
      final paged =
          await HgApi.tagVideos(_selectedTag!, page: page, size: 30);
      if (!mounted) return;
      setState(() {
        _page = page;
        _pages = paged.pagination.pages < 1 ? 1 : paged.pagination.pages;
        _items.addAll(paged.items);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (page == 1) _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items.isEmpty) {
      return _ErrorRetry(message: _error!, onRetry: _loadTags);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
          _loadPage(_page + 1);
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _TagChips(
              groups: _groups,
              selected: _selectedTag,
              sort: _sort,
              onSelect: (tag) {
                if (tag == _selectedTag) return;
                setState(() => _selectedTag = tag);
                _reload();
              },
              onSort: (sort) {
                if (sort == _sort) return;
                setState(() => _sort = sort);
                _reload();
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    HgVideoGridCard(card: _items[i], onOpen: _open),
                childCount: _items.length,
              ),
            ),
          ),
          if (_loading && _items.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4)),
              ),
            ),
        ],
      ),
    );
  }

  void _open(HgVideoCard card) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HgFeedPage(startVideoId: card.id),
    ));
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips({
    required this.groups,
    required this.selected,
    required this.sort,
    required this.onSelect,
    required this.onSort,
  });

  final List<HgTagGroup> groups;
  final String? selected;
  final String sort;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSort;

  static const sorts = <(String, String)>[
    ('latest', '最近更新'),
    ('hot_window', '当前热播'),
    ('random', '精选推荐'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in sorts)
                ChoiceChip(
                  label: Text(label),
                  selected: sort == value,
                  onSelected: (_) => onSort(value),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(group.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final tag in group.tags)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tag.name),
                      selected: selected == tag.name,
                      onSelected: (_) => onSelect(tag.name),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/* ═════════════════════════ 吃瓜 ═════════════════════════ */

class _PostsPane extends StatefulWidget {
  const _PostsPane();

  @override
  State<_PostsPane> createState() => _PostsPaneState();
}

class _PostsPaneState extends State<_PostsPane>
    with AutomaticKeepAliveClientMixin {
  List<HgPostCategory> _categories = [];
  String _route = '';
  String _sort = 'latest';
  final List<HgPost> _items = [];
  int _page = 0;
  int _pages = 1;
  bool _loading = false;
  bool _initialized = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await HgApi.postCategories();
      if (!mounted) return;
      setState(() {
        _categories = data;
        _route = data.isNotEmpty ? data.first.route : '';
      });
      await _reload();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _pages = 1;
      _error = null;
      _loading = true;
    });
    await _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    if (_loading || page > _pages) return;
    _loading = true;
    try {
      final HgPaged<HgPost> paged;
      if (_route.isEmpty) {
        paged = await HgApi.posts(page: page, size: 20, sort: _sort);
      } else {
        paged = await HgApi.postCategory(_route, page: page, size: 20, sort: _sort);
      }
      if (!mounted) return;
      setState(() {
        _page = page;
        _pages = paged.pagination.pages < 1 ? 1 : paged.pagination.pages;
        _items.addAll(paged.items);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (page == 1) _error = e.toString();
        });
      }
    }
  }

  void _open(HgPost post) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HgPostPage(postId: post.id, post: post),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _items.isEmpty && !_initialized) {
      return _ErrorRetry(message: _error!, onRetry: _loadCategories);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
          _loadPage(_page + 1);
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PostChips(
              categories: _categories,
              route: _route,
              sort: _sort,
              onSelect: (route) {
                if (route == _route) return;
                setState(() => _route = route);
                _reload();
              },
              onSort: (sort) {
                if (sort == _sort) return;
                setState(() => _sort = sort);
                _reload();
              },
            ),
          ),
          if (_error != null && _items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: FilledButton.tonal(onPressed: _reload, child: const Text('重试')),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _PostTile(post: _items[i], onOpen: _open),
                  childCount: _items.length,
                ),
              ),
            ),
          if (_loading && _items.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostChips extends StatelessWidget {
  const _PostChips({
    required this.categories,
    required this.route,
    required this.sort,
    required this.onSelect,
    required this.onSort,
  });

  final List<HgPostCategory> categories;
  final String route;
  final String sort;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSort;

  static const sorts = <(String, String)>[
    ('latest', '最新'),
    ('hot', '最热'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in sorts)
                ChoiceChip(
                  label: Text(label),
                  selected: sort == value,
                  onSelected: (_) => onSort(value),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.name),
                    selected: route == c.route,
                    onSelected: (_) => onSelect(c.route),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 吃瓜帖列表瓦片：封面缩略 + 标题 + 摘要 + 真实计数行。
class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onOpen});

  final HgPost post;
  final void Function(HgPost) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = HgProxy.coverUrl(post.cover);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onOpen(post),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 74,
                  height: 96,
                  child: cover.isEmpty
                      ? Container(color: theme.colorScheme.surfaceContainerHighest)
                      : Image.network(cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              color: theme.colorScheme.surfaceContainerHighest)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (post.desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(post.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.favorite_outline_rounded,
                            size: 14, color: Color(0xFFFF4D67)),
                        const SizedBox(width: 3),
                        Text(hgFmtCount(post.likeCount),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 10),
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 14, color: Color(0xFF53B7FF)),
                        const SizedBox(width: 3),
                        Text(hgFmtCount(post.commentCount),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 10),
                        const Icon(Icons.star_outline_rounded,
                            size: 14, color: Color(0xFFFFC53A)),
                        const SizedBox(width: 3),
                        Text(hgFmtCount(post.collectCount),
                            style: const TextStyle(fontSize: 12)),
                        const Spacer(),
                        if (post.author?.name.isNotEmpty == true)
                          Text(post.author!.name,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ═════════════════════════ 专题 ═════════════════════════ */

class _TopicsPane extends StatefulWidget {
  const _TopicsPane();

  @override
  State<_TopicsPane> createState() => _TopicsPaneState();
}

class _TopicsPaneState extends State<_TopicsPane>
    with AutomaticKeepAliveClientMixin {
  List<HgTopic> _topics = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await HgApi.topics();
      if (mounted) {
        setState(() {
          _topics = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _open(HgTopic topic) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _HgTopicDetailPage(slug: topic.slug, title: topic.title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorRetry(message: _error!, onRetry: _load);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: _topics.length,
      itemBuilder: (context, i) => _TopicCard(topic: _topics[i], onOpen: _open),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onOpen});

  final HgTopic topic;
  final void Function(HgTopic) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = HgProxy.coverUrl(topic.cover);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onOpen(topic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover.isEmpty
                      ? Container(color: theme.colorScheme.surfaceContainerHighest)
                      : Image.network(cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              color: theme.colorScheme.surfaceContainerHighest)),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${hgFmtCount(topic.videoCount)}部',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (topic.intro.isNotEmpty)
            Text(topic.intro,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _HgTopicDetailPage extends StatefulWidget {
  const _HgTopicDetailPage({required this.slug, required this.title});

  final String slug;
  final String title;

  @override
  State<_HgTopicDetailPage> createState() => _HgTopicDetailPageState();
}

class _HgTopicDetailPageState extends State<_HgTopicDetailPage> {
  HgTopicDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await HgApi.topic(widget.slug);
      if (mounted) {
        setState(() {
          _detail = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : _error != null && detail == null
              ? _ErrorRetry(message: _error!, onRetry: _load)
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: detail!.videos.items.length,
                  itemBuilder: (context, i) => HgVideoGridCard(
                    card: detail.videos.items[i],
                    onOpen: (card) {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => HgFeedPage(startVideoId: card.id),
                      ));
                    },
                  ),
                ),
    );
  }
}

/* ═════════════════════════ 排行 ═════════════════════════ */

class _RankPane extends StatefulWidget {
  const _RankPane();

  @override
  State<_RankPane> createState() => _RankPaneState();
}

class _RankPaneState extends State<_RankPane>
    with AutomaticKeepAliveClientMixin {
  static const kinds = <(String, String)>[
    ('hot', '热度榜'),
    ('recommend', '推荐榜'),
    ('potential', '潜力榜'),
  ];
  String _kind = 'hot';
  List<HgRankItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await HgApi.rank(_kind);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              for (final (value, label) in kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _kind == value,
                    onSelected: (_) {
                      setState(() => _kind = value);
                      _load();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? _ErrorRetry(message: _error!, onRetry: _load)
              : _loading && _items.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: SizedBox(
                            width: 46,
                            height: 62,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: HgProxy.coverUrl(item.cover).isEmpty
                                  ? Container(color: Colors.black12)
                                  : Image.network(
                                      HgProxy.coverUrl(item.cover),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          Container(color: Colors.black12),
                                    ),
                            ),
                          ),
                          title: Text(
                            '${i + 1}. ${item.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item.cateName} · ${item.episodeCount}集 · ${item.metricLabel} ${hgFmtCount(item.metricValue)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) =>
                                  HgFeedPage(startVideoId: item.videoId),
                            ));
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/* ═════════════════════════ 搜索 ═════════════════════════ */

class _HgSearchPage extends StatefulWidget {
  const _HgSearchPage();

  @override
  State<_HgSearchPage> createState() => _HgSearchPageState();
}

class _HgSearchPageState extends State<_HgSearchPage> {
  final TextEditingController _input = TextEditingController();
  final List<HgVideoCard> _results = [];
  final List<HgPost> _postResults = [];
  final Set<int> _searched = HashSet<int>();
  /// 搜索范围：短剧 / 吃瓜帖（上游接口必须显式 type=post）。
  String _scope = 'video';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      // 中文输入法组合期间不搜索。
      if (_input.text.isEmpty) {
        setState(() {
          _results.clear();
          _postResults.clear();
        });
      }
    });
  }

  Future<void> _search() async {
    final q = _input.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_scope == 'post') {
        final posts = await HgApi.searchPosts(q, page: 1, size: 40);
        if (!mounted) return;
        setState(() {
          _postResults
            ..clear()
            ..addAll(posts);
          _results.clear();
          _searched.add(q.hashCode);
          _loading = false;
        });
      } else {
        final items = await HgApi.search(q, page: 1, size: 40);
        if (!mounted) return;
        setState(() {
          _results
            ..clear()
            ..addAll(items);
          _postResults.clear();
          _searched.add(q.hashCode);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _input,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '搜索短剧',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final (value, label) in const [('video', '短剧'), ('post', '吃瓜帖')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _scope == value,
                      onSelected: (_) {
                        setState(() => _scope = value);
                        if (_input.text.trim().isNotEmpty) _search();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : _error != null
                    ? _ErrorRetry(message: _error!, onRetry: _search)
                    : _scope == 'post'
                        ? _postResults.isEmpty
                            ? Center(
                                child: Text('输入关键词开始搜索吃瓜帖',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _postResults.length,
                                itemBuilder: (context, i) => _PostTile(
                                  post: _postResults[i],
                                  onOpen: (post) {
                                    Navigator.of(context)
                                        .push(MaterialPageRoute<void>(
                                      builder: (_) =>
                                          HgPostPage(postId: post.id, post: post),
                                    ));
                                  },
                                ),
                              )
                        : _results.isEmpty
                            ? Center(
                                child: Text('输入关键词开始搜索',
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 130,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.62,
                                ),
                                itemCount: _results.length,
                                itemBuilder: (context, i) => HgVideoGridCard(
                                  card: _results[i],
                                  onOpen: (card) {
                                    Navigator.of(context)
                                        .push(MaterialPageRoute<void>(
                                      builder: (_) =>
                                          HgFeedPage(startVideoId: card.id),
                                    ));
                                  },
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

/* ═════════════════════════ 共用 ═════════════════════════ */

/// 网格视频卡：封面（本地代理解密）+ 标题 + 集数/评分。
class HgVideoGridCard extends StatelessWidget {
  const HgVideoGridCard({super.key, required this.card, required this.onOpen});

  final HgVideoCard card;
  final void Function(HgVideoCard) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = HgProxy.coverUrl(card.cover);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover.isEmpty
                      ? Container(color: theme.colorScheme.surfaceContainerHighest)
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              color:
                                  theme.colorScheme.surfaceContainerHighest),
                        ),
                  if (card.score > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          card.score.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Color(0xFFFFB03A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${card.episodeCount > 0 ? card.episodeCount : card.totalEpisodes}集',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
