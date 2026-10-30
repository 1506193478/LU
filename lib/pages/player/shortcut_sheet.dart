import 'package:flutter/material.dart';

import 'package:XL/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/constants.dart';

/// 播放器快捷键一览。
///
/// 键位读的是**当前生效**的那份（设置里改过的会生效），不是默认表 ——
/// 显示默认值等于骗人。
Future<void> showPlayerShortcutSheet(BuildContext context) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    maxHeightFactor: 0.82,
    builder: (BuildContext context) => const _PlayerShortcutSheet(),
  );
}

class _PlayerShortcutSheet extends StatelessWidget {
  const _PlayerShortcutSheet();

  /// 生效中的键位（用户改过的优先）。
  Map<String, List<String>> _effectiveShortcuts() {
    return <String, List<String>>{
      for (final MapEntry<String, List<String>> entry
          in defaultShortcuts.entries)
        entry.key: GStorage.getStringListSettingByName(
          'shortcut_${entry.key}',
          defaultValue: entry.value,
        ),
    };
  }

  String _keyLabel(String key) => keyAliases[key] ?? key;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Map<String, List<String>> shortcuts = _effectiveShortcuts();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(Icons.keyboard_rounded, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '播放器快捷键',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '键位可以在 设置 → 播放器 → 快捷键 里改',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                for (final MapEntry<String, List<String>> entry
                    in shortcuts.entries)
                  _ShortcutRow(
                    label: shortcutsChineseName[entry.key] ?? entry.key,
                    keys: <String>[
                      for (final String key in entry.value) _keyLabel(key),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  '长按「快进 / 快退」键可以持续拖动进度；`?` 随时打开这张表。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.keys});

  final String label;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          for (final String key in keys)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  key,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
