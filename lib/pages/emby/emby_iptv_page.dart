import 'package:flutter/material.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_lu_play.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/lu_iptv.dart';

/// IPTV 页（对应 SenPlayer 的 IPTV：M3U/M3U8/TXT + 在线订阅 + 频道分组）。
///
/// 频道列表按 #EXTGRP / group-title 分组，点频道走 [luPlay] 起播
/// （本地资源壳，不往 Emby 上报进度）。
class EmbyIptvPage extends StatefulWidget {
  const EmbyIptvPage({super.key});

  @override
  State<EmbyIptvPage> createState() => _EmbyIptvPageState();
}

class _EmbyIptvPageState extends State<EmbyIptvPage> {
  final LuIptv _iptv = LuIptv.instance;
  bool _loading = false;

  Future<void> _addSubscription() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 IPTV 订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/list.m3u',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '支持 M3U / M3U8 / TXT，可填本地文件路径（file://）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;

    setState(() => _loading = true);
    try {
      final count = await _iptv.addSubscription(url: url);
      if (mounted) {
        KazumiDialog.showToast(message: '已加载 $count 个频道');
        setState(() {});
      }
    } catch (e) {
      if (mounted) KazumiDialog.showToast(message: '订阅加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_iptv.subscriptions.isEmpty) return;
    setState(() => _loading = true);
    try {
      final count = await _iptv.refreshAll();
      if (mounted) {
        KazumiDialog.showToast(message: '已更新，共 $count 个频道');
        setState(() {});
      }
    } catch (e) {
      if (mounted) KazumiDialog.showToast(message: '更新失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _iptv.grouped;
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('IPTV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新订阅',
            onPressed: _loading ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加订阅',
            onPressed: _loading ? null : _addSubscription,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _iptv.channels.isEmpty
          ? _Empty(onAdd: _addSubscription)
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_iptv.subscriptions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '${_iptv.subscriptions.length} 个订阅 · ${_iptv.channels.length} 个频道',
                      style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
                    ),
                  ),
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      '${entry.key}（${entry.value.length}）',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PvColors.subInk(context),
                      ),
                    ),
                  ),
                  for (final channel in entry.value)
                    ListTile(
                      leading: const Icon(Icons.live_tv_rounded, size: 20),
                      title: Text(channel.name, style: TextStyle(color: PvColors.ink(context))),
                      subtitle: Text(
                        channel.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: PvColors.ink3(context)),
                      ),
                      onTap: () => luPlay(context, title: channel.name, url: channel.url),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_outlined, size: 56, color: PvColors.ink3(context)),
          const SizedBox(height: 12),
          Text('还没有 IPTV 订阅', style: TextStyle(color: PvColors.ink(context), fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            '添加一个 M3U / M3U8 列表开始观看',
            style: TextStyle(color: PvColors.ink3(context), fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加订阅'),
          ),
        ],
      ),
    );
  }
}
