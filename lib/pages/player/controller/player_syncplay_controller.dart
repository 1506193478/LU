// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/syncplay_catch_up.dart';
import 'package:XL/services/player/syncplay_pull_request.dart';
import 'package:XL/services/player/syncplay_drift.dart';
import 'package:XL/services/player/syncplay_source_key.dart';
import 'package:XL/services/player/syncplay_reaction.dart';
import 'package:XL/services/player/syncplay_room_prompts.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/services/player/syncplay_avatar_message.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/player/syncplay_client.dart';
import 'package:XL/services/player/syncplay_endpoint.dart';
import 'package:XL/utils/async_session.dart';
import 'package:mobx/mobx.dart';

part 'player_syncplay_controller.g.dart';

class PlayerSyncPlayController = _PlayerSyncPlayController
    with _$PlayerSyncPlayController;

abstract class _PlayerSyncPlayController with Store {
  _PlayerSyncPlayController({
    required this.bangumiId,
    required this.currentEpisode,
    required this.currentRoad,
    required this.playing,
    required this.currentPosition,
    required this.playerPosition,
    required this.duration,
    required this.pause,
    required this.play,
    required this.seek,
    required this.isScrubbing,
    required this.playbackSpeed,
    required this.setPlaybackSpeed,
    required this.followRemoteSeek,
  });

  final int Function() bangumiId;
  final int Function() currentEpisode;
  final int Function() currentRoad;
  final bool Function() playing;
  final Duration Function() currentPosition;
  final Duration Function() playerPosition;
  final Duration Function() duration;
  final Future<void> Function({bool enableSync}) pause;
  final Future<void> Function({bool enableSync}) play;
  final Future<void> Function(Duration duration, {bool enableSync}) seek;

  /// 当前播放倍速 / 改倍速（温和追帧用）。
  final double Function() playbackSpeed;
  final Future<void> Function(double speed) setPlaybackSpeed;

  /// 别人拖动进度条时，我要不要跟着跳。
  ///
  /// 关掉（锁定我的进度）之后只跟播放/暂停，别人跳走我只提示一句；
  /// 偏差超过 [lockedHardSeekMs] 才强制对齐，免得彻底跑偏。
  final bool Function() followRemoteSeek;

  /// 用户正按着进度条拖。
  ///
  /// 拖动期间画面停在预览位置，服务端推下来的位置/暂停状态这时候不该生效，
  /// 否则手指还没松开，进度就被别人（或自己的回声）拽走了。
  final bool Function() isScrubbing;

  /// Set before the socket opens and cleared on teardown, so unlike
  /// [syncplayRoom] it also covers the window where the connection is still
  /// being established.
  @observable
  SyncplayClient? syncplayController;
  final AsyncSessionOwner _connectionSessions = AsyncSessionOwner();
  @observable
  String syncplayRoom = '';
  @observable
  int syncplayClientRtt = 0;

  /// 房间里的完整成员名单，由服务端 `Set.user` 推送。
  @observable
  ObservableList<SyncPlayUserInfo> syncplayMembers = ObservableList.of([]);

  /// 房间聊天记录，供播放器内的聊天面板显示。
  @observable
  ObservableList<SyncPlayChatMessage> chatMessages = ObservableList.of([]);

  /// 房间顶部的置顶公告，空串表示没有。
  @observable
  String pinnedNotice = '';

  /// 房间共享的播放队列（集号，按出现顺序）。
  ///
  /// 用 ValueNotifier 而不是 @observable：加一个 observable 就要重跑
  /// build_runner 生成代码，而这个列表只有房间面板一个消费者，
  /// 和 [activity] 一样走轻量通知就够了。
  final ValueNotifier<List<int>> playQueue =
      ValueNotifier<List<int>>(const <int>[]);

  /// 房间顶部横幅：等我一下 / 投票 / 片源不一致，同一时间只显示一条。
  final ValueNotifier<SyncPlayStallState?> stall =
      ValueNotifier<SyncPlayStallState?>(null);
  final ValueNotifier<SyncPlayVoteState?> vote =
      ValueNotifier<SyncPlayVoteState?>(null);
  final ValueNotifier<SyncPlaySourceMismatch?> sourceMismatch =
      ValueNotifier<SyncPlaySourceMismatch?>(null);

  /// 「等我一下」开始之前我是不是在播。到点只恢复本来在播的人。
  bool _stallWasPlaying = false;
  Timer? _stallTimer;

  /// 投票通过后要换集时用；createRoom 时从参数里接过来。
  Future<void> Function(int episode, {int currentRoad, int offset})?
      _changeEpisode;

  /// 自己这边的片源指纹，进房 / 换集时广播出去。
  SyncPlaySourceInfo? _mySource;

  /// 别人广播过来的片源指纹（按昵称存）。
  final Map<String, SyncPlaySourceInfo> _peerSources =
      <String, SyncPlaySourceInfo>{};

  /// 温和追帧的运行状态。
  Timer? _catchUpTimer;
  double _catchUpBaseSpeed = 1.0;
  double _catchUpAppliedSpeed = 1.0;
  Duration _catchUpTarget = Duration.zero;
  DateTime? _catchUpStartedAt;

  /// 锁定时，偏差超过这个值仍然强制对齐（不然会彻底跑偏）。
  static const int lockedHardSeekMs = 30000;

  /// 上一次「别人跳走了」的提示时间，避免刷屏。
  DateTime? _lastSeekHintAt;

  /// 断线自动重连已经试了几次。
  ///
  /// 不放进 observable：只有重连逻辑自己关心，界面不需要跟着重建。
  int _autoReconnectAttempt = 0;

  /// 自动重连上限。超过就退回「手动重新连接」，免得在一个已经挂掉的服务器上
  /// 无限重试，把播放也拖住。
  static const int _maxAutoReconnectAttempts = 2;

