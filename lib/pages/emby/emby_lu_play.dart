import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';

/// 本地 / 直链播放的公共入口。
///
/// 资源库里导入的东西（本地文件、相册视频、网络链接、WebDAV 网盘）没有
/// Emby 服务器，所以这里造一个"本地"服务器壳子，播放器照样能用，只是
/// 不往服务端上报进度。
void luPlay(
  BuildContext context, {
  required String title,
  required String url,
  String subtitle = '',
  List<({String title, String url})>? playlist,
  int index = 0,
}) {
  final items = <EmbyItem>[];
  final list = playlist ?? [(title: title, url: url)];
  for (var i = 0; i < list.length; i++) {
    items.add(
      EmbyItem(
        id: 'local-$i',
        name: list[i].title,
        type: 'Movie',
        directUrl: list[i].url,
      ),
    );
  }
  final start = index.clamp(0, items.length - 1);

  context.pushNamed(
    '/emby/player',
    arguments: EmbyPlaybackLaunch(
      server: const EmbyServer(
        id: 'local',
        name: '本地资源',
        url: '',
        userId: '',
        userName: '',
        accessToken: '',
      ),
      title: title,
      episodes: items,
      initialIndex: start,
    ),
  );
}
