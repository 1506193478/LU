part of 'collect_library_view.dart';

class _CollectCategories extends StatelessWidget {
  const _CollectCategories({
    super.key,
    required this.controller,
    required this.selected,
    required this.count,
  });

  final TabController controller;

  /// 选中类目。用 ValueNotifier 单独驱动「加粗」这一件事，
  /// 不再让整个 TabBar 随换类重建。
  final ValueListenable<CollectType?> selected;
  final int Function(CollectType?) count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // 预览稿是「灰色轨道 + 白色选中胶囊」的分段控件，六段等宽铺满一行。
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0x1A787880),
        borderRadius: BorderRadius.circular(11),
      ),
      child: TabBar(
        key: const PageStorageKey('collect-filter-strip'),
        controller: controller,
        isScrollable: false,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.zero,
        indicator: BoxDecoration(
          color: dark ? const Color(0xFF33353C) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        indicatorAnimation: TabIndicatorAnimation.elastic,
        labelColor: dark ? Colors.white : const Color(0xFF0B0B0F),
        unselectedLabelColor: dark ? Colors.white54 : const Color(0xFF5B5B60),
        // 选中/未选中必须是同一个 TextStyle 实例：TabBar 切换动画期间
        // 会在两个样式间逐帧插值，字重不同 = 每帧新建字体实例 = 掉帧。
        // 加粗改为在 label 内部按选中态一次性切换（见下面每个 Tab）。
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        labelPadding: EdgeInsets.zero,
        splashBorderRadius: BorderRadius.circular(9),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        tabs: [
          for (final type in _collectCategories)
            Tab(
              height: 31,
              child: Semantics(
                label: '${type?.label ?? '全部'}，${count(type)} 部',
                excludeSemantics: true,
                child: Center(
                  child: ValueListenableBuilder<CollectType?>(
                    valueListenable: selected,
                    builder: (context, value, _) => Text(
                      type?.label ?? '全部',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: value == type
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollectLayoutSwitch extends StatelessWidget {
  const _CollectLayoutSwitch({required this.value, required this.onChanged});

  final CollectLayout value;
  final ValueChanged<CollectLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final layout in [CollectLayout.cards, CollectLayout.list])
          Semantics(
            selected: value == layout,
            inMutuallyExclusiveGroup: true,
            child: IconButton.filledTonal(
              tooltip: '${layout.label}布局',
              isSelected: value == layout,
              onPressed: () => onChanged(layout),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                visualDensity: VisualDensity.standard,
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.secondaryContainer
                      : colors.surfaceContainerLow,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                shape: WidgetStateProperty.resolveWith(
                  (states) => RoundedRectangleBorder(
                    borderRadius: states.contains(WidgetState.pressed)
                        ? BorderRadius.circular(12)
                        : states.contains(WidgetState.selected)
                        ? BorderRadius.circular(24)
                        : BorderRadiusDirectional.horizontal(
                            start: Radius.circular(
                              layout == CollectLayout.cards ? 24 : 8,
                            ),
                            end: Radius.circular(
                              layout == CollectLayout.list ? 24 : 8,
                            ),
                          ),
                  ),
                ),
                animationDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
              ),
              icon: Icon(
                layout == CollectLayout.list
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
            ),
          ),
      ],
    );
  }
}

class _CollectSortMenu extends StatelessWidget {
  const _CollectSortMenu({
    required this.value,
    required this.showLabel,
    required this.onChanged,
  });

  final CollectSort value;
  final bool showLabel;
  final ValueChanged<CollectSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return KazumiMenuButton(
      menuChildren: [
        for (final sort in CollectSort.values)
          KazumiMenuItem(
            selected: value == sort,
            onPressed: () => onChanged(sort),
            label: sort.label,
          ),
      ],
      builder: (context, toggle) {
        return Tooltip(
          message: '排序：${value.label}',
          child: showLabel
              ? TextButton.icon(
                  onPressed: toggle,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.sort_rounded, size: 20),
                  label: Text(value.label),
                )
              : IconButton(
                  onPressed: toggle,
                  icon: const Icon(Icons.sort_rounded),
                ),
        );
      },
    );
  }
}
