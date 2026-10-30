import 'package:XL/services/network/acceleration_mode.dart';
import 'package:XL/services/storage/storage.dart';

/// 弹幕接口来源。
///
/// `bilibili` 走公开的 web 接口，不需要任何凭据；`dandanplay` 需要自备
/// 开放平台的 AppId / AppSecret，空凭据的请求会被服务端直接拒绝。
enum DanmakuSource implements AccelerationMode {
  bilibili,
  dandanplay;

  static DanmakuSource get current {
    final stored = GStorage.getSetting(SettingsKeys.danmakuSource);
    return values.asNameMap()[stored] ?? bilibili;
  }

  @override
  String get label => switch (this) {
    DanmakuSource.bilibili => 'B站',
    DanmakuSource.dandanplay => '弹弹play',
  };

  @override
  String get description => switch (this) {
    DanmakuSource.bilibili => '免凭据，按番剧名自动匹配',
    DanmakuSource.dandanplay => '需自备开放平台密钥',
  };
}
