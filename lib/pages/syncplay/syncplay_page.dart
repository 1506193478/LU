import 'dart:async';
import 'dart:ui' show ImageFilter;

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
import 'package:XL/pages/player/controller/player_models.dart';
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
import 'package:XL/bean/widget/clay_neu.dart';
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
  bool _chatExpanded = true;
  bool _serverExpanded = false;
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
    final args = controller.buildPlaybackArgs();
    if (args == null) {
      KazumiDialog.showToast(message: '请先选择播放来源', context: context);
      return;
    }
    if (!controller.isInRoom) {
      KazumiDialog.showToast(message: '先创建或加入房间', context: context);
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

  // ---------------------------------------------------------------- 构建
  @override
  Widget build(BuildContext context) {
    // 这一页是「模糊封面 + 玻璃面板」的影院感布局，深浅两种模式各用一套底色：
    // 浅色下必须是浅底，否则主题给的深色正文会直接糊成一片。
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: neuScaffoldBackground(context) ??
          (dark ? immersiveDarkScaffold : immersiveLightScaffold),
      body: Stack(
        children: [
          _buildBackdrop(context),
          CircularRevealOverlay(origin: _revealOrigin),
          // 进房 / 离房的动态条贴在页面顶部：这一页没有视频画面可盖，
          // 让它落在标题栏下面一点，既不挡卡片也不至于看不见。
          Positioned(
            top: MediaQuery.paddingOf(context).top + 52,
            left: 0,
            right: 0,
            child: Center(
              child: SyncPlayActivityToast(activity: controller.activity),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return CustomScrollView(
                slivers: [
                  _buildAppBar(context),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      immersiveTabBarInset(context) + 24,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (controller.phase == SyncPlayPhase.connecting)
                          _buildConnectingCard(context)
                        else if (controller.isInRoom) ...[
                          _buildRoomCard(context),
                          const SizedBox(height: 12),
                          _buildNowPlayingCard(context),
                          const SizedBox(height: 12),
                          _buildChatCard(context),
                        ] else ...[
                          _buildNicknameField(context),
                          const SizedBox(height: 12),
                          _buildEntryCards(context),
                        ],
                        const SizedBox(height: 12),
                        _buildMoreCard(context),
                      ]),
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

  /// 页面背景：选了番就把封面糊掉当底，玻璃面板才有东西可衬。
  ///
  /// 只在选中番剧时出现，模糊一次性算好（child 不变，layer 可复用），
  /// 不会因为滚动每帧重算。
  Widget _buildBackdrop(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color base = dark ? immersiveDarkScaffold : immersiveLightScaffold;
    final cover = controller.selected?.images['large'] ?? '';
    if (cover.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: base),
        child: const SizedBox.expand(),
      );
    }
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
          child: NetworkImgLayer(
            src: cover,
            width: size.width,
            height: size.height,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // 浅色模式的压盖要更狠：封面多半是深色海报，不压到 0.9 以上，
              // 深色正文压上去就没有对比度了。
              colors: [
                base.withValues(alpha: dark ? 0.74 : 0.88),
                base.withValues(alpha: dark ? 0.90 : 0.95),
                base,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final bool desktop = isDesktop();
    final appBarActions = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ClayIconButton(
          tooltip: '一起看设置',
          size: 38,
          icon: Icons.tune_rounded,
          onPressed: _showSyncPlaySettings,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ClayIconButton(
          tooltip: '实测服务器延迟',
          size: 38,
          icon: Icons.network_ping_rounded,
          onPressed: controller.isProbing ? null : controller.probeLatency,
        ),
      ),
    ];
    if (desktop) {
      // 无边框模式下系统标题栏没了，三个窗口按钮得自己画。
      // 和 SysAppBar 同一套规则：无边框画全套；留了系统边框但隐藏了
      // 窗口按钮的只给一个关闭。
      if (DesktopWindowConfig.frameless) {
        appBarActions.add(const DesktopWindowControls());
      } else if (!DesktopWindowConfig.showWindowButton) {
        appBarActions.add(CloseButton(onPressed: () => windowManager.close()));
      }
    }
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      title: Text(
        '一起看',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      // 拖动窗口用的透明层，铺在标题栏整条上（含标题文字和按钮下面的
      // 空白）。Listener 不参与手势竞技场，按钮照常点，按住拖动就换窗口。
      flexibleSpace: desktop
          ? Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _titleBarPointerDown,
              onPointerMove: _titleBarPointerMove,
              onPointerUp: (_) => _titleBarPointerEnd(),
              onPointerCancel: (_) => _titleBarPointerEnd(),
              child: const SizedBox.expand(),
            )
          : null,
      actions: appBarActions,
    );
  }

  // ---------------------------------------------------------------- 连接中
  Widget _buildConnectingCard(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('正在连接', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            controller.endPoint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          ClayButton(
            tone: ClayTone.subtle,
            height: 44,
            expand: true,
            onPressed: controller.leaveRoom,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 房间卡
  Widget _buildRoomCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final members = controller.members;
    final shown = members.take(4).toList();

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '房间',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              ClayIconButton(
                tooltip: '拉取正在播放',
                size: 34,
                icon: Icons.connect_without_contact_rounded,
                onPressed: _requestPlaybackSync,
              ),
              const SizedBox(width: 6),
              ClayIconButton(
                tooltip: '置顶公告',
                size: 34,
                icon: Icons.push_pin_outlined,
                onPressed: _editPin,
              ),
              const SizedBox(width: 6),
              ClayIconButton(
                tooltip: '复制邀请文案',
                size: 34,
                icon: Icons.ios_share_rounded,
                onPressed: _copyInvite,
              ),
              const SizedBox(width: 6),
              ClayIconButton(
                tooltip: '复制房间号',
                size: 34,
                icon: Icons.copy_rounded,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.room));
                  KazumiDialog.showToast(message: '已复制房间号', context: context);
                },
              ),
              const SizedBox(width: 6),
              ClayIconButton(
                tooltip: '退出房间',
                size: 34,
                icon: Icons.logout_rounded,
                onPressed: _confirmExitRoom,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            controller.room,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 3.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (controller.pinnedNotice != null) ...[
            const SizedBox(height: 10),
            _PinnedNoticeBar(
              text: controller.pinnedNotice!,
              by: controller.pinnedBy,
              onClear: () => controller.announcePin(''),
            ),
          ],
          if (controller.currentEpisode != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  controller.totalEpisodes == null
                      ? '正在看 第 ${controller.currentEpisode} 话'
                      : '正在看 第 ${controller.currentEpisode} 话 / 共 ${controller.totalEpisodes} 话',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in shown)
                      GestureDetector(
                        // 单击 = 敲一下；长按 = 屏蔽确认。
                        onTap: () => _nudgeMember(m.username),
                        onLongPress: () => _showMemberActions(m.username),
                        child: _MemberChip(
                          username: m.username,
                          isSelf: m.username == controller.username,
                          selfName: controller.username,
                          avatars: controller.avatarBytes,
                        ),
                      ),
                    if (members.length > shown.length)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '+${members.length - shown.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (members.isEmpty)
                      _MemberChip(
                        username: controller.username,
                        isSelf: true,
                        selfName: controller.username,
                        avatars: controller.avatarBytes,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.network_ping_rounded,
                label: '${controller.rtt} ms',
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 正在看
  Widget _buildNowPlayingCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasSource = controller.hasSource;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                hasSource ? '正在看' : '选择番剧',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasSource)
                TextButton(
                  onPressed: controller.clearSelection,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('换一部'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasSource) ...[
            _buildSearchField(context),
            const SizedBox(height: 12),
            _buildPosterDeck(context),
          ] else
            _buildSelectedSource(context),
          const SizedBox(height: 14),
          ClayCompleteButton(
            key: _startButtonKey,
            enabled: hasSource && controller.isInRoom,
            label: hasSource ? '开始一起看' : '先选一部番',
            onPressed: _startWatching,
          ),
          if (!hasSource)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '点海报挑播放来源，选好后这里会出现开始按钮',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索番剧',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.keyword.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  controller.clearSearch();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onChanged: controller.updateKeyword,
    );
  }

  /// 候补片单：收起时是一叠，点表头摊开成网格。
  Widget _buildPosterDeck(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
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
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${results.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _deckExpanded ? 0.5 : 0,
                duration: duration,
                curve: KazumiMotion.spring,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
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
                      borderRadius: immersiveBorderRadius,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = controller.selected!;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: NetworkImgLayer(
            src: item.images['large'] ?? '',
            width: 46,
            height: 64,
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (controller.sourceHint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '播放源：${controller.sourceHint}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 聊天
  Widget _buildChatCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final messages = controller.messages;
    final duration = KazumiMotion.scale(context, KazumiMotion.base);

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              KazumiHaptics.select();
              setState(() => _chatExpanded = !_chatExpanded);
            },
            child: Row(
              children: [
                Text(
                  '聊天',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${messages.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _chatExpanded ? 0.5 : 0,
                  duration: duration,
                  curve: KazumiMotion.spring,
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: KazumiMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _chatExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      SizedBox(
                        height: messages.isEmpty ? 84 : 168,
                        child: messages.isEmpty
                            ? Center(
                                child: Text(
                                  '说点什么吧',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _chatScrollController,
                                padding: EdgeInsets.zero,
                                itemCount: messages.length,
                                itemBuilder: (context, index) => _ChatBubble(
                                  message: messages[index],
                                  self: controller.username,
                                  avatars: controller.avatarBytes,
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      // 快捷反应：比打字快，也不占聊天记录的地盘。
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: SyncPlayReaction.palette.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final String emoji =
                                SyncPlayReaction.palette[index];
                            return ClayButton(
                              height: 36,
                              radius: 18,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              onPressed: () {
                                KazumiHaptics.select();
                                controller.sendReaction(emoji);
                              },
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 18),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 快捷短语：一起看时最常打的几句，点一下直接发。
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _quickPhrases.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final String phrase = _quickPhrases[index];
                            return ActionChip(
                              label: Text(
                                phrase,
                                style: theme.textTheme.labelMedium,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                KazumiHaptics.select();
                                controller.sendChatMessage(phrase);
                                _scrollChatToBottom();
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ClayIconButton(
                            size: 42,
                            tone: ClayTone.surface,
                            icon: Icons.emoji_emotions_outlined,
                            onPressed: () => showSyncPlayChatPicker(
                              context: context,
                              textController: _chatController,
                              onSticker: controller.sendSticker,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              style: theme.textTheme.bodyMedium,
                              minLines: 1,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '发送消息',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                              ),
                              onSubmitted: (_) => _sendChat(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ClayIconButton(
                            size: 42,
                            tone: ClayTone.accent,
                            icon: Icons.send_rounded,
                            onPressed: _sendChat,
                          ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 大厅
  Widget _buildNicknameField(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '昵称',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '房间内可见',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: controller.setUsername,
            onSubmitted: (_) => _showJoinField ? _joinRoom() : _createRoom(),
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                controller.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryCards(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = KazumiMotion.scale(context, KazumiMotion.base);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayButton(
          tone: ClayTone.accent,
          expand: true,
          height: 68,
          onPressed: _createRoom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('创建房间'),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '生成房号 $_createdRoom，等好友进来',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  // 跟着强调色粘土的前景色走：深色模式下这块是浅紫（配深墨），
                  // 浅色模式下是深紫（配白字），写死深墨会在浅色模式下消失。
                  color: ClayToneColors.of(context, ClayTone.accent)
                      .fg
                      .withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ClayButton(
          tone: ClayTone.subtle,
          expand: true,
          height: 68,
          onPressed: () {
            KazumiHaptics.select();
            setState(() => _showJoinField = !_showJoinField);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.login_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('加入房间'),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '输入好友分享的 8 位房号',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: colors.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: KazumiMotion.emphasized,
          alignment: Alignment.topCenter,
          child: _showJoinField
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: GlassPanel(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _roomController,
                          autofocus: true,
                          style: theme.textTheme.titleMedium?.copyWith(
                            letterSpacing: 3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '房间号',
                            prefixIcon: Icon(Icons.tag_rounded, size: 20),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _joinRoom(),
                        ),
                        const SizedBox(height: 10),
                        ClayButton(
                          expand: true,
                          height: 46,
                          onPressed: _joinRoom,
                          child: const Text('加入'),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (controller.recentRooms.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '最近进过',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  KazumiHaptics.select();
                  controller.clearRecentRooms();
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('清空'),
              ),
            ],
          ),
          for (final recent in controller.recentRooms)
            _RecentRoomTile(
              recent: recent,
              onTap: () => _rejoinRecent(recent),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 更多
  Widget _buildMoreCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = KazumiMotion.scale(context, KazumiMotion.base);
    final endPoints = [
      ...officialSyncPlayEndPoints,
      if (!officialSyncPlayEndPoints.contains(controller.endPoint))
        controller.endPoint,
    ];

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              KazumiHaptics.select();
              setState(() => _serverExpanded = !_serverExpanded);
            },
            child: Row(
              children: [
                Text(
                  '同步服务器',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.endPoint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _serverExpanded ? 0.5 : 0,
                  duration: duration,
                  curve: KazumiMotion.spring,
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: KazumiMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _serverExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      for (final endPoint in endPoints)
                        _EndPointTile(
                          endPoint: endPoint,
                          selected: endPoint == controller.endPoint,
                          result: controller.latency[endPoint],
                          onTap: () => controller.setEndPoint(endPoint),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        '房间成员必须使用同一台服务器',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // 聊天弹幕 / 进出提醒 / 自动跟播这些开关收进了右上角的
          // 「一起看设置」（_showSyncPlaySettings），这里只留一次性的
          // 服务器选择和排障工具，免得首屏被开关占满。
          ClayButton(
            height: 46,
            expand: true,
            onPressed: _showDiagnostics,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.monitor_heart_outlined, size: 18),
                SizedBox(width: 8),
                Text('网络诊断'),
              ],
            ),
          ),
        ],
      ),
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
  });

  final String text;
  final String by;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.push_pin_rounded,
            size: 16,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                if (by.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '— $by',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '取消置顶',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colors.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 大厅里的一条「最近进过的房间」。
class _RecentRoomTile extends StatelessWidget {
  const _RecentRoomTile({required this.recent, required this.onTap});

  final SyncPlayRecentRoom recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recent.room,
                      style: theme.textTheme.titleSmall?.copyWith(
                        letterSpacing: 2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (recent.title.isNotEmpty)
                      Text(
                        recent.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.username,
    required this.isSelf,
    required this.selfName,
    required this.avatars,
  });

  final String username;
  final bool isSelf;
  final String selfName;

  /// 远端成员的真实头像（用户名 -> 内存字节），查不到就退回首字色块。
  final Map<String, Uint8List> avatars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final String name = SyncPlayAvatar.displayName(username, selfName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelf ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SyncPlayAvatar(
            name: username,
            isSelf: isSelf,
            size: 22,
            radius: 11,
            remoteImage: avatars[username],
          ),
          const SizedBox(width: 6),
          Text(
            isSelf ? '$name (你)' : name,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isSelf ? colors.onPrimaryContainer : colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFF1A1C22).withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
  });

  final String endPoint;
  final bool selected;
  final SyncPlayLatencyResult? result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        KazumiHaptics.select();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 17,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                endPoint,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              result == null
                  ? '未测速'
                  : (result!.reachable ? '${result!.milliseconds} ms' : '连接失败'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: latencyColor ?? colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
