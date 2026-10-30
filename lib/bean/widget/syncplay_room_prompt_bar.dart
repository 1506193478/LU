import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:XL/services/player/syncplay_room_prompts.dart';

/// 播放器顶部那条「需要你回应一下」的横幅。
///
/// 三种状态共用一条，同一时间只显示一个（优先级：等我一下 > 投票 > 片源）：
/// - 等我一下：全房间暂停中，显示倒计时，可以提前「继续」；
/// - 投票：显示票数和倒计时，可以「同意 / 反对」；
/// - 片源不一致：同插件时可以一键切到对方的线路。
///
/// 它盖在画面上，所以做得尽量扁（40 高），颜色跟主题走，不抢戏。
class SyncPlayRoomPromptBar extends StatefulWidget {
  const SyncPlayRoomPromptBar({
    super.key,
    required this.stall,
    required this.vote,
    required this.sourceMismatch,
    required this.memberCount,
    required this.onCancelStall,
    required this.onVote,
    required this.onDismissVote,
    required this.onSwitchSource,
    required this.onDismissSource,
    this.disableAnimations = false,
  });

  final ValueListenable<SyncPlayStallState?> stall;
  final ValueListenable<SyncPlayVoteState?> vote;
  final ValueListenable<SyncPlaySourceMismatch?> sourceMismatch;
  final int memberCount;

  final VoidCallback onCancelStall;
  final void Function(bool agree) onVote;
  final VoidCallback onDismissVote;
  final void Function(int road) onSwitchSource;
  final VoidCallback onDismissSource;

  final bool disableAnimations;

  @override
  State<SyncPlayRoomPromptBar> createState() => _SyncPlayRoomPromptBarState();
}

class _SyncPlayRoomPromptBarState extends State<SyncPlayRoomPromptBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 倒计时是「按秒刷」的：状态里存的是结束时刻，界面自己数。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.stall.value == null && widget.vote.value == null) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.stall,
        widget.vote,
        widget.sourceMismatch,
      ]),
      builder: (context, _) {
        final Widget? content = _buildContent(context);
        return AnimatedSwitcher(
          duration: widget.disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: content ?? const SizedBox.shrink(),
        );
      },
    );
  }

  Widget? _buildContent(BuildContext context) {
    final SyncPlayStallState? stall = widget.stall.value;
    if (stall != null) {
      return _pill(
        context,
        key: 'stall',
        icon: Icons.hourglass_bottom_rounded,
        text: '${_who(stall.by)} 让大家等一下 · ${stall.remainingSeconds}s',
        actions: [
          _action(
            context,
            label: '继续',
            onPressed: widget.onCancelStall,
            emphasized: true,
          ),
        ],
      );
    }

    final SyncPlayVoteState? vote = widget.vote.value;
    if (vote != null) {
      final int total = widget.memberCount <= 0
          ? vote.yesCount + vote.noCount
          : widget.memberCount;
      return _pill(
        context,
        key: 'vote',
        icon: Icons.how_to_vote_rounded,
        text: '投票：${vote.title} · ${vote.yesCount}/$total 同意 · '
            '${vote.remainingSeconds}s',
        actions: [
          _action(
            context,
            label: '同意',
            onPressed: () => widget.onVote(true),
            emphasized: true,
          ),
          _action(context, label: '反对', onPressed: () => widget.onVote(false)),
          _action(
            context,
            label: '忽略',
            onPressed: widget.onDismissVote,
            muted: true,
          ),
        ],
      );
    }

    final SyncPlaySourceMismatch? mismatch = widget.sourceMismatch.value;
    if (mismatch != null) {
      final bool canSwitch = mismatch.samePlugin;
      return _pill(
        context,
        key: 'source',
        icon: Icons.compare_arrows_rounded,
        text: canSwitch
            ? '${_who(mismatch.by)} 在看「${mismatch.info.roadName}」，你不是这条线路'
            : '${_who(mismatch.by)} 用的是 ${mismatch.info.pluginName} 插件，和你不是同一个源',
        actions: [
          if (canSwitch)
            _action(
              context,
              label: '切过去',
              onPressed: () => widget.onSwitchSource(mismatch.info.road),
              emphasized: true,
            ),
          _action(
            context,
            label: '知道了',
            onPressed: widget.onDismissSource,
            muted: true,
          ),
        ],
      );
    }

    return null;
  }

  String _who(String name) => name.isEmpty ? '房间成员' : name;

  Widget _pill(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String text,
    required List<Widget> actions,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color background = dark
        ? const Color(0xE6242630)
        : const Color(0xF2FFFFFF);
    final Color foreground =
        dark ? const Color(0xFFEDEEF3) : const Color(0xFF1D1E24);

    return Center(
      key: ValueKey<String>(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: background,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
    bool muted = false,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor:
              emphasized ? colors.primary : Colors.transparent,
          foregroundColor:
              emphasized ? colors.onPrimary : (muted ? null : colors.primary),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
