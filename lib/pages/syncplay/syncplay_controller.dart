import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/roads/road_module.dart';
import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:XL/request/apis/bangumi_api.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/player/syncplay_client.dart';
import 'package:XL/services/player/syncplay_countdown.dart';
import 'package:XL/services/player/syncplay_endpoint.dart';
import 'package:XL/services/player/syncplay_reaction.dart';
import 'package:XL/services/player/syncplay_recent_room.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/services/storage/storage.dart';

/// 一个服务器的延迟实测结果。
class SyncPlayLatencyResult {
  const SyncPlayLatencyResult({
    required this.endPoint,
    required this.duration,
  });

  final String endPoint;

  /// 握手耗时；null 表示探测失败。
  final Duration? duration;

  bool get reachable => duration != null;

  int get milliseconds => duration?.inMilliseconds ?? -1;
}

/// 一起看页面的会话状态。
enum SyncPlayPhase { lobby, connecting, inRoom }

/// 一起看独立页的状态中心。
///
/// 与播放器里的 [PlayerSyncPlayController] 相互独立：这里的连接只用于
/// 建房 / 加入 / 成员与聊天，选定番剧进入播放时会断开，由播放器接管房间。
class SyncPlayController extends ChangeNotifier {
  SyncPlayController();

  /// 延迟解析插件控制器。
  ///
  /// 不能写成构造参数注入：模块注册阶段会**立即**创建 singleton，此时 Modular
  /// 还没 bootstrap 完成，`inject()` 会抛
  /// `Bad state: inject<PluginsController>(): no Modular app has been bootstrapped yet.`
  /// 导致首帧构建失败、窗口根本不显示。放到真正用到时再取就安全了。
  PluginsController get pluginsController => inject<PluginsController>();

  static final Random _random = Random();

  // ---------------------------------------------------------------- 服务器
  String _endPoint = defaultSyncPlayEndPoint;

  String get endPoint => _endPoint;

  final Map<String, SyncPlayLatencyResult> _latency = {};

  /// 服务器地址 -> 延迟结果。
  Map<String, SyncPlayLatencyResult> get latency =>
      Map.unmodifiable(_latency);

  bool _isProbing = false;

  bool get isProbing => _isProbing;

  // ------------------------------------------------------------------ 会话
  SyncplayClient? _client;
  SyncPlayPhase _phase = SyncPlayPhase.lobby;
  String _room = '';
  String _username = '';
  int _rtt = 0;
  List<SyncPlayUserInfo> _members = const [];
  String? _currentFile;
  final List<SyncPlayChatMessage> _messages = [];
  String? _error;
  Timer? _errorClearTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// 自动重连上限。超过就退回大厅，让用户自己重进 —— 服务器已经挂了的话，
  /// 无限重试只会让人以为卡住了。
  static const int _maxReconnectAttempts = 3;

  /// 进房 / 离房这条动态条源，页面顶部的胶囊监听它。
  ///
  /// 房间里的动作用 [SyncPlayActivity] 表达，跟播放器画面里那条胶囊是同一套
  /// 数据结构，外观也能保持一致。走 ValueNotifier 而不是 notifyListeners：
  /// 只有顶部那条胶囊关心它，不必让整页重建。
  final ValueNotifier<SyncPlayActivity?> activity =
      ValueNotifier<SyncPlayActivity?>(null);

  /// 其他成员发起「开始一起看」时在这里广播，页面据此自动拉起播放器。
  final StreamController<SyncPlayPlayRequest> _playRequestController =
      StreamController<SyncPlayPlayRequest>.broadcast();

  final SyncPlayPlayRequestAssembler _playRequestAssembler =
      SyncPlayPlayRequestAssembler();

  final SyncPlayStickerAssembler _stickerAssembler =
      SyncPlayStickerAssembler();

  Stream<SyncPlayPlayRequest> get playRequests =>
      _playRequestController.stream;

