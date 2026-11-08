import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_cloud_browse_page.dart';
import 'package:XL/utils/motion.dart';
import 'package:XL/pages/emby/emby_cloud_sheet.dart';
import 'package:XL/pages/emby/emby_display_prefs_page.dart';
import 'package:XL/pages/emby/emby_favorites_page.dart';
import 'package:XL/pages/emby/emby_gesture_settings_page.dart';
import 'package:XL/pages/emby/emby_stream_settings_page.dart';
import 'package:XL/pages/emby/emby_vault_lock_settings_page.dart';
import 'package:XL/services/emby/vault_lock.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_play_behavior_page.dart';
import 'package:XL/pages/emby/emby_scan_page.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/res_card_prefs.dart';
import 'package:XL/theme/kz_context_menu.dart';
import 'package:XL/pages/emby/emby_server_form_page.dart';
import 'package:XL/pages/emby/emby_vault_browse_page.dart';
import 'package:XL/pages/emby/emby_vault_lock_page.dart';
import 'package:XL/services/emby/emby_gesture_prefs.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/player/cache_profile.dart';
import 'package:XL/services/emby/lu_cloud_drive.dart';
import 'package:XL/services/emby/lu_media_vault.dart';

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
  bool _showWatchedTime = true;
  bool _showMediaStats = true;
  bool _showConnState = true;
  bool _glass = true;

  /// 每张卡一个 GlobalKey：长按菜单要以卡片本身为锚点浮起预览。
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};

  GlobalKey _cardKey(String prefKey) =>
      _cardKeys.putIfAbsent(prefKey, () => GlobalKey());

  /// 每台 Emby 的（电影数, 集数），卡片上那行小字用。拉失败就不显示。
  final Map<String, (String, String)> _counts = {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
    // 隐藏/加密/图标这类卡片配置变了要刷网格和顶栏锁按钮。
    ResCardPrefs.instance.revision.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    ResCardPrefs.instance.revision.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
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
    KazumiDialog.notify(message);
  }

  // ------------------------------------------------------------ 本地来源

  /// 能被「本地文件 / 本地私密」导入的扩展名。
  ///
  /// `file_picker` 的 custom 类型必须给扩展名（不带点、小写），它据此在
  /// iOS 上映射成 UTType。给全一点：国产剧常见 mkv / rmvb / ts 这些。
  static const List<String> kVaultVideoExtensions = <String>[
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'ts',
    'm2ts',
    'mpg',
    'mpeg',
    'rmvb',
    'rm',
    '3gp',
    'ogv',
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
      final dest =
          '${target.path}/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await File(src).copy(dest);
      return dest;
    } catch (_) {
      return src;
    }
  }

  Future<void> _openVault(String kind) async {
    if (!mounted) return;
    // 本地私密要过锁：第一次进先设置密码（顺手问生物解锁），之后每次
    // 都要验证通过才能看到里面的内容。
    if (kind == 'private') {
      final unlocked = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const EmbyVaultLockPage()),
      );
      if (unlocked != true || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EmbyVaultBrowsePage(title: _vaultTitle(kind), kind: kind),
      ),
    );
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
          .where(
            (f) => !kVaultVideoExtensions.any(
              (e) => f.name.toLowerCase().endsWith('.$e'),
            ),
          )
          .toList();
      if (bad.isNotEmpty) {
        _toast('跳过 ${bad.length} 个非视频文件');
      }
      final videos = picked
          .where(
            (f) => kVaultVideoExtensions.any(
              (e) => f.name.toLowerCase().endsWith('.$e'),
            ),
          )
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
                children: [Text('添加到本地私密', style: PvText.rowTitle(context))],
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
      final String stored = await _persistCopy(kind, file.path, file.name);
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
    final url = await showKzPrompt(
      context: context,
      title: '网络链接',
      hint: '粘贴视频直链，例如 https://.../a.mp4',
      confirmLabel: '播放',
    );
    if (url == null || url.isEmpty) return;
    final name = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '网络视频';
    await LuMediaVault.instance.addEntries('link', [(name: name, source: url)]);
    if (!mounted) return;
    luPlay(context, title: name, url: url);
  }

  // ------------------------------------------------------------ 添加来源

  // ---------------------------------------------------------------- 长按菜单

  /// 服务器卡长按：iOS 上下文菜单。
  Future<void> _serverCardMenu(_ServerEntry entry, Widget preview) async {
    KazumiHaptics.heavy();
    final ResCardPrefs prefs = ResCardPrefs.instance;
    final String key = entry.prefKey;
    final KzContextMenuController ctrl = KzContextMenuController();

    List<KzContextMenuItem> buildItems() {
      final bool isHome = prefs.defaultHome == key;
      final bool agg = prefs.aggregated(key);
      return <KzContextMenuItem>[
        KzContextMenuItem(
          label: '服务配置',
          icon: Icons.edit_rounded,
          onTap: () async {
            if (entry.emby != null) {
              widget.onEditServer();
            } else if (entry.cloud != null) {
              await showLuCloudSheet(
                context,
                type: entry.cloud!.type,
                existing: entry.cloud!,
              );
            } else if (entry.vault != null) {
              await _openForm(entry.vault!.type, existing: entry.vault!);
            }
          },
        ),
        if (entry.emby != null)
          KzContextMenuItem(
            label: agg ? '禁用聚合' : '启用聚合',
            icon: agg ? Icons.content_paste_off_rounded : Icons.copy_rounded,
            keepOpen: true,
            onTap: () {
              prefs.setAggregated(key, !agg);
              ctrl.updateItems(buildItems());
              _toast(agg ? '已停用聚合搜索' : '已启用聚合搜索');
            },
          ),
        KzContextMenuItem(
          label: isHome ? '取消默认首页' : '设为默认首页',
          icon: Icons.home_rounded,
          keepOpen: true,
          onTap: () {
            if (isHome) {
              prefs.setDefaultHome(null);
              _toast('已取消默认首页');
            } else {
              prefs.setDefaultHome(key);
              _toast('已设为默认首页');
            }
            ctrl.updateItems(buildItems());
          },
        ),
        if (entry.vault != null)
          KzContextMenuItem(
            label: '修改密码',
            icon: Icons.key_rounded,
            onTap: () async {
              await _changeVaultPassword(entry.vault!);
            },
          ),
        KzContextMenuItem(
          label: '修改图标',
          icon: Icons.person_rounded,
          onTap: () async {
            await _openIconPicker(key);
          },
        ),
        KzContextMenuItem(
          label: '加密',
          icon: Icons.lock_rounded,
          onTap: () async {
            await _encryptCard(key);
          },
        ),
        KzContextMenuItem(
          label: '删除',
          icon: Icons.delete_rounded,
          destructive: true,
          onTap: () async {
            if (entry.emby != null) {
              await EmbyService.instance.remove(entry.emby!.id);
            } else if (entry.cloud != null) {
              await LuCloudStore.instance.remove(entry.cloud!.id);
            } else if (entry.vault != null) {
              await LuMediaVault.instance.removeServer(entry.vault!.id);
            }
          },
        ),
      ];
    }

    ctrl.updateItems(buildItems());
    await showKzContextMenu(
      context: context,
      anchorKey: _cardKey(key),
      preview: preview,
      items: buildItems(),
      controller: ctrl,
    );
    if (mounted) setState(() {});
  }

  /// 本地卡长按：设为默认首页 / 隐藏。
  Future<void> _localCardMenu(String prefKey, Widget preview) async {
    KazumiHaptics.heavy();
    final ResCardPrefs prefs = ResCardPrefs.instance;
    final KzContextMenuController ctrl = KzContextMenuController();

    List<KzContextMenuItem> buildItems() {
      final bool isHome = prefs.defaultHome == prefKey;
      return <KzContextMenuItem>[
        KzContextMenuItem(
          label: isHome ? '取消默认首页' : '设为默认首页',
          icon: Icons.home_rounded,
          keepOpen: true,
          onTap: () {
            if (isHome) {
              prefs.setDefaultHome(null);
              _toast('已取消默认首页');
            } else {
              prefs.setDefaultHome(prefKey);
              _toast('已设为默认首页');
            }
            ctrl.updateItems(buildItems());
          },
        ),
        KzContextMenuItem(
          label: '隐藏',
          icon: Icons.visibility_off_rounded,
          onTap: () async {
            prefs.setHidden(prefKey, true);
          },
        ),
      ];
    }

    ctrl.updateItems(buildItems());
    await showKzContextMenu(
      context: context,
      anchorKey: _cardKey(prefKey),
      preview: preview,
      items: buildItems(),
      controller: ctrl,
    );
    if (mounted) setState(() {});
  }

  /// 「加密」：没有私密锁先去建；建完把卡片藏起来（顶栏锁按钮负责找回）。
  Future<void> _encryptCard(String key) async {
    if (!VaultLock.isSet) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const VaultLockSettingsPage()));
      if (!VaultLock.isSet) return;
    }
    ResCardPrefs.instance.setLocked(key, true);
    _toast('已加密隐藏，点顶栏锁图标可找回');
  }

  /// 顶栏锁按钮：验证通过后把隐藏的卡片全部显示回来。
  Future<void> _revealHidden() async {
    final ResCardPrefs prefs = ResCardPrefs.instance;
    if (prefs.hiddenCount == 0) return;
    if (prefs.hasLocked) {
      bool ok = false;
      if (await VaultLock.biometricAvailable()) {
        ok = await VaultLock.authenticateWithBiometrics();
      }
      if (!ok) {
        // 生物识别不可用/被拒：退回密码解锁页。
        ok =
            await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => const EmbyVaultLockPage(),
              ),
            ) ??
            false;
      }
      if (!ok) return;
    }
    prefs.revealAll();
    _toast('已显示隐藏的卡片');
  }

  /// 修改密码（仅 vault 类条目：LU 里 Emby 官方服务器只存 token，没有
  /// 本地密码可改）。
  Future<void> _changeVaultPassword(LuVaultServer server) async {
    final TextEditingController p1 = TextEditingController();
    final TextEditingController p2 = TextEditingController();
    // 对话框无论以哪种方式结束都要释放 controller，不然算泄露。
    Future<void> disposeControllers() async {
      p1.dispose();
      p2.dispose();
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: p1,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: '新密码'),
            ),
            TextField(
              controller: p2,
              obscureText: true,
              decoration: const InputDecoration(hintText: '再次输入新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      await disposeControllers();
      return;
    }
    if (p1.text.isEmpty || p1.text != p2.text) {
      KazumiDialog.showError(message: '两次输入不一致或为空');
      await disposeControllers();
      return;
    }
    await LuMediaVault.instance.saveServer(
      LuVaultServer(
        id: server.id,
        type: server.type,
        name: server.name,
        note: server.note,
        host: server.host,
        path: server.path,
        port: server.port,
        https: server.https,
        user: server.user,
        password: p1.text,
        addedAt: server.addedAt,
        backupLines: server.backupLines,
      ),
    );
    await disposeControllers();
    _toast('密码已更新');
  }

  /// 图标库：选一个替换卡片右上角的默认图标；第一项恢复默认。
  Future<void> _openIconPicker(String key) async {
    final ResCardPrefs prefs = ResCardPrefs.instance;
    final String? current = prefs.icon(key);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final bool dark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text('图标库', style: PvText.rowTitle(ctx)),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    for (final (String name, IconData icon) in kResIconCatalog)
                      _IconPickCell(
                        icon: icon,
                        selected: current == name,
                        dark: dark,
                        onTap: () => Navigator.of(ctx).pop(name),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(''),
                    child: const Text('恢复默认图标'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    prefs.setIcon(key, picked.isEmpty ? null : picked);
  }

  /// 扫一扫添加：解析出主机/端口/账号后，带着预填值打开表单。
  ///
  /// 不直接入库：扫码只负责省掉打字，类型和密码还得让人看一眼——扫错一个
  /// 字符就会得到一台连不上的服务器，而「为什么连不上」是最难排查的问题。
  Future<void> _openScan() async {
    // mobile_scanner 只有 Android / iOS / macOS 的实现。桌面端点进来会抛
    // MissingPluginException，所以在入口先挡掉，别让它变成一个崩溃。
    if (!Platform.isAndroid && !Platform.isIOS) {
      KazumiDialog.showError(message: '扫码只在手机端可用');
      return;
    }
    final EmbyScanResult? result = await Navigator.of(context)
        .push<EmbyScanResult>(
          MaterialPageRoute<EmbyScanResult>(
            builder: (_) => const EmbyScanPage(),
          ),
        );
    if (result == null || !mounted) {
      return;
    }
    await showEmbyServerSheet(
      context,
      type: result.type,
      prefill: result.server,
    );
    if (mounted) {
      setState(() {});
    }
  }

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
          PvMenuItem(label, onTap: () => _openForm(type)),
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
        PvMenuItem(
          '显示观看时间',
          checked: _showWatchedTime,
          onTap: () => setState(() => _showWatchedTime = !_showWatchedTime),
        ),
        PvMenuItem(
          '显示媒体统计',
          checked: _showMediaStats,
          onTap: () => setState(() => _showMediaStats = !_showMediaStats),
        ),
        PvMenuItem(
          '连接状态',
          checked: _showConnState,
          onTap: () => setState(() => _showConnState = !_showConnState),
        ),
        PvMenuItem(
          '毛玻璃效果',
          checked: _glass,
          onTap: () => setState(() => _glass = !_glass),
        ),
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
              // 有隐藏/加密的卡片时才出现：点它过面容/密码，验证通过后
              // 隐藏的卡片重新显示。
              ValueListenableBuilder<int>(
                valueListenable: ResCardPrefs.instance.revision,
                builder: (BuildContext context, int _, Widget? __) {
                  if (ResCardPrefs.instance.hiddenCount == 0) {
                    return const SizedBox(width: 0, height: 0);
                  }
                  return PvIconBtn(
                    icon: Icons.lock_open_rounded,
                    onTap: _revealHidden,
                  );
                },
              ),
              const SizedBox(width: 6),
              PvIconBtn(icon: Icons.qr_code_scanner_rounded, onTap: _openScan),
              const SizedBox(width: 6),
              PvIconBtn(
                icon: Icons.more_horiz_rounded,
                circled: true,
                onTap: _openMoreMenu,
              ),
            ],
          ),
          Padding(
            // 标题和第一排卡片之间留一点呼吸。原来是 4，几乎贴在一起。
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _EntryGrid(
              dark: dark,
              showStats: _showMediaStats,
              showWatched: _showWatchedTime,
              servers: [
                // 隐藏/加密的卡不进网格；顶栏锁按钮负责把它们带回来。
                ...embyServers
                    .where((s) => !ResCardPrefs.instance.hidden('emby:${s.id}'))
                    .map(
                      (s) => _ServerEntry(
                        title: s.name,
                        subtitle: '主线路',
                        kind: 'emby',
                        online: true,
                        emby: s,
                        stats: _counts[s.id],
                      ),
                    ),
                // Emby / Jellyfin 已经进 EmbyService 了，别再重复出一张卡。
                ...vaultServers
                    .where(
                      (v) =>
                          !v.isEmbyLike &&
                          !ResCardPrefs.instance.hidden('vault:${v.id}'),
                    )
                    .map(
                      (v) => _ServerEntry(
                        title: v.displayName,
                        subtitle: v.host,
                        kind: v.type,
                        online: false,
                        vault: v,
                      ),
                    ),
                ...LuCloudStore.instance.accounts
                    .where(
                      (a) => !ResCardPrefs.instance.hidden('cloud:${a.id}'),
                    )
                    .map(
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LuCloudBrowsePage(account: cloud),
                    ),
                  );
                  return;
                }
                final v = entry.vault;
                if (v == null) return;
                if (v.isWebdav) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          EmbyVaultBrowsePage(title: v.displayName, server: v),
                    ),
                  );
                  return;
                }
                if (v.isEmbyLike) {
                  widget.onEditServer();
                  return;
                }
                _toast('${v.typeLabel} 暂不支持直连，请改用 WebDAV 方式接入');
              },
              onServerMenu: (entry, preview) => _serverCardMenu(entry, preview),
              onLocalMenu: (prefKey, preview) =>
                  _localCardMenu(prefKey, preview),
              cardKeyFor: _cardKey,
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

  /// 卡片配置（隐藏/加密/聚合/图标/默认首页）在 [ResCardPrefs] 里的 key。
  String get prefKey {
    final EmbyServer? e = emby;
    if (e != null) return 'emby:${e.id}';
    final LuVaultServer? v = vault;
    if (v != null) return 'vault:${v.id}';
    return 'cloud:${cloud!.id}';
  }
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
    required this.onServerMenu,
    required this.onLocalMenu,
    required this.cardKeyFor,
  });

  final bool dark;
  final List<_ServerEntry> servers;
  final bool showStats;
  final bool showWatched;
  final VoidCallback onLocalFiles;

  /// 长按菜单：回调带上卡片 widget，浮起的预览直接用它。
  final void Function(_ServerEntry entry, Widget preview) onServerMenu;
  final void Function(String prefKey, Widget preview) onLocalMenu;

  /// 长按锚点：菜单要以卡片所在位置浮起来。
  final GlobalKey Function(String prefKey) cardKeyFor;
  final VoidCallback onPrivate;
  final VoidCallback onGallery;
  final VoidCallback onLink;
  final ValueChanged<_ServerEntry> onServer;
  @override
  Widget build(BuildContext context) {
    /// [withKey] = true 的实例挂在网格里，同时是长按菜单的锚点；
    /// = false 的实例只作浮起预览渲染。**预览绝不能带同一个
    /// GlobalKey**——同一棵树里出现两份同 key 的 widget 会在浮层
    /// build 时抛 duplicate key 异常，整层浮层失败，表现就是
    /// 「长按没反应，什么都不弹」。
    Widget localCard({
      required String prefKey,
      required String title,
      required String footLeft,
      required String footRight,
      required _Glyph glyph,
      required _Tone tone,
      required VoidCallback onTap,
      bool withKey = true,
    }) {
      final Widget card = _LibCard(
        title: title,
        footLeft: footLeft,
        footRight: footRight,
        glyph: glyph,
        tone: tone,
        dark: dark,
        customIcon: resIconByName(ResCardPrefs.instance.icon(prefKey)),
        onTap: onTap,
        onLongPress: () => onLocalMenu(
          prefKey,
          localCard(
            prefKey: prefKey,
            title: title,
            footLeft: footLeft,
            footRight: footRight,
            glyph: glyph,
            tone: tone,
            onTap: onTap,
            withKey: false,
          ),
        ),
      );
      if (!withKey) return card;
      return KeyedSubtree(key: cardKeyFor(prefKey), child: card);
    }

    Widget serverCard(_ServerEntry s, {bool withKey = true}) {
      final Widget card = _LibCard(
        title: s.title,
        footLeft: s.subtitle,
        footRight: s.online ? '刚刚' : '未连接',
        glyph: _Glyph.emby,
        tone: _Tone.green,
        dark: dark,
        customIcon: resIconByName(ResCardPrefs.instance.icon(s.prefKey)),
        onlineDot: s.online,
        stats: showStats ? s.stats : null,
        onTap: () => onServer(s),
        onLongPress: () => onServerMenu(s, serverCard(s, withKey: false)),
      );
      if (!withKey) return card;
      return KeyedSubtree(key: cardKeyFor(s.prefKey), child: card);
    }

    // 隐藏的本地卡不进网格（顶栏锁按钮负责显示回来）。
    Widget? maybeLocal({
      required String prefKey,
      required String title,
      required String footLeft,
      required _Glyph glyph,
      required _Tone tone,
      required VoidCallback onTap,
    }) {
      if (ResCardPrefs.instance.hidden(prefKey)) return null;
      return localCard(
        prefKey: prefKey,
        title: title,
        footLeft: footLeft,
        footRight: showWatched ? _localFoot(_localFootKey(prefKey)) : '',
        glyph: glyph,
        tone: tone,
        onTap: onTap,
      );
    }

    final List<Widget?> cards = <Widget?>[
      maybeLocal(
        prefKey: 'local:files',
        title: '本地文件',
        footLeft: '本地',
        glyph: _Glyph.folder,
        tone: _Tone.amber,
        onTap: onLocalFiles,
      ),
      maybeLocal(
        prefKey: 'local:private',
        title: '本地私密',
        footLeft: '私密',
        glyph: _Glyph.folderLock,
        tone: _Tone.amber,
        onTap: onPrivate,
      ),
      maybeLocal(
        prefKey: 'local:gallery',
        title: '相册视频',
        footLeft: '相册',
        glyph: _Glyph.album,
        tone: _Tone.gold,
        onTap: onGallery,
      ),
      maybeLocal(
        prefKey: 'local:link',
        title: '网络链接',
        footLeft: '链接',
        glyph: _Glyph.link,
        tone: _Tone.sky,
        onTap: onLink,
      ),
      for (final s in servers) serverCard(s),
    ].whereType<Widget>().toList();

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

  /// prefKey -> vault kind（_localFoot 的参数）。
  static const Map<String, String> _localKindByPrefKey = <String, String>{
    'local:files': 'local',
    'local:private': 'private',
    'local:gallery': 'gallery',
    'local:link': 'link',
  };

  static String _localFootKey(String prefKey) =>
      _localKindByPrefKey[prefKey] ?? prefKey.split(':').last;

  String _localFoot(String kind) {
    final n = LuMediaVault.instance.entriesOf(kind).length;
    return n == 0 ? '未观看' : '$n 个';
  }
}

