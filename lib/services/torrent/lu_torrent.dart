/// 磁力/种子在线播放服务（libtorrent 方案）。
///
/// 架构（用户拍板的 libtorrent 路线）：
///   * Android：libtorrent4j（JNI，Kotlin 侧 TorrentEngine.kt）顺序下载，
///     本地 HTTP 服务把「下载中的文件」按 Range 转成可拖动的流（边下边播）——
///     播放器每请求一段，就先把那段分片置为最优先，等落盘再喂出去；
///   * Windows：libtorrent DLL FFI 待后续版本接入；
///   * iOS：不做 BT（后台长连接受限 + App Store 审核对 BT 敏感）。
///
/// 入口在资源库页的「磁力播放」卡片（emby_res_pane.dart）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:XL/modules/hg/hg_diag.dart';

/// 磁力播放相关异常（消息直接展示给用户）。
class LuTorrentException implements Exception {
  const LuTorrentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 磁力任务的下载状态。
enum LuTorrentState {
  /// 正在解析元数据（等 peer / 种子信息）。
  fetching,

  /// 下载中（含边下边播）。
  downloading,

  /// 文件齐了。
  completed,

  /// 失败（无法解析 / 无可用 peer）。
  failed,
}

/// 磁力任务状态回推。
class LuTorrentProgress {
  const LuTorrentProgress({
    required this.state,
    required this.progress,
    this.downloadSpeed = 0,
    this.peers = 0,
    this.message = '',
  });

  final LuTorrentState state;

  /// 0.0 ~ 1.0。
  final double progress;
  final int downloadSpeed;
  final int peers;
  final String message;
}

class _TorrentTask {
  HttpServer? server;
  RandomAccessFile? file;
  Timer? pollTimer;
  StreamSubscription<dynamic>? events;
  int fileSize = 0;
  String fileName = '';
  String filePath = '';
  int pieceLength = 0;
}

class LuTorrent {
  LuTorrent._();

  static const MethodChannel _method = MethodChannel('lu/torrent');
  static final ValueNotifier<LuTorrentProgress> progress =
      ValueNotifier(const LuTorrentProgress(state: LuTorrentState.fetching, progress: 0));

  static _TorrentTask? _task;

  /// 元数据就绪后的文件名（进度弹窗里显示）。
  static String get fileName => _task?.fileName ?? '';

  /// 当前平台是否支持磁力播放（Android = libtorrent4j，iOS = libtorrent C++ 预制库）。
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  /// 发起磁力/种子在线播放。
  ///
  /// [source] 可以是 `magnet:?xt=...` 或 http(s) 的 .torrent 地址。
  /// 返回本地代理流地址（可直接交给播放器，边下边播、可拖动）。
  ///
  /// [onProgress] 下载进度回调（取第一个视频文件的下载比例）。
  static Future<String> stream(
    String source, {
    void Function(LuTorrentProgress p)? onProgress,
  }) async {
    final trimmed = source.trim();
    final isMagnet = trimmed.toLowerCase().startsWith('magnet:');
    final isTorrentUrl =
        Uri.tryParse(trimmed)?.path.toLowerCase().endsWith('.torrent') == true;
    if (!isMagnet && !isTorrentUrl) {
      throw const LuTorrentException('不是磁力链接（magnet:?xt=...）或种子地址（.torrent）');
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const LuTorrentException('磁力播放目前支持 Android / iOS，Windows 引擎将在后续版本接入');
    }

    await stop();
    final task = _TorrentTask();
    _task = task;

    // 元数据事件：就绪 / 失败。
    final ready = Completer<void>();
    task.events = EventChannel('lu/torrent/events')
        .receiveBroadcastStream()
        .listen((data) {
      if (data is! Map) return;
      final event = data['event'];
      if (event == 'metadata') {
        if (!ready.isCompleted) ready.complete();
      } else if (event == 'metadata_failed' || event == 'error') {
        if (!ready.isCompleted) {
          ready.completeError(const LuTorrentException('种子元数据获取失败（无可用 peer）'));
        }
      }
    }, onError: (Object e) {
      if (!ready.isCompleted) ready.completeError(e);
    });

    // 保存目录：应用支持目录/torrent。
    final dir = await getApplicationSupportDirectory();
    final saveDir = '${dir.path}${Platform.pathSeparator}torrent';

    try {
      // 逐步打点：原生崩溃时进程直接没了，只能靠「崩前最后一步」定位。
      // 重启 App 后看「播放诊断日志」里的 torrent.step。
      await HgDiag.trace('torrent.step', {
        'at': 'before_start',
        'ios': Platform.isIOS,
        'len': trimmed.length,
      });
      await _method.invokeMethod<dynamic>('start', {
        'magnet': trimmed,
        'saveDir': saveDir,
      });
      await HgDiag.trace('torrent.step', {'at': 'after_start'});
    } on PlatformException catch (e) {
      await stop();
      throw LuTorrentException('磁力任务启动失败：${e.message ?? e.code}');
    }

    // 等元数据（DHT/tracker 找种）。给 120 秒，超时明确报错。
    try {
      await ready.future.timeout(const Duration(seconds: 120));
    } on TimeoutException {
      await stop();
      throw const LuTorrentException('等种子元数据超时（120 秒）——磁力可能没有可用 peer');
    } on LuTorrentException {
      await stop();
      rethrow;
    } catch (e) {
      await stop();
      throw LuTorrentException('磁力任务失败：${e.toString().split('\n').first}');
    }

    await HgDiag.trace('torrent.step', {'at': 'after_metadata'});

    // 拉文件信息。
    final info = await _method.invokeMethod<dynamic>('fileInfo');
    await HgDiag.trace('torrent.step', {
      'at': 'after_fileinfo',
      'size': (info is Map ? info['fileSize'] : null),
    });
    if (info is! Map || (info['fileSize'] as num?) == null) {
      await stop();
      throw const LuTorrentException('种子元数据异常（没有文件信息）');
    }
    task.fileName = (info['fileName'] as String?)?.isNotEmpty == true
        ? info['fileName'] as String
        : '磁力视频';
    task.fileSize = (info['fileSize'] as num).toInt();
    task.filePath = info['path'] as String? ?? '';
    task.pieceLength = (info['pieceLength'] as num?)?.toInt() ?? 16384;
    if (task.fileSize <= 0 || task.filePath.isEmpty) {
      await stop();
      throw const LuTorrentException('种子里没有可播放的文件');
    }

    // 进度轮询（500ms）。
    if (onProgress != null) {
      task.pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          final st = await _method.invokeMethod<dynamic>('status');
          if (st is! Map || task != _task) return;
          final stateStr = st['state'] as String? ?? 'downloading';
          final p = LuTorrentProgress(
            state: stateStr == 'completed'
                ? LuTorrentState.completed
                : LuTorrentState.downloading,
            progress: ((st['progress'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
            downloadSpeed: (st['speed'] as num?)?.toInt() ?? 0,
            peers: (st['peers'] as num?)?.toInt() ?? 0,
          );
          progress.value = p;
          onProgress(p);
        } catch (_) {}
      });
    }

    await HgDiag.trace('torrent.step', {'at': 'before_server'});

    // 本地供流服务。
    try {
      task.server = await _startServer(task);
      await HgDiag.trace('torrent.step', {
        'at': 'after_server',
        'port': task.server?.port,
      });
    } catch (e) {
      await stop();
      throw LuTorrentException('本地流服务启动失败：${e.toString().split('\n').first}');
    }

    final port = task.server!.port;
    return 'http://127.0.0.1:$port/stream';
  }

