import 'package:flutter/material.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/error_widget.dart';
import 'package:XL/bean/widget/state_presentation.dart';
import 'package:XL/pages/emby/emby_style.dart';
import 'package:XL/request/clients/emby_client.dart';

/// Emby 相关的通用小组件。
///
/// 这里刻意复用 [NeuSurface] / [EmbyImage]，而不是另起一套视觉：
/// 拟态面板的凸起和阴影参数在 [NeuTokens] 里统一管，新页面自己画一套
/// 很容易在浅色和深色两种模式下各偏一点。

/// 把异常翻成一句能给用户看的话。
String embyErrorMessage(Object error) {
  if (error is EmbyApiException) return error.message;
  return '请求失败：$error';
}

/// 统一的加载 / 报错 / 空状态包装。
class EmbyFutureView<T> extends StatelessWidget {
  const EmbyFutureView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
    this.onSwitchServer,
    this.isEmpty,
    this.loadingBuilder,
    this.emptyTitle = '这里是空的',
    this.emptyMessage = '换个媒体库看看，或者先在 Emby 服务端添加内容。',
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  /// 出错时的第二条出路。连不上就卡在这一页是最糟的体验，
  /// 必须能直接换一台服务器。
  final VoidCallback? onSwitchServer;
  final bool Function(T data)? isEmpty;

  /// 加载态自定义占位。详情页用它画「封面大图骨架」——转场动画期间
  /// 直接就是这部剧的封面，而不是一整页黑底 + 居中转圈。
  final WidgetBuilder? loadingBuilder;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return loadingBuilder?.call(context) ??
              const Center(child: KzLoading());
        }
        if (snapshot.hasError) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: GeneralErrorWidget(
              title: '连不上 Emby',
              errMsg: embyErrorMessage(snapshot.error!),
              onRetry: onRetry,
              actions: [
                if (onSwitchServer != null)
                  TextButton(
                    onPressed: onSwitchServer,
                    child: const Text('换服务器'),
                  ),
              ],
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return _empty(context);
        }
        if (isEmpty?.call(data) ?? false) {
          return _empty(context);
        }
        return builder(context, data);
      },
    );
  }

  Widget _empty(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: GeneralErrorWidget(
      title: emptyTitle,
      errMsg: emptyMessage,
      icon: Icons.inbox_rounded,
      actions: [TextButton(onPressed: onRetry, child: const Text('刷新'))],
    ),
  );
}

/// 封面卡：媒体库和剧集列表共用。
///
/// 封面本身不叠双向阴影，只套一层 [NeuMedia] 的内描边——和番剧卡片
/// 踩过的坑一样，彩色海报上叠阴影会糊出一圈灰雾。
class EmbyPosterCard extends StatelessWidget {
  const EmbyPosterCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.aspectRatio = 0.68,
    this.trailing,
  });

  final String imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// 宽 / 高。剧集海报一般是 2:3，电影有时更宽。
  final double aspectRatio;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool neu = isNeuLayout(context);
    final double pad = isDesktopWideLayout(context) ? 10 : 7;
    final double radius = isDesktopWideLayout(context) ? NeuRadius.card : 18;

    final Widget cover = AspectRatio(
      aspectRatio: aspectRatio,
      child: neu
          ? NeuMedia(radius: radius - 6, child: _image(context))
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _image(context),
            ),
    );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        cover,
        SizedBox(height: neu ? 7 : 8),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final Widget body = Padding(
      padding: EdgeInsets.all(neu ? pad : 0),
      child: content,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: neu
              ? NeuSurface(radius: radius, onTap: onTap, child: body)
              : Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: onTap, child: body),
                ),
        ),
        if (trailing != null) Positioned(top: 6, right: 6, child: trailing!),
      ],
    );
  }

  Widget _image(BuildContext context) {
    return EmbyImage(url: imageUrl);
  }
}

/// 页面顶部的一句话说明，复用状态徽章的形状语言。
class EmbyIntro extends StatelessWidget {
  const EmbyIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StateIconBadge(
          icon: icon,
          size: 56,
          iconSize: 24,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.headlineSmall),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 空态。和 [EmbyFutureView] 的空态共用同一套版式，只是不带"刷新"按钮。
class GeneralEmbyEmpty extends StatelessWidget {
  const GeneralEmbyEmpty({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => GeneralErrorWidget(
    title: title,
    errMsg: message,
    icon: Icons.inbox_rounded,
    actions: [?action],
  );
}
