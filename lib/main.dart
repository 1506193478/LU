import 'dart:io';
import 'package:flutter/material.dart';
import 'package:XL/app_module.dart';
import 'package:XL/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:XL/services/deep_links/app_deep_links.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/services/download/download_directory_service.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:XL/services/network/metered_network_service.dart';
import 'package:XL/services/network/ech_http_licenses.dart';
import 'package:XL/services/network/proxy_manager.dart';
import 'package:XL/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:XL/utils/device.dart';
import 'package:XL/services/platform/desktop_window_config.dart';
import 'package:XL/services/platform/webview_feature_service.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDeepLinks().start();
  registerEchHttpLicenses();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  await DownloadDirectoryService().restoreAccess();
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final frameless = DesktopWindowConfig.frameless;
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // 窗口背景**不要**设成透明。
      //
      // 透明是为了让外壳裁出来的四个圆角能透出桌面，代价有两个：
      // 1. 整窗每一帧都要和桌面做一次 alpha 合成，拖拽缩放时掉帧特别明显；
      // 2. Windows 11 的 DWM 会给透明窗口区域叠一层背景模糊，于是四周出现
      //    一圈"莫名其妙的玻璃"——用户看到的就是这个。
      // 改成实色之后圆角不再透桌面，但那圈也就彻底没了。
      backgroundColor: null,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: frameless || Platform.isMacOS || !showWindowButton
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: frameless ? false : showWindowButton,
      title: 'LU',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (frameless) {
        // 只去系统边框，缩放交给 WindowShell 的八向热区；背景保持不透明。
        await windowManager.setAsFrameless();
      }
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
