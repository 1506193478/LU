import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/desktop_window_controls.dart';
import 'package:XL/bean/widget/pressable.dart';
import 'package:XL/bean/card/bangumi_card.dart';
import 'package:XL/bean/widget/skeleton_card.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/pages/popular/popular_controller.dart';
import 'package:XL/pages/popular/recent_watch_strip.dart';
import 'package:XL/utils/constants.dart';
import 'package:XL/utils/immersive_theme.dart';
import 'package:XL/utils/motion.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/platform/desktop_window_config.dart';
import 'package:XL/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:XL/utils/device.dart';

class PopularPage extends StatefulWidget {
  const PopularPage({
    super.key,
    required this.controller,
  });

  final PopularController controller;

  @override
  State<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends State<PopularPage> {
  late final ScrollController scrollController;
  PopularController get popularController => widget.controller;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      initialScrollOffset: popularController.scrollOffset,
    );
    scrollController.addListener(scrollListener);
    if (popularController.trendList.isEmpty) {
      popularController.queryBangumiByTrend();
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    super.dispose();
  }

  void scrollListener() {
    popularController.scrollOffset = scrollController.offset;
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        !popularController.isLoadingMore) {
      KazumiLogger()
          .i('PopularPageController: Fetching next recommendation batch');
      if (popularController.currentTag != '') {
        popularController.queryBangumiByTag();
      } else {
        popularController.queryBangumiByTrend();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neuScaffoldBackground(context),
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          buildSliverAppBar(),
          const SliverToBoxAdapter(
            child: RecentWatchStrip(),
          ),
          SliverToBoxAdapter(
            child: _buildTagBar(context),
          ),
          SliverToBoxAdapter(
            child: Observer(
              builder: (_) => AnimatedOpacity(
                opacity: popularController.isLoadingMore ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: popularController.isLoadingMore
                    ? const LinearProgressIndicator(minHeight: 4)
                    : const SizedBox(height: 4),
              ),
            ),
          ),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  StyleString.cardSpace, 8, StyleString.cardSpace, 0),
              sliver: Observer(builder: (_) {
                if (popularController.isTimeOut) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 400,
                      child: BangumiMirrorErrorWidget(
                        onRetry: () {
                          if (popularController.trendList.isEmpty) {
                            popularController.queryBangumiByTrend();
                          } else {
                            popularController.queryBangumiByTag();
                          }
                        },
                        onSettingsReturned: () {
                          if (mounted) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  );
                }
                return contentGrid(
                  (popularController.currentTag == '')
                      ? popularController.trendList
                      : popularController.bangumiList,
                );
              })),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: immersiveTabBarInset(context) + 16,
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: immersiveTabBarInset(context) - 20),
        child: FloatingActionButton(
          onPressed: () => scrollController.animateTo(
            0,
            duration: KazumiMotion.slow,
            curve: KazumiMotion.emphasized,
          ),
          child: const Icon(Icons.arrow_upward),
        ),
      ),
    );
  }

  /// 标签横滑条：替代原来的下拉菜单，去掉弹层与边框。
  Widget _buildTagBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: Observer(
        builder: (_) {
          final current = popularController.currentTag;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: defaultAnimeTags.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final tag = index == 0 ? '' : defaultAnimeTags[index - 1];
              final selected = tag == current;
              final TextStyle labelStyle = theme.textTheme.labelLarge!.copyWith(
                color: selected ? colors.primary : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
              return Pressable(
                pressedScale: 0.94,
                onTap: () => _selectTag(tag),
                child: AnimatedSwitcher(
                  duration: KazumiMotion.scale(context, KazumiMotion.fast),
                  switchInCurve: KazumiMotion.standard,
                  switchOutCurve: KazumiMotion.standard,
                  child: selected && isNeuLayout(context)
                      // 拟态下选中态用凹槽 + 强调色文字，不再铺实色块——
                      // 实色块会把拟态的层次压平。
                      ? NeuSurface(
                          key: ValueKey<String>('on-$tag'),
                          mode: NeuMode.recess,
                          radius: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Text(tag.isEmpty ? '热门番组' : tag,
                                style: labelStyle),
                          ),
                        )
                      : Padding(
                          key: ValueKey<String>('off-$tag'),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Text(tag.isEmpty ? '热门番组' : tag,
                                style: labelStyle),
                          ),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget contentGrid(List<BangumiItem> bangumiList) {
    // 桌面宽屏：不再按断点数死列数，卡片宽度封顶 210，窗口越宽列数越多，
    // 拖窗口时不会突然从 6 列跳成 5 列。
    if (isDesktopWideLayout(context)) {
      const double maxCardWidth = 210;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          NeuSpacing.pagePadding,
          8,
          NeuSpacing.pagePadding,
          0,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCardWidth,
            mainAxisSpacing: NeuSpacing.gap + 4,
            crossAxisSpacing: NeuSpacing.gap,
            mainAxisExtent: maxCardWidth / 0.65 +
                MediaQuery.textScalerOf(context).scale(32.0),
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              // 列表还没回来时铺骨架屏：和真卡片同尺寸，内容一到就原地替换，
              // 不会整块跳一下。
              return bangumiList.isNotEmpty
                  ? BangumiCardV(bangumiItem: bangumiList[index])
                  : const BangumiCardSkeleton();
            },
            childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
          ),
        ),
      );
    }
    int crossCount = 3;
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.compact['width']!) {
      crossCount = 5;
    }
    if (MediaQuery.sizeOf(context).width > LayoutBreakpoint.medium['width']!) {
      crossCount = 6;
    }
    // 拟态卡片是「凸起面板」：四周有内边距，标题占两行，还有一行评分。
    // 封面高度要按卡片**实际可用宽度**算，不能拿屏宽除列数——不然封面
    // 会被内边距和文字挤扁。
    //
    // 尾部的固定开销宁可算多一点：卡片里封面是 `Expanded`，高度不够会直接
    // 溢出报错，多算了只是封面略高一点，看不出来。
    // 14 = 上下内边距 7×2，7 = 封面与标题间距，3 = 标题与评分间距，
    // 30 = 两行标题，16 = 评分行。改卡片布局要跟着改这里。
    const double pad = 8;
    final double cellWidth = (MediaQuery.sizeOf(context).width -
            pad * 2 -
            StyleString.cardSpace * (crossCount - 1)) /
        crossCount;
    final double neuExtent = (cellWidth - 14) / 0.65 +
        14 +
        7 +
        MediaQuery.textScalerOf(context).scale(30) +
        3 +
        MediaQuery.textScalerOf(context).scale(16);

    return SliverPadding(
      padding: const EdgeInsets.all(pad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // 行间距
          mainAxisSpacing: StyleString.cardSpace + 4,
          // 列间距
          crossAxisSpacing: StyleString.cardSpace,
          // 列数
          crossAxisCount: crossCount,
          mainAxisExtent: isNeuLayout(context)
              ? neuExtent
              : MediaQuery.of(context).size.width / crossCount / 0.65 +
                  MediaQuery.textScalerOf(context).scale(32.0),
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return bangumiList.isNotEmpty
                ? BangumiCardV(bangumiItem: bangumiList[index])
                : const BangumiCardSkeleton(compact: true);
          },
          childCount: bangumiList.isNotEmpty ? bangumiList.length : 10,
        ),
      ),
    );
  }

  Widget buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      toolbarHeight: kToolbarHeight + 4,
      title: isDesktopWideLayout(context)
          ? Text(
              '推荐',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            )
          : null,
      actions: buildActions(),
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(child: const SizedBox.expand()),
      ),
    );
  }

  List<Widget> buildActions() {
    return <Widget>[
      if (MediaQuery.of(context).orientation == Orientation.portrait)
        IconButton(
          tooltip: '搜索',
          onPressed: () => context.pushNamed('/search/'),
          icon: const Icon(Icons.search),
        ),
      IconButton(
        tooltip: '历史记录',
        onPressed: () => context.pushNamed('/settings/history/'),
        icon: const Icon(Icons.history),
      ),
      if (isDesktop() && DesktopWindowConfig.frameless)
        const DesktopWindowControls()
      else if (isDesktop() && !DesktopWindowConfig.showWindowButton)
        IconButton(
          tooltip: '退出',
          onPressed: () => windowManager.close(),
          icon: const Icon(Icons.close),
        ),
    ];
  }

  Future<void> _selectTag(String selected) async {
    if (!mounted || selected == popularController.currentTag) return;
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    popularController.setCurrentTag(selected);
    if (selected.isEmpty) {
      popularController.clearBangumiList();
      if (popularController.trendList.isEmpty) {
        await popularController.queryBangumiByTrend();
      }
    } else {
      await popularController.queryBangumiByTag(type: 'init');
    }
  }
}