enum _Tone { amber, gold, sky, green }

/// 卡片配色：预览稿 `.tone-*` 是 135° 白 → 浅色 → 更深的浅色。
/// 浅色卡片的三段渐变。
///
/// 原来第三段是 #FBE7BE / #CDEEDA 这类实打实的黄和绿，压在白底上还看得过去；
/// 换成渐变背景之后，黄配粉紫会发脏，一排卡片像糖果盒。现在只保留一点点
/// 色温差异（第三段和白只差 3~5%），辨识主要靠右上角那枚图标。
const Map<_Tone, List<Color>> _toneLight = {
  _Tone.amber: [Color(0xFFFFFFFF), Color(0xFFFEFCF7), Color(0xFFFDF6E9)],
  _Tone.gold: [Color(0xFFFFFFFF), Color(0xFFFEFCF6), Color(0xFFFCF5E6)],
  _Tone.sky: [Color(0xFFFFFFFF), Color(0xFFFBFDFF), Color(0xFFF3F8FE)],
  _Tone.green: [Color(0xFFFFFFFF), Color(0xFFFAFDFB), Color(0xFFF1FAF5)],
};

const Map<_Tone, Color> _toneDark = {
  _Tone.amber: Color(0xFFFFB340),
  _Tone.gold: Color(0xFFFFD426),
  _Tone.sky: Color(0xFF64B5FF),
  _Tone.green: Color(0xFF34C759),
};

