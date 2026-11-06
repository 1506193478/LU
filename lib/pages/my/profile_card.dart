import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/bean/widget/neu_dialog.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/storage/storage.dart';

/// 「我的」页顶部的个人资料卡：圆角头像 + 昵称，点开就能改。
///
/// 头像不存相册原图路径——手机上原图可能被删、Android 13 之后还会受
/// scoped storage 限制。选中后先复制一份到应用私有目录，只存副本路径。
class ProfileCard extends StatefulWidget {
  const ProfileCard({super.key});

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  String _nickname = '';
  String _avatarPath = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _nickname = GStorage.getSetting(SettingsKeys.userNickname);
    _avatarPath = GStorage.getSetting(SettingsKeys.userAvatarPath);
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: _nickname);
    String previewPath = _avatarPath;
    String? pickedPath;

    final saved = await KazumiDialog.show<bool>(
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => NeuDialog(
          title: '个人资料',
          maxWidth: 420,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final path = await _pickImage();
                  if (path == null) return;
                  setDialogState(() {
                    pickedPath = path;
                    previewPath = path;
                  });
                },
                child: _Avatar(
                  path: previewPath,
                  size: 92,
                  radius: 28,
                  onTapHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  final path = await _pickImage();
                  if (path == null) return;
                  setDialogState(() {
                    pickedPath = path;
                    previewPath = path;
                  });
                },
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('从相册选一张'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  hintText: '给自己起个名字',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            NeuDialogButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            NeuDialogButton(
              label: '保存',
              primary: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) {
      controller.dispose();
      return;
    }

    final String nickname = controller.text.trim();
    controller.dispose();

    String avatarPath = _avatarPath;
    if (pickedPath != null) {
      final stored = await _persistAvatar(pickedPath!);
      if (stored != null) avatarPath = stored;
    }

    await GStorage.putSetting(SettingsKeys.userNickname, nickname);
    await GStorage.putSetting(SettingsKeys.userAvatarPath, avatarPath);
    if (!mounted) return;
    setState(() {
      _nickname = nickname;
      _avatarPath = avatarPath;
    });
  }

  Future<String?> _pickImage() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 88,
        );
        return file?.path;
      }
      // 桌面端（Windows / macOS / Linux）走系统文件对话框。
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      return result?.files.single.path;
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'Profile: pick avatar failed',
        error: error,
        stackTrace: stackTrace,
      );
      KazumiDialog.showToast(message: '没能读取这张图片，换一张试试');
      return null;
    }
  }

  /// 把选中的图片复制进应用目录，顺手删掉上一张，避免越攒越多。
  Future<String?> _persistAvatar(String sourcePath) async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'avatar'));
      if (!await dir.exists()) await dir.create(recursive: true);

      final ext = p.extension(sourcePath).isEmpty
          ? '.png'
          : p.extension(sourcePath).toLowerCase();
      final target = File(
        p.join(dir.path, 'avatar_${DateTime.now().millisecondsSinceEpoch}$ext'),
      );
      await File(sourcePath).copy(target.path);

      if (_avatarPath.isNotEmpty && _avatarPath != target.path) {
        final old = File(_avatarPath);
        if (await old.exists()) await old.delete();
      }
      return target.path;
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'Profile: persist avatar failed',
        error: error,
        stackTrace: stackTrace,
      );
      KazumiDialog.showError(message: '保存头像失败');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool empty = _nickname.isEmpty;

    // 拟态凸起面板换成了 Pv 白卡：整页现在已经没有第二套材质了。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _edit,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: PvColors.card(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            _Avatar(path: _avatarPath, size: 60, radius: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    empty ? '点这里设置昵称' : _nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: empty
                          ? PvColors.ink3(context)
                          : PvColors.ink(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    empty ? '头像和昵称只存在这台设备上' : '点击编辑头像和昵称',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: PvColors.ink3(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 18, color: PvColors.ink3(context)),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.path,
    required this.size,
    required this.radius,
    this.onTapHint = false,
  });

  final String path;
  final double size;
  final double radius;
  final bool onTapHint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.5,
        color: colors.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (path.isEmpty)
              placeholder
            else
              Image.file(
                File(path),
                // 换了图但路径没变时 Flutter 会吃缓存，用 key 强制重建。
                key: ValueKey<String>(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              ),
            if (onTapHint)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size: 14,
                    color: PvColors.ink3(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
