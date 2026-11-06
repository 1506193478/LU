import 'package:flutter/material.dart';

import 'package:XL/bean/dialog/dialog.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_setting_rows.dart';
import 'package:XL/services/platform/cast_service.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 「播放行为」：把原来散落在「我的 → 播放器」里的七个开关收成一处。
///
/// 3.9.59 之前「我的」页是两组 18 行，光「播放器」这一组就占了一屏半，
/// 想找「弹幕」要往下翻很久。这里只重排、不删功能：主页面按职能分四组，
/// 七个开关型选项整组搬到这里，主页面 18 项降到 14 项。
///
/// 设置键沿用原来的 `pv.*`，所以升级后用户的选择不会丢。
class EmbyPlayBehaviorPage extends StatelessWidget {
  const EmbyPlayBehaviorPage({super.key});

  Future<void> _openCast(BuildContext context) async {
    if (!CastService.supported) {
      KazumiDialog.showError(message: '当前平台没有系统投屏可用');
      return;
    }
    try {
      final bool ok = await CastService.open();
      if (!ok && context.mounted) {
        KazumiDialog.showError(message: '这台设备上找不到系统投屏入口');
      }
    } on CastUnsupported catch (e) {
      KazumiDialog.showError(message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 背景由壳层提供，这里不再重复铺一层。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const _PvNavBar(title: '播放行为'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: <Widget>[
                  const PvGroupLabel('字幕'),
                  PvGroup(
                    children: const <Widget>[
                      PvSwitchRow(
                        icon: Icons.subtitles_rounded,
                        iconColor: Color(0xFF5E5CE6),
                        title: '双字幕',
                        subtitle: '主字幕 + 第二路同时显示',
                        prefKey: 'pv.doubleSubtitle',
                        defaultValue: true,
                      ),
                      PvSwitchRow(
                        icon: Icons.translate_rounded,
                        iconColor: Color(0xFFFF375F),
                        title: '字幕翻译',
                        subtitle: '简繁转换 · 跟随字幕设置',
                        prefKey: 'pv.subtitleTranslate',
                        defaultValue: false,
                        showDivider: false,
                      ),
                    ],
                  ),
                  const PvGroupLabel('弹幕'),
                  PvGroup(
                    children: const <Widget>[
                      PvSwitchRow(
                        icon: Icons.emoji_emotions_outlined,
                        iconColor: Color(0xFF30B0C7),
                        title: '弹幕',
                        subtitle: 'Emby 源默认关闭',
                        prefKey: 'pv.danmaku',
                        defaultValue: true,
                        showDivider: false,
                      ),
                    ],
                  ),
                  const PvGroupLabel('播放'),
                  PvGroup(
                    children: const <Widget>[
                      PvSwitchRow(
                        icon: Icons.skip_next_rounded,
                        iconColor: Color(0xFF8E8E93),
                        title: '片头片尾跳过',
                        subtitle: '按剧集记忆标记',
                        prefKey: 'pv.introOutroSkip',
                        defaultValue: true,
                      ),
                      PvSwitchRow(
                        icon: Icons.screen_lock_portrait_rounded,
                        iconColor: Color(0xFFFF9F0A),
                        title: '上滑锁定屏幕',
                        subtitle: '播放中上滑进入锁定',
                        prefKey: 'pv.swipeLock',
                        defaultValue: true,
                      ),
                      PvSwitchRow(
                        icon: Icons.desktop_access_disabled_rounded,
                        iconColor: Color(0xFF34C759),
                        title: '关屏后返回首页',
                        subtitle: '息屏即退出播放器',
                        prefKey: 'pv.backOnScreenOff',
                        defaultValue: false,
                        showDivider: false,
                      ),
                    ],
                  ),
                  const PvGroupLabel('输出'),
                  PvGroup(
                    children: <Widget>[
                      Builder(
                        builder: (ctx) => PvRow(
                          icon: Icons.cast_rounded,
                          iconColor: const Color(0xFF0A84FF),
                          title: '投屏',
                          subtitle: 'AirPlay / DLNA',
                          value: CastService.supported ? '未连接' : '不支持',
                          onTap: () => _openCast(ctx),
                          showDivider: false,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      '这七项只换了位置，键名和默认值都没变。',
                      style: PvText.rowSub(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级页顶栏：居中标题 + 左侧返回，和系统导航栏同一套度量。
class _PvNavBar extends StatelessWidget {
  const _PvNavBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        children: <Widget>[
          Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: PvColors.ink(context),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: KzPressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                      color: PvColors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '我的',
                      style: TextStyle(fontSize: 17, color: PvColors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