  /// 画面上那条「谁做了什么」的动态条，由 [SyncPlayActivityPill] 监听。
  ///
  /// 不用 mobx observable：这个值只在播放器浮层里用，走 ValueNotifier 不必
  /// 重新跑一遍代码生成，也不会把整棵播放器面板卷进重建。
  final ValueNotifier<SyncPlayActivity?> activity =
      ValueNotifier<SyncPlayActivity?>(null);

  int _activityRevision = 0;

  final SyncPlayStickerAssembler _stickerAssembler =
      SyncPlayStickerAssembler();

  /// 远端成员头像：按用户名索引，存解码后的内存字节。
  ///
  /// SyncPlay 协议不传头像，头像走 Chat 通道上的缩略图协议传过来（`LUSAV1|`）。
  /// 这里故意用 [ValueNotifier] 而不是 MobX observable：改它不需要重新跑
  /// build_runner 生成代码，渲染点用 [ValueListenableBuilder] 局部监听即可。
  final SyncPlayAvatarAssembler _avatarAssembler =
      SyncPlayAvatarAssembler();
  final ValueNotifier<Map<String, Uint8List>> _avatarBytesNotifier =
      ValueNotifier<Map<String, Uint8List>>(const {});

  /// 远端成员的真实头像（解码后的内存字节），按用户名索引。
  ///
  /// 查不到说明对方还没发过、或没设头像，渲染时退回首字色块即可。
  Map<String, Uint8List> get avatarBytes => _avatarBytesNotifier.value;

  /// 上次广播出去的头像内容 + 时间，用来做冷却去重。
  String _lastAvatarB64 = '';
  DateTime? _lastAvatarBroadcastAt;
  static const Duration _avatarBroadcastCooldown = Duration(seconds: 30);

  /// 让渲染点局部监听头像变化的通知器。
  ValueNotifier<Map<String, Uint8List>> get avatarBytesNotifier =>
      _avatarBytesNotifier;

  /// 当前播放内容的信息提供者，由视频页注入（播放器控制器不持有
  /// videoPageController，拿不到完整的番剧 / 片源信息）。
  ///
  /// 房间里有人点「拉取正在播放」时用它构造定向播放请求回给他。
  /// 返回 null（离线 / Emby 播放等没有可分享的片源）就当作没听见。
  /// 视频页 dispose 时必须置回 null，闭包里抓着的是页面状态。
  SyncPlayPlayRequest? Function()? currentPlayRequestProvider;

  /// 上次响应「求同步」的时间，冷却去重：请求是广播的，房间里有几个人
  /// 在看就有几个人响应；而有人手滑连点按钮时也不该把聊天通道灌满。
  DateTime? _lastPullAnswerAt;
  static const Duration _pullAnswerCooldown = Duration(seconds: 10);

  void _publishActivity(
    SyncPlayActivityKind kind,
    String username, {
    Duration? position,
    int? episode,
  }) {
    activity.value = SyncPlayActivity(
      username: username.isEmpty ? '房间成员' : username,
      kind: kind,
      position: position,
      episode: episode,
      revision: ++_activityRevision,
    );
  }

  bool get hasSession => syncplayController != null;

  /// 自己的进度，供房间面板算偏差。
  Duration get selfPosition => playerPosition();

  /// 自己的片源标记，格式和发给服务端的 fileName 一致：`番剧id[集数]`。
  String get selfFileTag => '${bangumiId()}[${currentEpisode()}]';

  /// 自己和房间里其他人的进度差；正数表示自己落后。房间里只有自己时返回 null。
  Duration? get driftBehind {
    final String self = syncplayController?.username ?? '';
    return syncPlayDriftBehind(
      self: playerPosition(),
      othersSeconds: <double?>[
        for (final SyncPlayUserInfo member in syncplayMembers)
          if (member.username != self) member.position,
      ],
    );
  }

  /// 房间里有人正在看别的番 / 别的集。
  ///
  /// 文件名里带的是 `番剧id[集数]`，两边不一致就说明各放各的 —— 这时候画面
  /// 还在同步，但内容对不上，比不同步更让人困惑，必须明确提示。
  bool get hasSourceMismatch {
    final String self = syncplayController?.username ?? '';
    final String mine = selfFileTag;
    for (final SyncPlayUserInfo member in syncplayMembers) {
      if (member.username == self) continue;
      // 归一化之后再比：直接比字符串的话，混进一个官方 Syncplay 客户端
      // （它传的是真实文件名）就会一直误报，换个清晰度也会误报。
      if (syncPlaySourcesDiffer(mine, member.fileName)) return true;
    }
    return false;
  }

  final StreamController<SyncPlayChatMessage> _chatStreamController =
      StreamController<SyncPlayChatMessage>.broadcast();

  Stream<SyncPlayChatMessage> get chatStream => _chatStreamController.stream;

  void emitChatMessage({
    required String username,
    required String message,
    required bool fromRemote,
  }) {
    if (_chatStreamController.isClosed) {
      return;
    }
    _chatStreamController.add(SyncPlayChatMessage(
      username: username,
      message: message,
      fromRemote: fromRemote,
    ));
  }

