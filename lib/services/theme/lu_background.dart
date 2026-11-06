import 'dart:io';

import 'package:flutter/material.dart';

import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// 背景里的一颗光球。
@immutable
class LuBgOrb {
  const LuBgOrb({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.color,
    required this.strength,
  });

  /// 圆心（相对宽高的比例）。
  final double dx;
  final double dy;

  /// 半径（相对短边的比例）。
  final double radius;
  final Color color;

  /// 中心不透明度。
  final double strength;
}

/// 一套背景：四段底色渐变 + 若干光球。
@immutable
class LuBgPreset {
  const LuBgPreset({
    required this.id,
    required this.name,
    required this.dark,
    required this.colors,
    required this.orbs,
  });

  final String id;
  final String name;

  /// 这套是给深色模式用的，还是给浅色模式用的。
  final bool dark;

  /// 四段渐变（从左上到右下）。
  final List<Color> colors;
  final List<LuBgOrb> orbs;
}

/// 背景外观：预设 + 用户自定义图片。
///
/// 深浅模式**各记一套**：同一个用户白天用浅色、晚上用深色，两边想要的
/// 氛围通常不一样，共用一个 id 会让某一边永远差一点。
///
/// 自定义图片只存一份，深浅共用——图片本身不适合也跟着主题换，
/// 变化的是盖在上面的遮罩浓度。
abstract final class LuBackground {
  LuBackground._();

