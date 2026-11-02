import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';

/// LU 本地账号资料：头像 + 昵称。
///
/// 「我的」页账号行只显示这两样，不再往同步设置里跳。头像存本地图片的
/// 绝对路径（相册选的或文件导入的），昵称随便改。
class LuProfile {
  LuProfile._();

  static final LuProfile instance = LuProfile._();

  static const String defaultNickname = 'LU 用户';

  static const _nameKey = SettingKey<String>(
    'luProfileNickname',
    defaultNickname,
    group: SettingGroup.interface,
  );

  static const _avatarKey = SettingKey<String>(
    'luProfileAvatar',
    '',
    group: SettingGroup.interface,
  );

  String _nickname = defaultNickname;
  String _avatarPath = '';
  bool _loaded = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final name = GStorage.getSetting(_nameKey).trim();
      _nickname = name.isEmpty ? defaultNickname : name;
      _avatarPath = GStorage.getSetting(_avatarKey).trim();
    } catch (_) {
      _nickname = defaultNickname;
      _avatarPath = '';
    }
  }

  String get nickname {
    _ensureLoaded();
    return _nickname;
  }

  /// 头像的本地路径，没设过就是空串。
  String get avatarPath {
    _ensureLoaded();
    return _avatarPath;
  }

  bool get hasAvatar => avatarPath.isNotEmpty;

  Future<void> setNickname(String value) async {
    _ensureLoaded();
    final next = value.trim();
    _nickname = next.isEmpty ? defaultNickname : next;
    await GStorage.putSetting(_nameKey, _nickname);
  }

  Future<void> setAvatarPath(String value) async {
    _ensureLoaded();
    _avatarPath = value.trim();
    await GStorage.putSetting(_avatarKey, _avatarPath);
  }

  Future<void> clearAvatar() => setAvatarPath('');
}
