import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/emby_pip_prefs.dart';

/// 「我的 → 画中画」设置页（照 iOS 设置里「通用 → 画中画」的样子还原）。
class EmbyPipSettingsPage extends StatefulWidget {
  const EmbyPipSettingsPage({super.key});

  @override
  State<EmbyPipSettingsPage> createState() => _EmbyPipSettingsPageState();
}

class _EmbyPipSettingsPageState extends State<EmbyPipSettingsPage> {
  bool _auto = EmbyPipPrefs.autoEnter;

  Future<void> _toggle(bool value) async {
    setState(() => _auto = value);
    await EmbyPipPrefs.setAutoEnter(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '画中画',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 40),
        children: [
          PvGroup(
            children: [
              PvRow(
                icon: Icons.picture_in_picture_alt_rounded,
                iconColor: const Color(0xFF34C759),
                title: '自动开启画中画',
                trailingWidget: PvSwitch(
                  value: _auto,
                  onChanged: _toggle,
                ),
                trailing: PvRowTrailing.widget,
                showDivider: false,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(
              '回到主屏幕或切换到其他 App 时，视频将自动以画中画模式继续播放。',
              style: PvText.rowSub(context).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
