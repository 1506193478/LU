import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:XL/services/storage/storage.dart';

/// 一起看里统一的头像：自己用设置里导入的本地头像，别人用昵称首字色块。
///
/// SyncPlay 协议本身不传头像，远端成员只能按名字首字生成确定性色块；自己则
/// 直接读 `userAvatarPath`（「我的」页导入的本地相册副本），没有就退回首字。
///
/// 远端成员的真实头像走 Chat 通道上的缩略图协议（`syncplay_avatar_message.dart`）
/// 传过来，存为内存字节；这里通过 [remoteImage] 接收并显示，查不到时退回首字。
class SyncPlayAvatar extends StatelessWidget {
  const SyncPlayAvatar({
    super.key,
    required this.name,
    this.isSelf = false,
    this.size = 32,
    this.radius = 16,
    this.remoteImage,
  });

  /// 房间里的用户名（用来取首字、判颜色）。
  final String name;

  /// 是不是「我」：是的话优先用设置里的本地头像。
  final bool isSelf;

  final double size;
  final double radius;

  /// 远端成员的真实头像（已解码的内存字节）。
  ///
  /// 走 Chat 通道的缩略图协议传过来；为空说明对方还没发过、或没设头像，
  /// 这时退回昵称首字色块。自己（[isSelf]）永远用本地文件，不读这个。
  final Uint8List? remoteImage;

  /// 自己一套、别人一套的柔和色板，按名字 hash 取，保证同一个人颜色稳定。
  static const List<Color> _palette = <Color>[
    Color(0xFFF48FB1),
    Color(0xFFCE93D8),
    Color(0xFF9FA8DA),
    Color(0xFF90CAF9),
    Color(0xFF80DEEA),
    Color(0xFF80CBC4),
    Color(0xFFA5D6A7),
    Color(0xFFFFCC80),
    Color(0xFFBCAAA4),
    Color(0xFFEF9A9A),
  ];

  static Color colorFor(String name) {
    if (name.isEmpty) return _palette.last;
    int hash = 0;
    for (final int r in name.runes) {
      hash = (hash * 31 + r) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  /// 一起看里展示用的名字：自己优先用设置里的昵称，否则退回房间用户名。
  static String displayName(String username, String selfName) {
    if (username != selfName) return username;
    final String nick = GStorage.getSetting(SettingsKeys.userNickname);
    return nick.isNotEmpty ? nick : username;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String initial =
        name.isEmpty ? '?' : name.characters.first.toUpperCase();

    final String avatarPath = isSelf
        ? GStorage.getSetting(SettingsKeys.userAvatarPath)
        : '';
    final bool hasImage = avatarPath.isNotEmpty;

    final Widget inner;
    if (isSelf && hasImage) {
      // 自己：直接用「我的」页导入的本地相册副本，最清晰。
      inner = Image.file(
        File(avatarPath),
        key: ValueKey<String>(avatarPath),
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _letter(colors, initial),
      );
    } else if (!isSelf && remoteImage != null) {
      // 别人：优先显示对方通过协议传过来的真实头像缩略图。
      inner = Image.memory(
        remoteImage!,
        key: ValueKey<Object>(remoteImage!),
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _letter(colors, initial),
      );
    } else {
      // 都没拿到：退回「昵称首字 + 确定性色块」。
      inner = _letter(colors, initial);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: inner,
      ),
    );
  }

  Widget _letter(ColorScheme colors, String initial) {
    final Color bg = isSelf ? colors.primaryContainer : colorFor(name);
    final Color fg = isSelf ? colors.onPrimaryContainer : Colors.white;
    return ColoredBox(
      color: bg,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: fg,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
