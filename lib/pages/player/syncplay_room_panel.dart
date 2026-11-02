import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/empty_state_widget.dart';
import 'package:XL/bean/widget/syncplay_notice.dart';
import 'package:XL/bean/widget/syncplay_avatar.dart';
import 'package:XL/bean/widget/syncplay_sticker_view.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/pages/player/player_controller.dart';
import 'package:XL/pages/syncplay/syncplay_chat_picker.dart';
import 'package:XL/pages/syncplay/syncplay_sticker_packs.dart';
import 'package:XL/services/player/syncplay_client.dart';
import 'package:XL/services/player/syncplay_reaction.dart';
import 'package:XL/services/player/syncplay_room_signals.dart';
import 'package:XL/services/player/syncplay_sticker_message.dart';
import 'package:XL/services/storage/storage.dart';

/// 播放器侧栏里的「一起看」面板：房间成员 + 播放队列 + 聊天。
class SyncPlayRoomPanel extends StatefulWidget {
  const SyncPlayRoomPanel({
    super.key,
    required this.playerController,
    this.onChangeEpisode,
    this.episodeCount = 0,
  });

  final PlayerController playerController;

  /// 换集（换完会经播放器初始化广播给房间，别人跟着切）。
  /// 为 null 时队列只能看，不能点。
  final Future<void> Function(int episode)? onChangeEpisode;

  /// 当前线路一共几集；0 表示未知，不做越界检查。
  final int episodeCount;

  @override
  State<SyncPlayRoomPanel> createState() => _SyncPlayRoomPanelState();
}

