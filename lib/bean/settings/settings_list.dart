import 'package:flutter/material.dart';

import 'package:XL/bean/widget/split_list_row.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';

/// 设置页的通用列表件，全部按 Pv（iOS 白卡）画。
///
/// 这一层被 20 多个设置页共用，改这里等于把所有二级页一起拉过来：分组是一张
/// 整卡 + 行间发丝线，行高 50、左右 15，标题 15/w500，说明 13 灰；开关用
/// iOS 那种绿色 [PvSwitch]，单选用蓝色对勾。
///
/// 之所以不在每个页面各画一遍：设置页有二十来个，一套一套改必然长歪，
/// 之前「一页里两套材质」就是这么来的。
enum _TileKind { plain, toggle, radio }

class SettingsList extends StatelessWidget {
  const SettingsList({
    super.key,
    required this.sections,
    this.maxWidth = 1000,
  });

  final List<Widget> sections;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: sections.length,
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: sections[index],
        ),
      ),
    );
  }
}

/// 一组设置：上面一个小灰标签，下面一张白卡。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.title,
    this.bottomInfo,
    this.margin,
  });

  final List<Widget> tiles;
  final Widget? title;
  final Widget? bottomInfo;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 7),
              child: DefaultTextStyle.merge(
                style: PvText.groupLabel(context),
                child: title!,
              ),
            ),
          SplitListGroup(children: tiles),
          if (bottomInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: PvColors.ink3(context),
                ),
                child: bottomInfo!,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsRadioSection<T> extends StatelessWidget {
  const SettingsRadioSection({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.tiles,
    this.title,
  });

  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final List<Widget> tiles;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: SettingsSection(title: title, tiles: tiles),
    );
  }
}

Color _disabledInk(BuildContext context) =>
    PvColors.ink3(context).withValues(alpha: 0.6);

/// 设置行左侧的小图标：28×28 圆角 8 的彩色底 + 白色图标。
///
/// 颜色按标题稳定散列到一组 Pv 常用的强调色上——设置页里有几十行带图标的
/// 条目，逐个指定颜色既啰嗦又容易撞色，按标题取色至少同一行每次都是同一个色。
const List<Color> _badgeTones = <Color>[
  Color(0xFF0A84FF),
  Color(0xFF34C759),
  Color(0xFFFF9F0A),
  Color(0xFFFF375F),
  Color(0xFF5E5CE6),
  Color(0xFF30B0C7),
  Color(0xFF8E8E93),
  Color(0xFF5856D6),
];

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.title,
    this.leading,
    this.description,
    this.enabled = true,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? PvColors.ink(context) : _disabledInk(context);
    final sub = enabled ? PvColors.ink3(context) : _disabledInk(context);

    return Row(
      children: [
        if (leading != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: enabled
                  ? _badgeTones[title.hashCode.abs() % _badgeTones.length]
                  : PvColors.searchFill(context),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(leading, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.15,
                  height: 1.25,
                  color: ink,
                ),
                child: title,
              ),
              if (description != null) ...[
                const SizedBox(height: 3),
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13, height: 1.35, color: sub),
                  child: description!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 「设置 → 某个分类」的入口行（索引页用）。
class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _badgeTones[title.hashCode.abs() % _badgeTones.length],
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.15,
                        color: PvColors.ink(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: PvColors.ink3(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 17, color: PvColors.chev(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.leading,
    this.description,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TileLabel(
                  title: title,
                  leading: leading,
                  description: description,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: PvColors.searchFill(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: PvColors.ink2(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: PvColors.blue,
              inactiveTrackColor: PvColors.searchFill(context),
              thumbColor: Colors.white,
              overlayColor: PvColors.blue.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              valueIndicatorShape: const RectangularSliderValueIndicatorShape(),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTile<T> extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.trailing,
    this.value,
    this.onPressed,
    this.enabled = true,
  })  : _kind = _TileKind.plain,
        onToggle = null,
        initialValue = null,
        radioValue = null;

  /// Row taps pass null to [onToggle]; switch gestures pass the new value.
  const SettingsTile.switchTile({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onToggle,
    this.leading,
    this.description,
    this.enabled = true,
  })  : _kind = _TileKind.toggle,
        trailing = null,
        value = null,
        onPressed = null,
        radioValue = null;

  const SettingsTile.radioTile({
    super.key,
    required this.title,
    required T this.radioValue,
    this.leading,
    this.description,
    this.enabled = true,
  })  : _kind = _TileKind.radio,
        trailing = null,
        value = null,
        onPressed = null,
        onToggle = null,
        initialValue = null;

  final Widget title;

  final IconData? leading;
  final Widget? description;
  final Widget? trailing;
  final Widget? value;
  final void Function(BuildContext context)? onPressed;
  final void Function(bool? value)? onToggle;
  final bool? initialValue;
  final T? radioValue;
  final bool enabled;
  final _TileKind _kind;

  VoidCallback? _tapHandler(BuildContext context) {
    if (!enabled) {
      return null;
    }
    switch (_kind) {
      case _TileKind.plain:
        return onPressed == null ? null : () => onPressed!(context);
      case _TileKind.toggle:
        return onToggle == null ? null : () => onToggle!(null);
      case _TileKind.radio:
        final registry = RadioGroup.maybeOf<T>(context);
        return registry == null ? null : () => registry.onChanged(radioValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = enabled ? PvColors.ink2(context) : _disabledInk(context);
    final selected =
        _kind == _TileKind.radio && RadioGroup.maybeOf<T>(context)?.groupValue == radioValue;

    return InkWell(
      onTap: _tapHandler(context),
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: _TileLabel(
                  title: title,
                  leading: leading,
                  description: description,
                  enabled: enabled,
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 13.5, color: secondary),
                  child: value!,
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                IconTheme.merge(
                  data: IconThemeData(
                    color: secondary,
                    size: 18,
                  ),
                  child: trailing!,
                ),
              ],
              if (_kind == _TileKind.toggle) ...[
                const SizedBox(width: 12),
                PvSwitch(
                  value: initialValue ?? false,
                  onChanged: enabled ? (v) => onToggle?.call(v) : (_) {},
                ),
              ],
              if (_kind == _TileKind.radio) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 19, color: PvColors.blue)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
