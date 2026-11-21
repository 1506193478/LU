import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/danmaku/danmaku_source_convert_prefs.dart';
import 'package:XL/services/subtitle/han_convert.dart';
import 'package:XL/theme/ios_interaction.dart';

/// 弹幕「按来源简繁转换」设置行 + 实时预览。
///
/// 对齐 Animeko v6.4.0「按弹幕来源单独配置并预览转换效果」：
/// 每个来源一个下拉（不转换 / 转简体 / 转繁体），下方固定示例文本实时预览。
class DanmakuSourceConvertTile extends StatefulWidget {
  const DanmakuSourceConvertTile({super.key});

  @override
  State<DanmakuSourceConvertTile> createState() =>
      _DanmakuSourceConvertTileState();
}

class _DanmakuSourceConvertTileState extends State<DanmakuSourceConvertTile> {
  final DanmakuSourceConvertPrefs _prefs = DanmakuSourceConvertPrefs.instance;

  static const String _sample = '这是个测试弹幕，简体繁体都能看清楚';
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 用一行可点的开关行控制展开（复用 PvRow 的按压手感）。
        PvRow(
          icon: Icons.translate_rounded,
          iconColor: const Color(0xFF0A84FF),
          title: '按来源转换',
          subtitle: '为不同弹幕来源单独设置，展开查看并预览',
          trailing: PvRowTrailing.none,
          onTap: () => setState(() => _expanded = !_expanded),
          showDivider: !_expanded,
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          PvGroup(
            children: [
              for (final src in DanmakuSrc.values)
                _SourceDropdown(src: src, prefs: _prefs),
            ],
          ),
          const SizedBox(height: 8),
          _Preview(sample: _sample),
        ],
      ],
    );
  }
}

class _SourceDropdown extends StatefulWidget {
  const _SourceDropdown({required this.src, required this.prefs});

  final DanmakuSrc src;
  final DanmakuSourceConvertPrefs prefs;

  @override
  State<_SourceDropdown> createState() => _SourceDropdownState();
}

class _SourceDropdownState extends State<_SourceDropdown> {
  late HanConvertMode _mode = widget.prefs.modeOf(widget.src);
  bool _saving = false;

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<HanConvertMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: PvColors.card(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${widget.src.label} · 转换方式',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              for (final m in HanConvertMode.values)
                ListTile(
                  title: Text(m.label),
                  trailing: m == _mode
                      ? const Icon(Icons.check_rounded, color: PvColors.blue)
                      : null,
                  onTap: () => Navigator.of(context).pop(m),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _mode || !mounted) return;
    setState(() {
      _mode = picked;
      _saving = true;
    });
    await widget.prefs.setMode(widget.src, picked);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PvRow(
      icon: Icons.subtitles_outlined,
      iconColor: const Color(0xFF30B0C7),
      title: widget.src.label,
      value: _mode.label,
      onTap: _saving ? null : _pick,
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.sample});

  final String sample;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Text('预览', style: PvText.groupLabel(context)),
          ),
          PvGroup(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final src in DanmakuSrc.values) ...[
                      Row(
                        children: [
                          Text(src.label, style: PvText.rowSub(context)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        HanConvert.applyWithMode(
                          sample,
                          DanmakuSourceConvertPrefs.instance.modeOf(src),
                        ),
                        style: PvText.rowTitle(context),
                      ),
                      if (src != DanmakuSrc.values.last)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
