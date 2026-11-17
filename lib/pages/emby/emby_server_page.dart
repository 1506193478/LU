import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/settings/settings_detail_scaffold.dart';
import 'package:XL/bean/widget/clay.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_backup_lines.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/utils/motion.dart';
import 'package:XL/pages/emby/emby_sheet_fields.dart';
import 'package:XL/pages/emby/emby_widgets.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/lu_media_vault.dart';
import 'package:XL/services/logging/logger.dart';

/// 服务器列表：切换、编辑、删除。
class EmbyServerPage extends StatelessWidget {
  const EmbyServerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = EmbyService.instance;
    return SettingsDetailScaffold(
      title: const Text('Emby 服务器'),
      actions: [
        IconButton(
          tooltip: '添加服务器',
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      body: ValueListenableBuilder<int>(
        valueListenable: service.revision,
        builder: (context, _, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final service = EmbyService.instance;
    final servers = service.servers;
    final active = service.activeServer;
    if (servers.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EmbyIntro(
                  icon: Icons.dns_rounded,
                  title: '还没有服务器',
                  description: '添加一个 Emby 或 Jellyfin 服务器，就能浏览上面的媒体库。',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _edit(context, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加服务器'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        for (final server in servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ServerTile(
              server: server,
              isActive: active?.id == server.id,
              onTap: () => _edit(context, server),
              onActivate: () async {
                await service.setActive(server.id);
                if (context.mounted) Navigator.of(context).maybePop();
              },
              onDelete: () => _delete(context, server),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加服务器'),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, EmbyServer? server) async {
    await context.pushNamed('/emby/servers/edit', arguments: server);
  }

  Future<void> _delete(BuildContext context, EmbyServer server) async {
    final confirmed = await ClayDialog.confirm(
      context,
      title: '删除这台服务器？',
      message: '只会删掉 LU 里保存的地址和登录凭据，不影响 Emby 服务端本身。',
      icon: Icons.delete_outline_rounded,
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    await EmbyService.instance.remove(server.id);
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isActive,
    required this.onTap,
    required this.onActivate,
    required this.onDelete,
  });

  final EmbyServer server;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.dns_outlined,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${server.userName} · ${server.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'activate') onActivate();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              if (!isActive)
                const PopupMenuItem(value: 'activate', child: Text('设为当前服务器')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );

    if (isNeuLayout(context)) {
      return NeuSurface(radius: 22, onTap: onTap, child: content);
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// 新增 / 编辑 Emby 服务器（整页表单，全局唯一入口）。
///
/// 以前有两条互不相通的路径：
///   * 这一页（`/emby/servers/edit`）：只有地址 / 账号 / 密码，**没有备用线路**，
///     而且保存时用的是 `authenticate` 的简化版；
///   * 资源库那张底部弹窗（`showEmbyServerSheet`）：字段全、备用线路能填、
///     登录失败不入库——但它只在资源库出现，跟服务器列表不是一套。
///
/// 结果就是「从第一种方式导入不能用、备用线路也不生效」。现在把弹窗那套
/// **运行逻辑**整体搬到这一页：主机 / 路径 / 端口 / https 拆开填、备用线路
/// 走同一个 `showBackupLinesSheet`、保存前带备用线路去登录、登不上就不入库；
/// 弹窗对 Emby 关闭，只剩 WebDAV / SMB / FTP 还在用它。
class EmbyServerEditPage extends StatefulWidget {
  const EmbyServerEditPage({super.key, this.server});

  /// null 表示新增。
  final EmbyServer? server;

  @override
  State<EmbyServerEditPage> createState() => _EmbyServerEditPageState();
}

class _EmbyServerEditPageState extends State<EmbyServerEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _host;
  late final TextEditingController _path;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;

  bool _https = false;
  bool _advanced = false;
  bool _strm = false;

  /// 未播放提醒的天数：0 = 关闭（参考稿里的「未播放提醒」）。
  int _reminderDays = 0;
  bool _passwordVisible = false;
  bool _busy = false;
  bool _failed = false;
  String _message = '';

  /// 备用线路。跟底部弹窗共用同一个编辑面板，保存时一起落盘。
  List<LuBackupLine> _lines = const <LuBackupLine>[];

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _name = TextEditingController(text: server?.name ?? '');
    _username = TextEditingController(text: server?.userName ?? '');
    _password = TextEditingController();
    _host = TextEditingController();
    _path = TextEditingController();
    _port = TextEditingController();
    _note = TextEditingController();

    if (server != null) {
      _reminderDays = server.reminderDays;
      // 地址是拼好的基址，拆回「主机 / 端口 / 路径 / https」四个字段，
      // 否则用户看到一个整串地址、又没法单独改端口。
      final Uri? uri = Uri.tryParse(server.url);
      if (uri != null) {
        _https = uri.scheme == 'https';
        _host.text = uri.host;
        if (uri.hasPort) _port.text = '${uri.port}';
        _path.text = uri.path.replaceFirst(RegExp(r'^/+'), '');
      } else {
        _host.text = server.url;
      }
      // 备注和备用线路只存在 LuVaultServer 里，按同一个 id 取回来。
      for (final v in LuMediaVault.instance.servers) {
        if (v.id != server.id) continue;
        _note.text = v.note;
        _lines = List<LuBackupLine>.of(v.backupLines);
        _password.text = v.password;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _host.dispose();
    _path.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 「未播放提醒」天数选择。
  ///
  /// 参考稿是一个列表弹窗（关闭 / 3 天 / 7 天 / 14 天 / 30 天）。这里用系统
  /// 底部操作表，选完立刻回显，不打断表单填写。
  Future<void> _pickReminderDays() async {
    const List<int> options = <int>[0, 3, 7, 14, 30];
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final bool darkMode = PvColors.isDark(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              decoration: BoxDecoration(
                color: darkMode
                    ? const Color(0xF21F1F22)
                    : const Color(0xF7FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Text(
                      '未播放提醒',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PvColors.ink2(ctx),
                      ),
                    ),
                  ),
                  for (final int d in options)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                d == 0 ? '关闭' : '收藏后 $d 天未看提醒',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: PvColors.ink(ctx),
                                ),
                              ),
                            ),
                            if (d == _reminderDays)
                              Icon(Icons.check_rounded,
                                  size: 19, color: PvColors.blue),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    KazumiHaptics.select();
    setState(() => _reminderDays = picked);
  }

  Future<void> _openLines() async {
    await showBackupLinesSheet(
      context,
      lines: _lines,
      onChanged: (lines) {
        if (!mounted) return;
        setState(() => _lines = lines);
      },
    );
  }

  String get _baseUrl => buildBaseUrl(
    host: _host.text.trim(),
    path: _path.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    https: _https,
  );

  /// 从剪贴板识别服务器信息（参考稿右上角剪贴板按钮）。
  ///
  /// 支持：一行一项（地址/用户名/密码），或者写在一段话里。
  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    var host = '';
    var port = '';
    var path = '';
    var https = false;
    var user = '';
    var pass = '';

    // 1) 地址：优先带协议的 URL，其次裸 IP/域名。
    final urlMatch =
        RegExp('https?://[^\\s\"' + "'" + '<>，,、；;]+').firstMatch(text);
    if (urlMatch != null) {
      final uri = Uri.tryParse(urlMatch.group(0)!);
      if (uri != null && uri.host.isNotEmpty) {
        host = uri.host;
        https = uri.scheme == 'https';
        if (uri.hasPort) port = '${uri.port}';
        final seg = uri.pathSegments.where((e) => e.isNotEmpty).join('/');
        if (seg.isNotEmpty && !seg.contains('.')) path = '/$seg';
      }
    } else {
      final bare = RegExp(
        r'\b((?:\d{1,3}\.){3}\d{1,3}|[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(?::(\d{2,5}))?',
      ).firstMatch(text);
      if (bare != null) {
        host = bare.group(1)!;
        port = bare.group(2) ?? '';
      }
    }

    // 2) 用户名 / 密码：带标签的优先。
    String grab(String pattern) {
      final m = RegExp(pattern, caseSensitive: false).firstMatch(text);
      return m?.group(1)?.trim() ?? '';
    }

    user = grab(r'(?:用户名|账号|账户|user(?:name)?)\s*[:：=]\s*(\S+)');
    pass = grab(r'(?:密码|口令|pass(?:word)?)\s*[:：=]\s*(\S+)');

    // 3) 没有标签：取「非地址行」里剩下的两项，短的当用户名。
    if (user.isEmpty && pass.isEmpty) {
      final tokens = <String>[];
      for (final line in text.split(RegExp(r'[\r\n]+'))) {
        final t = line.trim();
        if (t.isEmpty) continue;
        if (t.contains('://') || RegExp(r'^[\d.]+$').hasMatch(t)) continue;
        tokens.add(t);
      }
      if (tokens.length >= 2) {
        final a = tokens[tokens.length - 2];
        final b = tokens[tokens.length - 1];
        if (a.length <= b.length) {
          user = a;
          pass = b;
        } else {
          user = b;
          pass = a;
        }
      }
    }

    if (host.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('没有识别到服务器信息'),
          content: const Text(
            '复制包含服务器地址、用户名和密码的文字后再试，每项一行或写在一段话里都可以。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _host.text = host;
      if (port.isNotEmpty) _port.text = port;
      if (path.isNotEmpty) _path.text = path;
      _https = https;
      if (user.isNotEmpty) _username.text = user;
      if (pass.isNotEmpty) _password.text = pass;
    });
    KazumiDialog.showToast(
      message: pass.isEmpty ? '已识别服务器地址' : '已识别地址、用户名和密码',
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() {
        _failed = true;
        _message = '请先填主机地址，例如 192.168.1.10';
      });
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在连接…';
    });

    final existing = widget.server;
    final String id = existing?.id ?? EmbyService.newServerId();
    final String baseUrl = _baseUrl;
    final List<String> backupUrls = [
      for (final line in _lines)
        if (line.baseUrl.isNotEmpty) line.baseUrl,
    ];

    try {
      // 地址没变、密码也没填 → 只是想改备注：沿用旧 Token，不再登一次。
      final bool reuseToken =
          existing != null && existing.url == baseUrl && _password.text.isEmpty;
      if (reuseToken) {
        await _persist(
          existing.copyWith(
            name: _name.text.trim().isEmpty ? existing.name : _name.text.trim(),
            allowBadCertificate: true,
            backupUrls: backupUrls,
          ),
          id: id,
          baseUrl: baseUrl,
        );
        return;
      }

      final client = EmbyClient(
        serverUrl: baseUrl,
        // 主线路登不上会自动换备用线路，用户不用先把主线路改对才能存。
        backupUrls: backupUrls,
        allowBadCertificate: true,
        deviceId: EmbyService.instance.deviceId,
      );
      final EmbyAuthResult auth;
      try {
        auth = await client.authenticate(
          username: _username.text.trim(),
          password: _password.text,
        );
      } finally {
        client.close();
      }

      await _persist(
        EmbyServer(
          id: id,
          name: _name.text.trim().isEmpty ? auth.serverName : _name.text.trim(),
          url: baseUrl,
          userId: auth.userId,
          userName: auth.userName,
          accessToken: auth.accessToken,
          allowBadCertificate: true,
          backupUrls: backupUrls,
          reminderDays: _reminderDays,
        ),
        id: id,
        baseUrl: baseUrl,
      );
    } catch (e) {
      KazumiLogger().w('Emby: server setup failed', error: e);
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
          _message = embyErrorMessage(e);
        });
      }
    }
  }

  /// 两边一起写：EmbyService 管播放与接口，LuMediaVault 管资源库卡片和
  /// 密码 / 备用线路的名字。少写一边就会出现「列表里有、资源库没有」。
  Future<void> _persist(
    EmbyServer server, {
    required String id,
    required String baseUrl,
  }) async {
    await EmbyService.instance.upsert(server);
    await EmbyService.instance.setActive(server.id);
    await LuMediaVault.instance.saveServer(
      LuVaultServer(
        id: id,
        type: 'emby',
        name: server.name,
        note: _note.text.trim(),
        host: _host.text.trim(),
        path: _path.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        https: _https,
        user: _username.text.trim(),
        password: _password.text,
        addedAt: widget.server == null
            ? DateTime.now().millisecondsSinceEpoch
            : (LuMediaVault.instance.servers
                      .where((v) => v.id == id)
                      .map((v) => v.addedAt)
                      .firstOrNull ??
                  DateTime.now().millisecondsSinceEpoch),
        backupLines: _lines,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = false;
      _message = '连接成功 · $baseUrl';
    });
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final bool isNew = widget.server == null;
    return PopScope(
      canPop: !_busy,
      child: SettingsDetailScaffold(
        title: Text(isNew ? '添加服务器' : '编辑服务器'),
        actions: [
          IconButton(
            tooltip: '从剪贴板识别',
            onPressed: _busy ? null : _importFromClipboard,
            icon: const Icon(Icons.content_paste_rounded),
          ),
        ],
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SheetGroup(
              dark: dark,
              children: [
                SheetFieldRow(
                  dark: dark,
                  label: '名称',
                  hint: 'Name (可选)',
                  controller: _name,
                ),
                SheetFieldRow(
                  dark: dark,
                  label: '备注',
                  hint: 'Note (可选)',
                  controller: _note,
                ),
              ],
            ),
            SheetGroupLabel(dark: dark, text: '服务器地址'),
            SheetGroup(
              dark: dark,
              children: [
                SheetFieldRow(
                  dark: dark,
                  label: '主机',
                  hint: 'Host (必填)',
                  controller: _host,
                  keyboard: TextInputType.url,
                ),
                SheetFieldRow(
                  dark: dark,
                  label: '路径',
                  hint: 'Path (可选)',
                  controller: _path,
                ),
                SheetFieldRow(
                  dark: dark,
                  label: '端口',
                  hint: 'Port (可选)',
                  controller: _port,
                  keyboard: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SheetSwitchRow(
                  dark: dark,
                  label: 'https',
                  value: _https,
                  onChanged: _busy ? (_) {} : (v) => setState(() => _https = v),
                ),
              ],
            ),
            SheetGroupLabel(dark: dark, text: '登录信息'),
            SheetGroup(
              dark: dark,
              children: [
                SheetFieldRow(
                  dark: dark,
                  label: '用户',
                  hint: 'Username (可选)',
                  controller: _username,
                ),
                SheetFieldRow(
                  dark: dark,
                  label: '密码',
                  hint: isNew ? 'Password' : '留空沿用已保存凭据',
                  controller: _password,
                  obscure: !_passwordVisible,
                  suffix: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        _passwordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 17,
                        color: const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SheetGroup(
              dark: dark,
              children: [
                SheetArrowRow(
                  dark: dark,
                  label: '备用线路',
                  value: _lines.isEmpty ? '未设置' : '${_lines.length} 条',
                  onTap: _busy ? () {} : _openLines,
                ),
                SheetArrowRow(
                  dark: dark,
                  label: '未播放提醒',
                  value: _reminderDays <= 0 ? '未开启' : '$_reminderDays 天',
                  onTap: _busy ? () {} : _pickReminderDays,
                ),
                SheetArrowRow(
                  dark: dark,
                  label: '高级设置',
                  expanded: _advanced,
                  onTap: () => setState(() => _advanced = !_advanced),
                ),
                if (_advanced)
                  SheetNestedSwitchRow(
                    dark: dark,
                    title: 'STRM 优先使用原始路径播放',
                    subtitle: '如果你不清楚作用，请不要开启!',
                    value: _strm,
                    onChanged: (v) => setState(() => _strm = v),
                  ),
              ],
            ),
            SheetHint(dark: dark, text: '主线路登录失败时会依次尝试备用线路，保存成功后自动切到这台服务器。'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.login_rounded),
              label: Text(_busy ? '正在连接…' : '保存并登录'),
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _failed
                      ? const Color(0xFFC0392B)
                      : const Color(0xFF2E7D32),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
