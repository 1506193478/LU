/// 「管理媒体库」页（参考稿：已添加列表 + 排序 + 添加 + 每行长按菜单）。
///
/// 与旧的 [EmbyServerPage]（Material 设置页）并存：胶囊面板的「设置」和
/// 媒体库面板的齿轮都进这里，视觉按参考稿做成玻璃卡片列表。
library;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/theme/lu_glass.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_line_probe.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/theme/ios_interaction.dart';

class EmbyMediaManagePage extends StatefulWidget {
  const EmbyMediaManagePage({super.key});

  @override
  State<EmbyMediaManagePage> createState() => _EmbyMediaManagePageState();
}

class _EmbyMediaManagePageState extends State<EmbyMediaManagePage> {
  /// 每台服务器的连通状态文案（null = 未测）。
  final Map<String, String> _latency = <String, String>{};
  final Map<String, bool> _probing = <String, bool>{};

  Future<void> _testConnection(EmbyServer server) async {
    setState(() => _probing[server.id] = true);
    final ms = await EmbyLineProbe.probe(server.url);
    if (!mounted) return;
    setState(() {
      _probing[server.id] = false;
      _latency[server.id] = EmbyLineProbe.label(ms);
    });
  }

  Future<void> _openEditor(EmbyServer? server) async {
    await context.pushNamed('/emby/servers/edit', arguments: server);
  }

  Future<void> _openLines(EmbyServer server) async {
    await context.pushNamed('/emby/lines', arguments: server);
  }

  Future<void> _delete(EmbyServer server) async {
    final ok = await showKzConfirm(
      context: context,
      title: '删除「${server.name}」？',
      message: '只会删除 LU 里保存的地址和登录凭据，不影响服务端。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!ok) return;
    await EmbyService.instance.remove(server.id);
  }

  Future<void> _openRowMenu(EmbyServer server) async {
    const labels = ['编辑配置', '测试连接', '配置备用线路', '调整顺序', '删除'];
    const icons = [
      Icons.tune_rounded,
      Icons.show_chart_rounded,
      Icons.hub_outlined,
      Icons.swap_vert_rounded,
      Icons.delete_outline_rounded,
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ActionSheet(
        title: server.name,
        labels: labels,
        icons: icons,
      ),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 0:
        await _openEditor(server);
      case 1:
        await _testConnection(server);
      case 2:
        await _openLines(server);
      case 3:
        await _openReorder();
      case 4:
        await _delete(server);
    }
  }

  Future<void> _openReorder() async {
    final servers = List<EmbyServer>.of(EmbyService.instance.servers);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReorderSheet(servers: servers),
    );
  }

  Future<void> _openAddProvider() async {
    await context.pushNamed('/emby/providers');
  }

