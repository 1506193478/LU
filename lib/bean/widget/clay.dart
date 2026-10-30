import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:XL/utils/immersive_theme.dart';
import 'package:XL/utils/motion.dart';

/// 粘土材质的语义色。
enum ClayTone {
  /// 普通操作：深灰粘土，压得住背景。
  surface,

  /// 主操作：强调色粘土，一屏最多一个。
  accent,

  /// 危险操作：离房、删除。
  danger,

  /// 次级操作：比 surface 更薄一点，用于并列的第二个选项。
  subtle,

  /// 成功：添加、完成、已连接。
  success,

  /// 信息：跳转、上传这类中性但需要注意的动作。
  info,
}

/// 一个色调在某亮度下的颜色：左上受光、右下背光、块上的文字色，外加一个实色。
///
/// 深色模式用 [clayLight]/[clayDark] 这套偏蓝的深灰；浅色模式另给一套，
/// 否则浅色主题下会突然冒出一堆黑块。
class ClayToneColors {
  const ClayToneColors({
    required this.light,
    required this.dark,
    required this.fg,
    Color? strong,
  }) : strong = strong ?? fg;

  /// 受光端（渐变左上）。
  final Color light;

  /// 背光端（渐变右下）。
  final Color dark;

  /// 压在 [light]..[dark] 之间的文字 / 图标色。
  final Color fg;

  /// 需要一个「实色」时用：进度轨的已播放段、封面上的选中遮罩、
  /// 染色底上的强调文字。这些地方要的是一眼看得见，不是柔和的粘土面。
  final Color strong;

  /// 按当前主题取色。
  ///
  /// 四个语义色（accent / danger / success / info）全部从 [ColorScheme] 推，
  /// 用户在设置里换了主色，整套粘土控件和播放器小标识会一起变色；
  /// surface / subtle 保持中性灰阶不动，免得跟封面抢戏。
  static ClayToneColors of(BuildContext context, ClayTone tone) {
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    final ColorScheme scheme = theme.colorScheme;
    return switch (tone) {
      ClayTone.accent =>
        ClayToneColors.fromSeed(scheme.primary, darkMode: darkMode),
      ClayTone.danger =>
        ClayToneColors.fromSeed(scheme.error, darkMode: darkMode),
      ClayTone.success =>
        ClayToneColors.fromSeed(scheme.tertiary, darkMode: darkMode),
      ClayTone.info =>
        ClayToneColors.fromSeed(scheme.secondary, darkMode: darkMode),
      ClayTone.subtle => darkMode
          ? const ClayToneColors(
              light: Color(0xFF1F222A),
              dark: Color(0xFF14161B),
              fg: Color(0xFFD6D6DD),
            )
          : const ClayToneColors(
              light: Color(0xFFF7F8FB),
              dark: Color(0xFFE3E5EC),
              fg: Color(0xFF3A3B44),
            ),
      ClayTone.surface => darkMode
          ? const ClayToneColors(
              light: clayLight,
              dark: clayDark,
              fg: Color(0xFFEDEDF2),
            )
          : const ClayToneColors(
              light: Color(0xFFFFFFFF),
              dark: Color(0xFFE9EAF0),
              fg: Color(0xFF1B1C22),
            ),
    };
  }

  /// 从一个基色推粘土色：左上受光、右下背光，块上永远配深墨字。
  ///
  /// 关键决定：**粘土块一律是浅色块 + 深墨字**。深色模式的 `primary` 本来就是
  /// tone-80（浅紫），浅色模式的是 tone-40（中紫）——后者配白字只有 3.8:1，
  /// 正是「浅色模式看不清字」的根子，所以浅色模式先把它往白里混成浅紫，
  /// 再走同一套「浅块 + 深墨」的规则，两种模式的观感也就统一了。
  ///
  /// [strong] 是同一色相里够饱和的那一支，给进度轨、选中遮罩这类
  /// 「必须一眼看见」的填充用。
  factory ClayToneColors.fromSeed(Color seed, {required bool darkMode}) {
    if (darkMode) {
      return ClayToneColors(
        light: Color.lerp(seed, Colors.white, 0.16)!,
        dark: Color.lerp(seed, Colors.black, 0.20)!,
        // 深色模式的语义色理论上都是浅色，留一道亮度兜底防止自定义配色翻车。
        fg: seed.computeLuminance() > 0.30
            ? const Color(0xFF16121F)
            : Colors.white,
        strong: Color.lerp(seed, Colors.white, 0.04)!,
      );
    }
    // 0.55：再淡一点（0.62 以上）主操作按钮在浅色页面上就像禁用态了，
    // 再深一点白字规则又得推翻。这一档深墨字仍有 9:1 左右。
    final Color pastel = Color.lerp(seed, Colors.white, 0.55)!;
    return ClayToneColors(
      light: Color.lerp(pastel, Colors.white, 0.12)!,
      dark: Color.lerp(pastel, Colors.black, 0.12)!,
      fg: const Color(0xFF16121F),
      strong: Color.lerp(seed, Colors.black, 0.06)!,
    );
  }