/// 右上角那枚彩色图标（预览稿里的 folder / folderlock / album / link / emby）。
enum _Glyph { folder, folderLock, album, link, emby }

/// 「修改图标」的图标库。名字进 [ResCardPrefs] 存储，别改动已有序目的
/// 名字（老配置按名字找回图标）。
const List<(String, IconData)> kResIconCatalog = <(String, IconData)>[
  ('play', Icons.play_circle_fill_rounded),
  ('movie', Icons.movie_rounded),
  ('tv', Icons.tv_rounded),
  ('folder', Icons.folder_rounded),
  ('cloud', Icons.cloud_rounded),
  ('server', Icons.dns_rounded),
  ('link', Icons.link_rounded),
  ('album', Icons.photo_library_rounded),
  ('star', Icons.star_rounded),
  ('heart', Icons.favorite_rounded),
  ('bolt', Icons.bolt_rounded),
  ('globe', Icons.public_rounded),
  ('hub', Icons.hub_rounded),
  ('rocket', Icons.rocket_launch_rounded),
  ('music', Icons.music_note_rounded),
  ('podcast', Icons.podcasts_rounded),
  ('wifi', Icons.wifi_rounded),
  ('storage', Icons.storage_rounded),
  ('theater', Icons.theater_comedy_rounded),
  ('shield', Icons.shield_rounded),
  ('fire', Icons.local_fire_department_rounded),
  ('moon', Icons.dark_mode_rounded),
  ('sun', Icons.light_mode_rounded),
  ('pets', Icons.pets_rounded),
];

