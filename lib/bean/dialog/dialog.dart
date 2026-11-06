import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:XL/bean/dialog/ios_hud.dart';
import 'package:XL/navigation.dart';
import 'package:XL/theme/ios_interaction.dart';
import 'package:XL/utils/constants.dart';

/// Single-use ownership of a route, including before its first frame.
class KazumiDialogHandle<T> {
  Route<T>? _route;
  bool _used = false;
  bool _dismissed = false;

  bool get isActive => !_dismissed && (_route?.isActive ?? false);

  void dismiss({T? popWith}) {
    if (_dismissed) return;
    _dismissed = true;
    final route = _route;
    if (route != null) KazumiDialog._dismissRoute(route, popWith);
  }

  void _attach(Route<T> route) {
    _used = true;
    _route = route;
  }

  void _finish() {
    _dismissed = true;
    _route = null;
  }
}

class KazumiDialog {
  static final KazumiDialogObserver observer = KazumiDialogObserver();
  // Allows modal sheets to use the same dismissal and route tracking.
  static const routeSettings = RouteSettings(name: 'KazumiDialog');
  static int _toastRevision = 0;

  KazumiDialog._internal();

  static Future<T?> show<T>({
    BuildContext? context,
    KazumiDialogHandle<T>? handle,
    bool clickMaskDismiss = true,
    FutureOr<void> Function()? onDismiss,
    Duration? transitionDuration,
    RouteTransitionsBuilder? transitionBuilder,
    required WidgetBuilder builder,
  }) async {
    final dialog = handle ?? KazumiDialogHandle<T>();
    if (dialog._used) {
      throw StateError('A dialog handle can only be used once.');
    }
    try {
      final ctx = context ??
          rootNavigatorKey.currentContext ??
          observer.navigator?.context;
      if (ctx == null || !ctx.mounted || dialog._dismissed) return null;
      final navigator = Navigator.of(ctx, rootNavigator: true);
      final route = _KazumiDialogRoute<T>(
        context: ctx,
        builder: builder,
        themes: InheritedTheme.capture(from: ctx, to: navigator.context),
        barrierColor: DialogTheme.of(ctx).barrierColor ??
            Theme.of(ctx).dialogTheme.barrierColor ??
            Colors.black54,
        barrierDismissible: clickMaskDismiss,
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        settings: routeSettings,
        animationStyle: transitionDuration == null
            ? null
            : AnimationStyle(duration: transitionDuration),
        transitionBuilder: transitionBuilder,
      );
      dialog._attach(route);
      return await navigator.push<T>(route);
    } catch (e) {
      debugPrint('Kazumi Dialog Error: Failed to show dialog: $e');
      return null;
    } finally {
      dialog._finish();
      await onDismiss?.call();
    }
  }

