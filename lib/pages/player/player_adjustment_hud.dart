import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay.dart';
import 'package:XL/bean/widget/syncplay_activity_capsule.dart';
import 'package:XL/pages/player/controller/player_models.dart';
import 'package:XL/utils/format.dart';
import 'package:XL/utils/motion.dart';

/// 播放器里的浮层（OSD）：音量/亮度、拖动进度、倍速，以及一起看的动态条。
///
/// 三条硬约束：
/// 1. 颜色一律走 [ClayToneColors]，用户在设置里换了主色，这里跟着变；
/// 2. 不用 `BackdropFilter`——Impeller 在视频层上做 saveLayer 会原生崩溃
///    （flutter/flutter#185506），体积感靠渐变 + 阴影 + 0.5px 高光边；
/// 3. 进出场动效统一走 [PlayerOsdShell]，四处浮层手感一致。
class PlayerOsdShell extends StatelessWidget {
  const PlayerOsdShell({
    super.key,
    required this.visible,
    required this.child,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.width,
    this.slideOffset = -0.18,
    this.scaleFrom = 0.92,
    this.shadowBlur = 24,
    this.shadowOffset = const Offset(0, 10),
    this.duration,
  });

  final bool visible;
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? width;

  /// 收起时沿 Y 轴偏移的比例，负数表示往上缩。
  final double slideOffset;
  final double scaleFrom;

  /// 落影参数。小浮层（比如一起看的动态条）要把影收小一点，
  /// 否则 24px 的模糊挂在 30px 高的胶囊上会显得浮得很重。
  final double shadowBlur;
  final Offset shadowOffset;

  /// 传 null 走默认节奏，传 [Duration.zero] 表示关掉动效。
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    final ClayToneColors surface = ClayToneColors.of(context, ClayTone.surface);
    final Duration motion =
        duration ?? KazumiMotion.scale(context, KazumiMotion.base);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: motion,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : Offset(0, slideOffset),
          duration: motion,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: visible ? 1 : scaleFrom,
            duration: motion,
            // 不用 easeOutBack：那一下回弹放在浮层上显得跳，
            // 一起看的动态条要的是"滑进来、滑走"。
            curve: Curves.easeOutCubic,
            child: Container(
              width: width,
              padding: padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [surface.light, surface.dark],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  // 浅色模式下浮层是白底，白描边等于没有边；换一条极淡的墨线。
                  color: darkMode
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFF1A1C22).withValues(alpha: 0.07),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: darkMode ? 0.38 : 0.18,
                    ),
                    blurRadius: shadowBlur,
                    offset: shadowOffset,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形的粘土图标徽章，浮层里统一用它当「头像位」。
class _OsdBadge extends StatelessWidget {
  const _OsdBadge({
    required this.icon,
    required this.size,
    required this.colors,
  });

  final IconData icon;
  final double size;
  final ClayToneColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.light, colors.dark],
        ),
        borderRadius: BorderRadius.circular(size),
        boxShadow: [
          BoxShadow(
            color: colors.dark.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: colors.fg, size: size * 0.52),
    );
  }
}

/// 浮层里的小进度轨：底轨 + 已播放段 + 可选圆钮。
class _OsdTrack extends StatelessWidget {
  const _OsdTrack({
    required this.progress,
    required this.active,
    required this.inactive,
    this.height = 3,
    this.knob = false,
  });

