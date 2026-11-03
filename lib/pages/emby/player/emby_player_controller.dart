import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/emby/emby_urls.dart';
import 'package:XL/pages/emby/player/emby_player_args.dart';
import 'package:XL/pages/player/controller/player_debug_controller.dart';
import 'package:XL/pages/player/controller/player_playback_controller.dart';
import 'package:XL/request/clients/emby_client.dart';
import 'package:XL/services/emby/emby_service.dart';
import 'package:XL/services/emby/emby_stream_resolver.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/emby/emby_subtitle_picker.dart';
import 'package:XL/services/emby/emby_watch_log.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/player/avplayer_engine.dart';
import 'package:XL/services/player/emby_srt.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/video_source/video_source_format.dart';

/// 播完一条后的行为。
enum EmbyPlaybackMode {
  order('顺序播放'),
  single('单个播放'),
  singleLoop('单个循环'),
  playlistLoop('列表循环'),
  shuffle('随机播放');

  const EmbyPlaybackMode(this.label);
  final String label;
}

/// 解码方式。
enum EmbyDecodeMode {
  hard('硬解码'),
  hardGpu('硬解码 (HW/GPU)'),
  soft('软解码 (SW/CPU)');

  const EmbyDecodeMode(this.label);
  final String label;
}

/// 字幕调节（延迟 / 偏移 / 缩放 / 不透明度）。
class EmbySubtitleSettings {
  const EmbySubtitleSettings({
    this.delay = 0,
    this.verticalOffset = 0,
    this.scale = 1,
    this.opacity = 1,
  });

  final double delay; // 秒，负数为提前
  final double verticalOffset; // 0~100，画面高度百分比
  final double scale; // 0.5~2
  final double opacity; // 0~1

  EmbySubtitleSettings copyWith({
    double? delay,
    double? verticalOffset,
    double? scale,
    double? opacity,
  }) => EmbySubtitleSettings(
    delay: delay ?? this.delay,
    verticalOffset: verticalOffset ?? this.verticalOffset,
    scale: scale ?? this.scale,
    opacity: opacity ?? this.opacity,
  );
}

/// Emby 专用播放器。
///
/// 为什么不复用番剧那条链路：`PlayerController` 背着一整套番剧语义
/// （弹幕、一起看、BangumiItem、假插件、历史落库）。Emby 只需要
/// 「一个地址 + 一条音轨 + 一条字幕轨 + 往服务端报进度」，塞进去反而要处处
/// 加空判断，而且会把一起看的重连逻辑带进来。
///
/// 但底层引擎（media_kit 的封装、硬解、缓存、代理、Android 渲染器选择）是通用的，
/// 直接复用 [PlayerPlaybackController]，不重写。
class EmbyPlayerController extends ChangeNotifier {
  EmbyPlayerController({
    required this.launch,
    required ShaderAssetService shaderAssetService,
  }) {
    playback = PlayerPlaybackController(
      shaderAssetService: shaderAssetService,
      debug: _debug,
      videoUrl: () => _url,
      isLocalPlayback: () => true,
    );
    _client = EmbyService.instance.clientFor(launch.server);
  }

  final EmbyPlaybackLaunch launch;
  final PlayerDebugController _debug = PlayerDebugController();
  late final PlayerPlaybackController playback;
  late final EmbyClient _client;

  String _url = '';
  String? _mediaSourceId;
  int _index = 0;

  bool _disposed = false;
  bool _autoAdvanced = false;

  EmbyItem? get current {
    if (launch.episodes.isEmpty) return null;
    final safe = _index.clamp(0, launch.episodes.length - 1);
    return launch.episodes[safe];
  }

  int get index => _index;
  bool get hasNext => _index + 1 < launch.episodes.length;
  bool get hasPrevious => _index > 0;

  /// 播放器画布。`createVideoController` 成功后才有值。
  VideoController? get videoController => playback.videoController;

  /// 第一条真正能出流的地址，调试用。
  String get streamUrl => _url;

  // ------------------------------------------------------------ 可观察状态

  bool loading = true;
  String error = '';
  bool playing = false;
  bool buffering = true;
  bool completed = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration buffer = Duration.zero;
  double speed = 1;
  bool controlsVisible = true;

  /// 0~100，和 media_kit 的 volume 一致（已含音频增强增益）。
  double volume = 100;

  /// 用户拖动滑杆的音量（不含增益），0~100。
  double baseVolume = 100;

  /// 音频增强倍率：1=关闭，1.5/3/5/10 对应 150%/300%/500%/1000%。
  /// 桌面端 media_kit 走 MPV，音量可超过 100 实现放大；移动端 ExoPlayer 上限 100。
  double audioGain = 1;

  /// 锁定后点击画面不再唤出控件（Rex 的 `player.action.lock_controls`）。
  bool locked = false;

  /// 当前视频的像素尺寸，用于「统计」里显示分辨率。
  int videoWidth = 0;
  int videoHeight = 0;

  // ------------------------------------------------------------ 播放设置

  EmbyPlaybackMode playbackMode = EmbyPlaybackMode.order;

  /// 0=不启用，1=播完当前后停止，>=5=分钟数。
  int sleepMode = 0;
  int sleepRemaining = 0;

  /// 进度条常显：控件不自动隐藏。
  bool progressAlwaysVisible = false;

  /// 后台音频：退出播放器后继续在后台放声音（架构限制，见说明）。
  bool backgroundAudio = false;

  /// 解码方式偏好。
  EmbyDecodeMode decodeMode = EmbyDecodeMode.hard;

  /// 字幕调节。
  EmbySubtitleSettings subtitleSettings = const EmbySubtitleSettings();

  /// 自动跳过片头 / 片尾。
  bool introSkip = false;
  bool outroSkip = false;

  /// 最近一次「用户主动」seek 的时间。自动跳过片头片尾在它之后 1.5 秒内
  /// 不能再插手，否则会把人刚跳过去的位置又拽回来——表现出来就是
  /// 「快进没反应」。
  DateTime? _lastUserSeek;

  /// 转码会话重建后的保护窗，期间不做落点校验（open+seek 本身就要几秒）。
  bool _reopenGuard = false;

  /// 这一条是不是服务端转码（HLS）。seek 健壮化要用它决定「重试失败后
  /// 能不能重建会话」。
  bool _isHls = false;

  /// 当前条目是不是本地/相册直链（不走 Emby 服务器）。
  bool _isLocalDirect = false;

  // ------------------------------------------------------------ AVPlayer 内核

  /// 非空表示当前这条流走的是 iOS AVPlayer 内核（转码 HLS 优先），
  /// null 表示 media_kit/mpv。所有引擎相关分支都看它。
  AvPlayerEngine? _av;