IconData? resIconByName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final (String n, IconData icon) in kResIconCatalog) {
    if (n == name) return icon;
  }
  return null;
}

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
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 21,
          ),
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
          child: const Icon(
            Icons.photo_library_rounded,
            size: 33,
            color: Colors.white,
          ),
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
                child: const Icon(
                  Icons.folder_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
              if (kind == _Glyph.folderLock)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
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
    this.customIcon,
  });

  final String title;
  final String footLeft;
  final String footRight;
  final _Glyph glyph;
  final _Tone tone;
  final bool dark;

  /// 「修改图标」选的自定义图标；null = 用默认 [glyph]。
  final IconData? customIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// (电影数, 集数)，只有服务器卡有。
  final (String, String)? stats;
  final bool onlineDot;

  @override
  Widget build(BuildContext context) {
    final tint = _toneDark[tone]!;
    // 浅色卡片做成 82% 白玻璃：背景的渐变透一点上来，和「我的」页那套
    // 玻璃卡是同一个材质；留 18% 让底下的粉色/蓝色参与进来。
    final colors = dark
        ? <Color>[
            const Color(0xFF26282F).withValues(alpha: 0.86),
            const Color(0xFF24262C).withValues(alpha: 0.86),
            Color.alphaBlend(
              tint.withValues(alpha: 0.18),
              const Color(0xFF23252B),
            ).withValues(alpha: 0.86),
          ]
        : _toneLight[tone]!
              // 58% 白：背景的粉/紫/蓝能明显透上来，卡片跟着背景变色。
              // 再低会影响黑字对比度（背后是饱和度不低的渐变）。
              .map((Color c) => c.withValues(alpha: 0.58))
              .toList();

    final ink = PvColors.ink(context);
    final ink3 = dark
        ? Colors.white.withValues(alpha: 0.42)
        : const Color(0xFF8A8A8E);

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
          // 不再整圈描边：一圈 1px 白边会让每张卡都像贴了相框，一排看过去
          // 全是格子。改成「顶部 1px 高光 + 一点投影」，靠明暗表示材质。
          border: Border(
            top: BorderSide(
              color: dark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.92),
              width: 0.8,
            ),
          ),
          // 阴影压到很小：一屏八到十张卡，每张一个大模糊阴影意味着
          // 每帧十次离屏合成，滚动时全是白开销。玻璃感靠半透明和顶部
          // 高光已经够了，阴影只负责让卡片"贴"在背景上。
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.22 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
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
                if (customIcon != null)
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(customIcon, color: Colors.white, size: 19),
                  )
                else
                  _LibGlyph(glyph),
              ],
            ),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    Icon(
                      Icons.movie_creation_outlined,
                      size: 13,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF5E5E64),
                    ),
                    const SizedBox(width: 4),
                    Text(stats!.$1, style: _statStyle(dark)),
                    const SizedBox(width: 11),
                    Icon(
                      Icons.videocam_outlined,
                      size: 13,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF5E5E64),
                    ),
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
                Text(footRight, style: TextStyle(fontSize: 12, color: ink3)),
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
    color: dark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF5E5E64),
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
      final version = await EmbyService.instance
          .clientFor(server)
          .fetchServerVersion();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (_) {
      // 版本拿不到就不显示。
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    KazumiDialog.notify(message);
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
          const PvGroupLabel('内容'),
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
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbyFavoritesPage(),
                    ),
                  );
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
                icon: Icons.lock_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: '本地私密锁',
                value: VaultLock.isSet ? '已开启' : null,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const VaultLockSettingsPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
                showDivider: false,
              ),
            ],
          ),
          const PvGroupLabel('播放'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.gesture_rounded,
                iconColor: const Color(0xFF0A84FF),
                title: '播放手势',
                value: '亮度 / 音量 / 倍速',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EmbyGestureSettingsPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              PvRow(
                icon: Icons.screen_rotation_rounded,
                iconColor: const Color(0xFF5E5CE6),
                title: '屏幕方向',
                value: EmbyDisplayPrefs.enter.label,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbyDisplayPrefsPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              PvRow(
                icon: Icons.timelapse_rounded,
                iconColor: const Color(0xFFFF9F0A),
                title: '播放缓存',
                value: PlaybackCacheProfile.current.label,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbyStreamSettingsPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              PvRow(
                icon: Icons.play_circle_outline_rounded,
                iconColor: const Color(0xFFAF52DE),
                title: '播放行为',
                subtitle: '字幕 · 弹幕 · 片头片尾 · 投屏',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmbyPlayBehaviorPage(),
                  ),
                ),
                showDivider: false,
              ),
            ],
          ),
          const PvGroupLabel('画质与性能'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.swap_vert_rounded,
                iconColor: const Color(0xFF8E8E93),
                title: '转码与串流',
                value: EmbyStreamPrefs.mode == EmbyStreamMode.auto
                    ? null
                    : '${EmbyStreamPrefs.mode.label}${EmbyStreamPrefs.bitrateMbps > 0 ? ' · ${EmbyStreamPrefs.bitrateMbps}M' : ''}',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmbyStreamSettingsPage(),
                    ),
                  );
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
                showDivider: false,
              ),
            ],
          ),
          const PvGroupLabel('其他'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.add_circle_outline_rounded,
                iconColor: const Color(0xFF3ED177),
                title: '添加服务器',
                subtitle: '连接 Emby / Jellyfin',
                onTap: () => context.pushNamed('/emby/servers'),
              ),
              PvRow(
                icon: Icons.settings_rounded,
                iconColor: const Color(0xFF8E8E93),
                title: '设置',
                onTap: () => context.pushNamed('/settings/'),
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图标库里的一格。
class _IconPickCell extends StatelessWidget {
  const _IconPickCell({
    required this.icon,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = selected
        ? PvColors.blue.withValues(alpha: dark ? 0.28 : 0.14)
        : (dark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.045));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: PvColors.blue, width: 1.4)
              : null,
        ),
        child: Icon(
          icon,
          size: 24,
          color: selected ? PvColors.blue : PvColors.ink(context),
        ),
      ),
    );
  }
}
