import 'dart:io';

import 'package:XL/services/player/syncplay_endpoint.dart';
import 'package:XL/utils/device.dart';

enum SettingGroup {
  player,
  danmaku,
  theme,
  interface,
  proxy,
  webdav,
  emby,
  download,
  bangumi,
  collect,
  sync,
  update,
  misc,
}

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

// Add new settings here. SettingsKeys is the public typed registry used by
// callers; new keys can use literal string names directly.
class SettingsKeys {
  static const hAenable = SettingKey<bool>(
    _SettingBoxKey.hAenable,
    true,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    _SettingBoxKey.hardwareDecoder,
    'auto-safe',
    group: SettingGroup.player,
  );
  static const searchEnhanceEnable = SettingKey<bool>(
    _SettingBoxKey.searchEnhanceEnable,
    true,
    group: SettingGroup.misc,
  );
  static const autoUpdate = SettingKey<bool>(
    _SettingBoxKey.autoUpdate,
    true,
    group: SettingGroup.update,
  );
  static const checkPluginUpdateOnStartup = SettingKey<bool>(
    'checkPluginUpdateOnStartup',
    true,
    group: SettingGroup.update,
  );
  static const alwaysOntop = SettingKey<bool>(
    _SettingBoxKey.alwaysOntop,
    false,
    group: SettingGroup.misc,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultPlaySpeed,
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultShortcutForwardPlaySpeed,
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    _SettingBoxKey.defaultAspectRatioType,
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    _SettingBoxKey.buttonSkipTime,
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    _SettingBoxKey.arrowKeySkipTime,
    10,
    group: SettingGroup.player,
  );
  static const danmakuEnhance = SettingKey<bool>(
    _SettingBoxKey.danmakuEnhance,
    true,
    group: SettingGroup.danmaku,
  );
  /// Off on desktop and on on mobile, like the B 站 client.
  static final pauseOnDanmakuEdit = SettingKey<bool>(
    'pauseOnDanmakuEdit',
    true,
    group: SettingGroup.danmaku,
    defaultResolver: (_) => !isDesktop(),
  );
  static const danmakuBorder = SettingKey<bool>(
    _SettingBoxKey.danmakuBorder,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorderSize = SettingKey<double>(
    _SettingBoxKey.danmakuBorderSize,
    1.5,
    group: SettingGroup.danmaku,
  );
  static const danmakuOpacity = SettingKey<double>(
    _SettingBoxKey.danmakuOpacity,
    1.0,
    group: SettingGroup.danmaku,
  );
  static final danmakuFontSize = SettingKey<double>(
    _SettingBoxKey.danmakuFontSize,
    25.0,
    group: SettingGroup.danmaku,
    defaultResolver: (context) => context.compactLayout ? 16.0 : 25.0,
  );
  static const danmakuTop = SettingKey<bool>(
    _SettingBoxKey.danmakuTop,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuScroll = SettingKey<bool>(
    _SettingBoxKey.danmakuScroll,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBottom = SettingKey<bool>(
    _SettingBoxKey.danmakuBottom,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuMassive = SettingKey<bool>(
    _SettingBoxKey.danmakuMassive,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuDeduplication = SettingKey<bool>(
    _SettingBoxKey.danmakuDeduplication,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuChConvert = SettingKey<int>(
    'danmakuChConvert',
    0,
    group: SettingGroup.danmaku,
  );
  // 弹幕源：'bilibili' 免凭据；'dandanplay' 需要自备开放平台密钥。
  // 默认走 B 站，因为弹弹play 的空凭据请求一律被拒。
  static const danmakuSource = SettingKey<String>(
    'danmakuSource',
    'bilibili',
    group: SettingGroup.danmaku,
  );
  static const danmakuArea = SettingKey<double>(
    _SettingBoxKey.danmakuArea,
    1.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuColor = SettingKey<bool>(
    _SettingBoxKey.danmakuColor,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDuration = SettingKey<double>(
    _SettingBoxKey.danmakuDuration,
    8.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuLineHeight = SettingKey<double>(
    _SettingBoxKey.danmakuLineHeight,
    1.6,
    group: SettingGroup.danmaku,
  );
  static const danmakuTimeOffset = SettingKey<double>(
    _SettingBoxKey.danmakuTimeOffset,
    0.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuEnabledByDefault = SettingKey<bool>(
    _SettingBoxKey.danmakuEnabledByDefault,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuBiliBiliSource = SettingKey<bool>(
    _SettingBoxKey.danmakuBiliBiliSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuGamerSource = SettingKey<bool>(
    _SettingBoxKey.danmakuGamerSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDanDanSource = SettingKey<bool>(
    _SettingBoxKey.danmakuDanDanSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuFontWeight = SettingKey<int>(
    _SettingBoxKey.danmakuFontWeight,
    4,
    group: SettingGroup.danmaku,
  );
  static const danmakuFollowSpeed = SettingKey<bool>(
    _SettingBoxKey.danmakuFollowSpeed,
    true,
    group: SettingGroup.danmaku,
  );
  /// 内容沉浸型界面默认深色；手机端拟态风默认浅色。
  ///
  /// 拟态的光影逻辑在浅色下更像"一块被压出来的材料"，深色下反而容易糊；
  /// 桌面端大屏铺深色更沉浸，所以按平台分开给默认值。
  /// 用户在「外观设置」里改过之后以存储值为准，这里只影响首次启动。
  static final themeMode = SettingKey<String>(
    _SettingBoxKey.themeMode,
    'dark',
    group: SettingGroup.theme,
    defaultResolver: (_) => isDesktop() ? 'dark' : 'light',
  );
  static const themeColor = SettingKey<String>(
    _SettingBoxKey.themeColor,
    'default',
    group: SettingGroup.theme,
  );
  static const privateMode = SettingKey<bool>(
    _SettingBoxKey.privateMode,
    false,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    _SettingBoxKey.autoPlay,
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    _SettingBoxKey.autoPlayNext,
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    _SettingBoxKey.playResume,
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    _SettingBoxKey.showPlayerError,
    false,
    group: SettingGroup.player,
  );
  static const oledEnhance = SettingKey<bool>(
    _SettingBoxKey.oledEnhance,
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    _SettingBoxKey.displayMode,
    null,
    group: SettingGroup.interface,
  );
  static const enableGitProxy = SettingKey<bool>(
    _SettingBoxKey.enableGitProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableBangumiProxy = SettingKey<bool>(
    _SettingBoxKey.enableBangumiProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const imageAcceleration = SettingKey<String>(
    'imageAcceleration',
    'ech',
    group: SettingGroup.proxy,
  );
  // 新安装默认走 ECH（番剧条目）与 gh-proxy（规则仓库），与引导页一致。
  static const bangumiAcceleration = SettingKey<String>(
    'bangumiAcceleration',
    'ech',
    group: SettingGroup.proxy,
  );
  static const rulesMirror = SettingKey<String>(
    'rulesMirror',
    'ghProxy',
    group: SettingGroup.proxy,
  );
  static const enableSystemProxy = SettingKey<bool>(
    _SettingBoxKey.enableSystemProxy,
    false,
    group: SettingGroup.proxy,
  );
  static const defaultStartupPage = SettingKey<String>(
    _SettingBoxKey.defaultStartupPage,
    '/tab/popular/',
    group: SettingGroup.interface,
  );
  static const webDavEnable = SettingKey<bool>(
    _SettingBoxKey.webDavEnable,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableHistory = SettingKey<bool>(
    _SettingBoxKey.webDavEnableHistory,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableCollect = SettingKey<bool>(
    _SettingBoxKey.webDavEnableCollect,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableDanmakuShield = SettingKey<bool>(
    'webDavEnableDanmakuShield',
    false,
    group: SettingGroup.webdav,
  );
  static const danmakuShieldSyncDeviceId = SettingKey<String>(
    'danmakuShieldSyncDeviceId',
    '',
    group: SettingGroup.sync,
  );
  static const danmakuShieldSyncState = SettingKey<String>(
    'danmakuShieldSyncState',
    '',
    group: SettingGroup.sync,
  );
  static const danmakuShieldSyncCorruptState = SettingKey<String>(
    'danmakuShieldSyncCorruptState',
    '',
    group: SettingGroup.sync,
  );
  static const webDavURL = SettingKey<String>(
    _SettingBoxKey.webDavURL,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavUsername = SettingKey<String>(
    _SettingBoxKey.webDavUsername,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavPassword = SettingKey<String>(
    _SettingBoxKey.webDavPassword,
    '',
    group: SettingGroup.webdav,
  );
  static const lowMemoryMode = SettingKey<bool>(
    _SettingBoxKey.lowMemoryMode,
    false,
    group: SettingGroup.player,
  );
  /// 自定义规则仓库地址（留空用官方仓库）。
  ///
  /// 填一个以 / 结尾的地址，程序会去取它下面的 index.json。
  static const rulesRepoUrl = SettingKey<String>(
    _SettingBoxKey.rulesRepoUrl,
    '',
    group: SettingGroup.misc,
  );

  /// 「我的」页顶部的个人资料：昵称 + 头像。
  ///
  /// 头像存的是**应用私有目录里的副本**路径，不是相册原图路径——原图可能被删、
  /// 也可能在 Android 上受 scoped storage 限制读不到。
  static const userNickname = SettingKey<String>(
    _SettingBoxKey.userNickname,
    '',
    group: SettingGroup.misc,
  );
  static const userAvatarPath = SettingKey<String>(
    _SettingBoxKey.userAvatarPath,
    '',
    group: SettingGroup.misc,
  );
  // Null preserves the legacy lowMemoryMode choice until a policy is selected.
  static const lowMemoryPolicy = SettingKey<String?>(
    'lowMemoryPolicy',
    null,
    group: SettingGroup.player,
  );
  static const showWindowButton = SettingKey<bool>(
    _SettingBoxKey.showWindowButton,
    false,
    group: SettingGroup.theme,
  );
  /// 无边框窗口（只对 Windows 生效）。
  ///
  /// 打开后窗口去掉系统标题栏，由 [WindowShell] 接管八向缩放热区和窗口按钮。
  /// 注意窗口背景是**不透明**的：早先为了让圆角透出桌面开过透明窗口，结果
  /// Win11 会在四周叠一层背景模糊（"玻璃边"），拖拽缩放也要每帧跟桌面做
  /// alpha 合成，掉帧明显，已经去掉了。改完要重启才生效。
  static final framelessWindow = SettingKey<bool>(
    _SettingBoxKey.framelessWindow,
    true,
    group: SettingGroup.theme,
    defaultResolver: (_) => Platform.isWindows,
  );
  static const useDynamicColor = SettingKey<bool>(
    _SettingBoxKey.useDynamicColor,
    false,
    group: SettingGroup.theme,
  );
  /// 一次性迁移标记：这一版把默认主色换成固定紫色，需要把老用户身上
  /// 开着的「动态取色」关掉一次（否则主色会跟着系统强调色变，与设计不一致）。
  static const uiAccentMigrated = SettingKey<bool>(
    _SettingBoxKey.uiAccentMigrated,
    false,
    group: SettingGroup.theme,
  );
  static const exitBehavior = SettingKey<int>(
    _SettingBoxKey.exitBehavior,
    2,
    group: SettingGroup.interface,
  );
  static const playerDebugMode = SettingKey<bool>(
    _SettingBoxKey.playerDebugMode,
    false,
    group: SettingGroup.player,
  );
  static const syncPlayEndPoint = SettingKey<String>(
    _SettingBoxKey.syncPlayEndPoint,
    defaultSyncPlayEndPoint,
    group: SettingGroup.player,
  );
  static const syncPlayUserName = SettingKey<String>(
    'syncPlayUserName',
    '',
    group: SettingGroup.player,
  );

  /// 一起看时把别人的聊天以弹幕形式飘在画面上。
  ///
  /// 人多的时候房间进出消息会一直飘，很多人只想要聊天记录、不想被刷屏。
  static const syncPlayChatDanmaku = SettingKey<bool>(
    'syncPlayChatDanmaku',
    true,
    group: SettingGroup.player,
  );

  /// 一起看时在页面顶部弹「谁进来了 / 谁离开了」那条胶囊。
  static const syncPlayPresenceNotice = SettingKey<bool>(
    'syncPlayPresenceNotice',
    true,
    group: SettingGroup.player,
  );

  /// 最近进过的房间（JSON 数组），供大厅一键重回。
  static const syncPlayRecentRooms = SettingKey<String>(
    'syncPlayRecentRooms',
    '[]',
    group: SettingGroup.player,
  );

  /// 选集列表默认是不是倒序（最新一集排在最上面）。
  ///
  /// 追更的人几乎总是在找最后一集，正序每次都要一路滚到底。做成设置而不是
  /// 页面内临时状态，是因为「我习惯倒着看」这件事跨页面、跨次打开都成立。
  static const episodeListDescending = SettingKey<bool>(
    'episodeListDescending',
    false,
    group: SettingGroup.interface,
  );

  /// 卡顿自动换源：连续缓冲超时后自动切到同一集的下一条线路。
  static const autoSwitchSourceOnStall = SettingKey<bool>(
    'autoSwitchSourceOnStall',
    true,
    group: SettingGroup.player,
  );

  /// 一起看时，别人拖动进度条要不要把我也拽过去。
  ///
  /// 默认跟（一起看就该看同一处）；关掉之后只跟播放/暂停，别人跳走只提示
  /// 一句，偏差超过 30 秒才强制对齐。
  static const syncPlayFollowRemoteSeek = SettingKey<bool>(
    'syncPlayFollowRemoteSeek',
    true,
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    _SettingBoxKey.androidEnableOpenSLES,
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    _SettingBoxKey.androidVideoRenderer,
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    _SettingBoxKey.androidAutoEnterPIP,
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    _SettingBoxKey.defaultSuperResolutionMode,
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    _SettingBoxKey.disableSuperResolutionWarning,
    false,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    _SettingBoxKey.playerDisableAnimations,
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    _SettingBoxKey.playerLogLevel,
    2,
    group: SettingGroup.player,
  );
  static const timelineNotShowAbandonedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowAbandonedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineNotShowWatchedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowWatchedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineOnlyShowWatchingBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineOnlyShowWatchingBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const useSystemFont = SettingKey<bool>(
    _SettingBoxKey.useSystemFont,
    false,
    group: SettingGroup.theme,
  );
  static const forceAdBlocker = SettingKey<bool>(
    _SettingBoxKey.forceAdBlocker,
    false,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    _SettingBoxKey.backgroundPlayback,
    false,
    group: SettingGroup.player,
  );
  static const proxyEnable = SettingKey<bool>(
    _SettingBoxKey.proxyEnable,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyConfigured = SettingKey<bool>(
    _SettingBoxKey.proxyConfigured,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyUrl = SettingKey<String>(
    _SettingBoxKey.proxyUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const proxyTestUrl = SettingKey<String>(
    _SettingBoxKey.proxyTestUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const showRating = SettingKey<bool>(
    _SettingBoxKey.showRating,
    true,
    group: SettingGroup.interface,
  );
  static const defaultCollectLayout = SettingKey<String>(
    'defaultCollectLayout',
    'list',
    group: SettingGroup.interface,
  );
  static const downloadParallelEpisodes = SettingKey<int>(
    _SettingBoxKey.downloadParallelEpisodes,
    2,
    group: SettingGroup.download,
  );
  static const downloadParallelSegments = SettingKey<int>(
    _SettingBoxKey.downloadParallelSegments,
    3,
    group: SettingGroup.download,
  );
  static const downloadDanmaku = SettingKey<bool>(
    _SettingBoxKey.downloadDanmaku,
    true,
    group: SettingGroup.download,
  );
  static const downloadDirectory = SettingKey<String>(
    _SettingBoxKey.downloadDirectory,
    '',
    group: SettingGroup.download,
  );
  // macOS only: security-scoped bookmark that keeps downloadDirectory
  // writable across app restarts under the sandbox.
  static const downloadDirectoryBookmark = SettingKey<String>(
    'downloadDirectoryBookmark',
    '',
    group: SettingGroup.download,
  );
  static const shortcutDialogShown = SettingKey<bool>(
    _SettingBoxKey.shortcutDialogShown,
    false,
    group: SettingGroup.misc,
  );
  static const onboardingCompleted = SettingKey<bool>(
    'onboardingCompleted',
    false,
    group: SettingGroup.misc,
  );
  static const bangumiSyncEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiSyncEnable,
    false,
    group: SettingGroup.bangumi,
  );
  static const bangumiAccessToken = SettingKey<String>(
    _SettingBoxKey.bangumiAccessToken,
    '',
    group: SettingGroup.bangumi,
  );
  static const bangumiSyncPriority = SettingKey<int>(
    _SettingBoxKey.bangumiSyncPriority,
    0,
    group: SettingGroup.bangumi,
  );
  static const bangumiImmediateSyncToastEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiImmediateSyncToastEnable,
    true,
    group: SettingGroup.bangumi,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    _SettingBoxKey.brightnessVolumeGesture,
    true,
    group: SettingGroup.player,
  );
  static const historySyncDeviceId = SettingKey<String>(
    _SettingBoxKey.historySyncDeviceId,
    '',
    group: SettingGroup.sync,
  );
  static const historySyncSequence = SettingKey<int>(
    _SettingBoxKey.historySyncSequence,
    0,
    group: SettingGroup.sync,
  );
  static const historySyncSnapshotInitialized = SettingKey<bool>(
    _SettingBoxKey.historySyncSnapshotInitialized,
    false,
    group: SettingGroup.sync,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );

  static final List<SettingKey<Object?>> all = [
    hAenable,
    hardwareDecoder,
    searchEnhanceEnable,
    autoUpdate,
    checkPluginUpdateOnStartup,
    alwaysOntop,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    danmakuEnhance,
    pauseOnDanmakuEdit,
    danmakuBorder,
    danmakuBorderSize,
    danmakuOpacity,
    danmakuFontSize,
    danmakuTop,
    danmakuScroll,
    danmakuBottom,
    danmakuMassive,
    danmakuDeduplication,
    danmakuChConvert,
    danmakuSource,
    danmakuArea,
    danmakuColor,
    danmakuDuration,
    danmakuLineHeight,
    danmakuTimeOffset,
    danmakuEnabledByDefault,
    danmakuBiliBiliSource,
    danmakuGamerSource,
    danmakuDanDanSource,
    danmakuFontWeight,
    danmakuFollowSpeed,
    themeMode,
    themeColor,
    privateMode,
    autoPlay,
    autoPlayNext,
    playResume,
    showPlayerError,
    oledEnhance,
    displayMode,
    enableGitProxy,
    enableBangumiProxy,
    imageAcceleration,
    bangumiAcceleration,
    rulesMirror,
    enableSystemProxy,
    defaultStartupPage,
    webDavEnable,
    webDavEnableHistory,
    webDavEnableCollect,
    webDavEnableDanmakuShield,
    danmakuShieldSyncDeviceId,
    danmakuShieldSyncState,
    danmakuShieldSyncCorruptState,
    webDavURL,
    webDavUsername,
    webDavPassword,
    lowMemoryMode,
    lowMemoryPolicy,
    rulesRepoUrl,
    userNickname,
    userAvatarPath,
    showWindowButton,
    framelessWindow,
    useDynamicColor,
    uiAccentMigrated,
    exitBehavior,
    playerDebugMode,
    syncPlayEndPoint,
    syncPlayUserName,
    syncPlayChatDanmaku,
    syncPlayPresenceNotice,
    syncPlayRecentRooms,
    syncPlayFollowRemoteSeek,
    autoSwitchSourceOnStall,
    episodeListDescending,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    playerDisableAnimations,
    playerLogLevel,
    timelineNotShowAbandonedBangumis,
    timelineNotShowWatchedBangumis,
    timelineOnlyShowWatchingBangumis,
    useSystemFont,
    forceAdBlocker,
    backgroundPlayback,
    proxyEnable,
    proxyConfigured,
    proxyUrl,
    proxyTestUrl,
    showRating,
    defaultCollectLayout,
    downloadParallelEpisodes,
    downloadParallelSegments,
    downloadDanmaku,
    downloadDirectory,
    downloadDirectoryBookmark,
    shortcutDialogShown,
    onboardingCompleted,
    bangumiSyncEnable,
    bangumiAccessToken,
    bangumiSyncPriority,
    bangumiImmediateSyncToastEnable,
    brightnessVolumeGesture,
    historySyncDeviceId,
    historySyncSequence,
    historySyncSnapshotInitialized,
    playerControllerLayerDisappearTime,
    defaultVolume,
    playerMuted,
    embyServers,
    embyActiveServerId,
    embyDeviceId,
    embyDirectPlay,
  ];

  /// Emby / Jellyfin 服务器列表，整份 JSON 数组存在这里。
  ///
  /// 单独一个 SettingGroup.emby 分组，是为了让「重置播放设置」「重置弹幕设置」
  /// 这类按组重置不会顺手把服务器配置和 Token 一起清掉。
  static const embyServers = SettingKey<String>(
    _SettingBoxKey.embyServers,
    '[]',
    group: SettingGroup.emby,
  );

  /// 当前选中的服务器 id（对应 EmbyServer.id）。
  static const embyActiveServerId = SettingKey<String>(
    _SettingBoxKey.embyActiveServerId,
    '',
    group: SettingGroup.emby,
  );

  /// 一次生成、长期复用的设备 id。Emby 靠它识别"同一台设备"。
  static const embyDeviceId = SettingKey<String>(
    _SettingBoxKey.embyDeviceId,
    '',
    group: SettingGroup.emby,
  );

  /// 优先直连播放（原盘流）而不是让服务端转码出 HLS。
  static const embyDirectPlay = SettingKey<bool>(
    _SettingBoxKey.embyDirectPlay,
    true,
    group: SettingGroup.emby,
  );

  static List<SettingKey<Object?>> byGroup(SettingGroup group) {
    return [
      for (final key in all)
        if (key.group == group) key
    ];
  }

  SettingsKeys._();
}

// Historical Hive key names used by settings created before the typed registry.
// Keep these strings stable so existing users keep their saved settings.
// New settings do not need to be added here unless they intentionally reuse an
// existing persisted key.
class _SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      autoUpdate = 'autoUpdate',
      alwaysOntop = 'alwaysOntop',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      danmakuEnhance = 'danmakuEnhance',
      danmakuBorder = 'danmakuBorder',
      danmakuBorderSize = 'danmakuBorderSize',
      danmakuOpacity = 'danmakuOpacity',
      danmakuFontSize = 'danmakuFontSize',
      danmakuTop = 'danmakuTop',
      danmakuScroll = 'danmakuScroll',
      danmakuBottom = 'danmakuBottom',
      danmakuMassive = 'danmakuMassive',
      danmakuDeduplication = 'danmakuDeduplication',
      danmakuArea = 'danmakuArea',
      danmakuColor = 'danmakuColor',
      danmakuDuration = 'danmakuDuration',
      danmakuLineHeight = 'danmakuLineHeight',
      danmakuTimeOffset = 'danmakuTimeOffset',
      danmakuEnabledByDefault = 'danmakuEnabledByDefault',
      danmakuBiliBiliSource = 'danmakuBiliBiliSource',
      danmakuGamerSource = 'danmakuGamerSource',
      danmakuDanDanSource = 'danmakuDanDanSource',
      danmakuFontWeight = 'danmakuFontWeight',
      danmakuFollowSpeed = 'danmakuFollowSpeed',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      privateMode = 'privateMode',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      displayMode = 'displayMode',
      enableGitProxy = 'enableGitProxy',
      enableBangumiProxy = 'enableBangumiProxy',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',
      webDavEnable = 'webDavEnable',
      webDavEnableHistory = 'webDavEnableHistory',
      webDavEnableCollect = 'webDavEnableCollect',
      webDavURL = 'webDavURL',
      webDavUsername = 'webDavUsername',
      webDavPassword = 'webDavPasswd',
      lowMemoryMode = 'lowMemoryMode',
      rulesRepoUrl = 'rulesRepoUrl',
      userNickname = 'userNickname',
      userAvatarPath = 'userAvatarPath',
      showWindowButton = 'showWindowButton',
      framelessWindow = 'framelessWindow',
      useDynamicColor = 'useDynamicColor',
      uiAccentMigrated = 'uiAccentMigrated',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      androidEnableOpenSLES = 'androidEnableOpenSLES',
      androidVideoRenderer = 'androidVideoRenderer',
      androidAutoEnterPIP = 'androidAutoEnterPIP',
      defaultSuperResolutionMode = 'defaultSuperResolutionType',
      disableSuperResolutionWarning = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      timelineNotShowAbandonedBangumis = 'timelineNotShowAbandonedBangumis',
      timelineNotShowWatchedBangumis = 'timelineNotShowWatchedBangumis',
      timelineOnlyShowWatchingBangumis = 'timelineOnlyShowWatchingBangumis',
      useSystemFont = 'useSystemFont',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      proxyTestUrl = 'proxyTestUrl',
      showRating = 'showRating',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      downloadDanmaku = 'downloadDanmaku',
      downloadDirectory = 'downloadDirectory',
      shortcutDialogShown = 'shortcutDialogShown',
      bangumiSyncEnable = 'bangumiSyncEnable',
      bangumiAccessToken = 'bangumiAccessToken',
      bangumiSyncPriority = 'bangumiSyncPriority',
      bangumiImmediateSyncToastEnable = 'bangumiImmediateSyncToastEnable',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      historySyncDeviceId = 'historySyncDeviceId',
      historySyncSequence = 'historySyncSequence',
      historySyncSnapshotInitialized = 'historySyncSnapshotInitialized',
      embyServers = 'embyServers',
      embyActiveServerId = 'embyActiveServerId',
      embyDeviceId = 'embyDeviceId',
      embyDirectPlay = 'embyDirectPlay';
}
