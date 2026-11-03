import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_cloud_browse_page.dart';
import 'package:XL/pages/emby/emby_cloud_sheet.dart';
import 'package:XL/pages/emby/emby_display_prefs_page.dart';
import 'package:XL/pages/emby/emby_favorites_page.dart';
import 'package:XL/pages/emby/emby_gesture_settings_page.dart';
import 'package:XL/pages/emby/emby_stream_settings_page.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_server_form_page.dart';
import 'package:XL/pages/emby/emby_vault_browse_page.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/emby/lu_cloud_drive.dart';
import 'package:XL/services/emby/lu_media_vault.dart';
import 'package:XL/services/platform/cast_service.dart';
import 'package:XL/services/storage/storage.dart';

/// Emby「资源库」页签。
///
/// 上半是四个本地来源（本地文件 / 本地私密 / 相册视频 / 网络链接），
/// 下半是添加进来的服务器和网盘。IPTV 按需求删掉了。
///
/// - 本地文件：系统文件选择器挑视频，导入后在这里看
/// - 本地私密：同上，但单独一份列表
/// - 相册视频：从系统相册挑视频
/// - 网络链接：粘贴一个视频直链，直接用 LU 播放器播
class EmbyResourcePane extends StatefulWidget {
  const EmbyResourcePane({
    super.key,
    required this.onSwitchServer,
    required this.onEditServer,
    required this.onOpenLibrary,
  });

  /// 点 Emby 服务器卡片：切到这台并回到媒体库页签。
  final ValueChanged<EmbyServer> onSwitchServer;

  /// 打开服务器管理页。
  final VoidCallback onEditServer;

  final VoidCallback onOpenLibrary;

  @override
  State<EmbyResourcePane> createState() => _EmbyResourcePaneState();
}

class _EmbyResourcePaneState extends State<EmbyResourcePane> {
  bool _showSearch = true;
  bool _showWatchedTime = true;
  bool _showMediaStats = true;
  bool _showConnState = true;
  bool _glass = true;

  /// 每台 Emby 的（电影数, 集数），卡片上那行小字用。拉失败就不显示。
  final Map<String, (String, String)> _counts = {};

  @override
  void initState() {
    super.initState();
    _showSearch =
        GStorage.getSetting(const SettingKey<bool>(
      'pv.resShowSearch',
      true,
      group: SettingGroup.emby,
    ));
    _loadCounts();
  }

  /// 只给服务器卡拉一次统计，失败静默。
  Future<void> _loadCounts() async {
    for (final server in EmbyService.instance.servers) {
      if (_counts.containsKey(server.id)) continue;
      try {
        final c = await EmbyService.instance
            .clientFor(server)
            .fetchItemCounts(userId: server.userId);
        if (!mounted) return;
        setState(() {
          _counts[server.id] = (_fmtCount(c.movies), _fmtCount(c.episodes));
        });
      } catch (_) {
        // 反代把 /Items/Counts 关掉的情况很常见，直接不显示。
      }
    }
  }

  static String _fmtCount(int value) {
    if (value >= 10000) {
      final v = value / 10000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}万';
    }
    return '$value';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ------------------------------------------------------------ 本地来源

  /// 能被「本地文件 / 本地私密」导入的扩展名。
  ///
  /// `file_picker` 的 custom 类型必须给扩展名（不带点、小写），它据此在
  /// iOS 上映射成 UTType。给全一点：国产剧常见 mkv / rmvb / ts 这些。
  static const List<String> kVaultVideoExtensions = <String>[
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v',
    'ts', 'm2ts', 'mpg', 'mpeg', 'rmvb', 'rm', '3gp', 'ogv',
  ];

  static String _vaultTitle(String kind) => switch (kind) {
        'private' => '本地私密',
        'gallery' => '相册视频',
        'link' => '网络链接',
        _ => '本地文件',
      };

