import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/services/emby/sen_tab_prefs.dart';

/// 打开「模块管理」面板：SenPlayer 式的 Tab 显隐 / 排序 / 默认页 / 位置。
void showEmbyTabManager(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TabManagerSheet(),
  );
}

class _TabManagerSheet extends StatelessWidget {
  const _TabManagerSheet();

  @override
  Widget build(BuildContext context) {
    final prefs = SenTabPrefs.instance;
    return Container(
      decoration: BoxDecoration(
        color: PvColors.card(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PvColors.hair(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '模块管理',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: PvColors.ink(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: prefs.reset,
                    child: const Text('恢复默认'),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: PvColors.ink2(context)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '拖动排序 · 开关显隐 · 点选默认页',
                style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: AnimatedBuilder(
                animation: prefs.revision,
                builder: (context, _) {
                  final ids = prefs.visibleIds;
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    itemCount: ids.length,
                    onReorderItem: (oldIndex, newIndex) {
                      prefs.reorderVisible(ids, oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final meta = SenTabPrefs.metaOf(ids[index])!;
                      final isDefault = prefs.defaultTab == meta.id;
                      return _buildRow(context, prefs, meta, isDefault);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _buildHiddenSection(context, prefs),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    SenTabPrefs prefs,
    SenTabMeta meta,
    bool isDefault,
  ) {
    return Container(
      key: ValueKey<String>(meta.id),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PvColors.hair(context), width: 0.5),
        ),
      ),
      child: ListTile(
        leading: Icon(meta.icon, color: PvColors.subInk(context)),
        title: Row(
          children: <Widget>[
            Text(
              meta.label,
              style: TextStyle(color: PvColors.ink(context), fontSize: 15),
            ),
            if (isDefault) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PvColors.blue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '默认',
                  style: TextStyle(fontSize: 10, color: PvColors.blue),
                ),
              ),
            ],
          ],
        ),
        trailing: SizedBox(
          width: 124,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!isDefault)
                IconButton(
                  icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                  tooltip: '设为默认',
                  color: PvColors.subInk(context),
                  onPressed: () => prefs.setDefaultTab(meta.id),
                ),
              IconButton(
                icon: const Icon(Icons.visibility_off_outlined, size: 20),
                tooltip: '隐藏',
                color: PvColors.ink3(context),
                onPressed: () => prefs.setVisible(meta.id, false),
              ),
              const Icon(Icons.reorder_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenSection(BuildContext context, SenTabPrefs prefs) {
    final hidden = SenTabPrefs.all
        .where((SenTabMeta m) => !prefs.isVisible(m.id))
        .toList();
    if (hidden.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '已隐藏',
            style: TextStyle(fontSize: 12, color: PvColors.ink3(context)),
          ),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final SenTabMeta m in hidden)
              ActionChip(
                avatar: Icon(m.icon, size: 16, color: PvColors.ink2(context)),
                label: Text(m.label),
                onPressed: () => prefs.setVisible(m.id, true),
              ),
          ],
        ),
      ],
    );
  }
}
