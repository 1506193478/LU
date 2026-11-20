import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/player_button_prefs.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 播放器按钮设置（对应 SenPlayer 的 `kShowPlayerXxxButton`：按钮逐个开关）。
///
/// 按 顶栏 / 底栏 / 工具行 分组；播放/暂停不可隐藏（否则无法控制播放）。
/// 改完 revision +1，播放器监听后即时刷新控制栏，无需退出重进。
class EmbyPlayerButtonsPage extends StatefulWidget {
  const EmbyPlayerButtonsPage({super.key});

  @override
  State<EmbyPlayerButtonsPage> createState() => _EmbyPlayerButtonsPageState();
}

class _EmbyPlayerButtonsPageState extends State<EmbyPlayerButtonsPage> {
  final PlayerButtonPrefs _prefs = PlayerButtonPrefs.instance;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<({String id, String label, String group})>>{};
    for (final button in PlayerButtonPrefs.buttons) {
      (groups.putIfAbsent(button.group, () => [])).add(button);
    }

    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        leading: const KzBackButton(),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('播放器按钮'),
        actions: [
          KzPressable(
            pressedOpacity: 0.5,
            onTap: () {
              _prefs.resetAll();
              setState(() {});
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('全部显示'),
            ),
          ),
        ],
      ),
      // 从全屏播放器推过来时系统栏还是 immersiveSticky，SafeArea 保证
      // 第一行不会被刘海/状态栏压住。
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '逐个开关播放器控制栏的按钮。播放/暂停始终保留。',
                style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
              ),
            ),
            for (final entry in groups.entries) ...[
              PvGroupLabel(entry.key),
              PvGroup(
                children: [
                  for (final button in entry.value)
                    KzSwitchTile(
                      title: Text(button.label),
                      subtitle: button.id == 'play'
                          ? const Text('始终显示，无法隐藏')
                          : null,
                      value: _prefs.shown(button.id),
                      onChanged: button.id == 'play'
                          ? null
                          : (value) {
                              _prefs.setShown(button.id, value);
                              setState(() {});
                            },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
