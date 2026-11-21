import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/pages/menu/route_visibility.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/my/my_controller.dart';
import 'package:XL/pages/my/my_space_view.dart';
import 'package:XL/pages/my/watch_report_page.dart';

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
        MyDestination.notifications => '/settings/notifications',
        MyDestination.danmaku => '/settings/danmaku/',
        MyDestination.rules => '/settings/plugin/',
        MyDestination.history => '/settings/history/',
        MyDestination.downloads => '/settings/download/',
        MyDestination.sync => '/settings/sync',
        MyDestination.storage => '/settings/storage',
        MyDestination.about => '/settings/about/',
        MyDestination.emby => '/tab/emby/',
        MyDestination.proxy => '/settings/proxy/',
        // 上面已经提前 return，这里只是让 switch 穷尽。
        MyDestination.timeline => '/tab/timeline/',
        MyDestination.report => '/my/',
      });
  }

  @override
  Widget build(BuildContext context) {
    // 预览稿「我的」页是页内 34px 大标题（.page-title），不走 AppBar。
    return Scaffold(
      // 内容层早就是 Pv 了，外壳还留着拟态底色，一页里两套材质最扎眼。
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PvPageHead(
              title: '我的',
              actions: [
                PvIconBtn(
                  icon: Icons.settings_outlined,
                  tooltip: '设置',
                  onTap: () => context.pushNamed('/settings/'),
                ),
              ],
              topPadding: 10,
            ),
            // 时间段问候（巧思 #19）：按当前时间换文案与暖/冷色调，
            // 顺带把「已看 N 集」用数字滚动带出来。
            _TimeGreeting(watched: widget.controller.watchStats.watchedEpisodeCount),
            Expanded(
              child: Observer(
                builder: (context) => MySpaceView(
                  stats: widget.controller.watchStats,
                  onOpen: _open,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 时间段问候 + 已看集数滚动（巧思 #19 / #03）。
///
/// 深夜/傍晚给暖色光、白天给清透蓝，随系统时间换文案；
/// 「已看 N 集」从 0 滚到实际值（进页只放一次，不重复闪）。
class _TimeGreeting extends StatelessWidget {
  const _TimeGreeting({required this.watched});

  final int watched;

  @override
  Widget build(BuildContext context) {
    final int hour = DateTime.now().hour;
    final (String text, IconData icon, Color tint) = switch (hour) {
      >= 5 && < 10 => ('早上好，从追番开始新的一天', Icons.wb_twilight_rounded, const Color(0xFFFFD9A8)),
      >= 10 && < 17 => ('午后好，来一集轻松的', Icons.wb_sunny_rounded, const Color(0xFFBFE0FF)),
      >= 17 && < 22 => ('傍晚好，继续追番时间', Icons.nights_stay_rounded, const Color(0xFFD9BFFF)),
      _ => ('夜深了，别熬太晚', Icons.dark_mode_rounded, const Color(0xFFB9A8E8)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: PvColors.ink2(context),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: watched.toDouble()),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) {
              return Text(
                '已看 ${v.round()} 集',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink3(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
