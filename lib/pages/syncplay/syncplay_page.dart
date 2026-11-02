import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/circular_reveal.dart';
import 'package:XL/bean/widget/clay.dart';
import 'package:XL/bean/widget/desktop_window_controls.dart';
import 'package:XL/bean/widget/loading_indicator.dart';
import 'package:XL/bean/widget/syncplay_activity_capsule.dart';
import 'package:XL/bean/widget/syncplay_notice.dart';
import 'package:XL/bean/widget/syncplay_avatar.dart';
import 'package:XL/bean/widget/syncplay_sticker_view.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/roads/road_module.dart';
import 'package:XL/modules/search/plugin_search_module.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/services/player/syncplay_client.dart' show SyncPlayUserInfo;
import 'package:XL/pages/syncplay/syncplay_controller.dart';
import 'package:XL/pages/syncplay/syncplay_chat_picker.dart';
import 'package:XL/pages/syncplay/syncplay_source_sheet.dart';
import 'package:XL/pages/syncplay/syncplay_sticker_packs.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/player/syncplay_endpoint.dart';
import 'package:XL/services/player/syncplay_play_request.dart';
import 'package:XL/services/player/syncplay_reaction.dart';
import 'package:XL/services/player/syncplay_recent_room.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/platform/desktop_window_config.dart';
import 'package:XL/utils/device.dart';
import 'package:XL/utils/immersive_theme.dart';
import 'package:XL/utils/motion.dart';
import 'package:XL/utils/title_match.dart';
import 'package:window_manager/window_manager.dart';

/// 一起看。
///
/// 信息层级按「房间 → 正在看 → 聊天」三段排：进房后第一眼先看到房间号和人，
/// 第二眼看到在放什么，聊天放最后并且可以折叠。同步服务器这类一次性设置
/// 收进「更多」，不占首屏。
///
/// 材质分工：玻璃（半透明面板）只承载内容，粘土（厚实渐变）只承载可点的东西。
class SyncPlayPage extends StatefulWidget {
  const SyncPlayPage({super.key, required this.controller});

  final SyncPlayController controller;

  @override
  State<SyncPlayPage> createState() => _SyncPlayPageState();
}

