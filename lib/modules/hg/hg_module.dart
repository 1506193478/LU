/// HG 短剧模块注册（flutter_modular）。
///
/// 外观（HgPrefs.appearance：system/light/dark）只在 HG 模块内生效：
/// 路由 child 外层包一层 Theme override，跟随设置即时切换；竖滑
/// 沉浸页（Feed）自身恒黑不受影响。
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/hg/hg_feed_page.dart';
import 'package:XL/modules/hg/hg_web_page.dart';
import 'package:XL/modules/hg/hg_session.dart';

final hgModule = createModule(
  path: '/hg',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      // WebView 路线（fork 前端原样承载）：移动/macOS 走 WebView；
      // Windows/Linux 尚无 flutter_inappwebview 平台实现，暂回退原生 UI。
      child: (context, state) => (Platform.isWindows || Platform.isLinux)
          ? const HgAppearanceScope(child: HgFeedPage())
          : const HgWebPage(),
    );
  },
);

class HgAppearanceScope extends StatefulWidget {
  const HgAppearanceScope({super.key, required this.child});

  final Widget child;

  @override
  State<HgAppearanceScope> createState() => _HgAppearanceScopeState();
}

/// HG 模块内统一推页：包一层外观主题，保证推入的子页面也跟随
/// HgPrefs.appearance（根 Navigator 不在路由 Theme 内）。
Future<T?> hgPush<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<T>(
      builder: (_) => HgAppearanceScope(child: page),
    ));

class _HgAppearanceScopeState extends State<HgAppearanceScope> {
  @override
  void initState() {
    super.initState();
    HgStore.prefs.changed.addListener(_onChanged);
  }

  @override
  void dispose() {
    HgStore.prefs.changed.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Brightness? _resolved() {
    switch (HgStore.prefs.appearance) {
      case 'light':
        return Brightness.light;
      case 'dark':
        return Brightness.dark;
      default:
        // system：取平台实际模式（外层 MaterialApp 可能已解析，但这里
        // 独立判断，避免依赖 LU 主体主题设置）。
        return SchedulerBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _resolved();
    final outer = Theme.of(context);
    final themeData = brightness == Brightness.light
        ? ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: outer.colorScheme.primary,
          )
        : ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: outer.colorScheme.primary,
          );
    return Theme(data: themeData, child: widget.child);
  }
}