  bool get isAvBackend => _av != null;

  /// AV 路径的画面纹理 id；页面用它渲染 `Texture`。
  int? get avTextureId {
    final engine = _av;
    return (engine != null && engine.ready) ? engine.textureId : null;
  }

  /// AV 路径的当前字幕文本（Dart 层渲染，跟着 position 走）。
  String avSubtitleText = '';

  List<SrtCue> _avCues = const [];
  bool _avCompletedHandled = false;

  /// 内核偏好：`auto` / `av` / `mpv`（见 [SettingsKeys.embyIosKernel]）。
  ///
  /// 「AVPlayer 优先」在 [_open] 里会跳过直连、强制转码——因为 AVPlayer
  /// 只认 MP4/MOV/HLS 这类它认识的容器，直连原盘（MKV 等）塞给它必死；
  /// 转出来的 HLS（H264/AAC/TS）则 100% 兼容。
  bool _shouldUseAv() {
    if (!Platform.isIOS) return false;
    // 这一集已经回退过 mpv 就不再尝试 AV：重试会把刚被服务端回收的
    // 转码会话又耗一遍，用户只会等更久。
    if (_avFallbackUsed) return false;
    final pref = GStorage.getSetting(SettingsKeys.embyIosKernel);
    if (pref == 'mpv') return false;
    return _isHls;
  }

  /// 本集是否已经从 AVPlayer 回退过（防循环）。
  bool _avFallbackUsed = false;

  /// 本集是否已经做过「直连失败 → 降级转码」的重试（防循环）。
  bool _mpvDowngradeTried = false;

  /// 重试时跳过直连、直接用转码流。
  bool _preferTranscodeRetry = false;

  /// mpv 这次 open 的时间，用于判断「开播不久就失败」。
  DateTime? _mpvOpenedAt;

  /// AVPlayer 最后一次失败的原因。回退 mpv 后如果 mpv 也失败，
  /// 两边原因一起显示——一张截图就能看出坏在哪条路。
  String _lastAvError = '';

  /// 把引擎原始错误压成一行可读的（Exception 壳、堆栈都去掉）。
  String _shortError(Object e) {
    var s = e.toString().trim();
    s = s.replaceFirst(
      RegExp(r'^(Exception|PlatformException)\s*\(?.*?:\s*'),
      '',
    );
    if (s.length > 160) s = '${s.substring(0, 160)}…';
    return s;
  }

  /// 当前条目解析出的片头 / 片尾位置。
  Duration? _introStart;
  Duration? _introEnd;
  Duration? _outroStart;
  bool _outroSkipped = false;

  /// 用户手动标记的「片尾开始」（在「片头片尾」面板点「标记当前进度为片尾」）。
  Duration? _outroUserStart;

  /// 当前条目的章节（Emby 提供时才有）。
  List<EmbyChapter> chapters = const [];

  /// 解码方式。media_kit 在移动端会走硬解，桌面端视平台而定，
  /// 这里只按平台给一个大致标签，不假装精确。
  String get decodeLabel => _av != null ? 'AVPlayer 硬解' : decodeMode.label;

  /// 形如 `1920×1080`，拿不到时返回空串。
  String get resolutionLabel =>
      videoWidth > 0 && videoHeight > 0 ? '$videoWidth×$videoHeight' : '';

  /// 形如 `S01E03`，Emby 的单集条目才有。
  String get episodeLabel {
    final item = current;
    if (item == null || !item.isEpisode) return '';
    final s = item.parentIndexNumber;
    final e = item.indexNumber;
    if (s == null || e == null) return '';
    return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
  }

  List<AudioTrack> audioTracks = const [];

  /// media_kit 自己从容器里读出来的字幕轨。
  List<SubtitleTrack> subtitleTracks = const [];

  /// 从 Emby 的 `MediaSources[].MediaStreams` 里翻译过来的字幕轨。
  ///
  /// Emby 的外挂字幕（.srt/.ass）不在视频容器里，mpv 永远读不到，必须走
  /// `/Videos/{id}/{source}/Subtitles/{index}/Stream.srt` 这条地址单独加载。
  /// 这里把它们也做成 [SubtitleTrack]（URI 轨），面板就能和容器内字幕并排列出，
  /// 选中时 `setSubtitleTrack` 直接就把外挂字幕挂上了。
  List<SubtitleTrack> embySubtitleTracks = const [];

  /// 与 [embySubtitleTracks] 一一对应的 Emby 字幕流。
  ///
  /// 面板要显示「中文（简体）[Forced]」这类信息，也要按语言挑默认轨，
  /// 光有 media_kit 的 [SubtitleTrack] 拿不到 `IsForced` / `IsDefault`。
  List<EmbyMediaStream> embySubtitleStreams = const [];

  /// 用户从本地导入的字幕（这次播放有效，换集清空）。
  List<SubtitleTrack> importedSubtitleTracks = const [];

  /// 当前这一条是直连还是转码，给媒体信息面板用。
  String streamModeLabel = '';

  /// 面板上要展示的全部字幕轨：Emby 的在前（更全），用户导入的和容器内的在后。
  List<SubtitleTrack> get allSubtitleTracks => [
    ...embySubtitleTracks,
    ...importedSubtitleTracks,
    ...subtitleTracks,
  ];
  AudioTrack? currentAudio;
  SubtitleTrack? currentSubtitle;

  /// 副字幕（"双字幕"里的第二路）。见 [selectSecondarySubtitle]。
  SubtitleTrack? secondarySubtitle;

  Timer? _progressTimer;
  Timer? _hideTimer;
  Timer? _autoNextTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  // ------------------------------------------------------------ 生命周期

  Future<void> start() async {
    await _open(launch.initialIndex);
  }

  /// 切到第 [target] 条。
  Future<void> openIndex(int target) async {
    if (target < 0 || target >= launch.episodes.length) return;
    // 用户主动换集：上一集的降级记录不带走，每集都有完整的一轮机会。
    if (target != _index) {
      _preferTranscodeRetry = false;
      _lastAvError = '';
    }
    // 已经在放这一条：重复点同一集不该重启引擎。失败状态下允许重来。
    if (target == _index &&
        !loading &&
        error.isEmpty &&
        (playback.mediaPlayer != null || _av != null)) {
      return;
    }
    await _open(target);
  }

