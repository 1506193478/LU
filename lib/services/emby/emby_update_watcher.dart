import 'dart:async';
import 'dart:convert';

import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/notification/lu_notification_center.dart';
import 'package:XL/services/storage/storage.dart';

/// 追更提醒：App 运行期间定期检查收藏剧集有没有更新。
///
/// 原理很朴素：记住每部收藏剧「上次检查时见过的最大集号」，下次检查发现
/// 最大集号变大，就往通知中心塞一条「更新了 N 集」。第一次见到一部剧只记
/// 基线不通知——不然装完 App 第一天收一堆「这是你收藏的剧」。
///
/// 触发时机受平台限制：App 退到后台 / 被杀就查不了（没有后台任务通道），
/// 所以是「启动后延迟一拍 + 每 6 小时一轮」。数据全部本地，不开通知的
/// 时候只有一次收藏列表 + 每剧一次集数列表的读请求。
class EmbyUpdateWatcher {
  EmbyUpdateWatcher._();

  static final EmbyUpdateWatcher instance = EmbyUpdateWatcher._();

  static const SettingKey<String> _stateKey = SettingKey<String>(
    'emby.updateWatcher',
    '',
    group: SettingGroup.emby,
  );

  /// 首次基线记录用的版本：v1 起服务才算上线。
  static const int _stateVersion = 1;

  Timer? _timer;
  bool _checking = false;
  bool _started = false;

  /// 开关（设置里可关）。关掉时停止轮询。
  static bool get enabled =>
      GStorage.getSetting(SettingsKeys.embyUpdateWatcher);

  /// 启动轮询：启动 45 秒后先查一轮，之后每 6 小时一轮。
  /// 重复调用安全（只起一次）。
  void start() {
    if (_started) return;
    _started = true;
    Future<void>.delayed(const Duration(seconds: 45), () async {
      await checkNow();
    });
    _timer = Timer.periodic(const Duration(hours: 6), (_) {
      if (!enabled) return;
      unawaited(checkNow());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// 立即检查一轮。返回本轮发现的新集条数（测试 / 手动刷新用）。
  Future<int> checkNow() async {
    if (_checking) return 0;
    if (!enabled) return 0;
    _checking = true;
    var added = 0;
    try {
      final service = EmbyService.instance;
      await service.load();
      final state = _loadState();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final server in service.servers) {
        if (server.userId.isEmpty || server.accessToken.isEmpty) continue;
        final client = service.clientFor(server);
        List<EmbyItem> favorites;
        try {
          favorites = await client.fetchFavorites(userId: server.userId);
        } catch (e) {
          KazumiLogger().w(
            'Emby update watcher: favorites failed @${server.name}',
            error: e,
          );
          continue;
        }
        final series = favorites.where((i) => i.isSeries).toList();
        for (final s in series) {
          final seriesId = s.id;
          if (seriesId.isEmpty) continue;
          final knownKey = '${server.id}:$seriesId';
          final stored = state['series']?[knownKey] as Map<String, dynamic>?;
          int maxIndex;
          try {
            final episodes = await client.fetchEpisodes(
              userId: server.userId,
              seriesId: seriesId,
            );
            if (episodes.isEmpty) continue;
            maxIndex = _maxEpisodeIndex(episodes);
            if (maxIndex <= 0) continue;
          } catch (e) {
            KazumiLogger().w(
              'Emby update watcher: episodes failed @${server.name}',
              error: e,
            );
            continue;
          }

          final name = s.name;
          final oldIndex = (stored?['maxIndex'] as num?)?.toInt() ?? -1;
          if (stored == null) {
            // 首次见到的剧：只记基线。
            state['series'] ??= <String, dynamic>{};
            (state['series'] as Map<String, dynamic>)[knownKey] = {
              'name': name,
              'serverId': server.id,
              'maxIndex': maxIndex,
              'at': now,
            };
            continue;
          }
          if (maxIndex > oldIndex) {
            final delta = maxIndex - oldIndex;
            await LuNotificationCenter.instance.add(
              category: LuNotificationCategory.update,
              title: name,
              body: delta == 1
                  ? '更新到第 $maxIndex 集'
                  : '更新 $delta 集（最新第 $maxIndex 集）',
              id: 'update-$knownKey-$maxIndex',
            );
            added += delta;
            (state['series'] as Map<String, dynamic>)[knownKey] = {
              'name': name,
              'serverId': server.id,
              'maxIndex': maxIndex,
              'at': now,
            };
          }
        }
      }
      state['version'] = _stateVersion;
      state['lastCheck'] = now;
      await _saveState(state);
      if (added > 0) {
        KazumiLogger().i('Emby update watcher: $added new episode(s) found');
      }
      return added;
    } catch (e) {
      KazumiLogger().w('Emby update watcher: check failed', error: e);
      return 0;
    } finally {
      _checking = false;
    }
  }

  /// 一次集号对不上时取「季号 + 集号」复合排序的最大值的集号。
  int _maxEpisodeIndex(List<EmbyItem> episodes) {
    var best = -1;
    var bestKey = <int>[];
    for (final e in episodes) {
      final season = e.parentIndexNumber ?? 0;
      final index = e.indexNumber ?? 0;
      final key = [season, index];
      if (bestKey.isEmpty || _cmp(key, bestKey) > 0) {
        bestKey = key;
        best = index;
      }
    }
    return best;
  }

  int _cmp(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  Map<String, dynamic> _loadState() {
    final raw = GStorage.getSetting(_stateKey);
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _saveState(Map<String, dynamic> state) async {
    try {
      await GStorage.putSetting(_stateKey, jsonEncode(state));
    } catch (_) {
      // 状态存不上只是下次会重复通知，不致命。
    }
  }

  /// 清空基线（用户关掉开关再打开时不想收历史剧的通知，可以手动重置）。
  Future<void> reset() async {
    await GStorage.putSetting(_stateKey, jsonEncode({
      'version': _stateVersion,
      'series': <String, dynamic>{},
    }));
  }
}
