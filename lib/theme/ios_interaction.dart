import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:XL/utils/motion.dart';

/// 是否按 iOS 原生交互渲染。
///
/// 用 [defaultTargetPlatform] 而不是 `Platform.isIOS`：后者在 Web 上会抛
/// 异常，而这个判断散布在控件里，一旦崩就是整页白屏。
///
/// 注意这是「交互动词」层面的判断，不是「皮肤」：颜色、圆角、字体仍然走
/// 项目自己的 Pv 设计语言，只有**控件行为与动效**跟着平台走。
bool get kIsCupertinoPlatform =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// iOS 系统绿，开关、滑块、成功态统一用它。
const Color kCupertinoGreen = Color(0xFF34C759);

/// iOS 系统蓝，链接、默认按钮用它。
const Color kCupertinoBlue = Color(0xFF007AFF);

/// iOS 系统红，破坏性操作用它。
const Color kCupertinoRed = Color(0xFFFF3B30);

// ---------------------------------------------------------------- 加载指示

/// 加载指示器：iOS 用八线 spinner，其余平台用 Material 圆环。
///
/// 尺寸语义统一成「外接方框边长」，两端视觉大小才一致
/// （Cupertino 的 radius 是半径，直接用会和 Material 差一倍）。
class KzLoading extends StatelessWidget {
  const KzLoading({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!kIsCupertinoPlatform) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: color,
        ),
      );
    }
    return CupertinoActivityIndicator(
      radius: size * 0.62,
      color: color,
    );
  }
}

/// 整页加载：两端都用「居中 + 上面的小 spinner」。
class KzPageLoading extends StatelessWidget {
  const KzPageLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KzLoading(size: 26),
          if (text != null) ...[
            const SizedBox(height: 14),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 开关 / 滑块

/// 开关：iOS 是绿色胶囊，Android 是 Material Switch。
///
/// 尺寸按 iOS 的 51x31 给（Material 是 52x32，几乎一样），
/// 两端切换不会让布局跳一下。
class KzSwitch extends StatelessWidget {
  const KzSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    if (!kIsCupertinoPlatform) {
      return Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor ?? Theme.of(context).colorScheme.primary,
      );
    }
    return SizedBox(
      width: 51,
      height: 31,
      child: FittedBox(
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: activeColor ?? kCupertinoGreen,
          onChanged: onChanged == null
              ? null
              : (v) {
                  KazumiHaptics.select();
                  onChanged!(v);
                },
        ),
      ),
    );
  }
}

/// 滑块：iOS 是细轨 + 白色圆钮，Android 是 Material 滑块。
class KzSlider extends StatelessWidget {
  const KzSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    if (!kIsCupertinoPlatform) {
      return SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: activeColor,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      );
    }
    return CupertinoSlider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor ?? kCupertinoBlue,
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------- 弹窗

/// 一个弹窗按钮的描述。两端各自渲染成自己那套动作按钮。
class KzDialogAction {
  const KzDialogAction({
    required this.label,
    this.onPressed,
    this.result,
    this.resolveResult,
    this.isDefault = false,
    this.isDestructive = false,
  });

  final String label;

  /// 额外动作。点击后会先关闭弹窗（带 [result]），再执行它。
  final VoidCallback? onPressed;

  /// 关闭弹窗时 `Navigator.pop` 的返回值。
  ///
  /// 这样 `showDialog<bool>` / `showDialog<String>` 的调用点不用改结构，
  /// 直接把 AlertDialog 换成这个就能拿到结果。
  final Object? result;

  /// 动态结果：点了才求值（输入框那种要把当前文本带出去）。
  /// 优先于 [result]。
  final Object? Function()? resolveResult;

  /// iOS 上会加粗（CupertinoDialogAction 的 isDefaultAction）。
  final bool isDefault;
  final bool isDestructive;
}

/// 系统风格弹窗。
///
/// iOS：居中、毛玻璃底、标题与正文居中、按钮横排（两个以上竖排）。
/// Android：Material 圆角卡片、标题左对齐。
class KzAlertDialog extends StatelessWidget {
  const KzAlertDialog({
    super.key,
    this.title,
    this.message,
    this.actions = const <KzDialogAction>[],
    this.content,
  });

  final String? title;
  final String? message;
  final List<KzDialogAction> actions;

