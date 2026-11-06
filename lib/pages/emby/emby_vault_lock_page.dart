import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/vault_lock.dart';

/// 本地私密的访问锁页。
///
/// 三种状态（一个页面走完整个生命周期）：
///   * [setupFirst / setupConfirm] —— 第一次进私密时设置 4 位密码，
///     确认后弹窗问要不要启用面容 / 指纹解锁；
///   * [unlock] —— 已设密码，二选一解锁：生物识别（自动拉起一次，
///     失败后点图标重试）或数字键盘，底部胶囊随时切换。
///
/// 视觉照 iOS 的 App Lock 还原：大标题 + 居中 Face ID 图标 /
/// 「请输入密码」+ 圆点 + 圆形数字键盘 + 蓝色胶囊切换。
/// 返回值：true = 解锁（或首次设置）成功。
///
/// [setupOnly] = true 时跳过解锁、直接走「设置新密码」流程——「设置 →
/// 本地私密锁 → 修改密码」里，旧密码已经在上一步验证过了。
class EmbyVaultLockPage extends StatefulWidget {
  const EmbyVaultLockPage({super.key, this.setupOnly = false});

  final bool setupOnly;

  @override
  State<EmbyVaultLockPage> createState() => _EmbyVaultLockPageState();
}

enum _LockPhase { setupFirst, setupConfirm, unlock }

enum _LockMode { biometric, keypad }

class _EmbyVaultLockPageState extends State<EmbyVaultLockPage> {
  _LockPhase _phase = _LockPhase.unlock;
  _LockMode _mode = _LockMode.keypad;

  String _pin = '';
  String _firstPin = '';
  String _message = '';

  bool _shake = false;
  bool _busy = false;
  bool _bioUsable = false;
  Timer? _shakeTimer;

  @override
  void initState() {
    super.initState();
    if (widget.setupOnly || !VaultLock.isSet) {
      _phase = _LockPhase.setupFirst;
      _message = '设置 4 位数字密码，用于访问本地私密';
    }
    _initMode();
  }

