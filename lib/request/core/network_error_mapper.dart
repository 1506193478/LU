import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:XL/request/core/network_exception.dart';

class NetworkErrorMapper {
  const NetworkErrorMapper._();

  static Future<NetworkException> mapException(DioException error) async {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return NetworkException(
          type: NetworkExceptionType.badCertificate,
          message: '证书有误！',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return NetworkException(
          type: NetworkExceptionType.badResponse,
          message: '服务器异常，请稍后重试！',
          statusCode: statusCode,
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.cancel:
        return NetworkException(
          type: NetworkExceptionType.cancel,
          message: '请求已被取消，请重新请求',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.connectionError:
        return NetworkException(
          type: NetworkExceptionType.connectionError,
          message: '连接错误，请检查网络设置',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.connectionTimeout:
        return NetworkException(
          type: NetworkExceptionType.connectionTimeout,
          message: '网络连接超时，请检查网络设置',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.receiveTimeout:
        return NetworkException(
          type: NetworkExceptionType.receiveTimeout,
          message: '响应超时，请稍后重试！',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.sendTimeout:
        return NetworkException(
          type: NetworkExceptionType.sendTimeout,
          message: '发送请求超时，请检查网络设置',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.transformTimeout:
        return NetworkException(
          type: NetworkExceptionType.parseError,
          message: '响应解析超时，请稍后重试！',
          rawError: error,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.unknown:
        var connection = '';
        try {
          connection = await _connectionLabel().timeout(
            const Duration(seconds: 1),
          );
        } catch (_) {}
        // 这里原来只拼「正在使用wifi 网络异常」——真正的原因（TLS 被中断、
        // 域名解析失败、连接被重置）全被丢掉了，用户和日志都看不出是哪一步
        // 断的。番剧插件站连不上时全是这条，等于没有信息。
        final cause = _causeOf(error);
        return NetworkException(
          type: NetworkExceptionType.unknown,
          message: [connection, '网络异常', cause]
              .where((part) => part.isNotEmpty)
              .join(' · '),
          rawError: error,
          stackTrace: error.stackTrace,
        );
    }
  }

  /// 从底层异常里抠一句人话原因，抠不到就返回空串。
  static String _causeOf(DioException error) {
    final Object raw = error.error ?? error;
    final String text = raw.toString();
    if (text.contains('HandshakeException')) return 'TLS 握手被中断';
    if (text.contains('SocketException')) {
      if (text.contains('Failed host lookup')) return '域名解析失败';
      if (text.contains('Connection refused')) return '对方拒绝连接';
      if (text.contains('Connection reset')) return '连接被重置';
      if (text.contains('Network is unreachable')) return '网络不可达';
      return '连接被关闭';
    }
    if (text.contains('HttpException')) return 'HTTP 层出错';
    final String message = error.message ?? '';
    return message.length > 80 ? '${message.substring(0, 80)}…' : message;
  }

  static NetworkException parse(Object error, StackTrace stackTrace) {
    return NetworkException(
      type: NetworkExceptionType.parseError,
      message: '响应解析失败',
      rawError: error,
      stackTrace: stackTrace,
    );
  }

  static Future<String> _connectionLabel() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.mobile)) {
      return '正在使用移动流量';
    }
    if (connectivityResult.contains(ConnectivityResult.wifi)) {
      return '正在使用wifi';
    }
    if (connectivityResult.contains(ConnectivityResult.ethernet)) {
      return '正在使用局域网';
    }
    if (connectivityResult.contains(ConnectivityResult.vpn)) {
      return '正在使用代理网络';
    }
    if (connectivityResult.contains(ConnectivityResult.other)) {
      return '正在使用其他网络';
    }
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return '未连接到任何网络';
    }
    return '';
  }
}
