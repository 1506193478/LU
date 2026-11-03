import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/theme/rex_design.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';

/// 跨库搜索。
///
/// 只搜电影 / 剧集 / 单集，不搜演职员——Emby 的 `SearchTerm` 对人物命中很差，
/// 搜出来一堆无关条目反而干扰。
class EmbySearchPage extends StatefulWidget {
  const EmbySearchPage({super.key});

  @override
  State<EmbySearchPage> createState() => _EmbySearchPageState();
}

class _EmbySearchPageState extends State<EmbySearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  String _keyword = '';
  bool _loading = false;
  String _error = '';
  List<EmbyItem> _results = const [];
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    // 进页面就聚焦：搜索页不聚焦，用户还得先点一下输入框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final keyword = value.trim();
    _debounce?.cancel();
    if (keyword.isEmpty) {
      setState(() {
        _keyword = '';
        _results = const [];
        _loading = false;
        _error = '';
      });
      return;
    }
    // 边打边搜，但别每敲一个字都发一次请求。
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(keyword);
    });
  }

  Future<void> _search(String keyword) async {
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    final int seq = ++_requestSeq;
    setState(() {
      _keyword = keyword;
      _loading = true;
      _error = '';
    });
    try {
      final items = await EmbyService.instance
          .clientFor(server)
          .search(userId: server.userId, keyword: keyword);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      KazumiLogger().w('Emby search: failed', error: e);
      setState(() {
        _loading = false;
        _error = embyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = EmbyService.instance.activeServer;
    final RexPalette p = RexPalette.of(context);
    final double pad = embyPagePadding(context);
    return EmbyPageShell(
      title: '搜索',
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, RexSpace.xs, pad, RexSpace.sm),
            child: Container(
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.circular(RexRadius.control),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onChanged,
                onSubmitted: (value) {
                  final keyword = value.trim();
                  if (keyword.isNotEmpty) _search(keyword);
                },
                textInputAction: TextInputAction.search,
                style: RexText.body.copyWith(color: p.inkPrimary),
                decoration: InputDecoration(
                  hintText: '搜索电影、剧集',
                  hintStyle: RexText.body.copyWith(color: p.inkTertiary),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: p.inkSecondary,
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: p.inkSecondary,
                          ),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: p.accent,
                backgroundColor: p.surfaceSunken,
              ),
            ),
          Expanded(child: _buildResults(context, server)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, EmbyServer? server) {
    final theme = Theme.of(context);
    if (_keyword.isEmpty) {
      return Center(
        child: Text(
          '输入关键词开始搜索',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty && !_loading) {
      return Center(
        child: Text(
          '没有找到「$_keyword」',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (server == null) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        embyIsDesktop(context) ? 24 : 16,
        8,
        embyIsDesktop(context) ? 24 : 16,
        24,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: embyIsDesktop(context) ? 150 : 120,
        mainAxisSpacing: embyIsDesktop(context) ? 18 : 14,
        crossAxisSpacing: embyIsDesktop(context) ? 14 : 10,
        childAspectRatio: 0.56,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return EmbyPosterTile(
          item: item,
          imageUrl: embyImageUrl(
            serverUrl: server.url,
            itemId: item.coverItemId,
            accessToken: server.accessToken,
            maxHeight: 420,
            tag: item.coverTag,
          ),
          headers: embyAuthHeaders(server),
          onTap: () => context.pushNamed('/emby/detail', arguments: item),
        );
      },
    );
  }
}