  @override
  Widget build(BuildContext context) {
    final service = EmbyService.instance;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: service.revision,
          builder: (context, _, __) {
            final servers = service.servers;
            final active = service.activeServer;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      embyPagePadding(context) - 8, 6, embyPagePadding(context), 4),
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
                        '管理媒体库',
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
                      embyPagePadding(context), 10, embyPagePadding(context), 8),
                  child: Row(
                    children: [
                      Text(
                        '已添加 ${servers.length}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PvColors.ink(context),
                        ),
                      ),
                      const Spacer(),
                      _CircleBtn(
                        icon: Icons.swap_vert_rounded,
                        onTap: servers.length > 1 ? _openReorder : null,
                      ),
                      const SizedBox(width: 10),
                      _CircleBtn(
                        icon: Icons.add_rounded,
                        filled: true,
                        onTap: _openAddProvider,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: servers.isEmpty
                      ? Center(
                          child: Text(
                            '还没有添加媒体库',
                            style: TextStyle(
                                fontSize: 14, color: PvColors.ink3(context)),
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                              embyPagePadding(context), 4,
                              embyPagePadding(context), 40),
                          children: [
                            // 液态玻璃 v2 分组卡 + 长按拖拽排序（B24）：
                            // ReorderableListView 自带弹簧让位动画，松手即落库。
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, child) => Opacity(
                                opacity: t.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, (1 - t) * 14),
                                  child: child,
                                ),
                              ),
                              child: LuGlass.box(
                                context: context,
                                blur: true,
                                radius: BorderRadius.circular(16),
                                child: ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: servers.length,
                                  onReorder: (oldIndex, newIndex) async {
                                    setState(() {
                                      if (newIndex > oldIndex) newIndex -= 1;
                                      final moved = servers.removeAt(oldIndex);
                                      servers.insert(newIndex, moved);
                                    });
                                    await EmbyService.instance
                                        .reorder(servers.map((s) => s.id).toList());
                                  },
                                  proxyDecorator: (child, index, anim) =>
                                      AnimatedBuilder(
                                    animation: anim,
                                    builder: (context, _) {
                                      final t = Curves.easeOut
                                          .transform(anim.value.clamp(0.0, 1.0));
                                      return Transform.scale(
                                        scale: 1 + 0.03 * t,
                                        child: Material(
                                          color: Colors.transparent,
                                          elevation: 6 * t,
                                          shadowColor: Colors.black45,
                                          borderRadius: BorderRadius.circular(14),
                                          child: child,
                                        ),
                                      );
                                    },
                                  ),
                                  itemBuilder: (context, i) {
                                    final s = servers[i];
                                    return ReorderableDragStartListener(
                                      key: ValueKey(s.id),
                                      index: i,
                                      child: _ManageRow(
                                        server: s,
                                        active: s.id == active?.id,
                                        status: _probing[s.id] == true
                                            ? '测试中…'
                                            : _latency[s.id],
                                        lineCount: s.backupUrls.length + 1,
                                        showDivider: i != servers.length - 1,
                                        onTap: () => _openEditor(s),
                                        onMenu: () => _openRowMenu(s),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                '长按条目拖动可调整顺序',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: PvColors.ink3(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.server,
    required this.active,
    required this.status,
    required this.lineCount,
    required this.showDivider,
    required this.onTap,
    required this.onMenu,
  });

  final EmbyServer server;
  final bool active;
  final String? status;
  final int lineCount;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      onLongPress: onMenu,
      pressedOpacity: 0.55,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(color: PvColors.hair(context), width: 0.6),
                )
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PvColors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child:
                  Icon(Icons.play_arrow_rounded, size: 22, color: PvColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: PvColors.ink(context),
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_rounded,
                            size: 14, color: PvColors.ink(context)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Emby · ${lineCount > 1 ? '$lineCount 条线路' : Uri.tryParse(server.url)?.host ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, color: PvColors.ink3(context)),
                  ),
                ],
              ),
            ),
            if (status != null) ...[
              Text(
                status!,
                style: TextStyle(
                  fontSize: 12,
                  color: status == '超时'
                      ? PvColors.ink3(context)
                      : PvColors.green,
                ),
              ),
              const SizedBox(width: 4),
            ],
            KzPressable(
              onTap: onMenu,
              pressedOpacity: 0.5,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.more_horiz_rounded,
                    size: 20, color: PvColors.ink2(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, this.onTap, this.filled = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.6,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: filled
              ? PvColors.blue
              : (dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.7)),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 19,
          color: filled
              ? Colors.white
              : (onTap == null ? PvColors.ink3(context) : PvColors.ink(context)),
        ),
      ),
    );
  }
}

/// 调整顺序（拖动右侧把手）。
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.servers});

  final List<EmbyServer> servers;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late List<EmbyServer> _list = List<EmbyServer>.of(widget.servers);
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await EmbyService.instance.reorder(_list.map((e) => e.id).toList());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C1F) : const Color(0xFFF7F5F1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.only(bottom: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
              child: Row(
                children: [
                  Text(
                    '调整顺序',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PvColors.ink(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: (56.0 * _list.length).clamp(120.0, 420.0),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _list.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _list.removeAt(oldIndex);
                    _list.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final s = _list[index];
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(s.id),
                    index: index,
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: PvColors.green.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.play_arrow_rounded,
                                size: 18, color: PvColors.green),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: PvColors.ink(context),
                                  ),
                                ),
                                Text(
                                  'Emby',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: PvColors.ink3(context)),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.drag_handle_rounded,
                              size: 20, color: PvColors.ink3(context)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS 风格操作表（长按行 / 「…」按钮）。
class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.labels,
    required this.icons,
  });

  final String title;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xF21F1F22) : const Color(0xF7FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    KzPressable(
                      onTap: () => Navigator.of(context).pop(i),
                      pressedOpacity: 0.55,
                      child: Container(
                        decoration: BoxDecoration(
                          border: i == labels.length - 1
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                      color: PvColors.hair(context),
                                      width: 0.6),
                                ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 15),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: i == labels.length - 1
                                      ? PvColors.red
                                      : PvColors.ink(context),
                                ),
                              ),
                            ),
                            Icon(
                              icons[i],
                              size: 19,
                              color: i == labels.length - 1
                                  ? PvColors.red
                                  : PvColors.ink2(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xF21F1F22) : const Color(0xF7FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: KzPressable(
                onTap: () => Navigator.of(context).pop(),
                pressedOpacity: 0.55,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: PvColors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