  Future<void> _open(int target) async {
    if (_disposed) return;
    final item = launch.episodes[target];
    _index = target;
    _autoAdvanced = false;
    error = '';
    loading = true;
    completed = false;
    position = Duration.zero;
    duration = Duration.zero;
    buffer = Duration.zero;
    _notify();

    // 换集前先停掉旧引擎，避免两个 Player 抢同一个音频输出。
    await _teardownPlayer();
    if (_disposed) return;

    // 本地文件 / 相册视频 / 网络链接 / 网盘直链：条目自带地址，不再问服务端。
    final direct = item.directUrl;
    if (direct != null && direct.isNotEmpty) {
      _url = direct;
      _mediaSourceId = null;
      _isHls = false;
      _isLocalDirect = true;
      _introStart = null;
      _introEnd = null;
      _outroStart = null;
      _outroSkipped = false;
      _outroUserStart = null;
      chapters = const [];
      embySubtitleTracks = const [];
      embySubtitleStreams = const [];
      importedSubtitleTracks = const [];
      streamModeLabel = '本地文件';
    } else {
      _isLocalDirect = false;
      // 每集重置一次性的降级标记；「直连失败降级转码」的重试会带着
      // _preferTranscodeRetry 再进来，直接拿 HLS。
      _avFallbackUsed = false;
      _mpvDowngradeTried = false;
      // 「AVPlayer 优先」：跳过直连探测、直接让服务端出 HLS——AVPlayer
      // 播不了 MKV 这类原盘容器，直连给它必死；强制转码后 100% 兼容。
      final pref = GStorage.getSetting(SettingsKeys.embyIosKernel);
      final resolution = await EmbyStreamResolver.resolve(
        client: _client,
        itemId: item.id,
        userId: launch.server.userId,
        preferDirect:
            GStorage.getSetting(SettingsKeys.embyDirectPlay) &&
            !_preferTranscodeRetry &&
            pref != 'av',
      );
      if (_disposed) return;

      if (!resolution.isOk) {
        loading = false;
        error = resolution.error;
        _notify();
        return;
      }

      _isHls = resolution.isHls;
      _url = resolution.url;
      _mediaSourceId = resolution.mediaSourceId;
      streamModeLabel = resolution.modeLabel;

      // 字幕轨要从 `MediaStreams` 里翻。极少数服务端的 PlaybackInfo 只回
      // 媒体源的壳、不带 MediaStreams，那种情况下字幕面板会是空的——看起来
      // 就像「这个播放器没有字幕功能」。所以空的时候再问一次条目详情。
      var source = resolution.mediaSource;
      if (source == null || source.subtitleStreams.isEmpty) {
        final fallback = await _client.fetchItemMediaSource(
          itemId: item.id,
          userId: launch.server.userId,
        );
        if (fallback != null && fallback.subtitleStreams.isNotEmpty) {
          source = source == null ? fallback : source.withStreamsFrom(fallback);
          _mediaSourceId ??= fallback.id;
        }
      }

      // 片头片尾 / 章节来自 Emby 的 PlaybackInfo，换集时刷新。
      _introStart = source?.introStart;
      _introEnd = source?.introEnd;
      _outroStart = source?.outroStart;
      _outroSkipped = false;
      _outroUserStart = null;
      chapters = source?.chapters ?? const [];

      // 外挂 / 内封字幕全部做成 URI 轨，选谁就把谁挂到引擎上。
      embySubtitleStreams = [
        for (final s in source?.subtitleStreams ?? const <EmbyMediaStream>[]) s,
      ];
      embySubtitleTracks = _buildSubtitleTracks(item.id, embySubtitleStreams);
      importedSubtitleTracks = const [];
    }

    // 服务端记着上次看到哪，直接接着播。
    final startAt = item.resumePosition?.inSeconds ?? 0;

    // iOS + 转码（HLS）优先走 AVPlayer：原生硬解、HDR、seek 稳；其余照旧
    // media_kit（mpv）。设置里可以强制指定内核做兜底。AV 起播失败会自动
    // 重试、最终回退 mpv（见 _avConnectFailed）。
    if (_shouldUseAv()) {
      await _openAv(startAt);
      return;
    }

    await _openMpv(startAt);
  }

  /// mpv / media_kit 路径（Android、Windows、iOS 直连与本地文件，以及
  /// AVPlayer 起播失败后的兜底）。
  Future<void> _openMpv(int startAt) async {
    _mpvOpenedAt = DateTime.now();
    final player = await playback.createVideoController(
      {
        // HLS 的分片请求会继承这些头，只靠地址上的 api_key 不够。
        'X-Emby-Token': launch.server.accessToken,
        'Authorization': 'MediaBrowser Token="${launch.server.accessToken}"',
      },
      false,
      canInstall: () => !_disposed,
      offset: startAt,
      videoSourceFormat: _isHls
          ? VideoSourceFormat.hls
          : VideoSourceFormat.auto,
    );
    if (_disposed) return;

    if (player == null) {
      loading = false;
      error = '播放器初始化失败，请重试';
      _notify();
      return;
    }

    _attachStreams(player);
    _applySubtitleSettings();
    loading = false;
    _notify();

    // 起播就按偏好挂上默认字幕，别让用户每集都手动点一次。
    unawaited(_applyDefaultSubtitle());

    unawaited(_reportStart());
    unawaited(_logWatch());
    _startProgressTimer();
    _scheduleHideControls();
  }