class _SyncPlayPageState extends State<SyncPlayPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  SyncPlayController get controller => widget.controller;

  bool _showJoinField = false;

  /// 剪贴板里的 8 位房号，用来在大厅给一条「点这里加入」。
  String _clipRoom = '';

  /// 聊天抽屉是不是开着。开着的时候不显示未读红点（正在看还提示未读很怪）。
  bool _chatSheetOpen = false;

  /// 上次看到第几条消息。底部聊天条的红点按 `总数 - 这个数` 算，
  /// 不能直接拿消息总数当未读——那样读完也一直挂个数字。
  int _seenChatCount = 0;
  final String _createdRoom = SyncPlayController.generateRoomNumber();

  /// 别人发起「开始一起看」时自动跟播用的订阅。
  StreamSubscription<SyncPlayPlayRequest>? _playRequestSubscription;
  bool _isFollowingRemotePlay = false;
  /// 上一次处理的播放请求签名 + 时间。发送方会用同一个消息 id 原样重发
  /// 一轮来补丢失的分片，收齐的组会重复解出同一个请求；同一部片短时间
  /// 内只处理一次，免得重复弹 toast（15 秒足够盖过重发窗口）。
  String _lastRemotePlaySignature = '';
  DateTime _lastRemotePlayAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 来源面板是不是开着；跟播时要先把它收掉，免得播放器退出后露出过期的面板。
  bool _isSourceSheetOpen = false;

  ///「开始一起看」按钮的位置，圆形扩散从这里长出来。
  final GlobalKey _startButtonKey = GlobalKey();
  Offset? _revealOrigin;

  /// 正在探片源。探针跑着的时候按钮转圈并禁点，避免连点广播两次。
  bool _isProbingSource = false;

  /// 候补片单是不是摊开的（叠卡展开）。
  bool _deckExpanded = false;

  /// 别人开始播放时是否自动跟播；关掉只提示不跳转。
  bool _autoFollow = true;

  // ---- 标题栏拖动（桌面） --------------------------------------------
  // 这页的标题栏是 SliverAppBar，套在 CustomScrollView 里，pan 手势会被
  // 滚动抢走竞技场，表现为「窗口拖不动」。跟 SysAppBar 同一套解法：
  // Listener 在命中分发阶段直接拿指针事件，位移超阈值就进系统拖动循环。
  Offset? _titleBarDragStart;
  bool _titleBarDragStarted = false;
  static const double _titleBarDragThreshold = 8.0;

  void _titleBarPointerDown(PointerDownEvent event) {
    _titleBarDragStart = event.position;
    _titleBarDragStarted = false;
  }

  void _titleBarPointerMove(PointerMoveEvent event) {
    final Offset? start = _titleBarDragStart;
    if (_titleBarDragStarted || start == null) return;
    if ((event.position - start).distance < _titleBarDragThreshold) return;
    _titleBarDragStarted = true;
    windowManager.startDragging();
  }

  void _titleBarPointerEnd() {
    _titleBarDragStart = null;
    _titleBarDragStarted = false;
  }

  StreamSubscription<String>? _nudgeSubscription;
  StreamSubscription<bool>? _hostTakeoverSubscription;

  /// 一起看时最常打的几句。点一下直接发，不用打字也不用等输入法。
  static const List<String> _quickPhrases = <String>[
    '等我一下',
    '我卡了',
    '继续吧',
    '笑死',
  ];

  /// 兜底换源时的标题相似度门槛（0~100）。
  ///
  /// 80 大致相当于「去掉了季数/字幕组后缀仍然一致」。调低会把「第2季」
  /// 和「第3季」当成同一部，那是灾难。
  static const int _fallbackTitleThreshold = 80;

  /// 一起看的两条降噪开关，直接从设置里读，改了就写回。
  bool _chatDanmaku = true;
  bool _presenceNotice = true;

  @override
  void initState() {
    super.initState();
    controller.restore();
    controller.loadRecentRooms();
    _usernameController.text = controller.username;
    _roomController.text = '';
    _chatDanmaku = GStorage.getSetting<bool>(SettingsKeys.syncPlayChatDanmaku);
    _presenceNotice =
        GStorage.getSetting<bool>(SettingsKeys.syncPlayPresenceNotice);
    unawaited(_readClipboardRoom());
    _playRequestSubscription =
        controller.playRequests.listen(_followRemotePlay);
    _nudgeSubscription = controller.nudges.listen((from) {
      if (!mounted) return;
      KazumiHaptics.select();
      KazumiDialog.showToast(
        message: '$from 敲了敲你',
        context: context,
        duration: const Duration(seconds: 3),
      );
    });
    _hostTakeoverSubscription = controller.hostTakeovers.listen((_) {
      if (!mounted) return;
      // 房主走了，控场权落到自己手上：不说一声，用户不知道自己现在一暂停、
      // 一换集就带着全房间一起动。
      KazumiHaptics.success();
      KazumiDialog.showToast(
        message: '房主离开了，现在由你主持房间',
        context: context,
        duration: const Duration(seconds: 4),
      );
    });
  }

  @override
  void dispose() {
    _nudgeSubscription?.cancel();
    _hostTakeoverSubscription?.cancel();
    _playRequestSubscription?.cancel();
    _usernameController.dispose();
    _roomController.dispose();
    _searchController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  /// 剪贴板里如果是 8 位纯数字，就在大厅顶部提示「点这里加入」。
  ///
  /// 实际用起来大多数人是被拉进别人的房间，复制房号再回来粘贴是常态；
  /// 读失败（桌面端没权限、剪贴板是图）就当没有，静默。
  Future<void> _readClipboardRoom() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.length != 8 || int.tryParse(text) == null) return;
      if (!mounted) return;
      setState(() => _clipRoom = text);
    } catch (_) {
      // 读不到就算了，不影响别的功能。
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: KazumiMotion.base,
        curve: KazumiMotion.emphasized,
      );
    });
  }

  // ---------------------------------------------------------------- 房间
  /// 广播一条「求同步」：正在播放的成员会把自己的番剧定向发回来，
  /// 这边收到播放请求后走 [_followRemotePlay] 自动拉起播放器。
  /// 「就绪握手」：等房间里其他人都把片源加载好。
  ///
  /// 没有这一步的话，房主按下开始就广播，自己这边 0:12 了，别人还在转圈，
  /// 第一次对齐只能硬 seek。现在房主停在大厅等 ready，齐了一起进场。
  Future<void> _waitForRoomReady() async {
    if (!controller.isInRoom || controller.otherMembers.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (_) => _ReadyCheckSheet(controller: controller),
    );
  }

  Future<void> _requestPlaybackSync() async {
    if (!controller.isInRoom) return;
    final ok = await controller.requestPlaybackSync();
    if (!mounted) return;
    KazumiHaptics.select();
    KazumiDialog.showToast(
      message: ok ? '已请求同步，正在播放的成员会发来片源' : '请求失败，请稍后再试',
      context: context,
      duration: const Duration(seconds: 3),
    );
  }

  /// 把这一页散落的开关汇总成一个面板：自动跟播（会话内）、聊天弹幕 /
  /// 进出提醒（持久化，原本在「更多」卡片里）、跟随进度条拖动（持久化，
  /// 原本只在播放器设置里）。
  ///
  /// 面板是独立 route，页面 setState 刷不到它，所以用 StatefulBuilder
  /// 让对话框自己重建；页面侧的 [_autoFollow] 再补一次 setState 保持
  /// 两边一致。
  Future<void> _showSyncPlaySettings() async {
    KazumiHaptics.select();
    await KazumiDialog.show<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Widget tile(
              String title,
              String subtitle,
              bool value,
              ValueChanged<bool> onChanged,
            ) {
              final colors = Theme.of(ctx).colorScheme;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(ctx).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ClaySwitch(value: value, onChanged: onChanged),
                  ],
                ),
              );
            }

            return ClayDialog(
              title: '一起看设置',
              message: '只影响自己这台设备，房间里的其他人不受影响。',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tile(
                    '自动跟播',
                    '别人开始播放时自动进入同一部番',
                    _autoFollow,
                    (v) {
                      setDialogState(() => _autoFollow = v);
                      if (mounted) setState(() {});
                    },
                  ),
                  tile(
                    '聊天弹幕',
                    _chatDanmaku
                        ? '房间里的聊天飘在播放画面上'
                        : '只在聊天记录里显示',
                    _chatDanmaku,
                    (v) {
                      setDialogState(() => _chatDanmaku = v);
                      GStorage.putSetting<bool>(
                        SettingsKeys.syncPlayChatDanmaku,
                        v,
                      );
                    },
                  ),
                  tile(
                    '进出提醒',
                    _presenceNotice
                        ? '有人进出房间时在顶部提示'
                        : '不提示，聊天记录里还留着',
                    _presenceNotice,
                    (v) {
                      setDialogState(() => _presenceNotice = v);
                      GStorage.putSetting<bool>(
                        SettingsKeys.syncPlayPresenceNotice,
                        v,
                      );
                    },
                  ),
                  tile(
                    '跟随进度条拖动',
                    '别人拖进度条时把我也拽过去',
                    GStorage.getSetting<bool>(
                      SettingsKeys.syncPlayFollowRemoteSeek,
                    ),
                    (v) {
                      setDialogState(() {});
                      GStorage.putSetting<bool>(
                        SettingsKeys.syncPlayFollowRemoteSeek,
                        v,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _createRoom() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      KazumiDialog.showToast(message: '请先填写昵称', context: context);
      return;
    }
    final ok = await controller.joinRoom(_createdRoom, username);
    if (!ok || !mounted) return;
    KazumiHaptics.success();
    KazumiDialog.showToast(message: '已创建房间 $_createdRoom', context: context);
  }

  Future<void> _joinRoom() async {
    final username = _usernameController.text.trim();
    final room = _roomController.text.trim();
    if (username.isEmpty) {
      KazumiDialog.showToast(message: '请先填写昵称', context: context);
      return;
    }
    if (room.isEmpty) {
      KazumiDialog.showToast(message: '请输入房间号', context: context);
      return;
    }
    if (room.length != kSyncPlayRoomNumberLength) {
      KazumiDialog.showToast(
        message: '房间号是 $kSyncPlayRoomNumberLength 位数字',
        context: context,
      );
      return;
    }
    final ok = await controller.joinRoom(room, username);
    if (!ok || !mounted) return;
    KazumiHaptics.success();
    KazumiDialog.showToast(message: '已加入房间 $room', context: context);
  }

  // ---------------------------------------------------------------- 选番
  /// 一键重回最近进过的房间。
  ///
  /// 房间号只在**同一台服务器**上有效，所以顺手把服务器也切回去 —— 否则
  /// 会在另一台服务器上开一个同样房号的空房间，看起来像「进去了但没人」。
  Future<void> _rejoinRecent(SyncPlayRecentRoom recent) async {
    if (recent.endPoint.isNotEmpty && recent.endPoint != controller.endPoint) {
      controller.setEndPoint(recent.endPoint);
    }
    _roomController.text = recent.room;
    setState(() => _showJoinField = true);
    await _joinRoom();
  }

  /// 点头像：敲一下对方。长按才进屏蔽确认 —— 敲一敲是高频动作，
  /// 屏蔽是低频且要确认的动作，两者不能都挂在单击上。
  Future<void> _nudgeMember(String username) async {
    if (username.isEmpty || username == controller.username) return;
    KazumiHaptics.select();
    final bool ok = await controller.nudge(username);
    if (!mounted) return;
    KazumiDialog.showToast(
      message: ok ? '敲了敲 $username' : '敲不动，先检查网络',
      context: context,
    );
  }

  /// 编辑置顶公告。留空 = 取消置顶。
  Future<void> _editPin() async {
    final TextEditingController textController =
        TextEditingController(text: controller.pinnedNotice ?? '');
    final String? result = await KazumiDialog.show<String>(
      context: context,
      builder: (ctx) => ClayDialog(
        title: '置顶公告',
        message: '钉在房间顶部，房间里所有人都能看到。留空则取消。',
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: SyncPlayPin.maxLength,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '比如：今晚看 1-3 集',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          ClayButton(
            height: 44,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ClayButton(
            height: 44,
            tone: ClayTone.accent,
            onPressed: () => Navigator.of(ctx).pop(textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (result == null || !mounted) return;
    final bool ok = await controller.announcePin(result);
    if (!mounted) return;
    if (!ok) {
      KazumiDialog.showToast(message: '公告没发出去，检查一下网络', context: context);
    }
  }

  /// 点头像：屏蔽 / 解除屏蔽这个人。
  Future<void> _showMemberActions(String username) async {
    if (username.isEmpty || username == controller.username) return;
    final bool blocked = controller.isBlocked(username);
    KazumiHaptics.select();
    final bool? ok = await ClayDialog.confirm(
      context,
      title: blocked ? '解除屏蔽 $username' : '屏蔽 $username',
      message: blocked
          ? '解除之后他的消息会重新出现。'
          : '他的聊天、反应和进出提醒都不会再显示。只对本次房间有效，退出即恢复。',
      confirmLabel: blocked ? '解除' : '屏蔽',
      destructive: !blocked,
    );
    if (ok != true) return;
    controller.toggleBlocked(username);
  }

  /// 网络诊断：把「连不上」拆成几个能分别确认的点，不用瞎猜。
  Future<void> _showDiagnostics() async {
    KazumiHaptics.select();
    await KazumiDialog.show<void>(
      context: context,
      builder: (ctx) => ClayDialog(
        title: '网络诊断',
        message: '逐项确认，哪一项不对就照它右边说的做。',
        content: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final parsed = parseSyncPlayEndPoint(controller.endPoint);
            final latency = controller.latency[controller.endPoint];
            final members = controller.members;
            final owner = members.where((m) => m.isController).toList();
            final rows = <(bool, String, String)>[
              (
                parsed != null,
                '服务器地址',
                parsed == null
                    ? '不合法，改成 host:port'
                    : '${parsed.host}:${parsed.port}',
              ),
              (
                latency == null || latency.reachable,
                '服务器可达',
                latency == null
                    ? '还没测，点下面的「重新测速」'
                    : (latency.reachable
                        ? '${latency.milliseconds} ms'
                        : '连不上，换一台服务器试试'),
              ),
              (
                controller.isInRoom,
                '房间',
                controller.isInRoom
                    ? '${controller.room} · ${members.length} 人'
                    : '还没进房',
              ),
              (
                controller.isInRoom ? owner.isNotEmpty : true,
                '控制权',
                owner.isEmpty
                    ? '服务端还没指派（等它推一次成员状态）'
                    : '房主是 ${owner.first.username}',
              ),
              (
                controller.rtt < 300,
                '当前延迟',
                controller.isInRoom ? '${controller.rtt} ms' : '进房后才有',
              ),
              (
                controller.blockedUsers.isEmpty,
                '屏蔽',
                controller.blockedUsers.isEmpty
                    ? '没有屏蔽任何人'
                    : '屏蔽了 ${controller.blockedUsers.length} 人',
              ),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          row.$1
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: row.$1
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 78,
                          child: Text(
                            row.$2,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.$3,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          ClayButton(
            height: 44,
            onPressed: () => controller.probeLatency(),
            child: Text(controller.isProbing ? '测速中' : '重新测速'),
          ),
          ClayButton(
            height: 44,
            tone: ClayTone.accent,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 复制一段可以直接发给好友的邀请文案。
  void _copyInvite() {
    final title = controller.selected == null
        ? ''
        : (controller.selected!.nameCn.isNotEmpty
            ? controller.selected!.nameCn
            : controller.selected!.name);
    final buffer = StringBuffer()
      ..writeln(title.isEmpty ? '来一起看番！' : '一起来看《$title》')
      ..writeln('房间号：${controller.room}')
      ..writeln('服务器：${controller.endPoint}');
    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    KazumiDialog.showToast(message: '邀请文案已复制', context: context);
  }

  /// 退出当前房间：先确认，避免误触把聊天和成员列表清掉。
  Future<void> _confirmExitRoom() async {
    final bool? ok = await ClayDialog.confirm(
      context,
      title: '退出房间',
      message: '退出后聊天记录和成员列表会清空，需要时可从「最近进过」一键重回。',
      confirmLabel: '退出',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    KazumiHaptics.select();
    await controller.leaveRoom();
    if (!mounted) return;
    KazumiDialog.showToast(message: '已退出房间', context: context);
  }

  /// 打开「播放来源」面板，让用户挑规则源与具体条目。
  Future<void> _openSourceSheet(BangumiItem item) async {
    controller.selectBangumi(item);
    _isSourceSheetOpen = true;
    await showAdaptiveBottomSheet<void>(
      context: context,
      maxHeightFactor: 0.88,
      builder: (_) => SyncPlaySourceSheet(
        bangumiItem: item,
        pluginsController: controller.pluginsController,
        onSelected: (plugin, searchItem, roads) =>
            _onSourceSelected(item, plugin, searchItem, roads),
      ),
    );
    _isSourceSheetOpen = false;
  }

  void _onSourceSelected(
    BangumiItem item,
    Plugin plugin,
    SearchItem searchItem,
    List<Road> roads,
  ) {
    // 先关掉来源面板，再进入播放器。
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    controller.selectSource(item, plugin, searchItem, roads);
    if (controller.isInRoom) {
      _startWatching();
    } else {
      KazumiDialog.showToast(
        message: '已选择来源，创建或加入房间后即可开始',
        context: context,
      );
    }
  }

  Future<void> _startWatching() async {
    // 同 _followRemotePlay：跳转前收键盘，别把它带进播放器。
    FocusManager.instance.primaryFocus?.unfocus();
    if (_showJoinField) setState(() => _showJoinField = false);
    if (_isProbingSource) return;
    final args = controller.buildPlaybackArgs();
    if (args == null) {
      KazumiDialog.showToast(message: '请先选择播放来源', context: context);
      return;
    }
    if (!controller.isInRoom) {
      KazumiDialog.showToast(message: '先创建或加入房间', context: context);
      return;
    }
    // 广播之前先探一下源。以前是直接广播「开始一起看」，源要是挂了，
    // 全房间一起黑屏，谁都说不清是谁选错了源。这里花一两秒确认条目页
    // 还能打开，打不开就原地提示，房间不散，换一个源接着试。
    setState(() => _isProbingSource = true);
    final probe = await controller.probeSource(args.src);
    if (!mounted) return;
    setState(() => _isProbingSource = false);
    if (!probe.isOk) {
      KazumiHaptics.tap();
      KazumiDialog.showToast(
        message: '这个源打不开（${probe.message}），换一个再试',
        context: context,
      );
      return;
    }
    final room = controller.room;
    final username = controller.username;
    // 把「播什么」广播出去，然后断开大厅连接交给播放器接管。
    // 顺序不能反：离开房间会断开 socket，消息就发不出去了。
    await controller.announcePlayback(
      SyncPlayPlayRequest(
        bangumiId: args.bangumiItem.id,
        name: args.bangumiItem.name,
        nameCn: args.bangumiItem.nameCn,
        coverUrl: args.bangumiItem.images['large'] ?? '',
        pluginName: args.plugin.name,
        title: args.title,
        src: args.src,
      ),
    );
    // 广播之后等一等：别人要重新拉剧集、解析源、缓冲，前后能差 5~15 秒。
    // 这里先把「谁还没加载好」摆出来，齐了再一起进场；最多等 12 秒，
    // 超时也照样开始 —— 等待不能变成新的卡点。
    if (mounted) {
      await _waitForRoomReady();
    }
    if (!mounted) return;
    // 立刻断开有可能在服务端读取之前就发 RST，把刚写出去的分片丢掉，
    // 留一点时间让它转发完再离开。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await controller.leaveRoom();
    if (!mounted) return;
    // 圆形扩散：从「开始一起看」按钮长出一个圆铺满整屏，再进播放器。
    // 播放器底色也是黑的，所以圆铺满之后换页看不出接缝。
    setState(() => _revealOrigin = revealOriginOf(_startButtonKey));
    await Future<void>.delayed(kCircularRevealDuration);
    if (!mounted) return;
    KazumiHaptics.success();
    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: args.bangumiItem,
        plugin: args.plugin,
        title: args.title,
        src: args.src,
        roads: args.roads,
        syncPlayRoom: room,
        syncPlayUserName: username,
      ),
    ).then((_) {
      // 从播放器回来后把遮罩收掉。
      if (mounted) setState(() => _revealOrigin = null);
    });
  }

  /// 房间里有人点了「开始一起看」，自动跟播同一部番、同一个片源。
  ///
  /// 对方只广播了「规则源 + 条目地址」，剧集列表在这里重新拉一遍，
  /// 这样两边的线路结构与进度都对得上，也不用把可能上千条的剧集塞进聊天消息。
  Future<void> _followRemotePlay(SyncPlayPlayRequest request) async {
    if (_isFollowingRemotePlay || !mounted || !controller.isInRoom) return;
    // iOS：如果键盘正开着（比如正在输房间号），直接跳转播放器会把键盘
    // 带过去，且播放器里没有能收起它的地方 —— 表现是「竖屏强制拉起系统
    // 键盘关不掉」。跳转前先收焦点，顺带把「加入房间」的输入框收起来，
    // 免得从播放器退回大厅时 autofocus 又把键盘弹出来。
    FocusManager.instance.primaryFocus?.unfocus();
    if (_showJoinField) setState(() => _showJoinField = false);
    final String signature = '${request.pluginName}#${request.src}';
    final DateTime now = DateTime.now();
    if (signature == _lastRemotePlaySignature &&
        now.difference(_lastRemotePlayAt) < const Duration(seconds: 15)) {
      return;
    }
    _lastRemotePlaySignature = signature;
    _lastRemotePlayAt = now;
    final reqTitle = request.title.isEmpty ? request.name : request.title;
    if (!_autoFollow) {
      KazumiDialog.showToast(
        message: '《$reqTitle》开始了，点「正在看」加入',
        context: context,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    _isFollowingRemotePlay = true;
    final room = controller.room;
    final username = controller.username;
    final title = reqTitle;

    Plugin? plugin;
    for (final candidate in controller.pluginsController.pluginList) {
      if (candidate.name == request.pluginName) {
        plugin = candidate;
        break;
      }
    }
    List<Road> roads = const <Road>[];
    if (plugin != null) {
      try {
        roads = await plugin.queryChapterRoads(request.src);
      } catch (error) {
        KazumiLogger().w('SyncPlay: resolve remote roads failed', error: error);
      }
    }
    // 没装对方用的那个源，或者对方选的片源已经失效 —— 先别急着报错，
    // 拿番名在自己已装的规则里再找一遍。同一部番在不同源里都有，
    // 能接上就比让用户自己去翻强。
    String fallbackPluginName = '';
    if (roads.isEmpty) {
      final fallback = await _findLocalSource(request);
      if (fallback == null) {
        _isFollowingRemotePlay = false;
        if (mounted) {
          KazumiDialog.showToast(
            message: plugin == null
                ? '房间里有人在看《$title》，但你没有装规则源「${request.pluginName}」，'
                    '你自己的源里也没搜到这部'
                : '对方选的片源已失效，你自己的源里也没搜到这部',
            context: context,
            duration: const Duration(seconds: 4),
          );
        }
        return;
      }
      plugin = fallback.plugin;
      roads = fallback.roads;
      fallbackPluginName = fallback.plugin.name;
    }
    if (!mounted) return;
    if (plugin == null) {
      // 走到这里说明剧集列表有内容却没有源，逻辑上不可能；防御一下，
      // 顺便让下面能按非空类型用 plugin。
      _isFollowingRemotePlay = false;
      return;
    }
    if (fallbackPluginName.isNotEmpty) {
      KazumiDialog.showToast(
        message: '已用你的源「$fallbackPluginName」接上《$title》',
        context: context,
        duration: const Duration(seconds: 3),
      );
    }

    KazumiDialog.showToast(
      message: '正在加入《$title》',
      context: context,
    );
    try {
      // 播放器会重新加入同一个房间，先把大厅这条连接让出来。
      await controller.leaveRoom();
      if (!mounted) return;
      if (_isSourceSheetOpen) {
        // 对方已经替我们决定了播什么，把没用的来源面板收掉。
        Navigator.of(context).maybePop();
        _isSourceSheetOpen = false;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }
      context.pushNamed(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: request.toBangumiItem(),
          plugin: plugin,
          title: title,
          src: request.src,
          roads: roads,
          syncPlayRoom: room,
          syncPlayUserName: username,
        ),
      );
    } catch (error) {
      KazumiLogger().w('SyncPlay: follow remote play failed', error: error);
      if (mounted) {
        KazumiDialog.showToast(message: '跟播失败，请手动选择番剧', context: context);
      }
    } finally {
      _isFollowingRemotePlay = false;
    }
  }

  // ---------------------------------------------------------------- 聊天
  /// 用番名在本地已装的规则里找同一部番，返回能直接播的源与剧集列表。
  ///
  /// 只在「对方用的源我没装 / 那个源失效了」时走这条路。标题必须真的对得上
  /// （相似度 ≥ [_fallbackTitleThreshold]）—— 随手取第一条会播成别的番，
  /// 那比不播更糟。
  Future<({Plugin plugin, List<Road> roads})?> _findLocalSource(
    SyncPlayPlayRequest request,
  ) async {
    final List<String> titles = <String>[
      request.nameCn,
      request.name,
    ].where((String title) => title.trim().isNotEmpty).toList();
    if (titles.isEmpty) return null;

    for (final Plugin plugin in controller.pluginsController.pluginList) {
      for (final String title in titles) {
        try {
          final response = await plugin.queryBangumi(title);
          if (response.data.isEmpty) continue;
          SearchItem? best;
          int bestScore = 0;
          for (final SearchItem item in response.data) {
            final int score = bestTitleScore(title, <String>[item.name]);
            if (score > bestScore) {
              bestScore = score;
              best = item;
            }
          }
          if (best == null || bestScore < _fallbackTitleThreshold) continue;
          final List<Road> roads = await plugin.queryChapterRoads(best.src);
          if (roads.isEmpty) continue;
          KazumiLogger().i(
            'SyncPlay: fallback to ${plugin.name} / ${best.name} '
            '(score $bestScore)',
          );
          return (plugin: plugin, roads: roads);
        } catch (error) {
          // 某个源搜不了不该拖垮整轮兜底，继续试下一个。
          KazumiLogger().w('SyncPlay: fallback search failed', error: error);
        }
      }
    }
    return null;
  }

  void _sendChat() {
    final text = _chatController.text;
    if (text.trim().isEmpty) return;
    _chatController.clear();
    controller.sendChatMessage(text);
    _scrollChatToBottom();
  }

  // ================================================================ 页面骨架

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PvColors.page(context),
      body: Stack(
        children: [
          CircularRevealOverlay(origin: _revealOrigin),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final bool inRoom = controller.isInRoom &&
                  controller.phase != SyncPlayPhase.connecting;
              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SafeArea(
                        bottom: false,
                        child: _buildHead(context, inRoom: inRoom),
                      ),
                      Expanded(
                        child: controller.phase == SyncPlayPhase.connecting
                            ? _buildConnectingBody(context)
                            : inRoom
                                ? _buildRoomBody(context)
                                : _buildLobbyBody(context),
                      ),
                    ],
                  ),
                  // 聊天条常驻在底栏上方：发送只要一次点击，历史才进抽屉。
                  if (inRoom && !_isWideLayout(context))
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: MediaQuery.paddingOf(context).bottom + 10,
                      child: _buildChatBar(context),
                    ),
                  // 进房 / 离房的动态条贴在标题下面。
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 58,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SyncPlayActivityToast(
                        activity: controller.activity,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 页内大标题 + 右上角操作。
  ///
  /// 跟「我的」「资源库」是同一套（`PvPageHead` 的 34px 大标题），区别只是
  /// 房内还要多一颗连接状态灯和一个「⋯」——房间的五个操作全收进那个「⋯」。
  Widget _buildHead(BuildContext context, {required bool inRoom}) {
    final bool desktop = isDesktop();
    final Widget head = Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text('一起看', style: PvText.pageTitle(context)),
          ),
          if (inRoom) ...[
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 2),
              child: _SyncStatusDot(
                rtt: controller.rtt,
                probing: controller.isProbing,
                onTap: controller.probeLatency,
              ),
            ),
            // 原来这里还有个「⋯」把四件事全收进去，太隐蔽了（而且菜单会弹到
            // 页面中间去）。现在拆开：复制/邀请在房号条上，拉取播放在「正在看」
            // 标题行，置顶公告在成员行的小旗子，退出房间在列表最底下。
          ],
          PvIconBtn(
            icon: Icons.tune_rounded,
            tooltip: '一起看设置',
            onTap: _showSyncPlaySettings,
          ),
          if (desktop) ...[
            if (DesktopWindowConfig.frameless)
              const DesktopWindowControls()
            else if (!DesktopWindowConfig.showWindowButton)
              CloseButton(onPressed: () => windowManager.close()),
          ],
        ],
      ),
    );
    if (!desktop) return head;
    // 无边框窗口下系统标题栏没了，整条标题栏都要能拖窗口。
    // 跟 SysAppBar 同一套解法：Listener 不参与手势竞技场，按钮照常点。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _titleBarPointerDown,
      onPointerMove: _titleBarPointerMove,
      onPointerUp: (_) => _titleBarPointerEnd(),
      onPointerCancel: (_) => _titleBarPointerEnd(),
      child: head,
    );
  }

  // ================================================================ 大厅

  Widget _buildLobbyBody(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom + 28;
    final String clipRoom = _clipRoom;
    final bool showClip =
        clipRoom.isNotEmpty && clipRoom != controller.room && !_showJoinField;

    return ListView(
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        PvGroup(children: [
          _SyncFieldRow(
            label: '昵称',
            hint: '房间内可见',
            controller: _usernameController,
            onChanged: controller.setUsername,
            onSubmitted: (_) => _showJoinField ? _joinRoom() : _createRoom(),
            showDivider: false,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: _SyncPrimaryButton(
            label: '创建房间',
            icon: Icons.add_rounded,
            onTap: _createRoom,
          ),
        ),
        PvGroup(children: [
          _SyncTapRow(
            title: '加入房间',
            subtitle: '输入好友分享的 8 位房号',
            showDivider: false,
            onTap: () {
              KazumiHaptics.select();
              setState(() => _showJoinField = !_showJoinField);
            },
          ),
        ]),
        if (_showJoinField) _buildJoinCard(context),
        if (showClip) _buildClipboardTip(context, clipRoom),
        if (controller.recentRooms.isNotEmpty) ...[
          PvGroupLabel('最近进过'),
          PvGroup(children: [
            for (var i = 0; i < controller.recentRooms.length; i++)
              _SyncRecentRow(
                recent: controller.recentRooms[i],
                showDivider: i > 0,
                onTap: () => _rejoinRecent(controller.recentRooms[i]),
                onRemove: () {
                  KazumiHaptics.tap();
                  controller.removeRecentRoom(controller.recentRooms[i].room);
                },
              ),
          ]),
        ],
        PvGroup(children: [
          _SyncTapRow(
            title: '一起看设置',
            value: '弹幕 · 提醒 · 跟播',
            showDivider: false,
            onTap: _showSyncPlaySettings,
          ),
        ]),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
            child: Text(
              controller.error!,
              style: TextStyle(fontSize: 13, color: PvColors.red),
            ),
          ),
      ],
    );
  }

  Widget _buildJoinCard(BuildContext context) {
    return PvGroup(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _roomController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(kSyncPlayRoomNumberLength),
              ],
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: PvColors.ink(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '房间号',
                hintStyle: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  color: PvColors.searchHint(context),
                ),
                filled: true,
                fillColor: PvColors.searchFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onSubmitted: (_) => _joinRoom(),
            ),
            const SizedBox(height: 10),
            _SyncPrimaryButton(label: '加入', height: 44, onTap: _joinRoom),
          ],
        ),
      ),
    ]);
  }

  /// 剪贴板里有 8 位房号时给一条快捷入口。
  ///
  /// 实际用起来大多数人是「被拉进别人的房间」，复制房号再回来粘贴是常态，
  /// 与其让人点开输入框粘贴，不如直接把这条摆出来。
  Widget _buildClipboardTip(BuildContext context, String room) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          KazumiHaptics.select();
          _roomController.text = room;
          setState(() => _showJoinField = true);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: PvColors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.content_paste_rounded,
                  size: 16, color: PvColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '剪贴板里有房间号 $room，点这里填入',
                  style: const TextStyle(fontSize: 13, color: PvColors.blue),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 17, color: PvColors.blue),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================ 连接中

  Widget _buildConnectingBody(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(
        top: 14,
        bottom: MediaQuery.paddingOf(context).bottom + 28,
      ),
      children: [
        PvGroup(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('正在连接', style: PvText.rowTitle(context)),
                const Spacer(),
                Text(
                  controller.endPoint,
                  style: PvText.rowSub(context),
                ),
              ],
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: _SyncPrimaryButton(
            label: '取消',
            tone: _SyncButtonTone.subtle,
            onTap: controller.leaveRoom,
          ),
        ),
      ],
    );
  }

  // ================================================================ 房内

  /// 宽屏（>= 760）把聊天挪到右栏常驻；窄屏用底部聊天条 + 抽屉。
  bool _isWideLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 760;

  Widget _buildRoomBody(BuildContext context) {
    final double navInset = MediaQuery.paddingOf(context).bottom;
    final bool wide = _isWideLayout(context);

    final Widget left = ListView(
      padding: EdgeInsets.only(bottom: navInset + (wide ? 20 : 78)),
      children: [
        _buildCoverStrip(context),
        const SizedBox(height: 14),
        _buildNowCard(context),
        _buildSyncRow(context),
        // 退出房间。原来是「⋯」菜单最后一项，红色但没人找得到；
        // 现在放在列表最底下一行红字，跟 iOS 设置页的「退出登录」同一个位置感。
        _buildExitRow(context),
      ],
    );

    if (!wide) return left;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: left),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 4, 20, navInset + 20),
            child: Container(
              decoration: BoxDecoration(
                color: PvColors.card(context),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _ChatPanel(
                controller: controller,
                textController: _chatController,
                quickPhrases: _quickPhrases,
                onSend: _sendChat,
                showGrabber: false,
                showClose: false,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部 74 高的封面条：房号 + 复制 + 人数。
  ///
  /// 不铺满整页——铺满之后浅色模式得压到 90% 白才看得清字，封面等于白做。
  /// 只在房内出现（大厅没有「正在看的东西」，摆一条空封面没意义）。
  Widget _buildCoverStrip(BuildContext context, {double horizontal = 20}) {
    final String cover = controller.selected?.images['large'] ?? '';
    final bool hasCover = cover.isNotEmpty;
    final bool dark = PvColors.isDark(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 74,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasCover)
                LayoutBuilder(
                  builder: (context, box) => NetworkImgLayer(
                    src: cover,
                    width: box.maxWidth,
                    height: 74,
                  ),
                )
              else
                ColoredBox(
                  color: dark ? const Color(0xFF26252A) : const Color(0xFFDCDAE0),
                ),
              if (hasCover)
                const ColoredBox(color: Color(0x57000000)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                child: Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _prettyRoom(controller.room),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: hasCover
                                ? Colors.white
                                : PvColors.ink(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RoomChip(
                      label: '复制',
                      filled: hasCover,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: controller.room));
                        KazumiDialog.showToast(
                            message: '已复制房间号', context: context);
                      },
                    ),
                    const SizedBox(width: 6),
                    _RoomChip(
                      label: '邀请',
                      filled: hasCover,
                      onTap: _copyInvite,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 房间 + 正在看合成的一张卡。
  ///
  /// 原来拆两张，房间卡里已经写了「正在看 第 N 话」，下面又摆一张「正在看」，
  /// 说的是同一件事。合起来之后首屏能省一百多 dp，聊天条才放得下。
  Widget _buildNowCard(BuildContext context) {
    final bool hasSource = controller.hasSource;
    // 房间里已经有人在放（服务端把文件名写进 Set.file）。注意判的是
    // 「房间在播」而不是「我选好源了」——后进房间的人什么都没选，
    // 正是需要一键跟上的时候。
    final bool remotePlaying = (controller.currentFile ?? '').isNotEmpty;
    final int? remoteEpisode = controller.currentEpisode;
    final bool showingNow = hasSource || remotePlaying;

    return PvGroup(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMemberRow(context),
            if (controller.pinnedNotice != null) ...[
              const SizedBox(height: 10),
              _PinnedNoticeBar(
                text: controller.pinnedNotice!,
                by: controller.pinnedBy,
                onTap: _editPin,
                onClear: () => controller.announcePin(''),
              ),
            ],
            const SizedBox(height: 12),
            Container(height: 0.8, color: PvColors.hair(context)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  showingNow ? '正在看' : '选择番剧',
                  style: PvText.rowTitle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (hasSource)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: controller.clearSelection,
                    child: const Text(
                      '换一部',
                      style: TextStyle(fontSize: 13, color: PvColors.blue),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 「加入一起看」：房主已经开播、你后进来的时候，这一颗就是入口。
            // 原来它只是标题右边一个 13px 的「拉取播放」文字链，藏得太深，
            // 后进房间的人根本不知道能点——这次改成整宽按钮，文案也说清楚
            // 对方在看第几话。
            if (remotePlaying) ...[
              if (!hasSource)
                _SyncPrimaryButton(
                  label: '加入一起看',
                  icon: Icons.play_arrow_rounded,
                  height: 46,
                  onTap: _requestPlaybackSync,
                )
              else
                _SyncPrimaryButton(
                  label: '跟上对方的播放',
                  icon: Icons.sync_rounded,
                  height: 44,
                  tone: _SyncButtonTone.subtle,
                  onTap: _requestPlaybackSync,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  remoteEpisode == null
                      ? '房间正在播放，点一下把画面拉过来'
                      : '对方正在看第 $remoteEpisode 话，点一下把画面拉过来',
                  textAlign: TextAlign.center,
                  style: PvText.rowSub(context).copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (!hasSource) ...[
              _buildSearchField(context),
              const SizedBox(height: 10),
              _buildPosterDeck(context),
            ] else
              _buildSelectedSource(context),
            const SizedBox(height: 12),
            _SyncPrimaryButton(
              key: _startButtonKey,
              label: _isProbingSource
                  ? '正在检查片源'
                  : (hasSource ? '开始一起看' : '先选一部番'),
              enabled: hasSource && controller.isInRoom,
              busy: _isProbingSource,
              onTap: _startWatching,
            ),
            if (!hasSource)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  '点海报挑播放来源，选好后这里会出现开始按钮',
                  textAlign: TextAlign.center,
                  style: PvText.rowSub(context).copyWith(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  /// 成员头像行：点一下敲他，长按屏蔽。
  Widget _buildMemberRow(BuildContext context) {
    final members = controller.members;
    final shown = members.take(5).toList();
    final int extra = members.length - shown.length;

    return Row(
      children: [
        if (shown.isEmpty)
          SyncPlayAvatar(
            name: controller.username,
            isSelf: true,
            size: 28,
            radius: 14,
            remoteImage: controller.avatarBytes[controller.username],
          )
        else
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == shown.length - 1 ? 0 : 5),
              child: GestureDetector(
                onTap: () => _nudgeMember(shown[i].username),
                onLongPress: () => _showMemberActions(shown[i].username),
                child: SyncPlayAvatar(
                  name: shown[i].username,
                  isSelf: shown[i].username == controller.username,
                  size: 28,
                  radius: 14,
                  remoteImage: controller.avatarBytes[shown[i].username],
                ),
              ),
            ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '+$extra',
              style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
            ),
          ),
        const SizedBox(width: 7),
        Text(
          '${members.isEmpty ? 1 : members.length} 人',
          style: PvText.rowSub(context).copyWith(fontSize: 12),
        ),
        const Spacer(),
        if (controller.currentEpisode != null) ...[
          Text(
            controller.totalEpisodes == null
                ? '第 ${controller.currentEpisode} 话'
                : '第 ${controller.currentEpisode} / ${controller.totalEpisodes} 话',
            style: PvText.rowSub(context).copyWith(fontSize: 12),
          ),
          const SizedBox(width: 10),
        ],
        // 置顶公告的入口。以前藏在「⋯」里没人找得到；现在就在成员行右边，
        // 有公告时图标变实心，点一下就能改。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _editPin,
          child: Tooltip(
            message: controller.pinnedNotice == null ? '置顶一条公告' : '修改公告',
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                controller.pinnedNotice == null
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                size: 17,
                color: controller.pinnedNotice == null
                    ? PvColors.ink3(context)
                    : PvColors.amberInk(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索番剧',
        hintStyle: TextStyle(
          fontSize: 15,
          color: PvColors.searchHint(context),
        ),
        prefixIcon: Icon(Icons.search_rounded,
            size: 19, color: PvColors.searchHint(context)),
        suffixIcon: controller.keyword.isEmpty
            ? null
            : GestureDetector(
                onTap: () {
                  _searchController.clear();
                  controller.clearSearch();
                },
                child: Icon(Icons.cancel_rounded,
                    size: 17, color: PvColors.searchHint(context)),
              ),
        filled: true,
        fillColor: PvColors.searchFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
      ),
      onChanged: controller.updateKeyword,
    );
  }

  Widget _buildPosterDeck(BuildContext context) {
    final results = controller.searchResults;

    if (controller.isSearching) {
      return const SizedBox(
        height: 96,
        child: Center(child: LoadingIndicator()),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          controller.keyword.isEmpty
              ? '搜一部番剧，房间里所有人会同步看同一集'
              : '没有找到相关番剧',
          textAlign: TextAlign.center,
          style: PvText.rowSub(context).copyWith(fontSize: 12),
        ),
      );
    }

    final duration = KazumiMotion.scale(context, KazumiMotion.base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            KazumiHaptics.select();
            setState(() => _deckExpanded = !_deckExpanded);
          },
          child: Row(
            children: [
              Text(
                '候补片单',
                style: PvText.rowSub(context).copyWith(fontSize: 12.5),
              ),
              const SizedBox(width: 6),
              Text(
                '${results.length}',
                style: TextStyle(fontSize: 11.5, color: PvColors.ink3(context)),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _deckExpanded ? 0.5 : 0,
                duration: duration,
                curve: KazumiMotion.spring,
                child: Icon(Icons.expand_more_rounded,
                    size: 18, color: PvColors.ink3(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: duration,
          curve: KazumiMotion.emphasized,
          alignment: Alignment.topCenter,
          child: _deckExpanded
              ? Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  children: [
                    for (final item in results.take(9))
                      SizedBox(
                        width: 92,
                        child: _PosterCard(
                          item: item,
                          selected: controller.selected?.id == item.id,
                          onTap: () => _openSourceSheet(item),
                        ),
                      ),
                  ],
                )
              : _buildStackedDeck(results.take(3).toList()),
        ),
      ],
    );
  }

  /// 收起状态：几张封面错开叠在一起，只露出一点边。
  Widget _buildStackedDeck(List<BangumiItem> items) {
    return SizedBox(
      height: 138,
      child: Stack(
        children: [
          for (var i = items.length - 1; i >= 0; i--)
            Positioned(
              top: i * 10.0,
              left: 0,
              child: Transform.scale(
                alignment: Alignment.topCenter,
                scale: 1 - i * 0.05,
                child: Opacity(
                  opacity: i == 0 ? 1 : 0.8 - i * 0.18,
                  child: GestureDetector(
                    onTap: () => _openSourceSheet(items[i]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: NetworkImgLayer(
                        src: items[i].images['large'] ?? '',
                        width: 92,
                        height: 126,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedSource(BuildContext context) {
    final item = controller.selected!;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: NetworkImgLayer(
            src: item.images['large'] ?? '',
            width: 44,
            height: 60,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PvText.rowTitle(context),
              ),
              if (controller.sourceHint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '播放源：${controller.sourceHint}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PvText.rowSub(context).copyWith(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 同步服务器 + 网络诊断收成一行，点开才是列表。
  ///
  /// 跟服务器表单里的「高级设置」一个套路：一次性设置不该常驻首屏。
  Widget _buildSyncRow(BuildContext context) {
    final int? ms = controller.latency[controller.endPoint]?.milliseconds;
    final String value = ms == null
        ? (controller.isProbing ? '探测中…' : '未探测')
        : '$ms ms';

    return PvGroup(children: [
      _SyncTapRow(
        title: '同步服务器',
        subtitle: controller.endPoint,
        value: value,
        showDivider: false,
        onTap: () => _showSyncServerSheet(context),
      ),
    ]);
  }

  // ---------------------------------------------------------------- 房间操作

  /// 列表最底下的「退出房间」。
  ///
  /// 以前是「⋯」菜单的最后一项。退出是破坏性操作，不适合跟「复制房间号」
  /// 这种放在一起；挪到最底下一行红字，既显眼又不容易误触。
  Widget _buildExitRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _confirmExitRoom,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PvColors.card(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            '退出房间',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PvColors.red,
            ),
          ),
        ),
      ),
    );
  }

  /// 同步服务器列表 + 网络诊断。
  Future<void> _showSyncServerSheet(BuildContext context) async {
    final endPoints = [
      ...officialSyncPlayEndPoints,
      if (!officialSyncPlayEndPoints.contains(controller.endPoint))
        controller.endPoint,
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      isScrollControlled: true,
      builder: (sheetContext) => Material(
        color: PvColors.page(sheetContext),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetGrabber(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Text('同步服务器',
                          style: PvText.section(context)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(sheetContext).maybePop(),
                        child: const Text('完成',
                            style:
                                TextStyle(fontSize: 15, color: PvColors.blue)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      PvGroup(children: [
                        for (var i = 0; i < endPoints.length; i++)
                          _EndPointTile(
                            endPoint: endPoints[i],
                            selected: endPoints[i] == controller.endPoint,
                            result: controller.latency[endPoints[i]],
                            showDivider: i > 0,
                            onTap: () => controller.setEndPoint(endPoints[i]),
                          ),
                      ]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                        child: Text(
                          '房间成员必须使用同一台服务器',
                          style: PvText.rowSub(context).copyWith(fontSize: 12),
                        ),
                      ),
                      PvGroup(children: [
                        _SyncTapRow(
                          title: '网络诊断',
                          subtitle: '连不上时先跑一遍',
                          showDivider: false,
                          onTap: () {
                            Navigator.of(sheetContext).maybePop();
                            _showDiagnostics();
                          },
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 聊天条

  /// 常驻的输入条：左边是打开历史的按钮（带未读数），中间输入，右边发送。
  Widget _buildChatBar(BuildContext context) {
    final int total = controller.messages.length;
    final int unread =
        _chatSheetOpen ? 0 : (total - _seenChatCount).clamp(0, 999);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openChatSheet(context),
            child: SizedBox(
              width: 38,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 20, color: PvColors.ink2(context)),
                  if (unread > 0)
                    Positioned(
                      right: 2,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 15),
                        decoration: BoxDecoration(
                          color: PvColors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _chatController,
              style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                isDense: true,
                // 有未读时把最后一条消息当占位文案：不点开抽屉也知道对方说了
                // 什么。原来这里恒为「发送消息」，红点只告诉你「有新消息」，
                // 想说句什么还得先点开看一眼。
                hintText: unread > 0 ? _latestChatPreview() : '发送消息',
                hintStyle: TextStyle(
                  fontSize: unread > 0 ? 14 : 15,
                  color: unread > 0
                      ? PvColors.ink2(context)
                      : PvColors.searchHint(context),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _sendChat(),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sendChat,
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: PvColors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  size: 19, color: Colors.white),
            ),
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }

  /// 最后一条消息压成一行：`昵称：正文`。快捷反应只有一个 emoji，就只给 emoji。
  String _latestChatPreview() {
    if (controller.messages.isEmpty) return '发送消息';
    final SyncPlayChatMessage last = controller.messages.last;
    final String body = last.message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty) return '发送消息';
    if (last.isReaction) return '${last.username} $body';
    return '${last.username}：$body';
  }

  Future<void> _openChatSheet(BuildContext context) {
    setState(() {
      _chatSheetOpen = true;
      _seenChatCount = controller.messages.length;
    });
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.30),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.74,
        child: _ChatSheet(
          controller: controller,
          textController: _chatController,
          quickPhrases: _quickPhrases,
          onSend: _sendChat,
        ),
      ),
    ).whenComplete(() {
      // 抽屉关掉时把「看到第几条」推到最新，红点从这里重新数。
      if (!mounted) return;
      setState(() {
        _chatSheetOpen = false;
        _seenChatCount = controller.messages.length;
      });
    });
  }
}

// ================================================================ 新组件

/// 顶栏的连接状态灯。
///
/// 「卡不卡」是一起看最关键的信息，原来缩成房间卡角落一个灰 chip，
/// 现在做成一颗点：绿 / 黄 / 红，点一下重测。
class _SyncStatusDot extends StatelessWidget {
  const _SyncStatusDot({
    required this.rtt,
    required this.probing,
    required this.onTap,
  });

  final int rtt;
  final bool probing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (probing || rtt <= 0) {
      color = const Color(0xFFB4B2A9);
      label = probing ? '正在测延迟' : '延迟未知';
    } else if (rtt <= 80) {
      color = const Color(0xFF34C759);
      label = '延迟 $rtt ms';
    } else if (rtt <= 200) {
      color = const Color(0xFFFF9F0A);
      label = '延迟 $rtt ms';
    } else {
      color = const Color(0xFFFF3B30);
      label = '延迟 $rtt ms';
    }

    return Tooltip(
      message: '$label，点一下重测',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 30,
          child: Center(
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面条上的小胶囊：复制 / 邀请。
///
/// 压在模糊封面上时用半透明白底，没封面时用淡蓝底，两种底色下都够清楚。
class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;

  /// 是不是压在封面上（决定用白底还是淡蓝底）。
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: filled
              ? Colors.white.withValues(alpha: 0.24)
              : PvColors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : PvColors.blue,
          ),
        ),
      ),
    );
  }
}

/// 白卡里的一行：标题 / 副标题 / 右侧值 / 箭头。
class _SyncTapRow extends StatelessWidget {
  const _SyncTapRow({
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PvText.rowTitle(context)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PvText.rowSub(context).copyWith(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null && value!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(value!, style: PvText.rowSub(context)),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: PvColors.chev(context)),
          ],
        ),
      ),
    );

    final body = onTap == null
        ? row
        : InkWell(onTap: onTap, child: row);

    if (!showDivider) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 15),
          color: PvColors.hair(context),
        ),
        body,
      ],
    );
  }
}

/// 白卡里的输入行：标签 + 右侧胶囊输入框。
class _SyncFieldRow extends StatelessWidget {
  const _SyncFieldRow({
    required this.label,
    required this.hint,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.showDivider = true,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 15),
          SizedBox(
            width: 56,
            child: Text(label, style: PvText.rowTitle(context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: PvColors.searchFill(context),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(fontSize: 15, color: PvColors.ink(context)),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: PvColors.searchHint(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
        ],
      ),
    );

    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 15),
          color: PvColors.hair(context),
        ),
        row,
      ],
    );
  }
}

enum _SyncButtonTone { accent, subtle }

/// 主按钮：蓝色实心胶囊；[tone] 为 subtle 时是浅灰底。
class _SyncPrimaryButton extends StatelessWidget {
  const _SyncPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.busy = false,
    this.height = 50,
    this.tone = _SyncButtonTone.accent,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;

  /// 跑着异步活儿（比如探片源）时转圈并禁点。
  final bool busy;
  final double height;
  final _SyncButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final bool accent = tone == _SyncButtonTone.accent;
    final bool tappable = enabled && !busy;
    final Color bg;
    final Color fg;
    if (!enabled || busy) {
      bg = PvColors.blue.withValues(alpha: 0.30);
      fg = Colors.white;
    } else if (accent) {
      bg = PvColors.blue;
      fg = Colors.white;
    } else {
      bg = PvColors.searchFill(context);
      fg = PvColors.ink(context);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tappable ? onTap : null,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「最近进过」的一行：房号 + 当时看的番 + 时间。
class _SyncRecentRow extends StatelessWidget {
  const _SyncRecentRow({
    required this.recent,
    required this.onTap,
    this.onRemove,
    this.showDivider = true,
  });

  final SyncPlayRecentRoom recent;
  final VoidCallback onTap;

  /// 删掉这条记录。原来是「只能进不能删」，进错的房间会一直占着最上面。
  final VoidCallback? onRemove;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _prettyRoom(recent.room),
                    style: PvText.rowTitle(context).copyWith(
                      letterSpacing: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (recent.title.isNotEmpty) recent.title,
                        _relativeTime(recent.at),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PvText.rowSub(context).copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 10),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: PvColors.ink3(context)),
                ),
              ),
            Icon(Icons.chevron_right_rounded,
                size: 17, color: PvColors.chev(context)),
          ],
        ),
      ),
    );

    final body = InkWell(onTap: onTap, child: row);
    if (!showDivider) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 15),
          color: PvColors.hair(context),
        ),
        body,
      ],
    );
  }
}

