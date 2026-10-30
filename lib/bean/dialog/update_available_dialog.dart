import 'package:flutter/material.dart';
import 'package:XL/bean/dialog/dialog.dart';
import 'package:XL/bean/settings/settings_dropdown_tile.dart';
import 'package:XL/bean/settings/settings_list.dart';
import 'package:XL/bean/widget/neu_dialog.dart';
import 'package:XL/services/update/auto_updater.dart';
import 'package:XL/services/update/update_download_source.dart';
import 'package:XL/utils/date_time.dart';

typedef UpdateDialogChoice = ({
  InstallationType type,
  UpdateDownloadSource source,
});

/// Pops with an [UpdateDialogChoice] when the user starts the update.
class UpdateAvailableDialog extends StatefulWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.updateInfo,
    this.onDisableAutoUpdateChanged,
  });

  final UpdateInfo updateInfo;

  /// Shows the auto-update opt-out when non-null.
  final ValueChanged<bool>? onDisableAutoUpdateChanged;

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  var _source = UpdateDownloadSource.github;
  late var _type = widget.updateInfo.recommendedInstallationType;
  var _disableAutoUpdate = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadInApp = _type.downloadsInApp;

    return NeuDialog(
      title: '发现新版本',
      icon: Icons.system_update_alt_rounded,
      maxWidth: 460,
      scrollable: true,
      content: SizedBox(
        width: 392,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, downloadInApp),
            const SizedBox(height: 14),
            if (downloadInApp) ...[
              const SizedBox(height: 20),
              _buildDownloadOptions(),
            ],
            if (widget.onDisableAutoUpdateChanged != null) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _disableAutoUpdate,
                onChanged: (value) {
                  setState(() => _disableAutoUpdate = value ?? false);
                  widget.onDisableAutoUpdateChanged!(_disableAutoUpdate);
                },
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text('不再自动检查', style: theme.textTheme.bodyMedium),
              ),
            ],
          ],
        ),
      ),
      actions: [
        NeuDialogButton(
          label: '稍后',
          height: 48,
          onPressed: () => KazumiDialog.dismiss(context: context),
        ),
        NeuDialogButton(
          label: downloadInApp ? '更新' : '前往下载',
          icon: downloadInApp
              ? Icons.download_rounded
              : Icons.open_in_new_rounded,
          primary: true,
          height: 48,
          onPressed: () => KazumiDialog.dismiss(
            context: context,
            popWith: (type: _type, source: _source),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool downloadInApp) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final info = widget.updateInfo;
    // 更新日志不再在推送页展示（用户要求）。releaseNotes 仍用作兜底"前往下载"
    // 时打开的发布页地址，由 auto_updater 负责。

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            info.version,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSecondaryContainer,
            ),
          ),
        ),
        if (info.publishedAt.isNotEmpty)
          Text(
            formatDate(info.publishedAt),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadOptions() {
    final types = widget.updateInfo.availableInstallationTypes;
    return SettingsSection(
      margin: EdgeInsets.zero,
      tiles: [
        SettingsDropdownTile<UpdateDownloadSource>(
          leading: Icons.cloud_download_rounded,
          title: const Text('下载源'),
          value: _source,
          options: {
            for (final source in UpdateDownloadSource.values)
              source: source.label,
          },
          onChanged: (source) => setState(() => _source = source),
        ),
        if (types.length > 1)
          SettingsDropdownTile<InstallationType>(
            leading: Icons.inventory_2_rounded,
            title: const Text('安装类型'),
            value: _type,
            options: {for (final type in types) type: type.label},
            onChanged: (type) => setState(() => _type = type),
          ),
      ],
    );
  }
}