  /// 落地阴影的颜色。浅色下用冷灰，用纯黑会脏。
  Color get shadow => light.computeLuminance() > 0.5
      ? const Color(0xFF8A90A0)
      : Colors.black;

  /// 用这个色调染一块底，保证正文色（`onSurface`）压上去还看得清。
  ///
  /// 和 [fg] 是两套东西：[fg] 是「压在粘土块上的字」，而这里只取一点点色相，
  /// 底仍然是跟主题同向的浅/深面，所以正文、次要文字都能直接盖上去——
  /// 聊天气泡、提示胶囊、胶囊状标签都该用它，而不是半透明的白色。
  Color tintSurface(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return theme.brightness == Brightness.dark
        ? Color.lerp(scheme.surfaceContainerHigh, dark, 0.42)!
        // 浅色下 light 已经是浅紫，混 0.16 刚好能看出色相又不吃掉对比度。
        : Color.lerp(scheme.surface, light, 0.16)!;
  }
}

/// 粘土按钮。
///
/// 粘土的观感来自三件事：**左上亮、右下暗的渐变**（受光方向）、
/// **柔和的落地阴影**（厚度）、**按下去时渐变反向 + 下沉 2px**
/// （被压扁）。
///
/// Flutter 的 `BoxShadow` 不支持 inset，所以不做真内阴影；用渐变 + 0.5px
/// 描边就能得到足够的体积感，单帧开销也比自定义 Painter 小。
class ClayButton extends StatefulWidget {
  const ClayButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tone = ClayTone.surface,
    this.expand = false,
    this.height = 50,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.haptic = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ClayTone tone;
  final bool expand;
  final double height;
  final double radius;
  final EdgeInsets padding;
  final bool haptic;

  bool get enabled => onPressed != null;

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ClayToneColors tone = ClayToneColors.of(context, widget.tone);
    final Color light = tone.light;
    final Color dark = tone.dark;
    final Color fg = tone.fg;
    final bool enabled = widget.enabled;
    final bool active = _pressed && enabled;
    final Duration duration = KazumiMotion.scale(
      context,
      active ? KazumiMotion.instant : KazumiMotion.base,
    );

    final Widget content = AnimatedContainer(
      duration: duration,
      curve: active ? KazumiMotion.emphasized : KazumiMotion.spring,
      height: widget.height,
      width: widget.expand ? double.infinity : null,
      transform: Matrix4.translationValues(0, active ? 2 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active ? [dark, light] : [light, dark],
        ),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 0.04 : 0.10),
          width: 0.5,
        ),
        boxShadow: active
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: widget.tone == ClayTone.accent ? 0.30 : 0.42,
                  ),
                  blurRadius: widget.tone == ClayTone.accent ? 20 : 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(
        padding: widget.padding,
        child: Center(
          widthFactor: widget.expand ? null : 1,
          child: DefaultTextStyle(
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.2,
            ),
            child: IconTheme(
              data: IconThemeData(color: fg, size: 19),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) KazumiHaptics.tap();
                widget.onPressed!();
              }
            : null,
        child: Opacity(opacity: enabled ? 1 : 0.42, child: content),
      ),
    );
  }
}

/// 方形粘土图标按钮，用于「复制房号」这类单一动作。
class ClayIconButton extends StatefulWidget {
  const ClayIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.size = 40,
    this.tone = ClayTone.surface,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final double size;
  final ClayTone tone;
  final String? tooltip;

  @override
  State<ClayIconButton> createState() => _ClayIconButtonState();
}

