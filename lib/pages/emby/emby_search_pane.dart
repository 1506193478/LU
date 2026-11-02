import 'dart:async';

import 'package:flutter/material.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_service.dart';

/// Emby「搜索」页签。
///
/// 严格按设计稿：大标题「搜索」→ 右上分段控件（媒体库 / 网盘）→ 灰色圆角
/// 搜索框 → 结果列表。空态是居中的大放大镜 + 「搜索「XX」中的内容」。
///
/// 这个页只搜 Emby 库里的资源，跟首页番剧的搜索是两套逻辑，互不相干。
class EmbySearchPane extends StatefulWidget {
  const EmbySearchPane({
    super.key,
    required this.onOpenDetail,
    required this.onPlay,
  });

  final void Function(EmbyItem item) onOpenDetail;
  final void Function(EmbyItem item) onPlay;

  @override
  State<EmbySearchPane> createState() => _EmbySearchPaneState();
}

class _EmbySearchPaneState extends State<EmbySearchPane> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 0 = 媒体库，1 = 网盘。设计稿是这两个。
  int _scope = 0;

  /// 搜哪台服务器：null = 聚合搜索（所有已添加的都搜）。
  String? _serverId;

  /// 结果条目 → 它来自哪台服务器（聚合搜索后要用它取图、起播）。
  final Map<String, EmbyServer> _origin = <String, EmbyServer>{};

  bool _loading = false;
  String _error = '';
  List<EmbyItem> _results = const <EmbyItem>[];

  /// 已经真正发出去的关键词（用来避免防抖连发重复请求）。
  String _sent = '';

  /// 请求令牌：只认最后一次发出的请求的结果，防止慢请求把新结果覆盖回去。
  int _runToken = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(String keyword, {bool force = false}) async {
    final String text = _normalizeKeyword(keyword);
    // 同一个词不重复发请求（防抖会连发），但 `force` 时无条件重来 ——
    // 这是原来「有时搜不到」的根因：`_sent` 一旦记下就再也不清，第一次
    // 请求失败（切服务器、token 刷新、网络抖动）之后，同样的词再也不会
    // 重新发，页面就一直空着。
    if (!force && text == _sent) return;
    _sent = text;

    if (text.isEmpty) {
      ++_runToken;
      if (!mounted) return;
      setState(() {
        _results = const <EmbyItem>[];
        _loading = false;
        _error = '';
      });
      return;
    }

    final service = EmbyService.instance;
    // 聚合搜索 = 所有已添加的服务器都搜一遍；否则只搜选中的那台。
    final targets = _serverId == null
        ? service.servers
        : service.servers.where((s) => s.id == _serverId).toList();
    if (targets.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '还没有添加 Emby 服务器';
        _results = const <EmbyItem>[];
      });
      return;
    }

    final int token = ++_runToken;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      var merged = await _searchAll(targets, text);
      // 第二轮：库里如果存的是「单集」或者「家庭视频」（网盘同步进来的
      // 往往是 Video），第一轮的类型过滤会把它们全挡掉，看起来就是「搜不到」。
      // 这里放开类型再捞一遍，把单集折回它所属的剧。
      if (merged.isEmpty) {
        merged = await _searchAll(targets, text, includeEpisodes: true);
      }
      if (!mounted || token != _runToken) return;
      setState(() {
        _results = merged;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted || token != _runToken) return;
      // 失败后清掉去重标记，按回车/重新输入同一个词还能再试。
      _sent = '';
      setState(() {
        _loading = false;
        _error = '搜索失败：${e.toString().split('\n').first}';
        _results = const <EmbyItem>[];
      });
    }
  }

  /// 去掉全角空格、首尾空白 —— 从别处复制过来的关键词常带这些，Emby 的
  /// `SearchTerm` 会当成内容的一部分，于是搜不到。
  static String _normalizeKeyword(String value) => value
      .replaceAll('\u3000', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 对每台服务器发一次搜索请求，合并结果并记下来源服务器。
  Future<List<EmbyItem>> _searchAll(
    List<EmbyServer> targets,
    String keyword, {
    bool includeEpisodes = false,
  }) async {
    final service = EmbyService.instance;
    final lists = await Future.wait(targets.map((s) async {
      try {
        return await service.clientFor(s).search(
              userId: s.userId,
              keyword: keyword,
              includeItemTypes: includeEpisodes
                  ? 'Movie,Series,BoxSet,Video,Episode'
                  : 'Movie,Series,BoxSet,Video',
            );
      } catch (_) {
        // 某台挂了不影响别的。
        return <EmbyItem>[];
      }
    }));

    final origin = <String, EmbyServer>{};
    final merged = <EmbyItem>[];
    final seen = <String>{};
    for (var i = 0; i < targets.length; i++) {
      for (final item in lists[i]) {
        // 只出「剧」不出「集」：搜「仙逆」应该给一部剧，不是 194 个单集。
        if (item.isEpisode) continue;
        if (!seen.add(item.id)) continue;
        merged.add(item);
        origin[item.id] = targets[i];
      }
    }
    _origin
      ..clear()
      ..addAll(origin);
    return merged;
  }

  void _onChanged(String value) {
    // 输入停顿 350ms 才真的去搜，避免打一个字打一次接口。
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value.trim()));
    if (mounted) setState(() {});
  }

  String get _scopeName => _scope == 0 ? '所有媒体库' : '网盘';

  /// 左上角那个蓝色图标按钮：点开选「聚合搜索」或某一台服务器。
  Widget _serverPickerButton() {
    return GestureDetector(
      onTap: _openServerMenu,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF0A84FF).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.dns_rounded, size: 17, color: Color(0xFF0A84FF)),
      ),
    );
  }

  Future<void> _openServerMenu() async {
    final servers = EmbyService.instance.servers;
    await showPvMenu<Object>(
      context: context,
      position: const RelativeRect.fromLTRB(18, 66, 120, 220),
      minWidth: 230,
      items: [
        PvMenuItem(
          '聚合搜索',
          checked: _serverId == null,
          onTap: () => setState(() {
            _serverId = null;
            _sent = '';
            _results = const <EmbyItem>[];
          }),
        ),
        if (servers.isNotEmpty) const PvMenuItem.divider(),
        for (final s in servers)
          PvMenuItem(
            s.name,
            checked: _serverId == s.id,
            onTap: () => setState(() {
              _serverId = s.id;
              _sent = '';
              _results = const <EmbyItem>[];
            }),
          ),
      ],
    );
    if (mounted) {
      final keyword = _controller.text.trim();
      if (keyword.isNotEmpty) _run(keyword, force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final keyword = _controller.text.trim();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 顶行：左边是「搜哪台服务器」的按钮，中间偏右是分段控件。
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Row(
                children: [
                  _serverPickerButton(),
                  Expanded(
                    child: Center(
                      child: _ScopeSwitch(
                        index: _scope,
                        onChanged: (i) => setState(() {
                          _scope = i;
                          _sent = '';
                          _results = const <EmbyItem>[];
                          if (keyword.isNotEmpty) _run(keyword, force: true);
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 大标题在控件下面一行，跟截图一致。
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '搜索',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
            // 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFF1F1F4),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 11),
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: dark ? Colors.white38 : const Color(0xFF9A9AA0),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: _onChanged,
                        onSubmitted: (v) => _run(v.trim(), force: true),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜索',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: dark
                                ? Colors.white30
                                : const Color(0xFF9A9AA0),
                          ),
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          _run('');
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: dark
                                ? Colors.white38
                                : const Color(0xFF9A9AA0),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(dark, keyword)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool dark, String keyword) {
    if (_scope == 1) {
      return _EmptyHint(
        dark: dark,
        text: keyword.isEmpty
            ? '搜索「网盘」中的内容'
            : '网盘搜索暂未开放，先搜「媒体库」',
      );
    }
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: dark ? Colors.white54 : const Color(0xFF8A8A90),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _run(_controller.text.trim(), force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (keyword.isEmpty) {
      return _EmptyHint(dark: dark, text: '搜索「$_scopeName」中的内容');
    }
    if (_results.isEmpty) {
      return _EmptyHint(dark: dark, text: '没有找到「$keyword」相关的内容');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        indent: 118,
        color: dark ? Colors.white12 : const Color(0xFFF0F0F3),
      ),
      itemBuilder: (context, i) {
        final item = _results[i];
        final server = _origin[item.id] ?? EmbyService.instance.activeServer;
        return _ResultRow(
          item: item,
          imageUrl: server == null
              ? ''
              : embyImageUrl(
                  serverUrl: server.url,
                  itemId: item.id,
                  accessToken: server.accessToken,
                  maxHeight: 300,
                  tag: item.primaryImageTag,
                ),
          headers: embyAuthHeaders(server),
          dark: dark,
          onTap: () async {
            // 聚合搜索可能搜到别的服务器上的东西，点进去前先切过去，
            // 否则详情页拿的还是当前服务器的图。
            if (server != null &&
                EmbyService.instance.activeServer?.id != server.id) {
              await EmbyService.instance.setActive(server.id);
            }
            if (!mounted) return;
            if (item.isEpisode) {
              widget.onPlay(item);
            } else {
              widget.onOpenDetail(item);
            }
          },
        );
      },
    );
  }
}

/// 右上角的「媒体库 / 网盘」分段控件（设计稿：浅灰底，选中白色带阴影）。
class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final bg = dark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFEDEDF2);

    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 2; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index
                      ? (dark ? Colors.white24 : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: i == index && !dark
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  i == 0 ? '媒体库' : '网盘',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: i == index
                        ? PvColors.subInk(context)
                        : (dark ? Colors.white54 : const Color(0xFF8A8A90)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    final grey = dark ? Colors.white24 : const Color(0xFFC9C9CF);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 66, color: grey),
          const SizedBox(height: 14),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: dark ? Colors.white38 : const Color(0xFFA0A0A6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 结果行：左边 16:9 缩略图，右边标题 + 副标题。
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.imageUrl,
    required this.headers,
    required this.dark,
    required this.onTap,
  });

  final EmbyItem item;
  final String imageUrl;
  final Map<String, String>? headers;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sub = <String>[
      _typeName(item.type),
      if (item.productionYear != null) '${item.productionYear}',
      if (item.isEpisode && item.indexNumber != null) '第 ${item.indexNumber} 集',
      if (item.isSeries && item.childCount != null) '${item.childCount} 集',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 104,
                  height: 60,
                  child: imageUrl.isEmpty
                      ? Container(
                          color: dark ? Colors.white12 : const Color(0xFFECECF1),
                          child: const Icon(Icons.movie_outlined, size: 22),
                        )
                      : EmbyImage(url: imageUrl, headers: headers),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: dark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF8A8A90),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: dark ? Colors.white24 : const Color(0xFFC7C7CC),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _typeName(String type) => switch (type) {
      'Movie' => '电影',
      'Series' => '剧集',
      'Episode' => '单集',
      'BoxSet' => '合集',
      _ => '媒体',
    };
