import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/appbar/sys_app_bar.dart';
import 'package:XL/pages/menu/route_visibility.dart';
import 'package:XL/pages/my/my_controller.dart';
import 'package:XL/pages/my/my_space_view.dart';
import 'package:XL/pages/my/watch_report_page.dart';
import 'package:XL/bean/widget/clay_neu.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key, required this.controller});

  final MyController controller;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setAttached(!RouteVisibility.isCoveredOf(context));
  }

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach();
    }
  }

  @override
  void dispose() {
    _setAttached(false);
    super.dispose();
  }

  void _setAttached(bool value) {
    if (_attached == value) return;
    _attached = value;
    if (value) {
      widget.controller.attach();
    } else {
      widget.controller.detach();
    }
  }

  void _open(MyDestination destination) {
    if (destination == MyDestination.report) {
      // 年报不是设置页，直接推一个页面，不用往模块路由表里加东西。
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WatchReportPage(
            histories: widget.controller.histories,
          ),
        ),
      );
      return;
    }
    context.pushNamed(switch (destination) {
        MyDestination.theme => '/settings/theme',
        MyDestination.player => '/settings/player',
        MyDestination.danmaku => '/settings/danmaku/',
        MyDestination.rules => '/settings/plugin/',
        MyDestination.history => '/settings/history/',
        MyDestination.downloads => '/settings/download/',
        MyDestination.sync => '/settings/sync',
        MyDestination.storage => '/settings/storage',
        MyDestination.about => '/settings/about/',
        MyDestination.emby => '/emby/',
        // 上面已经提前 return，这里只是让 switch 穷尽。
        MyDestination.report => '/my/',
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neuScaffoldBackground(context),
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '我的',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MySettingsButton(
              onTap: () => context.pushNamed('/settings/'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) => MySpaceView(
            stats: widget.controller.watchStats,
            onOpen: _open,
          ),
        ),
      ),
    );
  }
}
