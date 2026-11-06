import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/theme/lu_background.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 背景设置：深浅各一套预设，外加一张自定义图片。
///
/// 这里的「背景」就是全 App 的那层渐变——`MaterialApp.builder` 里的
/// `LuBackdrop`。页面本身全是透明的，所以改这里等于改所有页面。
class BackgroundSettingsPage extends StatefulWidget {
  const BackgroundSettingsPage({super.key});

  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage> {
  bool _busy = false;

  Future<void> _select(bool dark, String id) async {
    await LuBackground.setPreset(dark, id);
    if (mounted) {
      setState(() {});
    }
  }

  /// 导入图片。
  ///
  /// 两个入口都要走：iOS 相册受相册权限管，文件 App 受「文档选择器」管，
  /// 用户想找的那张图可能只在其中一个地方。
  Future<void> _import({required bool fromGallery}) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      String? source;
      if (fromGallery) {
        final XFile? file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          // 原图动辄十几 MB，这里先压一道，后面还会按屏宽再限制解码尺寸。
          maxWidth: 2400,
          imageQuality: 92,
        );
        source = file?.path;
      } else {
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        source = result?.files.single.path;
      }
      if (source == null || !mounted) {
        return;
      }

      // 必须复制到应用自己的目录：相册/文件选择器给的是临时路径，
      // 系统清理之后这张图就变成一块黑底了。
      final Directory dir = await getApplicationSupportDirectory();
      final String ext = source.contains('.')
          ? '.${source.split('.').last.toLowerCase()}'
          : '.jpg';
      final String dest = '${dir.path}/lu_background$ext';
      await File(source).copy(dest);
      await LuBackground.setImage(dest);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      KazumiDialog.showError(message: '导入失败：$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearImage() async {
    await LuBackground.clearImage();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LuBgPreset> light = LuBackground.presetsFor(false);
    final List<LuBgPreset> dark = LuBackground.presetsFor(true);
    final String lightId = LuBackground.presetIdFor(false);
    final String darkId = LuBackground.presetIdFor(true);
    final bool usingImage = LuBackground.usingImage;

    return SettingsDetailScaffold(
      title: const Text('背景'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: <Widget>[
          _label('浅色模式'),
          _PresetGrid(
            presets: light,
            selectedId: usingImage ? '' : lightId,
            onSelect: (String id) => _select(false, id),
          ),
          _label('深色模式'),
          _PresetGrid(
            presets: dark,
            selectedId: usingImage ? '' : darkId,
            onSelect: (String id) => _select(true, id),
          ),
          _label('自定义图片'),
          if (usingImage) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(LuBackground.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
          PvGroup(
            children: <Widget>[
              PvRow(
                icon: Icons.photo_library_outlined,
                iconColor: PvColors.blue,
                title: '从相册选择',
                onTap: () => _import(fromGallery: true),
              ),
              PvRow(
                icon: Icons.folder_outlined,
                iconColor: const Color(0xFFFF9F0A),
                title: '从文件选择',
                subtitle: 'iCloud 云盘 / 本地文件',
                onTap: () => _import(fromGallery: false),
                showDivider: usingImage,
              ),
              if (usingImage)
                PvRow(
                  icon: Icons.restore_rounded,
                  iconColor: const Color(0xFF8E8E93),
                  title: '恢复为预设背景',
                  titleColor: PvColors.red,
                  onTap: _clearImage,
                  showDivider: false,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(
              '自定义图片会复制一份到应用目录，之后删掉相册里的原图也不影响。'
              '深浅模式共用同一张图，遮罩浓度不同，保证文字始终读得清。',
              style: PvText.rowSub(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(text, style: PvText.groupLabel(context)),
      );
}

/// 预设缩略图网格：两列，卡片本身就是那块背景的缩小版。
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({
    required this.presets,
    required this.selectedId,
    required this.onSelect,
  });

  final List<LuBgPreset> presets;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 96,
        ),
        itemCount: presets.length,
        itemBuilder: (BuildContext context, int i) {
          final LuBgPreset p = presets[i];
          return _PresetCard(
            preset: p,
            selected: p.id == selectedId,
            onTap: () => onSelect(p.id),
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final LuBgPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = preset.dark;
    return KzPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: const Alignment(-0.35, -1),
            end: const Alignment(0.35, 1),
            colors: preset.colors,
            stops: const <double>[0, 0.34, 0.66, 1],
          ),
          border: Border.all(
            color: selected ? PvColors.blue : Colors.white.withValues(alpha: 0.5),
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            // 光球示意：跟真背景同一套参数，缩小看也是同一个东西。
            for (final LuBgOrb orb in preset.orbs)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: FractionallySizedBox(
                    alignment: Alignment(orb.dx * 2 - 1, orb.dy * 2 - 1),
                    widthFactor: orb.radius * 1.6,
                    heightFactor: orb.radius * 1.9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[
                            orb.color.withValues(alpha: orb.strength * 0.9),
                            orb.color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: dark ? Colors.white : const Color(0xFF17171B),
                    shadows: <Shadow>[
                      Shadow(
                        color: dark
                            ? Colors.black.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.9),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (selected)
              const Positioned(
                right: 8,
                top: 8,
                child: Icon(Icons.check_circle_rounded,
                    size: 20, color: PvColors.blue),
              ),
          ],
        ),
      ),
    );
  }
}
