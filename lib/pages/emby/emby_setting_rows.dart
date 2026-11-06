import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/storage/storage.dart';

/// 设置类页面共用的一行开关。
///
/// 原来它长在 `emby_res_pane.dart` 里、并且把 `showDivider` 写死成 `false`：
/// 结果一组里连着七个开关，行与行之间一条分隔线都没有，整块糊在一起。
/// 现在补上参数，由调用方决定（组内除最后一行都传 true）。
class PvSwitchRow extends StatefulWidget {
  const PvSwitchRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.prefKey,
    required this.defaultValue,
    this.showDivider = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String prefKey;
  final bool defaultValue;
  final bool showDivider;

  @override
  State<PvSwitchRow> createState() => _PvSwitchRowState();
}

class _PvSwitchRowState extends State<PvSwitchRow> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    _value = GStorage.getSetting(
      SettingKey<bool>(
        widget.prefKey,
        widget.defaultValue,
        group: SettingGroup.player,
      ),
    );
  }

  Future<void> _toggle(bool next) async {
    setState(() => _value = next);
    await GStorage.putSetting(
      SettingKey<bool>(
        widget.prefKey,
        widget.defaultValue,
        group: SettingGroup.player,
      ),
      next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool value = _value ?? widget.defaultValue;
    return PvRow(
      icon: widget.icon,
      iconColor: widget.iconColor,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: PvRowTrailing.widget,
      trailingWidget: PvSwitch(value: value, onChanged: _toggle),
      showDivider: widget.showDivider,
    );
  }
}