class _SyncPlayRoomPanelState extends State<SyncPlayRoomPanel> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 上次自动滚到底时的消息条数。
  ///
  /// 面板会跟着成员状态、队列、输入框反复重建，如果每次 build 都
  /// `animateTo(maxScrollExtent)`，就等于一直在跟用户的滚动手势抢控制权。
  int _lastMessageCount = 0;

  /// 别人拖动进度条时我要不要跟着跳（= 设置项取反）。
  late bool _followRemoteSeek =
      GStorage.getSetting<bool>(SettingsKeys.syncPlayFollowRemoteSeek);

  void _toggleFollowRemoteSeek() {
    setState(() => _followRemoteSeek = !_followRemoteSeek);
    GStorage.putSetting<bool>(
      SettingsKeys.syncPlayFollowRemoteSeek,
      _followRemoteSeek,
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    // 滚动交给 build 里的「消息条数变了才滚」，这里不用再动一次。
    widget.playerController.sendSyncPlayChatMessage(text);
  }

  /// 点队列里的一集：本地切集，播放器初始化时会把新片源广播给房间。
  Future<void> _openEpisode(int episode) async {
    final onChangeEpisode = widget.onChangeEpisode;
    if (onChangeEpisode == null) return;
    if (episode == widget.playerController.currentEpisode) return;
    if (widget.episodeCount > 0 && episode > widget.episodeCount) {
      KazumiDialog.showToast(message: '第 $episode 话还没更新');
      return;
    }
    await onChangeEpisode(episode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Observer(builder: (context) {
      final syncplay = widget.playerController.syncplay;
      if (!syncplay.hasSession || syncplay.syncplayRoom.isEmpty) {
        return GeneralEmptyState(
          icon: Icons.groups_outlined,
          title: '还没有加入一起看',
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '在播放器菜单里创建或加入一个房间',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      }

      final members = syncplay.syncplayMembers;
      final messages = syncplay.chatMessages;
      final self = syncplay.syncplayController?.username ?? '';
      if (messages.length != _lastMessageCount) {
        _lastMessageCount = messages.length;
        _scrollToBottom();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemberStrip(
            members: members,
            self: self,
            avatarBytes: syncplay.avatarBytesNotifier,
          ),
          if (syncplay.pinnedNotice.isNotEmpty)
            _PinnedBar(text: syncplay.pinnedNotice),
          _SyncStatusStrip(
            drift: syncplay.driftBehind,
            mismatch: syncplay.hasSourceMismatch,
            onResync: () => widget.playerController.requestSyncPlaySync(
              doSeek: true,
            ),
            locked: !_followRemoteSeek,
            onToggleLock: _toggleFollowRemoteSeek,
          ),
          _PlayQueueStrip(
            queue: syncplay.playQueue,
            currentEpisode: widget.playerController.currentEpisode,
            episodeCount: widget.episodeCount,
            onOpenEpisode: _openEpisode,
            onToggleEpisode: syncplay.toggleQueueEpisode,
            onClearQueue: () => syncplay.setPlayQueue(const <int>[]),
          ),
          _RoomActionRow(playerController: widget.playerController),
          // 聊天记录
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      '说点什么吧',
                      style: PvText.rowSub(context),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _ChatBubble(
                          message: messages[index],
                          self: self,
                          avatarBytes: syncplay.avatarBytesNotifier,
                        ),
                  ),
          ),
          // 快捷反应
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: SyncPlayReaction.palette.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final String emoji = SyncPlayReaction.palette[index];
                return Tooltip(
                  message: '发一个 $emoji',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        widget.playerController.sendSyncPlayReaction(emoji),
                    child: Container(
                      width: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PvColors.searchFill(context),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 19),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 输入区：一颗白胶囊 + 一颗蓝圆钮，和一起看页底部的聊天条同一套。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(left: 14, right: 2),
                    decoration: BoxDecoration(
                      color: PvColors.card(context),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            textInputAction: TextInputAction.send,
                            style: PvText.rowTitle(context)
                                .copyWith(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '发送消息',
                              hintStyle: PvText.rowSub(context)
                                  .copyWith(fontSize: 14),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showSyncPlayChatPicker(
                            context: context,
                            textController: _chatController,
                            onSticker:
                                widget.playerController.sendSyncPlaySticker,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.emoji_emotions_outlined,
                              size: 20,
                              color: PvColors.ink3(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _send,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: PvColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// 房间成员：一颗白卡，一行头像 + 昵称，自己那颗描蓝边。
///
/// 原来是一排灰胶囊，和旁边的队列胶囊、操作胶囊长得一模一样，
/// 首屏看过去分不清哪块是「人」哪块是「片」。
class _MemberStrip extends StatelessWidget {
  const _MemberStrip({
    required this.members,
    required this.self,
    required this.avatarBytes,
  });

  final List<SyncPlayUserInfo> members;
  final String self;
  final ValueNotifier<Map<String, Uint8List>> avatarBytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        decoration: BoxDecoration(
          color: PvColors.card(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('房间成员', style: PvText.section(context)),
                const SizedBox(width: 6),
                Text('${members.length} 人', style: PvText.count(context)),
              ],
            ),
            const SizedBox(height: 9),
            if (members.isEmpty)
              Text('房间里只有你', style: PvText.rowSub(context))
            else
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final SyncPlayUserInfo member = members[index];
                    final bool isSelf = member.username == self;
                    final bool paused = member.paused ?? true;
                    final String shownName =
                        SyncPlayAvatar.displayName(member.username, self);
                    return Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: isSelf
                            ? PvColors.blue.withValues(alpha: 0.12)
                            : PvColors.searchFill(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<Map<String, Uint8List>>(
                            valueListenable: avatarBytes,
                            builder: (ctx, avatars, _) => SyncPlayAvatar(
                              name: member.username,
                              isSelf: isSelf,
                              size: 24,
                              radius: 12,
                              remoteImage: avatars[member.username],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isSelf ? '$shownName (你)' : shownName,
                            style: PvText.rowTitle(context).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelf ? PvColors.blue : null,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 暂停/播放只用一个 4px 圆点表示，别再塞一颗图标抢名字的位置。
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: paused
                                  ? PvColors.ink3(context)
                                  : PvColors.green,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 置顶公告：琥珀色一条，和一起看页里的公告同色。
class _PinnedBar extends StatelessWidget {
  const _PinnedBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final bool dark = PvColors.isDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A2E14) : const Color(0xFFFAEEDA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.push_pin_rounded,
              size: 13,
              color: dark ? const Color(0xFFF0C878) : const Color(0xFF854F0B),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color:
                      dark ? const Color(0xFFF0C878) : const Color(0xFF854F0B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 同步状态条：落后多少 / 是否同一个片源 / 一键重新同步。
///
/// 偏差取的是「最后一次成员状态推送时」的值，服务端在播放状态变化时会推
/// `Set.user`，所以它会跟着播放/暂停/拖动刷新，但不会像秒表那样每秒跳。
class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({
    required this.drift,
    required this.mismatch,
    required this.onResync,
    required this.locked,
    required this.onToggleLock,
  });

  /// 正数=自己落后；null 表示房间里只有自己。
  final Duration? drift;
  final bool mismatch;
  final VoidCallback onResync;

  /// 进度锁：开着就不跟别人的拖动，只跟播放/暂停。
  final bool locked;
  final VoidCallback onToggleLock;

  /// 超过这个偏差才值得提一句。1 秒以内的抖动属于正常范围，一直报反而烦。
  static const Duration _noticeThreshold = Duration(milliseconds: 800);

  String _driftLabel(Duration value) {
    final int ms = value.inMilliseconds.abs();
    final String amount = ms >= 1000
        ? '${(ms / 1000).toStringAsFixed(1)} 秒'
        : '$ms 毫秒';
    return value.isNegative ? '你超前 $amount' : '你落后 $amount';
  }

  @override
  Widget build(BuildContext context) {
    final Duration? value = drift;
    final bool off = value != null && value.abs() > _noticeThreshold;

    final (IconData, String, Color) state;
    if (mismatch) {
      state = (
        Icons.swap_horiz_rounded,
        '有人在看别的番或别的集',
        PvColors.red,
      );
    } else if (value == null) {
      state = (
        Icons.person_outline_rounded,
        '房间里只有你',
        PvColors.ink3(context),
      );
    } else if (off) {
      state = (Icons.sync_problem_rounded, _driftLabel(value), PvColors.red);
    } else {
      state = (
        Icons.check_circle_outline_rounded,
        '进度已对齐',
        PvColors.green,
      );
    }

    // 一条 44 高的浅色条：状态用底色区分（对齐=浅绿、落后=浅红），
    // 比一行灰字更容易在播放器里一眼扫到。
    final bool ok = !mismatch && value != null && !off;
    final Color tint = mismatch || off
        ? PvColors.red.withValues(alpha: 0.10)
        : (ok
            ? PvColors.green.withValues(alpha: 0.10)
            : PvColors.ink3(context).withValues(alpha: 0.08));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(state.$1, size: 16, color: state.$3),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                state.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: state.$3,
                ),
              ),
            ),
            if (off)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onResync,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: PvColors.red.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    '重新同步',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PvColors.red,
                    ),
                  ),
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleLock,
              child: Tooltip(
                message: locked ? '进度已锁定：别人拖动不会拽走你' : '跟随房间进度',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 17,
                    color: locked ? PvColors.blue : PvColors.ink3(context),
                  ),
                ),
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
    required this.avatarBytes,
  });

  final SyncPlayChatMessage message;

  /// 本地用户名，用来判断「这是不是我发的」并取对应的头像/昵称。
  final String self;

  /// 远端成员的真实头像通知器（用户名 -> 内存字节），查不到就退回首字色块。
  ///
  /// 用 [ValueListenableBuilder] 局部监听：头像往往是「进房后单独传来的一条
  /// 协议」，不会写进聊天记录，所以得让头像自己能触发重建。
  final ValueNotifier<Map<String, Uint8List>> avatarBytes;

  @override
  Widget build(BuildContext context) {
    if (message.username.isEmpty) {
      return SyncPlayNotice(
        text: message.message,
        highlight: SyncPlayNotice.isJoin(message.message),
      );
    }
    final bool mine = !message.fromRemote;
    final bool isSelf = message.username == self;
    final String name = SyncPlayAvatar.displayName(message.username, self);
    // 头像走单独的协议通道传来，不写进聊天记录，所以用通知器局部监听，
    // 让「对方头像到了」能单独触发这一块重建，而不用等下一条聊天消息。
    Widget avatar({required double size, required double radius}) =>
        ValueListenableBuilder<Map<String, Uint8List>>(
          valueListenable: avatarBytes,
          builder: (ctx, avatars, _) => SyncPlayAvatar(
            name: message.username,
            isSelf: isSelf,
            size: size,
            radius: radius,
            remoteImage: avatars[message.username],
          ),
        );
    // 反应只画一个 emoji，不套气泡、不加「说」的排版，否则看起来像句话。
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
                avatar(size: 24, radius: 12),
                const SizedBox(width: 6),
              ],
              Text(message.message, style: const TextStyle(fontSize: 26)),
            ],
          ),
        ),
      );
    }
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
                avatar(size: 32, radius: 16),
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
                        style: PvText.rowSub(context).copyWith(fontSize: 11.5),
                      ),
                    ),
                  SyncPlayStickerView(
                    sticker: SyncPlayStickerStore.instance.resolveMessage(
                      stickerMessage.packId,
                      stickerMessage.stickerId,
                      stickerMessage.url,
                    ),
                    size: 92,
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
        color: mine ? PvColors.blue : PvColors.card(context),
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
              style: PvText.rowSub(context).copyWith(fontSize: 11.5),
            ),
          Text(
            message.message,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: mine ? Colors.white : PvColors.ink(context),
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
            avatar(size: 32, radius: 16),
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
          avatar(size: 32, radius: 16),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// 房间共享的播放队列：一排集号，点一下全房间切过去，× 掉就移出队列。
///
/// 队列本身不限制谁改（房间就几个人，排片是低冲突操作），点谁算谁。
/// 集号上限由 [episodeCount] 兜住：越界的集点下去只会让播放器报错，
/// 不如在入口处就拦住。
class _PlayQueueStrip extends StatelessWidget {
  const _PlayQueueStrip({
    required this.queue,
    required this.currentEpisode,
    required this.episodeCount,
    required this.onOpenEpisode,
    required this.onToggleEpisode,
    required this.onClearQueue,
  });

  final ValueListenable<List<int>> queue;
  final int currentEpisode;
  final int episodeCount;
  final Future<void> Function(int episode) onOpenEpisode;
  final Future<void> Function(int episode) onToggleEpisode;
  final Future<void> Function() onClearQueue;

  /// 「+」要加的那一集：接在队尾后面，队空就从当前集往后数。
  int _nextEpisode(List<int> items) {
    final int last = items.isEmpty ? currentEpisode : items.last;
    return last + 1;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<int>>(
      valueListenable: queue,
      builder: (context, items, _) {
        final int next = _nextEpisode(items);
        final bool canAdd = episodeCount <= 0 || next <= episodeCount;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 8, 8, 10),
            decoration: BoxDecoration(
              color: PvColors.card(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('播放队列', style: PvText.section(context)),
                    const SizedBox(width: 6),
                    Text(
                      items.isEmpty ? '还没排片' : '${items.length} 集',
                      style: PvText.count(context),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      _QueueIconButton(
                        icon: Icons.playlist_remove_rounded,
                        tooltip: '清空队列',
                        onTap: () => onClearQueue(),
                      ),
                    _QueueIconButton(
                      icon: Icons.add_rounded,
                      tooltip: canAdd ? '把第 $next 话排进队列' : '已经排到最后一集了',
                      onTap: canAdd ? () => onToggleEpisode(next) : null,
                    ),
                  ],
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final int episode = items[index];
                        final bool isCurrent = episode == currentEpisode;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onOpenEpisode(episode),
                          child: Container(
                            padding: const EdgeInsets.only(left: 10, right: 3),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? PvColors.blue
                                  : PvColors.searchFill(context),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '第 $episode 话',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrent
                                        ? Colors.white
                                        : PvColors.ink(context),
                                  ),
                                ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => onToggleEpisode(episode),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: isCurrent
                                          ? Colors.white
                                          : PvColors.ink3(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 队列卡右上角那颗小图标：24 见方，别用 IconButton，会把卡片顶高。
class _QueueIconButton extends StatelessWidget {
  const _QueueIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? PvColors.ink3(context).withValues(alpha: 0.4)
                : PvColors.blue,
          ),
        ),
      ),
    );
  }
}

/// 房间操作行：等我一下 / 回退 / 投票。
///
/// 这三个都是「一说全房间一起动」的动作，所以放在聊天框上面一行，
/// 而不是塞进菜单里 —— 卡住的时候没空翻菜单。
class _RoomActionRow extends StatelessWidget {
  const _RoomActionRow({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _chip(
            context,
            icon: Icons.hourglass_bottom_rounded,
            label: '等我一下',
            tooltip: '让全房间暂停 30 秒，到点自动继续',
            onTap: () => playerController.requestSyncPlayStall(),
          ),
          _chip(
            context,
            icon: Icons.replay_10_rounded,
            label: '回退 15s',
            tooltip: '全房间一起往回退 15 秒',
            onTap: () => playerController
                .seekForRoom(const Duration(seconds: -15)),
          ),
          _chip(
            context,
            icon: Icons.replay_30_rounded,
            label: '回退 30s',
            tooltip: '全房间一起往回退 30 秒',
            onTap: () => playerController
                .seekForRoom(const Duration(seconds: -30)),
          ),
          _VoteMenuButton(playerController: playerController),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: PvColors.searchFill(context),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: PvColors.blue),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PvColors.ink(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 投票入口：暂停 / 继续 / 换到下一集。
class _VoteMenuButton extends StatelessWidget {
  const _VoteMenuButton({required this.playerController});

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(PvColors.card(context)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.pause_rounded, size: 18),
          onPressed: () => playerController
              .startSyncPlayVote(SyncPlayVoteKind.pause),
          child: const Text('投票：暂停一下'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow_rounded, size: 18),
          onPressed: () => playerController
              .startSyncPlayVote(SyncPlayVoteKind.resume),
          child: const Text('投票：继续播放'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.skip_next_rounded, size: 18),
          onPressed: () => playerController.startSyncPlayVote(
            SyncPlayVoteKind.episode,
            episode: playerController.currentEpisode + 1,
          ),
          child: const Text('投票：换到下一集'),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: '发起投票（过半执行，房主可否决）',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: PvColors.searchFill(context),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.how_to_vote_rounded,
                  size: 14,
                  color: PvColors.blue,
                ),
                const SizedBox(width: 5),
                Text(
                  '投票',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PvColors.ink(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
