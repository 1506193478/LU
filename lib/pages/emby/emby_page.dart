import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/services/emby/emby_service.dart';

/// Emby 入口页：列出当前服务器上的媒体库。
///
/// 没配服务器时不摆一个空网格，而是直接给一张"添加服务器"的引导卡——
/// 这个功能第一次打开必然是这个状态，引导比空态更重要。
class EmbyPage extends StatefulWidget {
  const EmbyPage({super.key});

  @override
  State<EmbyPage> createState() => _EmbyPageState();
}

class _EmbyPageState extends State<EmbyPage> {
  Future<_HomeData>? _future;

  @override
  void initState() {
    super.initState();
    // 首帧前直接赋值，不用 setState：initState 里调 setState 只会把
    // 已经脏掉的树再标一次脏。
    _future = _load();
    // 服务器增删、换账号都会让 revision +1，跟着重新拉一次库列表。
    EmbyService.instance.revision.addListener(_onRevisionChanged);
  }

  @override
  void dispose() {
    EmbyService.instance.revision.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() {
    if (mounted) _reload();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<_HomeData> _load() async {
    final service = EmbyService.instance;
    await service.load();
    final server = service.activeServer;
    if (server == null) {
      return const _HomeData(server: null, libraries: []);
    }
    return _HomeData(
      server: server,
      libraries:
          await service.clientFor(server).fetchLibraries(server.userId),
    );
  }

  Future<void> _openServers() async {
    await context.pushNamed('/emby/servers');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('Emby 媒体库'),
      actions: [
        IconButton(
          tooltip: '服务器设置',
          onPressed: _openServers,
          icon: const Icon(Icons.dns_rounded),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: EmbyFutureView<_HomeData>(
        future: _future!,
        onRetry: _reload,
        builder: (context, data) {
          if (data.server == null) {
            return _NoServerGuide(onAdd: _openServers);
          }
          return _LibraryGrid(
            libraries: data.libraries,
            serverName: data.server!.name,
            onOpen: (library) => context.pushNamed(
              '/emby/library',
              arguments: library,
            ),
          );
        },
      ),
    );
  }
}

/// 首页要同时表达"有没有服务器"和"服务器上有哪些库"。
///
/// 不能只返回 `List<EmbyLibrary>?`：`EmbyFutureView` 会把 null 当成空数据，
/// 那样"还没配服务器"就会走到通用空态，看不到引导卡。
class _HomeData {
  const _HomeData({required this.server, required this.libraries});

  final EmbyServer? server;
  final List<EmbyLibrary> libraries;
}

class _NoServerGuide extends StatelessWidget {
  const _NoServerGuide({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EmbyIntro(
                icon: Icons.dns_rounded,
                title: '连接 Emby 服务器',
                description: '填好服务器地址和账号密码，就能在 LU 里直接浏览和播放你自建媒体库的内容。',
              ),
              const SizedBox(height: 20),
              NeuSurface(
                radius: NeuRadius.card,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hint(context, '1', '地址填服务器根地址，例如 http://192.168.1.10:8096'),
                    _hint(context, '2', '局域网自签证书的服务器，打开「允许自签证书」'),
                    _hint(context, '3', 'Emby 和 Jellyfin 都支持，不用区分'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加服务器'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String index, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              index,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.libraries,
    required this.serverName,
    required this.onOpen,
  });

  final List<EmbyLibrary> libraries;
  final String serverName;
  final ValueChanged<EmbyLibrary> onOpen;

  @override
  Widget build(BuildContext context) {
    if (libraries.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GeneralEmbyEmpty(
          title: '服务器上没有媒体库',
          message: '$serverName 里还没有可浏览的内容。先在 Emby 服务端添加媒体库，再回来刷新。',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final double inset = constraints.maxWidth < 600 ? 16 : 28;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 28),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 92,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: libraries.length,
          itemBuilder: (context, index) => _LibraryTile(
            library: libraries[index],
            onTap: () => onOpen(libraries[index]),
          ),
        );
      },
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.library, required this.onTap});

  final EmbyLibrary library;
  final VoidCallback onTap;

  IconData get _icon => switch (library.collectionType) {
        'movies' => Icons.movie_rounded,
        'tvshows' => Icons.live_tv_rounded,
        'music' => Icons.music_note_rounded,
        'boxsets' => Icons.collections_bookmark_rounded,
        'homevideos' => Icons.video_library_rounded,
        'photos' => Icons.photo_library_rounded,
        _ => Icons.folder_rounded,
      };

  String get _typeLabel => switch (library.collectionType) {
        'movies' => '电影',
        'tvshows' => '剧集',
        'music' => '音乐',
        'boxsets' => '合集',
        'homevideos' => '家庭视频',
        'photos' => '照片',
        _ => '媒体库',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool neu = isNeuLayout(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_icon,
                color: theme.colorScheme.onPrimaryContainer, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  library.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _typeLabel,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );

    if (neu) {
      return NeuSurface(radius: 22, onTap: onTap, child: content);
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
