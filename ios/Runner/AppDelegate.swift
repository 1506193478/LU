import UIKit
import Flutter
import AVKit
import app_links

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Unclaimed URLs make Flutter replay launch callbacks to legacy plugins,
        // registering flutter_foreground_task's background task twice.
        AppLinks.shared.urlHandledCallBack = { url in
            url.scheme?.lowercased() == "kazumi"
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        // AVPlayer 插件的 registrar 要从 engineBridge.pluginRegistry 取——这是
        // 引擎自己的注册表，返回真正的 FlutterPluginRegistrar。两个错误来源都
        // 踩过：self.registrar(forPlugin:) 在隐式引擎下返回 nil（强解包即崩，
        // 3.9.36 启动闪退）；engineBridge.applicationRegistrar 是
        // FlutterApplicationRegistrar，类型不满足 FlutterPluginRegistrar。
        if let avRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "AvPlayerEnginePlugin") {
            AvPlayerEnginePlugin.register(with: avRegistrar)
        }

        let channel = FlutterMethodChannel(
            name: "com.predidit.kazumi/intent",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "openWithReferer" {
                guard let args = call.arguments else { return }
                if let myArgs = args as? [String: Any],
                   let url = myArgs["url"] as? String,
                   let referer = myArgs["referer"] as? String {
                    self?.openVideoWithReferer(url: url, referer: referer)
                }
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let storageChannel = FlutterMethodChannel(
            name: "com.predidit.kazumi/storage",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        storageChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "getAvailableStorage" {
                do {
                    let attrs = try FileManager.default.attributesOfFileSystem(
                        forPath: NSHomeDirectory()
                    )
                    if let freeSize = attrs[.systemFreeSize] as? Int64 {
                        result(freeSize)
                    } else {
                        result(-1)
                    }
                } catch {
                    result(-1)
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let castChannel = FlutterMethodChannel(
            name: "com.predidit.kazumi/cast",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        castChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "openRoutePicker" {
                result(NSNumber(value: self?.showRoutePicker() ?? false))
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // 系统自带的 AirPlay 设备列表。AVRoutePickerView 没有公开的直接弹出方法，
    // 只能把它临时挂到 window 上再触发它内部按钮的点击。
    private func showRoutePicker() -> Bool {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return false
        }
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.alpha = 0.01
        window.addSubview(picker)
        var tapped = false
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                tapped = true
                break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            picker.removeFromSuperview()
        }
        return tapped
    }

    // TODO: ADD VLC SUPPORT
    // VLC can be downloaded from iOS App Store, but don't know how to build selectable app lists, while checking if it is installled.
    // VLC supports more video formats than AVPlayer but does not support referer while AVPlayer does
    private func openVideoWithReferer(url: String, referer: String) {
        guard let videoUrl = URL(string: url) else { return }

        let headers: [String: String] = [
            "Referer": referer,
        ]
        let asset = AVURLAsset(url: videoUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.videoGravity = AVLayerVideoGravity.resizeAspect

        // Use UIScene API instead of deprecated keyWindow
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        rootViewController.present(playerViewController, animated: true) {
            playerViewController.player?.play()
        }

//        guard let appURL = URL(string: "vlc-x-callback://x-callback-url/stream?url=" + url) else {
//            return
//        }
//        if UIApplication.shared.canOpenURL(appURL) && referer.isEmpty {
//            UIApplication.shared.open(appURL, options: [:], completionHandler: nil)
//        }
    }
}

/// iOS 上的 AVPlayer 播放引擎（方向 B：HLS 走原生硬解）。
///
/// 为什么要做它：libmpv 播 Emby 转码（HLS）时向前 seek 可能落到还没转出来的
/// 切片上直接静默失败；而且 HDR / 画中画 / AirPlay 只有 AVPlayer 这条原生路。
/// 所以 iOS 上转码流优先走这里，AVPlayer 吃不了的容器（MKV 内封字幕等）继续
/// 回退到 media_kit。
///
/// 结构：
///   * MethodChannel `xl/avplayer` —— 控制命令（open/play/pause/seek/...）；
///   * EventChannel  `xl/avplayer/events` —— 状态回推（playing/position/...）；
///   * `registerExternalTexture` —— AVPlayerItemVideoOutput 的 pixel buffer
///     通过 CADisplayLink 拷给 Flutter Texture（videoTextureId 交给 Dart 侧
///     的 Texture widget 渲染）。
@objcMembers public class AvPlayerEnginePlugin: NSObject, FlutterPlugin, FlutterTexture, FlutterStreamHandler {
    private static let channelName = "xl/avplayer"
    private static let eventChannelName = "xl/avplayer/events"

    private var registrar: FlutterPluginRegistrar?
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var textureId: Int64 = -1
    private var timeObserver: Any?

    private var eventSink: FlutterEventSink?
    private var lastReportedPositionMs: Int64 = -1

    // 画中画：AVPictureInPictureController 必须吃一个「挂在视图层级里、
    // 有有效尺寸」的 AVPlayerLayer。我们渲染走的是 AVPlayerItemVideoOutput
    // （Flutter 纹理），没有 layer，所以专门造一个屏幕外的宿主 view 给它。
    // PiP 窗口显示的是这一层，和 Flutter 纹理互不干扰。
    private var pipController: AVPictureInPictureController?
    private var pipLayer: AVPlayerLayer?
    private var pipHost: UIView?

    // 供 Dart 查询的缓存值（periodic observer 每 0.5s 刷一次）。
    private var cachedDurationMs: Int64 = 0
    private var cachedBufferedMs: Int64 = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AvPlayerEnginePlugin()
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger()).setStreamHandler(instance)
    }

    // ---- EventChannel ----

    private var pendingResult: FlutterResult?
    private var isListening = false

    @objc public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        isListening = true
        addPeriodicObserver()
        return nil
    }

    @objc public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        isListening = false
        eventSink = nil
        return nil
    }

    // ---- Texture ----

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let output = output, let player = player else { return nil }
        let time = player.currentTime()
        guard time.isNumeric else { return nil }
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }
        if CVPixelBufferGetWidth(buffer) == 0 { return nil }
        return Unmanaged<CVPixelBuffer>.passRetained(buffer)
    }

    // ---- MethodChannel ----

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            createTexture(result)
        case "open":
            open(arguments: call.arguments, result: result)
        case "play":
            player?.play(); result(nil)
        case "pause":
            player?.pause(); result(nil)
        case "seek":
            seek(ms: (call.arguments as? NSNumber)?.int64Value ?? 0, result: result)
        case "setVolume":
            player?.volume = Float(truncating: call.arguments as? NSNumber ?? 1)
            result(nil)
        case "setRate":
            let rate = Float(truncating: call.arguments as? NSNumber ?? 1)
            let wasPlaying = player?.timeControlStatus == .playing
            player?.rate = wasPlaying ? rate : 0
            player?.currentItem?.audioTimePitchAlgorithm = .timeDomain
            result(nil)
        case "selectAudioTrack":
            selectTrack(trackId: call.arguments as? String ?? "", characteristic: .audible, result: result)
        case "selectSubtitleTrack":
            selectTrack(trackId: call.arguments as? String ?? "", characteristic: .legible, result: result)
        case "getTracks":
            result(trackInfo())
        case "getPosition":
            result(Int64(player?.currentTime().seconds.isNaN == true ? 0 : (player?.currentTime().seconds ?? 0) * 1000))
        case "getDuration":
            result(cachedDurationMs)
        case "isPipAvailable":
            result(pipController != nil && AVPictureInPictureController.isPictureInPictureSupported())
        case "startPip":
            guard let pip = pipController, pip.isPictureInPicturePossible else {
                result(FlutterError(code: "avplayer", message: "画中画暂时不可用", details: nil))
                return
            }
            pip.startPictureInPicture()
            result(nil)
        case "stopPip":
            if pipController?.isPictureInPictureActive == true {
                pipController?.stopPictureInPicture()
            }
            result(nil)
        case "dispose":
            teardown()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func createTexture(_ result: @escaping FlutterResult) {
        teardown()
        guard let registrar = registrar else {
            result(FlutterError(code: "avplayer", message: "registrar unavailable", details: nil))
            return
        }
        textureId = registrar.textures().register(self)
        result(Int64(textureId))
    }

    private func open(arguments: Any?, result: @escaping FlutterResult) {
        // 兼容两种参数：旧版纯 String；现在 [url, headers]（HLS 分片要带
        // X-Emby-Token，光靠地址上的 api_key 不够）。
        var urlString = ""
        var headers: [String: String] = [:]
        if let dict = arguments as? [String: Any] {
            urlString = dict["url"] as? String ?? ""
            if let raw = dict["headers"] as? [String: String] {
                headers = raw
            }
        } else if let s = arguments as? String {
            urlString = s
        }
        open(urlString: urlString, headers: headers, result: result)
    }

    private func open(urlString: String, headers: [String: String], result: @escaping FlutterResult) {
        guard let registrar = registrar, textureId >= 0, let uri = URL(string: urlString) else {
            result(FlutterError(code: "avplayer", message: "texture not created or bad url", details: nil))
            return
        }
        teardownPlayerOnly()

        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: uri)
        } else {
            asset = AVURLAsset(url: uri, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        // 尽量少做格式转换：转码流出来就是能硬解的 H264/HEVC。
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_32BGRA]
        ])
        item.add(output)
        self.output = output

        // 完成事件。
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)

        // 失败事件。
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailed(note:)),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        newPlayer.volume = 1.0
        newPlayer.play()
        // 后台播放 / PiP / AirPlay 都依赖 playback 类别的音频会话，open 时
        // 就配好（配不成只影响这几样，不影响前台播放）。
        configureAudioSession()
        setupPip(player: newPlayer)
        addPeriodicObserver()
        startDisplayLink()
        result(nil)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // 静默失败：播放在前台照常，只是退后台可能被系统压掉。
        }
    }

    private func setupPip(player newPlayer: AVPlayer) {
        teardownPip()
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // 宿主 view 放屏幕外（系统仍认它在视图层级里），160x90 给 layer
        // 一个有效尺寸；0 尺寸 / 不挂 window 时 startPictureInPicture 静默无效。
        let host = UIView(frame: CGRect(x: -220, y: -220, width: 160, height: 90))
        host.alpha = 0.01
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        window.addSubview(host)
        let layer = AVPlayerLayer(player: newPlayer)
        layer.frame = host.bounds
        layer.videoGravity = .resizeAspect
        host.layer.addSublayer(layer)
        pipHost = host
        pipLayer = layer
        let controller = AVPictureInPictureController(playerLayer: layer)
        // 用户按 Home / 切后台时自动进小窗——这是 iOS 播放器的标准体验。
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.delegate = self
        pipController = controller
    }

    private func teardownPip() {
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true {
            // 换片 / 销毁时先把小窗收掉，别让它挂着旧画面。
            pipController?.stopPictureInPicture()
        }
        pipController = nil
        pipLayer?.removeFromSuperlayer()
        pipLayer = nil
        pipHost?.removeFromSuperview()
        pipHost = nil
    }

    private func seek(ms: Int64, result: @escaping FlutterResult) {
        let seconds = Double(ms) / 1000.0
        // HLS 向前 seek 可能要等切片，宽松一点别立刻放弃。
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player?.play()
            result(nil)
        }
    }

    private func selectTrack(trackId: String, characteristic: AVMediaCharacteristic, result: @escaping FlutterResult) {
        guard let item = player?.currentItem else { result(nil); return }
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            result(nil); return
        }
        if trackId == "no" {
            item.select(nil, in: group)
            result(nil); return
        }
        if let index = Int(trackId), index < group.options.count {
            item.select(group.options[index], in: group)
        }
        result(nil)
    }

    private func trackInfo() -> [[String: Any]] {
        guard let item = player?.currentItem else { return [] }
        let groups: [(AVMediaCharacteristic, String)] = [
            (AVMediaCharacteristic.audible, "audio"),
            (AVMediaCharacteristic.legible, "subtitle"),
        ]
        var out: [[String: Any]] = []
        for (characteristic, kind) in groups {
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic)
            var list: [[String: Any]] = []
            let options = group?.options ?? []
            for index in 0..<options.count {
                let option = options[index]
                list.append([
                    "id": String(index),
                    "title": option.displayName,
                    "language": option.extendedLanguageTag ?? "",
                ])
            }
            out.append(["kind": kind, "tracks": list])
        }
        return out
    }

    // ---- 周期上报 ----

    private func addPeriodicObserver() {
        guard let player = player, timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main) { [weak self] time in
            self?.reportState(time: time)
        }
    }

    private func reportState(time: CMTime) {
        guard isListening, let player = player, let item = player.currentItem else { return }
        let positionMs = Int64(time.seconds.isNaN ? 0 : time.seconds * 1000)
        let durationMs = Int64(item.duration.seconds.isNaN ? 0 : item.duration.seconds * 1000)
        let lastRange = item.loadedTimeRanges.map { $0.timeRangeValue }.last
        let bufferedEnd = (lastRange?.start.seconds ?? 0) + (lastRange?.duration.seconds ?? 0)
        let bufferedMs = Int64(bufferedEnd.isNaN ? 0 : bufferedEnd * 1000)
        cachedDurationMs = durationMs
        cachedBufferedMs = bufferedMs
        let playing = player.timeControlStatus != .paused
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate

        // 视频尺寸变化（第一帧出画面前拿不到）。
        if let track = item.asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            eventSink?(["type": "size", "width": Int(abs(size.width)), "height": Int(abs(size.height))])
        }
        eventSink?([
            "type": "state",
            "position": positionMs,
            "duration": durationMs,
            "buffered": bufferedMs,
            "playing": playing,
            "buffering": buffering,
        ] as [String: Any])
    }

    @objc private func itemDidEnd() {
        eventSink?(["type": "completed"] as [String: Any])
    }

    @objc private func itemFailed(note: Notification) {
        let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription ?? "播放失败"
        eventSink?(["type": "error", "message": message] as [String: Any])
    }

    // ---- 渲染帧 ----

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(frameTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frameTick() {
        guard textureId >= 0, let registrar = registrar else { return }
        registrar.textures().textureFrameAvailable(textureId)
    }

    // ---- 清理 ----

    private func teardownPlayerOnly() {
        teardownPip()
        stopDisplayLink()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        player?.pause()
        player = nil
        output = nil
    }

    private func teardown() {
        teardownPlayerOnly()
        if textureId >= 0, let registrar = registrar {
            registrar.textures().unregisterTexture(textureId)
            textureId = -1
        }
    }

    deinit {
        teardown()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension AvPlayerEnginePlugin: AVPictureInPictureControllerDelegate {
    // 注意：类是 public 的，public 协议的实现方法也必须显式 public，
    // 否则 CI 上编译直接报错（本地不编 iOS 探不到）。
    public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        // 画面走系统小窗了，Flutter 纹理这一路先停掉省电（后台 displayLink
        // 本来也会被系统挂起，主动停是让「PiP 期间回前台」也不空转）。
        stopDisplayLink()
        eventSink?(["type": "pip", "active": true] as [String: Any])
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        if player != nil {
            startDisplayLink()
        }
        eventSink?(["type": "pip", "active": false] as [String: Any])
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // 用户在小窗点了「还原」：Flutter 播放页还开着，直接认领。
        completionHandler(true)
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        // 注意不能发 "error" 类型——那会触发 Dart 侧的回退 mpv 逻辑。
        eventSink?([
            "type": "pip", "active": false,
            "message": error.localizedDescription,
        ] as [String: Any])
    }
}
