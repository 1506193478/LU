import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import Combine

// MARK: - 播放内核

final class PlayerViewModel: ObservableObject {
    let player: AVPlayer
    private(set) var stream: PlayStream

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var rate: Float = 1.0
    @Published var danmakuEnabled = true
    @Published var danmakuComments: [DanmakuComment] = []
    @Published var laidOut: [LaidOutDanmaku] = []
    @Published var errorText: String?
    @Published var isSeeking = false
    /// 画面比例（适应 / 填充 / 拉伸）
    @Published var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// 内嵌音轨与字幕轨
    @Published private(set) var audioTracks: [MediaTrack] = []
    @Published private(set) var subtitleTracks: [MediaTrack] = []

    /// 一条内嵌轨道
    struct MediaTrack: Identifiable, Equatable {
        let id: Int
        let name: String
        let isSelected: Bool
    }

    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?

    var onPlaybackEnded: (() -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusCancellable: AnyCancellable?
    private var canvasWidth: CGFloat = 390
    /// 挂在当前 item 上的视频输出，用于截取当前帧
    private var videoOutput: AVPlayerItemVideoOutput?

    init(stream: PlayStream) {
        self.stream = stream

        var options: [String: Any] = [:]
        if !stream.headers.isEmpty {
            // AVURLAsset 的 HTTP 头扩展键（业界通用做法），用于携带 Referer
            options["AVURLAssetHTTPHeaderFieldsKey"] = stream.headers
        }
        let asset = AVURLAsset(url: stream.url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true

        videoGravity = Self.gravity(for: AppSettings.shared.aspectMode)
        activateAudioSession()
        observe()
        applyEnhance(AppSettings.shared.videoEnhance)
        // 轨道列表要等资源元数据就绪，延迟一次再读
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshMediaOptions()
        }
    }

    // MARK: 画面比例 / 滤镜

    static func gravity(for mode: String) -> AVLayerVideoGravity {
        switch mode {
        case "fill": return .resizeAspectFill
        case "stretch": return .resize
        default: return .resizeAspect
        }
    }

    /// 画质增强走 `AVVideoComposition` + Core Image。
    /// 注意：开了这层会失去 HDR 与部分硬件直通，默认关闭。
    func applyEnhance(_ mode: String) {
        guard let item = player.currentItem else { return }
        guard mode != "off", let asset = item.asset as? AVURLAsset else {
            item.videoComposition = nil
            return
        }
        item.videoComposition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            var output = source
            switch mode {
            case "sharpen":
                output = source.applyingFilter("CISharpenLuminance",
                                               parameters: [kCIInputSharpnessKey: 0.55])
            case "vivid":
                output = source.applyingFilter("CIColorControls",
                                               parameters: [kCIInputSaturationKey: 1.12,
                                                            kCIInputContrastKey: 1.04])
            case "soft":
                output = source.applyingFilter("CINoiseReduction",
                                               parameters: ["inputNoiseLevel": 0.02,
                                                            "inputSharpness": 0.4])
            default:
                break
            }
            request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
        }
        luLogInfo("Player", "画质增强：\(mode)")
    }

    // MARK: 内嵌轨道

    func refreshMediaOptions() {
        guard let item = player.currentItem, let asset = item.asset as? AVURLAsset else { return }
        Task { @MainActor in
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            audioGroup = audible
            legibleGroup = legible

            var currentAudio: AVMediaSelectionOption?
            if let audible {
                currentAudio = item.currentMediaSelection.selectedMediaOption(in: audible)
            }
            audioTracks = (audible?.options ?? []).enumerated().map { index, option in
                MediaTrack(id: index, name: option.displayName, isSelected: option === currentAudio)
            }

            var currentSubtitle: AVMediaSelectionOption?
            if let legible {
                currentSubtitle = item.currentMediaSelection.selectedMediaOption(in: legible)
            }
            subtitleTracks = (legible?.options ?? []).enumerated().map { index, option in
                MediaTrack(id: index, name: option.displayName, isSelected: option === currentSubtitle)
            }
        }
    }

