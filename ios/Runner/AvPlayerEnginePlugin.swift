import Foundation
import AVFoundation
import Flutter

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
@objc public class AvPlayerEnginePlugin: NSObject, FlutterPlugin, FlutterTexture {
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

    // ---- Texture ----

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let output = output else { return nil }
        let buffer = output.copyPixelBuffer(forItemTime: player?.currentTime(), itemTimeForDisplay: nil)
        if buffer.width == 0 { return nil }
        return Unmanaged<CVPixelBuffer>.passRetained(buffer)
    }

    // ---- MethodChannel ----

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            createTexture(result)
        case "open":
            open(url: call.arguments as? String ?? "", result: result)
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
            selectTrack(trackId: call.arguments as? String ?? "", mediaType: .audio, result: result)
        case "selectSubtitleTrack":
            selectTrack(trackId: call.arguments as? String ?? "", mediaType: .legible, result: result)
        case "getTracks":
            result(trackInfo())
        case "getPosition":
            result(Int64(player?.currentTime().seconds.isNaN == true ? 0 : (player?.currentTime().seconds ?? 0) * 1000))
        case "getDuration":
            result(cachedDurationMs)
        case "dispose":
            teardown()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func createTexture(_ result: @escaping FlutterResult) {
        teardown()
        textureId = registrar!.textures().register(self)
        result(Int64(textureId))
    }

    private func open(url: String, result: @escaping FlutterResult) {
        guard let registrar = registrar, textureId >= 0, let uri = URL(string: url) else {
            result(FlutterError(code: "avplayer", message: "texture not created or bad url", details: nil))
            return
        }
        teardownPlayerOnly()

        let item = AVPlayerItem(url: uri)
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
        addPeriodicObserver()
        startDisplayLink()
        result(nil)
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

    private func selectTrack(trackId: String, mediaType: AVMediaType, result: @escaping FlutterResult) {
        guard let item = player?.currentItem else { result(nil); return }
        let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: mediaType)
        if trackId == "no" {
            item.selectMediaOption(nil, in: group!)
            result(nil); return
        }
        if let group = group, let index = Int(trackId), index < group.options.count {
            item.selectMediaOption(group.options[index], in: group)
        }
        result(nil)
    }

    private func trackInfo() -> [[String: Any]] {
        guard let item = player?.currentItem else { return [] }
        var out: [[String: Any]] = []
        for (mediaType, kind) in [(AVMediaType.audio, "audio"), (AVMediaType.legible, "subtitle")] {
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: mediaType)
            var list: [[String: Any]] = []
            for (i, option) in (group?.options ?? []).enumerated() {
                list.append([
                    "id": String(i),
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
        let bufferedMs = Int64((item.currentTime() + (item.bufferedTimeRanges.last?.timeRangeValue.duration ?? .zero)).seconds * 1000)
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
        guard textureId >= 0 else { return }
        registrar!.textures().textureFrameAvailable(textureId)
    }

    // ---- 清理 ----

    private func teardownPlayerOnly() {
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
