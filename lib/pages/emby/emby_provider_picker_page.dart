/// 「添加提供商」页（参考稿：Emby / Jellyfin / SMB / WebDAV / FTP / 本地 网格）。
///
/// 每个入口都接到已有实现，不自造第二套流程：
///   * Emby / Jellyfin → `/emby/servers/edit`（同一个表单）
///   * SMB / WebDAV / FTP → `showEmbyServerSheet`
///   * 本地 → 回资源库用「本地文件 / 本地私密」卡片
library;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/pages/emby/emby_server_form_page.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/theme/ios_interaction.dart';

class EmbyProviderPickerPage extends StatelessWidget {
  const EmbyProviderPickerPage({super.key});

  static const _providers = <_Provider>[
    _Provider(
      'Emby',
      '媒体库、元数据与播放进度',
      Icons.play_arrow_rounded,
      Color(0xFF2FBF5C),
      'emby',
    ),
    _Provider(
      'Jellyfin',
      '开源媒体服务器',
      Icons.play_circle_outline_rounded,
      Color(0xFF7B5CFA),
      'jellyfin',
    ),
    _Provider(
      'SMB',
      '局域网共享文件夹',
      Icons.dns_outlined,
      Color(0xFF2C2C2E),
      'smb',
    ),
    _Provider(
      'WebDAV',
      '网盘与远程目录',
      Icons.cloud_outlined,
      Color(0xFF2C2C2E),
      'webdav',
    ),
    _Provider(
      'FTP',
      '传统文件服务器',
      Icons.storage_rounded,
      Color(0xFF2C2C2E),
      'ftp',
    ),
    _Provider(
      '本地',
      '本机或 iCloud 中的文件夹',
      Icons.smartphone_rounded,
      Color(0xFF2C2C2E),
      'local',
    ),
  ];

  Future<void> _pick(BuildContext context, _Provider p) async {
    if (p.type == 'emby' || p.type == 'jellyfin') {
      await context.pushNamed('/emby/servers/edit');
      return;
    }
    if (p.type == 'local') {
      // 本地来源在资源库里（本地文件 / 本地私密 / 相册），不在这里再开一套。
      await context.pushNamed('/emby');
      return;
    }
    await showEmbyServerSheet(context, type: p.type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context) - 8, 6, embyPagePadding(context), 8),
              child: Row(
                children: [
                  KzPressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    pressedOpacity: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.chevron_left_rounded,
                          size: 26, color: PvColors.blue),
                    ),
                  ),
                  Text(
                    '添加提供商',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: PvColors.ink(context),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context), 4, embyPagePadding(context), 0),
              child: Text(
                '选择提供商',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: PvColors.ink(context),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context), 4, embyPagePadding(context), 14),
              child: Text(
                '选择媒体服务器或存储位置',
                style: TextStyle(
                  fontSize: 12.5,
                  color: PvColors.ink3(context),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(embyPagePadding(context), 0,
                    embyPagePadding(context), 32),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.32,
                ),
                itemCount: _providers.length,
                itemBuilder: (context, i) => _ProviderCard(
                  provider: _providers[i],
                  onTap: () => _pick(context, _providers[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Provider {
  const _Provider(this.name, this.desc, this.icon, this.tint, this.type);

  final String name;
  final String desc;
  final IconData icon;
  final Color tint;
  final String type;
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.onTap});

  final _Provider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.75,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(provider.icon, size: 22, color: provider.tint),
            ),
            const Spacer(),
            Text(
              provider.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: PvColors.ink(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              provider.desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: PvColors.ink3(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
