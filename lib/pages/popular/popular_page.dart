import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/widget/bangumi_mirror_error_widget.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/bean/widget/clay_neu.dart' show isDesktopWideLayout;
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
import 'package:XL/theme/rex_design.dart';
import 'package:XL/theme/rex_big_view.dart';
import 'package:flutter/services.dart';

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
    // 手机端首屏是通栏大视图：图片顶到状态栏底下，顶栏只留浮动操作。
    // 桌面宽屏维持「标题栏 + 卡片横幅」，通栏图在宽窗口会把标题拉得太长。
    final bool mobileBigView = !isDesktopWideLayout(context);
    return Scaffold(
      backgroundColor: PvColors.page(context),
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          if (mobileBigView)
            SliverToBoxAdapter(child: Observer(builder: (_) => _buildBigView()))
          else ...[
            buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Observer(builder: (_) => _buildHero()),
            ),
          ],
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
    return SizedBox(
      height: 52,
      child: Observer(
        builder: (_) {
          final current = popularController.currentTag;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: defaultAnimeTags.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final tag = index == 0 ? '' : defaultAnimeTags[index - 1];
              final selected = tag == current;
              return Pressable(
                pressedScale: 0.94,
                onTap: () => _selectTag(tag),
                child: AnimatedContainer(
                  key: ValueKey<String>('$selected-$tag'),
                  duration: KazumiMotion.scale(context, KazumiMotion.fast),
                  curve: KazumiMotion.standard,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Pv 的选中就是淡蓝胶囊 + 蓝字，不用凹槽。
                    color: selected
                        ? PvColors.subCap(context)
                        : PvColors.card(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag.isEmpty ? '热门番组' : tag,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? PvColors.subInk(context)
                          : PvColors.ink2(context),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCardWidth,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
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
    // Pv 卡片是白底圆角 + 下方两行文字，高度按卡片宽度等比算就够了，
    // 不需要再为拟态的厚度额外加那几十 dp。
    final double cardExtent = cellWidth / 0.65 +
        MediaQuery.textScalerOf(context).scale(32.0);

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
          mainAxisExtent: cardExtent,
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
    final bool desktop = isDesktopWideLayout(context);
    return SliverAppBar(
      pinned: false,
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      toolbarHeight: desktop ? kToolbarHeight + 4 : kToolbarHeight + 10,
      automaticallyImplyLeading: false,
      titleSpacing: desktop ? 24 : 18,
      title: Text(
        '推荐',
        style: RexText.display.copyWith(
          color: RexPalette.of(context).inkPrimary,
          fontSize: desktop ? 28 : 26,
        ),
      ),
      actions: buildActions(),
      flexibleSpace: SafeArea(
        child: dtb.DragToMoveArea(child: const SizedBox.expand()),
      ),
    );
  }

  /// 通栏主视觉：取热榜第一条当封面。
  ///
  /// Rex 的发现页第一屏就是这个东西——先给一张大图定调，再往下才是货架。
  /// 这里只在「全部」标签下显示，切到具体标签后直接给网格，免得切一次标签
  /// 顶部还挂着一张跟当前筛选无关的图。
  Widget _buildHero() {
    if (popularController.currentTag.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final list = popularController.trendList;
    if (list.isEmpty) return const SizedBox.shrink();
    final item = list.first;
    final cover = item.images['large'] ?? item.images['common'] ?? '';
    final meta = <String>[
      if (item.ratingScore > 0) '${item.ratingScore.toStringAsFixed(1)} 分',
      if (item.airDate.isNotEmpty) item.airDate,
      if (item.tags.isNotEmpty) item.tags.take(2).map((t) => t.name).join(' / '),
    ].where((e) => e.isNotEmpty).join('  ·  ');

    return RexHeroBanner(
      imageUrl: cover,
      title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
      subtitle: meta,
      eyebrow: '本周热门',
      primaryLabel: '查看详情',
      primaryIcon: Icons.arrow_forward_rounded,
      onPrimary: () => context.pushNamed('/info/', arguments: item),
    );
  }

  /// 通栏大视图轮播：取热榜前 5 条。
  ///
  /// 图片顶到状态栏底下，标题/评分/简介压在底部渐隐区上；
  /// 状态栏图标在图上是白的，滚过大图之后跟主题走。
  Widget _buildBigView() {
    final RexPalette p = RexPalette.of(context);
    final list = popularController.currentTag.isEmpty
        ? popularController.trendList
        : const <BangumiItem>[];
    final items = <RexBigViewItem>[
      for (final item in list.take(5))
        RexBigViewItem(
          imageUrl:
              item.images['large'] ?? item.images['common'] ?? '',
          title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
          score: item.ratingScore > 0
              ? item.ratingScore.toStringAsFixed(1)
              : null,
          year: item.airDate.isNotEmpty ? item.airDate.split('-').first : null,
          genres: item.tags.isEmpty
              ? null
              : item.tags.take(2).map((t) => t.name).join(' / '),
          desc: item.summary.trim().isEmpty ? null : item.summary.trim(),
          onTap: () => context.pushNamed('/info/', arguments: item),
        ),
    ];
    final double heroHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(380.0, 520.0);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool overImage = popularController.scrollOffset < heroHeight - 120;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overImage
          ? SystemUiOverlayStyle.light
          : (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
      child: RexBigViewCarousel(
        items: items,
        fadeColor: p.canvas,
        topOverlay: _BigViewTopBar(actions: buildActions()),
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

/// 大视图顶上的浮动操作行。
///
/// 图顶到状态栏底下之后没有 AppBar 了，搜索 / 历史 / 窗口控制改为
/// 浮在图片上方：图标转白并加投影，保证在亮色海报上也读得出来。
class _BigViewTopBar extends StatelessWidget {
  const _BigViewTopBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: Row(
          children: [
            const Spacer(),
            ...[
              for (final action in actions)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: action,
                  ),
                ),
            ],
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}