  void _attachStreams(Player player) {
    _cancelSubscriptions();
    void bind<T>(Stream<T> stream, void Function(T value) onData) {
      _subscriptions.add(stream.listen(onData));
    }

    bind(player.stream.position, (value) {
      position = value;
      _maybeSkipIntroOutro(value);
      _notify();
    });
    bind(player.stream.duration, (value) {
      duration = value;
      _notify();
    });
    bind(player.stream.buffer, (value) {
      buffer = value;
      _notify();
    });
    bind(player.stream.playing, (value) {
      playing = value;
      if (value) _scheduleHideControls();
      _notify();
    });
    bind(player.stream.buffering, (value) {
      buffering = value;
      _notify();
    });
    bind(player.stream.completed, (value) {
      completed = value;
      if (value) _handleCompleted();
      _notify();
    });
    bind(player.stream.tracks, (tracks) {
      audioTracks = tracks.audio;
      subtitleTracks = tracks.subtitle;
      _notify();
    });
    bind(player.stream.track, (_) {
      currentAudio = player.state.track.audio;
      currentSubtitle = player.state.track.subtitle;
      _notify();
    });
    bind(player.stream.rate, (value) {
      speed = value;
      _notify();
    });
    bind(player.stream.volume, (value) {
      volume = value;
      _notify();
    });
    bind(player.stream.width, (value) {
      videoWidth = value ?? 0;
      _notify();
    });
    bind(player.stream.height, (value) {
      videoHeight = value ?? 0;
      _notify();
    });
    bind(player.stream.error, (Object e) {
      if (_disposed) return;
      final String raw = _shortError(e);
      final openedAt = _mpvOpenedAt;
      final bool justOpened =
          openedAt != null &&
          DateTime.now().difference(openedAt) <= const Duration(seconds: 12);
      // 直连 + 开播初期：自动降级成转码重试一次（转码出来的 H264/AAC
      // 哪个平台都能播）。转码流失败不在这降级，走下面的错误显示。
      if (!_mpvDowngradeTried && !_isLocalDirect && !_isHls && justOpened) {
        _mpvDowngradeTried = true;
        _preferTranscodeRetry = true;
        KazumiLogger().w('EmbyPlayer: 直连打不开，自动降级转码重试 ($raw)');
        unawaited(_open(_index));
        return;
      }
      // 还没出流就失败：给出带内核/流类型诊断的错误视图，别让页面停在
      // 黑屏上只有一条 toast。
      if (!playing && duration <= Duration.zero) {
        var msg = '[libmpv · ${_isHls ? '转码' : '直连'}] $raw';
        if (_lastAvError.isNotEmpty) {
          msg += '\n[此前 AVPlayer 也失败] $_lastAvError';
        }
        loading = false;
        error = msg;
        _notify();
      }
    });

    audioTracks = player.state.tracks.audio;
    subtitleTracks = player.state.tracks.subtitle;
    currentAudio = player.state.track.audio;
    currentSubtitle = player.state.track.subtitle;
    baseVolume = player.state.volume.clamp(0, 100);
    volume = (baseVolume * audioGain).clamp(0, 1000);
    videoWidth = player.state.width ?? 0;
    videoHeight = player.state.height ?? 0;
  }

  // ------------------------------------------------------------ AVPlayer 路径

  /// 起播看门狗。AVPlayer 对「服务端转码还没拉起来」容忍度很差：
  /// Emby 拉 FFmpeg 要几秒，期间 master.m3u8 可能 404/503，mpv 会耐心
  /// 重试清单，AVPlayer 直接报错放弃。这就是「Emby 播放老连接不上」的
  /// 主因（错误又从不透传，用户只看到无限转圈）。
  Timer? _avWatchdog;
  int _avRetries = 0;
  int? _avStartAt;

  Future<void> _openAv(int startAt) async {
    final engine = AvPlayerEngine();
    try {
      await engine.create();
    } catch (_) {
      loading = false;
      error = 'AVPlayer 初始化失败，可在串流设置里把内核切回 mpv';
      _notify();
      return;
    }
    if (_disposed) {
      await engine.dispose();
      return;
    }
    _av = engine;
    _avCompletedHandled = false;
    _avCues = const [];
    avSubtitleText = '';
    _avRetries = 0;
    _avStartAt = startAt;
    engine.addListener(_onAvChanged);
    await _avDoOpen(engine);
    if (_disposed) return;
    loading = false;
    _notify();

    unawaited(_applyDefaultSubtitle());
    unawaited(_reportStart());
    unawaited(_logWatch());
    _startProgressTimer();
    _scheduleHideControls();
  }

  Future<void> _avDoOpen(AvPlayerEngine engine) async {
    engine.resetError();
    await engine.open(
      _url,
      // HLS 的分片请求会继承这些头，只靠地址上的 api_key 不够。
      headers: {
        'X-Emby-Token': launch.server.accessToken,
        'Authorization': 'MediaBrowser Token="${launch.server.accessToken}"',
      },
    );
    // 续播：此时 duration 多半还是 0，AVPlayer 支持「没就绪先 seek」，
    // 资产加载完会直接落到目标位置。
    if ((_avStartAt ?? 0) > 0) {
      await engine.seek(Duration(seconds: _avStartAt!));
    }
    _armAvWatchdog();
  }

  /// 起播看门狗：25 秒内没等到时长就视为连接失败，走重试 / 回退。
  void _armAvWatchdog() {
    _avWatchdog?.cancel();
    // 12 秒足够服务端拉起转码（正常 2~5 秒）；再久基本就是流本身有问题，
    // 磨蹭只会让用户等更久才看到降级。
    _avWatchdog = Timer(const Duration(seconds: 12), () {
      if (_disposed || _av == null) return;
      unawaited(_avConnectFailed('连接超时（服务器 12 秒内没有出流）'));
    });
  }

  void _cancelAvWatchdog() {
    _avWatchdog?.cancel();
    _avWatchdog = null;
  }

