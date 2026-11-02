// 复现 App 里 EmbyClient 的网络层：同样的 8s connect / 20s receive，
// 同样的 IOHttpClientAdapter，直接打真实服务器，看每一步耗时。
//
//   dart --packages=.dart_tool/package_config.json tool/emby_net_probe.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

Future<void> main(List<String> args) async {
  final String base = args.isNotEmpty ? args.first : 'https://emby.bbqwq.com';

  final client = HttpClient();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => client);

  Future<void> probe(String label, String url) async {
    final sw = Stopwatch()..start();
    try {
      final r = await dio.get<dynamic>(
        url,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Emby-Authorization':
                'MediaBrowser Client="LU", Device="Probe", DeviceId="probe", Version="1.0.0"',
          },
          // 图片是二进制，别让 dio 去解 json
          responseType: label.startsWith('image')
              ? ResponseType.bytes
              : ResponseType.plain,
        ),
      );
      final data = r.data;
      final size = data is List ? data.length : '$data'.length;
      stdout.writeln(
        '  [$label] ${r.statusCode}  ${sw.elapsedMilliseconds}ms  ${size}B',
      );
    } on DioException catch (e) {
      stdout.writeln(
        '  [$label] FAIL ${e.type}  ${sw.elapsedMilliseconds}ms  ${e.message}',
      );
    } catch (e) {
      stdout.writeln('  [$label] FAIL ${sw.elapsedMilliseconds}ms  $e');
    }
  }

  stdout.writeln('target: $base');
  await probe('public-info', '$base/System/Info/Public');
  await probe('public-users', '$base/Users/Public');
  await probe('items-unauth', '$base/Items?Recursive=true&Limit=1');
  // 拿一个不存在的 item id 试图片端点，看它是 404 还是 401 —— 判断
  // 「封面不加载」到底是鉴权问题还是网络问题。
  await probe(
    'image-fake-id',
    '$base/Items/ffffffffffffffffffffffffffffffff/Images/Primary?maxHeight=480',
  );

  // 连续 3 次，看连接复用之后还稳不稳。
  for (var i = 0; i < 3; i++) {
    await probe('repeat-$i', '$base/System/Info/Public');
  }

  client.close(force: true);
  exit(0);
}
