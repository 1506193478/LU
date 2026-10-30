import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/pages/syncplay/syncplay_controller.dart';
import 'package:XL/pages/syncplay/syncplay_page.dart';

final syncPlayModule = createModule(
  path: '/syncplay',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => SyncPlayPage(
        controller: inject<SyncPlayController>(),
      ),
    );
  },
);

/// 与底部导航 shell 同生命周期：切换 tab 不丢失房间会话。
///
/// 注意：这里**不要**在 factory 里 `inject<PluginsController>()`。
/// singleton 是在 Modular bootstrap 之前就创建的，那一刻 inject 会抛
/// `no Modular app has been bootstrapped yet`，直接把首帧打崩。
/// SyncPlayController 内部改为按需 `inject()`。
final syncPlayControllerModule = createModule(
  register: (c) {
    c.addSingleton<SyncPlayController>(SyncPlayController.new);
  },
);
