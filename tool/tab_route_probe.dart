import 'package:XL/pages/router.dart';

/// 侧栏路由映射自检：确认 `menu.getPath(i)` 生成的路径能被
/// `menu.indexForPath` 认回来，且和 `index_module.dart` 里注册的
/// 子路由一致。
///
/// 用法（绕过 native build hook）：
/// `dart --packages=.dart_tool/package_config.json tool/tab_route_probe.dart`
void main() {
  var ok = true;
  void check(String label, bool value, [String? detail]) {
    if (!value) ok = false;
    print('${value ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : '  $detail'}');
  }

  // 这张表必须和 index_module.dart 里 tabModule 的 children 一致。
  const List<String> expected = <String>[
    '/popular',
    '/timeline',
    '/collect',
    '/syncplay',
    '/my',
  ];

  check('tab 数量为 5', menu.menuList.length == 5, '${menu.menuList.length}');

  for (int i = 0; i < expected.length; i++) {
    final String path = menu.getPath(i);
    check(
      'index $i 路径 == ${expected[i]}',
      path == expected[i],
      path,
    );
    // 侧栏点击走的就是 '/tab${path}/'
    final String navigateTo = '/tab$path/';
    final int back = menu.indexForPath(navigateTo);
    check(
      'index $i 反查回 $i',
      back == i,
      '$navigateTo -> $back',
    );
  }

  // 反查必须支持带尾斜杠和不带尾斜杠两种写法。
  check(
    "'/tab/popular' 反查 == 0",
    menu.indexForPath('/tab/popular') == 0,
    '${menu.indexForPath('/tab/popular')}',
  );
  check(
    "'/tab/my/' 反查 == 4",
    menu.indexForPath('/tab/my/') == 4,
    '${menu.indexForPath('/tab/my/')}',
  );
  // 详情页这类子路径也要落到它所属的 tab 上。
  check(
    "'/tab/popular/extra' 反查 == 0",
    menu.indexForPath('/tab/popular/extra') == 0,
    '${menu.indexForPath('/tab/popular/extra')}',
  );
  // 未知路径回落到 0，不能是 -1（那会让 _selectedIndex 变成 -1）。
  check(
    "未知路径回落 == 0",
    menu.indexForPath('/tab/nope/') == 0,
    '${menu.indexForPath('/tab/nope/')}',
  );

  print(ok ? '\nALL PASS' : '\nHAS FAILURE');
}
