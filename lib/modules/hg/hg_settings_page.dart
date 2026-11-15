/// HG 设置页（HGhubX `src/pages/Settings.tsx` 全量照搬）。
///
/// 分区：外观 / 播放 / 本地数据 / 网络（自动选线 + 线路选择器 + 严格
/// 安全模式）/ 清理缓存 / 关于。设置只作用于 HG 模块内部（Hive box
/// 'hg' 的 HgPrefs），不影响 LU 主体偏好。
library;

import 'package:flutter/material.dart';

import 'package:XL/modules/hg/hg_lines.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_session.dart';

class HgSettingsPage extends StatefulWidget {
  const HgSettingsPage({super.key});

  @override
  State<HgSettingsPage> createState() => _HgSettingsPageState();
}

class _HgSettingsPageState extends State<HgSettingsPage> {
  @override
  void initState() {
    super.initState();
    HgStore.prefs.changed.addListener(_onPrefsChanged);
    HgAutoLine.lineEpoch.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    HgStore.prefs.changed.removeListener(_onPrefsChanged);
    HgAutoLine.lineEpoch.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = HgStore.prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionLabel(theme, '外观'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('跟随')),
                ButtonSegment(value: 'light', label: Text('浅色')),
                ButtonSegment(value: 'dark', label: Text('深色')),
              ],
              selected: {prefs.appearance},
              onSelectionChanged: (v) =>
                  HgStore.prefs.setAppearance(v.first),
            ),
          ),
          const SizedBox(height: 8),

          _sectionLabel(theme, '播放'),
          _toggleTile(
            icon: Icons.volume_off_rounded,
            title: '启动时静音',
            subtitle: '默认开启，每次启动均静音；关闭后记住上次状态。',
            value: prefs.muteOnStartup,
            onChanged: HgStore.prefs.setMuteOnStartup,
          ),
          _toggleTile(
            icon: Icons.hd_rounded,
            title: '优先高清',
            subtitle: '有高清就用 HEVC，播不了会自动切回标准',
            value: prefs.preferHevc,
            onChanged: HgStore.prefs.setPreferHevc,
          ),

          _sectionLabel(theme, '本地数据'),
          ListTile(
            leading: const Icon(Icons.favorite_rounded),
            title: const Text('本地片库'),
            subtitle: Text(
                '${prefs.favs.length} 部收藏 · ${prefs.history.length} 条观看记录'),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: const Text('清理缓存'),
            subtitle: const Text('封面 / 播放缓存与观看记录'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _clearCache,
          ),

          _sectionLabel(theme, '网络'),
          _toggleTile(
            icon: Icons.route_rounded,
            title: '自动选择线路',
            subtitle: '启动自动探测最快线路；主线路恢复时优先切回',
            value: prefs.autoLine,
            onChanged: (v) => HgAutoLine.setEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('选择线路'),
            subtitle: Text('当前：${Uri.tryParse(HgNet.base)?.host ?? HgNet.base}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLinePicker(),
          ),
          _toggleTile(
            icon: Icons.security_rounded,
            title: '严格安全模式',
            subtitle: '镜像线路仅供游客浏览；登录/注册请切换到固定线路',
            value: prefs.strictSecurity,
            onChanged: HgStore.prefs.setStrictSecurity,
          ),

          _sectionLabel(theme, '其他'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于 HG 短剧'),
            subtitle: const Text('源自 HGhubX · 仅限非商业使用'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'HG 短剧模块 · 设置仅作用于本模块',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('将清空封面、播放列表与分片缓存，以及本模块的观看记录。收藏与登录状态不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清理')),
        ],
      ),
    );
    if (confirmed != true) return;
    HgProxy.clearCaches();
    await HgStore.prefs.clearHistory();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('缓存已清理')));
    }
  }

  Future<void> _openLinePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const HgLinePicker(),
    );
    if (mounted) setState(() {});
  }
}

/* ──────────────── 线路选择器（LinePicker.tsx 照搬） ──────────────── */

class HgLinePicker extends StatefulWidget {
  const HgLinePicker({super.key});

  @override
  State<HgLinePicker> createState() => HgLinePickerState();
}

class HgLinePickerState extends State<HgLinePicker> {
  List<HgMirrorItem>? _mirrors;
  String? _mirrorError;
  final Map<String, HgProbeHit> _probes = {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _loadMirrors();
  }

  Future<void> _loadMirrors() async {
    setState(() {
      _mirrorError = null;
    });
    try {
      final listing = await mirrors();
      if (mounted) setState(() => _mirrors = listing.recommended);
    } catch (e) {
      if (mounted) setState(() => _mirrorError = e.toString());
    }
  }

  Future<void> _probeAll() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _probes.clear();
    });
    try {
      final urls = <String>[
        for (final (_, url) in kHgFixedLines) url,
        if (_mirrors != null) ...[for (final m in _mirrors!) m.url],
      ];
      final hits = await probe(urls);
      if (mounted) {
        setState(() {
          for (final hit in hits) {
            _probes[hit.url] = hit;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _switchTo(String url) async {
    final host = Uri.tryParse(url)?.host ?? url;
    final changedLine = HgNet.base != url;
    if (!changedLine) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换线路'),
        content: Text(
            '将切换到 $host。\n\n登录状态按线路保存，切换后需要重新登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('切换')),
        ],
      ),
    );
    if (confirmed != true) return;
    HgNet.setBase(url);
    await HgAutoLine.pickLine('manual', force: true);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已切换到线路 $host')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBase = HgNet.base;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        child: SizedBox(
          height: MediaQuery.heightOf(context) * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('选择线路', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _probing ? null : _probeAll,
                      icon: _probing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.speed_rounded, size: 18),
                      label: const Text('探测'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  '登录状态按线路保存，切换后需要重新登录。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final (name, url) in kHgFixedLines)
                      _lineTile(theme, name, url, fixed: true),
                    const Divider(height: 1),
                    if (_mirrors == null && _mirrorError == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (_mirrorError != null)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('镜像列表获取失败',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text(_mirrorError!,
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: _loadMirrors,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    if (_mirrors != null && _mirrors!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('地址发布页里没有可用的镜像地址'),
                      ),
                    for (final m in _mirrors ?? const <HgMirrorItem>[])
                      _lineTile(theme, m.host, m.url, fixed: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineTile(ThemeData theme, String name, String url,
      {required bool fixed}) {
    final isCurrent = HgNet.base == url;
    final hit = _probes[url];
    return ListTile(
      dense: !fixed,
      leading: Icon(
        isCurrent
            ? Icons.check_circle_rounded
            : fixed
                ? Icons.dns_rounded
                : Icons.public_rounded,
        color: isCurrent ? theme.colorScheme.primary : null,
        size: fixed ? 24 : 20,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w700 : null,
        ),
      ),
      subtitle: hit == null
          ? null
          : Text(
              hit.ok
                  ? '可用 · ${hit.ms}ms'
                  : hit.reachable
                      ? '连通但数据异常 · ${hit.ms}ms'
                      : '不可用 · ${hit.error ?? ''}',
              style: TextStyle(
                fontSize: 12,
                color: hit.ok
                    ? Colors.green.shade600
                    : theme.colorScheme.error,
              ),
            ),
      trailing: isCurrent
          ? Text('当前', style: theme.textTheme.labelSmall)
          : const Icon(Icons.chevron_right_rounded),
      onTap: () => _switchTo(url),
    );
  }
}