/// 抽屉顶部的拖拽条。
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: PvColors.ink3(context).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 聊天抽屉：消息列表 + 快捷反应 + 快捷短语 + 输入条。
/// 聊天抽屉：底部弹出时套一层圆角 Material。
class _ChatSheet extends StatelessWidget {
  const _ChatSheet({
    required this.controller,
    required this.textController,
    required this.quickPhrases,
    required this.onSend,
  });

  final SyncPlayController controller;
  final TextEditingController textController;
  final List<String> quickPhrases;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PvColors.page(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: _ChatPanel(
        controller: controller,
        textController: textController,
        quickPhrases: quickPhrases,
        onSend: onSend,
      ),
    );
  }
}

/// 聊天本体：消息列表 + 快捷反应 + 快捷短语 + 输入条。
///
/// 抽屉和宽屏右栏共用这一份，省得两处各写一套。
class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    required this.controller,
    required this.textController,
    required this.quickPhrases,
    required this.onSend,
    this.showGrabber = true,
    this.showClose = true,
  });

  final SyncPlayController controller;
  final TextEditingController textController;
  final List<String> quickPhrases;
  final VoidCallback onSend;
  final bool showGrabber;
  final bool showClose;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final messages = controller.messages;
        return Column(
          children: [
            if (widget.showGrabber) const _SheetGrabber(),
            Padding(
              padding: EdgeInsets.fromLTRB(20, widget.showGrabber ? 2 : 14, 14, 8),
              child: Row(
                children: [
                  Text('聊天', style: PvText.section(context)),
                  const SizedBox(width: 7),
                  Text('${messages.length}', style: PvText.count(context)),
                  const Spacer(),
                  if (widget.showClose)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.expand_more_rounded,
                            size: 24, color: PvColors.blue),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text('说点什么吧', style: PvText.rowSub(context)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _ChatBubble(
                        message: messages[index],
                        self: controller.username,
                        avatars: controller.avatarBytes,
                      ),
                    ),
            ),
            // 快捷反应：比打字快，也不占聊天记录的地盘。
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: SyncPlayReaction.palette.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final String emoji = SyncPlayReaction.palette[index];
                  return GestureDetector(
                    onTap: () {
                      KazumiHaptics.select();
                      controller.sendReaction(emoji);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PvColors.searchFill(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 19)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.quickPhrases.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final String phrase = widget.quickPhrases[index];
                  return GestureDetector(
                    onTap: () {
                      KazumiHaptics.select();
                      controller.sendChatMessage(phrase);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PvColors.searchFill(context),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        phrase,
                        style: PvText.rowSub(context).copyWith(
                          fontSize: 13,
                          color: PvColors.ink2(context),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showSyncPlayChatPicker(
                        context: context,
                        textController: widget.textController,
                        onSticker: controller.sendSticker,
                      ),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.emoji_emotions_outlined,
                            size: 22, color: PvColors.ink2(context)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: PvColors.searchFill(context),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          controller: widget.textController,
                          minLines: 1,
                          maxLines: 3,
                          style: TextStyle(
                              fontSize: 15, color: PvColors.ink(context)),
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            hintText: '发送消息',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: PvColors.searchHint(context),
                            ),
                          ),
                          onSubmitted: (_) {
                            widget.onSend();
                            WidgetsBinding.instance
                                .addPostFrameCallback((_) => _toBottom());
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onSend();
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _toBottom());
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: PvColors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 小组件

/// 房间顶部的置顶公告条。
class _PinnedNoticeBar extends StatelessWidget {
  const _PinnedNoticeBar({
    required this.text,
    required this.by,
    required this.onClear,
    this.onTap,
  });

  final String text;
  final String by;
  final VoidCallback onClear;

  /// 点正文直接改公告（跟成员行那颗小旗子同一个入口）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = PvColors.amberFill(context);
    final Color fg = PvColors.amberInk(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.push_pin_rounded, size: 14, color: fg),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 13, height: 1.35, color: fg),
                  ),
                  if (by.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '— $by',
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Icon(Icons.close_rounded, size: 15, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.self,
    required this.avatars,
  });

  final SyncPlayChatMessage message;

  /// 本地用户名，用来判断「这是不是我发的」并取对应的头像/昵称。
  final String self;

  /// 远端成员的真实头像（用户名 -> 内存字节），查不到就退回首字色块。
  final Map<String, Uint8List> avatars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool isSystem = message.username.isEmpty;
    if (isSystem) {
      return SyncPlayNotice(
        text: message.message,
        highlight: SyncPlayNotice.isJoin(message.message),
      );
    }
    final bool mine = !message.fromRemote;
    final bool isSelf = message.username == self;
    final String name = SyncPlayAvatar.displayName(message.username, self);
    // 反应不套气泡，只画一个 emoji —— 套上气泡就成了「一句话」。
    if (message.isReaction) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!mine) ...[
                SyncPlayAvatar(
                  name: message.username,
                  isSelf: isSelf,
                  size: 24,
                  radius: 12,
                  remoteImage: avatars[message.username],
                ),
                const SizedBox(width: 6),
              ],
              Text(message.message, style: const TextStyle(fontSize: 24)),
            ],
          ),
        ),
      );
    }
    final bool dark = theme.brightness == Brightness.dark;
    final SyncPlayStickerMessage? stickerMessage =
        SyncPlayStickerMessage.tryDecodeChat(message.message);
    if (stickerMessage != null) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                SyncPlayAvatar(
                  name: message.username,
                  isSelf: isSelf,
                  size: 32,
                  radius: 16,
                  remoteImage: avatars[message.username],
                ),
                const SizedBox(width: 8),
              ],
              Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  SyncPlayStickerView(
                    sticker: SyncPlayStickerStore.instance.resolveMessage(
                      stickerMessage.packId,
                      stickerMessage.stickerId,
                      stickerMessage.url,
                    ),
                    size: 104,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final Widget bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 232),
      decoration: BoxDecoration(
        // 自己的气泡用强调色染底、别人的用中性面；两者都只取一点点色，
        // 让主题正文色压上去始终有对比度——浅色下直接写白色会整块消失。
        color: mine
            ? ClayToneColors.of(context, ClayTone.accent).tintSurface(context)
            : (dark
                ? Colors.white.withValues(alpha: 0.07)
                : theme.colorScheme.surfaceContainerHigh),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 4),
          bottomRight: Radius.circular(mine ? 4 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          Text(
            message.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
    // 自己靠右、别人靠左；两边都带头像，昵称只在别人的气泡里标一次。
    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bubble,
            const SizedBox(width: 8),
            SyncPlayAvatar(
              name: message.username,
              isSelf: isSelf,
              size: 32,
              radius: 16,
              remoteImage: avatars[message.username],
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          SyncPlayAvatar(
            name: message.username,
            isSelf: isSelf,
            size: 32,
            radius: 16,
            remoteImage: avatars[message.username],
          ),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BangumiItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return SizedBox(
      width: 92,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: immersiveBorderRadius,
              child: Stack(
                children: [
                  NetworkImgLayer(
                    src: item.images['large'] ?? '',
                    width: 92,
                    height: 126,
                  ),
                  if (selected)
                    Positioned.fill(
                      child: ColoredBox(
                        // 压在封面上的选中遮罩要够重，白勾才浮得出来：
                        // 浅色模式的粘土色是浅紫，直接用会在封面上糊成一片。
                        color: ClayToneColors.of(context, ClayTone.accent)
                            .strong
                            .withValues(alpha: 0.55),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EndPointTile extends StatelessWidget {
  const _EndPointTile({
    required this.endPoint,
    required this.selected,
    required this.result,
    required this.onTap,
    this.showDivider = true,
  });

  final String endPoint;
  final bool selected;
  final SyncPlayLatencyResult? result;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    final int? ms = result?.milliseconds;
    Color? latencyColor;
    if (ms != null && ms >= 0) {
      // 直接用 Colors.green / orange 在白底上只有 2:1 左右的对比度，
      // 浅色模式换成压深的同色相，深色模式用提亮的版本。
      latencyColor = ms < 120
          ? (dark ? const Color(0xFF7BD88A) : const Color(0xFF2E7D32))
          : ms < 300
              ? (dark ? const Color(0xFFFFC46B) : const Color(0xFFA86200))
              : (dark ? const Color(0xFFFF9A8F) : const Color(0xFFB3261E));
    }

    final row = InkWell(
      onTap: () {
        KazumiHaptics.select();
        onTap();
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: selected ? PvColors.blue : PvColors.chev(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  endPoint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PvText.rowTitle(context).copyWith(
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                result == null
                    ? '未测速'
                    : (result!.reachable
                        ? '${result!.milliseconds} ms'
                        : '连接失败'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: latencyColor ?? PvColors.ink3(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 0.8,
          margin: const EdgeInsets.only(left: 15),
          color: PvColors.hair(context),
        ),
        row,
      ],
    );
  }
}

/// `12345678` → `1234 5678`。八位连排容易看错位。
String _prettyRoom(String room) {
  final clean = room.replaceAll(' ', '');
  if (clean.length != 8) return room;
  return '${clean.substring(0, 4)} ${clean.substring(4)}';
}

/// 「3 分钟前」这种相对时间，超过一周就退回日期。
String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${at.month} 月 ${at.day} 日';
}

/// 「等待房间」：把每个人的加载状态摆出来，齐了一起起播。
///
/// 自己管计时：全员就绪或超时都自动关掉，不需要房主再点一次。
class _ReadyCheckSheet extends StatefulWidget {
  const _ReadyCheckSheet({required this.controller});

  final SyncPlayController controller;

  @override
  State<_ReadyCheckSheet> createState() => _ReadyCheckSheetState();
}

class _ReadyCheckSheetState extends State<_ReadyCheckSheet> {
  static const Duration _timeout = Duration(seconds: 12);
  static const Duration _tick = Duration(milliseconds: 250);

  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_tick, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _check() {
    if (_closing) return;
    final bool allReady = widget.controller.allOthersReady;
    final bool timeout = DateTime.now().difference(_startedAt) > _timeout;
    if (!allReady && !timeout) return;
    _finish();
  }

  void _finish() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: PvColors.card(context),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (BuildContext context, _) {
              final List<SyncPlayUserInfo> others =
                  widget.controller.otherMembers;
              final int ready = widget.controller.readyCount;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '等待房间',
                        style: PvText.section(context)
                            .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '$ready/${others.length} 已就绪',
                        style: PvText.count(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '等大家把片源加载好再一起开始，第一个镜头就不会有人掉队',
                    style: PvText.rowSub(context).copyWith(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  for (final SyncPlayUserInfo member in others)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SyncPlayAvatar(
                            name: member.username,
                            size: 26,
                            radius: 13,
                            remoteImage:
                                widget.controller.avatarBytes[member.username],
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              member.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PvText.rowTitle(context),
                            ),
                          ),
                          Text(
                            member.isReady == true ? '已就绪' : '正在加载',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: member.isReady == true
                                  ? PvColors.green
                                  : PvColors.ink3(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  _SyncPrimaryButton(
                    label: '现在开始',
                    height: 46,
                    onTap: _finish,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
