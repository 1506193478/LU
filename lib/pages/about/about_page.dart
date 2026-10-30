import 'package:flutter/material.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/content_section.dart';
import 'package:XL/pages/about/about_widgets.dart';
import 'package:XL/request/config/api_endpoints.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('关于'),
        body: AboutContent(
          children: [
            _ProjectHeader(onCheckUpdate: onCheckUpdate),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              // 只剩「开源」这一组了，宽屏也不再分两栏。
              final sections = <Widget>[
                ContentSection.group(
                  title: '开源',
                  children: [
                    const AboutLinkTile(
                      icon: Icons.handshake_outlined,
                      title: '贡献指南',
                      url:
                          '${ApiEndpoints.sourceUrl}/blob/main/static/doc/CONTRIBUTING.md',
                    ),
                    const AboutLinkTile.route(
                      icon: Icons.favorite_outline_rounded,
                      title: '致谢',
                      route: '/settings/about/credits',
                    ),
                    const AboutLinkTile(
                      icon: Icons.balance_rounded,
                      title: 'GPL-3.0 许可证',
                      url: '${ApiEndpoints.sourceUrl}/blob/main/LICENSE',
                    ),
                    const AboutLinkTile.route(
                      icon: Icons.description_outlined,
                      title: '第三方许可证',
                      route: '/settings/about/license',
                    ),
                  ],
                ),
              ];
              if (constraints.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(14) < 21) {
                // 宽屏时限制一下宽度，别让四行链接拉成一条长带。
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: sections[0],
                  ),
                );
              }
              return Column(children: sections);
            }),
          ],
        ),
      );
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'LU',
              style: theme.textTheme.displayMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ApiEndpoints.version,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '只想和你看❤',
            style: theme.textTheme.headlineMedium?.copyWith(
              // 站酷快乐体：圆润的手写体，跟原来那行正文字体不是一个味道。
              fontFamily: 'ZCOOLKuaiLe',
              fontSize: 30,
              height: 1.3,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CheckUpdateButton(onCheckUpdate: onCheckUpdate),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => openAboutLink(
                  context,
                  '${ApiEndpoints.sourceUrl}/releases',
                ),
                child: const Text('更新日志'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