  /// 房主发起开场倒计时时在这里广播秒数，页面据此弹 3-2-1 遮罩。
  final StreamController<int> _countdownController =
      StreamController<int>.broadcast();

  Stream<int> get countdowns => _countdownController.stream;

  /// 本次会话里被屏蔽的成员。只在内存里，退出房间即清空。
  final Set<String> _blocked = <String>{};

  Set<String> get blockedUsers => Set<String>.unmodifiable(_blocked);

  bool isBlocked(String username) => _blocked.contains(username);

  void toggleBlocked(String username) {
    if (username.isEmpty || username == _username) return;
    if (!_blocked.remove(username)) {
      _blocked.add(username);
    }
    notifyListeners();
  }

  /// 房间顶部的置顶公告；null 表示没有。
  ///
  /// 不落盘：公告是「这一场」的事，换个房间就该失效。
  String? _pinnedNotice;
  String _pinnedBy = '';

  String? get pinnedNotice => _pinnedNotice;

  String get pinnedBy => _pinnedBy;

  /// 别人敲你时在这里广播对方的昵称，页面据此弹提示。
  final StreamController<String> _nudgeController =
      StreamController<String>.broadcast();

  Stream<String> get nudges => _nudgeController.stream;

  /// 房主（Syncplay 协议里的 controller）易主时广播：`true` 表示控场权落到了
  /// 你自己头上。页面据此弹一条「你现在是房主」的提示，并开放控场入口。
  ///
  /// 房主离开后服务端会自动把 `isController` 转给下一个人，这边的同步本就由
  /// 房主的播放状态驱动，所以「接管」在协议层是自动发生的 —— 这里只负责让
  /// 用户知道「现在轮到你控场了」。
  final StreamController<bool> _hostTakeoverController =
      StreamController<bool>.broadcast();

  Stream<bool> get hostTakeovers => _hostTakeoverController.stream;

  /// 最近进过的房间，最新在前。
  List<SyncPlayRecentRoom> _recentRooms = const <SyncPlayRecentRoom>[];

  List<SyncPlayRecentRoom> get recentRooms => _recentRooms;

  void loadRecentRooms() {
    _recentRooms = SyncPlayRecentRoom.load();
    notifyListeners();
  }

  void clearRecentRooms() {
    _recentRooms = SyncPlayRecentRoom.clear();
    notifyListeners();
  }

  SyncPlayPhase get phase => _phase;

  bool get hasSession => _client != null;

  bool get isInRoom => _room.isNotEmpty;

  String get room => _room;

  String get username => _username;

  int get rtt => _rtt;

  List<SyncPlayUserInfo> get members => _members;

  /// 当前房主（Syncplay 协议里的 controller）。服务端在 `Set.user` 里给每个人
  /// 标了 `controller.isController`，房主必然是其中之一；拿不到标记时退回名单
  /// 里的第一个人兜底，避免「明明有房主却显示无」的尴尬。
  SyncPlayUserInfo? get host {
    for (final SyncPlayUserInfo member in _members) {
      if (member.isController) return member;
    }
    return _members.isEmpty ? null : _members.first;
  }

  /// 你是不是房主。房主离场、控场权转给你时这条会从 false 翻成 true。
  bool get isHost =>
      _username.isNotEmpty && host?.username == _username;

  /// 当前房主用户名，拿不到标记时退回名单第一个人。用于成员名单刷新前后对比，
  /// 判断房主有没有换人。
  String? _currentHostUsername() {
    for (final SyncPlayUserInfo member in _members) {
      if (member.isController) return member.username;
    }
    return _members.isEmpty ? null : _members.first.username;
  }

  String? get currentFile => _currentFile;