    func selectAudio(_ index: Int) {
        guard let group = audioGroup, index >= 0, index < group.options.count,
              let item = player.currentItem else { return }
        item.select(group.options[index], in: group)
        refreshMediaOptions()
        LuHUD.shared.show("已切换音轨")
    }

    /// index 传 -1 表示关闭内嵌字幕
    func selectEmbeddedSubtitle(_ index: Int) {
        guard let group = legibleGroup, let item = player.currentItem else { return }
        if index < 0 {
            item.select(nil, in: group)
        } else if index < group.options.count {
            item.select(group.options[index], in: group)
        }
        refreshMediaOptions()
        LuHUD.shared.show(index < 0 ? "已关闭内嵌字幕" : "已切换内嵌字幕")
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback,
                                 options: [.allowAirPlay, .allowBluetooth])
        try? session.setActive(true)
    }

    private func observe() {
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status == .playing
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            if seconds.isFinite, !self.isSeeking {
                self.position = seconds
            }
            if let itemDuration = self.player.currentItem?.duration.seconds,
               itemDuration.isFinite, itemDuration > 0 {
                self.duration = itemDuration
            }
        }

        reobserveEnd()
    }

    private func reobserveEnd() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.onPlaybackEnded?()
            }
        }
    }

    /// 切集：替换当前 item，保留同一个 AVPlayer（避免重建视频层闪烁）。
    func switchStream(_ newStream: PlayStream) {
        stream = newStream
        var options: [String: Any] = [:]
        if !newStream.headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = newStream.headers
        }
        let asset = AVURLAsset(url: newStream.url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        player.replaceCurrentItem(with: item)
        reobserveEnd()
        applyEnhance(AppSettings.shared.videoEnhance)
        refreshMediaOptions()
        position = 0
        duration = 0
        isBuffering = true
        play()
    }

    // MARK: 控制

    func play() {
        player.play()
        player.rate = rate
    }

    func pause() { player.pause() }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let target = CMTime(seconds: max(0, min(seconds, max(duration, 0))),
                            preferredTimescale: 600)
        isSeeking = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.position = seconds
            }
        }
    }

    func skip(_ delta: Double) {
        seek(to: position + delta)
    }

    func setRate(_ value: Float) {
        rate = value
        if isPlaying { player.rate = value }
    }

    func start(from seconds: Double) {
        if seconds > 3 { seek(to: seconds) }
        play()
    }

    // MARK: 弹幕

    @MainActor
    func loadDanmaku(query: DanmakuQuery) async {
        do {
            let comments = try await DanmakuService.shared.fetch(query: query)
            danmakuComments = comments
            relayout()
            luLogInfo("Player", "弹幕 \(comments.count) 条（\(AppSettings.shared.danmakuSource)）")
        } catch {
            errorText = "弹幕加载失败：\(error.localizedDescription)"
            luLogWarn("Player", "弹幕失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func relayout() {
        let fontSize = CGFloat(AppSettings.shared.danmakuFontSize)
        laidOut = DanmakuLayout.layout(danmakuComments,
                                       fontSize: fontSize,
                                       canvasWidth: canvasWidth,
                                       duration: 8)
    }

    @MainActor
    func updateCanvasWidth(_ width: CGFloat) {
        guard abs(width - canvasWidth) > 1 else { return }
        canvasWidth = width
        relayout()
    }

    // MARK: 截图

    /// 取当前解码帧。返回 nil 表示当前帧还没解出来（刚起播或正在缓冲）。
    func snapshot() -> UIImage? {
        guard let output = videoOutput, let item = player.currentItem else { return nil }
        let time = item.currentTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusCancellable?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }
}

// MARK: - 视频层

final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct AVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        LuPiPController.shared.attach(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
        if uiView.playerLayer.videoGravity != gravity {
            uiView.playerLayer.videoGravity = gravity
        }
        LuPiPController.shared.attach(uiView.playerLayer)
    }
}
