import 'package:XL/modules/download/download_module.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/history/history_module.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

sealed class HistoryPlaybackResult {
  const HistoryPlaybackResult();
}

class HistoryPlaybackReady extends HistoryPlaybackResult {
  const HistoryPlaybackReady(this.args);

  final VideoPlaybackArgs args;
}

/// Emby 记录要交给 Emby 自己的播放器，不能塞进番剧那条链路。
class HistoryPlaybackEmby extends HistoryPlaybackResult {
  const HistoryPlaybackEmby(this.launch);

  final EmbyPlaybackLaunch launch;
}

class HistoryPlaybackUnavailable extends HistoryPlaybackResult {
  const HistoryPlaybackUnavailable(this.reason);

  final String reason;
}

/// Restores a history entry into arguments the player route can take.
///
/// The history page and the my page share this one resolution path; cards
/// carry no source-lookup logic of their own.
class HistoryPlaybackService {
  HistoryPlaybackService(this._pluginsController, this._downloadController);

  final PluginsController _pluginsController;
  final DownloadController _downloadController;

  /// [cancelToken] lets the caller abort the online lookup, e.g. when the
  /// loading dialog it put up is dismissed.
  Future<HistoryPlaybackResult> open(
    History history, {
    RuleCancelToken? cancelToken,
  }) async {
    // Emby 记录的适配器名形如 `emby:host:8096`，它不在插件列表里，
    // 走下面那条分支必然找不到源，所以先单独接一下。
    if (history.adapterName.startsWith('emby:')) {
      final launch = await _embyLaunch(history);
      return launch == null
          ? const HistoryPlaybackUnavailable('Emby 服务器不可用，请检查连接后重试')
          : HistoryPlaybackEmby(launch);
    }

    if (HistoryEntryKind.normalize(history.entryKind) ==
        HistoryEntryKind.offline) {
      final args = _offlineArgs(history);
      return args == null
          ? const HistoryPlaybackUnavailable('未找到可用缓存')
          : HistoryPlaybackReady(args);
    }

    final args = await _onlineArgs(history, cancelToken);
    return args == null
        ? const HistoryPlaybackUnavailable('在线源不可用，请重新选择播放源')
        : HistoryPlaybackReady(args);
  }

  /// 把一条 Emby 历史还原成 Emby 播放器要的启动参数。
  ///
  /// 剧集列表必须重新问一次服务器（可能是好几天前的记录），所以这里有一次
  /// 网络往返。失败就返回 null，让上层提示"服务器不可用"。
  Future<EmbyPlaybackLaunch?> _embyLaunch(History history) async {
    final service = EmbyService.instance;
    await service.load();
    EmbyServer? server;
    for (final candidate in service.servers) {
      if (candidate.adapterName == history.adapterName) {
        server = candidate;
        break;
      }
    }
    if (server == null) return null;

    // 播放时把 Emby 的剧集 id 存进了 lastSrc。
    final seriesItemId = history.lastSrc;
    if (seriesItemId.isEmpty) return null;

    final List<EmbyItem> items;
    try {
      items = await service.clientFor(server).fetchEpisodes(
            userId: server.userId,
            seriesId: seriesItemId,
          );
    } catch (e) {
      KazumiLogger().w('HistoryPlaybackService: failed to load emby episodes',
          error: e);
      return null;
    }
    if (items.isEmpty) return null;

    final String title = history.bangumiItem.nameCn.isEmpty
        ? history.bangumiItem.name
        : history.bangumiItem.nameCn;
    return EmbyPlaybackLaunch(
      server: server,
      title: title,
      episodes: items,
      initialIndex: history.lastWatchEpisode.clamp(1, items.length) - 1,
    );
  }

  Future<VideoPlaybackArgs?> _onlineArgs(
    History history,
    RuleCancelToken? cancelToken,
  ) async {
    if (history.lastSrc.isEmpty) {
      return null;
    }
    Plugin? targetPlugin;
    for (final plugin in _pluginsController.pluginList) {
      if (plugin.name == history.adapterName) {
        targetPlugin = plugin;
        break;
      }
    }
    if (targetPlugin == null) {
      return null;
    }
    try {
      final roads = await targetPlugin.queryChapterRoads(
        history.lastSrc,
        cancelToken: cancelToken,
      );
      if (roads.isEmpty) {
        return null;
      }
      return OnlineVideoPlaybackArgs(
        bangumiItem: history.bangumiItem,
        plugin: targetPlugin,
        title: history.bangumiItem.nameCn.isEmpty
            ? history.bangumiItem.name
            : history.bangumiItem.nameCn,
        src: history.lastSrc,
        roads: roads,
      );
    } catch (_) {
      KazumiLogger().w("QueryManager: failed to query roads");
      return null;
    }
  }

  VideoPlaybackArgs? _offlineArgs(History history) {
    final downloadedEpisodes = _downloadController.getCompletedEpisodes(
      history.bangumiItem.id,
      history.adapterName,
    );
    if (downloadedEpisodes.isEmpty) {
      return null;
    }

    // The page url pins the exact episode; the number is the legacy fallback.
    DownloadEpisode? targetEpisode;
    DownloadEpisode? numberMatch;
    for (final episode in downloadedEpisodes) {
      if (history.episodePageUrl.isNotEmpty &&
          episode.episodePageUrl == history.episodePageUrl) {
        targetEpisode = episode;
        break;
      }
      if (episode.episodeNumber == history.lastWatchEpisode) {
        numberMatch ??= episode;
      }
    }
    targetEpisode ??= numberMatch;
    if (targetEpisode == null) {
      return null;
    }

    final localPath = _downloadController.getLocalVideoPath(
      history.bangumiItem.id,
      history.adapterName,
      targetEpisode.episodeNumber,
    );
    if (localPath == null) {
      return null;
    }

    return OfflineVideoPlaybackArgs(
      bangumiItem: history.bangumiItem,
      pluginName: history.adapterName,
      episodeNumber: targetEpisode.episodeNumber,
      road: targetEpisode.road,
      downloadedEpisodes: downloadedEpisodes,
    );
  }
}
