import 'dart:io';

import 'package:flutter/material.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/storage/storage.dart';

/// 「转码与串流」：决定 Emby 这一条片子是原盘直连还是服务器转码。
///
/// 这个页面原来只是一行 `toast('转码与串流暂未开放')`。设置项落在
/// [EmbyStreamPrefs]，实际生效在 `EmbyStreamResolver.resolve`——也就是每次
/// 起播、每次切集都会重新按这里的设置挑地址。
class EmbyStreamSettingsPage extends StatefulWidget {
  const EmbyStreamSettingsPage({super.key});

  @override
  State<EmbyStreamSettingsPage> createState() => _EmbyStreamSettingsPageState();
}

class _EmbyStreamSettingsPageState extends State<EmbyStreamSettingsPage> {
  EmbyStreamMode _mode = EmbyStreamMode.auto;
  int _bitrate = 0;
  EmbyServer? _server;
  String _kernel = 'auto';

  @override
  void initState() {
    super.initState();
    _mode = EmbyStreamPrefs.mode;
    _bitrate = EmbyStreamPrefs.bitrateMbps;
    _server = EmbyService.instance.activeServer;
    _kernel = GStorage.getSetting(SettingsKeys.embyIosKernel);
  }

  Future<void> _setKernel(String value) async {
    setState(() => _kernel = value);
    await GStorage.putSetting(SettingsKeys.embyIosKernel, value);
  }

  Future<void> _setMode(EmbyStreamMode mode) async {
    setState(() => _mode = mode);
    await EmbyStreamPrefs.setMode(mode);
  }

  Future<void> _setBitrate(int mbps) async {
    setState(() => _bitrate = mbps);
    await EmbyStreamPrefs.setBitrateMbps(mbps);
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: PvColors.page(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: PvColors.ink(context),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '转码与串流',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: PvColors.ink(context),
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 40),
        children: [
          const PvGroupLabel('串流方式'),
          PvGroup(
            children: [
              for (var i = 0; i < EmbyStreamMode.values.length; i++)
                _RadioRow(
                  title: EmbyStreamMode.values[i].label,
                  subtitle: EmbyStreamMode.values[i].description,
                  selected: _mode == EmbyStreamMode.values[i],
                  showDivider: i != EmbyStreamMode.values.length - 1,
                  onTap: () => _setMode(EmbyStreamMode.values[i]),
                ),
            ],
          ),
          const PvGroupLabel('转码画质上限'),
          PvGroup(
            children: [
              for (var i = 0; i < embyBitratePresets.length; i++)
                _RadioRow(
                  title: embyBitrateLabel(embyBitratePresets[i]),
                  subtitle: embyBitratePresets[i] == 0
                      ? '服务器按自己的策略挑，通常等于原片码率'
                      : _bitrateHint(embyBitratePresets[i]),
                  selected: _bitrate == embyBitratePresets[i],
                  enabled: _mode != EmbyStreamMode.direct,
                  showDivider: i != embyBitratePresets.length - 1,
                  onTap: () => _setBitrate(embyBitratePresets[i]),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 2, 32, 18),
            child: Text(
              _mode == EmbyStreamMode.direct
                  ? '直连模式下码率不生效——原盘是多少就是多少，服务器不参与转码。'
                  : '只在转码时生效。宽带不稳、或者片源码率远高于电视解码能力时调低一档会明显更顺。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: PvColors.ink3(context),
              ),
            ),
          ),
          if (Platform.isIOS) ...[
            const PvGroupLabel('iOS 播放内核'),
            PvGroup(
              children: [
                _RadioRow(
                  title: '自动（推荐）',
                  subtitle: '服务器转码（HLS）走 AVPlayer 原生硬解，直连和本地文件走 mpv',
                  selected: _kernel == 'auto',
                  onTap: () => _setKernel('auto'),
                ),
                _RadioRow(
                  title: 'AVPlayer 优先',
                  subtitle: '强制服务器转码后走 AVPlayer（它播不了 MKV 原盘，所以直连被跳过）',
                  selected: _kernel == 'av',
                  onTap: () => _setKernel('av'),
                ),
                _RadioRow(
                  title: 'libmpv',
                  subtitle: '全部走 mpv。AVPlayer 播不了的片源在这里手动回退',
                  selected: _kernel == 'mpv',
                  showDivider: false,
                  onTap: () => _setKernel('mpv'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 2, 32, 18),
              child: Text(
                'AVPlayer 的画质由系统硬解接管（HDR 自动生效）；它不支持'
                '「内嵌字幕直接渲染」，选字幕走外挂或字幕搜索即可。改动下一次'
                '起播生效。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: PvColors.ink3(context),
                ),
              ),
            ),
          ],
          const PvGroupLabel('当前服务器'),
          PvGroup(
            children: [
              PvRow(
                icon: Icons.dns_rounded,
                iconColor: const Color(0xFF34C759),
                title: server?.name ?? '还没有服务器',
                subtitle: server == null ? '先去「媒体库管理」连一台' : server.url,
                trailing: PvRowTrailing.none,
              ),
              PvRow(
                icon: Icons.swap_vert_rounded,
                iconColor: const Color(0xFF5E5CE6),
                title: '当前方式',
                value: _mode == EmbyStreamMode.direct
                    ? '原盘直连'
                    : '${_mode.label}${_bitrate > 0 && _mode != EmbyStreamMode.direct ? ' · ${embyBitrateLabel(_bitrate)}' : ''}',
                trailing: PvRowTrailing.none,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: Text(
              '改完不用重启，下一次起播（包括切集、续播）就按新设置走。\n'
              '直连最省服务器、画质无损，但要求手机/电视能解原片编码；'
              '转码什么都能播，代价是服务器 CPU 和一点画质。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: PvColors.ink3(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _bitrateHint(int mbps) {
    if (mbps >= 20) return '接近原盘，局域网够用';
    if (mbps >= 8) return '1080p 高码率，画质和带宽平衡';
    if (mbps >= 4) return '1080p 常规，弱网也能稳';
    return '手机流量、或者网络很差时用';
  }
}

/// 单选行：右边一个勾，选中时整行文字加重。
class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? PvColors.ink(context) : PvColors.ink3(context);
    final row = InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: -0.15,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: PvColors.ink3(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (selected)
                const Icon(Icons.check_rounded, size: 19, color: PvColors.blue),
            ],
          ),
        ),
      ),
    );
    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 15),
          color: PvColors.hair(context),
        ),
        row,
      ],
    );
  }
}
