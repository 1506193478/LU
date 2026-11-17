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

    // 回到前台：把 AVPlayer 的取帧循环拉起来。
    //
    // 3.9.45 曾在这里（resignActive）主动拉起小窗，但那个时机太早、又依赖
    // 临时放大图层，结果退后台再回来会掉帧甚至闪退。现在自动小窗完全交给
    // 系统的 canStartPictureInPictureAutomaticallyFromInline，这里只负责
    // 恢复渲染，不碰播放状态。
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        AvPlayerEnginePlugin.appBecameActive()
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
        // 磁力播放桥（libtorrent iOS）：注册 lu/torrent 通道。
        // messenger 从 registrar 拿，与 Android TorrentEngine.kt 同协议。
        if let torrentRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "LuTorrentBridge") {
            LuTorrentBridge.register(with: torrentRegistrar.messenger())
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

/// iOS 上的 AVPlayer 播放引擎（v2：系统组件方案）。
///
/// v1 是自研渲染（AVPlayerItemVideoOutput + CADisplayLink + Flutter 纹理），
/// 在 iOS 16 上存在起播失败（Emby 模块 mpv 能播、AVPlayer 播不了），且双路
/// 渲染并存曾导致 4K 黑屏、掉帧。v2 整体换成系统 AVPlayerViewController：
///   * PlatformView `xl/avplayer_view` 直接嵌入 AVKit 的 VC——苹果维护的
///     HLS/AES-128/杜比视界/HDR 播放路径，零自研渲染代码；
///   * 画中画天然可用（AVPlayerLayer 就在视图层级里，不再需要 1x1 宿主）；
///   * MethodChannel `xl/avplayer` / EventChannel `xl/avplayer/events` 的
///     命令与事件形状保持不变，Dart 侧只是把 Texture 换成 PlatformView。
@objcMembers public class AvPlayerEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let channelName = "xl/avplayer"
    private static let eventChannelName = "xl/avplayer/events"
    private static let viewTypeName = "xl/avplayer_view"

    private var registrar: FlutterPluginRegistrar?
    private var player: AVPlayer?
    private var playerController: AVPlayerViewController?
    private var statusObservation: NSKeyValueObservation?

    private var timeObserver: Any?
    private var eventSink: FlutterEventSink?
    private var isListening = false
    private var lastStatusReportedFailed = false

    // 供 Dart 查询的缓存值（periodic observer 每 0.5s 刷一次）。
    private var cachedDurationMs: Int64 = 0
    private var cachedBufferedMs: Int64 = 0

    /// 「自动开启画中画」开关（设置页下发），只影响自动触发，手动按钮不受限。
    static var autoPipEnabled = true

    private static var shared: AvPlayerEnginePlugin?

    /// 回到前台：系统组件自管生命周期，无需恢复任何东西。
    /// 保留方法以维持 AppDelegate 调用点不变。
    static func appBecameActive() {}

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AvPlayerEnginePlugin()
        shared = instance
        instance.registrar = registrar
        registrar.addMethodCallDelegate(
            instance,
            channel: FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
            .setStreamHandler(instance)
        registrar.register(AvPlayerViewFactory(plugin: instance), withId: viewTypeName)
    }

    // ---- AVPlayerViewController（懒创建，整个 App 一份） ----

    /// PlatformView 工厂与 create 命令都会走到这里；幂等。
    func ensurePlayerController() -> AVPlayerViewController {
        if let vc = playerController { return vc }
        let newPlayer = AVPlayer()
        let vc = AVPlayerViewController()
        vc.player = newPlayer
        // 系统原生控制条（进度/播放/音轨字幕选择/PiP 全是 AVKit 自带交互），
        // Flutter 侧不再叠自绘控件——用户要求原生按钮与手势。
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        // 画中画：AVPlayerLayer 就在这个 VC 的视图层级里，天然可用。
        vc.allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
            vc.canStartPictureInPictureAutomaticallyFromInline = AvPlayerEnginePlugin.autoPipEnabled
        }
        player = newPlayer
        playerController = vc
        return vc
    }

    // ---- EventChannel ----

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        isListening = true
        addPeriodicObserver()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        isListening = false
        eventSink = nil
        return nil
    }

    // ---- MethodChannel ----

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            // 视图由 PlatformView 工厂提供，这里只保证播放器存在并回个句柄。
            ensurePlayerController()
            result(Int64(0))
        case "open":
            open(arguments: call.arguments, result: result)
        case "play":
            player?.play()
            result(nil)
        case "pause":
            player?.pause()
            result(nil)
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
            // PiP 由 AVPlayerViewController 系统控制条自带（allowsPictureInPicturePlayback），
            // Dart 侧不自建 AVPictureInPictureController，避免与系统控制条双实例冲突。
            if #available(iOS 15.0, *) {
                result(AVPictureInPictureController.isPictureInPictureSupported())
            } else {
                result(false)
            }
        case "setAutoPip":
            AvPlayerEnginePlugin.autoPipEnabled = call.arguments as? Bool ?? true
            syncAutoPip()
            result(nil)
        case "startPip":
            startPip(result: result)
        case "stopPip":
            // PiP 由系统控制条管理（用户点系统画中画按钮退出），Dart 不直接操控。
            result(nil)
        case "dispose":
            teardown()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
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
        guard let uri = URL(string: urlString), !urlString.isEmpty else {
            result(FlutterError(code: "avplayer", message: "bad url", details: nil))
            return
        }
        teardownPlayerOnly()
        let vc = ensurePlayerController()
        guard let player = player else {
            result(FlutterError(code: "avplayer", message: "player unavailable", details: nil))
            return
        }

        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: uri)
        } else {
            asset = AVURLAsset(url: uri, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        let item = AVPlayerItem(asset: asset)

        // 失败诊断：status 走到 .failed 时把底层错误回传 Dart（触发回退 mpv）。
        lastStatusReportedFailed = false
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self = self else { return }
            if observedItem.status == .failed && !self.lastStatusReportedFailed {
                self.lastStatusReportedFailed = true
                let message = observedItem.error?.localizedDescription ?? "播放失败"
                self.eventSink?(["type": "error", "message": message] as [String: Any])
            }
        }

        player.replaceCurrentItem(with: item)

        // 完成事件。
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        // 失败事件。
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailed(note:)),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        player.volume = 1.0
        player.play()
        // 后台播放 / PiP / AirPlay 都依赖 playback 类别的音频会话，open 时
        // 就配好（配不成只影响这几样，不影响前台播放）。
        configureAudioSession()
        syncAutoPip()
        addPeriodicObserver()
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

    private func syncAutoPip() {
        guard #available(iOS 14.2, *) else { return }
        playerController?.canStartPictureInPictureAutomaticallyFromInline =
            AvPlayerEnginePlugin.autoPipEnabled
    }

    private func startPip(result: @escaping FlutterResult) {
        // PiP 由 AVPlayerViewController 的系统控制条提供（原生按钮，零自研）。
        // Dart 侧命令仅返回可用性，实际进入画中画请点系统控制条的画中画按钮。
        if #available(iOS 15.0, *), AVPictureInPictureController.isPictureInPictureSupported() {
            result(nil)
        } else {
            result(FlutterError(code: "avplayer", message: "画中画暂时不可用", details: nil))
        }
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
        // 预加载进度用 seekable range（真正能跳过去的范围）。HLS 转码流上
        // loadedTimeRanges 会把服务端预先转好的分段全算进来，缓冲条可能
        // 一大截，跟实际「能看多久」对不上。
        let ranges = item.seekableTimeRanges.isEmpty
            ? item.loadedTimeRanges
            : item.seekableTimeRanges
        let lastRange = ranges.last?.timeRangeValue
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

    // ---- 清理 ----

    private func teardownPlayerOnly() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        statusObservation = nil
        lastStatusReportedFailed = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        cachedDurationMs = 0
        cachedBufferedMs = 0
    }

    private func teardown() {
        teardownPlayerOnly()
    }

    deinit {
        teardown()
    }
}

// MARK: - PlatformView（AVPlayerViewController 宿主）

/// 工厂：把 AVPlayerViewController 的视图嵌进 Flutter 视图树。
class AvPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let plugin: AvPlayerEnginePlugin

    init(plugin: AvPlayerEnginePlugin) {
        self.plugin = plugin
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        AvPlayerPlatformView(plugin: plugin)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

class AvPlayerPlatformView: NSObject, FlutterPlatformView {
    private let container: UIView

    init(plugin: AvPlayerEnginePlugin) {
        container = UIView(frame: .zero)
        container.backgroundColor = .black
        super.init()
        let vc = plugin.ensurePlayerController()
        vc.view.frame = container.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(vc.view)
    }

    func view() -> UIView {
        container
    }
}
