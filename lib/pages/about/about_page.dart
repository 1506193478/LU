import 'package:flutter/material.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/content_section.dart';
import 'package:XL/modules/hg/hg_lines.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/pages/about/about_widgets.dart';
import 'package:XL/request/config/api_endpoints.dart';
import 'package:XL/utils/motion.dart';

/// 「关于」标题：连点 3 次（1.5 秒窗口内）解锁隐藏的 HG 短剧底栏入口。
/// 解锁一次永久生效（存 Hive）。
class _HgUnlockTitle extends StatefulWidget {
  const _HgUnlockTitle();

  @override
  State<_HgUnlockTitle> createState() => _HgUnlockTitleState();
}

class _HgUnlockTitleState extends State<_HgUnlockTitle> {
  int _taps = 0;
  DateTime _firstTapAt = DateTime.now();

  void _onTap() {
    final now = DateTime.now();
    if (now.difference(_firstTapAt).inMilliseconds > 1500) {
      _taps = 0;
    }
    if (_taps == 0) _firstTapAt = now;
    _taps++;
    KazumiHaptics.select();
    if (_taps >= 3) {
      _taps = 0;
      _unlock();
    }
  }

  Future<void> _unlock() async {
    // 已解锁状态下再连点 3 次 = 重新隐藏入口（登录/片库数据保留）。
    if (HgStore.unlocked) {
      await HgStore.lock();
      HgAutoLine.stop();
      KazumiHaptics.heavy();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已隐藏「短剧」入口，再连点 3 次本标题可重新开启'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (mounted) setState(() {});
      return;
    }
    await HgStore.unlock();
    // 解锁后启动 HG 自动选线（镜像探测 + 健康检查）。
    HgAutoLine.start();
    KazumiHaptics.heavy();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已解锁「短剧」入口，回到主页看底栏'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: const Text('关于'),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const _HgUnlockTitle(),
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
                      icon: Icons.article_outlined,
                      title: '更新日志',
                      url: '${ApiEndpoints.sourceUrl}/releases',
                    ),
                    const AboutLinkTile.route(
                      icon: Icons.favorite_outline_rounded,
                      title: '致谢',
                      route: '/settings/about/credits',
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
            ],
          ),
        ],
      ),
    );
  }
}
