/// HG 会话：登录 token + 用户资料 + 彩蛋解锁标记，存独立 Hive box。
///
/// 会话按线路 origin 绑定（和 HGhubX 的 session.rs 一致）：换线路
/// token 不跟过去，避免把旧站点的凭证发给新站点。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:hive_ce/hive.dart';

import 'package:XL/modules/hg/hg_models.dart';

class HgSession {
  String origin = '';
  String token = '';
  HgUser? user;

  bool get loggedIn => token.isNotEmpty && origin.isNotEmpty;
}

class HgStore {
  HgStore._();

  static Box? _box;
  static final HgSession session = HgSession();

  /// 彩蛋解锁标记（连点「关于」3 次后置 true，底栏出现入口）。
  ///
  /// 底栏 [_ScaffoldMenu] 不在关于页的 widget 子树里，解锁后靠这个
  /// notifier 把变化推过去立即重建；初始值在 init() 里回填。
  static bool _unlocked = false;
  static final ValueNotifier<bool> unlockedNotifier = ValueNotifier<bool>(false);
  static bool get unlocked => _unlocked;

  static Future<void> init() async {
    _box = await Hive.openBox('hg');
    final origin = _box!.get('session_origin') as String? ?? '';
    final token = _box!.get('session_token') as String? ?? '';
    final userRaw = _box!.get('session_user');
    _unlocked = _box!.get('unlocked') as bool? ?? false;
    unlockedNotifier.value = _unlocked;
    if (token.isNotEmpty && origin.isNotEmpty) {
      session
        ..origin = origin
        ..token = token
        ..user = userRaw is Map
            ? HgUser.fromJson(Map<String, dynamic>.from(userRaw))
            : null;
    }
  }

  static Future<void> setSession(String origin, String token, HgUser? user) async {
    session
      ..origin = origin
      ..token = token
      ..user = user;
    await _box?.put('session_origin', origin);
    await _box?.put('session_token', token);
    await _box?.put(
      'session_user',
      user == null ? null : jsonDecode(jsonEncode(user.toJson())),
    );
  }

  static Future<void> clearSession() async {
    session
      ..origin = ''
      ..token = ''
      ..user = null;
    await _box?.delete('session_origin');
    await _box?.delete('session_token');
    await _box?.delete('session_user');
  }

  static Future<void> unlock() async {
    _unlocked = true;
    unlockedNotifier.value = true;
    await _box?.put('unlocked', true);
  }
}
