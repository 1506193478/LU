import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS AVPlayer 播放引擎（方向 B 的 Dart 侧）。
///
/// 原生实现在 `ios/Runner/AvPlayerEnginePlugin.swift`：
///   * MethodChannel `xl/avplayer` —— 控制命令；
///   * EventChannel `xl/avplayer/events` —— 状态回推；
///   * [textureId] 交给 `Texture` widget 渲染（AVPlayerItemVideoOutput 的
///     pixel buffer 经 CADisplayLink 驱动）。
///
/// 设计目标：接口形状尽量贴近 media_kit 的 `Player`（playing/buffering/
/// completed/position/duration/volume/rate + audio/subtitle 轨道），让
/// `EmbyPlayerController` 接入时两边可以走同一套分支逻辑。字幕轨道只有
/// 内嵌的（AVPlayer 不吃外部 srt/ass 挂载，外部字幕仍需 mpv 兜底路径）。
class AvPlayerEngine extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('xl/avplayer');
  static const EventChannel _events = EventChannel('xl/avplayer/events');

  StreamSubscription<dynamic>? _sub;

  int textureId = -1;
  bool ready = false;

  bool playing = false;
  bool buffering = true;
  bool completed = false;
  String error = '';

  /// 画中画。available 只在设备支持 + 当前流走 AVPlayer 时为 true；
  /// active 跟着原生 delegate 事件走（含「按 Home 自动进小窗」）。
  bool pipAvailable = false;
  bool pipActive = false;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffer = Duration.zero;
  double volume = 1;
  double rate = 1;

  /// 轨道：id 是选项在 AVMediaSelectionGroup 里的下标（"no" = 关闭）。
  List<AvPlayerTrack> audioTracks = const [];
  List<AvPlayerTrack> subtitleTracks = const [];
  String currentAudioId = '';
  String currentSubtitleId = '';

  bool _disposed = false;
  int _width = 0;
  int _height = 0;
  int get videoWidth => _width;
  int get videoHeight => _height;

  /// 控制器消费完错误后清掉，避免同一条错误反复触发回退逻辑。
  void resetError() => error = '';

  Future<void> create() async {
    textureId = (await _channel.invokeMethod<int>('create')) ?? -1;
    ready = textureId >= 0;
    _sub ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (e) {
        error = '$e';
        notifyListeners();
      },
    );
    notifyListeners();
  }

  /// [headers] 会经 `AVURLAssetHTTPHeaderFieldsKey` 传给 AVURLAsset——HLS 的
  /// 分片请求也会继承这些头，Emby 转码流光靠地址上的 api_key 不一定够。
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    error = '';
    completed = false;
    buffering = true;
    position = Duration.zero;
    duration = Duration.zero;
    buffer = Duration.zero;
    playing = false;
    notifyListeners();
    await _channel.invokeMethod<void>('open', <String, dynamic>{
      'url': url,
      'headers': headers,
    });
    pipActive = false;
    unawaited(_refreshPipAvailable());
  }

  Future<void> _refreshPipAvailable() async {
    try {
      final available =
          await _channel.invokeMethod<bool>('isPipAvailable') ?? false;
      if (_disposed) return;
      if (available != pipAvailable) {
        pipAvailable = available;
        notifyListeners();
      }
    } catch (_) {
      // 通道没了（页面销毁竞态）就算了。
    }
  }

  /// 退后台自动进小窗的开关（设置页下发；open 后也会由 controller 同步）。
  static Future<void> setAutoPipEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAutoPip', enabled);
    } catch (_) {
      // 引擎还没建好/已销毁时无所谓，open 后会再同步。
    }
  }

  /// 进画中画。失败（PiP 暂不可用等）返回 false，由上层决定提示文案。
  Future<bool> startPip() async {
    try {
      await _channel.invokeMethod<void>('startPip');
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> stopPip() async {
    try {
      await _channel.invokeMethod<void>('stopPip');
    } catch (_) {
      // 页面销毁竞态，无所谓。
    }
  }

  Future<void> play() async {
    await _channel.invokeMethod<void>('play');
    playing = true;
    notifyListeners();
  }

  Future<void> pause() async {
    await _channel.invokeMethod<void>('pause');
    playing = false;
    notifyListeners();
  }

  Future<void> togglePlay() async => playing ? await pause() : await play();

  Future<void> seek(Duration target) async {
    position = target;
    notifyListeners();
    await _channel.invokeMethod<void>('seek', target.inMilliseconds);
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    await _channel.invokeMethod<void>('setVolume', volume);
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    rate = value;
    await _channel.invokeMethod<void>('setRate', value);
    notifyListeners();
  }

  Future<void> selectAudioTrack(String id) async {
    await _channel.invokeMethod<void>('selectAudioTrack', id);
    currentAudioId = id;
    notifyListeners();
  }

  Future<void> selectSubtitleTrack(String id) async {
    await _channel.invokeMethod<void>('selectSubtitleTrack', id);
    currentSubtitleId = id;
    notifyListeners();
  }

  /// 主动问一次轨道列表（资产加载完成后调用，比如 position 第一次 > 0）。
  Future<void> refreshTracks() async {
    final info = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'getTracks',
    );
    if (info == null || _disposed) return;
    for (final group in info) {
      final kind = group['kind']?.toString() ?? '';
      final tracks = <AvPlayerTrack>[
        for (final t in (group['tracks'] as List? ?? []))
          if (t is Map)
            AvPlayerTrack(
              id: t['id']?.toString() ?? '',
              title: t['title']?.toString() ?? '',
              language: t['language']?.toString() ?? '',
            ),
      ];
      if (kind == 'audio') {
        audioTracks = tracks;
        currentAudioId = tracks.isNotEmpty ? tracks.first.id : '';
      } else if (kind == 'subtitle') {
        subtitleTracks = tracks;
        currentSubtitleId = '';
      }
    }
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {
      // 引擎随页面销毁，通道可能已经没了，不必追究。
    }
    super.dispose();
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    switch (event['type']) {
      case 'state':
        position = Duration(milliseconds: (event['position'] as int?) ?? 0);
        duration = Duration(milliseconds: (event['duration'] as int?) ?? 0);
        buffer = Duration(milliseconds: (event['buffered'] as int?) ?? 0);
        playing = event['playing'] == true;
        buffering = event['buffering'] == true;
        // 资产就绪后拉一次轨道（只拉一次：拿过了就不再问）。
        if (duration > Duration.zero &&
            audioTracks.isEmpty &&
            !_tracksRequested) {
          _tracksRequested = true;
          unawaited(refreshTracks());
        }
      case 'completed':
        completed = true;
        playing = false;
      case 'size':
        _width = (event['width'] as int?) ?? 0;
        _height = (event['height'] as int?) ?? 0;
      case 'error':
        error = event['message']?.toString() ?? '播放失败';
      case 'pip':
        pipActive = event['active'] == true;
      default:
        return;
    }
    notifyListeners();
  }

  bool _tracksRequested = false;
}

/// AVPlayer 的一条音轨 / 字幕轨。
class AvPlayerTrack {
  const AvPlayerTrack({
    required this.id,
    required this.title,
    required this.language,
  });

  final String id;
  final String title;
  final String language;
}
