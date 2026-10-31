import 'dart:async';
import 'dart:collection';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/webview/video/video_webview_controller.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:XL/utils/http_headers.dart';
import 'package:XL/utils/media.dart';

class VideoWebviewAppleImpl
    extends VideoWebviewController<PlatformInAppWebViewController> {
  PlatformHeadlessInAppWebView? headlessWebView;
  bool hasInjectedScripts = false;

  @override
  Future<void> init() async {
    headlessWebView ??= PlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams(
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: '''
            function removeLazyLoading() {
              document.querySelectorAll('iframe[loading="lazy"]').forEach(iframe => {
                console.log('Removing lazy loading from:', iframe.src);
                iframe.removeAttribute('loading');
              });
            }
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', removeLazyLoading);
            } else {
              removeLazyLoading();
            }
          ''',
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          userAgent: getRandomUA(),
          // WKWebView 默认 true：没有用户手势就不许 `<video>` 起播。
          // 但这个 webview 是**无头**的，全程没有任何手势可给，于是走
          // 「页面自己 JS 起播 → 我们去嗅流地址」这条链的源就永远拿不到
          // m3u8/mp4 —— 表现为 iOS 上「有的番剧点进去一直转圈 / 加载不出」，
          // 而同一部番在安卓正常（安卓 WebView 对无手势的限制宽松得多）。
          mediaPlaybackRequiresUserGesture: false,
          // 内联播放，别让 WKWebView 把视频推去全屏原生播放器。
          allowsInlineMediaPlayback: true,
          useOnLoadResource: false,
          cacheEnabled: false,
          isInspectable: false,
          contentBlockers: [
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?devtools-detector\.js",
                  resourceType: [
                    ContentBlockerTriggerResourceType.SCRIPT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: '.*', resourceType: [
                ContentBlockerTriggerResourceType.IMAGE,
              ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?googleads",
                  resourceType: [
                    ContentBlockerTriggerResourceType.DOCUMENT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?googlesyndication\.com",
                  resourceType: [
                    ContentBlockerTriggerResourceType.DOCUMENT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?prestrain\.html",
                  resourceType: [
                    ContentBlockerTriggerResourceType.DOCUMENT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?prestrain%2Ehtml",
                  resourceType: [
                    ContentBlockerTriggerResourceType.DOCUMENT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: r"^https?://.+?adtrafficquality",
                  resourceType: [
                    ContentBlockerTriggerResourceType.DOCUMENT,
                  ]),
              action:
                  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
          ],
        ),
        onWebViewCreated: (controller) {
          KazumiLogger().i('WebView: created');
          webviewController = controller;
          initEventController.add(true);
        },
        onLoadStart: (controller, url) {
          logEventController.add('started loading: $url');
        },
        onLoadStop: (controller, url) {
          logEventController.add('loading completed: $url');
        },
        onReceivedError: (controller, request, error) {
          KazumiLogger().e(
              'WebView: error: ${error.toString()} - Request: ${request.url}');
        },
      ),
    );
    await headlessWebView?.run();
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser,
      {int offset = 0}) async {
    // WKWebView 的 onWebViewCreated 是异步回来的，`headlessWebView.run()` 返回时
    // 并不保证 controller 已经就位。原来这里直接往下走，`webviewController?.`
    // 一旦是 null 就静默什么都不做 —— 页面根本没加载，却当成"已经去解析了"，
    // 表现就是某些源一直转圈解析不出来。这里先等一下，最多 3 秒。
    await _awaitWebviewController();
    await unloadPage();
    if (!hasInjectedScripts) {
      addJavaScriptHandlers(useLegacyParser);
      await addUserScripts(useLegacyParser);
      hasInjectedScripts = true;
    }
    count = 0;
    this.offset = offset;
    isIframeLoaded = false;
    isVideoSourceLoaded = false;
    videoLoadingEventController.add(true);

    await webviewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _awaitWebviewController() async {
    if (webviewController != null) return;
    final DateTime deadline =
        DateTime.now().add(const Duration(milliseconds: 3000));
    while (webviewController == null) {
      if (DateTime.now().isAfter(deadline)) {
        KazumiLogger().e(
            'WebView: controller still null after 3s, page will not load');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void addJavaScriptHandlers(bool useLegacyParser) {
    logEventController.add('Adding LogBridge handler');
    webviewController?.addJavaScriptHandler(
        handlerName: 'LogBridge',
        callback: (args) {
          String message = args[0].toString();
          if (message.contains('about:blank')) {
            return;
          }
          logEventController.add(message);
        });

    if (useLegacyParser) {
      logEventController.add('Adding JSBridgeDebug handler');
      webviewController?.addJavaScriptHandler(
          handlerName: 'JSBridgeDebug',
          callback: (args) {
            String message = args[0].toString();
            logEventController.add('Callback received: $message');
            logEventController.add(
                'If there is audio but no video, please report it to the rule developer.');
            if ((message.contains('http') || message.startsWith('//')) &&
                !message.contains('googleads') &&
                !message.contains('googlesyndication.com') &&
                !message.contains('prestrain.html') &&
                !message.contains('prestrain%2Ehtml') &&
                !message.contains('adtrafficquality')) {
              logEventController.add('Parsing video source $message');
              String encodedUrl = Uri.encodeFull(message);
              if (decodeVideoSource(encodedUrl) != encodedUrl) {
                isIframeLoaded = true;
                isVideoSourceLoaded = true;
                videoLoadingEventController.add(false);
                logEventController.add(
                    'Loading video source ${decodeVideoSource(encodedUrl)}');
                unloadPage();
                final videoUrl = decodeVideoSource(encodedUrl);
                notifyVideoSourceResolved(videoUrl);
              }
            }
          });
    } else {
      logEventController.add('Adding VideoBridgeDebug handler');
      webviewController?.addJavaScriptHandler(
          handlerName: 'VideoBridgeDebug',
          callback: (args) {
            String message = args[0].toString();
            logEventController.add('Callback received: $message');
            if (message.contains('http') && !isVideoSourceLoaded) {
              logEventController.add('Loading video source: $message');
              isIframeLoaded = true;
              isVideoSourceLoaded = true;
              videoLoadingEventController.add(false);
              unloadPage();
              notifyVideoSourceResolved(message);
            }
          });
    }
  }

  Future<void> addUserScripts(bool useLegacyParser) async {
    final List<UserScript> scripts = [];

    if (useLegacyParser) {
      logEventController.add('Adding JSBridgeDebug UserScript');
      const String jsBridgeDebugScript = """
        window.flutter_inappwebview.callHandler('LogBridge', 'JSBridgeDebug script loaded: ' + window.location.href);
        var iframes = document.getElementsByTagName('iframe');
        window.flutter_inappwebview.callHandler('LogBridge', 'The number of iframe tags is ' + iframes.length);
        for (var i = 0; i < iframes.length; i++) {
            var iframe = iframes[i];
            var src = iframe.getAttribute('src');
            if (src) {
              window.flutter_inappwebview.callHandler('JSBridgeDebug', src);
            }
        }
      """;
      scripts.add(UserScript(
        source: jsBridgeDebugScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ));
    } else {
      logEventController.add('Adding VideoBridgeDebug UserScripts');
      const String blobParserScript = """
        window.flutter_inappwebview.callHandler('LogBridge', 'BlobParser script loaded: ' + window.location.href);
        const _r_text = window.Response.prototype.text;
        window.Response.prototype.text = function () {
            return new Promise((resolve, reject) => {
                _r_text.call(this).then((text) => {
                    resolve(text);
                    if (text.trim().startsWith("#EXTM3U")) {
                        window.flutter_inappwebview.callHandler('LogBridge', 'M3U8 source found: ' + this.url);
                        window.flutter_inappwebview.callHandler('VideoBridgeDebug', this.url);
                    }
                }).catch(reject);
            });
        }

        const _open = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function (...args) {
            this.addEventListener("load", () => {
                try {
                    let content = this.responseText;
                    if (content.trim().startsWith("#EXTM3U")) {
                        window.flutter_inappwebview.callHandler('LogBridge', 'M3U8 source found: ' + args[1]);
                        window.flutter_inappwebview.callHandler('VideoBridgeDebug', args[1]);
                    };
                } catch {}
            });
            return _open.apply(this, args);
        };
      """;

      const String videoTagParserScript = """
        window.flutter_inappwebview.callHandler('LogBridge', 'VideoTagParser script loaded: ' + window.location.href);
        function processVideoElement(video) {
          window.flutter_inappwebview.callHandler('LogBridge', 'Scanning video element for source URL');
          let src = video.getAttribute('src');
          if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
            window.flutter_inappwebview.callHandler('LogBridge', 'VIDEO source found: ' + src);
            window.flutter_inappwebview.callHandler('VideoBridgeDebug', src);
            return;
          }
          const sources = video.getElementsByTagName('source');
          for (let source of sources) {
            src = source.getAttribute('src');
            if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
              window.flutter_inappwebview.callHandler('LogBridge', 'VIDEO source found (source tag): ' + src);
              window.flutter_inappwebview.callHandler('VideoBridgeDebug', src);
              return;
            }
          }
        }

        document.querySelectorAll('video').forEach(processVideoElement);

        const _observer = new MutationObserver((mutations) => {
          window.flutter_inappwebview.callHandler('LogBridge', 'Scanning for video elements...');
          mutations.forEach(mutation => {
            if (mutation.type === 'attributes' && mutation.target.nodeName === 'VIDEO') {
              processVideoElement(mutation.target);
            }
            mutation.addedNodes.forEach(node => {
              if (node.nodeName === 'VIDEO') processVideoElement(node);
              if (node.querySelectorAll) {
                node.querySelectorAll('video').forEach(processVideoElement);
              }
            });
          });  
        });

        _observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src']
        });
    """;

      // 按 **请求地址** 嗅 m3u8。
      //
      // 上面那三个脚本都在「拿到响应之后」才判断（Response.text / XHR 的
      // responseText / <video> 标签），覆盖不到三种常见写法：
      //   1. fetch 之后用 arrayBuffer()/blob() 读，从不调 text()；
      //   2. hls.js 之类把 master playlist 拉下来后只取二进制；
      //   3. 播放地址由 JS 拼好直接交给播放器库，从不落到 DOM 上。
      // 安卓那边有 shouldInterceptRequest 原生兜底（所有请求都能看到），
      // iOS 的 WKWebView 没有这个能力，只能靠 JS 自己补，于是同样的源在
      // 安卓能解析、在 iOS 解析不出来。
      //
      // 这里只在 DOCUMENT_START 包一层 fetch / XHR.open，看 **地址** 里有没有
      // .m3u8，命中就上报；广告域名直接丢掉。不碰响应体，开销可以忽略。
      // 整个脚本包在 IIFE 里，避免和上面那些脚本的顶层 const 撞名。
      const String urlSnifferScript = """
        (function () {
          if (window.__xlUrlSnifferInstalled) return;
          window.__xlUrlSnifferInstalled = true;

          const AD_HOSTS = ['googleads', 'googlesyndication', 'doubleclick',
                            'prestrain', 'adtrafficquality'];
          const seen = Object.create(null);

          function report(url) {
            if (!url || typeof url !== 'string') return;
            if (url.indexOf('.m3u8') < 0) return;
            const lower = url.toLowerCase();
            for (let i = 0; i < AD_HOSTS.length; i++) {
              if (lower.indexOf(AD_HOSTS[i]) >= 0) return;
            }
            if (seen[url]) return;
            seen[url] = true;
            window.flutter_inappwebview.callHandler('VideoBridgeDebug', url);
          }

          function pick(input) {
            try {
              if (typeof input === 'string') return input;
              if (input && typeof input.url === 'string') return input.url;
            } catch (e) {}
            return '';
          }

          const _fetch = window.fetch;
          if (_fetch) {
            window.fetch = function (input, init) {
              try { report(pick(input)); } catch (e) {}
              return _fetch.apply(this, arguments);
            };
          }

          const _xhrOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function (method, url) {
            try { report(pick(url)); } catch (e) {}
            return _xhrOpen.apply(this, arguments);
          };
        })();
      """;

      scripts.add(UserScript(
        source: blobParserScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ));
      scripts.add(UserScript(
        source: urlSnifferScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ));
      scripts.add(UserScript(
        source: videoTagParserScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        forMainFrameOnly: false,
      ));
    }

    await webviewController?.addUserScripts(
      userScripts: scripts,
    );
  }

  @override
  Future<void> unloadPage() async {
    // 用 ?. 而不是 !：`loadUrl` 里是先 unloadPage 再加载，controller 还没
    // 就位时这里 `!` 会直接抛 Null check operator，整个解析流程中断。
    await webviewController
        ?.loadUrl(urlRequest: URLRequest(url: WebUri("about:blank")));
  }

  @override
  Future<void> dispose() async {
    await headlessWebView?.dispose();
    headlessWebView = null;
    webviewController = null;
    disposeEventControllers();
  }
}