  Future<void> createRoom(
      String room,
      String username,
      Future<void> Function(int episode, {int currentRoad, int offset})
          changeEpisode) async {
    if (_connectionSessions.isClosed) {
      return;
    }
    // 投票换集要用；断线重连会再进来一次，直接覆盖成同一份。
    _changeEpisode = changeEpisode;
    final session = _connectionSessions.begin();
    final previousClient = syncplayController;
    // 同一个房间重连（断线自动重连）时保留聊天记录，只有换房间才清空。
    final String previousRoom = syncplayRoom;
    syncplayController = null;
    syncplayRoom = '';
    syncplayClientRtt = 0;
    syncplayMembers = ObservableList.of([]);
    _avatarAssembler.reset();
    _avatarBytesNotifier.value = const {};
    if (previousRoom != room) {
      chatMessages = ObservableList.of([]);
      // 换房间才清队列：断线重连回来还应该看见原来排的片。
      playQueue.value = const <int>[];
    }
    pinnedNotice = '';
    await previousClient?.disconnect();
    if (session.isStale) {
      return;
    }
    final String syncPlayEndPoint =
        GStorage.getSetting(SettingsKeys.syncPlayEndPoint);
    KazumiLogger().i('SyncPlay: connecting to $syncPlayEndPoint');
    final parsed = parseSyncPlayEndPoint(syncPlayEndPoint);
    if (parsed == null) {
      KazumiDialog.showToast(
        message: 'SyncPlay: 服务器地址不合法 $syncPlayEndPoint',
      );
      KazumiLogger().e('SyncPlay: invalid server address $syncPlayEndPoint');
      return;
    }
    final enableTLS = isOfficialSyncPlayEndPoint(parsed);
    final client = SyncplayClient(host: parsed.host, port: parsed.port);
    syncplayController = client;
    try {
      await client.connect(enableTLS: enableTLS);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      KazumiLogger().i('SyncPlay: connected to ${parsed.host}:${parsed.port}');
      client.onGeneralMessage.listen(
        null,
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final message =
              error is SyncplayException ? error.message : error.toString();
          KazumiLogger().e('SyncPlay: error $message', error: error);
          if (error is SyncplayConnectionException) {
            // 先自己重试几次：网络抖一下就掉房，让用户手动点太粗糙。
            // createRoom 可以重复调用（它会先断开旧客户端），所以重连就是
            // 原样再来一遍，房间号和昵称都还在。
            if (_autoReconnectAttempt < _maxAutoReconnectAttempts &&
                !_connectionSessions.isClosed) {
              _autoReconnectAttempt++;
              final int attempt = _autoReconnectAttempt;
              KazumiDialog.showToast(
                message: 'SyncPlay: 连接断开，正在重连（$attempt/$_maxAutoReconnectAttempts）',
                duration: const Duration(seconds: 3),
              );
              unawaited(
                Future<void>.delayed(Duration(milliseconds: 700 * attempt), () {
                  if (_connectionSessions.isClosed) return;
                  unawaited(createRoom(room, username, changeEpisode));
                }),
              );
              return;
            }
            _autoReconnectAttempt = 0;
            exitRoom();
            KazumiDialog.showToast(
              message: 'SyncPlay: 同步中断 $message',
              duration: const Duration(seconds: 5),
              showActionButton: true,
              actionLabel: '重新连接',
              onActionPressed: () {
                _autoReconnectAttempt = 0;
                createRoom(room, username, changeEpisode);
              },
            );
          }
        },
      );
      client.onRoomMessage.listen(
        (message) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          if (message['type'] == 'init') {
            if (message['username'] == '') {
              KazumiDialog.showToast(
                  message: 'SyncPlay: 您是当前房间中的唯一用户',
                  duration: const Duration(seconds: 5));
              setPlayingBangumi();
            } else {
              KazumiDialog.showToast(
                  message:
                      'SyncPlay: 您不是当前房间中的唯一用户, 当前以用户 ${message['username']} 进度为准');
            }
          }
          if (message['type'] == 'left') {
            final String who = (message['username'] ?? '').toString();
            _publishActivity(SyncPlayActivityKind.leave, who);
            _appendChatMessage(
              SyncPlayChatMessage(
                username: '',
                message: '$who 要休息啦~',
                fromRemote: true,
              ),
            );
          }
          if (message['type'] == 'joined') {
            final String who = (message['username'] ?? '').toString();
            _publishActivity(SyncPlayActivityKind.join, who);
            _appendChatMessage(
              SyncPlayChatMessage(
                username: '',
                message: '$who 想你啦~',
                fromRemote: true,
              ),
            );
            // 有人新进来：自己的头像再广播一次，让他那边也能显示真实头像。
            // 自己进房那条（who == username）已经在 join 后广播过了，跳过。
            if (who != username) {
              unawaited(broadcastAvatar());
            }
          }
        },
      );
      client.onFileChangedMessage.listen(
        (message) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          KazumiLogger().i(
              'SyncPlay: file changed by ${message['setBy']}: ${message['name']}');
          RegExp regExp = RegExp(r'(\d+)\[(\d+)\]');
          Match? match = regExp.firstMatch(message['name']);
          if (match != null) {
            int bangumiID = int.tryParse(match.group(1) ?? '0') ?? 0;
            int episode = int.tryParse(match.group(2) ?? '0') ?? 0;
            if (bangumiID != 0 && episode != 0 && episode != currentEpisode()) {
              // 选集跟暂停/跳转一样走画面上那条动态条，不再用底部 toast：
              // toast 贴在屏幕最下面，一进全屏就被控制条压住。
              _publishActivity(
                SyncPlayActivityKind.episode,
                (message['setBy'] ?? '').toString(),
                episode: episode,
              );
              changeEpisode(episode, currentRoad: currentRoad());
            }
          }
        },
      );
      client.onUserListMessage.listen(
        (users) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          // 房主易主：旧房主离场，服务端把控场权转给下一个人。轮到自己时
          // 必须说一声 —— 否则用户不知道自己现在一暂停、一换集就会带着
          // 全房间一起动。
          final String? previousHost = _currentHostUsername();
          syncplayMembers = ObservableList.of(users);
          final String? currentHost = _currentHostUsername();
          if (previousHost != null &&
              currentHost != null &&
              previousHost != currentHost &&
              currentHost == (client.username ?? '')) {
            _publishActivity(SyncPlayActivityKind.host, previousHost);
            KazumiDialog.showToast(
              message: '房主 $previousHost 离开了，现在由你主持房间',
              duration: const Duration(seconds: 4),
            );
          }
        },
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          KazumiLogger().e('SyncPlay: user list error', error: error);
        },
      );
      client.onChatMessage.listen(
        (message) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final String sender = (message['username'] ?? '').toString();
          final String text = (message['message'] ?? '').toString();
          // 「开始一起看」的广播是内部信令，不要在播放器聊天里显示成一串乱码。
          if (SyncPlayPlayRequest.isPlayRequest(text)) {
            return;
          }
          final bool fromRemote = message['username'] != username;
          // 「求同步」：新加入的成员想要当前播放内容，定向回给他。
          if (SyncPlayPullRequest.isPull(text)) {
            if (fromRemote) {
              unawaited(_answerPullRequest(sender));
            }
            return;
          }
          // 旧版本的开场倒计时信令：遮罩已移除，老版本还可能发它，
          // 静默吞掉，别在播放器聊天里显示成一串协议原文。
          if (text.startsWith('XLC1|')) {
            return;
          }
          // 置顶公告：钉在房间面板顶部，不进聊天正文。
          if (SyncPlayPin.isPin(text)) {
            pinnedNotice = SyncPlayPin.tryParse(text) ?? '';
            return;
          }
          // 播放队列：整份列表覆盖，不进聊天正文。
          if (SyncPlayQueue.isQueue(text)) {
            playQueue.value = SyncPlayQueue.tryParse(text);
            return;
          }
          // 「等我一下」：全房间暂停 N 秒。
          if (SyncPlayStall.isStall(text)) {
            final int? seconds = SyncPlayStall.tryParse(text);
            if (seconds != null && fromRemote) {
              _startStall(sender, seconds);
            }
            return;
          }
          // 投票：每条都是某个人的一个表态，各自本地计票。
          if (SyncPlayVote.isVote(text)) {
            final SyncPlayVoteMessage? message = SyncPlayVote.tryParse(text);
            if (message != null) {
              _onVoteSignal(sender, message);
            }
            return;
          }
          // 片源指纹：只用来提示「你和房主不是同一个源」。
          if (SyncPlaySourceTag.isSourceTag(text)) {
            final SyncPlaySourceInfo? info = SyncPlaySourceTag.tryParse(text);
            if (info != null) {
              _onSourceTag(sender, info);
            }
            return;
          }
          // 敲一敲：只对被敲的人弹提示，其他人静默。
          if (SyncPlayNudge.isNudge(text)) {
            final String? target = SyncPlayNudge.tryParse(text);
            if (target != null && target == username) {
              KazumiDialog.showToast(
                message: '${sender.isEmpty ? '房间成员' : sender} 敲了敲你',
                duration: const Duration(seconds: 3),
              );
            }
            return;
          }
          final String? reaction = SyncPlayReaction.tryParse(text);
          if (reaction != null) {
            _appendChatMessage(
              SyncPlayChatMessage(
                username: sender,
                message: reaction,
                fromRemote: fromRemote,
                isReaction: true,
              ),
            );
            if (_chatStreamController.isClosed) {
              return;
            }
            _chatStreamController.add(SyncPlayChatMessage(
              username: sender,
              message: reaction,
              fromRemote: fromRemote,
              isReaction: true,
            ));
            return;
          }
          // 远端头像：走 Chat 通道的缩略图协议传过来，不在聊天里显示。
          // 分片拼齐后才存进内存，收一半就丢，避免聊天里冒出一串半截协议。
          if (SyncPlayAvatarMessage.isAvatar(text)) {
            final String? full = _avatarAssembler.add(sender, text);
            if (full != null) {
              try {
                final bytes = base64Decode(full);
                final next =
                    Map<String, Uint8List>.from(_avatarBytesNotifier.value);
                next[sender] = bytes;
                _avatarBytesNotifier.value = next;
              } catch (_) {
                // 坏数据忽略，退回首字色块。
              }
            }
            return;
          }
          if (SyncPlayStickerMessage.isSticker(text)) {
            final SyncPlayStickerMessage? sticker =
                _stickerAssembler.add(sender, text);
            // 分片没收齐就先不显示，免得聊天里冒出一串半截协议。
            if (sticker == null) {
              return;
            }
            _appendChatMessage(
              SyncPlayChatMessage(
                username: sender,
                message: sticker.encodeSingle(),
                fromRemote: fromRemote,
              ),
            );
            return;
          }

          _appendChatMessage(
            SyncPlayChatMessage(
              username: sender,
              message: text,
              fromRemote: fromRemote,
            ),
          );
          emitChatMessage(
            username: sender,
            message: text,
            fromRemote: fromRemote,
          );
        },
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final message =
              error is SyncplayException ? error.message : error.toString();
          KazumiLogger().e('SyncPlay: error $message', error: error);
        },
      );
      client.onPositionChangedMessage.listen(
        (message) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          syncplayClientRtt = (message['clientRtt'].toDouble() * 1000).toInt();
          KazumiLogger().i(
              'SyncPlay: position changed by ${message['setBy']}: [${DateTime.now().millisecondsSinceEpoch / 1000.0}] calculatedPosition ${message['calculatedPositon']} position: ${message['position']} doSeek: ${message['doSeek']} paused: ${message['paused']} clientRtt: ${message['clientRtt']} serverRtt: ${message['serverRtt']} fd: ${message['fd']}');
          // 自己发出去的同步请求，服务端会原样广播回来。那份回声里的状态是
          // 「发请求那一刻」的快照，绕一圈回来时本地早就变了：拖动进度条先
          // 暂停、松手立刻恢复，回声里的 paused=true 会把刚恢复的播放又按下去。
          // 自己的状态自己最清楚，这条消息只用来记 RTT。
          final String setBy = (message['setBy'] ?? '').toString();
          if (setBy.isNotEmpty && setBy == (client.username ?? '')) {
            return;
          }
          // 手指还按在进度条上：别让远端状态把预览拽回去，松手后自己会报同步。
          if (isScrubbing()) {
            return;
          }
          if (message['paused'] != !playing()) {
            if (message['paused']) {
              if (message['position'] != 0) {
                _publishActivity(
                  SyncPlayActivityKind.pause,
                  (message['setBy'] ?? '').toString(),
                );
                pause(enableSync: false);
              }
            } else {
              if (message['position'] != 0) {
                _publishActivity(
                  SyncPlayActivityKind.play,
                  (message['setBy'] ?? '').toString(),
                );
                play(enableSync: false);
              }
            }
          }
          if (duration().inMilliseconds > 0) {
            final int targetMs =
                (message['calculatedPositon'].toDouble() * 1000).toInt();
            final Duration target = Duration(milliseconds: targetMs);
            // 正数 = 我落后（房间的位置在我前面）。
            final int driftMs = targetMs - playerPosition().inMilliseconds;
            final bool doSeek = message['doSeek'] == true;

            if (doSeek) {
              _stopCatchUp(restoreSpeed: true);
              _publishActivity(
                SyncPlayActivityKind.seek,
                (message['setBy'] ?? '').toString(),
                position: target,
              );
              if (!followRemoteSeek()) {
                // 锁定了进度：不跟着跳，只提醒一句（带「跟上」按钮）。
                _hintRemoteSeek((message['setBy'] ?? '').toString(), target);
                return;
              }
              seek(target, enableSync: false);
              return;
            }

            // 锁定模式下把「强制对齐」的门槛放宽到 30 秒：
            // 平时各看各的，彻底跑偏了才拉回来。
            final int hardLimit = followRemoteSeek()
                ? SyncPlayCatchUp.hardSeekAboveMs
                : lockedHardSeekMs;
            if (driftMs.abs() > hardLimit) {
              _stopCatchUp(restoreSpeed: true);
              seek(target, enableSync: false);
              return;
            }
            // 1~3 秒的偏差不跳，用倍速悄悄追上。
            if (playing() && SyncPlayCatchUp.needsCatchUp(driftMs)) {
              _beginCatchUp(target, driftMs);
            }
          }
        },
      );
      await client.joinRoom(room, username);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      syncplayRoom = room;
      // 进房成功就广播一次自己的头像；对方据此显示真实头像，而不是首字色块。
      unawaited(broadcastAvatar());
      // 连上了就把重试计数清零，下次断线重新给满额度。
      _autoReconnectAttempt = 0;
      // 进房前就知道自己的片源了（changeEpisode 会先 set），但那时还没有
      // 连接，消息发不出去。这里补发一次，别人才能判断「是不是同一个源」。
      final SyncPlaySourceInfo? mine = _mySource;
      if (mine != null) {
        unawaited(
          _runBestEffortSync(
            () => client.sendChatMessage(
              SyncPlaySourceTag.encode(
                pluginName: mine.pluginName,
                road: mine.road,
                roadName: mine.roadName,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      KazumiLogger().e('SyncPlay: error', error: e);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      syncplayController = null;
      syncplayRoom = '';
      syncplayClientRtt = 0;
      syncplayMembers = ObservableList.of([]);
      chatMessages = ObservableList.of([]);
      pinnedNotice = '';
      await client.disconnect();
      final message = e is SyncplayException ? e.message : e.toString();
      KazumiDialog.showError(
        message: 'SyncPlay: 连接失败 $message',
        duration: const Duration(seconds: 5),
      );
    }
  }

  bool _isCurrentConnection(AsyncSession session, SyncplayClient client) {
    return session.isActive && identical(syncplayController, client);
  }

  void setCurrentPosition({bool? forceSyncPlaying, double? forceSyncPosition}) {
    if (syncplayController == null) {
      return;
    }
    forceSyncPlaying ??= playing();
    syncplayController!.setPaused(!forceSyncPlaying);
    syncplayController!.setPosition((forceSyncPosition ??
        (((currentPosition().inMilliseconds - playerPosition().inMilliseconds)
                    .abs() >
                2000)
            ? currentPosition().inMilliseconds.toDouble() / 1000
            : playerPosition().inMilliseconds.toDouble() / 1000)));
  }

  Future<void> setPlayingBangumi(
      {bool? forceSyncPlaying, double? forceSyncPosition}) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(() async {
      // 之前这里写死 `10800, 220514438`，是占位值：时长永远报 3 小时，
      // 文件大小永远是同一个数。别的客户端拿它算漂移和「是否同一个文件」，
      // 报错了会让对方误判。时长报真实值，大小未知就报 0。
      final int seconds = duration().inSeconds;
      await client.setSyncPlayPlaying(
          "${bangumiId()}[${currentEpisode()}]",
          seconds <= 0 ? 1 : seconds.toDouble(),
          0);
      if (!identical(syncplayController, client)) {
        return;
      }
      setCurrentPosition(
          forceSyncPlaying: forceSyncPlaying,
          forceSyncPosition: forceSyncPosition);
      await client.sendSyncPlaySyncRequest(doSeek: null);
      // 片源真的加载完、进度也广播出去了，才算「就绪」。房主在大厅等这一条，
      // 齐了才一起起播 —— 否则每个人起播差 5~15 秒，第一次对齐只能硬 seek。
      await markReady();
    });
  }

  /// 上报就绪。重复上报无副作用，重连后再报一次也无妨。
  Future<void> markReady() async {
    final client = syncplayController;
    if (client == null) return;
    await _runBestEffortSync(() => client.setReady());
  }

  Future<void> requestSync({bool? doSeek}) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(
        () => client.sendSyncPlaySyncRequest(doSeek: doSeek));
  }

  void _appendChatMessage(SyncPlayChatMessage message) {
    chatMessages.add(message);
    if (chatMessages.length > 200) {
      chatMessages.removeAt(0);
    }
  }

  Future<void> sendChatMessage(String message) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    _appendChatMessage(
      SyncPlayChatMessage(
        username: client.username ?? '',
        message: message,
        fromRemote: false,
      ),
    );
    await _runBestEffortSync(() => client.sendChatMessage(message));
  }

  /// 发一张表情包：本地先回显一条，再按 150 字符分片发出去。
  Future<void> sendSticker(SyncPlayStickerMessage sticker) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    _appendChatMessage(
      SyncPlayChatMessage(
        username: client.username ?? '',
        message: sticker.encodeSingle(),
        fromRemote: false,
      ),
    );
    await _runBestEffortSync(() async {
      for (final String chunk in sticker.encodeChunks()) {
        await client.sendChatMessage(chunk);
      }
    });
  }

  /// 发一个快捷反应。本地先回显，再发一条 `XLR1|<emoji>`。
  Future<void> sendReaction(String emoji) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    final SyncPlayChatMessage local = SyncPlayChatMessage(
      username: client.username ?? '',
      message: emoji,
      fromRemote: false,
      isReaction: true,
    );
    _appendChatMessage(local);
    if (!_chatStreamController.isClosed) {
      _chatStreamController.add(local);
    }
    await _runBestEffortSync(
      () => client.sendChatMessage(SyncPlayReaction.encode(emoji)),
    );
  }

  /// 敲一下某个成员。
  Future<void> nudge(String target) async {
    final client = syncplayController;
    if (client == null) return;
    if (target.isEmpty || target == client.username) return;
    await _runBestEffortSync(
      () => client.sendChatMessage(SyncPlayNudge.encode(target)),
    );
  }

  /// 响应「求同步」：把当前播放的番剧**定向**发给请求者。
  ///
  /// 请求是广播的，房间里有几个人在看就有几个人收到；只有自己真的挂着
  /// 播放内容时才响应，而且带冷却——有人手滑连点按钮时不能把聊天通道
  /// 灌满触发服务端刷屏保护。响应走 [SyncPlayPlayRequest] 的分片协议，
  /// payload 里带 `target`，房间里其他人收到后不会跟着重进播放器。
  Future<void> _answerPullRequest(String requester) async {
    final client = syncplayController;
    if (client == null || syncplayRoom.isEmpty) return;
    final String me = client.username ?? '';
    if (requester.isEmpty || requester == me) return;
    final DateTime? last = _lastPullAnswerAt;
    if (last != null &&
        DateTime.now().difference(last) < _pullAnswerCooldown) {
      return;
    }
    final SyncPlayPlayRequest? current = currentPlayRequestProvider?.call();
    if (current == null) return;
    if (current.src.isEmpty || current.pluginName.isEmpty) return;
    _lastPullAnswerAt = DateTime.now();
    // 定向构造一份带 target 的请求；当前实例本身是广播语义的，不能改。
    final SyncPlayPlayRequest targeted = SyncPlayPlayRequest(
      bangumiId: current.bangumiId,
      name: current.name,
      nameCn: current.nameCn,
      coverUrl: current.coverUrl,
      pluginName: current.pluginName,
      title: current.title,
      src: current.src,
      target: requester,
    );
    final List<String> chunks =
        targeted.encodeChunks(messageId: SyncPlayPlayRequest.randomMessageId());
    await _runBestEffortSync(() async {
      for (final String chunk in chunks) {
        await client.sendChatMessage(chunk);
        await Future<void>.delayed(SyncPlayPlayRequest.chunkInterval);
      }
    });
  }

  /// 把整份播放队列推给房间。
  ///
  /// 本地先改再发：队列是「想法」不是「事实」，网络抖一下不该让界面回滚，
  /// 下一个人再改一次就自然覆盖了。
  Future<void> setPlayQueue(List<int> episodes) async {
    final List<int> next = SyncPlayQueue.normalize(episodes);
    playQueue.value = next;
    final client = syncplayController;
    if (client == null) return;
    await _runBestEffortSync(
      () => client.sendChatMessage(SyncPlayQueue.encode(next)),
    );
  }

  /// 队列里有就去掉，没有就加进去。
  Future<void> toggleQueueEpisode(int episode) {
    final List<int> current = List<int>.of(playQueue.value);
    if (!current.remove(episode)) {
      current.add(episode);
    }
    return setPlayQueue(current);
  }

  /// 当前房主（服务端把控场权标在成员身上）。
  String? _currentHostUsername() {
    for (final SyncPlayUserInfo member in syncplayMembers) {
      if (member.isController) {
        return member.username;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ 温和追帧
  /// 偏差 1~3 秒：不跳，改倍速追上。
  ///
  /// 目标位置会随时间往前走，所以本地自己推算「现在应该在哪」，
  /// 每 500ms 比一次，追上了就把倍速还回去。
  void _beginCatchUp(Duration target, int driftMs) {
    if (_catchUpTimer != null) {
      return;
    }
    _catchUpBaseSpeed = playbackSpeed();
    _catchUpAppliedSpeed = _catchUpBaseSpeed;
    _catchUpTarget = target;
    _catchUpStartedAt = DateTime.now();
    _applyCatchUpSpeed(driftMs);
    _catchUpTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _tickCatchUp(),
    );
  }

  void _applyCatchUpSpeed(int driftMs) {
    final double factor = SyncPlayCatchUp.speedFactor(driftMs);
    final double next = (_catchUpBaseSpeed * factor).clamp(0.25, 4.0);
    if ((next - _catchUpAppliedSpeed).abs() < 0.005) {
      return;
    }
    _catchUpAppliedSpeed = next;
    unawaited(setPlaybackSpeed(next));
  }

  void _tickCatchUp() {
    final DateTime? started = _catchUpStartedAt;
    if (started == null) {
      return;
    }
    if (!playing()) {
      _stopCatchUp(restoreSpeed: true);
      return;
    }
    // 用户自己调过倍速（当前值和「我们设的值」对不上）就让位，别抢回来。
    if ((playbackSpeed() - _catchUpAppliedSpeed).abs() > 0.01) {
      _stopCatchUp(restoreSpeed: false);
      return;
    }
    final Duration elapsed = DateTime.now().difference(started);
    if (elapsed > SyncPlayCatchUp.maxDuration) {
      _stopCatchUp(restoreSpeed: true);
      return;
    }
    final int expected = _catchUpTarget.inMilliseconds + elapsed.inMilliseconds;
    final int driftMs = expected - playerPosition().inMilliseconds;
    if (SyncPlayCatchUp.isDone(driftMs)) {
      _stopCatchUp(restoreSpeed: true);
      return;
    }
    _applyCatchUpSpeed(driftMs);
  }

  void _stopCatchUp({required bool restoreSpeed}) {
    _catchUpTimer?.cancel();
    _catchUpTimer = null;
    _catchUpStartedAt = null;
    if (!restoreSpeed) {
      return;
    }
    // 当前倍速已经被别人改过就别动它。
    if ((playbackSpeed() - _catchUpAppliedSpeed).abs() > 0.01) {
      return;
    }
    if ((_catchUpBaseSpeed - _catchUpAppliedSpeed).abs() < 0.001) {
      return;
    }
    unawaited(setPlaybackSpeed(_catchUpBaseSpeed));
  }

  // ------------------------------------------------------- 「等我一下」
  /// 广播「等我一下」：全房间暂停 N 秒后一起继续。
  Future<void> requestStall([
    int seconds = SyncPlayStall.defaultSeconds,
  ]) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    final int clamped = SyncPlayStall.clampSeconds(seconds);
    _startStall(client.username ?? '', clamped);
    await _runBestEffortSync(
      () => client.sendChatMessage(SyncPlayStall.encode(clamped)),
    );
  }

  void _startStall(String by, int seconds) {
    // 已经在等了就别重复叠加，按新的时长重来。
    _stallTimer?.cancel();
    _stallWasPlaying = playing();
    unawaited(pause(enableSync: false));
    _publishActivity(SyncPlayActivityKind.stall, by);
    stall.value = SyncPlayStallState(by: by, totalSeconds: seconds);
    _stallTimer = Timer(Duration(seconds: seconds), () {
      _finishStall(resume: true);
    });
  }

  /// 提前结束等待（横幅上的「继续」）。
  void cancelStall() => _finishStall(resume: true);

  void _finishStall({required bool resume}) {
    _stallTimer?.cancel();
    _stallTimer = null;
    final bool wasPlaying = _stallWasPlaying;
    _stallWasPlaying = false;
    if (stall.value == null) {
      return;
    }
    stall.value = null;
    if (resume && wasPlaying) {
      unawaited(play(enableSync: false));
    }
  }

  // --------------------------------------------------------------- 投票
  /// 发起一个投票。
  Future<void> startVote(SyncPlayVoteKind kind, {int episode = 0}) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    final SyncPlayVoteState? current = vote.value;
    if (current != null && !current.isExpired) {
      KazumiDialog.showToast(
        message: '已经有一个投票在进行中了',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final String me = client.username ?? '';
    final String id = '$me#${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final SyncPlayVoteState state = SyncPlayVoteState(
      id: id,
      by: me,
      kind: kind,
      value: episode,
    );
    state.yes.add(me);
    vote.value = state;
    _scheduleVoteExpiry(id);
    _publishActivity(
      SyncPlayActivityKind.vote,
      me,
      episode: kind == SyncPlayVoteKind.episode ? episode : null,
    );
    await _runBestEffortSync(
      () => client.sendChatMessage(
        SyncPlayVote.encode(
          id: id,
          kind: kind,
          value: episode,
          stance: 'start',
        ),
      ),
    );
  }

  /// 对当前投票表态。
  Future<void> castVote({required bool agree}) async {
    final client = syncplayController;
    final SyncPlayVoteState? state = vote.value;
    if (client == null || state == null) {
      return;
    }
    final String me = client.username ?? '';
    final SyncPlayVoteState next =
        _withStance(state, me, agree ? 'yes' : 'no');
    vote.value = next;
    await _runBestEffortSync(
      () => client.sendChatMessage(
        SyncPlayVote.encode(
          id: next.id,
          kind: next.kind,
          value: next.value,
          stance: agree ? 'yes' : 'no',
        ),
      ),
    );
    _evaluateVote(next);
  }

  /// 放弃当前投票（发起人或任何人）。
  void dismissVote() {
    _voteTimer?.cancel();
    _voteTimer = null;
    vote.value = null;
  }

  Timer? _voteTimer;

  void _scheduleVoteExpiry(String id) {
    _voteTimer?.cancel();
    _voteTimer = Timer(SyncPlayVote.lifetime, () {
      if (vote.value?.id != id) {
        return;
      }
      vote.value = null;
      KazumiDialog.showError(
        message: '投票超时，没通过',
        duration: const Duration(seconds: 3),
      );
    });
  }

  void _onVoteSignal(String sender, SyncPlayVoteMessage message) {
    SyncPlayVoteState? state = vote.value;
    if (message.stance == 'start') {
      if (state != null && (state.id == message.id || !state.isExpired)) {
        return;
      }
      state = SyncPlayVoteState(
        id: message.id,
        by: sender,
        kind: message.kind,
        value: message.value,
      );
      state.yes.add(sender);
      vote.value = state;
      _scheduleVoteExpiry(message.id);
      _publishActivity(
        SyncPlayActivityKind.vote,
        sender,
        episode:
            message.kind == SyncPlayVoteKind.episode ? message.value : null,
      );
      return;
    }
    if (state == null || state.id != message.id) {
      return;
    }
    final SyncPlayVoteState next = _withStance(state, sender, message.stance);
    vote.value = next;
    _evaluateVote(next);
  }

  /// 复制一份再改：ValueNotifier 对同一个实例赋值不会通知界面。
  SyncPlayVoteState _withStance(
    SyncPlayVoteState state,
    String username,
    String stance,
  ) {
    final SyncPlayVoteState next = SyncPlayVoteState(
      id: state.id,
      by: state.by,
      kind: state.kind,
      value: state.value,
      startedAt: state.startedAt,
    );
    next.yes.addAll(state.yes);
    next.no.addAll(state.no);
    if (stance == 'yes') {
      next.no.remove(username);
      next.yes.add(username);
    } else {
      next.yes.remove(username);
      next.no.add(username);
    }
    return next;
  }

  void _evaluateVote(SyncPlayVoteState state) {
    if (vote.value?.id != state.id) {
      return;
    }
    // 房主一票否决：直接把投票掐掉。
    final String? host = _currentHostUsername();
    if (host != null && state.no.contains(host)) {
      dismissVote();
      KazumiDialog.showToast(
        message: '房主否决了这个投票',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final int total = syncplayMembers.isEmpty
        ? state.yesCount + state.noCount
        : syncplayMembers.length;
    if (!SyncPlayVote.isPassed(
      yes: state.yesCount,
      no: state.noCount,
      totalMembers: total,
    )) {
      return;
    }
    dismissVote();
    _applyVote(state);
  }

  void _applyVote(SyncPlayVoteState state) {
    switch (state.kind) {
      case SyncPlayVoteKind.pause:
        unawaited(pause());
      case SyncPlayVoteKind.resume:
        unawaited(play());
      case SyncPlayVoteKind.episode:
        final change = _changeEpisode;
        if (change != null && state.value > 0) {
          unawaited(change(state.value, currentRoad: currentRoad()));
        }
    }
    KazumiDialog.showToast(
      message: '投票通过：${state.title}',
      duration: const Duration(seconds: 3),
    );
  }

  // ----------------------------------------------------------- 片源指纹
  /// 更新自己的片源指纹；在房间里就广播出去。
  void updateSource({
    required String pluginName,
    required int road,
    required String roadName,
  }) {
    _mySource = SyncPlaySourceInfo(
      pluginName: pluginName,
      road: road,
      roadName: roadName,
    );
    final client = syncplayController;
    if (client == null) {
      return;
    }
    unawaited(
      _runBestEffortSync(
        () => client.sendChatMessage(
          SyncPlaySourceTag.encode(
            pluginName: pluginName,
            road: road,
            roadName: roadName,
          ),
        ),
      ),
    );
    _refreshSourceMismatch();
  }

  void _onSourceTag(String sender, SyncPlaySourceInfo info) {
    if (sender == (syncplayController?.username ?? '')) {
      return;
    }
    _peerSources[sender] = info;
    _refreshSourceMismatch();
  }

  void _refreshSourceMismatch() {
    final SyncPlaySourceInfo? mine = _mySource;
    if (mine == null) {
      return;
    }
    // 以房主的为准；房主没广播过就看任意一个和我不同的。
    final String? host = _currentHostUsername();
    SyncPlaySourceInfo? peer;
    String by = '';
    if (host != null) {
      peer = _peerSources[host];
      by = host;
    }
    if (peer == null) {
      for (final MapEntry<String, SyncPlaySourceInfo> entry
          in _peerSources.entries) {
        if (entry.value.pluginName != mine.pluginName ||
            entry.value.road != mine.road) {
          peer = entry.value;
          by = entry.key;
          break;
        }
      }
    }
    if (peer == null ||
        (peer.pluginName == mine.pluginName && peer.road == mine.road)) {
      sourceMismatch.value = null;
      return;
    }
    sourceMismatch.value = SyncPlaySourceMismatch(
      by: by,
      info: peer,
      samePlugin: peer.pluginName == mine.pluginName,
    );
  }

  void dismissSourceMismatch() => sourceMismatch.value = null;

  /// 别人跳走了但我锁定了进度：提示一下，给个「跟上」按钮。
  void _hintRemoteSeek(String by, Duration target) {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastSeekHintAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastSeekHintAt = now;
    final String who = by.isEmpty ? '房间成员' : by;
    KazumiDialog.showToast(
      message: '$who 跳到了 ${_formatPosition(target)}（你的进度已锁定）',
      duration: const Duration(seconds: 5),
      showActionButton: true,
      actionLabel: '跟上',
      onActionPressed: () => seek(target, enableSync: false),
    );
  }

  static String _formatPosition(Duration value) {
    final int hours = value.inHours;
    final String minutes =
        value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds =
        value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /// 把自己的头像压成缩略图，通过 Chat 通道分片广播给房间里其他人。
  ///
  /// 协议本身不传头像，只能走这条「带外」通道。没设头像或编码失败就什么都不发，
  /// 对方那边自然退回首字色块——这是预期行为，不是错误。
  Future<void> broadcastAvatar() async {
    final client = syncplayController;
    if (client == null || syncplayRoom.isEmpty) return;
    final String path =
        GStorage.getSetting<String>(SettingsKeys.userAvatarPath);
    final String? b64 = await encodeLocalAvatar(path);
    if (b64 == null) return;
    final DateTime now = DateTime.now();
    if (b64 == _lastAvatarB64 &&
        _lastAvatarBroadcastAt != null &&
        now.difference(_lastAvatarBroadcastAt!) < _avatarBroadcastCooldown) {
      return;
    }
    final List<String> chunks = SyncPlayAvatarMessage(b64).encodeChunks();
    if (chunks.length > SyncPlayAvatarMessage.maxChunks) return;
    _lastAvatarB64 = b64;
    _lastAvatarBroadcastAt = now;
    await _runBestEffortSync(() async {
      for (final chunk in chunks) {
        await client.sendChatMessage(chunk);
        await Future<void>.delayed(SyncPlayAvatarMessage.chunkInterval);
      }
    });
  }

  Future<void> _runBestEffortSync(Future<void> Function() operation) async {
    try {
      await operation();
    } on SyncplayConnectionException {
      // Socket handlers report active connection failures.
    }
  }

  @action
  Future<void> exitRoom() async {
    _connectionSessions.cancel();
    final controller = syncplayController;
    syncplayController = null;
    syncplayRoom = '';
    syncplayClientRtt = 0;
    syncplayMembers = ObservableList.of([]);
    chatMessages = ObservableList.of([]);
    pinnedNotice = '';
    playQueue.value = const <int>[];
    activity.value = null;
    _stickerAssembler.reset();
    _avatarAssembler.reset();
    _avatarBytesNotifier.value = const {};
    // 房间级的临时状态全部清掉：退房后还挂着倒计时/投票是最容易漏的 bug。
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallWasPlaying = false;
    stall.value = null;
    _voteTimer?.cancel();
    _voteTimer = null;
    vote.value = null;
    sourceMismatch.value = null;
    _peerSources.clear();
    _stopCatchUp(restoreSpeed: true);
    if (controller == null) {
      return;
    }
    await controller.disconnect();
  }

  Future<void> dispose() async {
    _connectionSessions.close();
    await exitRoom();
    await _chatStreamController.close();
  }
}
