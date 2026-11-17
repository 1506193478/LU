/// HG 模块 WebView 宿主页（路线 A：承载 HGhubX fork 前端原样 bundle）。
///
/// 架构：
/// * 前端静态资源由 HgProxy 以 `/app/` 提供（与 /img /hls /seg 同源，无 CORS）；
/// * 文档创建前注入 shim：伪造 `window.__TAURI_INTERNALS__`（Tauri v2 IPC），
///   把 invoke 转成 flutter_inappwebview 的 callHandler('hgInvoke')；
/// * Dart 侧 [HgWebBridge.handle] 分派 40+ 个 Tauri 命令到现有 hg_* 服务。
///
/// 播放路径：hls.js（WebView 内，含上游低版本兼容修复）→ /hls /seg → 上游，
/// 不经过原生播放内核，规避 libmpv/AVPlayer 在低版本 iOS 上的兼容问题。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'hg_diag.dart';
import 'hg_proxy.dart';
import 'hg_web_bridge.dart';

class HgWebPage extends StatefulWidget {
  const HgWebPage({super.key});

  @override
  State<HgWebPage> createState() => _HgWebPageState();
}

class _HgWebPageState extends State<HgWebPage> {
  PlatformInAppWebViewController? _controller;
  String? _url;
  bool _loading = true;
  int _id = 0;

  @override
  void initState() {
    super.initState();
    _id = DateTime.now().microsecondsSinceEpoch;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await HgProxy.start();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      await HgDiag.trace('web.proxy_fail', {'err': e.toString()});
      return;
    }
    if (!mounted) return;
    setState(() => _url = '${HgProxy.origin}/app/index.html');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
          return;
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          child: _url == null ? _buildLoading() : _buildWebView(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Center(
      child: Text(
        '本地服务启动失败，请重启应用重试',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Widget _buildWebView() {
    final params = PlatformInAppWebViewWidgetCreationParams(
      initialUrlRequest: URLRequest(url: WebUri(_url!)),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _shimJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        transparentBackground: false,
        supportZoom: false,
        isInspectable: kDebugMode,
        javaScriptEnabled: true,
        useHybridComposition: Platform.isAndroid,
        disableContextMenu: false,
        allowBackgroundAudioPlaying: false,
        cacheEnabled: true,
      ),
      onWebViewCreated: (c) {
        _controller = c;
        c.addJavaScriptHandler(
          handlerName: 'hgInvoke',
          callback: (args) async => HgWebBridge.handle(args),
        );
      },
      onLoadStart: (_, __) {
        if (mounted) setState(() => _loading = true);
      },
      onLoadStop: (_, __) {
        if (mounted) setState(() => _loading = false);
        HgDiag.traceVerbose('web.loaded', {'url': _url});
      },
      onConsoleMessage: (_, message) {
        // 前端 console 落诊断日志，出问题有现场。
        HgDiag.traceVerbose('web.console', {
          'level': message.messageLevel.toString().split('.').last,
          'msg': message.message.length > 300
              ? message.message.substring(0, 300)
              : message.message,
        });
      },
      onReceivedError: (_, __, error) {
        HgDiag.trace('web.error', {'desc': error.description.toString()});
      },
    );
    final widget = PlatformInAppWebViewWidget(params);
    return widget.build(context);
  }

  /// Tauri v2 IPC shim（对齐 @tauri-apps/api 2.12 的内部实现）：
  /// * isTauri() 检查 window.isTauri 全局；
  /// * invoke → internals.invoke；
  /// * Channel 依赖 transformCallback + window['_<id>'] 回调；
  /// * getCurrentWindow 读 internals.metadata.currentWindow.label。
  ///
  /// flutter_inappwebview 自己的 JS 桥注入时机在文档创建之后，
  /// 所以 invoke 包一层轮询等待桥就绪。
  static String get _shimJs => '''
(function(){
  if (window.__HG_SHIM__) return;
  window.__HG_SHIM__ = true;
  window.__HG_LOCAL__ = '${HgProxy.origin}';
  window.isTauri = true;
  function callBridge(cmd, args) {
    return window.flutter_inappwebview.callHandler('hgInvoke', cmd, args || {});
  }
  var internals = {
    invoke: function(cmd, args, options) {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        return callBridge(cmd, args);
      }
      return new Promise(function(resolve, reject) {
        var n = 0;
        (function wait() {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            callBridge(cmd, args).then(resolve, reject);
          } else if (++n > 600) {
            reject('bridge not ready: ' + cmd);
          } else {
            setTimeout(wait, 10);
          }
        })();
      });
    },
    transformCallback: function(callback, once) {
      var identifier;
      try {
        identifier = window.crypto.getRandomValues(new Uint32Array(1))[0];
      } catch (e) {
        identifier = Math.floor(Math.random() * 2147483647);
      }
      var prop = '_' + identifier;
      Object.defineProperty(window, prop, {
        value: function(result) {
          if (once) { Reflect.deleteProperty(window, prop); }
          if (callback) { callback(result); }
        },
        writable: false,
        configurable: true
      });
      return identifier;
    },
    unregisterCallback: function() {},
    convertFileSrc: function(filePath, protocol) { return filePath; },
    metadata: {
      currentWindow: { label: 'main', listeners: {} },
      currentWebview: { windowLabel: 'main', label: 'main', listeners: {} }
    },
    plugins: {}
  };
  window.__TAURI_INTERNALS__ = internals;
})();
''';
}

