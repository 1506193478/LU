import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// 全局滚动物理。
///
/// 三端统一成带阻尼的那一套：松手后减速更连贯，不会像 Android 默认的
/// Clamping 那样"到边就硬停"。外层挂 AlwaysScrollable，是为了让内容不足
/// 一屏的列表也能下拉（不然短列表拉不动，观感上像卡死）。
const ScrollPhysics kazumiScrollPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// 全局滚动行为：物理统一 + 去掉 Android 的拉伸过冲 + 桌面端支持鼠标拖拽。
///
/// 原来各列表自己写 physics，`Clamping` / `Bouncing` 混着用，同一个 App
/// 里滚动手感不一致；Android 上还叠了一层 Material 的 stretch 过冲，跟
/// Bouncing 的阻尼回弹是两套反馈，一起出现会显得"弹两下"。
class KazumiScrollBehavior extends MaterialScrollBehavior {
  const KazumiScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => kazumiScrollPhysics;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Bouncing 自己的过冲就是反馈，再叠 stretch/glow 会重复。
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