  final double progress;
  final Color active;
  final Color inactive;
  final double height;
  final bool knob;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double filled = width * clamped;
        return SizedBox(
          height: knob ? height + 6 : height,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                width: double.infinity,
                height: height,
                decoration: BoxDecoration(
                  color: inactive,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
              Container(
                width: filled,
                height: height,
                decoration: BoxDecoration(
                  color: active,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
              if (knob)
                Positioned(
                  left: (filled - 5).clamp(0.0, (width - 10).clamp(0.0, width)),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: active,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum PlayerAdjustmentHudType {
  brightness,
  volume,
}

/// 音量 / 亮度：左侧图标徽章 + 粘土滑轨 + 右侧百分比。
class PlayerAdjustmentHud extends StatefulWidget {
  const PlayerAdjustmentHud({
    super.key,
    required this.visible,
    required this.type,
    required this.value,
    this.disableAnimations = false,
  });

  final bool visible;
  final PlayerAdjustmentHudType type;
  final double value;
  final bool disableAnimations;

  @override
  State<PlayerAdjustmentHud> createState() => _PlayerAdjustmentHudState();
}

class _PlayerAdjustmentHudState extends State<PlayerAdjustmentHud> {
  late PlayerAdjustmentHudType _displayType;
  late double _displayValue;
  bool _snapProgressOnNextBuild = false;

  @override
  void initState() {
    super.initState();
    _displayType = widget.type;
    _displayValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant PlayerAdjustmentHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      _displayType = widget.type;
      _displayValue = widget.value;
      if (!oldWidget.visible) {
        _snapProgressOnNextBuild = true;
      }
    }
  }

  double get _progress {
    return switch (_displayType) {
      PlayerAdjustmentHudType.brightness =>
        _displayValue.clamp(0.0, 1.0).toDouble(),
      PlayerAdjustmentHudType.volume =>
        (_displayValue / 100).clamp(0.0, 1.0).toDouble(),
    };
  }

  int get _percent => (_progress * 100).round();

  IconData get _icon {
    if (_displayType == PlayerAdjustmentHudType.brightness) {
      if (_percent <= 8) {
        return Icons.brightness_low_rounded;
      }
      if (_percent < 55) {
        return Icons.brightness_medium_rounded;
      }
      return Icons.brightness_high_rounded;
    }
    if (_percent <= 0) {
      return Icons.volume_off_rounded;
    }
    if (_percent < 45) {
      return Icons.volume_down_rounded;
    }
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ClayToneColors tone = ClayToneColors.of(
      context,
      _displayType == PlayerAdjustmentHudType.brightness
          ? ClayTone.info
          : ClayTone.accent,
    );
    final Color track = theme.colorScheme.onSurface.withValues(alpha: 0.14);
    final Duration motion = widget.disableAnimations
        ? Duration.zero
        : KazumiMotion.scale(context, KazumiMotion.fast);
    final bool snap = _snapProgressOnNextBuild;
    if (snap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _snapProgressOnNextBuild = false;
        });
      });
    }

    return PlayerOsdShell(
      visible: widget.visible,
      width: 216,
      radius: 999,
      duration: motion,
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      child: Row(
        children: [
          _OsdBadge(icon: _icon, size: 34, colors: tone),
          const SizedBox(width: 10),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _progress),
              duration: widget.disableAnimations || snap
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, animatedProgress, child) {
                return _OsdTrack(
                  progress: animatedProgress,
                  // 用 strong 而不是 light：浅色模式浮层是白底，
                  // 浅紫压在白色滑轨上根本看不出走到哪了。
                  active: tone.strong,
                  inactive: track,
                  height: 6,
                  knob: true,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$_percent%',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 拖动进度条 / 双击快进时的浮层：方向徽章 + 大号时间 + 偏移胶囊 + 进度轨。
class PlayerSeekHud extends StatefulWidget {
  const PlayerSeekHud({
    super.key,
    required this.visible,
    required this.currentPosition,
    required this.playerPosition,
    required this.duration,
    required this.direction,
    this.cancelPending = false,
    this.disableAnimations = false,
  });

  final bool visible;
  final Duration currentPosition;
  final Duration playerPosition;
  final Duration duration;
  final int direction;
  final bool cancelPending;
  final bool disableAnimations;

  @override
  State<PlayerSeekHud> createState() => _PlayerSeekHudState();
}

class _PlayerSeekHudState extends State<PlayerSeekHud> {
  late Duration _displayCurrentPosition;
  late Duration _displayPlayerPosition;
  late Duration _displayDuration;
  late int _displayDirection;
  late bool _displayCancelPending;
  bool _snapProgressOnNextBuild = false;

  @override
  void initState() {
    super.initState();
    _displayCurrentPosition = widget.currentPosition;
    _displayPlayerPosition = widget.playerPosition;
    _displayDuration = widget.duration;
    _displayDirection = widget.direction;
    _displayCancelPending = widget.cancelPending;
  }

  @override
  void didUpdateWidget(covariant PlayerSeekHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      _displayCurrentPosition = widget.currentPosition;
      _displayPlayerPosition = widget.playerPosition;
      _displayDuration = widget.duration;
      _displayDirection = widget.direction;
      _displayCancelPending = widget.cancelPending;
      if (!oldWidget.visible) {
        _snapProgressOnNextBuild = true;
      }
    }
  }

  int get _effectiveDirection {
    final positionDirection =
        _displayCurrentPosition.compareTo(_displayPlayerPosition);
    if (positionDirection != 0) {
      return positionDirection;
    }
    return _displayDirection;
  }

  bool get _isForward => _effectiveDirection >= 0;

  String get _offsetText {
    final offsetMs = (_displayCurrentPosition.inMilliseconds -
            _displayPlayerPosition.inMilliseconds)
        .abs();
    final sign = _isForward ? '+' : '-';
    return '$sign${durationToString(Duration(milliseconds: offsetMs))}';
  }

  double get _progress {
    final durationMs = _displayDuration.inMilliseconds;
    if (durationMs <= 0) {
      return 0;
    }
    return (_displayCurrentPosition.inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ClayToneColors tone = ClayToneColors.of(context, ClayTone.accent);
    final Duration motion = widget.disableAnimations
        ? Duration.zero
        : KazumiMotion.scale(context, KazumiMotion.base);
    final bool snap = _snapProgressOnNextBuild;
    final IconData icon = _displayCancelPending
        ? Icons.close_rounded
        : _isForward
            ? Icons.fast_forward_rounded
            : Icons.fast_rewind_rounded;
    if (snap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _snapProgressOnNextBuild = false;
        });
      });
    }

    final TextStyle timeStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return PlayerOsdShell(
      visible: widget.visible,
      width: 268,
      radius: 22,
      duration: motion,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OsdBadge(icon: icon, size: 40, colors: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayCancelPending
                            ? '松开取消'
                            : '${durationToString(_displayCurrentPosition)} / ${durationToString(_displayDuration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: timeStyle,
                      ),
                    ),
                    if (!_displayCancelPending) ...[
                      const SizedBox(width: 8),
                      _OffsetChip(text: _offsetText, colors: tone),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _progress),
                  duration: widget.disableAnimations || snap
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedProgress, child) {
                    return _OsdTrack(
                      progress: animatedProgress,
                      active: tone.strong,
                      inactive:
                          theme.colorScheme.onSurface.withValues(alpha: 0.14),
                      height: 3,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 偏移量的小胶囊，比如 `+15s`。
class _OffsetChip extends StatelessWidget {
  const _OffsetChip({required this.text, required this.colors});

  final String text;
  final ClayToneColors colors;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: colors.strong.withValues(alpha: darkMode ? 0.34 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: darkMode ? colors.light : colors.strong,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 长按倍速 / 快捷键改倍速时的小胶囊。
class PlayerSpeedHud extends StatelessWidget {
  const PlayerSpeedHud({
    super.key,
    required this.visible,
    required this.speed,
    this.disableAnimations = false,
  });

  final bool visible;
  final double speed;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ClayToneColors tone = ClayToneColors.of(context, ClayTone.accent);
    return PlayerOsdShell(
      visible: visible,
      radius: 999,
      duration: disableAnimations
          ? Duration.zero
          : KazumiMotion.scale(context, KazumiMotion.fast),
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OsdBadge(icon: Icons.bolt_rounded, size: 24, colors: tone),
          const SizedBox(width: 7),
          Text(
            '${speed.toStringAsFixed(1)}x',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一起看里别人进房 / 离房 / 暂停 / 继续 / 跳转 / 选集时的动态条。
///
/// 替掉原来的 `KazumiDialog.showToast`：SnackBar 贴在屏幕最底下，跟画面里的
/// 动作对不上，而且一进全屏就被底部控制条压住。
///
/// 贴着画面顶部显示（top 32，见 [PlayerItem] 里的摆放），并且做得尽量小：
/// 整条 28 高、昵称最长 90px。它盖在视频上，存在感越弱越好，
/// 停留 1.4 秒就收，进出场都是 easeOutCubic，不弹跳。
class SyncPlayActivityPill extends StatefulWidget {
  const SyncPlayActivityPill({
    super.key,
    required this.activity,
    this.disableAnimations = false,
  });

  final ValueListenable<SyncPlayActivity?> activity;
  final bool disableAnimations;

  @override
  State<SyncPlayActivityPill> createState() => _SyncPlayActivityPillState();
}

class _SyncPlayActivityPillState extends State<SyncPlayActivityPill> {
  static const Duration _hold = Duration(milliseconds: 1400);

  SyncPlayActivity? _shown;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_onActivity);
  }

  @override
  void didUpdateWidget(covariant SyncPlayActivityPill oldWidget) {
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
    _timer = Timer(_hold, () {
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
    // 尺寸是压着调的：整条只有 28 高（头像 20 + 上下各 4），
    // 比最早的 38 矮三成。它盖在画面上，越小越不挡戏。
    return PlayerOsdShell(
      visible: _visible,
      radius: 999,
      slideOffset: -0.35,
      scaleFrom: 0.94,
      shadowBlur: 16,
      shadowOffset: const Offset(0, 6),
      duration: widget.disableAnimations
          ? Duration.zero
          : KazumiMotion.scale(context, KazumiMotion.fast),
      padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
      child: SyncPlayActivityCapsule(activity: activity),
    );
  }
}