  static void showToast({
    required String message,
    BuildContext? context,
    bool showActionButton = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
    Duration duration = const Duration(seconds: 2),
  }) {
    // iOS：走 HUD（深色毛玻璃小浮层）。SnackBar 那种贴底黑条在 iOS 上
    // 不存在，而且会顶起底部导航，观感上就是"这 App 不像 iOS"。
    if (kIsCupertinoPlatform) {
      KzHud.show(
        message,
        duration: duration,
        actionLabel: showActionButton ? (actionLabel ?? '关闭') : null,
        onAction: onActionPressed,
      );
      return;
    }
    final messenger = _resolveScaffoldMessenger(context);
    if (messenger != null && messenger.mounted) {
      final toastContext =
          context != null && context.mounted ? context : messenger.context;
      try {
        _toastRevision++;
        messenger
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              width: MediaQuery.sizeOf(toastContext).width >
                      LayoutBreakpoint.medium['width']!
                  ? 600
                  : null,
              duration: duration,
              persist: false,
              action: showActionButton
                  ? SnackBarAction(
                      label: actionLabel ?? 'Dismiss',
                      onPressed: () {
                        // Let SnackBarAction close the old toast before replacing it.
                        if (onActionPressed != null) {
                          scheduleMicrotask(onActionPressed);
                        }
                      },
                    )
                  : null,
            ),
          );
      } catch (e) {
        debugPrint('Kazumi Dialog Error: Failed to show toast: $e');
      }
    } else {
      debugPrint(
          'Kazumi Dialog Error: No ScaffoldMessenger available to show Toast');
    }
  }

  /// 错误播报的统一入口。
  ///
  /// 「所有报错长得一样」这件事以前做不到：一部分走 showToast（居中黑玻璃）、
  /// 一部分走 showDialog（系统弹窗）、一部分干脆只写进日志。现在报错统一走
  /// 底部胶囊通知：整宽减 14、圆角 14、铃铛图标、3 秒自动落下，和系统通知
  /// 横幅一个形态。
  ///
  /// 成功/提示类仍然用 [showToast]——「已收藏」不该和「播放失败」长得一样。
  static void showError({
    required String message,
    BuildContext? context,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (message.trim().isEmpty) return;
    if (kIsCupertinoPlatform) {
      KzHud.showNotice(message, duration: duration);
      return;
    }
    showToast(message: message, context: context, duration: duration);
  }

  /// 按文案自动分流：看着像报错的走 [showError]，其余走 [showToast]。
  ///
  /// 存在的理由：页面里普遍有一个 `void _toast(msg)` 包装，几十个调用点混着
  /// 「已收藏」和「保存失败」。逐个改调用点做不到不漏，所以在这一层按关键词
  /// 判一次——这是启发式，不是精确语义；新写的代码请直接调
  /// [showError] / [showToast]，别依赖它。
  static void notify(String message) {
    if (message.trim().isEmpty) return;
    const List<String> hints = [
      '失败',
      '错误',
      '无法',
      '不能',
      '超时',
      '异常',
      '不可用',
      '未连接',
      '拒绝',
      'forbidden',
      'error',
      'failed',
      'timeout',
    ];
    final String lower = message.toLowerCase();
    final bool isError = hints.any(
      (h) => message.contains(h) || lower.contains(h),
    );
    if (isError) {
      showError(message: message);
    } else {
      showToast(message: message);
    }
  }

  static void dismiss<T>({BuildContext? context, T? popWith}) {
    if (context != null && !context.mounted) return;
    final route =
        context == null ? observer._lastDialogRoute : ModalRoute.of(context);
    if (route != null && route.settings.name == routeSettings.name) {
      _dismissRoute(route, popWith);
    }
  }

  static void _dismissRoute<T>(Route<T> route, T? result) {
    if (!route.isActive) return;
    // Owners may be disposed while Navigator is reconciling its routes.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dismissRoute(route, result);
      });
      return;
    }
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted) return;
    if (route.isCurrent) {
      navigator.pop<T>(result);
    } else {
      navigator.removeRoute<T>(route, result);
    }
  }

  static ScaffoldMessengerState? _resolveScaffoldMessenger(
    BuildContext? context,
  ) {
    if (context != null && context.mounted) {
      final scopedMessenger = ScaffoldMessenger.maybeOf(context);
      if (scopedMessenger != null) {
        return scopedMessenger;
      }
    }
    return rootScaffoldMessengerKey.currentState;
  }
}

class _KazumiDialogRoute<T> extends DialogRoute<T> {
  _KazumiDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.traversalEdgeBehavior,
    super.settings,
    super.animationStyle,
    this.transitionBuilder,
  });

  final RouteTransitionsBuilder? transitionBuilder;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      transitionBuilder?.call(context, animation, secondaryAnimation, child) ??
      super.buildTransitions(context, animation, secondaryAnimation, child);
}

class KazumiDialogObserver extends NavigatorObserver {
  final List<Route<dynamic>> _kazumiDialogRoutes = [];
  bool _snackBarClearScheduled = false;

  bool get hasKazumiDialog => _kazumiDialogRoutes.isNotEmpty;

  Route<dynamic>? get _lastDialogRoute =>
      _kazumiDialogRoutes.isEmpty ? null : _kazumiDialogRoutes.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isKazumiDialogRoute(route)) {
      _kazumiDialogRoutes.add(route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) _scheduleSnackBarClear();
    if (_isKazumiDialogRoute(route)) {
      _kazumiDialogRoutes.remove(route);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is PageRoute) _scheduleSnackBarClear();
    if (_isKazumiDialogRoute(oldRoute)) {
      _kazumiDialogRoutes.remove(oldRoute);
    }
    if (newRoute != null && _isKazumiDialogRoute(newRoute)) {
      _kazumiDialogRoutes.add(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute) _scheduleSnackBarClear();

    if (_isKazumiDialogRoute(route)) {
      _kazumiDialogRoutes.remove(route);
    }
  }

  bool _isKazumiDialogRoute(Route<dynamic>? route) =>
      route?.settings.name == KazumiDialog.routeSettings.name;

  void _scheduleSnackBarClear() {
    if (_snackBarClearScheduled) return;
    _snackBarClearScheduled = true;
    final revision = KazumiDialog._toastRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snackBarClearScheduled = false;
      // Only clear the old page's toast, never one posted after navigation.
      if (revision == KazumiDialog._toastRevision) {
        rootScaffoldMessengerKey.currentState?.removeCurrentSnackBar();
      }
    });
  }
}
