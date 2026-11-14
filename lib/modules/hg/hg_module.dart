/// HG 短剧模块注册（flutter_modular）。
library;

import 'package:flutter_modular/flutter_modular.dart';

import 'package:XL/modules/hg/hg_feed_page.dart';

final hgModule = createModule(
  path: '/hg',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => HgFeedPage(
        startVideoId: state.uri.queryParameters['id'] != null
            ? int.tryParse(state.uri.queryParameters['id']!)
            : null,
      ),
    );
  },
);
