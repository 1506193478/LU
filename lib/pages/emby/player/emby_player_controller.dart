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
import 'package:XL/services/emby/emby_skip_marks.dart';
import 'package:XL/services/emby/emby_stream_resolver.dart';
import 'package:XL/services/emby/emby_stream_prefs.dart';
import 'package:XL/services/emby/emby_subtitle_picker.dart';
import 'package:XL/services/emby/emby_watch_log.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/player/avplayer_engine.dart';
import 'package:XL/services/emby/emby_pip_prefs.dart';
import 'package:XL/services/player/emby_srt.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/subtitle/han_convert.dart';
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

  /// 自动跳过片头 / 片尾（字段声明在「片头片尾」小节，从设置盒读初值）。

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

  /// 进画中画（仅 iOS AVPlayer 内核）：设备支持 + 当前流走 AV 才可用。
  bool get pipAvailable => _av?.pipAvailable ?? false;
  bool get pipActive => _av?.pipActive ?? false;

  /// 画中画意图：用户点了小窗 / 退后台自动触发。mpv 内核时切转码走
  /// AVPlayer，起播后自动进小窗。
  bool _pipIntent = false;

  /// 一次性「强制走 AVPlayer」标记（[requestPip] 的转码切换用），
  /// [_shouldUseAv] 消费后清零。
  bool _forceAvOnce = false;

  /// 进画中画的统一入口（页面层负责「mpv 需要切换内核」的确认弹窗）：
  ///   * AVPlayer 内核 → 直接进小窗；
  ///   * mpv 内核 / 本地文件 → 返回 false，由页面决定提示或走
  ///     [switchToPipByTranscode]。
  Future<bool> requestPip() async {
    if (_disposed || loading) return false;
    final engine = _av;
    if (engine == null) return false;
    final ok = await engine.startPip();
    if (!ok && !_disposed) {
      KazumiDialog.showToast(message: '画中画暂时不可用，请稍后再试');
    }
    return ok;
  }

  /// 当前这条流能不能切转码进画中画（本地文件不行）。
  bool get canSwitchToPip => !_isLocalDirect && _av == null && !loading;

  /// mpv（直连原盘）切转码 → AVPlayer 重开当前进度 → 自动进小窗。
  /// 会中断当前播放几秒，调用前页面必须让用户确认。
  Future<void> switchToPipByTranscode() async {
    if (_disposed || !canSwitchToPip) return;
    _pipIntent = true;
    _forceAvOnce = true;
    _preferTranscodeRetry = true;
    KazumiDialog.showToast(message: '正在切换到画中画播放…');
    await _open(_index);
  }

  /// 退画中画，回到 app 内播放。
  Future<void> stopPip() async {
    await _av?.stopPip();
  }

  List<SrtCue> _avCues = const [];
  bool _avCompletedHandled = false;

  /// 内核偏好：`auto` / `av` / `mpv`（见 [SettingsKeys.embyIosKernel]）。
  ///
  /// 「AVPlayer 优先」在 [_open] 里会跳过直连、强制转码——因为 AVPlayer
  /// 只认 MP4/MOV/HLS 这类它认识的容器，直连原盘（MKV 等）塞给它必死；
  /// 转出来的 HLS（H264/AAC/TS）则 100% 兼容。
  bool _shouldUseAv() {
    if (!Platform.isIOS) return false;
    // 画中画意图触发的一次性强制：转码流 AVPlayer 必然能播。
    if (_forceAvOnce) {
      _forceAvOnce = false;
      return true;
    }
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

  /// 下一次 [_open] 的起播位置（回前台卡死重载时用当前进度，而不是让
  /// 服务端进度把人拽回几秒前）。
  Duration? _resumeOverride;

  /// AVPlayer 最后一次失败的原因。回退 mpv 后如果 mpv 也失败，
  /// 两边原因一起显示——一张截图就能看出坏在哪条路。
  String _lastAvError = '';

  /// 把引擎原始错误压成一行可读的（Exception 壳、堆栈、带 token 的地址都去掉）。
  String _shortError(Object e) {
    var s = e.toString().trim();
    s = s.replaceFirst(
      RegExp(r'^(Exception|PlatformException)\s*\(?.*?:\s*'),
      '',
    );
    // 播放地址里带 api_key，直接甩错误页上既没用又泄露凭据。
    s = s.replaceAll(RegExp(r'api_key=[^&\s]+'), 'api_key=***');
    // 长地址对排查没帮助，压成「主机 + 最后一段路径」。
    s = s.replaceAllMapped(
      RegExp(r'https?://[^\s&]+'),
      (m) {
        final uri = Uri.tryParse(m.group(0)!);
        if (uri == null) return m.group(0)!;
        return '${uri.host}${uri.path}';
      },
    );
    if (s.length > 160) s = '${s.substring(0, 160)}…';
    return s;
  }

  /// 网络类错误的中文说法：这类错误给用户看原始 errno 没有意义。
  static String _networkHint(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('tls') || l.contains('ssl')) {
      return '服务器连接中断（TLS 握手失败，可能是线路不稳）';
    }
    if (l.contains('ffurl_read') || l.contains('tcp:')) {
      return '服务器连接中断（线路不稳或带宽不足）';
    }
    if (l.contains('socket') || l.contains('connection')) {
      return '服务器连接中断';
    }
    return '';
  }

  /// 当前条目解析出的片头 / 片尾位置。
  Duration? _introStart;
  Duration? _introEnd;
  Duration? _outroStart;
  bool _outroSkipped = false;

  /// 用户手动标记的「片尾开始」（在「片头片尾」面板点「标记当前进度为片尾」）。
  Duration? _outroUserStart;

  /// 本次播放会话里用户标过的片头片尾。
  ///
  /// 落盘是异步的（Hive put 不保证立刻可读），而用户经常「标完马上点下一集」。
  /// 这份内存副本保证同一会话内换集一定生效；冷启动后由 [EmbySkipMarks] 兜底。
  final Map<String, EmbySkipMark> _sessionMarks = <String, EmbySkipMark>{};

  /// 上一次「自动跳过」自己发 seek 的时间。
  ///
  /// 跳过窗口里位置每变一次就 seek 一次的话，播放器会被拖成幻灯片——seek
  /// 还没落地，下一帧又发一个。加个冷却，一次跳过只发一脚。
  DateTime? _lastAutoSkip;

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

  /// mpv 内核的当前字幕文本。
  ///
  /// media_kit 把 mpv 的 `sub-text` 和 `secondary-sub-text` 一起塞进
  /// `player.stream.subtitle`（下标 0 是主字幕、1 是副字幕），这里存下来给
  /// 自绘字幕层用。只有走到自绘层（开了简繁转换或挂了副字幕）才会读它。
  String _mpvSubtitleText = '';
  String _mpvSecondaryText = '';

  /// AVPlayer 内核的副字幕：mpv 那套 `secondary-sid` 用不上，改成把字幕拉
  /// 下来解析成时间轴，跟着 position 自己算当前这一句。
  List<SrtCue> _avSecondaryCues = const [];
  String _avSecondaryText = '';

  /// 要不要把 media_kit 自带的字幕层关掉、换成本地自绘的一层。
  ///
  /// 只有两种情况需要：开了简繁转换（要改文本），或者挂了副字幕（要画两行）。
  /// 其余情况仍然走 media_kit 原生那层——不转换、不看双字幕的用户拿到的
  /// 画面和 3.9.55 一模一样，不给「只是打开播放器」的人引入任何变量。
  bool get usesCustomSubtitleLayer =>
      HanConvert.mode != HanConvertMode.off || secondarySubtitle != null;

  /// 主字幕文本（已按用户设置做简繁转换）。
  String get primarySubtitleText =>
      HanConvert.apply(isAvBackend ? avSubtitleText : _mpvSubtitleText);

  /// 副字幕文本（已做简繁转换）。
  String get secondarySubtitleText =>
      HanConvert.apply(isAvBackend ? _avSecondaryText : _mpvSecondaryText);

  /// 切换简繁转换方向。转换是「渲染前改文本」，所以换完立刻整页刷新一次；
  /// 词表是懒加载的，加载完再刷一次，用户不会看到「开了没反应」。
  Future<void> setHanConvertMode(HanConvertMode mode) async {
    await HanConvert.setMode(mode);
    if (_disposed) return;
    _notify();
    // 词表首次加载要读两份资源（几十毫秒），加载完再推一次把文本换掉。
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (_disposed) return;
    _notify();
  }

  Timer? _progressTimer;
  Timer? _hideTimer;
  Timer? _autoNextTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  // ------------------------------------------------------------ 生命周期

  Future<void> start() async {
    // 简繁转换：先把设置读进内存（词表懒加载，不转换就不加载）。
    HanConvert.init();
    await _open(launch.initialIndex);
  }

  /// 切到第 [target] 条。
  Future<void> openIndex(int target) async {
    if (target < 0 || target >= launch.episodes.length) return;
    // 用户主动换集：上一集的降级记录不带走，每集都有完整的一轮机会。
    if (target != _index) {
      _preferTranscodeRetry = false;
      _lastAvError = '';
      _pipIntent = false;
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

  /// 打开第 [target] 条。外面包一层兜底：解析 / 网络异常以前会变成
  /// 未捕获的异步错误，播放器停在转圈上，用户只能退出去重进。
  Future<void> _open(int target) async {
    try {
      await _openUnsafe(target);
    } catch (e, st) {
      KazumiLogger().e(
        'Emby player: open ${launch.episodes[target].id} failed',
        error: e,
        stackTrace: st,
      );
      if (_disposed) return;
      loading = false;
      buffering = false;
      error = _shortError(e);
      _notify();
    }
  }

  Future<void> _openUnsafe(int target) async {
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
      _lastAutoSkip = null;
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
      _lastAutoSkip = null;
      _outroUserStart = null;
      chapters = source?.chapters ?? const [];

      // 用户自己标过的片头片尾优先：服务端一般不给这两项，而「在第一集
      // 标好、第二集就失效」正是没读这份本地记录造成的。
      final mark = _marksFor(item);
      if (mark != null && !mark.isEmpty) {
        _introStart = mark.introStart ?? _introStart;
        _introEnd = mark.introEnd ?? _introEnd;
        _outroStart = mark.outroStart ?? _outroStart;
        _outroUserStart = mark.outroStart;
        KazumiLogger().i(
          'Emby skip marks applied: intro=${_introStart?.inSeconds}'
          '-${_introEnd?.inSeconds} outro=${_outroStart?.inSeconds} '
          'item=${item.id} series=${item.seriesId}',
        );
      }

      // 外挂 / 内封字幕全部做成 URI 轨，选谁就把谁挂到引擎上。
      embySubtitleStreams = [
        for (final s in source?.subtitleStreams ?? const <EmbyMediaStream>[]) s,
      ];
      embySubtitleTracks = _buildSubtitleTracks(item.id, embySubtitleStreams);
      importedSubtitleTracks = const [];
    }

    // 服务端记着上次看到哪，直接接着播。
    //
    // 播放记录页拿到的条目是本地缓存拼的（没有 userData），续播位置只能由
    // 调用方通过 [EmbyPlaybackLaunch.startAt] 递进来；它只对**首集**有效，
    // 换集之后当然要从头播。
    final resume = _resumeOverride ??
        (target == launch.initialIndex ? launch.startAt : null) ??
        item.resumePosition;
    _resumeOverride = null;
    final startAt = resume?.inSeconds ?? 0;

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
    // mpv 的 sub-text / secondary-sub-text。media_kit 已经把两路一起发出来了
    // （[主, 副]），不需要我们再去 observeProperty。
    bind(player.stream.subtitle, (lines) {
      final primary = lines.isEmpty ? '' : lines[0];
      final secondary = lines.length > 1 ? lines[1] : '';
      if (primary == _mpvSubtitleText && secondary == _mpvSecondaryText) return;
      _mpvSubtitleText = primary;
      _mpvSecondaryText = secondary;
      // 自绘层没开的时候这两段文本没人看，别为它触发整页重建。
      if (usesCustomSubtitleLayer) _notify();
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
      // 网络层断连（tcp/tls 读失败、连接被重置、socket 错误）。
      //
      // 直连原盘最怕这个：一个 800MB 的静态文件，拖进度条就是向服务器
      // 重新请求一大段，带宽不够 / 服务端限流时直接断连，mkv 那边还会
      // 判定「文件损坏，重新同步」，画面就彻底停了。这类错误不能等
      // 「开播 12 秒内」那套条件——用户往往是播了几分钟拖进度才踩到。
      final lower = raw.toLowerCase();
      final bool networkBroken =
          lower.contains('ffurl_read') ||
          lower.contains('tcp:') ||
          lower.contains('tls:') ||
          lower.contains('connection') ||
          lower.contains('socket');

      // 直连 + （开播初期 或 网络断连）：自动降级成转码重试一次。
      // 转码出来的是 HLS 分片，能续传、seek 只请求附近分片，比硬啃
      // 原盘文件稳得多。转码流失败不在这降级，走下面的错误显示。
      if (!_mpvDowngradeTried &&
          !_isLocalDirect &&
          !_isHls &&
          (justOpened || networkBroken)) {
        _mpvDowngradeTried = true;
        _preferTranscodeRetry = true;
        // 中途断连的话，从当前进度接着放，别把用户拽回片头。
        if (!justOpened && position > const Duration(seconds: 5)) {
          _resumeOverride = position;
        }
        KazumiLogger().w(
          'EmbyPlayer: ${networkBroken ? '网络断连' : '直连打不开'}，'
          '自动降级转码重试 ($raw)',
        );
        unawaited(_open(_index));
        return;
      }
      // 还没出流就失败：给出带内核/流类型诊断的错误视图，别让页面停在
      // 黑屏上只有一条 toast。
      if (!playing && duration <= Duration.zero) {
        final hint = _networkHint(raw);
        var msg = hint.isEmpty
            ? '[libmpv · ${_isHls ? '转码' : '直连'}] ${raw.isEmpty ? '播放失败' : raw}'
            : '$hint\n[libmpv · ${_isHls ? '转码' : '直连'}] $raw';
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
    // open 重建了 PiP controller，把「自动开启画中画」的设置同步过去。
    unawaited(EmbyPipPrefs.syncToEngine());
    // 画中画意图（mpv 切转码进来）：起播了就进小窗。
    if (_pipIntent && !_disposed) {
      _pipIntent = false;
      unawaited(engine.startPip());
    }
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
    _pipIntent = false;
    await _teardownPlayer();
    KazumiDialog.showToast(message: 'AVPlayer 播不了这部，已自动切换 libmpv');
    await _open(_index);
  }

  /// 把 AVPlayer 引擎的状态灌进控制器的可观察字段——和 mpv 的
  /// `_attachStreams` 做的是同一件事，只是源从十几条流变成一个 ChangeNotifier。
  void _onAvChanged() {
    final engine = _av;
    if (engine == null || _disposed) return;
    position = engine.position;
    // 片头片尾自动跳过在 AV 路径同样要跑（之前只挂在 mpv 的 position 流上，
    // AV 内核下开了开关也永远不会跳）。
    _maybeSkipIntroOutro(position);
    // 总时长优先用 Emby 元数据：转码中的 HLS，AVPlayer 报的 item.duration
    // 是「已生成片段的总和」，会随转码推进变长，进度条比例全程不对。
    // 元数据的 RunTimeTicks 才是影片真实时长。
    final metaDuration = current?.runTime;
    duration = (metaDuration != null && metaDuration > Duration.zero)
        ? metaDuration
        : engine.duration;
    // 预加载进度封顶到总时长（引擎偶尔会把 buffered 报出界）。
    buffer = engine.buffer > duration ? duration : engine.buffer;
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
    // 画中画失败：原生会带原因，直接告诉用户，别让按钮「点了没反应」。
    if (engine.pipError.isNotEmpty) {
      final message = engine.pipError;
      engine.resetPipError();
      KazumiDialog.showToast(message: '画中画启动失败：$message');
    }
    // 内嵌字幕（HLS 里的 mov_text 等）AVPlayerItemVideoOutput 的像素缓冲里
    // 不带渲染结果，列出来也看不了，干脆不进面板；外挂字幕走 _loadAvSubtitle。
    _updateAvSubtitleText();
    _notify();
  }

  void _updateAvSubtitleText() {
    final offset = Duration(
      milliseconds: (subtitleSettings.delay * 1000).round(),
    );
    final primary = _avCues.isEmpty
        ? ''
        : (srtCueAt(_avCues, position - offset)?.text ?? '');
    if (primary != avSubtitleText) avSubtitleText = primary;
    final secondary = _avSecondaryCues.isEmpty
        ? ''
        : (srtCueAt(_avSecondaryCues, position - offset)?.text ?? '');
    if (secondary != _avSecondaryText) _avSecondaryText = secondary;
  }

  /// 拉一份字幕并按时间轴切成 cue。地址可以是 http（Emby 的
  /// `/Stream.srt`）或本地文件路径。失败返回 null，调用方自己决定怎么退化。
  Future<List<SrtCue>?> _fetchSubtitleCues(String source) async {
    try {
      final String raw;
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
      return cues.isEmpty ? null : cues;
    } catch (_) {
      return null;
    }
  }

  /// AV 路径挂字幕：srt/vtt/ass 都让服务器按 `Stream.srt` 交付（服务端会转），
  /// 拉回来在 Dart 里解析、跟着 position 显示。本地导入的文件直接读。
  Future<void> _loadAvSubtitle(SubtitleTrack track) async {
    _avCues = const [];
    avSubtitleText = '';
    currentSubtitle = track;
    _notify();
    final cues = await _fetchSubtitleCues(track.id);
    if (_disposed) return;
    if (cues == null) {
      currentSubtitle = SubtitleTrack.no();
    } else {
      _avCues = cues;
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

  /// 副字幕 —— 也就是「双字幕」的第二路。
  ///
  /// 之前这里只把选中的轨道记在内存里就完事了（注释写的是「等将来做叠加
  /// 渲染」），所以面板上能选、画面上永远只有一路。现在两条内核各走各的路：
  ///
  ///   * mpv：`sub-add` 把外掛轨挂进来（**不带 select 标志**，主字幕不受
  ///     影响），再从 `track-list/N/id` 读回它分到的 sid，写进
  ///     `secondary-sid`。文本由 mpv 自己算，media_kit 已经通过
  ///     `secondary-sub-text` 并进 `stream.subtitle[1]` 了。
  ///   * AVPlayer：mpv 那套完全用不上，把字幕当 srt 拉下来解析成时间轴，
  ///     跟着 position 自己算——和主字幕用的是同一套 `srtCueAt`。
  Future<void> selectSecondarySubtitle(SubtitleTrack track) async {
    if (track.id == 'no') {
      secondarySubtitle = null;
      _avSecondaryCues = const [];
      _avSecondaryText = '';
      _mpvSecondaryText = '';
      await _setSecondarySid('no');
      _notify();
      return;
    }
    secondarySubtitle = track;
    _notify();
    if (_av != null) {
      await _loadAvSecondarySubtitle(track);
      return;
    }
    await _applySecondarySid(track);
  }

  Future<void> _setSecondarySid(String sid) async {
    final platform = playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('secondary-sid', sid);
    } catch (e) {
      KazumiLogger().w('Emby player: set secondary-sid=$sid failed', error: e);
    }
  }

  Future<void> _applySecondarySid(SubtitleTrack track) async {
    final platform = playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return;
    try {
      var sid = track.id;
      if (!RegExp(r'^\d+$').hasMatch(sid)) {
        // 外挂轨（Emby 的字幕地址 / 本地导入的文件）：容器里没有这一条，
        // 必须先 sub-add 让 mpv 认识，才会分配 sid。
        final primary = playback.mediaPlayer?.state.track.subtitle;
        var path = sid;
        if (sid.startsWith('http')) {
          path = await _prepareSanitizedSubtitleFile(sid) ?? sid;
        }
        await platform.command(['sub-add', path]);
        // 不同的 mpv 版本对「sub-add 不带 flags 会不会顺手选中」处理不一致。
        // 万一主字幕被顶掉了，用 sid 直接写回去——重新 setSubtitleTrack 会
        // 再挂一条重复的轨，sid 赋值不会。
        if (primary != null && primary.id != 'no' && primary.id != 'auto') {
          final now = playback.mediaPlayer?.state.track.subtitle;
          if (now == null || now.id != primary.id) {
            await platform.setProperty('sid', primary.id);
          }
        }
        final added = await _lastExternalSubtitleSid(platform);
        if (added == null || added.isEmpty) {
          KazumiLogger().w('Emby player: sub-add succeeded but sid not found');
          return;
        }
        sid = added;
      }
      await platform.setProperty('secondary-sid', sid);
      KazumiLogger().i('Emby player: secondary subtitle sid=$sid');
    } catch (e) {
      KazumiLogger().w('Emby player: apply secondary subtitle failed', error: e);
    }
  }

  /// 读回刚 `sub-add` 进来的那条外挂字幕的 sid。
  ///
  /// 不用 `getProperty('track-list')`：那是 node 属性，取回来是 mpv 自己的
  /// 文本格式（键不带引号），不是 JSON，解析起来只能靠正则凑。逐项读
  /// `track-list/N/xxx` 每个都是标量，稳得多。
  Future<String?> _lastExternalSubtitleSid(NativePlayer platform) async {
    try {
      final count =
          int.tryParse(await platform.getProperty('track-list/count')) ?? 0;
      for (var i = count - 1; i >= 0; i--) {
        final type = await platform.getProperty('track-list/$i/type');
        if (type != 'sub') continue;
        final external = await platform.getProperty('track-list/$i/external');
        if (external != 'yes' && external != 'true') continue;
        final id = await platform.getProperty('track-list/$i/id');
        if (id.isNotEmpty) return id;
      }
    } catch (e) {
      KazumiLogger().w('Emby player: read track-list failed', error: e);
    }
    return null;
  }

  Future<void> _loadAvSecondarySubtitle(SubtitleTrack track) async {
    final cues = await _fetchSubtitleCues(track.id);
    if (_disposed) return;
    _avSecondaryCues = cues ?? const [];
    _avSecondaryText = '';
    _updateAvSubtitleText();
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

  /// 回前台后重建视频解码器。
  ///
  /// iOS 在 App 进后台期间会回收 VideoToolbox 的解码会话，回到前台 mpv
  /// 还拿着这个已经失效的 session 继续解——日志里那一串
  /// `hevc: Failed to decode frame (invalid session, -12903)` /
  /// `vt decoder cb: output image buffer is null` 就是它。表现是画面
  /// 掉帧卡住，持续失败还会把解码队列和内存堆死，最后闪退。
  ///
  /// mpv 不会自己重建失效的 VT 会话，所以把 `hwdec` 切走再切回来：这会让
  /// 它拆掉整条视频解码链重新建，新会话由系统重新签发。切完必须从当前
  /// 位置再 seek 一次，否则解码器停在半个 GOP 上（花屏或一直等帧）。
  Future<void> rebuildDecoderAfterBackground() async {
    // AVPlayer 内核的解码会话由系统托管，不用我们插手。
    if (_av != null || _disposed) return;
    final platform = playback.mediaPlayer?.platform;
    if (platform is! NativePlayer) return;
    // 本来就是软解，没有会失效的硬解会话。
    if (!playback.hAenable) return;
    final hw = playback.hardwareDecoder;
    if (hw.isEmpty || hw == 'no') return;
    try {
      await platform.setProperty('hwdec', 'no');
      // 给 mpv 一点时间真正销毁旧 decoder，再切回去才会重建。
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await platform.setProperty('hwdec', hw);
      if (_disposed) return;
      await seek(position, user: false);
      KazumiLogger().i('Emby player: video decoder rebuilt ($hw)');
    } catch (e) {
      KazumiLogger().w('Emby player: rebuild decoder failed', error: e);
    }
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

  /// 和「我的 → 播放器 → 片头片尾跳过」共用同一个设置键，两处开关同源。
  static const _introSkipKey = SettingKey<bool>(
    'pv.introOutroSkip',
    true,
    group: SettingGroup.emby,
  );
  static const _outroSkipKey = SettingKey<bool>(
    'pv.outroSkip',
    true,
    group: SettingGroup.emby,
  );

  bool introSkip = GStorage.getSetting(_introSkipKey);
  bool outroSkip = GStorage.getSetting(_outroSkipKey);

  void setIntroSkip(bool value) {
    introSkip = value;
    _notify();
    unawaited(GStorage.putSetting(_introSkipKey, value));
  }

  void setOutroSkip(bool value) {
    outroSkip = value;
    _notify();
    unawaited(GStorage.putSetting(_outroSkipKey, value));
  }

  /// 把「当前进度」标记为片头开始，同时写进本剧的持久化标记。
  ///
  /// 片头窗口固定按 90 秒算：每次都重算 end——从上一集继承来的 end 可能
  /// 落在新 start 前面，窗口直接作废，表现就是「标了但不跳」。
  void markIntroAt(Duration position) {
    // 语义是「当前进度 = 片头结束」：用户都是看到正片起来了才点按钮。
    // 以前记成「片头开始 +90 秒」，等于把用户点的位置又往后吞了 90 秒，
    // 就是「标完反而跳错」的直接原因。
    const window = Duration(seconds: 90);
    _introEnd = position;
    _introStart = position > window ? position - window : Duration.zero;
    _outroSkipped = false;
    _lastAutoSkip = null;
    _storeMarks();
    setIntroSkip(true);
  }

  /// 把「当前进度」标记为片尾开始，之后开启「自动跳过片尾」会从此处起跳。
  void markOutroAt(Duration position) {
    _outroStart = position;
    _outroUserStart = position;
    _outroSkipped = false;
    _lastAutoSkip = null;
    _storeMarks();
    setOutroSkip(true);
  }

  /// 有没有标过片头 / 片尾（面板据此显示「清除」）。
  bool get hasIntroMark => _introStart != null && _introEnd != null;
  bool get hasOutroMark => (_outroUserStart ?? _outroStart) != null;

  /// 面板副标题用的可读范围。
  String get introMarkLabel =>
      hasIntroMark ? '${_fmt(_introStart!)} – ${_fmt(_introEnd!)}' : '';
  String get outroMarkLabel {
    final v = _outroUserStart ?? _outroStart;
    return v == null ? '' : '从 ${_fmt(v)} 起';
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 清掉片头标记（标错了用这个，之前只能写不能删）。
  void clearIntroMark() {
    _introStart = null;
    _introEnd = null;
    _lastAutoSkip = null;
    _storeMarks(clearIntro: true);
    _notify();
  }

  /// 清掉片尾标记。
  void clearOutroMark() {
    _outroStart = null;
    _outroUserStart = null;
    _outroSkipped = false;
    _lastAutoSkip = null;
    _storeMarks(clearOutro: true);
    _notify();
  }

  /// 回前台后画面彻底不动时的兜底重载。
  ///
  /// 极少数情况下 VT 会话连重建都救不回来（系统直接把进程的解码能力废了），
  /// 这时只能整条流重新打开。调用方会先观察几秒，确认进度真的不推进才调，
  /// 避免正常缓冲也被判成卡死。
  Future<void> reloadAfterStall() async {
    if (_disposed || loading) return;
    final at = position;
    KazumiLogger().w('Emby player: reload after stall at ${at.inSeconds}s');
    _resumeOverride = at;
    await _open(_index);
  }

  /// 读某个条目的标记：本次会话的内存副本优先，其次本地存储。
  EmbySkipMark? _marksFor(EmbyItem item) {
    final keys = EmbySkipMarks.keysFor(
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      itemId: item.id,
    );
    for (final key in keys) {
      final session = _sessionMarks[key];
      if (session != null && !session.isEmpty) return session;
    }
    return EmbySkipMarks.read(
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      itemId: item.id,
    );
  }

  /// 把当前条目的片头片尾同时写进内存和本地存储（按单集 + 整剧两个键）。
  ///
  /// [clearIntro] / [clearOutro] 为 true 时对应字段会被移除而不是写入——
  /// 标错了必须能撤销，否则每次播到那儿都会往外跳。
  void _storeMarks({bool clearIntro = false, bool clearOutro = false}) {
    final item = current;
    if (item == null) return;
    final mark = EmbySkipMark(
      introStart: clearIntro ? null : _introStart,
      introEnd: clearIntro ? null : _introEnd,
      outroStart: clearOutro ? null : (_outroUserStart ?? _outroStart),
    );
    for (final key in EmbySkipMarks.keysFor(
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      itemId: item.id,
    )) {
      if (mark.isEmpty) {
        _sessionMarks.remove(key);
      } else {
        _sessionMarks[key] = mark;
      }
    }
    if (clearIntro || clearOutro) {
      EmbySkipMarks.clear(
        seriesId: item.seriesId,
        seriesName: item.seriesName,
        itemId: item.id,
        intro: clearIntro,
        outro: clearOutro,
      );
    }
    if (!mark.isEmpty) {
      EmbySkipMarks.write(
        seriesId: item.seriesId,
        seriesName: item.seriesName,
        itemId: item.id,
        introStart: mark.introStart?.inSeconds,
        introEnd: mark.introEnd?.inSeconds,
        outroStart: mark.outroStart?.inSeconds,
      );
    }
    KazumiLogger().i(
      'Emby skip marks saved: intro=${mark.introStart?.inSeconds}'
      '-${mark.introEnd?.inSeconds} outro=${mark.outroStart?.inSeconds} '
      'clearIntro=$clearIntro clearOutro=$clearOutro '
      'item=${item.id} series=${item.seriesId}',
    );
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
    // 自己刚跳过：等播放器把位置搬过去再说，否则会连着发 seek（画面直接
    // 一顿一顿的，倍速下更明显）。
    final auto = _lastAutoSkip;
    if (auto != null &&
        DateTime.now().difference(auto) < const Duration(seconds: 3)) {
      return;
    }
    final introStart = _introStart;
    final introEnd = _introEnd;
    if (introSkip &&
        introStart != null &&
        introEnd != null &&
        introEnd > introStart &&
        value >= introStart &&
        value < introEnd) {
      _lastAutoSkip = DateTime.now();
      unawaited(seek(introEnd, user: false));
      return;
    }
    if (outroSkip && !_outroSkipped) {
      final outro = _outroUserStart ?? _outroStart;
      // 片尾点必须是「影片里」的合法位置：0 或超过总时长（服务端偶尔回
      // 这种脏数据）会让刚起播就跳到结尾。
      if (outro != null &&
          outro > const Duration(seconds: 5) &&
          outro < duration &&
          value >= outro) {
        _outroSkipped = true;
        _lastAutoSkip = DateTime.now();
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
    // 副字幕挂的是「上一集/上一条流」的轨道，换集之后那个 sid 已经失效，
    // 留着只会让 mpv 去 secondary-sid 一个不存在的轨（表现为副字幕消失但
    // 面板仍显示选中）。统一在这里清掉，和主字幕一样每集重新选。
    secondarySubtitle = null;
    _mpvSubtitleText = '';
    _mpvSecondaryText = '';
    _avSecondaryCues = const [];
    _avSecondaryText = '';
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
