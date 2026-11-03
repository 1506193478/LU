import 'dart:convert';

import 'package:XL/services/storage/storage.dart';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

/// 本地私密的访问锁：4 位数字密码 + 生物识别（iOS 面容/触控 ID、
/// Android 指纹/面容、Windows Hello）。
///
/// 密码只存 sha256 摘要（带固定盐），不落明文。生物识别走 local_auth：
/// Android 端要求主 Activity 是 FlutterFragmentActivity（本项目里是
/// AudioServiceFragmentActivity），iOS 端要在 Info.plist 里声明
/// NSFaceIDUsageDescription。
class VaultLock {
  VaultLock._();

  /// PIN 摘要。空串 = 还没设置过密码。
  static const _pinKey = SettingKey<String>(
    'luVaultPinHash',
    '',
    group: SettingGroup.emby,
  );

  /// 用户是否同意用生物识别解锁。
  static const _biometricKey = SettingKey<bool>(
    'luVaultBiometric',
    false,
    group: SettingGroup.emby,
  );

  static String _hash(String pin) =>
      sha256.convert(utf8.encode('lu-vault-lock:$pin')).toString();

  /// 有没有设置过密码（没设过 = 每次进私密都要先走一遍设置流程）。
  static bool get isSet => GStorage.getSetting(_pinKey).isNotEmpty;

  static bool get biometricEnabled => GStorage.getSetting(_biometricKey);

  static Future<void> setPin(String pin) async {
    await GStorage.putSetting(_pinKey, _hash(pin));
  }

  static Future<void> setBiometricEnabled(bool value) async {
    await GStorage.putSetting(_biometricKey, value);
  }

  static bool verifyPin(String pin) {
    final stored = GStorage.getSetting(_pinKey);
    return stored.isNotEmpty && _hash(pin) == stored;
  }

  static Future<void> reset() async {
    await GStorage.putSetting(_pinKey, '');
    await GStorage.putSetting(_biometricKey, false);
  }

  // ------------------------------------------------------------ 生物识别

  static final LocalAuthentication _auth = LocalAuthentication();

  /// 设备能不能做生物识别（有已注册的指纹 / 面容）。
  static Future<bool> biometricAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported || canCheck;
    } catch (_) {
      return false;
    }
  }

  /// 拉起系统生物识别。失败 / 取消返回 false。
  ///
  /// biometricOnly = true：不许系统回退到设备 PIN——我们自己的数字键盘
  /// 就是 PIN，不能让系统那道变成绕过私密密码的口子。
  static Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: '验证身份以解锁本地私密',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
