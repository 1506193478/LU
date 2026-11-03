import 'dart:async';

import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/lu_cloud_drive.dart';

/// 网盘授权卡片（底部弹出，跟服务器表单同一套壳）。
///
/// 三种授权形态：
///   * 账号密码（123 云盘）—— 直接换 token
///   * 扫码（115 网盘）—— 显示官方二维码，2 秒轮询一次
///   * 粘贴令牌（阿里 / 百度 / OneDrive / Dropbox / 光鸭）—— 存下来直接调 OpenAPI
Future<void> showLuCloudSheet(
  BuildContext context, {
  required String type,
  LuCloudAccount? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.86,
      child: _CloudSheet(type: type, existing: existing),
    ),
  );
}

class _CloudSheet extends StatefulWidget {
  const _CloudSheet({required this.type, this.existing});

  final String type;
  final LuCloudAccount? existing;

  @override
  State<_CloudSheet> createState() => _CloudSheetState();
}

class _CloudSheetState extends State<_CloudSheet> {
  late final TextEditingController _label;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _token;

  bool _obscure = true;
  bool _busy = false;
  String _message = '';
  bool _failed = false;

  // 扫码相关
  Timer? _poll;
  LuQrSession? _qr;
  LuQrState _qrState = LuQrState.waiting;
  String _qrTip = '正在生成二维码…';
  LuCloudAccount? _scanned;

  String get _type => widget.type;
  String get _mode => LuCloudDrive.authMode(_type);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(
      text: e?.label ?? LuCloudDrive.labelOf(_type),
    );
    _user = TextEditingController(text: e?.user ?? '');
    _password = TextEditingController();
    _token = TextEditingController(text: e?.token ?? '');
    if (_mode == 'qrcode' && e == null) _startQr();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _label.dispose();
    _user.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 扫码

  Future<void> _startQr() async {
    try {
      final session = await LuCloudApi.start115Qr();
      if (!mounted) return;
      setState(() {
        _qr = session;
        _qrState = LuQrState.waiting;
        _qrTip = '用 115 App 扫码登录';
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = e.toString();
        _qrTip = '二维码生成失败';
      });
    }
  }

  Future<void> _tick() async {
    final session = _qr;
    if (session == null) return;
    try {
      final (state, account) = await LuCloudApi.poll115Qr(
        session,
        label: _label.text.trim(),
      );
      if (!mounted) return;
      if (state == LuQrState.expired) {
        _poll?.cancel();
        setState(() {
          _qrState = state;
          _qrTip = '二维码已失效，点这里重新生成';
        });
        return;
      }
      if (account != null) {
        _poll?.cancel();
        setState(() {
          _qrState = LuQrState.confirmed;
          _scanned = account;
          _qrTip = '已登录，点右上角保存';
        });
        return;
      }
      if (state != _qrState) {
        setState(() {
          _qrState = state;
          _qrTip = state == LuQrState.scanned
              ? '已扫码，请在手机上确认'
              : '用 115 App 扫码登录';
        });
      }
    } catch (_) {
      // 网络抖动继续轮询，不打断。
    }
  }

