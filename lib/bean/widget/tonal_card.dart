import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay.dart';

const double tonalCardRadius = 24;

/// 内容卡片。
///
/// 原本是一层 `surfaceContainerLow` 纯色，第四批起换成粘土底板：
/// 受光渐变 + 落地阴影，和按钮、拨杆是同一套材质语言。
/// 类名与 API 保持不变，全项目 16 处调用不用改。
class TonalCard extends StatelessWidget {
  const TonalCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => ClayPanel(
        radius: tonalCardRadius,
        padding: padding,
        child: child,
      );
}
