import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/storage/storage.dart';

/// Emby 服务器配置的读写与客户端缓存。
///
/// 故意做成静态单例而不是 modular 里的 singleton：设置页（`/emby/servers`）
/// 和播放页（`/video/`）分属两个模块，跨模块 inject 会多出一圈注册代码，
/// 而这里的状态本来就是全局唯一的一份。项目里 `RulesRepoClient.instance`
/// 也是同样的做法。
class EmbyService {
  EmbyService._();

  static final EmbyService instance = EmbyService._();

  /// 配置变更信号。页面订阅它来重建，避免各处手动刷新。
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<EmbyServer> _servers = const [];
  final Map<String, EmbyClient> _clients = {};
  String? _deviceId;
  bool _loaded = false;

  List<EmbyServer> get servers => List<EmbyServer>.unmodifiable(_servers);

  /// 当前选中的服务器；选中项被删掉时退回第一个。
  EmbyServer? get activeServer {
    if (_servers.isEmpty) return null;
    final activeId = GStorage.getSetting(SettingsKeys.embyActiveServerId);
    for (final server in _servers) {
      if (server.id == activeId) return server;
    }
    return _servers.first;
  }

  /// 当前服务器的客户端。没配服务器时为 null。
  EmbyClient? get activeClient {
    final server = activeServer;
    if (server == null) return null;
    return clientFor(server);
  }

  /// 同一台服务器的客户端复用同一个 Dio，省掉重复建连接池。
  ///
  /// 备用线路一并交给客户端：主线路连不上时它会自己换下一条，
  /// 切换结果记在客户端实例里，后续请求不用再等主线路超时。
  EmbyClient clientFor(EmbyServer server) {
    return _clients.putIfAbsent(
      server.id,
      () => EmbyClient(
        serverUrl: server.url,
        backupUrls: server.backupUrls,
        accessToken: server.accessToken,
        allowBadCertificate: server.allowBadCertificate,
        deviceId: deviceId,
      ),
    );
  }

  /// 一次性设备 id，Emby 靠它在「设备」列表里认出这是同一台机器。
  String get deviceId {
    if (_deviceId != null) return _deviceId!;
    var stored = GStorage.getSetting(SettingsKeys.embyDeviceId);
    if (stored.isEmpty) {
      stored = _randomHex(16);
      // 写盘是异步的，但内存里立刻生效，不需要等。
      GStorage.putSetting(SettingsKeys.embyDeviceId, stored);
    }
    _deviceId = stored;
    return stored;
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0')
    ].join();
  }

  /// 生成一个本地服务器 id（不和 Emby 服务端的 ServerId 混用）。
  static String newServerId() => _randomHex(8);

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    final raw = GStorage.getSetting(SettingsKeys.embyServers);
    if (raw.trim().isEmpty) {
      _servers = const [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _servers = const [];
        return;
      }
      _servers = [
        for (final item in decoded)
          if (item is Map)
            EmbyServer.fromJson(Map<String, dynamic>.from(item)),
      ].where((server) => server.id.isNotEmpty && server.url.isNotEmpty).toList();
    } catch (e) {
      // 配置坏了不能让应用起不来，退化成"没有服务器"，用户重新填一遍即可。
      KazumiLogger().w('Emby: failed to parse server list', error: e);
      _servers = const [];
    }
  }

  Future<void> _persist() async {
    await GStorage.putSetting(
      SettingsKeys.embyServers,
      jsonEncode([for (final server in _servers) server.toJson()]),
    );
    revision.value++;
  }

  /// 新增或按 id 覆盖。
  Future<void> upsert(EmbyServer server) async {
    await load();
    final index = _servers.indexWhere((item) => item.id == server.id);
    if (index >= 0) {
      _servers = [..._servers]..[index] = server;
    } else {
      _servers = [..._servers, server];
    }
    // 配置变了（地址/Token/证书开关），旧客户端不能再用。
    _disposeClient(server.id);
    await _persist();
    final activeId = GStorage.getSetting(SettingsKeys.embyActiveServerId);
    if (activeId.isEmpty) {
      await setActive(server.id);
    }
  }

  Future<void> remove(String id) async {
    await load();
    _servers = [..._servers.where((server) => server.id != id)];
    _disposeClient(id);
    await _persist();
    final activeId = GStorage.getSetting(SettingsKeys.embyActiveServerId);
    if (activeId == id) {
      await GStorage.putSetting(
        SettingsKeys.embyActiveServerId,
        _servers.isEmpty ? '' : _servers.first.id,
      );
      revision.value++;
    }
  }

  Future<void> setActive(String id) async {
    await GStorage.putSetting(SettingsKeys.embyActiveServerId, id);
    revision.value++;
  }

  void _disposeClient(String serverId) {
    _clients.remove(serverId)?.close();
  }
}