  /// 需要自定义内容（输入框等）时用它，[message] 会被忽略。
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final body = content ?? (message == null ? null : Text(message!));
    if (!kIsCupertinoPlatform) {
      return AlertDialog(
        title: title == null ? null : Text(title!),
        content: body,
        actions: [
          for (final a in actions)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  a.resolveResult?.call() ?? a.result,
                );
                a.onPressed?.call();
              },
              style: a.isDestructive
                  ? TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              child: Text(a.label),
            ),
        ],
      );
    }
    return CupertinoAlertDialog(
      title: title == null ? null : Text(title!),
      content: body,
      actions: [
        for (final a in actions)
          CupertinoDialogAction(
            isDefaultAction: a.isDefault,
            isDestructiveAction: a.isDestructive,
            onPressed: () {
              Navigator.of(context).pop(
                a.resolveResult?.call() ?? a.result,
              );
              a.onPressed?.call();
            },
            child: Text(a.label),
          ),
      ],
    );
  }
}

/// 底部动作表里的一个选项。
class KzSheetAction<T> {
  const KzSheetAction({
    required this.label,
    this.value,
    this.icon,
    this.isDestructive = false,
    this.subtitle,
  });

  final String label;
  final T? value;
  final IconData? icon;
  final bool isDestructive;
  final String? subtitle;
}

/// 底部动作表（分享、选择、更多操作）。
///
/// iOS 用 [CupertinoActionSheet]（从底部推入 + 取消按钮独立成块），
/// Android 用 Material 底部弹层（列表 + 无取消块，点外部关闭）。
Future<T?> showKzActionSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required List<KzSheetAction<T>> actions,
  String cancelLabel = '取消',
}) async {
  if (!kIsCupertinoPlatform) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            for (final a in actions)
              ListTile(
                leading: a.icon == null ? null : Icon(a.icon),
                title: Text(
                  a.label,
                  style: a.isDestructive
                      ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                      : null,
                ),
                subtitle: a.subtitle == null ? null : Text(a.subtitle!),
                onTap: () => Navigator.of(ctx).pop(a.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // iOS：取消按钮单独一块，操作项一屏放不下时可滚动。
  final result = await showCupertinoModalPopup<_KzSheetPick<T>>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: a.isDestructive,
            onPressed: () => Navigator.of(ctx).pop(_KzSheetPick<T>(a.value)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (a.icon != null) ...[
                  Icon(a.icon, size: 20, color: a.isDestructive ? null : null),
                  const SizedBox(width: 8),
                ],
                Text(a.label),
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(cancelLabel),
      ),
    ),
  );
  return result?.value;
}

/// 包一层只为了区分「选了 null」和「点了取消」。
class _KzSheetPick<T> {
  const _KzSheetPick(this.value);
  final T? value;
}

// ---------------------------------------------------------------- 导航栏

/// iOS 风格返回按钮：chevron + 可选上一页标题。
///
/// Material 的 BackButton 是「←」，iOS 是「‹」。差别很小但一眼就能认出来。
class KzBackButton extends StatelessWidget {
  const KzBackButton({super.key, this.label, this.onPressed, this.color});