  /// 把相册/临时目录里的文件搬进应用私有目录。
  ///
  /// 相册选出来的是**临时文件**：系统清理缓存、重启、或者用户清一次存储，
  /// 列表里那条就指向一个不存在的路径，点开直接报「文件不存在」。私密内容
  /// 也不该留在公共目录里。复制失败就退回原路径，保证这一次能播。
  Future<String> _persistCopy(String kind, String src, String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory('${dir.path}/vault/$kind');
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dest = '${target.path}/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await File(src).copy(dest);
      return dest;
    } catch (_) {
      return src;
    }
  }

  Future<void> _openVault(String kind) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmbyVaultBrowsePage(title: _vaultTitle(kind), kind: kind),
    ));
    if (mounted) setState(() {});
  }

  /// 「本地文件」：只走系统文件选择器，浏览手机/平板里的目录。
  Future<void> _importLocal(String kind) async {
    try {
      // 注意：这里**不能**用 `FileType.video`。
      //
      // `file_picker` 对 `video` 的处理是：iOS 直接弹 PHPicker（系统相册），
      // Android 发 `ACTION_OPEN_DOCUMENT` 但很多国产 ROM 会把它路由到相册。
      // 于是「本地文件」和「本地私密 → 从文件选择」打开的都是相册，压根
      // 碰不到手机目录。改成按扩展名挑（`FileType.custom`），iOS 就会走
      // 「文件」App（UIDocumentPicker），Android 走文档界面，这才是用户
      // 说的「访问手机的文件夹」。
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kVaultVideoExtensions,
        allowMultiple: true,
      );
      final files = result?.files ?? [];
      if (files.isEmpty) return;
      final picked = files
          .where((f) => f.path != null)
          .map((f) => (name: f.name, source: f.path!))
          .toList();
      if (picked.isEmpty) {
        _toast('选中的文件读不到路径，换个目录再试');
        return;
      }
      // 少数 ROM 会忽略扩展名过滤，允许勾非视频文件。挑出来直接挡掉，
      // 不然列表里会出现一堆打不开的东西。
      final bad = picked
          .where((f) =>
              !kVaultVideoExtensions.any((e) => f.name.toLowerCase().endsWith('.$e')))
          .toList();
      if (bad.isNotEmpty) {
        _toast('跳过 ${bad.length} 个非视频文件');
      }
      final videos = picked
          .where((f) =>
              kVaultVideoExtensions.any((e) => f.name.toLowerCase().endsWith('.$e')))
          .toList();
      if (videos.isEmpty) return;
      await LuMediaVault.instance.addEntries(kind, videos);
      await _openVault(kind);
    } catch (e) {
      _toast('导入失败：${e.toString().split('\n').first}');
    }
  }

  /// 「本地私密」：来源可以是文件夹，也可以是相册——两条路都进同一个私密
  /// 列表，让用户自己选，而不是像以前那样跟「本地文件」完全一样。
  Future<void> _importPrivate() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: PvColors.card(context),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text('添加到本地私密', style: PvText.rowTitle(context)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('从文件夹选择'),
              subtitle: const Text('浏览手机存储里的目录，挑视频文件'),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('从相册选择'),
              subtitle: const Text('打开系统相册，挑一段视频'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.list_rounded),
              title: const Text('只看已导入的'),
              onTap: () => Navigator.of(ctx).pop('open'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'file':
        await _importLocal('private');
      case 'gallery':
        await _importGallery(kind: 'private');
      case 'open':
        await _openVault('private');
    }
  }

  /// 「相册视频」：直接打开系统默认相册挑视频，导入后进列表（原来选完就
  /// 直接播，用户下次想再找它根本翻不到）。
  Future<void> _importGallery({String kind = 'gallery'}) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final String stored =
          await _persistCopy(kind, file.path, file.name);
      await LuMediaVault.instance.addEntries(kind, [
        (name: file.name, source: stored),
      ]);
      await _openVault(kind);
    } on PlatformException catch (e) {
      // 相册权限被拒时 iOS / Android 都会抛这个，直接说清楚怎么开。
      if (e.code == 'photo_access_denied' || e.code == 'camera_access_denied') {
        _toast('没有相册权限，去系统设置里允许 LU 访问照片后重试');
      } else {
        _toast('读取相册失败：${e.message ?? e.code}');
      }
    } catch (e) {
      _toast('读取相册失败：${e.toString().split('\n').first}');
    }
  }

  Future<void> _addLink() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('网络链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '粘贴视频直链，例如 https://.../a.mp4',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('播放'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final name = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '网络视频';
    await LuMediaVault.instance.addEntries('link', [(name: name, source: url)]);
    if (!mounted) return;
    luPlay(context, title: name, url: url);
  }

  // ------------------------------------------------------------ 添加来源

  Future<void> _openAddMenu() async {
    // 按最新要求：只留前四项（WebDAV / SMB / FTP / Emby），
    // Jellyfin 和各路网盘都从菜单里撤掉了。
    const entries = <(String, String)>[
      ('WebDAV', 'webdav'),
      ('SMB', 'smb'),
      ('FTP', 'ftp'),
      ('Emby', 'emby'),
    ];
    await showPvMenu<Object>(
      context: context,
      position: const RelativeRect.fromLTRB(120, 110, 20, 200),
      minWidth: 240,
      items: [
        for (final (label, type) in entries)
          PvMenuItem(
            label,
            onTap: () => _openForm(type),
          ),
      ],
    );
  }

  Future<void> _openForm(String type, {LuVaultServer? existing}) async {
    // 网盘走各自的授权流程（扫码 / 账号密码 / OAuth）。
    if (LuCloudDrive.isCloudType(type)) {
      await showLuCloudSheet(context, type: type);
      if (mounted) setState(() {});
      return;
    }
    // Emby / Jellyfin 统一走整页表单 `/emby/servers/edit`——跟「我的 → 媒体库
    // 管理」里那一条是同一个页面、同一套逻辑。底部弹窗只剩 WebDAV / SMB / FTP
    // 在用，避免再出现「两套导入互不相通」。
    if (type == 'emby' || type == 'jellyfin') {
      await context.pushNamed('/emby/servers/edit');
      if (mounted) setState(() {});
      return;
    }
    await showEmbyServerSheet(context, type: type, existing: existing);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ 菜单

  Future<void> _openMoreMenu<T>() async {
    await showPvMenu<Object>(
      context: context,
      position: const RelativeRect.fromLTRB(120, 110, 20, 260),
      minWidth: 240,
      items: [
        PvMenuItem('显示观看时间',
            checked: _showWatchedTime,
            onTap: () => setState(() => _showWatchedTime = !_showWatchedTime)),
        PvMenuItem('显示媒体统计',
            checked: _showMediaStats,
            onTap: () => setState(() => _showMediaStats = !_showMediaStats)),
        PvMenuItem('连接状态',
            checked: _showConnState,
            onTap: () => setState(() => _showConnState = !_showConnState)),
        PvMenuItem('搜索框', checked: _showSearch, onTap: () async {
          setState(() => _showSearch = !_showSearch);
          await GStorage.putSetting(
            const SettingKey<bool>(
              'pv.resShowSearch',
              true,
              group: SettingGroup.emby,
            ),
            _showSearch,
          );
        }),
        PvMenuItem('毛玻璃效果',
            checked: _glass,
            onTap: () => setState(() => _glass = !_glass)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final embyServers = EmbyService.instance.servers;
    final vaultServers = LuMediaVault.instance.servers;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: pvSubDockClearance),
        children: [
          PvPageHead(
            title: '资源库',
            actions: [
              PvIconBtn(icon: Icons.add_rounded, onTap: _openAddMenu),
              const SizedBox(width: 6),
              PvIconBtn(
                icon: Icons.qr_code_scanner_rounded,
                onTap: () => _toast('扫码添加暂未开放'),
              ),
              const SizedBox(width: 6),
              PvIconBtn(
                icon: Icons.more_horiz_rounded,
                circled: true,
                onTap: _openMoreMenu,
              ),
            ],
          ),
          if (_showSearch)
            PvSearchField(hint: '搜索', onTap: () => _toast('搜索请到「搜索」页签')),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: _EntryGrid(
              dark: dark,
              showStats: _showMediaStats,
              showWatched: _showWatchedTime,
              servers: [
                ...embyServers.map((s) => _ServerEntry(
                      title: s.name,
                      subtitle: '主线路',
                      kind: 'emby',
                      online: true,
                      emby: s,
                      stats: _counts[s.id],
                    )),
                // Emby / Jellyfin 已经进 EmbyService 了，别再重复出一张卡。
                ...vaultServers.where((v) => !v.isEmbyLike).map(
                      (v) => _ServerEntry(
                        title: v.displayName,
                        subtitle: v.host,
                        kind: v.type,
                        online: false,
                        vault: v,
                      ),
                    ),
                ...LuCloudStore.instance.accounts.map(
                      (a) => _ServerEntry(
                        title: a.label.isNotEmpty ? a.label : a.typeLabel,
                        subtitle: a.typeLabel,
                        kind: a.type,
                        online: true,
                        cloud: a,
                      ),
                    ),
              ],
              onLocalFiles: () => _importLocal('local'),
              onPrivate: _importPrivate,
              onGallery: _importGallery,
              onLink: _addLink,
              onServer: (entry) {
                if (entry.emby != null) {
                  widget.onSwitchServer(entry.emby!);
                  return;
                }
                final cloud = entry.cloud;
                if (cloud != null) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LuCloudBrowsePage(account: cloud),
                  ));
                  return;
                }
                final v = entry.vault;
                if (v == null) return;
                if (v.isWebdav) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EmbyVaultBrowsePage(
                      title: v.displayName,
                      server: v,
                    ),
                  ));
                  return;
                }
                if (v.isEmbyLike) {
                  widget.onEditServer();
                  return;
                }
                _toast('${v.typeLabel} 暂不支持直连，请改用 WebDAV 方式接入');
              },
              onServerLongPress: (entry) async {
                final cloud = entry.cloud;
                if (cloud != null) {
                  await showPvMenu<Object>(
                    context: context,
                    position: const RelativeRect.fromLTRB(120, 200, 20, 200),
                    minWidth: 220,
                    items: [
                      PvMenuItem(
                        '编辑',
                        onTap: () =>
                            showLuCloudSheet(context, type: cloud.type, existing: cloud),
                      ),
                      PvMenuItem(
                        '删除',
                        destructive: true,
                        onTap: () async {
                          await LuCloudStore.instance.remove(cloud.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  );
                  if (mounted) setState(() {});
                  return;
                }
                final v = entry.vault;
                if (v == null) {
                  widget.onEditServer();
                  return;
                }
                await showPvMenu<Object>(
                  context: context,
                  position:
                      const RelativeRect.fromLTRB(120, 200, 20, 200),
                  minWidth: 220,
                  items: [
                    PvMenuItem('编辑', onTap: () => _openForm(v.type, existing: v)),
                    PvMenuItem('删除',
                        destructive: true,
                        onTap: () async {
                          await LuMediaVault.instance.removeServer(v.id);
                          if (mounted) setState(() {});
                        }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerEntry {
  const _ServerEntry({
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.online,
    this.emby,
    this.vault,
    this.cloud,
    this.stats,
  });

  final String title;
  final String subtitle;
  final String kind;
  final bool online;
  final EmbyServer? emby;
  final LuVaultServer? vault;
  final LuCloudAccount? cloud;

  /// (电影数, 集数)，从 `/Items/Counts` 拿；拿不到就 null，卡片不显示这一行。
  final (String, String)? stats;
}

// ---------------------------------------------------------------- 网格

/// 资源库的两列网格：四个本地来源 + 已添加的服务器 / 网盘。
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.dark,
    required this.servers,
    required this.showStats,
    required this.showWatched,
    required this.onLocalFiles,
    required this.onPrivate,
    required this.onGallery,
    required this.onLink,
    required this.onServer,
    required this.onServerLongPress,
  });

  final bool dark;
  final List<_ServerEntry> servers;
  final bool showStats;
  final bool showWatched;
  final VoidCallback onLocalFiles;
  final VoidCallback onPrivate;
  final VoidCallback onGallery;
  final VoidCallback onLink;
  final ValueChanged<_ServerEntry> onServer;
  final ValueChanged<_ServerEntry> onServerLongPress;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _LibCard(
        title: '本地文件',
        footLeft: '本地',
        footRight: showWatched ? _localFoot('local') : '',
        glyph: _Glyph.folder,
        tone: _Tone.amber,
        dark: dark,
        onTap: onLocalFiles,
      ),
      _LibCard(
        title: '本地私密',
        footLeft: '私密',
        footRight: showWatched ? _localFoot('private') : '',
        glyph: _Glyph.folderLock,
        tone: _Tone.amber,
        dark: dark,
        onTap: onPrivate,
      ),
      _LibCard(
        title: '相册视频',
        footLeft: '相册',
        footRight: showWatched ? _localFoot('gallery') : '',
        glyph: _Glyph.album,
        tone: _Tone.gold,
        dark: dark,
        onTap: onGallery,
      ),
      _LibCard(
        title: '网络链接',
        footLeft: '链接',
        footRight: showWatched ? _localFoot('link') : '',
        glyph: _Glyph.link,
        tone: _Tone.sky,
        dark: dark,
        onTap: onLink,
      ),
      for (final s in servers)
        _LibCard(
          title: s.title,
          footLeft: s.subtitle,
          footRight: s.online ? '刚刚' : '未连接',
          glyph: _Glyph.emby,
          tone: _Tone.green,
          dark: dark,
          onlineDot: s.online,
          stats: showStats ? s.stats : null,
          onTap: () => onServer(s),
          onLongPress: () => onServerLongPress(s),
        ),
    ];

    // 严格两列。之前用 Wrap + 手算宽度，浮点误差会让第二列挤不下去，
    // 实际渲染成一大列（用户截图里就是这个样子）。GridView 的 delegate
    // 自己算宽度，不会再出现这种问题。
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 11,
        crossAxisSpacing: 11,
        mainAxisExtent: 120,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => cards[i],
    );
  }

  String _localFoot(String kind) {
    final n = LuMediaVault.instance.entriesOf(kind).length;
    return n == 0 ? '未观看' : '$n 个';
  }
}

enum _Tone { amber, gold, sky, green }

/// 卡片配色：预览稿 `.tone-*` 是 135° 白 → 浅色 → 更深的浅色。
const Map<_Tone, List<Color>> _toneLight = {
  _Tone.amber: [Color(0xFFFFFFFF), Color(0xFFFEF6E6), Color(0xFFFBE7BE)],
  _Tone.gold: [Color(0xFFFFFFFF), Color(0xFFFDF3DF), Color(0xFFF8E0B4)],
  _Tone.sky: [Color(0xFFFFFFFF), Color(0xFFEDF3FD), Color(0xFFD8E6F8)],
  _Tone.green: [Color(0xFFFFFFFF), Color(0xFFEAF8EE), Color(0xFFCDEEDA)],
};

const Map<_Tone, Color> _toneDark = {
  _Tone.amber: Color(0xFFFFB340),
  _Tone.gold: Color(0xFFFFD426),
  _Tone.sky: Color(0xFF64B5FF),
  _Tone.green: Color(0xFF34C759),
};

/// 右上角那枚彩色图标（预览稿里的 folder / folderlock / album / link / emby）。
enum _Glyph { folder, folderLock, album, link, emby }

class _LibGlyph extends StatelessWidget {
  const _LibGlyph(this.kind);

  final _Glyph kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _Glyph.emby:
        return Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: const Color(0xFF2FBF5C),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 21),
        );
      case _Glyph.link:
        return Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9CC6F5), Color(0xFF5E9BE8)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.link_rounded, color: Colors.white, size: 19),
        );
      case _Glyph.album:
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD05E), Color(0xFFFFA514)],
          ).createShader(r),
          child: const Icon(Icons.photo_library_rounded,
              size: 33, color: Colors.white),
        );
      case _Glyph.folder:
      case _Glyph.folderLock:
        return SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFC94D), Color(0xFFFFA514)],
                ).createShader(r),
                child: const Icon(Icons.folder_rounded,
                    size: 34, color: Colors.white),
              ),
              if (kind == _Glyph.folderLock)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                ),
            ],
          ),
        );
    }
  }
}