  /// AV 起播失败：错误事件驱动的失败等 1 秒重试 1 次（转码拉起慢的场景
  /// 基本就能成）；还不行就整套退掉、自动回退 libmpv 并明确提示——对用户
  /// 来说「能播」比「用哪个内核」重要得多，且降级必须可感知，不能静默。
  Future<void> _avConnectFailed(String message) async {
    _cancelAvWatchdog();
    final engine = _av;
    if (engine == null || _disposed) return;
    _lastAvError = message;
    if (engine.duration > Duration.zero || playing) {
      // 已经出流了，迟到的错误事件不影响正在播的画面。
      return;
    }
    if (_avRetries < 1) {
      _avRetries += 1;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed || _av == null || !identical(_av, engine)) return;
      if (engine.duration > Duration.zero || playing) return;
      await _avDoOpen(engine);
      return;
    }
    // 重试仍失败：整套退掉 AVPlayer，重新解析一遍再播。
    // 不能复用旧地址直接开 mpv——AV 那边反复请求很可能已经把服务端的
    // 转码会话弄死了，旧 master.m3u8 打不开就是「Failed to recognize
    // file format」。重新 resolve 会拿到全新的会话。
    _av = null;
    engine.removeListener(_onAvChanged);
    _avCues = const [];
    avSubtitleText = '';
    await engine.dispose();
    if (_disposed) return;
    _avFallbackUsed = true;
    await _teardownPlayer();
    unawaited(KazumiDialog.showToast(message: 'AVPlayer 播不了这部，已自动切换 libmpv'));
    await _open(_index);
  }

  /// 把 AVPlayer 引擎的状态灌进控制器的可观察字段——和 mpv 的
  /// `_attachStreams` 做的是同一件事，只是源从十几条流变成一个 ChangeNotifier。
  void _onAvChanged() {
    final engine = _av;
    if (engine == null || _disposed) return;
    position = engine.position;
    duration = engine.duration;
    buffer = engine.buffer;
    if (playing != engine.playing && engine.playing) {
      _scheduleHideControls();
    }
    playing = engine.playing;
    buffering = engine.buffering;
    if (engine.completed && !_avCompletedHandled) {
      _avCompletedHandled = true;
      completed = true;
      _handleCompleted();
    } else if (!engine.completed) {
      completed = false;
    }
    videoWidth = engine.videoWidth;
    videoHeight = engine.videoHeight;
    audioTracks = [
      // AV 的轨 id 就是 AVMediaSelectionGroup 的下标，select 时原样传回去。
      // 这个 fork 的 AudioTrack 是位置参数（id/title/language）。
      for (final t in engine.audioTracks) AudioTrack(t.id, t.title, t.language),
    ];
    // 面板要高亮「当前音轨」；AVPlayer 默认走第一轨，给它补上标记。
    if (currentAudio == null && audioTracks.isNotEmpty) {
      currentAudio = audioTracks.first;
    }
    // 出流了：连接成功，看门狗可以收队。
    if (engine.duration > Duration.zero && _avWatchdog != null) {
      _cancelAvWatchdog();
    }
    // 引擎报错必须透传——之前这里没接，播放失败时用户看到的是无限转圈。
    if (engine.error.isNotEmpty) {
      final message = engine.error;
      engine.resetError();
      unawaited(_avConnectFailed(message));
    }
    // 内嵌字幕（HLS 里的 mov_text 等）AVPlayerItemVideoOutput 的像素缓冲里
    // 不带渲染结果，列出来也看不了，干脆不进面板；外挂字幕走 _loadAvSubtitle。
    _updateAvSubtitleText();
    _notify();
  }

  void _updateAvSubtitleText() {
    if (_avCues.isEmpty) {
      if (avSubtitleText.isNotEmpty) avSubtitleText = '';
      return;
    }
    final offset = Duration(
      milliseconds: (subtitleSettings.delay * 1000).round(),
    );
    final cue = srtCueAt(_avCues, position - offset);
    final text = cue?.text ?? '';
    if (text != avSubtitleText) avSubtitleText = text;
  }

  /// AV 路径挂字幕：srt/vtt/ass 都让服务器按 `Stream.srt` 交付（服务端会转），
  /// 拉回来在 Dart 里解析、跟着 position 显示。本地导入的文件直接读。
  Future<void> _loadAvSubtitle(SubtitleTrack track) async {
    _avCues = const [];
    avSubtitleText = '';
    currentSubtitle = track;
    _notify();
    try {
      final String raw;
      // uri 轨的地址存在 id 里（SubtitleTrack.uri(url) → id = url）。
      final source = track.id;
      if (source.startsWith('http')) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        final request = await client.getUrl(Uri.parse(source));
        final response = await request.close();
        raw = await response.transform(utf8.decoder).join();
        client.close();
      } else {
        raw = await File(source).readAsString();
      }
      final cues = parseSrt(raw)
          .map(
            (c) => SrtCue(
              start: c.start,
              end: c.end,
              text: sanitizeSubtitleText(c.text),
            ),
          )
          .where((c) => c.text.isNotEmpty)
          .toList();
      if (cues.isEmpty) {
        currentSubtitle = SubtitleTrack.no();
      } else {
        _avCues = cues;
      }
    } catch (_) {
      currentSubtitle = SubtitleTrack.no();
    }
    _notify();
  }

  void _handleCompleted() {
    // 定时「播完当前后停止」。
    if (sleepMode == 1) {
      sleepMode = 0;
      sleepRemaining = 0;
      _cancelSleepTimer();
      unawaited(togglePlay().then((_) => playback.mediaPlayer?.pause()));
      _notify();
      return;
    }
    if (_autoAdvanced) return;
    _autoAdvanced = true;
    final target = _nextIndexForMode();
    if (target == null) return;
    // 片尾自动连播。留两秒，让用户来得及按返回。
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      unawaited(openIndex(target));
    });
  }

  /// 按当前播放模式算出「播完后该去哪一条」，返回 null 表示停下。
  int? _nextIndexForMode() {
    switch (playbackMode) {
      case EmbyPlaybackMode.single:
        return null;
      case EmbyPlaybackMode.singleLoop:
        return _index;
      case EmbyPlaybackMode.order:
      case EmbyPlaybackMode.playlistLoop:
        if (hasNext) return _index + 1;
        // 顺序播到末尾：列表循环回头，其余停下。
        return playbackMode == EmbyPlaybackMode.playlistLoop &&
                launch.episodes.length > 1
            ? 0
            : null;
      case EmbyPlaybackMode.shuffle:
        if (launch.episodes.length <= 1) return null;
        int pick = _index;
        while (pick == _index) {
          pick = (_rng.nextInt(launch.episodes.length));
        }
        return pick;
    }
  }

  final _rng = Random();

  // ------------------------------------------------------------ 控制

  Future<void> togglePlay() async {
    // AV 路径。
    final engine = _av;
    if (engine != null) {
      final bool wasPlaying = playing;
      playing = !wasPlaying;
      _notify();
      if (wasPlaying) {
        await engine.pause();
      } else {
        if (engine.completed) {
          await engine.seek(Duration.zero);
        }
        await engine.play();
      }
      return;
    }
    final player = playback.mediaPlayer;
    if (player == null) return;
    final bool wasPlaying = player.state.playing;
    // 先翻转再等引擎：mpv / ExoPlayer 的状态回流要一两帧，不乐观更新的话
    // 手指按下去图标不动，等回来才跳，就是那种「点了没反应」的滞涩感。
    // 真值由 player.stream.playing 随后覆盖，播放失败也会被纠正回来。
    playing = !wasPlaying;
    _notify();
    if (wasPlaying) {
      await player.pause();
    } else {
      // 播完了再点播放，从这一条的开头重来。
      if (player.state.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
  }

  Future<void> seek(Duration target, {bool user = true}) async {
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    position = clamped;
    _notify();
    if (user) _lastUserSeek = DateTime.now();
    // AV 路径：AVPlayer 对 HLS seek 本来就稳（等切片是原生行为），
    // 不需要 mpv 那套落点校验 + 会话重建。
    final engine = _av;
    if (engine != null) {
      await engine.seek(clamped);
      return;
    }
    final player = playback.mediaPlayer;
    if (player == null) return;
    await player.seek(clamped);
    // 转码（HLS）的流向前 seek 可能落到「还没转出来的切片」上，mpv 会静默
    // 失败——用户看到的就是「快进没反应」。落点校验一次：没到位就重试，
    // 还不行就重建转码会话直接落到目标位置。
    if (duration > Duration.zero && !_reopenGuard) {
      unawaited(_verifySeek(clamped));
    }
  }

  /// seek 之后检查位置是否真的过去了。
  Future<void> _verifySeek(Duration target) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_disposed || !playing) return;
    if ((position - target).abs() <= const Duration(milliseconds: 900)) return;
    final player = playback.mediaPlayer;
    if (player == null) return;
    await player.seek(target);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_disposed) return;
    if ((position - target).abs() <= const Duration(milliseconds: 1200)) return;
    if (_isHls) unawaited(_reopenAt(target));
  }

  /// 重新打开当前流并直接落到 [target]。
  ///
  /// master.m3u8 是动态清单，重开一次就带着新的播放窗口；先 open 再 seek，
  /// mpv 会等切片就绪。开着播放状态恢复，别让用户看到「点了快进，画面从头
  /// 加载然后停住」。
  Future<void> _reopenAt(Duration target) async {
    final player = playback.mediaPlayer;
    final url = _url;
    if (player == null || url.isEmpty) return;
    final wasPlaying = playing;
    _reopenGuard = true;
    try {
      await player.open(Media(url));
      await player.seek(target);
      if (wasPlaying) await player.play();
    } catch (_) {
      // 重建失败就维持现状，别为了一个 seek 把整个播放器搞崩。
    } finally {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 4), () {
          _reopenGuard = false;
        }),
      );
    }
  }

  Future<void> seekBy(Duration delta) => seek(position + delta);

  Future<void> setSpeed(double value) async {
    final engine = _av;
    if (engine != null) {
      await engine.setRate(value);
      speed = value;
      _notify();
      return;
    }
    final player = playback.mediaPlayer;
    if (player == null) return;
    await player.setRate(value);
  }

  /// 设置用户音量（滑杆值，不含增益），0~100。
  Future<void> setVolume(double value) async {
    baseVolume = value.clamp(0, 100);
    await _applyVolume();
  }

  /// 音频增强倍率：1=关闭，1.5/3/5/10 对应 150%/300%/500%/1000%。
  Future<void> setAudioGain(double gain) async {
    audioGain = gain;
    await _applyVolume();
  }

  /// 实际送给播放器的音量 = 用户音量 × 增益。桌面端 MPV 允许 >100 实现放大，
  /// 移动端会被 ExoPlayer 截到 100（增益上限受平台限制）。
  Future<void> _applyVolume() async {
    volume = (baseVolume * audioGain).clamp(0, 1000);
    final engine = _av;
    if (engine != null) {
      // AVPlayer 音量上限 1.0，增益放大在移动端本来就受限。
      await engine.setVolume(volume / 100);
    } else {
      final player = playback.mediaPlayer;
      if (player != null) await player.setVolume(volume);
    }
    _notify();
  }

  /// 音量增减（键盘 / 手势用）。
  Future<void> nudgeVolume(double delta) => setVolume(baseVolume + delta);

  /// 锁定 / 解锁控制层。锁定后点击画面不会唤出控件，避免误触。
  void toggleLock() {
    locked = !locked;
    if (locked) {
      controlsVisible = false;
      _hideTimer?.cancel();
    }
    _notify();
  }

  Future<void> selectAudio(AudioTrack track) async {
    final engine = _av;
    if (engine != null) {
      await engine.selectAudioTrack(track.id);
      currentAudio = track;
      _notify();
      return;
    }
    final player = playback.mediaPlayer;
    if (player == null) return;
    await player.setAudioTrack(track);
  }

  Future<void> selectSubtitle(SubtitleTrack track) async {
    // AV 路径：'no' 清空；其余都是 uri 轨，拉文本自己渲染。
    final engine = _av;
    if (engine != null) {
      if (track.id == 'no') {
        _avCues = const [];
        avSubtitleText = '';
        currentSubtitle = SubtitleTrack.no();
        _notify();
        return;
      }
      // 用户手动挑了一条，就把他之前的「永久禁用」解开。
      final item = current;
      if (item != null && EmbyStreamPrefs.isSubtitleDisabled(item.id)) {
        unawaited(EmbyStreamPrefs.setSubtitleDisabled(item.id, false));
      }
      await _loadAvSubtitle(track);
      return;
    }
    final player = playback.mediaPlayer;
    if (player == null) return;
    // 用户手动挑了一条，就把他之前的「永久禁用」解开——不然下一集又自动关掉，
    // 用户会觉得这个开关管不住。
    if (track.id != 'no') {
      final item = current;
      if (item != null && EmbyStreamPrefs.isSubtitleDisabled(item.id)) {
        unawaited(EmbyStreamPrefs.setSubtitleDisabled(item.id, false));
      }
    }
    // 服务器字幕不直接喂给 mpv：先拉下来过滤掉翻译插件留下的「[翻译失败]」
    // 占位行，再从本地文件挂载。字幕翻译是服务器插件干的，app 不做翻译，
    // 但那些没翻出来的调试行也不该上屏。
    var finalTrack = track;
    if (track.uri && track.id.startsWith('http')) {
      final local = await _prepareSanitizedSubtitleFile(track.id);
      if (_disposed) return;
      if (local != null) {
        finalTrack = SubtitleTrack.uri(
          local,
          title: track.title,
          language: track.language,
        );
      }
    }
    await player.setSubtitleTrack(finalTrack);
    // 换轨后把延迟/位置/缩放再写一遍：mpv 对「新挂上的外部字幕」不保证
    // 继承上一轨的这几项，用户会看到调好的位置突然跳回底部。
    _applySubtitleSettings();
  }

  /// 起播时按偏好自动挂一条字幕。
  ///
  /// 挑哪一条的逻辑在 [pickDefaultSubtitleIndex]，这里只负责落地。
  Future<void> _applyDefaultSubtitle() async {
    if (_disposed || embySubtitleTracks.isEmpty) return;
    final item = current;
    if (item == null) return;
    if (EmbyStreamPrefs.isSubtitleDisabled(item.id)) {
      await selectSubtitle(SubtitleTrack.no());
      return;
    }
    final pick = pickDefaultSubtitleIndex(
      streams: embySubtitleStreams,
      preferredLanguage: EmbyStreamPrefs.subtitleLanguage,
    );
    if (pick == null || pick >= embySubtitleTracks.length) return;
    await selectSubtitle(embySubtitleTracks[pick]);
  }

  /// 「永久禁用」：这一集以后打开不再自动挂字幕。
  Future<void> disableSubtitleForever() async {
    final item = current;
    if (item != null) await EmbyStreamPrefs.setSubtitleDisabled(item.id, true);
    await selectSubtitle(SubtitleTrack.no());
    _notify();
  }

  /// 本地导入字幕文件（srt / ass / vtt…），立刻挂上。
  Future<bool> importSubtitle(String path, {String? title}) async {
    if (path.isEmpty) return false;
    final label = (title == null || title.trim().isEmpty)
        ? path.split(RegExp(r'[\\/]')).last
        : title;
    // AV 路径：读文件 → 解析 → Dart 层渲染。ass 的排版指令会被剥掉，
    // 留纯文本。
    if (_av != null) {
      try {
        final cues = parseSrt(await File(path).readAsString());
        if (cues.isEmpty) return false;
        final track = SubtitleTrack.uri(path, title: label);
        importedSubtitleTracks = [...importedSubtitleTracks, track];
        _avCues = cues;
        avSubtitleText = '';
        currentSubtitle = track;
        _notify();
        return true;
      } catch (_) {
        return false;
      }
    }
    final player = playback.mediaPlayer;
    if (player == null) return false;
    // 导入的文件同样过一遍占位行过滤（有些下载来的双语字幕也是机器翻译的）。
    var sourcePath = path;
    try {
      final cleaned = sanitizeSubtitleFile(await File(path).readAsString());
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/import_sub_${DateTime.now().millisecondsSinceEpoch}.srt',
      );
      await file.writeAsString(cleaned, flush: true);
      sourcePath = file.path;
    } catch (_) {
      // 读不了就按原文件挂，别因为净化失败让导入整个失败。
    }
    final track = SubtitleTrack.uri(sourcePath, title: label);
    importedSubtitleTracks = [...importedSubtitleTracks, track];
    await player.setSubtitleTrack(track);
    _notify();
    return true;
  }

  /// 字幕搜索：问服务端有哪些字幕可下（服务器上要配好 OpenSubtitles 之类的插件）。
  Future<List<EmbyRemoteSubtitle>> searchRemoteSubtitles(
    String language,
  ) async {
    final item = current;
    if (item == null) return const [];
    return _client.searchRemoteSubtitles(
      itemId: item.id,
      language: language.isEmpty ? 'chi' : language,
    );
  }

  /// 关键词字幕搜索：剧名/季/集/片名随便组合，服务端模糊查。
  /// 整页搜索页用这个，旧的按条目搜索保留给兼容路径。
  Future<List<EmbyRemoteSubtitle>> searchRemoteSubtitlesByQuery({
    required String language,
    String? seriesName,
    int? season,
    int? episode,
    String? name,
  }) {
    return _client.searchRemoteSubtitlesByQuery(
      language: language,
      seriesName: seriesName,
      season: season,
      episode: episode,
      name: name,
    );
  }

  /// 下载选中的字幕，并把新轨道列进面板、直接挂上。
  Future<bool> applyRemoteSubtitle(EmbyRemoteSubtitle subtitle) async {
    final item = current;
    if (item == null) return false;
    await _client.downloadRemoteSubtitle(
      itemId: item.id,
      subtitleId: subtitle.id,
    );
    // 服务端把文件挂到媒体源之后，重新问一次才有新轨道。
    final source = await _client.fetchItemMediaSource(
      itemId: item.id,
      userId: launch.server.userId,
    );
    if (source == null || source.subtitleStreams.isEmpty) return false;
    embySubtitleStreams = source.subtitleStreams;
    embySubtitleTracks = _buildSubtitleTracks(item.id, embySubtitleStreams);
    _notify();
    // 新下的那条排在最后，直接选中它——用户点「下载」就是想看它。
    await selectSubtitle(embySubtitleTracks.last);
    return true;
  }

  List<SubtitleTrack> _buildSubtitleTracks(
    String itemId,
    List<EmbyMediaStream> streams,
  ) => [
    // codec 一律传空 → 服务器按 Stream.srt 交付：mpv 这边本来就只吃文本
    // 字幕（libass=false），AV 路径的 Dart 解析器也只认 srt，原生 ass 反而
    // 两边都用不上，还得靠服务端转。
    for (final s in streams)
      SubtitleTrack.uri(
        embySubtitleUrl(
          serverUrl: launch.server.url,
          itemId: itemId,
          index: s.index,
          mediaSourceId: _mediaSourceId,
          codec: null,
          accessToken: launch.server.accessToken,
        ),
        title: s.label,
        language: s.language.isEmpty ? null : s.language,
      ),
  ];

  /// 拉服务器字幕 → 过滤占位行 → 写临时文件，返回本地路径。
  /// 失败返回 null（调用方退回原始 uri：宁可显示带垃圾行，也别没字幕）。
  Future<String?> _prepareSanitizedSubtitleFile(String url) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      client.close();
      final cleaned = sanitizeSubtitleFile(raw);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/emby_sub_${url.hashCode.abs()}.srt');
      await file.writeAsString(cleaned, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 副字幕：media_kit 一次只能渲染一路内封字幕，所以副轨只记下来，
  /// 供「双字幕」开关将来做叠加渲染时用，不直接塞给引擎。
  Future<void> selectSecondarySubtitle(SubtitleTrack track) async {
    secondarySubtitle = track.id == 'no' ? null : track;
    _notify();
  }

  Future<void> playNext() async {
    if (!hasNext) return;
    await openIndex(_index + 1);
  }

  Future<void> playPrevious() async {
    if (!hasPrevious) return;
    await openIndex(_index - 1);
  }

  /// 重试当前这一条（出错时界面上的按钮）。
  /// 用户主动重试 = 给完整的一轮机会：降级/回退标记全部清零。
  Future<void> retry() {
    _avFallbackUsed = false;
    _mpvDowngradeTried = false;
    _preferTranscodeRetry = false;
    _lastAvError = '';
    error = '';
    return _open(_index);
  }

  // ------------------------------------------------------------ 播放设置

  void setPlaybackMode(EmbyPlaybackMode mode) {
    playbackMode = mode;
    _notify();
  }

  void setDecodeMode(EmbyDecodeMode mode) {
    decodeMode = mode;
    _notify();
  }

  void setProgressAlwaysVisible(bool value) {
    progressAlwaysVisible = value;
    if (value) {
      _hideTimer?.cancel();
      controlsVisible = true;
    } else {
      _scheduleHideControls();
    }
    _notify();
  }

  void setBackgroundAudio(bool value) {
    backgroundAudio = value;
    _notify();
  }

  void setSubtitleSettings(EmbySubtitleSettings next) {
    subtitleSettings = next;
    _applySubtitleSettings();
    _notify();
  }

  /// 把「字幕设置」落到引擎上。
  ///
  /// 注意分工（这是之前「怎么改都没用」的根源）：
  /// media_kit 这个分支默认 `libass = false`，mpv 只负责解码，字幕是由
  /// media_kit 的 Flutter `SubtitleView` 画出来的。所以
  ///   · 时间轴（延迟）→ 写 mpv 的 `sub-delay`，会改变 `sub-text` 的时序；
  ///   · 字号 / 位置 / 透明度 → **必须**走 `SubtitleViewConfiguration`，
  ///     在 `emby_player_page.dart` 里的 `_subtitleViewConfig()` 现算。
  /// 以前把后三项也写进 mpv（还包含根本不存在的 `sub-opacity`），自然是
  /// 石沉大海，用户看到的就是「面板在动、画面不变」。
  void _applySubtitleSettings() {
    // mpv 的属性只挂在 NativePlayer 上（Web 端没有），所以先判类型。
    final platform = playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return;
    unawaited(
      platform.setProperty(
        'sub-delay',
        subtitleSettings.delay.toStringAsFixed(2),
      ),
    );
  }

  // ------------------------------------------------------------ 片头片尾

  void setIntroSkip(bool value) {
    introSkip = value;
    _notify();
  }

  void setOutroSkip(bool value) {
    outroSkip = value;
    _notify();
  }

  /// 把「当前进度」标记为片尾开始，之后开启「自动跳过片尾」会从此处起跳。
  void markOutroAt(Duration position) {
    _outroUserStart = position;
    outroSkip = true;
    _notify();
  }

  void _maybeSkipIntroOutro(Duration value) {
    if (!playing || duration <= Duration.zero) return;
    // 用户刚主动 seek 过就先别动：跳过逻辑自己再 seek 一次，人只会看到
    // 「快进 / 拖动没反应」。
    final last = _lastUserSeek;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(milliseconds: 1500)) {
      return;
    }
    if (introSkip && _introStart != null && _introEnd != null) {
      if (value >= _introStart! && value < _introEnd!) {
        unawaited(seek(_introEnd!, user: false));
        return;
      }
    }
    if (outroSkip && !_outroSkipped) {
      final outro = _outroUserStart ?? _outroStart;
      if (outro != null && value >= outro) {
        _outroSkipped = true;
        unawaited(
          seek(duration - const Duration(milliseconds: 300), user: false),
        );
      }
    }
  }

  // ------------------------------------------------------------ 定时关闭

  Timer? _sleepTimer;

  /// 0=不启用，1=播完当前后停止，>=5=分钟数。
  void setSleepTimer(int mode) {
    sleepMode = mode;
    _cancelSleepTimer();
    if (mode >= 5) {
      sleepRemaining = mode * 60;
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        sleepRemaining -= 1;
        if (sleepRemaining <= 0) {
          _cancelSleepTimer();
          sleepMode = 0;
          sleepRemaining = 0;
          unawaited(togglePlay().then((_) => playback.mediaPlayer?.pause()));
          _notify();
        } else {
          _notify();
        }
      });
    }
    _notify();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  void setControlsVisible(bool visible) {
    // 锁定状态下只允许「收起」，不允许唤出。
    if (locked && visible) return;
    // 进度条常显时永远保持控件可见。
    if (progressAlwaysVisible && !visible) {
      controlsVisible = true;
      _notify();
      return;
    }
    if (controlsVisible == visible) return;
    controlsVisible = visible;
    if (visible) _scheduleHideControls();
    _notify();
  }

  void toggleControls() => setControlsVisible(!controlsVisible);

  /// 面板（弹出菜单）打开期间：保持控件可见，并且停掉 4 秒自动收起。
  ///
  /// 少了这一步，菜单还开着、底下的按钮已经淡出消失，看着像坏了。
  void pauseAutoHide() {
    _hideTimer?.cancel();
    if (!controlsVisible) {
      controlsVisible = true;
      _notify();
    }
  }

  /// 菜单关掉后重新开始计时。
  void resumeAutoHide() {
    if (locked || progressAlwaysVisible || !controlsVisible) return;
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    if (!playing || progressAlwaysVisible) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed || !playing || progressAlwaysVisible) return;
      setControlsVisible(false);
    });
  }

  // ------------------------------------------------------------ 进度上报

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed || !playing) return;
      unawaited(_reportProgress());
      // 播放列表 / 继续观看要的就是这份本地记录，跟着进度一起刷。
      unawaited(_logWatch());
    });
  }

  /// 把"看过什么、看到哪"记到本地。Emby 条目和本地直链都记。
  Future<void> _logWatch() async {
    final item = current;
    if (item == null) return;
    final server = launch.server;
    final direct = item.directUrl;
    final key = (direct != null && direct.isNotEmpty)
        ? 'src:$direct'
        : 'emby:${server.id}:${item.id}';
    await EmbyWatchLog.instance.put(
      EmbyWatchRecord(
        key: key,
        title: launch.title,
        subtitle: item.isEpisode ? item.name : '',
        itemId: (direct != null && direct.isNotEmpty) ? '' : item.id,
        serverId: server.id,
        serverName: server.name,
        source: direct ?? '',
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        playedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  int get _positionTicks => position.inMicroseconds * 10;

  Future<void> _reportStart() async {
    final item = current;
    final source = _mediaSourceId;
    if (item == null || source == null) return;
    await _client.reportPlaybackStart(
      itemId: item.id,
      mediaSourceId: source,
      positionTicks: _positionTicks,
    );
  }

  Future<void> _reportProgress() async {
    final item = current;
    final source = _mediaSourceId;
    if (item == null || source == null) return;
    await _client.reportPlaybackProgress(
      itemId: item.id,
      mediaSourceId: source,
      positionTicks: _positionTicks,
      isPaused: !playing,
    );
  }

  Future<void> _reportStopped() async {
    final item = current;
    final source = _mediaSourceId;
    if (item == null || source == null) return;
    await _client.reportPlaybackStopped(
      itemId: item.id,
      mediaSourceId: source,
      positionTicks: _positionTicks,
    );
  }

  // ------------------------------------------------------------ 释放

  Future<void> _teardownPlayer() async {
    _progressTimer?.cancel();
    _autoNextTimer?.cancel();
    _cancelSubscriptions();
    _cancelAvWatchdog();
    // AV 路径先退场。
    final engine = _av;
    if (engine != null) {
      _av = null;
      engine.removeListener(_onAvChanged);
      _avCues = const [];
      avSubtitleText = '';
      await _reportStopped();
      await engine.dispose();
      return;
    }
    if (playback.mediaPlayer != null) {
      await _reportStopped();
      await playback.stop();
    }
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _autoNextTimer?.cancel();
    _cancelSleepTimer();
    _cancelSubscriptions();
    final engine = _av;
    _av = null;
    engine?.removeListener(_onAvChanged);
    unawaited(engine?.dispose());
    unawaited(_reportStopped());
    unawaited(playback.stop());
    super.dispose();
  }
}