class _ClayIconButtonState extends State<ClayIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final bool active = _pressed && enabled;
    final ClayToneColors tone = ClayToneColors.of(context, widget.tone);
    final Color light = tone.light;
    final Color dark = tone.dark;
    final Color fg = tone.fg;

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: enabled
          ? () {
              KazumiHaptics.tap();
              widget.onPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: KazumiMotion.scale(
          context,
          active ? KazumiMotion.instant : KazumiMotion.base,
        ),
        curve: active ? KazumiMotion.emphasized : KazumiMotion.spring,
        width: widget.size,
        height: widget.size,
        transform: Matrix4.translationValues(0, active ? 2 : 0, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active ? [dark, light] : [light, dark],
          ),
          borderRadius: BorderRadius.circular(widget.size * 0.32),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.04 : 0.10),
            width: 0.5,
          ),
          boxShadow: active
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Icon(widget.icon, size: widget.size * 0.46, color: fg),
      ),
    );

    button = Opacity(opacity: enabled ? 1 : 0.42, child: button);
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 玻璃面板：承载内容的容器。
///
/// [blur] 大于 0 时才会真的加 `BackdropFilter`。**默认不加**——这一页背后
/// 没有滚动的内容可模糊，加了只是白耗 GPU；视觉上的"玻璃感"由半透明填充 +
/// 0.5px 高光边 + 顶部微亮渐变表达。只有底部导航那种有内容从下面滚过去的
/// 地方才值得开真模糊。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.blur = 0,
    this.opacity = 0.06,
    this.borderOpacity = 0.10,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blur;
  final double opacity;
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    // 深色：白玻璃薄薄一层，层次靠模糊底衬出来。
    // 浅色：白玻璃必须够厚，否则压在浅背景上等于没放；同时换成冷灰描边 +
    // 一层很浅的落影，面板边界才立得住，正文（深色）也才有干净的底。
    final Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Colors.white.withValues(alpha: opacity + 0.02),
                  Colors.white.withValues(alpha: opacity * 0.6),
                ]
              : [
                  Colors.white.withValues(alpha: 0.88),
                  Colors.white.withValues(alpha: 0.64),
                ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: borderOpacity)
              : const Color(0xFF1A1C22).withValues(alpha: 0.06),
          width: 0.5,
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1A1C22).withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (blur <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: panel,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      ),
    );
  }
}