  /// 停掉当前任务并清理本地代理。
  static Future<void> stop() async {
    final task = _task;
    _task = null;
    if (task == null) return;
    task.pollTimer?.cancel();
    await task.events?.cancel();
    try {
      await task.file?.close();
    } catch (_) {}
    try {
      await task.server?.close(force: true);
    } catch (_) {}
    try {
      await _method.invokeMethod<dynamic>('stop');
    } catch (_) {}
  }

  // ------------------------------------------------------------ 本地供流

  static Future<HttpServer> _startServer(_TorrentTask task) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.uri.path != '/stream') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        await _serve(task, request);
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    return server;
  }

  static Future<void> _serve(_TorrentTask task, HttpRequest request) async {
    final range = request.headers.value('range');
    int start = 0;
    int? end;
    if (range != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m.group(1)!.isNotEmpty) start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
      }
    }
    if (start >= task.fileSize) {
      request.response.statusCode = 416;
      request.response.headers.set('content-range', 'bytes */${task.fileSize}');
      await request.response.close();
      return;
    }
    end ??= task.fileSize - 1;
    end = end.clamp(start, task.fileSize - 1);

    final resp = request.response;
    resp.statusCode = 206;
    resp.headers.set('content-range', 'bytes $start-$end/${task.fileSize}');
    resp.headers.set('accept-ranges', 'bytes');
    resp.headers.set('content-type', 'video/mp4');
    resp.contentLength = end - start + 1;

    // 喂流：512KB 一段，先把分片置为最优先、等落盘再读。
    const chunk = 512 * 1024;
    var pos = start;
    final file = await File(task.filePath).open();
    task.file = file;
    final buffer = Uint8List(chunk);
    try {
      await resp.flush();
      while (pos <= end && _task == task) {
        final chunkEnd = (pos + chunk - 1).clamp(pos, end);
        final ok = await _ensureRange(task, pos, chunkEnd);
        if (!ok) {
          // 等不到分片（断种等）：直接断流，播放器会重试或报错。
          break;
        }
        final want = chunkEnd - pos + 1;
        await file.setPosition(pos);
        final got = await file.readInto(buffer, 0, want);
        if (got <= 0) break;
        pos += got;
        final data = Uint8List.sublistView(buffer, 0, got);
        await resp.addStream(Stream.value(data));
        await resp.flush();
      }
    } catch (_) {
      // 客户端断开（seek/暂停）很常见，静默。
    } finally {
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  /// 确保字节区间所在分片已落盘：先 prioritize（setPieceDeadline），再轮询。
  static Future<bool> _ensureRange(
      _TorrentTask task, int start, int end) async {
    // 交给引擎提升优先级。
    try {
      await _method.invokeMethod<dynamic>('prioritize', {
        'start': start,
        'end': end,
      });
    } catch (_) {}

    final deadline = DateTime.now().add(const Duration(seconds: 180));
    while (DateTime.now().isBefore(deadline) && _task == task) {
      try {
        final ready =
            await _method.invokeMethod<dynamic>('isReady', {'start': start, 'end': end});
        if (ready == true) return true;
      } catch (_) {
        return false; // 引擎没了（页面退出/任务停止）。
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// 校验链接格式（UI 输入框预校验用）。
  static bool looksLikeMagnet(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('magnet:') ||
        (Uri.tryParse(t)?.path.toLowerCase().endsWith('.torrent') == true);
  }
}
