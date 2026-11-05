import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/bean/widget/state_presentation.dart';
import 'package:XL/modules/my/watch_stats.dart';
import 'package:XL/pages/my/profile_card.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/request/config/api_endpoints.dart';
import 'package:XL/services/lu_profile.dart';
import 'package:XL/utils/immersive_theme.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

enum MyDestination {
  theme,
  player,
  timeline,
  danmaku,
  rules,
  history,
  downloads,
  sync,
  storage,
  about,
  emby,
  proxy,
  report,
}

const _tileRadius = BorderRadius.all(Radius.circular(28));

class MySpaceView extends StatelessWidget {
  const MySpaceView({
    super.key,
    required this.stats,
    required this.onOpen,
  });

  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
      final width = constraints.maxWidth - inset * 2;
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final wide = width >= 840 && !largeText;
      return SingleChildScrollView(
        key: const PageStorageKey('my-space'),
        padding: EdgeInsets.fromLTRB(
            inset, 12, inset, 32 + immersiveTabBarInset(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: wide
                ? _WideSpaceLayout(stats: stats, onOpen: onOpen)
                // 手机端严格按 LU_3.9.19_预览.html 的「我的」页：
                // LU 账号 + 内容 + 通用 三组 iOS 分组列表。
                : _PreviewSpaceLayout(onOpen: onOpen),
          ),
        ),
      );
    });
  }
}

/// 预览稿「我的」页（LU 全局）：iOS 分组列表。
class _PreviewSpaceLayout extends StatelessWidget {
  const _PreviewSpaceLayout({required this.onOpen});

  final ValueChanged<MyDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PvGroup(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          children: [
            // 账号行只显示头像 + 昵称，点开是改资料的面板，
            // 不再跳到同步设置。
            const _ProfileTile(),
          ],
        ),
        const PvGroupLabel('内容'),
        PvGroup(
          children: [
            PvRow(
              icon: Icons.trending_up_rounded,
              iconColor: const Color(0xFF0A84FF),
              title: '时间表',
              subtitle: '按星期看本季更新',
              onTap: () => onOpen(MyDestination.timeline),
            ),
            PvRow(
              icon: Icons.schedule_rounded,
              iconColor: const Color(0xFF30B0C7),
              title: '观看历史',
              onTap: () => onOpen(MyDestination.history),
            ),
            PvRow(
              icon: Icons.download_rounded,
              iconColor: const Color(0xFF64D2FF),
              title: '下载管理',
              onTap: () => onOpen(MyDestination.downloads),
            ),
            PvRow(
              icon: Icons.extension_rounded,
              iconColor: const Color(0xFFFF9F0A),
              title: '规则与插件',
              onTap: () => onOpen(MyDestination.rules),
              showDivider: false,
            ),
            // 「Emby 媒体库」入口按用户要求去掉了：底栏有 Emby 页签，
            // 这里不必再留一个。
          ],
        ),
        const PvGroupLabel('通用'),
        PvGroup(
          children: [
            PvRow(
              icon: Icons.contrast_rounded,
              iconColor: const Color(0xFF5E5CE6),
              title: '外观',
              onTap: () => onOpen(MyDestination.theme),
            ),
            PvRow(
              icon: Icons.public_rounded,
              iconColor: const Color(0xFF34C759),
              title: '网络与代理',
              onTap: () => onOpen(MyDestination.proxy),
            ),
            PvRow(
              icon: Icons.play_circle_rounded,
              iconColor: const Color(0xFFFF375F),
              title: '播放设置',
              onTap: () => onOpen(MyDestination.player),
            ),
            PvRow(
              icon: Icons.subtitles_rounded,
              iconColor: const Color(0xFF30B0C7),
              title: '弹幕设置',
              onTap: () => onOpen(MyDestination.danmaku),
            ),
            PvRow(
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF8E8E93),
              title: '关于',
              value: ApiEndpoints.version,
              onTap: () => onOpen(MyDestination.about),
              showDivider: false,
            ),
          ],
        ),
      ],
    );
  }
}

