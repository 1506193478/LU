import 'dart:convert';
import 'package:XL/services/storage/storage.dart';

/// Emby 播放器的手势偏好。
///
/// 之前这些行为全是写死的：左半屏调亮度、右半屏调音量、双击左右快进、
/// 没有任何开关。用户想关掉某一项（比如误触双击跳进度）只能忍着。这里把
/// 每一项拆成独立开关，播放器每次起播读一次，改设置后下次起手就生效。
///
/// 整份存成一个 JSON：字段多（十来个），一个个加设置键既啰嗦，又会让
/// 「重置播放设置」漏掉新增项。
class EmbyGesturePrefs {
  const EmbyGesturePrefs({
    this.brightness = true,
    this.volume = true,
    this.seekByDrag = true,
    this.tapToggleControls = true,
    this.doubleTapSeek = true,
    this.doubleTapPlayPause = true,
    this.dragProgressBar = true,
    this.longPressSpeed = true,
    this.longPressExit = true,
    this.pinchZoom = true,
    this.rememberZoom = false,
    this.hapticLongPress = true,
    this.hapticSeek = true,
    this.hapticProgress = true,
    this.longPressRate = 3.0,
    this.doubleTapSeconds = 10,
  });

  /// 左侧上下滑动调亮度。
  final bool brightness;

  /// 右侧上下滑动调音量。
  final bool volume;

  /// 左右滑动调进度。
  final bool seekByDrag;

  /// 单击显示 / 隐藏控件。
  final bool tapToggleControls;

  /// 双击左 / 右三分之一快退 / 快进。
  final bool doubleTapSeek;

  /// 双击中间播放 / 暂停。
  final bool doubleTapPlayPause;

  /// 允许拖动底部进度条。
  final bool dragProgressBar;

  /// 长按画面倍速播放（松手恢复）。
  final bool longPressSpeed;

  /// 长按左上角返回键直接退出播放器（视频里那颗按钮的行为）。
  final bool longPressExit;

  /// 双指缩放 / 拖动画面。
  final bool pinchZoom;

  /// 记住缩放大小。关掉后每次起播回到 100%，也不跨重启保存。
  final bool rememberZoom;

  final bool hapticLongPress;
  final bool hapticSeek;
  final bool hapticProgress;

  /// 长按倍速的倍率（1.5 / 2 / 3 / 4）。
  final double longPressRate;

  /// 双击快进 / 快退的秒数（5 / 10 / 15 / 30）。
  final int doubleTapSeconds;

  static const _key = SettingKey<String>(
    'embyGesturePrefs',
    '{}',
    group: SettingGroup.emby,
  );

  static EmbyGesturePrefs? _cache;

  static EmbyGesturePrefs get current {
    final cached = _cache;
    if (cached != null) return cached;
    EmbyGesturePrefs value = const EmbyGesturePrefs();
    try {
      final raw = GStorage.getSetting(_key);
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        bool b(String k, bool d) => map[k] is bool ? map[k] as bool : d;
        double d(String k, double v) =>
            map[k] is num ? (map[k] as num).toDouble() : v;
        int i(String k, int v) => map[k] is num ? (map[k] as num).toInt() : v;
        value = EmbyGesturePrefs(
          brightness: b('brightness', true),
          volume: b('volume', true),
          seekByDrag: b('seekByDrag', true),
          tapToggleControls: b('tapToggleControls', true),
          doubleTapSeek: b('doubleTapSeek', true),
          doubleTapPlayPause: b('doubleTapPlayPause', true),
          dragProgressBar: b('dragProgressBar', true),
          longPressSpeed: b('longPressSpeed', true),
          longPressExit: b('longPressExit', true),
          pinchZoom: b('pinchZoom', true),
          rememberZoom: b('rememberZoom', false),
          hapticLongPress: b('hapticLongPress', true),
          hapticSeek: b('hapticSeek', true),
          hapticProgress: b('hapticProgress', true),
          longPressRate: d('longPressRate', 3.0),
          doubleTapSeconds: i('doubleTapSeconds', 10),
        );
      }
    } catch (_) {
      // 存坏了就用默认值，不能让播放器因为它起不来。
    }
    _cache = value;
    return value;
  }

  static Future<void> save(EmbyGesturePrefs value) async {
    _cache = value;
    await GStorage.putSetting(
      _key,
      jsonEncode(<String, Object?>{
        'brightness': value.brightness,
        'volume': value.volume,
        'seekByDrag': value.seekByDrag,
        'tapToggleControls': value.tapToggleControls,
        'doubleTapSeek': value.doubleTapSeek,
        'doubleTapPlayPause': value.doubleTapPlayPause,
        'dragProgressBar': value.dragProgressBar,
        'longPressSpeed': value.longPressSpeed,
        'longPressExit': value.longPressExit,
        'pinchZoom': value.pinchZoom,
        'rememberZoom': value.rememberZoom,
        'hapticLongPress': value.hapticLongPress,
        'hapticSeek': value.hapticSeek,
        'hapticProgress': value.hapticProgress,
        'longPressRate': value.longPressRate,
        'doubleTapSeconds': value.doubleTapSeconds,
      }),
    );
  }

  EmbyGesturePrefs copyWith({
    bool? brightness,
    bool? volume,
    bool? seekByDrag,
    bool? tapToggleControls,
    bool? doubleTapSeek,
    bool? doubleTapPlayPause,
    bool? dragProgressBar,
    bool? longPressSpeed,
    bool? longPressExit,
    bool? pinchZoom,
    bool? rememberZoom,
    bool? hapticLongPress,
    bool? hapticSeek,
    bool? hapticProgress,
    double? longPressRate,
    int? doubleTapSeconds,
  }) =>
      EmbyGesturePrefs(
        brightness: brightness ?? this.brightness,
        volume: volume ?? this.volume,
        seekByDrag: seekByDrag ?? this.seekByDrag,
        tapToggleControls: tapToggleControls ?? this.tapToggleControls,
        doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
        doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
        dragProgressBar: dragProgressBar ?? this.dragProgressBar,
        longPressSpeed: longPressSpeed ?? this.longPressSpeed,
        longPressExit: longPressExit ?? this.longPressExit,
        pinchZoom: pinchZoom ?? this.pinchZoom,
        rememberZoom: rememberZoom ?? this.rememberZoom,
        hapticLongPress: hapticLongPress ?? this.hapticLongPress,
        hapticSeek: hapticSeek ?? this.hapticSeek,
        hapticProgress: hapticProgress ?? this.hapticProgress,
        longPressRate: longPressRate ?? this.longPressRate,
        doubleTapSeconds: doubleTapSeconds ?? this.doubleTapSeconds,
      );
}