/// 资源库网格里的一张卡（本地来源和服务器共用同一套骨架）。
class _LibCard extends StatelessWidget {
  const _LibCard({
    required this.title,
    required this.footLeft,
    required this.footRight,
    required this.glyph,
    required this.tone,
    required this.dark,
    required this.onTap,
    this.onLongPress,
    this.stats,
    this.onlineDot = false,
  });

  final String title;
  final String footLeft;
  final String footRight;
  final _Glyph glyph;
  final _Tone tone;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// (电影数, 集数)，只有服务器卡有。
  final (String, String)? stats;
  final bool onlineDot;

  @override
  Widget build(BuildContext context) {
    final tint = _toneDark[tone]!;
    final colors = dark
        ? <Color>[
            const Color(0xFF26282F),
            const Color(0xFF24262C),
            Color.alphaBlend(tint.withValues(alpha: 0.18), const Color(0xFF23252B)),
          ]
        : _toneLight[tone]!;

    final ink = PvColors.ink(context);
    final ink3 = dark ? Colors.white.withValues(alpha: 0.42) : const Color(0xFF8A8A8E);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            stops: const [0, 0.42, 1],
          ),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.75),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: -0.4,
                            color: ink,
                          ),
                        ),
                      ),
                      if (onlineDot)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 3, top: 1),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2FBF5C),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _LibGlyph(glyph),
              ],
            ),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    Icon(Icons.movie_creation_outlined,
                        size: 13,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF5E5E64)),
                    const SizedBox(width: 4),
                    Text(stats!.$1, style: _statStyle(dark)),
                    const SizedBox(width: 11),
                    Icon(Icons.videocam_outlined,
                        size: 13,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF5E5E64)),
                    const SizedBox(width: 4),
                    Text(stats!.$2, style: _statStyle(dark)),
                  ],
                ),
              ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    footLeft,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ink3,
                    ),
                  ),
                ),
                Text(
                  footRight,
                  style: TextStyle(fontSize: 12, color: ink3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _statStyle(bool dark) => TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: dark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF5E5E64),
      );
}