  /// 切换后台重建通知。[LuBackdrop] 挂在 MaterialApp.builder 上，
  /// 不会因为页面 setState 而重建，所以必须走 notifier。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const SettingKey<String> _lightKey = SettingKey<String>(
    'lu.bg.light',
    'aurora',
    group: SettingGroup.theme,
  );
  static const SettingKey<String> _darkKey = SettingKey<String>(
    'lu.bg.dark',
    'night',
    group: SettingGroup.theme,
  );
  static const SettingKey<String> _imageKey = SettingKey<String>(
    'lu.bg.image',
    '',
    group: SettingGroup.theme,
  );

  // ---------------------------------------------------------------- 预设

  static const List<LuBgPreset> presets = <LuBgPreset>[
    // ------------------------------ 浅色
    LuBgPreset(
      id: 'aurora',
      name: '极光',
      dark: false,
      colors: <Color>[
        Color(0xFFD6E0FF),
        Color(0xFFE7DAF9),
        Color(0xFFFFDFE8),
        Color(0xFFD6EEF7),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.24, dy: 0.10, radius: 0.52, color: Color(0xFF688CFF), strength: 0.52),
        LuBgOrb(dx: 0.86, dy: 0.32, radius: 0.50, color: Color(0xFFC67CFF), strength: 0.44),
        LuBgOrb(dx: 0.10, dy: 0.66, radius: 0.54, color: Color(0xFFFF8CB6), strength: 0.38),
        LuBgOrb(dx: 0.90, dy: 0.84, radius: 0.52, color: Color(0xFF4AE0F6), strength: 0.34),
        LuBgOrb(dx: 0.52, dy: 0.44, radius: 0.46, color: Color(0xFFFFFFFF), strength: 0.26),
      ],
    ),
    LuBgPreset(
      id: 'sakura',
      name: '樱雾',
      dark: false,
      colors: <Color>[
        Color(0xFFFFE6EE),
        Color(0xFFFFDCE8),
        Color(0xFFF6E4FF),
        Color(0xFFEDE6FF),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.20, dy: 0.14, radius: 0.56, color: Color(0xFFFF9EC0), strength: 0.46),
        LuBgOrb(dx: 0.84, dy: 0.28, radius: 0.50, color: Color(0xFFD9A0FF), strength: 0.40),
        LuBgOrb(dx: 0.14, dy: 0.72, radius: 0.54, color: Color(0xFFFFC0D0), strength: 0.36),
        LuBgOrb(dx: 0.88, dy: 0.86, radius: 0.50, color: Color(0xFFB9C4FF), strength: 0.30),
        LuBgOrb(dx: 0.50, dy: 0.46, radius: 0.44, color: Color(0xFFFFFFFF), strength: 0.24),
      ],
    ),
    LuBgPreset(
      id: 'mint',
      name: '海盐',
      dark: false,
      colors: <Color>[
        Color(0xFFD8F1F8),
        Color(0xFFDAF3EC),
        Color(0xFFE7F0FF),
        Color(0xFFF0EAFF),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.22, dy: 0.12, radius: 0.54, color: Color(0xFF57D6E8), strength: 0.44),
        LuBgOrb(dx: 0.86, dy: 0.34, radius: 0.50, color: Color(0xFF5FD9A8), strength: 0.36),
        LuBgOrb(dx: 0.12, dy: 0.70, radius: 0.52, color: Color(0xFF7FA8FF), strength: 0.34),
        LuBgOrb(dx: 0.86, dy: 0.86, radius: 0.50, color: Color(0xFFC2A8FF), strength: 0.28),
        LuBgOrb(dx: 0.50, dy: 0.46, radius: 0.44, color: Color(0xFFFFFFFF), strength: 0.22),
      ],
    ),
    LuBgPreset(
      id: 'dusk',
      name: '暮光',
      dark: false,
      colors: <Color>[
        Color(0xFFFFE7CE),
        Color(0xFFFFD8DC),
        Color(0xFFEBD8F7),
        Color(0xFFD8E2FF),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.18, dy: 0.16, radius: 0.54, color: Color(0xFFFFB067), strength: 0.46),
        LuBgOrb(dx: 0.84, dy: 0.26, radius: 0.50, color: Color(0xFFFF8FA8), strength: 0.40),
        LuBgOrb(dx: 0.14, dy: 0.74, radius: 0.52, color: Color(0xFFB98CFF), strength: 0.32),
        LuBgOrb(dx: 0.88, dy: 0.84, radius: 0.50, color: Color(0xFF6FA8FF), strength: 0.30),
        LuBgOrb(dx: 0.50, dy: 0.44, radius: 0.44, color: Color(0xFFFFFFFF), strength: 0.24),
      ],
    ),
    // ------------------------------ 深色
    LuBgPreset(
      id: 'night',
      name: '夜航',
      dark: true,
      colors: <Color>[
        Color(0xFF0D1017),
        Color(0xFF141824),
        Color(0xFF171523),
        Color(0xFF0A0D13),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.24, dy: 0.10, radius: 0.52, color: Color(0xFF566CA8), strength: 0.42),
        LuBgOrb(dx: 0.86, dy: 0.32, radius: 0.50, color: Color(0xFF685C96), strength: 0.35),
        LuBgOrb(dx: 0.10, dy: 0.66, radius: 0.54, color: Color(0xFF466E8C), strength: 0.32),
        LuBgOrb(dx: 0.90, dy: 0.84, radius: 0.52, color: Color(0xFF786084), strength: 0.28),
        LuBgOrb(dx: 0.52, dy: 0.44, radius: 0.46, color: Color(0xFFC8D2EB), strength: 0.10),
      ],
    ),
    LuBgPreset(
      id: 'ink',
      name: '墨紫',
      dark: true,
      colors: <Color>[
        Color(0xFF120E1C),
        Color(0xFF1A1226),
        Color(0xFF221428),
        Color(0xFF0E0B16),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.22, dy: 0.12, radius: 0.54, color: Color(0xFF6E4B9E), strength: 0.40),
        LuBgOrb(dx: 0.84, dy: 0.30, radius: 0.50, color: Color(0xFF9A5BA8), strength: 0.32),
        LuBgOrb(dx: 0.12, dy: 0.70, radius: 0.52, color: Color(0xFF4A3C82), strength: 0.30),
        LuBgOrb(dx: 0.88, dy: 0.86, radius: 0.50, color: Color(0xFF7A4E7E), strength: 0.26),
        LuBgOrb(dx: 0.50, dy: 0.44, radius: 0.44, color: Color(0xFFE0D2F0), strength: 0.08),
      ],
    ),
    LuBgPreset(
      id: 'ocean',
      name: '深海',
      dark: true,
      colors: <Color>[
        Color(0xFF08131F),
        Color(0xFF0C1C2C),
        Color(0xFF0A2230),
        Color(0xFF06101A),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.20, dy: 0.14, radius: 0.54, color: Color(0xFF2C6E9E), strength: 0.42),
        LuBgOrb(dx: 0.86, dy: 0.34, radius: 0.50, color: Color(0xFF227E8C), strength: 0.34),
        LuBgOrb(dx: 0.14, dy: 0.72, radius: 0.52, color: Color(0xFF2A4E86), strength: 0.32),
        LuBgOrb(dx: 0.86, dy: 0.88, radius: 0.50, color: Color(0xFF1E6A7A), strength: 0.26),
        LuBgOrb(dx: 0.50, dy: 0.44, radius: 0.44, color: Color(0xFFBEDDF0), strength: 0.08),
      ],
    ),
    LuBgPreset(
      id: 'forest',
      name: '森夜',
      dark: true,
      colors: <Color>[
        Color(0xFF0B1410),
        Color(0xFF12201A),
        Color(0xFF0F1C18),
        Color(0xFF08100C),
      ],
      orbs: <LuBgOrb>[
        LuBgOrb(dx: 0.22, dy: 0.12, radius: 0.54, color: Color(0xFF2E7A5A), strength: 0.38),
        LuBgOrb(dx: 0.86, dy: 0.32, radius: 0.50, color: Color(0xFF3E8A6E), strength: 0.32),
        LuBgOrb(dx: 0.12, dy: 0.72, radius: 0.52, color: Color(0xFF2A6E60), strength: 0.30),
        LuBgOrb(dx: 0.88, dy: 0.86, radius: 0.50, color: Color(0xFF4A7A50), strength: 0.24),
        LuBgOrb(dx: 0.50, dy: 0.44, radius: 0.44, color: Color(0xFFC8E8D4), strength: 0.07),
      ],
    ),
  ];

  static List<LuBgPreset> presetsFor(bool dark) =>
      presets.where((LuBgPreset p) => p.dark == dark).toList();

  static LuBgPreset byId(String id) =>
      presets.firstWhere((LuBgPreset p) => p.id == id,
          orElse: () => presets.first);

  // ---------------------------------------------------------------- 读写

  static String presetIdFor(bool dark) {
    final String id = dark
        ? GStorage.getSetting(_darkKey)
        : GStorage.getSetting(_lightKey);
    // 存的是另一套主题的 id（手改设置或版本迁移），退回该主题的默认。
    final LuBgPreset p = byId(id);
    if (p.dark != dark) {
      return dark ? 'night' : 'aurora';
    }
    return p.id;
  }

  static LuBgPreset presetFor(bool dark) => byId(presetIdFor(dark));

  static String get imagePath => GStorage.getSetting(_imageKey);

  static bool get hasImage {
    final String p = imagePath;
    return p.isNotEmpty && File(p).existsSync();
  }

  /// 当前生效：有自定义图片就优先用图片。
  static bool get usingImage => hasImage;

  static Future<void> setPreset(bool dark, String id) async {
    await GStorage.putSetting(dark ? _darkKey : _lightKey, id);
    revision.value++;
  }

  static Future<void> setImage(String path) async {
    await GStorage.putSetting(_imageKey, path);
    revision.value++;
  }

  static Future<void> clearImage() async {
    final String old = imagePath;
    await GStorage.putSetting(_imageKey, '');
    if (old.isNotEmpty) {
      try {
        final File f = File(old);
        if (f.existsSync()) {
          await f.delete();
        }
      } catch (_) {
        // 删不掉就算了，下次导入会覆盖同一个路径。
      }
    }
    revision.value++;
  }
}
