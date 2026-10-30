import 'package:XL/request/config/api_endpoints.dart';

// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=KAZUMI_APPID / KAZUMI_KEY.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID'),
  'value': String.fromEnvironment('KAZUMI_KEY'),
};

/// 本地构建没有注入 KAZUMI_APPID / KAZUMI_KEY 时，镜像的受保护接口
/// （番剧搜索、评论）签名一定是错的，服务端必然拒绝。
///
/// 而 `enableBangumiProxy` 默认为 true、`bangumiAcceleration` 默认为空串，
/// 两者叠加后镜像模式是开箱默认。于是「搜索永远返回空、界面却只显示
/// 一个空状态图标」，看不出是网络问题。调用方必须据此退回直连。
bool get hasBangumiMirrorCredentials =>
    bangumiMirrorCredentials['id']!.isNotEmpty &&
    bangumiMirrorCredentials['value']!.isNotEmpty;

/// 镜像模式下需要 X-AppId / X-Signature 的受保护接口。
///
/// 与 `BangumiClient` 的签名判断共用同一份定义，避免拦截器放行、
/// 客户端却不签名（或反过来）导致请求被拒。
bool isBangumiProtectedRequest(String url, String method) {
  final uri = Uri.tryParse(url);
  if (uri == null || !ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
    return false;
  }
  final verb = method.toUpperCase();
  final path = uri.path;
  if (verb == 'POST') {
    return path == '/v0/search/subjects';
  }
  if (verb != 'GET') {
    return false;
  }
  return path.startsWith('/p1/subjects/') && path.endsWith('/comments') ||
      path.startsWith('/p1/episodes/') && path.endsWith('/comments') ||
      path.startsWith('/p1/characters/') && path.endsWith('/comments');
}
