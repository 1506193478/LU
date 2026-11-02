import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/network/metered_network_service.dart';
import 'package:XL/services/platform/app_exit.dart';
import 'package:XL/services/platform/tray_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/dialog/exit_confirmation_dialog.dart';
import 'package:XL/bean/widget/window_shell.dart';
import 'package:XL/bean/settings/theme_provider.dart';
import 'package:XL/navigation.dart';
import 'package:XL/utils/device.dart';
import 'package:XL/utils/immersive_theme.dart';
import 'package:XL/utils/scroll_behavior.dart';
import 'package:XL/utils/theme.dart';

class AppWidget extends StatefulWidget {
  const AppWidget({super.key});

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget>
    with TrayListener, WidgetsBindingObserver, WindowListener {
  final TrayManager trayManager = TrayManager.instance;
  bool _isHandlingWindowClose = false;
  bool _didApplyStoredThemeSettings = false;
  Brightness? _lastTitleBarBrightness;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _initializePlatformIntegrations();
  }

  Future<void> _initializePlatformIntegrations() async {
    if (isDesktop()) {
      await windowManager.setPreventClose(true);
      await TrayService.initialize();
    }
    await _configurePreferredDisplayMode();
  }

  Future<void> _configurePreferredDisplayMode() async {
    if (!Platform.isAndroid) return;

    try {
      final modes = await FlutterDisplayMode.supported;
      final storageDisplay = GStorage.getSetting(SettingsKeys.displayMode);
      DisplayMode selectedMode = DisplayMode.auto;
      if (storageDisplay != null) {
        selectedMode = modes.firstWhere(
          (e) => e.toString() == storageDisplay,
          orElse: () => DisplayMode.auto,
        );
      }
      final preferred = modes.firstWhere(
        (el) => el == selectedMode,
        orElse: () => DisplayMode.auto,
      );
      await FlutterDisplayMode.setPreferredMode(preferred);
    } catch (e) {
      KazumiLogger().e('DisPlay: set preferred mode failed', error: e);
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = context.watch<ThemeProvider>();
    _applyStoredThemeSettings(themeProvider);
    _syncWindowsTitleBarBrightness(themeProvider);
  }

  /// 一次性迁移：把老用户身上开着的「动态取色」关掉。
  ///
  /// 这一版的视觉以固定紫色为基准，动态取色会让主色跟着系统强调色走
  /// （在 Windows 上就是系统主题色，可能是绿的），与设计稿对不上。
  /// 只关一次，之后用户在「外观设置」里想开还是能开。
  void _migrateAccentOnce() {
    if (GStorage.getSetting(SettingsKeys.uiAccentMigrated)) return;
    GStorage.putSetting(SettingsKeys.uiAccentMigrated, true);
    if (GStorage.getSetting(SettingsKeys.useDynamicColor)) {
      GStorage.putSetting(SettingsKeys.useDynamicColor, false);
    }
  }

  void _applyStoredThemeSettings(ThemeProvider themeProvider) {
    if (_didApplyStoredThemeSettings) return;
    _didApplyStoredThemeSettings = true;
    _migrateAccentOnce();

    themeProvider.setThemeMode(_storedThemeMode(), notify: false);
    themeProvider.setDynamic(
      GStorage.getSetting(SettingsKeys.useDynamicColor),
      notify: false,
    );
    themeProvider.setFontFamily(
      GStorage.getSetting(SettingsKeys.useSystemFont),
      notify: false,
    );

    final color = _storedThemeColor();
    final oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    final defaultDarkTheme = _buildAppTheme(
      brightness: Brightness.dark,
      color: color,
      fontFamily: themeProvider.currentFontFamily,
    );
    themeProvider.setTheme(
      _buildAppTheme(
        brightness: Brightness.light,
        color: color,
        fontFamily: themeProvider.currentFontFamily,
      ),
      oledEnhance ? oledDarkTheme(defaultDarkTheme) : defaultDarkTheme,
      notify: false,
    );
  }

  ThemeMode _storedThemeMode() {
    return switch (GStorage.getSetting(SettingsKeys.themeMode)) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  Color _storedThemeColor() {
    final defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    if (defaultThemeColor == 'default') {
      return kDefaultAccent;
    }
    return Color(int.parse(defaultThemeColor, radix: 16));
  }

  ThemeData _buildAppTheme({
    required Brightness brightness,
    required String? fontFamily,
    Color? color,
    ColorScheme? colorScheme,
  }) {
    return buildImmersiveTheme(
      brightness: brightness,
      color: color,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
    );
  }

  void _syncWindowsTitleBarBrightness(ThemeProvider themeProvider) {
    if (!Platform.isWindows) return;

    final brightness =
        themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light;
    if (_lastTitleBarBrightness == brightness) return;

    _lastTitleBarBrightness = brightness;
    windowManager.setBrightness(brightness).catchError((e) {
      KazumiLogger().w('Window: set title bar brightness failed', error: e);
    });
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
      case 'exit':
        AppExit.quit();
    }
  }

  // windowManager.close() triggers this handler; exit() bypasses confirmation.
  @override
  Future<void> onWindowClose() async {
    if (_isHandlingWindowClose || !mounted) return;
    _isHandlingWindowClose = true;
    try {
      var action = switch (GStorage.getSetting(SettingsKeys.exitBehavior)) {
        0 => ExitDialogAction.exit,
        1 => ExitDialogAction.minimizeToTray,
        _ => null,
      };
      if (action == null) {
        final result = await KazumiDialog.show<ExitDialogResult>(
          builder: (_) => const ExitConfirmationDialog(),
        );
        if (result == null || !mounted) return;

        action = result.action;
        if (result.rememberChoice) {
          await GStorage.putSetting(
            SettingsKeys.exitBehavior,
            switch (action) {
              ExitDialogAction.exit => 0,
              ExitDialogAction.minimizeToTray => 1,
            },
          );
        }
      }

      if (!mounted) return;
      switch (action) {
        case ExitDialogAction.exit:
          await AppExit.quit();
        case ExitDialogAction.minimizeToTray:
          await windowManager.hide();
      }
    } finally {
      _isHandlingWindowClose = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      KazumiLogger()
          .i("AppLifecycleState.paused: Application moved to background");
    } else if (state == AppLifecycleState.resumed) {
      KazumiLogger()
          .i("AppLifecycleState.resumed: Application moved to foreground");
      await MeteredNetworkService.refresh();
    } else if (state == AppLifecycleState.inactive) {
      KazumiLogger().i("AppLifecycleState.inactive: Application is inactive");
    }
  }

  @override
  Future<void> didChangePlatformBrightness() async {
    super.didChangePlatformBrightness();
    final ThemeProvider themeProvider = context.read<ThemeProvider>();
    KazumiLogger().i(
        "Platform brightness changed, themeMode: ${themeProvider.themeMode}");

    _syncWindowsTitleBarBrightness(themeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    bool oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);

    var app = DynamicColorBuilder(
      builder: (theme, darkTheme) {
        final useDynamicColor =
            themeProvider.useDynamicColor && theme != null && darkTheme != null;
        final lightTheme = useDynamicColor
            ? _buildAppTheme(
                brightness: Brightness.light,
                colorScheme: theme,
                fontFamily: themeProvider.currentFontFamily,
              )
            : themeProvider.light;
        final dynamicDarkTheme = useDynamicColor
            ? _buildAppTheme(
                brightness: Brightness.dark,
                colorScheme: darkTheme,
                fontFamily: themeProvider.currentFontFamily,
              )
            : themeProvider.dark;
        final effectiveDarkTheme = useDynamicColor && oledEnhance
            ? oledDarkTheme(dynamicDarkTheme)
            : dynamicDarkTheme;

        return MaterialApp.router(
          title: "LU",
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale.fromSubtags(
                languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
          ],
          locale: const Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
          theme: lightTheme,
          darkTheme: effectiveDarkTheme,
          themeMode: themeProvider.themeMode,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          // 全局滚动手感统一，见 utils/scroll_behavior.dart。
          scrollBehavior: const KazumiScrollBehavior(),
          routerConfig: ModularApp.routerConfigOf(context),
          // 无边框模式下套一层圆角外壳（透明窗口 + 自绘圆角 + 缩放热区）。
          // 开屏视频动画已移除：原生 launch 画面直接交棒给首页首帧，
          // 首页本身用淡入完成"丝滑过渡"。
          builder: (context, child) => WindowShell(
            child: _HomeFadeIn(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );

    return app;
  }
}

/// 首页淡入。
///
/// 开屏视频去掉之后，原生 launch 画面会直接交棒给 Flutter 的第一帧。
/// 直接交棒会有一次"啪一下贴上来"的生硬切换，这里给整个 App 外壳套一个
/// 一次性的短淡入（260ms），观感上是"揭幕"而不是"切换"。
///
/// 注意只做淡入、不做缩放：缩放会让首帧的内容看起来在"漂"，而淡入是
/// 无位移的，不会暴露启动时列表还在加载的事实。
/// 系统开了「减少动态效果」时直接跳过，不给动画。
class _HomeFadeIn extends StatefulWidget {
  const _HomeFadeIn({required this.child});

  final Widget child;

  @override
  State<_HomeFadeIn> createState() => _HomeFadeInState();
}

class _HomeFadeInState extends State<_HomeFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // 等下一帧再置 true：保证首帧是透明的、渐变从 0 起步，
    // 否则第一帧就已经是 1，淡入等于没做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
