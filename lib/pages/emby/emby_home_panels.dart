/// Emby 首页的两个浮层：服务器胶囊面板、媒体库面板。
///
/// 都按参考稿做成「从右上胶囊长出来的浮层卡片」：圆角 22、半透明材质、
/// 顶部一行标题 + 右上一个主线路胶囊，下面是内容；进出都是 180ms 的
/// 淡入 + 轻微缩放，点击遮罩收起。
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_line_probe.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/theme/ios_interaction.dart' show KzPressable;

const double _panelWidth = 322;

/// 打开「服务器胶囊」面板。
///
/// 内容（对齐参考稿）：线路卡片（当前服务器的所有线路 + 延迟 + 当前项打勾）、
/// 发现 / 搜索 / 媒体库 / 设置。
Future<void> showEmbyCapsulePanel(
  BuildContext context, {
  required EmbyServer server,
  required VoidCallback onOpenDiscover,
  required VoidCallback onOpenSearch,
  required VoidCallback onOpenMediaLibrary,
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenManage,
}) {
  return _showPanel(
    context,
    builder: (close) => _CapsulePanel(
      server: server,
      onClose: close,
      onOpenDiscover: onOpenDiscover,
      onOpenSearch: onOpenSearch,
      onOpenMediaLibrary: onOpenMediaLibrary,
      onOpenSettings: onOpenSettings,
      onOpenManage: onOpenManage,
    ),
  );
}

/// 打开「媒体库」面板：服务器列表 / 网格切换、设置入口、添加入口。
Future<void> showEmbyMediaLibraryPanel(
  BuildContext context, {
  required VoidCallback onOpenManage,
  required VoidCallback onAddProvider,
  required ValueChanged<EmbyServer> onSwitch,
}) {
  return _showPanel(
    context,
    builder: (close) => _MediaLibraryPanel(
      onClose: close,
      onOpenManage: onOpenManage,
      onAddProvider: onAddProvider,
      onSwitch: onSwitch,
    ),
  );
}

Future<void> _showPanel(
  BuildContext context, {
  required Widget Function(VoidCallback close) builder,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x22000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) {
      void close() => Navigator.of(ctx).maybePop();
      return SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(
              top: 56,
              right: embyPagePadding(ctx).clamp(8.0, 20.0),
            ),
            child: builder(close),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

/// 半透明浮层底板。
class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child, this.width = _panelWidth});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xF21C1C1F)
                    : const Color(0xF7F4F2EE),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.7),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2A000000),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行图标 + 文字（发现 / 搜索 / 媒体库 / 设置共用）。
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color ink = PvColors.ink(context);
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: destructive ? PvColors.red : ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: destructive ? PvColors.red : ink,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 小号分组标题（配置）。
class _PanelSectionLabel extends StatelessWidget {
  const _PanelSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: PvColors.ink3(context),
        ),
      ),
    );
  }
}

/* ────────────────────────────── 胶囊面板 ────────────────────────────── */

class _CapsulePanel extends StatefulWidget {
  const _CapsulePanel({
    required this.server,
    required this.onClose,
    required this.onOpenDiscover,
    required this.onOpenSearch,
    required this.onOpenMediaLibrary,
    required this.onOpenSettings,
    required this.onOpenManage,
  });

  final EmbyServer server;
  final VoidCallback onClose;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMediaLibrary;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenManage;

  @override
  State<_CapsulePanel> createState() => _CapsulePanelState();
}

class _CapsulePanelState extends State<_CapsulePanel> {
  late List<String> _lines;
  Map<String, int?> _latency = const {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _lines = _collectLines(widget.server);
    _probe();
  }

  List<String> _collectLines(EmbyServer server) {
    final seen = <String>{};
    final out = <String>[];
    for (final url in [server.url, ...server.backupUrls]) {
      final t = url.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      out.add(t);
    }
    return out;
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() => _probing = true);
    final res = await EmbyLineProbe.probeAll(_lines);
    if (!mounted) return;
    setState(() {
      _latency = res;
      _probing = false;
    });
  }

  /// 切线路：把选中的线路提到主线路位置，其余按原顺序跟随。
  Future<void> _switchLine(String url) async {
    final server = widget.server;
    if (server.url.trim() == url.trim()) return;
    final rest = <String>[
      server.url,
      ...server.backupUrls,
    ].where((u) => u.trim() != url.trim()).toList();
    await EmbyService.instance.upsert(server.copyWith(
      url: url.trim(),
      backupUrls: rest,
    ));
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return _PanelShell(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行：媒体 + 当前线路胶囊。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.video_library_outlined,
                      size: 17, color: PvColors.ink(context)),
                  const SizedBox(width: 8),
                  Text(
                    '媒体',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PvColors.ink(context),
                    ),
                  ),
                  const Spacer(),
                  KzPressable(
                    onTap: _probe,
                    pressedOpacity: 0.6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _probing
                              ? SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    color: PvColors.ink2(context),
                                  ),
                                )
                              : Icon(Icons.hub_outlined,
                                  size: 12, color: PvColors.ink2(context)),
                          const SizedBox(width: 4),
                          Text(
                            '主线路',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: PvColors.ink2(context),
                            ),
                          ),
                          Icon(Icons.expand_less_rounded,
                              size: 14, color: PvColors.ink3(context)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 线路卡片。
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.055)
                    : Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _lines.length; i++)
                    _LineRow(
                      url: _lines[i],
                      selected: _lines[i] == widget.server.url.trim(),
                      latency: _latency[_lines[i]],
                      probing: _probing && !_latency.containsKey(_lines[i]),
                      showDivider: i != _lines.length - 1,
                      onTap: () => _switchLine(_lines[i]),
                    ),
                  if (_lines.length <= 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: PvColors.ink3(context)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '还没有备用线路，去「设置 → 管理媒体库」添加',
                              style: TextStyle(
                                fontSize: 12,
                                color: PvColors.ink3(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _PanelRow(
              icon: Icons.explore_outlined,
              label: '发现',
              onTap: () {
                widget.onClose();
                widget.onOpenDiscover();
              },
            ),
            _PanelRow(
              icon: Icons.search_rounded,
              label: '搜索',
              onTap: () {
                widget.onClose();
                widget.onOpenSearch();
              },
            ),
            _PanelRow(
              icon: Icons.video_library_outlined,
              label: '媒体库',
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 18, color: PvColors.chev(context)),
              onTap: () {
                widget.onClose();
                widget.onOpenMediaLibrary();
              },
            ),
            _PanelSectionLabel('配置'),
            _PanelRow(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () {
                widget.onClose();
                widget.onOpenSettings();
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.url,
    required this.selected,
    required this.latency,
    required this.probing,
    required this.showDivider,
    required this.onTap,
  });

  final String url;
  final bool selected;
  final int? latency;
  final bool probing;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = PvColors.ink(context);
    final String host = Uri.tryParse(url)?.host ?? url;
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.55,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(color: PvColors.hair(context), width: 0.6),
                )
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: 15,
              color: selected ? PvColors.green : PvColors.ink3(context),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主线路',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: PvColors.ink3(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (probing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: PvColors.ink3(context),
                ),
              )
            else
              Text(
                EmbyLineProbe.label(latency),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: latency == null
                      ? PvColors.ink3(context)
                      : PvColors.green,
                ),
              ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_rounded, size: 16, color: PvColors.blue),
            ],
          ],
        ),
      ),
    );
  }
}