// ---------------------------------------------------------------- 我的

/// Emby「我的」页签。
///
/// 按用户要求：删掉了「存储空间」和「观看记录」，「播放列表」接的是真实
/// 播放记录（在 Emby 播放器里播过的影片），「投屏」调系统自带投屏。
class EmbyMinePane extends StatefulWidget {
  const EmbyMinePane({super.key, this.libraryCount = 0});

  final int libraryCount;

  @override
  State<EmbyMinePane> createState() => _EmbyMinePaneState();
}

class _EmbyMinePaneState extends State<EmbyMinePane> {
  String _version = '';
  int _favoriteCount = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadFavorites();
  }

  /// 收藏数量：拿不到就当 0，行上的数字只是参考，不影响点进去。
  Future<void> _loadFavorites() async {
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    try {
      final items = await EmbyService.instance
          .clientFor(server)
          .fetchFavorites(userId: server.userId);
      if (!mounted) return;
      setState(() => _favoriteCount = items.length);
    } catch (_) {
      // 服务器没开收藏、或者这个账号没有权限，安静地留 0。
    }
  }

  Future<void> _loadVersion() async {
    final server = EmbyService.instance.activeServer;
    if (server == null) return;
    try {
      final version =
          await EmbyService.instance.clientFor(server).fetchServerVersion();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (_) {
      // 版本拿不到就不显示。
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openCast() async {
    if (!CastService.supported) {
      _toast('当前平台没有系统投屏可用');
      return;
    }
    try {
      final ok = await CastService.open();
      if (!ok && mounted) _toast('这台设备上找不到系统投屏入口');
    } on CastUnsupported catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = EmbyService.instance.activeServer;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: pvSubDockClearance),
        children: [
          const PvPageHead(title: '我的'),
          const SizedBox(height: 14),
          PvGroup(
            children: [
              if (server != null)
                PvRow(
                  icon: Icons.play_arrow_rounded,
                  iconColor: PvColors.green,
                  title: server.name,
                  subtitle: _version.isEmpty ? '主线路' : '$_version · 主线路',
                  onTap: () => _toast('服务器：${server.name}'),
                )
              else
                PvRow(
                  icon: Icons.add_rounded,
                  iconColor: PvColors.green,
                  title: '添加服务器',
                  subtitle: '连接 Emby / Jellyfin',
                  onTap: () => context.pushNamed('/emby/servers'),
                ),
            ],
          ),
          const PvGroupLabel('资源模块'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.grid_view_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: '媒体库管理',
                value: '${widget.libraryCount} 个库',
                onTap: () => context.pushNamed('/emby/servers'),
              ),
              PvRow(
                icon: Icons.favorite_rounded,
                iconColor: const Color(0xFFFF375F),
                title: '收藏',
                value: _favoriteCount == 0 ? null : '$_favoriteCount 部',
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EmbyFavoritesPage(),
                  ));
                  if (mounted) _loadFavorites();
                },
              ),
              PvRow(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFF64D2FF),
                title: '离线下载',
                onTap: () => context.pushNamed('/settings/download/'),
              ),
              PvRow(
                icon: Icons.swap_vert_rounded,
                iconColor: const Color(0xFF8E8E93),
                title: '转码与串流',
                value: EmbyStreamPrefs.mode == EmbyStreamMode.auto
                    ? null
                    : '${EmbyStreamPrefs.mode.label}${EmbyStreamPrefs.bitrateMbps > 0 ? ' · ${EmbyStreamPrefs.bitrateMbps}M' : ''}',
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EmbyStreamSettingsPage(),
                  ));
                  if (mounted) setState(() {});
                },
                showDivider: false,
              ),
            ],
          ),
          const PvGroupLabel('播放器'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.gesture_rounded,
                iconColor: const Color(0xFF0A84FF),
                title: '播放手势',
                value: '亮度 / 音量 / 倍速',
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EmbyGestureSettingsPage(),
                  ));
                  if (mounted) setState(() {});
                },
              ),
              PvRow(
                icon: Icons.screen_rotation_rounded,
                iconColor: const Color(0xFF5E5CE6),
                title: '屏幕方向',
                value: EmbyDisplayPrefs.enter.label,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EmbyDisplayPrefsPage(),
                  ));
                  if (mounted) setState(() {});
                },
              ),
              PvRow(
                icon: Icons.monitor_rounded,
                iconColor: const Color(0xFF5856D6),
                title: '渲染后端',
                value: 'GPU · mpv',
                onTap: () => context.pushNamed('/settings/player'),
              ),
              PvRow(
                icon: Icons.memory_rounded,
                iconColor: const Color(0xFF34C759),
                title: '硬件解码',
                value: '自动',
                onTap: () => context.pushNamed('/settings/player'),
              ),
              PvRow(
                icon: Icons.timelapse_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: '播放缓存',
                value: '30 秒',
                onTap: () => context.pushNamed('/settings/player'),
              ),
              PvSwitchRow(
                icon: Icons.subtitles_rounded,
                iconColor: const Color(0xFF5E5CE6),
                title: '双字幕',
                prefKey: 'pv.doubleSubtitle',
                defaultValue: true,
              ),
              PvSwitchRow(
                icon: Icons.translate_rounded,
                iconColor: const Color(0xFFFF375F),
                title: '字幕翻译',
                prefKey: 'pv.subtitleTranslate',
                defaultValue: false,
              ),
              PvSwitchRow(
                icon: Icons.emoji_emotions_outlined,
                iconColor: const Color(0xFF30B0C7),
                title: '弹幕',
                prefKey: 'pv.danmaku',
                defaultValue: true,
              ),
              PvSwitchRow(
                icon: Icons.skip_next_rounded,
                iconColor: const Color(0xFF8E8E93),
                title: '片头片尾跳过',
                prefKey: 'pv.introOutroSkip',
                defaultValue: true,
              ),
              PvSwitchRow(
                icon: Icons.screen_lock_portrait_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: '上滑锁定屏幕',
                prefKey: 'pv.swipeLock',
                defaultValue: true,
              ),
              PvSwitchRow(
                icon: Icons.desktop_access_disabled_rounded,
                iconColor: const Color(0xFF34C759),
                title: '关屏后返回首页',
                prefKey: 'pv.backOnScreenOff',
                defaultValue: false,
              ),
              PvRow(
                icon: Icons.cast_rounded,
                iconColor: const Color(0xFF0A84FF),
                title: '投屏',
                value: CastService.supported ? '未连接' : '不支持',
                onTap: _openCast,
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「我的」页签里的开关行：状态持久化到设置盒。
class PvSwitchRow extends StatefulWidget {
  const PvSwitchRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.prefKey,
    required this.defaultValue,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String prefKey;
  final bool defaultValue;

  @override
  State<PvSwitchRow> createState() => _PvSwitchRowState();
}

class _PvSwitchRowState extends State<PvSwitchRow> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    _value = GStorage.getSetting(SettingKey<bool>(
      widget.prefKey,
      widget.defaultValue,
      group: SettingGroup.player,
    ));
  }

  Future<void> _toggle(bool next) async {
    setState(() => _value = next);
    await GStorage.putSetting(
      SettingKey<bool>(
        widget.prefKey,
        widget.defaultValue,
        group: SettingGroup.player,
      ),
      next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _value ?? widget.defaultValue;
    return PvRow(
      icon: widget.icon,
      iconColor: widget.iconColor,
      title: widget.title,
      trailing: PvRowTrailing.widget,
      trailingWidget: PvSwitch(value: value, onChanged: _toggle),
      showDivider: false,
    );
  }
}
