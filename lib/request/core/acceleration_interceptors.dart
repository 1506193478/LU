import 'package:dio/dio.dart';
import 'package:XL/request/config/api_endpoints.dart';
import 'package:XL/request/core/ech_adapter.dart';
import 'package:XL/request/clients/bangumi_client.dart'
    show bangumiForceDirectExtra;
import 'package:XL/services/network/bangumi_acceleration.dart';
import 'package:XL/services/network/rules_mirror.dart';
import 'package:XL/utils/bangumi_mirror_credentials.dart';

class BangumiAccelerationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    if (ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      switch (BangumiAcceleration.current) {
        case BangumiAcceleration.direct:
          break;
        case BangumiAcceleration.ech:
          options.path = uri.replace(scheme: 'https').toString();
          options.queryParameters = {};
          options.requireEch();
        case BangumiAcceleration.mirror:
          // 受保护接口需要镜像凭据签名。本地构建没注入凭据时签名必然被拒，
          // 这时必须走直连，否则番剧搜索会一直返回空。
          final needsSignature =
              isBangumiProtectedRequest(uri.toString(), options.method);
          if (options.extra[bangumiForceDirectExtra] == true ||
              (needsSignature && !hasBangumiMirrorCredentials)) {
            break;
          }
          options.path =
              ApiEndpoints.bangumiMirrorDomain +
              uri.path +
              (uri.hasQuery ? '?${uri.query}' : '');
          options.queryParameters = {};
      }
    }
    handler.next(options);
  }
}

class RulesMirrorInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final url = options.uri.toString();
    if (url.startsWith(ApiEndpoints.pluginShop)) {
      switch (RulesMirror.current) {
        case RulesMirror.direct:
          break;
        case RulesMirror.ghProxy:
          options.path = ApiEndpoints.ghProxyMirror + url;
          options.requireEch();
        case RulesMirror.ghfast:
          options.path = ApiEndpoints.ghfastMirror + url;
        case RulesMirror.gitcode:
          options.path =
              ApiEndpoints.gitcodeMirror +
              url.substring(ApiEndpoints.pluginShop.length);
      }
    }
    handler.next(options);
  }
}
