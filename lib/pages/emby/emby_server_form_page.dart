import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/emby/emby_backup_lines.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_sheet_fields.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/lu_media_vault.dart';

/// 资源库「添加来源」用的服务器表单——**卡片式底部弹出**，不是整页跳转。
///
/// 按 #6~#11 五张设计稿做的：
///   Emby / Jellyfin：名称备注 → 服务器地址（主机/路径/端口/https）→ 登录信息
///   → 备用线路 / 高级设置（展开里面才是 STRM 开关）→（无 iCloud 行）
///   WebDAV：端口是 `Port (可选)`，底下多一张「自动生成预览图」卡 + 风控提示
///   SMB：只有主机 + 端口 445，卡下写「支持 SMB2 和 SMB3 协议」
///   FTP：主机 + 路径 + 端口 21
///
/// Emby / Jellyfin 点保存会真的去 `AuthenticateByName`，登不上就不入库。
Future<LuVaultServer?> showEmbyServerSheet(
  BuildContext context, {
  required String type,
  LuVaultServer? existing,
}) {
  return showModalBottomSheet<LuVaultServer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _ServerSheet(type: type, existing: existing),
    ),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.type, this.existing});

  final String type;
  final LuVaultServer? existing;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _host;
  late final TextEditingController _path;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _password;

  bool _https = false;
  bool _obscure = true;
  bool _strm = false;
  bool _advanced = false;
  bool _preview = true;
  bool _busy = false;
  String _message = '';
  bool _failed = false;

  /// 备用线路。在「备用线路」页里增删，保存服务器时一起落盘。
  List<LuBackupLine> _lines = const <LuBackupLine>[];

  static const Map<String, int> _defaultPort = {
    'emby': 8096,
    'jellyfin': 8096,
    'smb': 445,
    'ftp': 21,
  };

  String get _type => widget.type;

  /// 有「路径 / https / 备用线路 / 高级设置」的只有这几类。
  bool get _hasPath => _type != 'smb';
  bool get _hasHttps => _type == 'emby' || _type == 'jellyfin' || _type == 'webdav';
  bool get _hasAdvanced => _type == 'emby' || _type == 'jellyfin';
  bool get _hasPreview => _type == 'webdav';
  bool get _isEmbyLike => _type == 'emby' || _type == 'jellyfin';

  String get _title => LuVaultServer(id: '', type: _type).typeLabel;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _path = TextEditingController(text: e?.path ?? '');
    _port = TextEditingController(
      text: (e?.port ?? 0) > 0
          ? '${e!.port}'
          : ((_defaultPort[_type] ?? 0) > 0 ? '${_defaultPort[_type]}' : ''),
    );
    _user = TextEditingController(text: e?.user ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _https = e?.https ?? false;
    _lines = List<LuBackupLine>.of(e?.backupLines ?? const <LuBackupLine>[]);
  }

  /// 打开「备用线路」页。那边的增删会实时回写 [_lines]，下滑关掉也不会丢。
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

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _host.dispose();
    _path.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() {
        _failed = true;
        _message = '请先填主机地址';
      });
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
      _message = '';
    });

    final server = LuVaultServer(
      id: widget.existing?.id ??
          'vault-${DateTime.now().millisecondsSinceEpoch}',
      type: _type,
      name: _name.text.trim(),
      note: _note.text.trim(),
      host: host,
      path: _path.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 0,
      https: _https,
      user: _user.text.trim(),
      password: _password.text,
      addedAt: widget.existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
      backupLines: _lines,
    );

    if (_isEmbyLike) {
      try {
        // 备用线路也交给客户端：主线路连不上时登录会自动换到下一条，
        // 用户不用先把主线路改对才能存。
        final client = EmbyClient(
          serverUrl: server.baseUrl,
          backupUrls: server.backupUrls,
          allowBadCertificate: true,
          deviceId: EmbyService.instance.deviceId,
        );
        EmbyAuthResult auth;
        try {
          auth = await client.authenticate(
            username: server.user,
            password: server.password,
          );
        } finally {
          client.close();
        }
        await EmbyService.instance.upsert(
          EmbyServer(
            id: server.id,
            name: server.name.isEmpty ? auth.serverName : server.name,
            url: server.baseUrl,
            userId: auth.userId,
            userName: auth.userName,
            accessToken: auth.accessToken,
            allowBadCertificate: true,
            backupUrls: server.backupUrls,
          ),
        );
        await EmbyService.instance.setActive(server.id);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _failed = true;
          _message = '连接失败：${e.toString().split('\n').first}';
        });
        return;
      }
    }

    await LuMediaVault.instance.saveServer(server);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = false;
      _message = _isEmbyLike ? '连接成功' : '已保存';
    });
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (mounted) Navigator.of(context).maybePop(server);
  }

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);

    return Material(
      color: PvColors.page(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SheetTopBar(
            title: _title,
            busy: _busy,
            onClose: () => Navigator.of(context).maybePop(),
            onSave: _busy ? null : _save,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 34),
              children: [
                SheetGroup(dark: dark, children: [
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
                ]),
                SheetGroupLabel(dark: dark, text: '服务器地址'),
                SheetGroup(dark: dark, children: [
                  SheetFieldRow(
                    dark: dark,
                    label: '主机',
                    hint: 'Host (必填)',
                    controller: _host,
                  ),
                  if (_hasPath)
                    SheetFieldRow(
                      dark: dark,
                      label: '路径',
                      hint: 'Path (可选)',
                      controller: _path,
                    ),
                  SheetFieldRow(
                    dark: dark,
                    label: '端口',
                    hint: _hasHttps || _type == 'ftp' ? 'Port (可选)' : 'Port',
                    controller: _port,
                    keyboard: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  if (_hasHttps)
                    SheetSwitchRow(
                      dark: dark,
                      label: 'https',
                      value: _https,
                      onChanged: (v) => setState(() => _https = v),
                    ),
                ]),
                if (_type == 'smb')
                  SheetHint(dark: dark, text: '支持 SMB2 和 SMB3 协议'),
                SheetGroupLabel(dark: dark, text: '登录信息'),
                SheetGroup(dark: dark, children: [
                  SheetFieldRow(
                    dark: dark,
                    label: '用户',
                    hint: 'Username (可选)',
                    controller: _user,
                  ),
                  SheetFieldRow(
                    dark: dark,
                    label: '密码',
                    hint: 'Password (可选)',
                    controller: _password,
                    obscure: _obscure,
                    // 注意别用 IconButton：它自带 48×48 的最小点击区，
                    // 塞进 34 高的胶囊里会直接溢出。这里用裸图标 + 手势。
                    suffix: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 17,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                    ),
                  ),
                ]),
                if (_hasAdvanced)
                  SheetGroup(dark: dark, children: [
                    SheetArrowRow(
                      dark: dark,
                      label: '备用线路',
                      value: '${_lines.length}',
                      onTap: _openLines,
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
                  ]),
                if (_hasPreview) ...[
                  SheetGroup(dark: dark, children: [
                    SheetSwitchRow(
                      dark: dark,
                      label: '自动生成预览图',
                      value: _preview,
                      onChanged: (v) => setState(() => _preview = v),
                    ),
                  ]),
                  SheetHint(dark: dark, text: '挂载外部网盘，推荐关闭该选项，否则可能导致风控'),
                ],
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                    child: Text(
                      _message,
                      style: TextStyle(
                        fontSize: 13,
                        color: _failed
                            ? const Color(0xFFC0392B)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