/* ────────────────────────────── 媒体库面板 ────────────────────────────── */

class _MediaLibraryPanel extends StatefulWidget {
  const _MediaLibraryPanel({
    required this.onClose,
    required this.onOpenManage,
    required this.onAddProvider,
    required this.onSwitch,
  });

  final VoidCallback onClose;
  final VoidCallback onOpenManage;
  final VoidCallback onAddProvider;
  final ValueChanged<EmbyServer> onSwitch;

  @override
  State<_MediaLibraryPanel> createState() => _MediaLibraryPanelState();
}

class _MediaLibraryPanelState extends State<_MediaLibraryPanel> {
  bool _grid = false;

  @override
  Widget build(BuildContext context) {
    final service = EmbyService.instance;
    final bool dark = PvColors.isDark(context);
    return ValueListenableBuilder<int>(
      valueListenable: service.revision,
      builder: (context, _, __) {
        final servers = service.servers;
        final active = service.activeServer;
        return _PanelShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 标题行：‹ 媒体库 | 列表/网格切换 | 设置 | +
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 8, 8),
                  child: Row(
                    children: [
                      KzPressable(
                        onTap: widget.onClose,
                        pressedOpacity: 0.5,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.chevron_left_rounded,
                              size: 22, color: PvColors.ink(context)),
                        ),
                      ),
                      Text(
                        '媒体库',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: PvColors.ink(context),
                        ),
                      ),
                      const Spacer(),
                      _MiniButton(
                        icon: _grid
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                        onTap: () => setState(() => _grid = !_grid),
                      ),
                      const SizedBox(width: 4),
                      _MiniButton(
                        icon: Icons.settings_outlined,
                        onTap: () {
                          widget.onClose();
                          widget.onOpenManage();
                        },
                      ),
                      const SizedBox(width: 4),
                      _MiniButton(
                        icon: Icons.add_rounded,
                        filled: true,
                        onTap: () {
                          widget.onClose();
                          widget.onAddProvider();
                        },
                      ),
                    ],
                  ),
                ),
                if (servers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                    child: Text(
                      '还没有添加媒体库',
                      style: TextStyle(
                        fontSize: 13,
                        color: PvColors.ink3(context),
                      ),
                    ),
                  )
                else if (_grid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in servers)
                          SizedBox(
                            width: (_panelWidth - 38) / 3,
                            child: _GridTile(
                              server: s,
                              selected: s.id == active?.id,
                              onTap: () async {
                                widget.onClose();
                                widget.onSwitch(s);
                              },
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.055)
                          : Colors.white.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < servers.length; i++)
                          _ServerLineTile(
                            server: servers[i],
                            selected: servers[i].id == active?.id,
                            showDivider: i != servers.length - 1,
                            onTap: () async {
                              widget.onClose();
                              widget.onSwitch(servers[i]);
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.6,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: filled
              ? PvColors.blue.withValues(alpha: 0.92)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: filled ? Colors.white : PvColors.ink2(context),
        ),
      ),
    );
  }
}

class _ServerLineTile extends StatelessWidget {
  const _ServerLineTile({
    required this.server,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final EmbyServer server;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.55,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(color: PvColors.hair(context), width: 0.6),
                )
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            const _ServerGlyph(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: PvColors.ink(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    Uri.tryParse(server.url)?.host ?? server.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: PvColors.ink3(context),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 16, color: PvColors.blue),
          ],
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.server,
    required this.selected,
    required this.onTap,
  });

  final EmbyServer server;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.6,
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: PvColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ServerGlyph(size: 24),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: PvColors.ink(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.check_rounded,
                    size: 14, color: PvColors.ink(context)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 绿色圆角播放图标（参考稿的服务器标识）。
class _ServerGlyph extends StatelessWidget {
  const _ServerGlyph({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PvColors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.play_arrow_rounded,
        size: size * 0.78,
        color: PvColors.green,
      ),
    );
  }
}
