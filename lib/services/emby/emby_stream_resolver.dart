import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/logging/logger.dart';

/// 一条真正能出流的地址。
///
/// 除了 url 本身，还带出 `mediaSourceId`——进度上报必须用它，否则 Emby 会把
/// 「正在播放」记到一个不存在的媒体源上，服务端的继续观看永远不会更新。
class EmbyStreamResolution {
  const EmbyStreamResolution({
    required this.url,
    required this.mediaSourceId,
    required this.isHls,
    required this.mediaSource,
    this.forcedTranscode = false,
  }) : error = '';

  const EmbyStreamResolution.failed(this.error)
      : url = '',
        mediaSourceId = null,
        isHls = false,
        mediaSource = null,
        forcedTranscode = false;

  final String url;
  final String? mediaSourceId;
  final bool isHls;
  final EmbyMediaSource? mediaSource;
  final String error;

  /// 这一次是用户明确要求「始终转码」，不是探测失败后的回落。
  ///
  /// 播放器的媒体信息面板要区分这两件事：一个是「你的设置」，一个是
  /// 「服务器只能这么给」，用户看到的解释完全不同。
  final bool forcedTranscode;

  bool get isOk => url.isNotEmpty;

  /// 面板上那一行「直连 / 转码」。
  String get modeLabel => isHls
      ? (forcedTranscode ? '服务器转码（已强制）' : '服务器转码')
      : '原盘直连';
}

/// 把「这一集怎么播」这件事收敛到一处。
///
/// 以前这段逻辑散在 `VideoPageController` 里，Emby 换成独立播放器后两边都要用，
/// 所以抽出来。顺序由「转码与串流」页的设置决定：
///
///   * 自动（默认）：直连（带真实媒体源 id）→ 直连（不带）→ 转码；
///   * 直连：只试两条直连，都不通就报错，绝不偷偷降级成转码；
///   * 转码：直接走 HLS，并按画质上限压码率。
///
/// 每一步都先探测。地址不对时服务端其实已经把原因写在响应体里了
/// （`Value cannot be null. (Parameter 'mediaSource')`），直接喂给播放器只会
/// 变成一行 "failed to open" 和一片黑屏。
class EmbyStreamResolver {
  const EmbyStreamResolver._();

  static Future<EmbyStreamResolution> resolve({
    required EmbyClient client,
    required String itemId,
    required String userId,
    bool preferDirect = true,
    EmbyStreamMode? mode,
    int? maxBitrateMbps,
  }) async {
    final mediaSource = await client.fetchPlaybackInfo(
      itemId: itemId,
      userId: userId,
    );
    final mediaSourceId = mediaSource?.id;
    final streamMode = mode ?? EmbyStreamPrefs.mode;
    final mbps = maxBitrateMbps ?? EmbyStreamPrefs.bitrateMbps;
    final bitrateBps = mbps <= 0 ? 0 : mbps * 1000 * 1000;

    final attempts = <_Attempt>[];
    void addDirect() {
      attempts
          .add(_Attempt(client.directStreamUrl(itemId, mediaSourceId: mediaSourceId)));
      if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
        attempts.add(_Attempt(client.directStreamUrl(itemId)));
      }
    }

    void addHls() {
      attempts.add(_Attempt(
        client.hlsStreamUrl(
          itemId,
          mediaSourceId: mediaSourceId,
          maxBitrateBps: bitrateBps,
        ),
        hls: true,
      ));
    }

    switch (streamMode) {
      case EmbyStreamMode.direct:
        addDirect();
      case EmbyStreamMode.transcode:
        addHls();
      case EmbyStreamMode.auto:
        if (preferDirect) addDirect();
        addHls();
        if (!preferDirect) addDirect();
    }

    String lastError = '';
    for (final attempt in attempts) {
      final probe = await client.probeStream(attempt.url);
      if (probe.isOk) {
        return EmbyStreamResolution(
          url: attempt.url,
          mediaSourceId: mediaSourceId,
          isHls: attempt.hls,
          mediaSource: mediaSource,
          forcedTranscode:
              attempt.hls && streamMode == EmbyStreamMode.transcode,
        );
      }
      lastError = probe.userMessage;
      KazumiLogger().w(
        'EmbyStreamResolver: probe failed (${attempt.hls ? "hls" : "direct"}) -> $lastError',
      );
    }

    // 强制直连失败时给一句能指导下一步的话，而不是把服务端原文丢出去。
    if (streamMode == EmbyStreamMode.direct) {
      return EmbyStreamResolution.failed(
        lastError.isEmpty
            ? '服务器不给原盘直连。到「转码与串流」里把方式改成自动或转码再试'
            : '原盘直连失败：$lastError。可以到「转码与串流」里改成转码试试',
      );
    }
    return EmbyStreamResolution.failed(
      lastError.isEmpty ? '无法播放这一集' : lastError,
    );
  }
}

class _Attempt {
  const _Attempt(this.url, {this.hls = false});

  final String url;
  final bool hls;
}
