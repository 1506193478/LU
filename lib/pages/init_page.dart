import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/clay.dart';
import 'package:XL/pages/my/my_controller.dart';
import 'package:XL/services/sync/bangumi_sync_service.dart';
import 'package:XL/services/sync/danmaku_shield_sync_service.dart';
import 'package:XL/services/sync/webdav.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/plugins/plugins_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/pages/collect/collect_controller.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/services/shaders/shader_asset_service.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/plugin_editor/plugin_update_actions.dart';
import 'package:XL/services/download/background_download_service.dart';
import 'package:XL/services/platform/windows_shortcut.dart';
import 'package:XL/services/platform/platform_environment_service.dart';
import 'package:XL/services/platform/app_exit.dart';
import 'package:XL/services/update/startup_update_check.dart';
import 'package:XL/navigation.dart';

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.downloadController,
    required this.danmakuShieldSync,
  });

  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DownloadController downloadController;
  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  PluginsController get pluginsController => widget.pluginsController;
  CollectController get collectController => widget.collectController;
  ShaderAssetService get shaderAssetService => widget.shaderAssetService;
  MyController get myController => widget.myController;
  DownloadController get downloadController => widget.downloadController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    widget.danmakuShieldSync.start();
    _migrateStorage();
    _loadShaders();
    unawaited(myController.loadShieldList());
    _webDavInit();
    _bangumiInit();
    try {
      await downloadController.init();
      _setupBackgroundDownloadNavigation();
    } catch (e) {
      KazumiLogger().e('InitPage: downloadController.init() failed', error: e);
    }

    await _checkRunningOnX11();
    await _showShortcutDialog();
    await _pluginInit();

    if (!mounted) {
      return;
    }
    // Installs that predate the flag already have rules; don't re-onboard them.
    if (!GStorage.getSetting(SettingsKeys.onboardingCompleted) &&
        pluginsController.pluginList.isEmpty) {
      context.navigate('/onboarding');
      return;
    }

    final updateController = myController;
    unawaited(runStartupUpdateCheck(
      isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
      checkForUpdate: () => updateController.checkUpdate(type: 'auto'),
    ));
    context.navigate(
      GStorage.getSetting(SettingsKeys.defaultStartupPage) == '/tab/timeline/'
          ? '/tab/popular/'
          : GStorage.getSetting(SettingsKeys.defaultStartupPage),
    );
  }

  void _setupBackgroundDownloadNavigation() {
    final backgroundService = BackgroundDownloadService();

    backgroundService.onNavigateToDownloadRequested = () {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final navigationContext = rootNavigatorKey.currentContext;
          if (navigationContext == null || !navigationContext.mounted) return;
          final path = navigationContext.routeState(listen: false).uri.path;
          if (path.contains('/download')) return;
          navigationContext.pushNamed('/settings/download/');
        } catch (e) {
          KazumiLogger()
              .w('InitPage: failed to navigate to download page', error: e);
        }
      });
    };

    backgroundService.onNotificationPermissionRequired = () async {
      final result = await KazumiDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) {
          return ClayDialog(
            title: '需要通知权限',
            icon: Icons.notifications_active_outlined,
            message: '开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n'
                '如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。',
            actions: [
              ClayButton(
                tone: ClayTone.subtle,
                height: 44,
                onPressed: () => KazumiDialog.dismiss(popWith: false),
                child: const Text('稍后再说'),
              ),
              ClayButton(
                tone: ClayTone.accent,
                height: 44,
                onPressed: () => KazumiDialog.dismiss(popWith: true),
                child: const Text('允许'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    };
  }

  // migrate collect from old version (favorites)
  Future<void> _migrateStorage() async {
    await collectController.migrateCollect();
  }

  Future<void> _loadShaders() async {
    await shaderAssetService.copyShadersToExternalDirectory();
  }

  Future<void> _webDavInit() async {
    bool webDavEnable = await GStorage.getSetting(SettingsKeys.webDavEnable);
    bool webDavEnableHistory =
        await GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    if (webDavEnable) {
      var webDav = WebDav();
      KazumiLogger().i('WebDav: Starting WebDav initialization');
      try {
        await webDav.init();
        await widget.danmakuShieldSync.syncIfEnabled();
        if (webDavEnableHistory) {
          try {
            await webDav.syncHistory();
            KazumiLogger().i('WebDav: Completed syncing watch history');
          } catch (e, stackTrace) {
            KazumiLogger().w(
              'WebDav: automatic watch history sync failed',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'WebDav: automatic initialization failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _bangumiInit() async {
    final bangumiEnable = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    if (bangumiEnable) {
      final bangumi = BangumiSyncService();
      KazumiLogger().i('Bangumi: Starting Bangumi initialization');
      try {
        await bangumi.ping();
      } catch (e) {
        KazumiLogger().w(
          'Bangumi: initialization failed; keeping sync enabled for retry',
          error: e,
        );
        KazumiDialog.showToast(
          message:
              'Bangumi 暂未连接，同步设置已保留：${BangumiSyncService.describeError(e)}',
        );
      }
    }
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: ClayDialog(
              title: 'X11 环境检测',
              icon: Icons.desktop_windows_outlined,
              message:
                  '检测到您当前运行在 X11 环境下，LU 在 X11 环境下可能出现性能问题或界面异常，'
                  '建议切换到 Wayland 以获得更好的体验。您是否希望在 X11 下继续使用 LU？',
              actions: [
                ClayButton(
                  tone: ClayTone.subtle,
                  height: 44,
                  onPressed: AppExit.quit,
                  child: const Text('退出'),
                ),
                ClayButton(
                  tone: ClayTone.accent,
                  height: 44,
                  onPressed: () {
                    KazumiDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await KazumiDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => ClayDialog(
        title: '创建桌面快捷方式',
        icon: Icons.desktop_access_disabled_outlined,
        message: '是否在桌面创建 LU 的快捷方式？',
        actions: [
          ClayButton(
            tone: ClayTone.subtle,
            height: 44,
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: const Text('暂不创建'),
          ),
          ClayButton(
            tone: ClayTone.accent,
            height: 44,
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      KazumiDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  Future<void> _pluginInit() async {
    try {
      await pluginsController.init();
      unawaited(_pluginUpdate());
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'Plugin: failed to initialize rules',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pluginUpdate() async {
    final checkOnStartup =
        GStorage.getSetting(SettingsKeys.checkPluginUpdateOnStartup);
    late final int count;
    try {
      count = await pluginsController.checkPluginUpdatesOnStartup(
        enabled: checkOnStartup,
      );
    } catch (_) {
      return;
    }
    if (count != 0) {
      KazumiDialog.showToast(
        message: '检测到 $count 条规则可以更新',
        showActionButton: true,
        actionLabel: '全部更新',
        onActionPressed: () => updateAllPluginsWithFeedback(
          pluginsController,
          ensureCatalog: false,
        ),
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
