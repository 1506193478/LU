import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/utils/motion.dart';

/// 一起看的「谁做了什么」胶囊，播放器画面里和一起看页顶部共用这一份。
///
/// 尺寸是压着调的：默认整条只有 28 高（头像 20 + 上下各 4），它盖在内容上，
/// 存在感越弱越好；进出场都走 easeOutCubic，不留弹跳，停留 1.4 秒就收。
class SyncPlayActivityCapsule extends StatelessWidget {
  const SyncPlayActivityCapsule({
    super.key,
    required this.activity,
    this.avatarSize = 20,
    this.fontSize = 12,
    this.nameMaxWidth = 90,
  });

  final SyncPlayActivity activity;

  /// 头像直径；整条胶囊的高度 = 它 + 上下内边距。
  final double avatarSize;
  final double fontSize;

  /// 昵称最长多少，超出省略号。房间昵称可能很长，不收着会把整条撑宽。
  final double nameMaxWidth;

  /// 昵称哈希到主题色相上：同一个昵称颜色固定，换主色时整组一起变。
  static Color avatarColor(ColorScheme scheme, String name) {
    final int hash = name.isEmpty
        ? 0
        : name.codeUnits.fold<int>(
            7, (acc, unit) => (acc * 31 + unit) & 0x7fffffff);
    final HSLColor base = HSLColor.fromColor(scheme.primary);
    return base
        .withHue((base.hue + (hash % 360)) % 360)
        .withSaturation(base.saturation.clamp(0.35, 0.75))
        .withLightness(0.46)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ClayToneColors surface = ClayToneColors.of(context, ClayTone.surface);
    final Color avatarBg = avatarColor(scheme, activity.username);
    final Color avatarFg =
        avatarBg.computeLuminance() > 0.42 ? const Color(0xFF16121F) : Colors.white;
    final String initial = activity.username.isEmpty
        ? '?'
        : activity.username.characters.first.toUpperCase();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
          child: Text(
            initial,
            style: theme.textTheme.labelSmall?.copyWith(
              color: avatarFg,
              fontSize: fontSize - 1,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: nameMaxWidth),
          child: Text(
            activity.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          activity.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: fontSize,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: avatarSize - 4,
          height: avatarSize - 4,
          decoration: BoxDecoration(
            color: surface.dark,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            activity.icon,
            size: fontSize - 1,
            color: surface.fg.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// 播放器之外（一起看页）用的那条动态条。
///
/// 监听一个 [SyncPlayActivity] 通知源，有事件就贴着页面顶部弹一条，
/// 停 [hold] 之后自己淡出。外观跟播放器里的胶囊一致，只是不带播放器的
/// 落影参数。
class SyncPlayActivityToast extends StatefulWidget {
  const SyncPlayActivityToast({
    super.key,
    required this.activity,
    this.hold = const Duration(milliseconds: 1400),
    this.disableAnimations = false,
  });

  final ValueListenable<SyncPlayActivity?> activity;

  /// 停留多久后收起。
  final Duration hold;

  final bool disableAnimations;

  @override
  State<SyncPlayActivityToast> createState() => _SyncPlayActivityToastState();
}

class _SyncPlayActivityToastState extends State<SyncPlayActivityToast> {
  SyncPlayActivity? _shown;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_onActivity);
  }

  @override
  void didUpdateWidget(covariant SyncPlayActivityToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.removeListener(_onActivity);
      widget.activity.addListener(_onActivity);
    }
  }

  @override
  void dispose() {
    widget.activity.removeListener(_onActivity);
    _timer?.cancel();
    super.dispose();
  }

  void _onActivity() {
    final SyncPlayActivity? next = widget.activity.value;
    if (next == null || !mounted) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _shown = next;
      _visible = true;
    });
    _timer = Timer(widget.hold, () {
      if (!mounted) {
        return;
      }
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SyncPlayActivity? activity = _shown;
    if (activity == null) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    final ClayToneColors surface = ClayToneColors.of(context, ClayTone.surface);
    final Duration motion = widget.disableAnimations
        ? Duration.zero
        : KazumiMotion.scale(context, KazumiMotion.fast);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: motion,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : const Offset(0, -0.35),
          duration: motion,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: _visible ? 1 : 0.94,
            duration: motion,
            curve: Curves.easeOutCubic,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [surface.light, surface.dark],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  // 浅色模式下面板是白的，白描边等于没边；换一条极淡的墨线。
                  color: darkMode
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF1A1C22).withValues(alpha: 0.07),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: darkMode ? 0.30 : 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SyncPlayActivityCapsule(activity: activity),
            ),
          ),
        ),
      ),
    );
  }
}