/// 完成反馈按钮：按下先收缩成圆，再从圆心迸发一圈粒子，然后才执行动作。
///
/// 用在「开始一起看」「播放」这类**有明确结果**的动作上。粒子走完（720ms）
/// 才回调，让"完成"这件事有一个收尾，而不是点了就走。
class ClayCompleteButton extends StatefulWidget {
  const ClayCompleteButton({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
    this.height = 52,
    this.tone = ClayTone.accent,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final double height;
  final ClayTone tone;

  @override
  State<ClayCompleteButton> createState() => _ClayCompleteButtonState();
}

class _ClayCompleteButtonState extends State<ClayCompleteButton> {
  bool _morphed = false;
  bool _burst = false;

  void _run() {
    if (!widget.enabled || _morphed) return;
    KazumiHaptics.success();
    setState(() {
      _morphed = true;
      _burst = true;
    });
  }

  void _onBurstDone() {
    widget.onPressed?.call();
    // 动作已经跑完（通常是换页），把状态收回来，返回时是干净的按钮。
    if (!mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _burst = false;
        _morphed = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 禁用时换成哑光粘土，不然一个不能点的按钮还在抢注意力。
    final ClayToneColors tone = ClayToneColors.of(
      context,
      widget.enabled ? widget.tone : ClayTone.surface,
    );
    final Color light = tone.light;
    final Color dark = tone.dark;
    final Color fg = widget.enabled
        ? tone.fg
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    final Duration morph = KazumiMotion.scale(context, KazumiMotion.slow);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double fullWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Center(
          child: SizedBox(
            height: widget.height,
            width: _morphed ? widget.height : fullWidth,
            child: GestureDetector(
              onTap: _run,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: morph,
                    curve: KazumiMotion.emphasized,
                    height: widget.height,
                    width: _morphed ? widget.height : fullWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [light, dark],
                      ),
                      borderRadius: BorderRadius.circular(
                        _morphed ? widget.height / 2 : 16,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _morphed
                          ? Icon(Icons.check_rounded, size: 24, color: fg)
                          : Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: fg,
                              ),
                            ),
                    ),
                  ),
                  if (_burst)
                    Positioned.fill(
                      child: _ParticleBurst(
                        color: light,
                        onDone: _onBurstDone,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 从中心向外飞散并消失的一圈粒子。
class _ParticleBurst extends StatefulWidget {
  const _ParticleBurst({required this.color, required this.onDone});

  final Color color;
  final VoidCallback onDone;

  @override
  State<_ParticleBurst> createState() => _ParticleBurstState();
}

class _ParticleBurstState extends State<_ParticleBurst>
    with SingleTickerProviderStateMixin {
  static const int _count = 14;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );
  late final List<_Particle> _particles = List.generate(_count, (i) {
    final double angle = (i / _count) * 6.2831853;
    return _Particle(
      angle: angle + (i % 3) * 0.06,
      distance: 42 + (i % 4) * 9,
      size: i % 3 == 0 ? 6 : 4.5,
    );
  });

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        // 先快后慢：起步冲出去，尾段减速消散。
        final double eased = 1 - (1 - t) * (1 - t) * (1 - t);
        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final p in _particles)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: Offset(
                        p.dx(eased),
                        p.dy(eased),
                      ),
                      child: Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Container(
                          width: p.size,
                          height: p.size,
                          decoration: BoxDecoration(
                            color: widget.color,
                            borderRadius: BorderRadius.circular(p.size),
                          ),
                        ),
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

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
  });

  final double angle;
  final double distance;
  final double size;

  double dx(double progress) => math.cos(angle) * distance * progress;

  double dy(double progress) => math.sin(angle) * distance * progress;
}

/// 勾选联动：一个动作，三重反馈。
///
/// 1. 勾自己画出来（描边动画）
/// 2. 右侧数字滚上去（不是直接跳）
/// 3. 整张容器亮一下（边框 + 外发光 + 底部分段进度）
class ClayFollowToggle extends StatelessWidget {
  const ClayFollowToggle({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.count,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 右侧大数字；变化时滚动。
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final Duration duration = KazumiMotion.scale(context, KazumiMotion.base);
    final ClayToneColors accent = ClayToneColors.of(context, ClayTone.accent);
    final ClayToneColors base = ClayToneColors.of(context, ClayTone.surface);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        KazumiHaptics.select();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: duration,
        curve: KazumiMotion.emphasized,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: value ? 0.10 : 0.06),
              Colors.white.withValues(alpha: value ? 0.05 : 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: value
                ? colors.primary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.12),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: duration,
              curve: KazumiMotion.spring,
              width: 26,
              height: 26,
              transform: Matrix4.diagonal3Values(value ? 1.06 : 1.0, value ? 1.06 : 1.0, 1),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: value
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent.light, accent.dark],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [base.light, base.dark],
                      ),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: AnimatedOpacity(
                duration: duration,
                opacity: value ? 1 : 0,
                child: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: accent.fg,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (count != null)
              RollingNumber(
                value: count!,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 数字滚动：从旧值平滑滚到新值，而不是直接跳变。
class RollingNumber extends StatefulWidget {
  const RollingNumber({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late int _from = widget.value;
  late int _to = widget.value;

  @override
  void didUpdateWidget(RollingNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    _from = _to;
    _to = widget.value;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = Curves.easeOutCubic.transform(_controller.value);
        final int current = (_from + (_to - _from) * t).round();
        return Text('$current', style: widget.style);
      },
    );
  }
}

/// 粘土容器：承载内容的底板。
///
/// 和 [ClayButton] 用同一套受光逻辑（左上亮、右下暗），但多了落地阴影，
/// 所以看起来是"放在页面上的一块"，而不是"贴在页面上的一层"。
///
/// 内部套一层透明 `Material`，让 `InkWell` 的水波纹画在粘土之上而不是
/// 被底板盖住——列表类内容（设置项、搜索结果）依赖这一点。
class ClayPanel extends StatelessWidget {
  const ClayPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
    this.tone = ClayTone.surface,
    this.depth = 1,
    this.borderOpacity = 0.07,
    this.gradient = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final ClayTone tone;

  /// 0 表示不放阴影（嵌套在别的粘土上时用）。
  final double depth;
  final double borderOpacity;

  /// 关掉渐变只留纯色，用于大面积背景板。
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ClayToneColors c = ClayToneColors.of(context, tone);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: gradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.light, c.dark],
              )
            : null,
        color: gradient ? null : c.light,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: borderOpacity)
              : Colors.black.withValues(alpha: 0.05),
          width: 0.5,
        ),
        boxShadow: depth <= 0
            ? const []
            : [
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.42 : 0.13),
                  blurRadius: 18 * depth,
                  offset: Offset(0, 7 * depth),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 方形粘土徽章：设置分类、对话框图标这类"一格里一个图标"的场景。
class ClayIconBadge extends StatelessWidget {
  const ClayIconBadge({
    super.key,
    required this.icon,
    this.size = 38,
    this.tone = ClayTone.accent,
    this.iconSize,
  });