/// 账号行：左边头像、右边昵称，点开是「编辑资料」面板。
///
/// 按用户要求：不再往同步设置里跳，头像可以相册选或文件导入，昵称自己填。
class _ProfileTile extends StatefulWidget {
  const _ProfileTile();

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  String _nickname = LuProfile.defaultNickname;
  String _avatarPath = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _nickname = LuProfile.instance.nickname;
      _avatarPath = LuProfile.instance.avatarPath;
    });
  }

  Future<void> _open() async {
    final changed = await showLuProfileEditor(context);
    if (changed != true) return;
    _reload();
    // 提示要在面板关掉之后弹，用面板自己的 context 已经取不到 Scaffold 了。
    if (!mounted) return;
    KazumiDialog.showToast(message: '已保存');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: Row(
          children: [
            _ProfileAvatar(path: _avatarPath, size: 46),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PvText.rowTitle(context)
                        .copyWith(fontSize: 16.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '点击修改头像和昵称',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PvText.rowSub(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: PvColors.chev(context)),
          ],
        ),
      ),
    );
  }
}

/// 圆形头像：有图显示图，没图用蓝紫渐变压一个人物图标。
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.path, required this.size});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B7CFF), Color(0xFF4A6CF7)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: path.isEmpty
          ? Icon(Icons.person_rounded,
              size: size * 0.56, color: Colors.white.withValues(alpha: 0.92))
          : Image(
              image: FileImage(File(path)),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.person_rounded,
                  size: size * 0.56,
                  color: Colors.white.withValues(alpha: 0.92)),
            ),
    );
  }
}

/// 弹出「编辑资料」面板，返回 true 表示资料改过了。
Future<bool?> showLuProfileEditor(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _ProfileEditorSheet(),
  );
}