  Future<void> _initMode() async {
    final usable = await VaultLock.biometricAvailable();
    if (!mounted) return;
    setState(() {
      _bioUsable = usable;
      if (_phase == _LockPhase.unlock &&
          _mode == _LockMode.keypad &&
          usable &&
          VaultLock.biometricEnabled) {
        _mode = _LockMode.biometric;
      }
    });
    if (_mode == _LockMode.biometric) {
      // 稍等页面转场完再拉系统弹窗，否则 iOS 面容框会和转场打架。
      Future.delayed(const Duration(milliseconds: 500), _authenticate);
    }
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ 生物识别

  Future<void> _authenticate() async {
    if (_busy || _phase != _LockPhase.unlock) return;
    setState(() => _busy = true);
    final ok = await VaultLock.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? '' : '验证未通过，请重试';
    });
    if (ok) _done();
  }

  // ------------------------------------------------------------ 键盘

  void _onDigit(String d) {
    if (_busy || _pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += d;
      _message = '';
    });
    if (_pin.length == 4) _onFull();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _onFull() async {
    switch (_phase) {
      case _LockPhase.setupFirst:
        setState(() {
          _firstPin = _pin;
          _phase = _LockPhase.setupConfirm;
          _pin = '';
          _message = '请再次输入密码';
        });
      case _LockPhase.setupConfirm:
        if (_pin == _firstPin) {
          await VaultLock.setPin(_pin);
          await _askBiometric();
        } else {
          _shakePin('两次输入不一致，请重新设置');
          setState(() {
            _phase = _LockPhase.setupFirst;
            _firstPin = '';
            _message = '设置 4 位数字密码，用于访问本地私密';
          });
        }
      case _LockPhase.unlock:
        if (VaultLock.verifyPin(_pin)) {
          HapticFeedback.mediumImpact();
          _done();
        } else {
          _shakePin('密码不正确');
        }
    }
  }

  /// 首次设置完：iOS 风弹窗问要不要生物解锁。
  Future<void> _askBiometric() async {
    final usable = await VaultLock.biometricAvailable();
    if (!mounted) return;
    var enable = false;
    if (usable) {
      final name = _bioName();
      enable = await showKzConfirm(
        context: context,
        title: '启用$name解锁？',
        message: '之后进入本地私密时，可以用生物识别代替数字密码。',
        cancelLabel: '暂不',
        confirmLabel: '启用',
      );
    }
    if (enable && mounted) {
      setState(() => _busy = true);
      final ok = await VaultLock.authenticateWithBiometrics();
      if (!mounted) return;
      setState(() => _busy = false);
      await VaultLock.setBiometricEnabled(ok);
      if (!ok) {
        KazumiDialog.showToast(message: '生物识别没有通过，之后可以在解锁页再开');
      }
    }
    if (mounted) _done();
  }

  String _bioName() {
    if (_bioUsable) return '面容 ID 或指纹';
    return '生物识别';
  }

  void _shakePin(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _shake = true;
      _message = message;
    });
    _shakeTimer?.cancel();
    _shakeTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _shake = false;
        _pin = '';
      });
    });
  }

  void _done() {
    Navigator.of(context).pop(true);
  }

  void _switchMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = _mode == _LockMode.biometric ? _LockMode.keypad : _LockMode.biometric;
      _pin = '';
      _message = '';
    });
    if (_mode == _LockMode.biometric) {
      Future.delayed(const Duration(milliseconds: 260), _authenticate);
    }
  }

  // ------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 12, 0),
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 24,
                    color: PvColors.ink2(context),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
            ),
            Expanded(
              child: _mode == _LockMode.biometric
                  ? _buildBiometric(dark)
                  : _buildKeypad(),
            ),
            if (_phase == _LockPhase.unlock &&
                (_mode == _LockMode.keypad
                    ? (_bioUsable && VaultLock.biometricEnabled)
                    : true))
              Padding(
                padding: const EdgeInsets.only(bottom: 26),
                child: _PillButton(
                  label: _mode == _LockMode.biometric
                      ? '切换到数字键盘'
                      : '切换到面容 ID 或指纹 ID',
                  onTap: _switchMode,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometric(bool dark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('私密', style: PvText.pageTitle(context)),
        const SizedBox(height: 62),
        GestureDetector(
          onTap: _authenticate,
          behavior: HitTestBehavior.opaque,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('bio_$_busy'),
            tween: Tween<double>(begin: 1, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (context, scale, child) => Transform.scale(
              scale: _busy ? 0.94 : scale,
              child: child,
            ),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: PvColors.card(context),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: PvColors.blue,
                        ),
                      )
                    : _FaceIdIcon(size: 56, color: PvColors.ink(context)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _message.isEmpty ? '轻触图标进行识别' : _message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _message.isEmpty
                ? PvColors.ink2(context)
                : PvColors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad() {
    final title = switch (_phase) {
      _LockPhase.setupFirst => '设置密码',
      _LockPhase.setupConfirm => '请再次输入密码',
      _LockPhase.unlock => '请输入密码',
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('私密', style: PvText.pageTitle(context)),
        const SizedBox(height: 30),
        Text(
          title,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: PvColors.ink(context),
          ),
        ),
        if (_phase != _LockPhase.unlock && _message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _message,
              style: TextStyle(fontSize: 13, color: PvColors.ink3(context)),
            ),
          ),
        const SizedBox(height: 22),
        _PinDots(count: _pin.length, shake: _shake),
        const SizedBox(height: 30),
        _Keypad(
          onDigit: _onDigit,
          onDelete: _onDelete,
        ),
      ],
    );
  }
}

/// 4 位圆点：未填蓝描边空心、已填实心蓝；错了整排横向抖动。
class _PinDots extends StatelessWidget {
  const _PinDots({required this.count, required this.shake});

