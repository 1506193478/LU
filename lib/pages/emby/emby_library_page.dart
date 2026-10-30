import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/services/emby/emby_service.dart';

/// 某个媒体库里的内容（剧集 / 电影）。
class EmbyLibraryPage extends StatefulWidget {
  const EmbyLibraryPage({super.key, required this.library});

  final EmbyLibrary library;

  @override
  State<EmbyLibraryPage> createState() => _EmbyLibraryPageState();
}

class _EmbyLibraryPageState extends State<EmbyLibraryPage> {
  Future<List<EmbyItem>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<List<EmbyItem>> _load() async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) return const [];
    return service.clientFor(server).fetchItems(
          userId: server.userId,
          parentId: widget.library.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text(widget.library.name),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: EmbyFutureView<List<EmbyItem>>(
        future: _future!,
        onRetry: _reload,
        emptyTitle: '这个库是空的',
        emptyMessage: '换个库看看，或者先在 Emby 服务端往这个库里添加内容。',
        isEmpty: (items) => items.isEmpty,
        builder: (context, items) => _ItemGrid(items: items),
      ),
    );
  }
}

class _ItemGrid extends StatelessWidget {
  const _ItemGrid({required this.items});

  final List<EmbyItem> items;

  /// 卡片高度必须自己算准。
  ///
  /// 封面是 [AspectRatio] 而不是 Expanded，格子给矮了会直接报 overflow；
  /// 而字号会跟着系统缩放走，所以文字部分也要按 textScaler 估。
  double _cellExtent(BuildContext context, double cellWidth) {
    final bool neu = isNeuLayout(context);
    final double pad = isDesktopWideLayout(context) ? 10 : 7;
    final double coverWidth = neu ? cellWidth - pad * 2 : cellWidth;
    final scaler = MediaQuery.textScalerOf(context);
    final double textHeight = scaler.scale(24) * 2 + 4 + scaler.scale(16);
    return coverWidth / 0.68 + (neu ? pad * 2 : 0) + 7 + textHeight + 10;
  }

  @override
  Widget build(BuildContext context) {
    final client = EmbyService.instance.activeClient;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double inset = constraints.maxWidth < 600 ? 16 : 28;
        final double usable = constraints.maxWidth - inset * 2;
        final int crossCount = (usable / 168).floor().clamp(2, 8);
        const double spacing = 12;
        final double cellWidth =
            (usable - spacing * (crossCount - 1)) / crossCount;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 14,
            mainAxisExtent: _cellExtent(context, cellWidth),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return EmbyPosterCard(
              imageUrl: client?.imageUrl(
                    item.id,
                    maxHeight: 480,
                    tag: item.primaryImageTag,
                  ) ??
                  '',
              title: item.name,
              subtitle: item.metaLine,
              onTap: () => context.pushNamed('/emby/detail', arguments: item),
            );
          },
        );
      },
    );
  }
}