  // ------------------------------------------------------------ 保存

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = '';
    });

    try {
      LuCloudAccount account;
      switch (_mode) {
        case 'password':
          if (_user.text.trim().isEmpty || _password.text.isEmpty) {
            throw LuCloudException('请填账号和密码');
          }
          account = await LuCloudApi.login123(
            user: _user.text.trim(),
            password: _password.text,
            label: _label.text.trim(),
          );
        case 'qrcode':
          final scanned = _scanned;
          if (scanned == null) {
            throw LuCloudException('请先用 115 App 扫码登录');
          }
          account = LuCloudAccount(
            id: widget.existing?.id ?? scanned.id,
            type: scanned.type,
            label: _label.text.trim(),
            user: scanned.user,
            token: scanned.token,
            addedAt: widget.existing?.addedAt ?? scanned.addedAt,
          );
        case 'token':
          if (_token.text.trim().isEmpty) {
            throw LuCloudException('请粘贴访问令牌');
          }
          account = LuCloudAccount(
            id: widget.existing?.id ?? LuCloudDrive.accountId(_type),
            type: _type,
            label: _label.text.trim(),
            user: _user.text.trim(),
            token: _token.text.trim(),
            addedAt:
                widget.existing?.addedAt ??
                DateTime.now().millisecondsSinceEpoch,
          );
        default:
          account = LuCloudAccount(
            id: widget.existing?.id ?? LuCloudDrive.accountId(_type),
            type: _type,
            label: _label.text.trim(),
            addedAt:
                widget.existing?.addedAt ??
                DateTime.now().millisecondsSinceEpoch,
          );
      }

      await LuCloudStore.instance.save(account);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '已保存';
      });
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _message = e is LuCloudException ? e.message : '保存失败：$e';
      });
    }
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
          SizedBox(
            height: 54,
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 19,
                      color: Color(0xFF007AFF),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: Text(
                    LuCloudDrive.labelOf(_type),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PvColors.ink(context),
                    ),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: _busy
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _save,
                          child: const Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(right: 16),
                              child: Text(
                                '保存',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
              children: [
                _Group(
                  dark: dark,
                  children: [
                    _LabeledInput(
                      dark: dark,
                      label: '名称',
                      hint: 'Name (可选)',
                      controller: _label,
                    ),
                  ],
                ),
                if (_mode == 'password') ...[
                  _GroupLabel(dark: dark, text: '登录信息'),
                  _Group(
                    dark: dark,
                    children: [
                      _LabeledInput(
                        dark: dark,
                        label: '账号',
                        hint: '手机号 / 邮箱',
                        controller: _user,
                      ),
                      _LabeledInput(
                        dark: dark,
                        label: '密码',
                        hint: 'Password',
                        controller: _password,
                        obscure: _obscure,
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
                    ],
                  ),
                  _Hint(dark: dark, text: '登录后拿到的令牌只存在本机，不会上传'),
                ],
                if (_mode == 'qrcode') _buildQr(dark),
                if (_mode == 'token') ...[
                  _GroupLabel(dark: dark, text: '授权令牌'),
                  _Group(
                    dark: dark,
                    children: [_TokenField(dark: dark, controller: _token)],
                  ),
                  _Hint(dark: dark, text: LuCloudDrive.tokenHint(_type)),
                ],
                if (_mode == 'none')
                  _Hint(dark: dark, text: '这家没有公开接口，暂时只能保存账号信息。'),
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

  Widget _buildQr(bool dark) {
    final session = _qr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Center(
          child: GestureDetector(
            onTap: _qrState == LuQrState.expired ? _startQr : null,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 18,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: session == null || session.imageUrl.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Image.network(
                      session.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          '二维码加载失败\n点这里重试',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: dark
                                ? Colors.white54
                                : const Color(0xFF8A8A8E),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _qrTip,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: _qrState == LuQrState.confirmed
                ? const Color(0xFF2E7D32)
                : (dark ? Colors.white54 : const Color(0xFF6B6B70)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 小组件

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: dark
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFF8A8A8E),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.dark, required this.children});

  final bool dark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1F1E22) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                indent: 14,
                color: dark ? Colors.white10 : const Color(0xFFEBEBEF),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.dark,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.suffix,
  });

  final bool dark;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 14),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 15.5, color: PvColors.ink(context)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 10, right: 4),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFEFEFF3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      obscureText: obscure,
                      textAlign: TextAlign.right,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: PvColors.ink(context),
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: hint,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: dark
                              ? Colors.white24
                              : const Color(0xFFB4B4BA),
                        ),
                      ),
                    ),
                  ),
                  if (suffix != null) suffix!,
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _TokenField extends StatelessWidget {
  const _TokenField({required this.dark, required this.controller});

  final bool dark;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 4,
        style: TextStyle(fontSize: 13.5, color: PvColors.ink(context)),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: '粘贴 access_token',
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: dark ? Colors.white24 : const Color(0xFFB9B9BF),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.dark, required this.text});

  final bool dark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: dark
              ? Colors.white.withValues(alpha: 0.35)
              : const Color(0xFF8A8A8E),
        ),
      ),
    );
  }
}