  final IconData icon;
  final double size;
  final ClayTone tone;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final ClayToneColors c = ClayToneColors.of(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.light, c.dark],
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: iconSize ?? size * 0.5, color: c.fg),
    );
  }
}

/// 粘土拨杆。
///
/// 关：凹槽（渐变反向，看起来是刻进去的）；开：整条变成强调色粘土并抬起。
/// 滑块本身是一颗小粘土球，按下会缩一下再弹回。
class ClaySwitch extends StatefulWidget {
  const ClaySwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 50,
    this.height = 28,
    this.haptic = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;
  final bool haptic;

  @override
  State<ClaySwitch> createState() => _ClaySwitchState();
}

class _ClaySwitchState extends State<ClaySwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final bool active = _pressed && enabled;
    final double thumb = widget.height - 8;
    final bool darkMode = Theme.of(context).brightness == Brightness.dark;
    final ClayToneColors on = ClayToneColors.of(context, ClayTone.accent);
    final ClayToneColors off = ClayToneColors.of(context, ClayTone.subtle);
    final Duration duration = KazumiMotion.scale(
      context,
      active ? KazumiMotion.instant : KazumiMotion.base,
    );

    // 开态用的那一对颜色。
    // 深色模式：浅紫底 + 白钮，靠落影区分；浅色模式：浅紫底和关态的灰几乎同色，
    // 开关看不出状态，所以改用饱和的那一支，白钮才压得住。
    final List<Color> onGradient = darkMode
        ? [on.light, on.dark]
        : [on.strong, Color.lerp(on.strong, Colors.black, 0.16)!];

    return Semantics(
      toggled: widget.value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) KazumiHaptics.select();
                widget.onChanged!(!widget.value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedContainer(
            duration: duration,
            curve: KazumiMotion.emphasized,
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              // 开=受光在左上，关=受光在右下（凹槽）。
              gradient: LinearGradient(
                begin: widget.value ? Alignment.topLeft : Alignment.bottomRight,
                end: widget.value ? Alignment.bottomRight : Alignment.topLeft,
                colors: widget.value
                    ? onGradient
                    : [off.dark, off.light],
              ),
              borderRadius: BorderRadius.circular(widget.height),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: widget.value ? 0.14 : 0.05),
                width: 0.5,
              ),
              boxShadow: widget.value
                  ? [
                      BoxShadow(
                        color: on.shadow.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: KazumiMotion.spring,
              alignment:
                  widget.value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedScale(
                scale: active ? 0.84 : 1,
                duration: duration,
                curve: KazumiMotion.spring,
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFDFDFF), Color(0xFFD6D9E2)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 粘土勾选框。选中时整块变成强调色粘土，勾从中间弹出来。
class ClayCheck extends StatelessWidget {
  const ClayCheck({
    super.key,
    required this.value,
    this.size = 24,
    this.onTap,
  });

  final bool value;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ClayToneColors on = ClayToneColors.of(context, ClayTone.accent);
    final ClayToneColors off = ClayToneColors.of(context, ClayTone.subtle);
    final Duration duration =
        KazumiMotion.scale(context, KazumiMotion.base);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: duration,
        curve: KazumiMotion.emphasized,
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: value ? [on.light, on.dark] : [off.light, off.dark],
          ),
          borderRadius: BorderRadius.circular(size * 0.34),
          border: Border.all(
            color: Colors.white.withValues(alpha: value ? 0.16 : 0.06),
            width: 0.5,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: on.shadow.withValues(alpha: 0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: AnimatedScale(
          scale: value ? 1 : 0.5,
          duration: duration,
          curve: KazumiMotion.spring,
          child: AnimatedOpacity(
            duration: duration,
            opacity: value ? 1 : 0,
            child: Icon(
              Icons.check_rounded,
              size: size * 0.66,
              color: on.fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// 粘土滑条。
///
/// 轨道是凹进去的（渐变反向 + 内描边），已选段是强调色粘土，滑钮是一颗
/// 凸起的球。拖动时滑钮放大 12%，数值变化时给一次轻震动。
class ClaySlider extends StatefulWidget {
  const ClaySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.height = 40,
    this.haptic = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final double height;
  final bool haptic;

  @override
  State<ClaySlider> createState() => _ClaySliderState();
}

class _ClaySliderState extends State<ClaySlider> {
  bool _dragging = false;

  void _emit(double dx, double width) {
    if (width <= 0) return;
    final double t = (dx / width).clamp(0.0, 1.0);
    final double span = widget.max - widget.min;
    double value = widget.min + t * span;
    final int? divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      final double step = span / divisions;
      value = widget.min + ((value - widget.min) / step).round() * step;
    }
    if ((value - widget.value).abs() < 1e-9) return;
    if (widget.haptic) KazumiHaptics.select();
    widget.onChanged(value.clamp(widget.min, widget.max));
  }

  @override
  Widget build(BuildContext context) {
    final ClayToneColors on = ClayToneColors.of(context, ClayTone.accent);
    final ClayToneColors off = ClayToneColors.of(context, ClayTone.subtle);
    const double thumb = 22;
    const double trackHeight = 10;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double span = widget.max - widget.min;
        final double t = span <= 0
            ? 0
            : ((widget.value - widget.min) / span).clamp(0.0, 1.0);
        final double left = t * (width - thumb);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _emit(details.localPosition.dx, width),
          onHorizontalDragStart: (details) {
            setState(() => _dragging = true);
            _emit(details.localPosition.dx, width);
          },
          onHorizontalDragUpdate: (details) =>
              _emit(details.localPosition.dx, width),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: SizedBox(
            height: widget.height,
            width: width,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                // 凹槽
                Positioned(
                  left: 0,
                  right: 0,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [off.dark, off.light],
                      ),
                      borderRadius: BorderRadius.circular(trackHeight),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.22),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
                // 已选段
                Positioned(
                  left: 0,
                  width: (left + thumb / 2).clamp(0.0, width),
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      // 用 strong 而不是 light：浅色模式下 light 是浅紫，
                      // 压在同样偏浅的凹槽上根本分不清走到哪了。
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          on.strong,
                          Color.lerp(on.strong, Colors.black, 0.14)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(trackHeight),
                      boxShadow: [
                        BoxShadow(
                          color: on.strong.withValues(alpha: 0.28),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                // 滑钮
                AnimatedPositioned(
                  duration: _dragging
                      ? Duration.zero
                      : KazumiMotion.scale(context, KazumiMotion.fast),
                  curve: KazumiMotion.emphasized,
                  left: left,
                  child: AnimatedScale(
                    scale: _dragging ? 1.12 : 1,
                    duration: KazumiMotion.scale(context, KazumiMotion.fast),
                    curve: KazumiMotion.spring,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFDFDFF), Color(0xFFD3D6E0)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.42),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 粘土对话框。
///
/// 不走 `AlertDialog`——`AlertDialog` 的背景是 `Material` 纯色，渐变塞不进去，
/// 所以自己搭一层透明 `Dialog` + [ClayPanel]。动作区固定横排，两个按钮各占一半。
class ClayDialog extends StatelessWidget {
  const ClayDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.icon,
    this.actions = const <Widget>[],
    this.maxWidth = 420,
    this.scrollable = false,
  });

  final String title;
  final String? message;
  final Widget? content;
  final IconData? icon;
  final List<Widget> actions;
  final double maxWidth;

  /// 内容比屏幕高时（长文案、表单、列表）打开它：
  /// 标题以下可滚动，动作区仍然钉在底部。
  final bool scrollable;

  /// 确认框的常用形态。返回 true 表示确认。
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    String? message,
    IconData? icon,
    String confirmLabel = '确定',
    String cancelLabel = '取消',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ClayDialog(
        title: title,
        message: message,
        icon: icon,
        actions: [
          ClayButton(
            tone: ClayTone.subtle,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          ClayButton(
            tone: destructive ? ClayTone.danger : ClayTone.accent,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (icon != null) ...[
          Center(child: ClayIconBadge(icon: icon!, size: 54)),
          const SizedBox(height: 16),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
        if (content != null) ...[
          const SizedBox(height: 18),
          content!,
        ],
      ],
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClayPanel(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scrollable)
                Flexible(child: SingleChildScrollView(child: body))
              else
                body,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
