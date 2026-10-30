import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_library_page.dart';
import 'package:XL/pages/emby/emby_page.dart';
import 'package:XL/pages/emby/emby_server_page.dart';
import 'package:XL/pages/route_error_page.dart';

/// Emby 媒体库。
///
/// 整块挂在 `/emby` 下，和插件源、离线下载互不影响：
/// 它不走 WebView 解析，也不需要 `PluginsController`。
final embyModule = createModule(
  path: '/emby',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const EmbyPage(),
      )
      ..route(
        '/library',
        child: (context, state) {
          final args = state.arguments;
          if (args is! EmbyLibrary) {
            return const RouteErrorPage(message: '媒体库参数无效，请返回后重试。');
          }
          return EmbyLibraryPage(library: args);
        },
      )
      ..route(
        '/detail',
        child: (context, state) {
          final args = state.arguments;
          if (args is! EmbyItem) {
            return const RouteErrorPage(message: '条目参数无效，请返回后重试。');
          }
          return EmbyDetailPage(item: args);
        },
      )
      ..route(
        '/servers',
        child: (context, state) => const EmbyServerPage(),
      )
      ..route(
        '/servers/edit',
        child: (context, state) {
          final args = state.arguments;
          return EmbyServerEditPage(server: args is EmbyServer ? args : null);
        },
      );
  },
);
