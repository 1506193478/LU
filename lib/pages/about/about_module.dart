import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/pages/about/about_page.dart';
import 'package:XL/pages/about/credits_page.dart';
import 'package:XL/pages/my/my_controller.dart';

final aboutModule = createModule(
  path: '/about',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => AboutPage(
          onCheckUpdate: inject<MyController>().checkUpdate,
        ),
      )
      ..route('/credits', child: (context, state) => const CreditsPage());
  },
);
