import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/emby/emby_vault_lock_page.dart';
import 'package:XL/services/emby/vault_lock.dart';

/// 本地私密锁的管理页（「我的」→「本地私密锁」）。
///
/// * 没设密码：只有一行「开启密码锁」，直接进设置流程；
/// * 已设密码：修改密码（先验旧密码再设新的）、生物解锁开关、
///   关闭密码锁（也要验旧密码）。
class VaultLockSettingsPage extends StatefulWidget {
  const VaultLockSettingsPage({super.key});

  @override
  State<VaultLockSettingsPage> createState() => _VaultLockSettingsPageState();
}

class _VaultLockSettingsPageState extends State<VaultLockSettingsPage> {
  bool _bioUsable = false;

  @override
  void initState() {
    super.initState();
    VaultLock.biometricAvailable().then((v) {
      if (mounted) setState(() => _bioUsable = v);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 验证旧密码：复用锁页的解锁模式，返回 true 表示验证通过。
  Future<bool> _verifyOldPin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const EmbyVaultLockPage()),
    );
    return ok == true;
  }

  Future<void> _enableLock() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const EmbyVaultLockPage(setupOnly: true),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _changePin() async {
    if (!await _verifyOldPin() || !mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const EmbyVaultLockPage(setupOnly: true),
      ),
    );
    if (ok == true && mounted) {
      _toast('密码已更新');
      setState(() {});
    }
  }

  Future<void> _disableLock() async {
    if (!await _verifyOldPin() || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关闭密码锁？'),
        content: const Text('关闭后进入本地私密将不再需要密码，生物解锁也会一并关闭。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await VaultLock.reset();
    if (mounted) {
      _toast('已关闭本地私密锁');
      setState(() {});
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value && !_bioUsable) {
      _toast('这台设备没有可用的面容 / 指纹，先去系统里录入');
      return;
    }
    await VaultLock.setBiometricEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final locked = VaultLock.isSet;
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: AppBar(
        backgroundColor: PvColors.page(context),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '本地私密锁',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 40),
        children: [
          PvGroup(
            children: [
              if (!locked) ...[
                PvRow(
                  icon: Icons.lock_outline_rounded,
                  iconColor: PvColors.blue,
                  title: '开启密码锁',
                  subtitle: '进入本地私密前需要输入 4 位密码',
                  onTap: _enableLock,
                  showDivider: false,
                ),
              ] else ...[
                PvRow(
                  icon: Icons.password_rounded,
                  iconColor: PvColors.blue,
                  title: '修改密码',
                  subtitle: '需要先验证当前密码',
                  onTap: _changePin,
                ),
                PvRow(
                  icon: Icons.face_retouching_natural_rounded,
                  iconColor: const Color(0xFF34C759),
                  title: '面容 / 指纹解锁',
                  subtitle: _bioUsable ? null : '这台设备没有可用的生物识别',
                  trailingWidget: PvSwitch(
                    value: VaultLock.biometricEnabled,
                    onChanged: _toggleBiometric,
                  ),
                  trailing: PvRowTrailing.widget,
                  onTap: () =>
                      _toggleBiometric(!VaultLock.biometricEnabled),
                  showDivider: false,
                ),
              ],
            ],
          ),
          if (locked) ...[
            const SizedBox(height: 6),
            PvGroup(
              children: [
                PvRow(
                  icon: Icons.lock_open_rounded,
                  iconColor: PvColors.red,
                  title: '关闭密码锁',
                  titleColor: PvColors.red,
                  subtitle: '需要先验证当前密码',
                  onTap: _disableLock,
                  showDivider: false,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