  /// 房间当前在放第几话。服务端推的文件名格式是 `番剧id[集数]`。
  int? get currentEpisode {
    final String? file = _currentFile;
    if (file == null || file.isEmpty) return null;
    final Match? match = RegExp(r'\[(\d+)\]').firstMatch(file);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 当前选好的这部剧一共几话；没选源时返回 null。
  int? get totalEpisodes {
    final List<Road>? roads = _selectedRoads;
    if (roads == null || roads.isEmpty) return null;
    return roads.length;
  }

  List<SyncPlayChatMessage> get messages => List.unmodifiable(_messages);

  String? get error => _error;

  // ------------------------------------------------------------------ 搜索
  String _keyword = '';
  bool _isSearching = false;
  List<BangumiItem> _searchResults = const [];
  BangumiItem? _selected;
  Plugin? _selectedPlugin;
  SearchItem? _selectedSearchItem;
  List<Road>? _selectedRoads;
  String? _sourceHint;
  Timer? _searchDebounce;
  int _searchGeneration = 0;

  String get keyword => _keyword;

  bool get isSearching => _isSearching;

  List<BangumiItem> get searchResults => _searchResults;

  BangumiItem? get selected => _selected;

  /// 已选中的番剧是否已经挑好了具体的播放来源与剧集。
  bool get hasSource =>
      _selectedPlugin != null &&
      _selectedSearchItem != null &&
      _selectedRoads != null;

  /// 已选中的规则源。
  Plugin? get selectedPlugin => _selectedPlugin;

  /// 已选中的条目（某一集 / 某条线路）。
  SearchItem? get selectedSearchItem => _selectedSearchItem;

  /// 已选中的剧集列表。
  List<Road>? get selectedRoads => _selectedRoads;

  String? get sourceHint => _sourceHint;

  // -------------------------------------------------------------- 生命周期
  /// 载入持久化设置；每次进入页面调用一次即可。
  void restore() {
    _endPoint = GStorage.getSetting<String>(SettingsKeys.syncPlayEndPoint);
    if (_endPoint.isEmpty) {
      _endPoint = defaultSyncPlayEndPoint;
    }
    _username = GStorage.getSetting<String>(SettingsKeys.syncPlayUserName);
    if (_username.isEmpty) {
      _username = generateUserName();
    }
    notifyListeners();
  }

  static String generateRoomNumber() =>
      List.generate(8, (_) => _random.nextInt(10)).join();

  static String generateUserName() {
    const String consonants = 'bcdfghjklmnpqrstvwxyz';
    const String vowels = 'aeiou';
    final int syllables = 3 + _random.nextInt(2);
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < syllables; i++) {
      buffer.write(consonants[_random.nextInt(consonants.length)]);
      buffer.write(vowels[_random.nextInt(vowels.length)]);
    }
    final String name = buffer.toString();
    return name[0].toUpperCase() + name.substring(1);
  }

  void setEndPoint(String endPoint) {
    if (_endPoint == endPoint) return;
    _endPoint = endPoint;
    GStorage.putSetting<String>(SettingsKeys.syncPlayEndPoint, endPoint);
    notifyListeners();
  }

