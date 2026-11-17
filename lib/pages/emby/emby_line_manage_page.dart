/// 备用线路管理页（参考稿：线路列表 + 右上刷新测延迟 + 添加/剪贴板导入）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/services/emby/emby_line_probe.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/theme/ios_interaction.dart';

class EmbyLineManagePage extends StatefulWidget {
  const EmbyLineManagePage({super.key, required this.server});

  final EmbyServer server;

  @override
  State<EmbyLineManagePage> createState() => _EmbyLineManagePageState();
}

class _EmbyLineManagePageState extends State<EmbyLineManagePage> {
  late EmbyServer _server = widget.server;
  Map<String, int?> _latency = const {};
  bool _probing = false;

  List<String> get _lines => <String>[
        _server.url,
        ..._server.backupUrls,
      ].where((u) => u.trim().isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _probe();
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

  Future<void> _persist({String? mainUrl, List<String>? backups}) async {
    final next = _server.copyWith(
      url: mainUrl ?? _server.url,
      backupUrls: backups ?? _server.backupUrls,
    );
    await EmbyService.instance.upsert(next);
    if (!mounted) return;
    setState(() => _server = next);
  }

  /// 设为默认：把该线路提到主线路位置。
  Future<void> _setDefault(String url) async {
    if (_server.url == url) return;
    final rest = _lines.where((u) => u != url).toList();
    await _persist(mainUrl: url, backups: rest);
  }

  Future<void> _removeLine(String url) async {
    if (_server.url == url) {
      KazumiDialog.showToast(message: '主线路不能删除，先把别的线路设为默认');
      return;
    }
    await _persist(
      backups: _server.backupUrls.where((u) => u.trim() != url).toList(),
    );
  }

  Future<void> _addLine() async {
    final value = await showKzPrompt(
      context: context,
      title: '添加线路',
      hint: 'https://example.com:443',
      confirmLabel: '添加',
    );
    if (value == null) return;
    final url = _normalize(value);
    if (url == null) {
      KazumiDialog.showToast(message: '地址格式不对');
      return;
    }
    if (_lines.contains(url)) {
      KazumiDialog.showToast(message: '这条线路已经有了');
      return;
    }
    await _persist(backups: [..._server.backupUrls, url]);
    await _probe();
  }

  /// 从剪贴板导入：一行一个地址，或一段话里挑出所有 http(s) 链接。
  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      KazumiDialog.showToast(message: '剪贴板是空的');
      return;
    }
    final found = <String>[];
    for (final m in RegExp(r'''https?://[^\s"'<>\\]+''').allMatches(text)) {
      final url = _normalize(m.group(0)!);
      if (url != null && !_lines.contains(url) && !found.contains(url)) {
        found.add(url);
      }
    }
    if (found.isEmpty) {
      KazumiDialog.showToast(message: '没识别到新的线路地址');
      return;
    }
    await _persist(backups: [..._server.backupUrls, ...found]);
    KazumiDialog.showToast(message: '已导入 ${found.length} 条线路');
    await _probe();
  }

  static String? _normalize(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return null;
    if (!t.startsWith('http://') && !t.startsWith('https://')) {
      t = 'https://$t';
    }
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return null;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context) - 8, 6, embyPagePadding(context), 0),
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
                  Flexible(
                    child: Text(
                      '编辑 ${_server.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: PvColors.ink(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  KzPressable(
                    onTap: _probe,
                    pressedOpacity: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _probing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: PvColors.blue,
                              ),
                            )
                          : Icon(Icons.refresh_rounded,
                              size: 22, color: PvColors.blue),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  embyPagePadding(context), 2, embyPagePadding(context), 10),
              child: Text(
                '同一台服务器的其它入口地址。当前线路不可用时会自动切换到下一条。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: PvColors.ink3(context),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    embyPagePadding(context), 0, embyPagePadding(context), 20),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: PvColors.isDark(context)
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < lines.length; i++)
                          _LineTile(
                            url: lines[i],
                            isDefault: lines[i] == _server.url,
                            latency: _latency[lines[i]],
                            probing: _probing && !_latency.containsKey(lines[i]),
                            showDivider: i != lines.length - 1,
                            onSetDefault: () => _setDefault(lines[i]),
                            onDelete: () => _removeLine(lines[i]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PillButton(
                          icon: Icons.add_rounded,
                          label: '添加线路',
                          onTap: _addLine,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PillButton(
                          icon: Icons.content_paste_rounded,
                          label: '从剪贴板导入',
                          onTap: _importFromClipboard,
                        ),
                      ),
                    ],
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

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.url,
    required this.isDefault,
    required this.latency,
    required this.probing,
    required this.showDivider,
    required this.onSetDefault,
    required this.onDelete,
  });

  final String url;
  final bool isDefault;
  final int? latency;
  final bool probing;
  final bool showDivider;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: PvColors.hair(context), width: 0.6),
              )
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          KzPressable(
            onTap: onSetDefault,
            pressedOpacity: 0.6,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                isDefault
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isDefault ? PvColors.blue : PvColors.chev(context),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '主线路',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: PvColors.ink(context),
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: PvColors.blue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '默认',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: PvColors.blue,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (probing)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: PvColors.ink3(context),
                        ),
                      )
                    else if (latency != null || !isDefault)
                      Text(
                        latency == null ? '' : EmbyLineProbe.label(latency),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: latency == null
                              ? PvColors.ink3(context)
                              : PvColors.green,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: PvColors.ink3(context),
                  ),
                ),
              ],
            ),
          ),
          KzPressable(
            onTap: isDefault ? null : onDelete,
            pressedOpacity: 0.5,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: isDefault ? PvColors.chev(context) : PvColors.ink2(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KzPressable(
      onTap: onTap,
      pressedOpacity: 0.6,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: PvColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: PvColors.ink(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: PvColors.ink(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