/// 进入播放器 / 换集时的屏幕方向。
enum EmbyOrientationMode {
  /// 按视频宽高比决定：宽片横屏、竖片竖屏（截图里的「适应宽高」）。
  auto,

  /// 不动，保持进来时的方向。
  keep,

  landscape,
  portrait;

  String get label => switch (this) {
        EmbyOrientationMode.auto => '适应宽高',
        EmbyOrientationMode.keep => '无变化',
        EmbyOrientationMode.landscape => '强制横屏',
        EmbyOrientationMode.portrait => '强制竖屏',
      };

  String get storageValue => switch (this) {
        EmbyOrientationMode.auto => 'auto',
        EmbyOrientationMode.keep => 'keep',
        EmbyOrientationMode.landscape => 'landscape',
        EmbyOrientationMode.portrait => 'portrait',
      };

  static EmbyOrientationMode parse(String raw) => switch (raw) {
        'keep' => EmbyOrientationMode.keep,
        'landscape' => EmbyOrientationMode.landscape,
        'portrait' => EmbyOrientationMode.portrait,
        _ => EmbyOrientationMode.auto,
      };
}

/// 横屏时倒向哪一边（仰卧在床上看时，机身两侧的摄像头位置决定手感）。
enum EmbyLandscapeSide {
  auto,
  left,
  right;

  String get label => switch (this) {
        EmbyLandscapeSide.auto => '自动',
        EmbyLandscapeSide.left => '摄像头在左',
        EmbyLandscapeSide.right => '摄像头在右',
      };

  String get storageValue => switch (this) {
        EmbyLandscapeSide.auto => 'auto',
        EmbyLandscapeSide.left => 'left',
        EmbyLandscapeSide.right => 'right',
      };

  static EmbyLandscapeSide parse(String raw) => switch (raw) {
        'left' => EmbyLandscapeSide.left,
        'right' => EmbyLandscapeSide.right,
        _ => EmbyLandscapeSide.auto,
      };
}

class EmbyDisplayPrefs {
  EmbyDisplayPrefs._();

  static const _enterKey = SettingKey<String>(
    'embyEnterOrientation',
    'auto',
    group: SettingGroup.emby,
  );
  static const _switchKey = SettingKey<String>(
    'embySwitchOrientation',
    'keep',
    group: SettingGroup.emby,
  );
  static const _sideKey = SettingKey<String>(
    'embyLandscapeSide',
    'auto',
    group: SettingGroup.emby,
  );

  static EmbyOrientationMode get enter =>
      EmbyOrientationMode.parse(GStorage.getSetting(_enterKey));

  static Future<void> setEnter(EmbyOrientationMode value) =>
      GStorage.putSetting(_enterKey, value.storageValue);

  static EmbyOrientationMode get onSwitch =>
      EmbyOrientationMode.parse(GStorage.getSetting(_switchKey));

  static Future<void> setOnSwitch(EmbyOrientationMode value) =>
      GStorage.putSetting(_switchKey, value.storageValue);

  static EmbyLandscapeSide get side =>
      EmbyLandscapeSide.parse(GStorage.getSetting(_sideKey));

  static Future<void> setSide(EmbyLandscapeSide value) =>
      GStorage.putSetting(_sideKey, value.storageValue);
}

/// 「记住缩放大小」的落地：按条目 id 存一个倍率。
///
/// 关掉开关时 [EmbyZoomMemory.clear] 会被调用，下次起播就是 100%；
/// 开着则跨重启也还在（最多留 60 部，超了丢最旧的）。
class EmbyZoomMemory {
  EmbyZoomMemory._();

  static const _key = SettingKey<String>(
    'embyZoomMemory',
    '{}',
    group: SettingGroup.emby,
  );

  static Map<String, double> _load() {
    try {
      final raw = jsonDecode(GStorage.getSetting(_key));
      if (raw is! Map) return <String, double>{};
      return <String, double>{
        for (final e in raw.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
    } catch (_) {
      return <String, double>{};
    }
  }

  static double of(String itemId) {
    if (itemId.isEmpty) return 1;
    return _load()[itemId] ?? 1;
  }

  static Future<void> put(String itemId, double zoom) async {
    if (itemId.isEmpty) return;
    final map = _load();
    if (zoom <= 1.02) {
      map.remove(itemId);
    } else {
      map[itemId] = zoom.clamp(1.0, 3.0);
    }
    // 简单裁剪：超出 60 条时只保留后 60 条（Map 保持插入顺序）。
    final entries = map.entries.toList();
    final kept = entries.length > 60
        ? entries.sublist(entries.length - 60)
        : entries;
    await GStorage.putSetting(
      _key,
      jsonEncode(<String, double>{
        for (final e in kept) e.key: e.value,
      }),
    );
  }

  static Future<void> clear() async => GStorage.putSetting(_key, '{}');
}
