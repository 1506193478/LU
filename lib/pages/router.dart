class MenuRouteItem {
  const MenuRouteItem({required this.path});

  final String path;
}

class MenuRoute {
  const MenuRoute(this.menuList);

  final List<MenuRouteItem> menuList;

  String getPath(int index) => menuList[index].path;

  int indexForPath(String path) {
    final index = menuList.indexWhere(
      (item) =>
          path == '/tab${item.path}' ||
          path == '/tab${item.path}/' ||
          path.startsWith('/tab${item.path}/'),
    );
    return index < 0 ? 0 : index;
  }
}

/// 底栏五项：推荐 - 追番 - 一起看 - Emby - 我的。
///
/// 时间表不再是底栏页：入口挪到「我的」页里（和设置同层），
/// 但 `/tab/timeline/` 路由仍然保留，老用户存的默认启动页指向它也能打开。
const MenuRoute menu = MenuRoute([
  MenuRouteItem(path: '/popular'),
  MenuRouteItem(path: '/collect'),
  MenuRouteItem(path: '/syncplay'),
  MenuRouteItem(path: '/emby'),
  MenuRouteItem(path: '/my'),
]);
