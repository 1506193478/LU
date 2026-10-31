import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/history/history_controller.dart';
import 'package:XL/pages/player/player_controller.dart';
import 'package:XL/pages/route_error_page.dart';
import 'package:XL/pages/video/video_controller.dart';
import 'package:XL/pages/video/video_page.dart';
import 'package:XL/pages/video/video_playback_args.dart';

final videoModule = createModule(
  path: '/video',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s
        ..add<VideoPageController>(VideoPageController.new)
        ..add<PlayerController>(PlayerController.new),
      child: (context, state) {
        final args = state.arguments;
        if (args is! VideoPlaybackArgs) {
          return const RouteErrorPage(message: '播放参数无效，请返回后重试。');
        }
        return VideoPage(
          args: args,
          playerController: context.read<PlayerController>(),
          videoPageController: context.read<VideoPageController>(),
          historyController: inject<HistoryController>(),
          downloadController: inject<DownloadController>(),
        );
      },
      // 播放页刻意不走全局的 Cupertino 转场：那个 builder 会在左边 20dp 挂
      // 返回手势，而播放器自己的「横向拖动 = 快进快退」正好从屏幕边缘起手，
      // 两个手势会抢。这里换成纯淡入（PageRouteBuilder，天生没有返回手势），
      // 退出仍然走返回按钮 / 系统返回键。
      transition: TransitionType.fade,
    );
  },
);
