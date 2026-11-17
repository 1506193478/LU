/// HG 设置页（HGhubX `src/pages/Settings.tsx` v2.0.0 全量照搬）。
///
/// 分区：外观 / 播放 / 本地数据 / 网络（代理访问 · 播放源 · 自动选线 ·
/// 严格安全模式 · 网络诊断）/ 播放诊断（日志开关 · 复制日志）/ 其他
/// （检查更新 · 关于）。设置只作用于 HG 模块内部（Hive box 'hg' 的
/// HgPrefs），不影响 LU 主体偏好。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:XL/modules/hg/hg_diag.dart';
import 'package:XL/modules/hg/hg_lines.dart';
import 'package:XL/modules/hg/hg_net.dart';
import 'package:XL/modules/hg/hg_proxy.dart';
import 'package:XL/modules/hg/hg_session.dart';
import 'package:XL/request/config/api_endpoints.dart';

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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            subtitle: '默认开启，每次启动均静音；关闭后记住上次静音状态。下次启动生效。',
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
            subtitle: const Text('封面 / 播放缓存与本地记录'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _clearCache,
          ),

          _sectionLabel(theme, '网络'),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('代理访问'),
            subtitle: Text(_proxySummary()),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openProxySheet,
          ),
          ListTile(
            leading: const Icon(Icons.bolt_rounded),
            title: const Text('播放源'),
            subtitle:
                Text(Uri.tryParse(HgNet.base)?.host ?? HgNet.base),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openLinePicker(),
          ),
          _toggleTile(
            icon: Icons.refresh_rounded,
            title: '自动选择线路',
            subtitle: '主站不可用时检测已发布镜像；关闭后保留手动选择',
            value: prefs.autoLine,
            onChanged: (v) => HgAutoLine.setEnabled(v),
          ),
          _toggleTile(
            icon: Icons.lock_rounded,
            title: '严格安全模式',
            subtitle:
                '默认开启，防上游投毒与内网探测；若导致正文或特殊代理异常可关闭',
            value: prefs.strictSecurity,
            onChanged: (v) async {
              await HgStore.prefs.setStrictSecurity(v);
              _toast(v ? '已开启严格安全模式' : '已切换为兼容模式（关闭激进清洗与守卫）');
            },
          ),
          ListTile(
            leading: const Icon(Icons.network_check_rounded),
            title: const Text('网络诊断'),
            subtitle: const Text('DNS / TCP / 系统代理 / 官网连通性，一键复制带结论的报告'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _runNetDiag,
          ),

          _sectionLabel(theme, '播放诊断'),
          _toggleTile(
            icon: Icons.info_outline_rounded,
            title: '播放诊断日志',
            subtitle: '版本、平台、当前线路和播放失败原因始终记录；开关只额外记录拖动与缓冲细节',
            value: prefs.playbackLog,
            onChanged: (v) async {
              await HgStore.prefs.setPlaybackLog(v);
              await HgDiag.trace('app.snapshot', {
                'verbose': v,
                'line': HgNet.base,
              });
              _toast(v ? '已开启播放诊断，请复现问题' : '已关闭播放诊断，已有日志保留');
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('复制播放诊断日志'),
            subtitle: Text(
              '含版本、平台、当前线路、播放失败原因，粘贴即完整',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _copyPlaybackLog,
          ),

          _sectionLabel(theme, '其他'),
          ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('检查更新'),
            subtitle: const Text('当前版本 · 对比 GitHub Release'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _checkUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于 HG 短剧'),
            subtitle: const Text('源自 HGhubX · 仅限非商业使用'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showAbout(),
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

  /* ── 代理访问（ProxySettings.tsx） ── */

  String _proxySummary() {
    final mode = HgStore.prefs.proxyMode;
    switch (mode) {
      case 'off':
        return '直连 · 忽略系统代理和环境变量';
      case 'custom':
        final url = HgStore.prefs.proxyUrl;
        return url.isEmpty ? '自定义代理' : '自定义代理 · ${_redactProxy(url)}';
      default:
        return '跟随系统 · ${_hasEnvProxy() ? '已检测到代理' : '未检测到代理'}';
    }
  }

  static bool _hasEnvProxy() {
    final env = Platform.environment;
    return (env['HTTP_PROXY'] ?? env['https_proxy'] ?? env['HTTPS_PROXY'] ??
            env['http_proxy'] ?? env['ALL_PROXY'] ?? env['all_proxy'] ?? '')
        .isNotEmpty;
  }

  /// 凭据脱敏（proxy.rs 的 redact_proxy）：只保留 scheme://host:port。
  static String _redactProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  Future<void> _openProxySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _HgProxySheet(),
    );
    if (mounted) setState(() {});
  }

  /* ── 网络诊断 ── */

  Future<void> _runNetDiag() async {
    _toast('正在诊断…');
    try {
      final result = await HgNetDiag.run();
      await Clipboard.setData(ClipboardData(text: result.report));
      _toast('诊断已复制 · ${result.shortVerdict}');
    } catch (e) {
      _toast('网络诊断失败：$e');
    }
  }

  /* ── 播放诊断日志 ── */

  Future<void> _copyPlaybackLog() async {
    try {
      final text = await HgDiag.read();
      if (text.trim().isEmpty) {
        _toast('尚无诊断日志，请开启后复现问题');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      _toast('播放诊断日志已复制');
    } catch (e) {
      _toast('复制日志失败：$e');
    }
  }

  /* ── 清理缓存（上游语义：只清封面/播放缓存，记录保留） ── */

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text(
            '只清除封面与播放列表缓存（解密图 / m3u8）。收藏、观看记录、搜索历史与登录状态都会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定清理')),
        ],
      ),
    );
    if (confirmed != true) return;
    HgProxy.clearCaches();
    _toast('缓存已清理');
  }

  /* ── 检查更新 ── */

  Future<void> _checkUpdate() async {
    _toast('正在检查更新…');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .getUrl(Uri.parse('https://api.github.com/repos/1506193478/LU/releases/latest'))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);
      if (response.statusCode != 200) {
        _toast('检查更新失败：HTTP ${response.statusCode}');
        return;
      }
      final data = jsonDecode(body) as Map;
      final tag = (data['tag_name'] ?? '').toString();
      final htmlUrl = (data['html_url'] ?? '').toString();
      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
      final current = ApiEndpoints.version;
      if (_isNewer(latest, current)) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('发现新版本'),
            content: Text('v$current → v$latest\n\n$tag'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  launchUrl(
                    Uri.parse(htmlUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('前往下载'),
              ),
            ],
          ),
        );
      } else {
        _toast('已是最新版本 v$current');
      }
    } catch (e) {
      _toast('检查更新失败：$e');
    }
  }

  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li != ci) return li > ci;
    }
    return false;
  }

  /* ── 关于 ── */

  Future<void> _showAbout() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HG 短剧模块'),
        content: const Text(
            '基于 HGhubX（Rust + Tauri 2 跨平台客户端）的功能原生移植。\n\n'
            '本项目仅供学习与交流，所有内容均来自上游站点，客户端不存储、不分发任何视频内容。'
            '请于 24 小时内删除相关资源，并支持正版。\n\nPolyForm Noncommercial 1.0.0 · 仅限非商业使用'),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  const ClipboardData(text: 'https://github.com/zxsos/HGhubX'));
              Navigator.pop(ctx);
              _toast('仓库地址已复制');
            },
            child: const Text('复制仓库地址'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _showTextDialog(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SelectableText(text,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: const Text('复制报告'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /* ── 通用构件 ── */

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

  Future<void> _openLinePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const HgLinePicker(),
    );
    if (mounted) setState(() {});
  }
}

/* ──────────────── 代理访问弹层（ProxySettings.tsx） ──────────────── */

class _HgProxySheet extends StatefulWidget {
  const _HgProxySheet();

  @override
  State<_HgProxySheet> createState() => _HgProxySheetState();
}

class _HgProxySheetState extends State<_HgProxySheet> {
  late String _mode = HgStore.prefs.proxyMode;
  late TextEditingController _url =
      TextEditingController(text: HgStore.prefs.proxyUrl);
  bool _visible = false;
  bool _busy = false;
  String? _error;
  String? _probe; // 测试结果描述
  bool _probeOk = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(bool save) async {
    if (_busy) return;
    if (_mode == 'custom' && _url.text.trim().isEmpty) {
      setState(() => _error = '请填写代理地址');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _probe = null;
    });
    try {
      final mode = _mode;
      final url = _mode == 'custom' ? _url.text.trim() : '';
      if (!save) {
        final (ok, ms, status, error) = await HgNet.testProxy(mode, url);
        setState(() {
          _probeOk = ok;
          _probe = ok
              ? '可用 · ${ms}ms'
              : '连接失败 · $error${status != null && status > 0 ? '（HTTP $status）' : ''}';
        });
        return;
      }
      if (mode == 'custom') {
        final (normalized, isSocks) = HgNet.normalizeProxy(url);
        if (normalized == null) throw '请填写代理地址';
        if (isSocks) {
          throw 'LU 网络层暂不支持 SOCKS 代理；请使用 HTTP 代理，或直接使用 VPN/TUN 全局接管';
        }
        await HgStore.prefs.setProxy('custom', normalized);
      } else {
        await HgStore.prefs.setProxy(mode, url);
      }
      HgNet.rebuildClients();
      _toast('代理设置已保存 · ${_modeLabel(mode)}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _modeLabel(String mode) =>
      mode == 'off' ? '直连' : mode == 'custom' ? '自定义' : '跟随系统';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            0, 12, 0, MediaQuery.paddingOf(context).bottom + 12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('代理访问', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '只应用于 HG 短剧模块。测试当前草稿的连通性后，可保存为模块的网络设置。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('跟随系统')),
                  ButtonSegment(value: 'custom', label: Text('自定义')),
                  ButtonSegment(value: 'off', label: Text('直连')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _error = null;
                  _probe = null;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == 'custom') ...[
                TextField(
                  controller: _url,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: '代理地址',
                    hintText: 'http://127.0.0.1:7890',
                    suffixIcon: IconButton(
                      icon: Icon(_visible
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded),
                      onPressed: () => setState(() => _visible = !_visible),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _probe = null;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  '支持 HTTP、HTTPS。手机上的 127.0.0.1 指手机自身；使用电脑代理时填写电脑的局域网地址。'
                  'SOCKS 暂不支持，可使用 VPN/TUN 全局接管代替。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ] else
                Text(
                  _mode == 'system'
                      ? '沿用系统代理与环境变量；移动端通常由 VPN/TUN 接管。保存过的自定义地址仍会保留。'
                      : '直接连接当前线路，忽略系统代理与环境变量；保存过的自定义地址仍会保留。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 12)),
              ],
              if (_probe != null) ...[
                const SizedBox(height: 6),
                Text(_probe!,
                    style: TextStyle(
                        fontSize: 12,
                        color: _probeOk
                            ? Colors.green.shade600
                            : theme.colorScheme.error)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _run(false),
                      child: Text(_busy && _probe == null ? '检测中…' : '测试连接'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _run(true),
                      child: const Text('保存代理'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ──────────────── 线路选择器（LinePicker.tsx v2.0.0 照搬） ──────────────── */

class HgLinePicker extends StatefulWidget {
  const HgLinePicker({super.key});

  @override
  State<HgLinePicker> createState() => HgLinePickerState();
}

class HgLinePickerState extends State<HgLinePicker> {
  final TextEditingController _custom = TextEditingController();
  List<HgMirrorItem>? _mirrors; // 地址发布页全部镜像（镜像线路组）
  String? _mirrorError;
  String? _customError;
  final Map<String, HgProbeHit> _probes = {};
  String? _probing; // 正在探测的组键
  String? _switching;
  bool _applying = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadMirrors() async {
    setState(() {
      _mirrorError = null;
    });
    try {
      final listing = await mirrors();
      if (mounted) setState(() => _mirrors = listing.items);
    } catch (e) {
      if (mounted) setState(() => _mirrorError = e.toString());
    }
  }

  Future<void> _probeList(String key, List<String> urls) async {
    if (_probing != null || urls.isEmpty) return;
    setState(() => _probing = key);
    try {
      final hits = await probe(urls);
      if (mounted) {
        setState(() {
          for (final hit in hits) {
            _probes[hit.url] = hit;
          }
        });
      }
    } catch (e) {
      _toast('检测失败：$e');
    } finally {
      if (mounted) setState(() => _probing = null);
    }
  }

  /// 手动切换（applyLine 语义）：关自动选线 → 切换；失败回滚自动选线。
  Future<void> _apply(String key, Future<void> Function() apply) async {
    if (_applying) return;
    _applying = true;
    setState(() => _switching = key);
    try {
      await apply();
      _toast('线路已切换，已使用手动选线，跨站点需重新登录');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast(e.toString());
    } finally {
      _applying = false;
      if (mounted) setState(() => _switching = null);
    }
  }

  void _pick(String url) {
    if (HgNet.base == url) return;
    _apply(url, () async {
      await setManualLine(url);
      if (mounted) setState(() => _custom.clear());
    });
  }

  void _saveCustom() {
    final raw = _custom.text.trim();
    _apply('custom', () async {
      await setCustomLine(raw);
    }).catchError((Object e) {
      setState(() => _customError = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBase = HgNet.base;
    final recommended = <HgMirrorItem>[];
    // 推荐镜像：当前线路置顶 + 发布页条目。
    recommended.add(HgMirrorItem(
      url: currentBase,
      host: Uri.tryParse(currentBase)?.host ?? currentBase,
    ));
    for (final m in _mirrors ?? const <HgMirrorItem>[]) {
      if (m.url != currentBase) recommended.add(m);
    }
    final busyAll = _probing != null || _switching != null || _applying;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        child: SizedBox(
          height: MediaQuery.heightOf(context) * 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('线路', style: theme.textTheme.titleMedium),
                          Text(
                            '当前：${Uri.tryParse(currentBase)?.host ?? currentBase}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: busyAll ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    _groupHead(theme, '自定义镜像', '保存后使用手动选线'),
                    _customSection(theme, busyAll),
                    _groupHead(theme, '固定线路', '需代理 / 非大陆网络',
                        action: TextButton(
                          onPressed: busyAll
                              ? null
                              : () => _probeList(
                                  'fixed',
                                  kHgFixedLines.map((l) => l.$2).toList()),
                          child: Text(_probing == 'fixed' ? '检测中…' : '全部检测'),
                        )),
                    _surfaceWrap(
                      theme,
                      [
                        for (final (name, url) in kHgFixedLines)
                          _row(theme, name, url, currentBase, busyAll),
                      ],
                    ),
                    _groupHead(theme, '推荐镜像', '来自发布页 · 当前线路置顶',
                        action: TextButton(
                          onPressed: busyAll
                              ? null
                              : () => _probeList(
                                  'recommended',
                                  recommended.map((m) => m.url).toList()),
                          child: Text(_probing == 'recommended'
                              ? '检测中…'
                              : '全部检测（${recommended.length}）'),
                        )),
                    _surfaceWrap(
                      theme,
                      [
                        for (final m in recommended) _row(theme, m.host, m.url, currentBase, busyAll),
                      ],
                    ),
                    _groupHead(theme, '镜像线路', '一般可直连', action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _probing != null ? null : _loadMirrors,
                          child: Text(_mirrors == null && _mirrorError == null
                              ? '获取中…'
                              : '刷新'),
                        ),
                        if (_mirrors?.isNotEmpty == true)
                          TextButton(
                            onPressed: busyAll
                                ? null
                                : () => _probeList(
                                    'mirrors',
                                    _mirrors!.map((m) => m.url).toList()),
                            child: Text(_probing == 'mirrors'
                                ? '检测中…'
                                : '全部检测（${_mirrors!.length}）'),
                          ),
                      ],
                    )),
                    _surfaceWrap(
                      theme,
                      _mirrorListBody(theme),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '切换后立即生效，请求链路与数据模型不变。这里的「检测」只探这一次；'
                      '日常的自动选线在 设置 → 网络 → 自动选择线路。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _mirrorListBody(ThemeData theme) {
    if (_mirrors == null && _mirrorError == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ];
    }
    if (_mirrorError != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('镜像线路获取失败',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 4),
              Text(_mirrorError!,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ];
    }
    if (_mirrors!.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(14),
          child: Text('地址发布页里没有可用的镜像地址', style: TextStyle(fontSize: 12)),
        ),
      ];
    }
    return [
      for (final m in _mirrors!)
        _row(theme, m.host, m.url, HgNet.base,
            _probing != null || _switching != null || _applying),
    ];
  }

  Widget _groupHead(ThemeData theme, String title, String hint,
      {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 0, 6),
      child: Row(
        children: [
          Text(title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: theme.colorScheme.outline,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _surfaceWrap(ThemeData theme, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _customSection(ThemeData theme, bool busyAll) {
    return _surfaceWrap(
      theme,
      [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _custom,
                enabled: !busyAll,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '镜像地址',
                  hintText: 'https://mirror.example.com',
                ),
                onChanged: (_) => setState(() => _customError = null),
              ),
              const SizedBox(height: 6),
              Text(
                '填写你信任的 HTTPS 站点。登录请求会发送到该站点；切换到其他站点后需重新登录。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_customError != null) ...[
                const SizedBox(height: 4),
                Text(_customError!,
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busyAll
                          ? null
                          : () => _apply('reset', () async {
                                await resetLine();
                                if (mounted) setState(() => _custom.clear());
                              }),
                      child: Text(_switching == 'reset' ? '恢复中…' : '恢复主站'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: busyAll ? null : _saveCustom,
                      child:
                          Text(_switching == 'custom' ? '保存中…' : '保存镜像'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 单条线路：左侧点按切换，右侧状态 + 检测按钮（LinePicker.tsx 的 Row）。
  Widget _row(ThemeData theme, String name, String url, String currentBase,
      bool busyAll) {
    final isCurrent = currentBase == url;
    final hit = _probes[url];
    return ListTile(
      dense: true,
      onTap: busyAll ? null : () => _pick(url),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w700 : null,
              ),
            ),
          ),
          if (isCurrent)
            Icon(Icons.check_rounded,
                size: 15, color: theme.colorScheme.primary),
        ],
      ),
      subtitle: Text(url.replaceFirst('https://', ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _switching == url
                ? '…'
                : hit == null
                    ? '—'
                    : hit.ok
                        ? '${hit.ms}ms'
                        : hit.reachable
                            ? '异常'
                            : '失败',
            style: TextStyle(
              fontSize: 12,
              color: hit == null
                  ? theme.colorScheme.outline
                  : hit.ok
                      ? Colors.green.shade600
                      : theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: busyAll
                ? null
                : () => _probeList(url, [url]),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('检测', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