  void setUsername(String username) {
    _username = username;
    if (username.isNotEmpty) {
      GStorage.putSetting<String>(SettingsKeys.syncPlayUserName, username);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- 延迟实测
  /// 依次实测 [endPoints]（默认官方列表 + 当前自定义地址）的握手耗时。
  Future<void> probeLatency({List<String>? endPoints}) async {
    if (_isProbing) return;
    final targets = endPoints ?? _defaultProbeTargets();
    _isProbing = true;
    notifyListeners();

    try {
      await Future.wait(targets.map(_probeOne));
    } finally {
      _isProbing = false;
      notifyListeners();
    }
  }

  List<String> _defaultProbeTargets() {
    final targets = officialSyncPlayEndPoints.toList();
    if (!officialSyncPlayEndPoints.contains(_endPoint)) {
      targets.add(_endPoint);
    }
    return targets;
  }

  Future<void> _probeOne(String endPoint) async {
    final parsed = parseSyncPlayEndPoint(endPoint);
    if (parsed == null) {
      _latency[endPoint] = SyncPlayLatencyResult(endPoint: endPoint, duration: null);
      return;
    }
    try {
      final duration = await SyncPlayLatencyProbe().measure(
        host: parsed.host,
        port: parsed.port,
        enableTLS: isOfficialSyncPlayEndPoint(parsed),
      );
      _latency[endPoint] =
          SyncPlayLatencyResult(endPoint: endPoint, duration: duration);
    } catch (e) {
      KazumiLogger()
          .w('SyncPlay: latency probe failed for $endPoint', error: e);
      _latency[endPoint] = SyncPlayLatencyResult(endPoint: endPoint, duration: null);
    }
    if (!_isProbing) {
      notifyListeners();
    }
  }

  /// 选出当前已知延迟最低且可达的服务器。
  String? get fastestEndPoint {
    final reachable = _latency.values.where((e) => e.reachable).toList()
      ..sort((a, b) => a.duration!.compareTo(b.duration!));
    return reachable.isEmpty ? null : reachable.first.endPoint;
  }

  // ---------------------------------------------------------------- 房间
  /// 建立与服务器的连接并加入 [room]。
  ///
  /// 返回是否成功加入；失败时 [error] 会带上原因。
  Future<bool> joinRoom(String room, String username) async {
    await leaveRoom();
    final parsed = parseSyncPlayEndPoint(_endPoint);
    if (parsed == null) {
      _setError('服务器地址不合法：$_endPoint');
      return false;
    }
    if (room.isEmpty) {
      _setError('请输入房间号');
      return false;
    }
    if (username.isEmpty) {
      _setError('请输入昵称');
      return false;
    }

    setUsername(username);
    _phase = SyncPlayPhase.connecting;
    _room = '';
    _rtt = 0;
    _members = const [];
    _currentFile = null;
    _messages.clear();
    _playRequestAssembler.reset();
    _stickerAssembler.reset();
    _setError(null);
    notifyListeners();

    final client = SyncplayClient(host: parsed.host, port: parsed.port);
    _client = client;
    _listen(client);

    try {
      await client.connect(
        enableTLS: isOfficialSyncPlayEndPoint(parsed),
      );
      if (!identical(_client, client)) {
        return false;
      }
      await client.joinRoom(room, username);
      if (!identical(_client, client)) {
        return false;
      }
      _room = room;
      _phase = SyncPlayPhase.inRoom;
      _reconnectAttempt = 0;
      // 进房成功就记一条，下次在大厅能一键重回。
      _recentRooms = SyncPlayRecentRoom.record(
        room: room,
        endPoint: _endPoint,
        title: _selected == null
            ? ''
            : (_selected!.nameCn.isNotEmpty
                ? _selected!.nameCn
                : _selected!.name),
      );
      notifyListeners();
      return true;
    } catch (e) {
      if (!identical(_client, client)) {
        return false;
      }
      final message = e is SyncplayException ? e.message : e.toString();
      KazumiLogger().e('SyncPlay: join room failed', error: e);
      _setError('连接失败：$message');
      await _closeClient();
      _phase = SyncPlayPhase.lobby;
      notifyListeners();
      return false;
    }
  }

  void _listen(SyncplayClient client) {
    client.onGeneralMessage.listen(
      null,
      onError: (Object error) {
        if (!identical(_client, client)) return;
        final message =
            error is SyncplayException ? error.message : error.toString();
        KazumiLogger().e('SyncPlay: session error $message', error: error);
        unawaited(_handleConnectionLost(client, message));
      },
    );
    client.onUserListMessage.listen((users) {
      if (!identical(_client, client)) return;
      // 先记下旧房主，再替换名单，才能判断「房主换人」。
      final String? prevHost = _currentHostUsername();
      _members = users;
      final String? newHost = _currentHostUsername();
      // 房主易主：旧房主离场、服务端把控场权转给新人。若轮到自己，广播一条
      // 让页面弹「你现在是房主」；其余情况静默（名单已经刷新，无需额外提示）。
      if (prevHost != null &&
          newHost != null &&
          prevHost != newHost &&
          newHost == _username &&
          !_hostTakeoverController.isClosed) {
        _hostTakeoverController.add(true);
      }
      notifyListeners();
    });
    client.onFileChangedMessage.listen((message) {
      if (!identical(_client, client)) return;
      _currentFile = message['name']?.toString();
      notifyListeners();
    });
    client.onPositionChangedMessage.listen((message) {
      if (!identical(_client, client)) return;
      final double clientRtt =
          (message['clientRtt'] as num?)?.toDouble() ?? 0.0;
      _rtt = (clientRtt * 1000).toInt();
      notifyListeners();
    });
    client.onChatMessage.listen((message) {
      if (!identical(_client, client)) return;
      final sender = (message['username'] ?? '').toString();
      final text = (message['message'] ?? '').toString();
      // 被屏蔽的人：聊天、反应、倒计时一律吞掉，连「进房」那条系统消息也不留。
      // 屏蔽是本次会话内的临时状态，不落盘 —— 它更像是「先别吵我」而不是黑名单。
      if (sender.isNotEmpty && _blocked.contains(sender)) return;
      final request = SyncPlayPlayRequest.isPlayRequest(text)
          ? _playRequestAssembler.add(sender, text)
          : null;
      if (request != null) {
        // 播放请求是内部信令，不当作聊天内容显示；服务端会回显给发送者，
        // 自己发的那条要跳过，否则会重复拉起播放器。
        if (sender == _username) return;
        final title = request.title.isEmpty ? request.name : request.title;
        _appendMessage(
          SyncPlayChatMessage(
            username: '',
            message: '${sender.isEmpty ? '房间成员' : sender} 开始了《$title》',
            fromRemote: true,
          ),
        );
        if (!_playRequestController.isClosed) {
          _playRequestController.add(request);
        }
        return;
      }
      if (SyncPlayPlayRequest.isPlayRequest(text)) return;
      // 开场倒计时：不进聊天记录，只推给页面弹遮罩。
      final countdown = SyncPlayCountdown.tryParse(text);
      if (countdown != null) {
        if (sender == _username) return;
        if (!_countdownController.isClosed) {
          _countdownController.add(countdown);
        }
        return;
      }
      // 置顶公告：不进聊天正文，钉在房间卡片顶上。
      //
      // 用 isPin 而不是 tryParse 判断：取消置顶发的是一条空公告（`XLP1|`），
      // tryParse 会返回 null，那样它就会掉进下面的普通聊天分支，把协议原文
      // 显示成一条消息。
      if (SyncPlayPin.isPin(text)) {
        final String? body = SyncPlayPin.tryParse(text);
        _pinnedNotice = body;
        _pinnedBy = body == null ? '' : sender;
        notifyListeners();
        return;
      }
      // 敲一敲：只对被敲的人生效，其他人静默。
      final nudged = SyncPlayNudge.tryParse(text);
      if (nudged != null) {
        if (nudged == _username && !_nudgeController.isClosed) {
          _nudgeController.add(sender.isEmpty ? '房间成员' : sender);
        }
        return;
      }
      final reaction = SyncPlayReaction.tryParse(text);
      if (reaction != null) {
        _appendMessage(
          SyncPlayChatMessage(
            username: sender,
            message: reaction,
            fromRemote: true,
            isReaction: true,
          ),
        );
        return;
      }
      if (SyncPlayStickerMessage.isSticker(text)) {
        final SyncPlayStickerMessage? sticker =
            _stickerAssembler.add(sender, text);
        // 分片没收齐就先不显示，免得聊天里冒出一串半截协议。
        if (sticker == null) return;
        _appendMessage(
          SyncPlayChatMessage(
            username: sender,
            message: sticker.encodeSingle(),
            fromRemote: true,
          ),
        );
        return;
      }
      _appendMessage(
        SyncPlayChatMessage(
          username: sender,
          message: text,
          fromRemote: true,
        ),
      );
    });
    client.onRoomMessage.listen((message) {
      if (!identical(_client, client)) return;
      final type = message['type']?.toString();
      final who = message['username']?.toString() ?? '';
      if (type == 'joined' || type == 'left') {
        final bool joined = type == 'joined';
        if (who.isNotEmpty && _blocked.contains(who)) return;
        _appendMessage(
          SyncPlayChatMessage(
            username: '',
            message: joined ? '$who 想你啦~' : '$who 要休息啦~',
            fromRemote: true,
          ),
        );
        // 进房 / 离房在页面顶部弹一条胶囊；聊天里那条系统消息照旧留着，
        // 翻记录时还能看到谁什么时候来过。
        //
        // 人多的时候这条会一直弹，所以给了开关；关掉只影响胶囊，聊天记录
        // 里的系统消息还在。
        if (GStorage.getSetting<bool>(SettingsKeys.syncPlayPresenceNotice)) {
          activity.value = SyncPlayActivity(
            username: who.isEmpty ? '房间成员' : who,
            kind: joined
                ? SyncPlayActivityKind.join
                : SyncPlayActivityKind.leave,
          );
        }
      }
    });
  }

  void _appendMessage(SyncPlayChatMessage message) {
    _messages.add(message);
    if (_messages.length > 200) {
      _messages.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    final client = _client;
    if (trimmed.isEmpty || client == null || !isInRoom) return;
    _appendMessage(
      SyncPlayChatMessage(
        username: _username,
        message: trimmed,
        fromRemote: false,
      ),
    );
    try {
      await client.sendChatMessage(trimmed);
    } catch (e) {
      if (!identical(_client, client)) return;
      _setError('消息发送失败：${e is SyncplayException ? e.message : e}');
    }
  }

  /// 发一张表情包：本地先回显一条，再按 150 字符分片发出去。
  Future<void> sendSticker(SyncPlayStickerMessage sticker) async {
    final client = _client;
    if (client == null || !isInRoom) return;
    _appendMessage(
      SyncPlayChatMessage(
        username: _username,
        message: sticker.encodeSingle(),
        fromRemote: false,
      ),
    );
    try {
      for (final String chunk in sticker.encodeChunks()) {
        await client.sendChatMessage(chunk);
      }
    } catch (e) {
      if (!identical(_client, client)) return;
      _setError('表情发送失败：${e is SyncplayException ? e.message : e}');
    }
  }

  /// 发一个快捷反应：本地先回显，再发一条 `XLR1|<emoji>`。
  Future<void> sendReaction(String emoji) async {
    final client = _client;
    if (client == null || !isInRoom) return;
    _appendMessage(
      SyncPlayChatMessage(
        username: _username,
        message: emoji,
        fromRemote: false,
        isReaction: true,
      ),
    );
    try {
      await client.sendChatMessage(SyncPlayReaction.encode(emoji));
    } catch (e) {
      if (!identical(_client, client)) return;
      _setError('反应发送失败：${e is SyncplayException ? e.message : e}');
    }
  }

  /// 钉一条公告。传空字符串等于取消置顶。
  Future<bool> announcePin(String text) async {
    final client = _client;
    if (client == null || !isInRoom) return false;
    final String trimmed = text.trim();
    try {
      if (trimmed.isEmpty) {
        // 协议里没有「取消」这条消息，用一条空公告表达，收到的一方清掉。
        await client.sendChatMessage(SyncPlayPin.prefix);
        _pinnedNotice = null;
        _pinnedBy = '';
      } else {
        await client.sendChatMessage(SyncPlayPin.encode(trimmed));
        _pinnedNotice = SyncPlayPin.tryParse(SyncPlayPin.encode(trimmed));
        _pinnedBy = _username;
      }
      notifyListeners();
      return true;
    } catch (e) {
      KazumiLogger().w('SyncPlay: announce pin failed', error: e);
      return false;
    }
  }

  /// 敲一下某个成员，提醒他跟上看。
  Future<bool> nudge(String target) async {
    final client = _client;
    if (client == null || !isInRoom) return false;
    if (target.isEmpty || target == _username) return false;
    try {
      await client.sendChatMessage(SyncPlayNudge.encode(target));
      return true;
    } catch (e) {
      KazumiLogger().w('SyncPlay: nudge failed', error: e);
      return false;
    }
  }

  /// 广播开场倒计时，让房间里所有人一起数完再起播。
  Future<bool> announceCountdown(int seconds) async {
    final client = _client;
    if (client == null || !isInRoom) return false;
    try {
      await client.sendChatMessage(SyncPlayCountdown.encode(seconds));
      return true;
    } catch (e) {
      KazumiLogger().w('SyncPlay: announce countdown failed', error: e);
      return false;
    }
  }

  /// 把自己选好的片源广播给房间里其他人，让他们自动拉起播放器。
  ///
  /// 必须在 [leaveRoom] **之前**调用：离开房间会断开连接，消息就发不出去了。
  /// 返回是否成功写进 socket。
  Future<bool> announcePlayback(SyncPlayPlayRequest request) async {
    final client = _client;
    if (client == null || !isInRoom) return false;
    try {
      // 服务器把单条聊天截到 150 字符，必须按分片逐条发。
      for (final chunk in request.encodeChunks()) {
        await client.sendChatMessage(chunk);
      }
      return true;
    } catch (e) {
      KazumiLogger().w('SyncPlay: announce playback failed', error: e);
      return false;
    }
  }

  Future<void> leaveRoom() async {
    _errorClearTimer?.cancel();
    _errorClearTimer = null;
    // 手动退出就不要再连回去了。
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _closeClient();
    _room = '';
    _members = const [];
    _currentFile = null;
    _rtt = 0;
    // 屏蔽名单是会话内的临时状态，人都不在房间里了就没有意义。
    _blocked.clear();
    // 公告也是「这一场」的事，换房间就失效。
    _pinnedNotice = null;
    _pinnedBy = '';
    _playRequestAssembler.reset();
    _stickerAssembler.reset();
    _phase = SyncPlayPhase.lobby;
    notifyListeners();
  }

  Future<void> _closeClient() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    await client.disconnect();
  }

  // ---------------------------------------------------------------- 断线重连
  /// 掉线之后自动重连：指数退避，最多 [_maxReconnectAttempts] 次。
  ///
  /// 不能复用旧客户端：`SyncplayClient.connect` 只允许调一次，断了就是断了，
  /// 所以重连 = 新建一个客户端 + 重新 joinRoom。房间号和昵称都还留着，
  /// 对服务端来说就是「同一个人重新进来」。
  Future<void> _handleConnectionLost(
    SyncplayClient failed,
    String reason,
  ) async {
    if (!identical(_client, failed)) return;
    await _closeClient();
    final String room = _room;
    final String username = _username;
    if (room.isEmpty) {
      _phase = SyncPlayPhase.lobby;
      _setError('同步中断：$reason');
      notifyListeners();
      return;
    }
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _reconnectAttempt = 0;
      _room = '';
      _members = const [];
      _phase = SyncPlayPhase.lobby;
      _setError('同步中断，重试 $_maxReconnectAttempts 次都没连上，请重新进房');
      notifyListeners();
      return;
    }
    _reconnectAttempt++;
    final int attempt = _reconnectAttempt;
    final int delayMs = 600 * (1 << (attempt - 1));
    _setError(
      '连接断开，${(delayMs / 1000).toStringAsFixed(1)} 秒后重连（第 $attempt 次）',
    );
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      // 等待期间用户可能已经退出或换了房间，那就别连回去了。
      if (_room != room) return;
      final parsed = parseSyncPlayEndPoint(_endPoint);
      if (parsed == null) return;
      final client = SyncplayClient(host: parsed.host, port: parsed.port);
      _client = client;
      _listen(client);
      try {
        await client.connect(enableTLS: isOfficialSyncPlayEndPoint(parsed));
        if (!identical(_client, client)) return;
        await client.joinRoom(room, username);
        if (!identical(_client, client)) return;
        _reconnectAttempt = 0;
        _setError(null);
        _appendMessage(
          SyncPlayChatMessage(
            username: '',
            message: '重新连上房间了',
            fromRemote: true,
          ),
        );
        notifyListeners();
      } catch (error) {
        if (!identical(_client, client)) return;
        KazumiLogger().w('SyncPlay: reconnect failed', error: error);
        await _handleConnectionLost(
          client,
          error is SyncplayException ? error.message : error.toString(),
        );
      }
    });
  }

  void _setError(String? message) {
    _error = message;
    if (message != null) {
      _errorClearTimer?.cancel();
      _errorClearTimer = Timer(const Duration(seconds: 6), () {
        _error = null;
        notifyListeners();
      });
    }
  }

  // ---------------------------------------------------------------- 搜索
  void updateKeyword(String keyword) {
    _keyword = keyword;
    notifyListeners();
    _searchDebounce?.cancel();
    if (keyword.trim().isEmpty) {
      _isSearching = false;
      _searchResults = const [];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      await search(keyword);
    });
  }

  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final generation = ++_searchGeneration;
    _isSearching = true;
    notifyListeners();
    try {
      final page = await BangumiApi.bangumiSearch(trimmed, limit: 24);
      if (generation != _searchGeneration) return;
      _searchResults = page?.items ?? const [];
    } catch (e) {
      if (generation != _searchGeneration) return;
      KazumiLogger().e('SyncPlay: bangumi search failed', error: e);
      _searchResults = const [];
      _setError('搜索失败，请检查网络');
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// 记录选中的番剧（尚未挑播放来源）。
  void selectBangumi(BangumiItem item) {
    _selected = item;
    _selectedPlugin = null;
    _selectedSearchItem = null;
    _selectedRoads = null;
    _sourceHint = null;
    notifyListeners();
  }

  /// 记录选中的播放来源与条目。
  void selectSource(
    BangumiItem item,
    Plugin plugin,
    SearchItem searchItem,
    List<Road> roads,
  ) {
    _selected = item;
    _selectedPlugin = plugin;
    _selectedSearchItem = searchItem;
    _selectedRoads = roads;
    _sourceHint = '${plugin.name} · ${searchItem.name}';
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    _selectedPlugin = null;
    _selectedSearchItem = null;
    _selectedRoads = null;
    _sourceHint = null;
    notifyListeners();
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    _keyword = '';
    _searchResults = const [];
    _isSearching = false;
    notifyListeners();
  }

  /// 拼出播放器需要的参数；未挑好来源时返回 null。
  OnlineVideoPlaybackArgs? buildPlaybackArgs() {
    final item = _selected;
    final plugin = _selectedPlugin;
    final searchItem = _selectedSearchItem;
    final roads = _selectedRoads;
    if (item == null || plugin == null || searchItem == null || roads == null) {
      return null;
    }
    return OnlineVideoPlaybackArgs(
      bangumiItem: item,
      plugin: plugin,
      title: searchItem.name,
      src: searchItem.src,
      roads: roads,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _errorClearTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_playRequestController.close());
    unawaited(_countdownController.close());
    unawaited(_nudgeController.close());
    unawaited(_hostTakeoverController.close());
    unawaited(_closeClient());
    activity.dispose();
    super.dispose();
  }
}