  /// 上一页标题，传了就渲染成「‹ 返回」那种。
  final String? label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurface;
    if (!kIsCupertinoPlatform) {
      return IconButton(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        icon: Icon(Icons.arrow_back_rounded, size: 22, color: tint),
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      pressedOpacity: 0.4,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.chevron_back, size: 22, color: tint),
            if (label != null && label!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, color: tint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// iOS 导航栏的毛玻璃底。
///
/// 有内容从下面滚过去时才会出现（[revealed] 控制），
/// 静止时保持完全透明 —— 这是 iOS 大标题导航栏的标准行为。
class KzNavBarGlass extends StatelessWidget {
  const KzNavBarGlass({
    super.key,
    required this.revealed,
    required this.child,
    this.blurSigma = 18,
  });

  /// 0 = 完全透明，1 = 完全不透明。滚动位置驱动。
  final double revealed;
  final Widget child;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final t = revealed.clamp(0.0, 1.0);
    if (t <= 0.001) return child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark
        ? const Color(0xFF151417).withValues(alpha: 0.72)
        : const Color(0xFFF3F1F2).withValues(alpha: 0.78);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: blurSigma * t,
                sigmaY: blurSigma * t,
              ),
              child: ColoredBox(
                color: tint.withValues(alpha: tint.a * t),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ---------------------------------------------------------------- 下拉刷新

/// 下拉刷新：iOS 用系统那个 spinner，Android 用 Material 圆环。
///
/// Flutter 自带的 [RefreshIndicator.adaptive] 在 iOS 上会换成
/// CupertinoActivityIndicator + 无背景，正好是原生观感。
class KzRefreshIndicator extends StatelessWidget {
  const KzRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (kIsCupertinoPlatform) {
      return RefreshIndicator.adaptive(
        onRefresh: onRefresh,
        color: color ?? kCupertinoBlue,
        // iOS 的下拉刷新没有 Material 那个圆形底，自适应版已经处理，
        // 这里把边缘间距按系统给足，避免 spinner 贴着导航栏。
        edgeOffset: 0,
        displacement: 44,
        child: child,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color,
      child: child,
    );
  }
}

// ---------------------------------------------------------------- 文本输入

/// iOS 风格的搜索/输入框。
///
/// 不用 [CupertinoTextField] 的默认外观（它是白底直角），
/// 而是保持项目里灰底圆角的形状，只把**行为**换成 iOS：
/// 光标颜色、清除按钮、按压反馈。
InputDecoration kzInputDecoration({
  required BuildContext context,
  String? hint,
  Widget? prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: prefix,
    suffixIcon: suffix,
    isDense: true,
    filled: true,
    fillColor: Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.05),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(
        color: kIsCupertinoPlatform
            ? kCupertinoBlue.withValues(alpha: 0.55)
            : Theme.of(context).colorScheme.primary,
        width: 1.2,
      ),
    ),
  );
}

/// 二次确认弹窗。返回 true 表示用户点了确认。
///
/// 两端语义一致，但外观不同：iOS 是居中毛玻璃 alert、按钮横排且默认项加粗，
/// Android 是 Material 卡片。用它替掉散落的 `showDialog + AlertDialog`，
/// 之后要统一改文案/样式只需要动这里。
Future<bool> showKzConfirm({
  required BuildContext context,
  required String title,
  String? message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => KzAlertDialog(
      title: title,
      message: message,
      actions: [
        KzDialogAction(label: cancelLabel, result: false),
        KzDialogAction(
          label: confirmLabel,
          result: true,
          isDefault: true,
          isDestructive: destructive,
        ),
      ],
    ),
  );
  return result == true;
}

/// 单行输入弹窗（网络链接、重命名）。返回 null 表示取消。
Future<String?> showKzPrompt({
  required BuildContext context,
  required String title,
  String? hint,
  String? initialValue,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => KzAlertDialog(
        title: title,
        content: kIsCupertinoPlatform
            ? CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: hint,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(ctx),
                  borderRadius: BorderRadius.circular(8),
                ),
                style: const TextStyle(fontSize: 14),
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              )
            : TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(hintText: hint, isDense: true),
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
        actions: [
          KzDialogAction(label: cancelLabel),
          KzDialogAction(
            label: confirmLabel,
            isDefault: true,
            resolveResult: () => controller.text.trim(),
          ),
        ],
      ),
    );
    return result;
  } finally {
    controller.dispose();
  }
}

// ---------------------------------------------------------------- 按压反馈

/// iOS 式按压反馈：按下时内容整体变淡，松开立即恢复。
///
/// iOS 没有水波纹，也没有 Material 那种矩形高亮：列表行、卡片、按钮按下
/// 时的反馈就是「内容自己 dim 一下」，时间约 100ms。
///
/// 项目里全局关掉了 splash，很多地方又用 InkWell（highlight 也被压成透明），
/// 结果就是点哪儿都没反应，手感很"死"。这个组件补的就是这一层。
class KzPressable extends StatefulWidget {
  const KzPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedOpacity = 0.55,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下时降到多少透明度。iOS 原生大约 0.4–0.6，卡片面积大就取高一点。
  final double pressedOpacity;
  final HitTestBehavior behavior;

  @override
  State<KzPressable> createState() => _KzPressableState();
}

class _KzPressableState extends State<KzPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // 没有交互就不包手势，避免吃掉父级（比如横向滑动的卡片列表）的事件。
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }
    if (!kIsCupertinoPlatform) {
      // Android 保持 Material 语义（涟漪由主题控制，这里只做点击转发）。
      return InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedOpacity(
        opacity: _pressed ? widget.pressedOpacity : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// iOS 风格设置行：标题左对齐、开关右对齐、整行可点。
///
/// 替掉 Material 的 `SwitchListTile`——那个是「左侧密集排版 + 整行涟漪」，
/// 而且行高和缩进跟 iOS 设置页差得远。这里保持和项目 PvRow 一致的密度。
class KzSwitchTile extends StatelessWidget {
  const KzSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.contentPadding = EdgeInsets.zero,
    this.secondary,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  /// 左侧图标（对应 Material 的 secondary）。
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    if (!kIsCupertinoPlatform) {
      return SwitchListTile(
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        value: value,
        onChanged: onChanged,
      );
    }
    final enabled = onChanged != null;
    return KzPressable(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: contentPadding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (secondary != null) ...[
                secondary!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 15.5,
                        color: enabled
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              KzSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