class _ProfileEditorSheet extends StatefulWidget {
  const _ProfileEditorSheet();

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _nameController;
  String _avatarPath = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: LuProfile.instance.nickname);
    _avatarPath = LuProfile.instance.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    KazumiDialog.showToast(message: message);
  }

  Future<void> _pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        imageQuality: 88,
      );
      if (file == null) return;
      setState(() {
        _avatarPath = file.path;
        _dirty = true;
      });
    } catch (e) {
      _toast('读取相册失败：$e');
    }
  }

  Future<void> _pickFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      setState(() {
        _avatarPath = path;
        _dirty = true;
      });
    } catch (e) {
      _toast('读取文件失败：$e');
    }
  }

  Future<void> _save() async {
    await LuProfile.instance.setNickname(_nameController.text);
    await LuProfile.instance.setAvatarPath(_avatarPath);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canPop = Navigator.of(context).canPop();
    return Container(
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: PvColors.hair(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '编辑资料',
                    style: TextStyle(
                      color: PvColors.ink(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canPop)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: PvColors.searchFill(context),
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: PvColors.ink2(context)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _ProfileAvatar(path: _avatarPath, size: 84),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SheetChip(
                  icon: Icons.photo_library_rounded,
                  label: '相册',
                  onTap: _pickFromGallery,
                ),
                const SizedBox(width: 10),
                _SheetChip(
                  icon: Icons.folder_rounded,
                  label: '文件',
                  onTap: _pickFromFile,
                ),
                const SizedBox(width: 10),
                _SheetChip(
                  icon: Icons.delete_outline_rounded,
                  label: '移除',
                  onTap: () => setState(() {
                    _avatarPath = '';
                    _dirty = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (_) => setState(() => _dirty = true),
              style: TextStyle(color: PvColors.ink(context), fontSize: 15),
              decoration: InputDecoration(
                hintText: '昵称',
                hintStyle: TextStyle(color: PvColors.ink3(context)),
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                filled: true,
                fillColor: PvColors.searchFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A6CF7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                onPressed: _dirty ? _save : () => Navigator.of(context).pop(false),
                child: Text(_dirty ? '保存' : '完成',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: PvColors.searchFill(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: PvColors.ink2(context)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: PvColors.ink(context),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _WideSpaceLayout extends StatelessWidget {
  const _WideSpaceLayout({required this.stats, required this.onOpen});

  final WatchStats stats;
  final ValueChanged<MyDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProfileCard(),
        const SizedBox(height: 18),
        _AdaptivePair(
          gap: 20,
          first: const _SpaceHeading(),
          second: _WatchStatsPanel(
            bangumiCount: stats.watchedBangumiCount,
            episodeCount: stats.watchedEpisodeCount,
            onTap: () => onOpen(MyDestination.report),
          ),
        ),
        const SizedBox(height: 28),
        _AdaptivePair(
          first: _RulesTile(onTap: () => onOpen(MyDestination.rules)),
          second: _AdaptivePair(
            first: _ToolTile(
              icon: Icons.history_rounded,
              title: '历史记录',
              caption: stats.watchedBangumiCount == 0 ? '暂无观看记录' : '查看观看记录',
              color: colors.secondaryContainer,
              foreground: colors.onSecondaryContainer,
              onTap: () => onOpen(MyDestination.history),
            ),
            second: _AdaptivePair(
              first: _ToolTile(
                icon: Icons.download_rounded,
                title: '离线下载',
                caption: stats.downloadTaskCount == 0
                    ? '管理离线内容'
                    : '${stats.downloadTaskCount} 集下载任务',
                color: colors.tertiaryContainer,
                foreground: colors.onTertiaryContainer,
                onTap: () => onOpen(MyDestination.downloads),
              ),
              second: _ToolTile(
                icon: Icons.dns_rounded,
                title: 'Emby',
                caption: '自建媒体库',
                color: colors.primaryContainer,
                foreground: colors.onPrimaryContainer,
                onTap: () => onOpen(MyDestination.emby),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AdaptivePair(
          first: _TimelineTile(onTap: () => onOpen(MyDestination.timeline)),
          second: const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        _AdaptivePair(
          first: _PreferencesPanel(onOpen: onOpen),
          second: _AdaptivePair(
            first: _ToolTile(
              icon: Icons.cloud_sync_rounded,
              title: '同步备份',
              caption: '跨设备同步数据',
              color: colors.surfaceContainer,
              foreground: colors.onSurface,
              onTap: () => onOpen(MyDestination.sync),
            ),
            second: _ToolTile(
              icon: Icons.cleaning_services_rounded,
              title: '存储管理',
              caption: '缓存与日志',
              color: colors.surfaceContainer,
              foreground: colors.onSurface,
              onTap: () => onOpen(MyDestination.storage),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.center,
          child: _ExpressiveAction(
            color: colors.surfaceContainerLow,
            foreground: colors.onSurfaceVariant,
            onTap: () => onOpen(MyDestination.about),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Flexible(child: Text('关于 LU')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// 时间表入口：底栏里挪走之后，这里就是它唯一的家。
class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ToolTile(
      icon: Icons.timeline_rounded,
      title: '时间表',
      caption: '本周新番播出时间',
      color: colors.surfaceContainer,
      foreground: colors.onSurface,
      onTap: onTap,
    );
  }
}

class _WatchStatsPanel extends StatelessWidget {
  const _WatchStatsPanel({
    required this.bangumiCount,
    required this.episodeCount,
    this.compact = false, // ignore: unused_element_parameter
    // (旧紧凑布局遗留，宽屏布局只走非 compact 分支)
    this.onTap,
  });

  final int bangumiCount;
  final int episodeCount;
  final bool compact;

  /// 点这块数字看年报。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: compact ? colors.primaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(compact ? 28 : 48),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (compact)
              Row(
                children: [
                  _ShapeIcon(
                    shape: _SpaceShape.sun,
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    size: 32,
                    color: colors.primary,
                    foreground: colors.onPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('观看足迹',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              )
            else
              Text('观看统计',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCount(
                    value: bangumiCount,
                    label: '看过番剧',
                    foreground: compact ? colors.onPrimaryContainer : null,
                  ),
                ),
                if (compact)
                  SizedBox(
                    height: 32,
                    child: VerticalDivider(
                      width: 24,
                      color: colors.onPrimaryContainer.withValues(alpha: .16),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.auto_awesome_rounded,
                        color: colors.primary, size: 20),
                  ),
                Expanded(
                  child: _StatCount(
                    value: episodeCount,
                    label: '观看集数',
                    foreground: compact ? colors.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StatCount extends StatelessWidget {
  const _StatCount({required this.value, required this.label, this.foreground});

  final int value;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Scale large totals without shrinking their labels.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$value',
              style: theme.textTheme.displaySmall?.copyWith(
                  color: foreground ?? theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
                color: foreground ?? theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SpaceHeading extends StatelessWidget {
  const _SpaceHeading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '个人中心',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                  height: 1.2,
                ),
          ),
        ),
        const SizedBox(width: 12),
        _ShapeIcon(
          shape: _SpaceShape.sun,
          icon: Icons.sentiment_satisfied_alt_rounded,
          size: 64,
          color: colors.tertiaryContainer,
          foreground: colors.onTertiaryContainer,
        ),
      ],
    );
  }
}

class _RulesTile extends StatelessWidget {
  const _RulesTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: colors.primary,
      foreground: colors.onPrimary,
      radius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(64),
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('规则设置',
                      style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary)),
                  const SizedBox(height: 6),
                  Text('管理番剧来源',
                      style:
                          text.bodyMedium?.copyWith(color: colors.onPrimary)),
                  const SizedBox(height: 20),
                  _ArrowCue(
                      color: colors.onPrimary, foreground: colors.primary),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ShapeIcon(
              shape: _SpaceShape.clover,
              icon: Icons.extension_rounded,
              size: 80,
              color: colors.primaryContainer,
              foreground: colors.onPrimaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.compact = false, // ignore: unused_element_parameter
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: color,
      foreground: foreground,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: compact ? 24 : 30),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
            SizedBox(height: compact ? 12 : 26),
            Text(title,
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            SizedBox(height: compact ? 4 : 6),
            Text(caption,
                style:
                    text.bodySmall?.copyWith(color: foreground, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({required this.onOpen});

  final ValueChanged<MyDestination> onOpen;

  static const _entries = [
    ('外观', Icons.palette_rounded, MyDestination.theme),
    ('播放', Icons.play_circle_rounded, MyDestination.player),
    ('弹幕', Icons.subtitles_rounded, MyDestination.danmaku),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: _tileRadius,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('偏好设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(child: _button(i)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(int index) {
    final (label, icon, destination) = _entries[index];
    return _PreferenceAction(
      icon: icon,
      label: label,
      first: index == 0,
      last: index == _entries.length - 1,
      onTap: () => onOpen(destination),
    );
  }
}

class _PreferenceAction extends StatelessWidget {
  const _PreferenceAction({
    required this.icon,
    required this.label,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ExpressiveAction(
      color: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
      radius: BorderRadius.horizontal(
        left: Radius.circular(first ? 24 : 8),
        right: Radius.circular(last ? 24 : 8),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }
}

class MySettingsButton extends StatelessWidget {
  const MySettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '全部设置',
      child: FilledButton.tonalIcon(
        style: StateActionButton.styleOf(context).copyWith(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.tune_rounded, size: 20),
        label: const Text('设置'),
      ),
    );
  }
}

class _ArrowCue extends StatelessWidget {
  const _ArrowCue({required this.color, required this.foreground});

  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 52,
          height: 32,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(20)),
          child: Icon(Icons.arrow_forward_rounded, color: foreground, size: 20),
        ),
      );
}

enum _SpaceShape { sun, clover }

class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({
    required this.shape,
    required this.icon,
    required this.size,
    required this.color,
    required this.foreground,
  });

  final _SpaceShape shape;
  final IconData icon;
  final double size;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipPath(
          clipper: _SpaceShapeClipper(shape),
          child: ColoredBox(
            color: color,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: foreground, size: size * .44),
            ),
          ),
        ),
      );
}

class _SpaceShapeClipper extends CustomClipper<Path> {
  const _SpaceShapeClipper(this.shape);

  final _SpaceShape shape;
  static final _paths = {
    _SpaceShape.sun: MaterialShapes.sunny.toPath(),
    _SpaceShape.clover: MaterialShapes.clover4Leaf.toPath(),
  };

  @override
  Path getClip(Size size) => _paths[shape]!
      .transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);

  @override
  bool shouldReclip(_SpaceShapeClipper oldClipper) => oldClipper.shape != shape;
}

class _ExpressiveAction extends StatefulWidget {
  const _ExpressiveAction({
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.child,
    this.radius = _tileRadius,
  });

  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;

  @override
  State<_ExpressiveAction> createState() => _ExpressiveActionState();
}

class _ExpressiveActionState extends State<_ExpressiveAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 150 : 300);
    return Semantics(
      button: true,
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? .97 : 1,
        duration: duration,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: _pressed ? BorderRadius.circular(16) : widget.radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.foreground.withValues(alpha: .10);
                }
                if (states.contains(WidgetState.focused)) {
                  return widget.foreground.withValues(alpha: .12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return widget.foreground.withValues(alpha: .08);
                }
                return null;
              }),
              child: IconTheme.merge(
                data: IconThemeData(color: widget.foreground),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.foreground,
                      ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.first,
    required this.second,
    this.stack = false, // ignore: unused_element_parameter
    this.gap = 12,
  });

  final Widget first;
  final Widget second;
  final bool stack;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, SizedBox(height: gap), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      ),
    );
  }
}