  final int count;
  final bool shake;

  @override
  Widget build(BuildContext context) {
    Widget row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? PvColors.blue : Colors.transparent,
              border: Border.all(color: PvColors.blue, width: 1.6),
            ),
          ),
        ],
      ],
    );
    if (shake) {
      row = TweenAnimationBuilder<double>(
        key: ValueKey('shake_$count'),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.linear,
        builder: (context, t, child) {
          // 左右各摆两下、幅度衰减，像 iOS 输错密码那样的横抖。
          final offset = math.sin(t * math.pi * 4) * 9 * (1 - t);
          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
        child: row,
      );
    }
    return row;
  }
}

/// 3x4 圆形数字键盘（截图样式：灰底圆、24px 数字、右下退格）。
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onDelete});

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = PvColors.isDark(context);
    final fill = dark ? Colors.white.withValues(alpha: 0.09) : const Color(0xFFF2F2F6);
    final ink = PvColors.ink(context);
    Widget key(Widget child, {VoidCallback? onTap}) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
          alignment: Alignment.center,
          child: child,
        ),
      );
    }

    Widget digit(String d) => key(
          Text(
            d,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w400,
              color: ink,
            ),
          ),
          onTap: () => onDigit(d),
        );

    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 20),
                  digit(row[i]),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 74),
              const SizedBox(width: 20),
              digit('0'),
              const SizedBox(width: 20),
              key(
                Icon(Icons.backspace_outlined, size: 22, color: ink),
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 底部蓝色胶囊（截图「切换到…」）。
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: PvColors.blue,
          borderRadius: BorderRadius.circular(19),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// iOS Face ID 风格图标：四角括号 + 双眼 + 鼻 + 微笑弧。
class _FaceIdIcon extends StatelessWidget {
  const _FaceIdIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FaceIdPainter(color),
    );
  }
}

class _FaceIdPainter extends CustomPainter {
  _FaceIdPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final inset = w * 0.08;
    final len = w * 0.24;

    // 四角括号。
    final corners = [
      [Offset(inset, inset + len), Offset(inset, inset), Offset(inset + len, inset)],
      [Offset(w - inset - len, inset), Offset(w - inset, inset), Offset(w - inset, inset + len)],
      [Offset(w - inset, h - inset - len), Offset(w - inset, h - inset), Offset(w - inset - len, h - inset)],
      [Offset(inset + len, h - inset), Offset(inset, h - inset), Offset(inset, h - inset - len)],
    ];
    for (final c in corners) {
      final path = Path()
        ..moveTo(c[0].dx, c[0].dy)
        ..lineTo(c[1].dx, c[1].dy)
        ..lineTo(c[2].dx, c[2].dy);
      canvas.drawPath(path, stroke);
    }

    // 双眼。
    final eyeY = h * 0.38;
    final eyeDx = w * 0.13;
    canvas.drawCircle(Offset(w / 2 - eyeDx, eyeY), w * 0.035, dot);
    canvas.drawCircle(Offset(w / 2 + eyeDx, eyeY), w * 0.035, dot);

    // 鼻子：短竖线 + 底部小折。
    final nosePath = Path()
      ..moveTo(w / 2, h * 0.40)
      ..lineTo(w / 2, h * 0.55)
      ..quadraticBezierTo(w / 2, h * 0.60, w / 2 - w * 0.045, h * 0.60);
    canvas.drawPath(nosePath, stroke);

    // 微笑弧。
    final mouth = Path()
      ..moveTo(w * 0.32, h * 0.70)
      ..quadraticBezierTo(w / 2, h * 0.80, w * 0.68, h * 0.70);
    canvas.drawPath(mouth, stroke);
  }

  @override
  bool shouldRepaint(covariant _FaceIdPainter oldDelegate) =>
      oldDelegate.color != color;
}
