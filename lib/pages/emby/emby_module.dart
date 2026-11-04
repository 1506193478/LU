import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_detail_page.dart';
import 'package:XL/pages/emby/emby_library_page.dart';
import 'package:XL/pages/emby/emby_page.dart';
import 'package:XL/pages/emby/emby_search_page.dart';
import 'package:XL/pages/emby/emby_server_page.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/emby/player/emby_player_page.dart';
import 'package:XL/pages/route_error_page.dart';

/// Emby 媒体库。
///
/// 整块挂在 `/emby` 下，和插件源、离线下载互不影响：
/// 它不走 WebView 解析，也不需要 `PluginsController`。
final embyModule = createModule(
  path: '/emby',
  register: (c) {
    c
      ..route('/', child: (context, state) => const EmbyPage())
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
        '/search',
        child: (context, state) {
          // 参数是服务器 id 时只搜那一台（首页右上角的搜索按钮）；
          // 不带参数就是全服务器搜索。
          final args = state.arguments;
          return EmbySearchPage(serverId: args is String ? args : null);
        },
      )
      ..route(
        '/player',
        child: (context, state) {
          final args = state.arguments;
          if (args is! EmbyPlaybackLaunch) {
            return const RouteErrorPage(message: '播放参数无效，请返回后重试。');
          }
          return EmbyPlayerPage(launch: args);
        },
      )
      ..route('/servers', child: (context, state) => const EmbyServerPage())
      ..route(
        '/servers/edit',
        child: (context, state) {
          final args = state.arguments;
          return EmbyServerEditPage(server: args is EmbyServer ? args : null);
        },
      );
  },
);

/// Emby 作为底栏页签时的壳路由。
///
/// 只挂首页一条路由；详情 / 播放 / 服务器管理仍然走根部的 [embyModule]
/// （`/emby/detail` 等绝对路径）。这样页签状态归 tab 壳管，
/// 二级页照旧从根部推入，不需要把所有 `pushNamed('/emby/...')` 改路径。
final embyTabModule = createModule(
  path: '/emby',
  register: (c) {
    c.route('/', child: (context, state) => const EmbyPage());
  },
);
