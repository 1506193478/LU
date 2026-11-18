import SwiftUI
import UIKit

struct PlayerView: View {
    let subject: AnimeSubject
    let episodes: [AnimeEpisode]
    var resolveStream: (AnimeEpisode) async -> PlayStream?

    @StateObject private var vm: PlayerViewModel
    @ObservedObject private var sync = SyncPlaySession.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings

    @State private var currentEpisode: AnimeEpisode
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var episodeSheetShown = false
    @State private var isSwitching = false

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var dragMode: DragMode = .none
    @State private var startBrightness: CGFloat = UIScreen.main.brightness
    @State private var overlayHint: String?

    // 字幕
    @State private var subtitleTrack: SubtitleTrack?
    @State private var subtitleOffset: Double = 0
    @State private var subtitleSheetShown = false
    @State private var optionsSheetShown = false

    // 投屏 / 下载
    @State private var castSheetShown = false
    @State private var downloadPrompt = false

    private enum DragMode: Equatable { case none, seek, brightness }

    init(subject: AnimeSubject, episode: AnimeEpisode, stream: PlayStream,
         episodes: [AnimeEpisode],
         initialSubtitle: SubtitleTrack? = nil,
         resolveStream: @escaping (AnimeEpisode) async -> PlayStream?) {
        self.subject = subject
        self.episodes = episodes
        self.resolveStream = resolveStream
        _currentEpisode = State(initialValue: episode)
        _subtitleTrack = State(initialValue: initialSubtitle)
        _vm = StateObject(wrappedValue: PlayerViewModel(stream: stream))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                AVPlayerSurface(player: vm.player, gravity: vm.videoGravity)
                    .ignoresSafeArea()

                if settings.danmakuEnabled && vm.danmakuEnabled {
                    DanmakuLayer(
                        comments: vm.laidOut,
                        currentTime: vm.position,
                        fontSize: CGFloat(settings.danmakuFontSize),
                        opacity: settings.danmakuOpacity,
                        areaRatio: settings.danmakuArea,
                        isPlaying: vm.isPlaying,
                        speed: settings.danmakuSpeed
                    )
                    .ignoresSafeArea()
                    .onAppear { vm.updateCanvasWidth(geo.size.width) }
                }

                if let subtitleTrack {
                    SubtitleOverlay(cue: subtitleTrack.cue(at: vm.position + subtitleOffset),
                                    fontSize: subtitleFontSize)
                }

                interactionLayer(width: geo.size.width)

                if showsSkipIntro {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: skipIntro) {
                                HStack(spacing: 5) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.system(size: 10))
                                    Text("跳过片头 \(settings.skipIntroSeconds)s")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().fill(Color.black.opacity(0.55)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.bottom, controlsVisible ? 132 : 32)
                        }
                    }
                    .transition(.luBoing)
                    .animation(LuMotion.quick, value: controlsVisible)
                }

                if controlsVisible {
                    controlsLayer(width: geo.size.width)
                        .transition(.luBlur)
                }

                if isSwitching {
                    ProgressView().tint(.white)
                        .padding(20)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }

                if let overlayHint {
                    Text(overlayHint)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.62)))
                        .transition(.luBoing)
                }
            }
        }
        .statusBarHidden(true)
        .background(Color.black)
        .onAppear { bootstrap() }
        .onDisappear { teardown() }        .sheet(isPresented: $episodeSheetShown) {
            episodeSheet.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $subtitleSheetShown) {
            SubtitleSheet(track: $subtitleTrack, offset: $subtitleOffset,
                          videoURL: vm.stream.url)
        }
        .sheet(isPresented: $optionsSheetShown) {
            PlayerOptionsSheet(vm: vm)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $castSheetShown) {
            CastSheet(stream: vm.stream,
                      title: "\(subject.displayName) \(currentEpisode.displayName)")
        }
        .alert("下载本集？", isPresented: $downloadPrompt) {
            Button("下载") { startDownload() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(currentEpisode.displayName) · \(vm.stream.quality)")
        }
    }

    // MARK: 生命周期

    private func bootstrap() {
        vm.danmakuEnabled = settings.danmakuEnabled
        let resume = settings.rememberPosition
            ? app.resumePosition(subjectID: subject.id, episodeID: currentEpisode.id)
            : 0
        vm.start(from: resume)
        scheduleHide()
        loadDanmaku()
        loadSidecarSubtitle()

        if settings.keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // 播完自动下一集
        let autoNext = settings.autoPlayNext
        vm.onPlaybackEnded = {
            guard autoNext else { return }
            guard let next = self.nextEpisode else {
                LuHUD.shared.show("已经是最后一集")
                return
            }
            LuHUD.shared.show("连播 \(next.displayName)")
            self.switchTo(next)
        }

        sync.positionProvider = { self.vm.position }
        sync.applyRemote = { message in
            // 房主也要应用观众的操作（房主权威：先落到本机，再广播状态）
            let session = SyncPlaySession.shared
            guard session.role != .none else { return }

            // 房主切集：观众自动跟到同一集（只认本番的 key）
            if session.role == .guest,
               let key = message.episodeKey, !key.isEmpty,
               let rawID = key.split(separator: "-").last,
               let episodeID = Int(rawID),
               episodeID != self.currentEpisode.id,
               let target = self.episodes.first(where: { $0.id == episodeID }) {
                self.switchTo(target)
                return
            }

            if let paused = message.paused {
                if paused, self.vm.isPlaying { self.vm.pause() }
                if !paused, !self.vm.isPlaying { self.vm.play() }
            }
            if let position = message.position, abs(position - self.vm.position) > 2.5 {
                self.vm.seek(to: position)
            }
        }
    }

    private func teardown() {
        persistProgress()
        vm.onPlaybackEnded = nil
        vm.teardown()
        hideTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        LuPiPController.shared.stop()
        sync.applyRemote = nil
        sync.positionProvider = nil
    }

    private var nextEpisode: AnimeEpisode? {
        guard let index = episodes.firstIndex(where: { $0.id == currentEpisode.id }),
              index + 1 < episodes.count else { return nil }
        return episodes[index + 1]
    }

    /// 片头还没跳过、且总时长足够时才显示按钮
    private var showsSkipIntro: Bool {
        let target = Double(settings.skipIntroSeconds)
        guard target > 3, vm.duration > target + 20 else { return false }
        return vm.position < target - 1
    }

    private func skipIntro() {
        let target = Double(settings.skipIntroSeconds)
        vm.seek(to: target)
        pushSeek(target)
        LuHUD.shared.show("已跳过片头")
    }

    private var subtitleFontSize: CGFloat {
        max(14, CGFloat(settings.danmakuFontSize) - 2)
    }

    // MARK: 手势层

    private func interactionLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragMode == .none {
                            if abs(value.translation.width) > 14 {
                                dragMode = .seek
                                scrubValue = vm.position
                            } else if abs(value.translation.height) > 14 {
                                dragMode = .brightness
                                startBrightness = UIScreen.main.brightness
                            }
                        }
                        switch dragMode {
                        case .seek:
                            let delta = Double(value.translation.width / max(width, 1)) * max(vm.duration, 60)
                            scrubValue = min(max(vm.position + delta, 0), max(vm.duration, 0))
                            overlayHint = timeText(scrubValue)
                        case .brightness:
                            let next = startBrightness - value.translation.height / 260
                            UIScreen.main.brightness = min(max(next, 0), 1)
                            overlayHint = "亮度 \(Int(UIScreen.main.brightness * 100))%"
                        case .none:
                            break
                        }
                    }
                    .onEnded { _ in
                        let wasTap = (dragMode == .none)
                        if dragMode == .seek {
                            vm.seek(to: scrubValue)
                            pushSeek(scrubValue)
                        }
                        dragMode = .none
                        withAnimation(LuTheme.quick) { overlayHint = nil }
                        if wasTap { toggleControls() }
                    }
            )
            // 长按 2x，松手恢复——对齐 Flutter 侧 speedLock 行为
            .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                if pressing {
                    vm.setRate(2)
                    overlayHint = "2x 倍速"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    vm.setRate(1)
                    withAnimation(LuTheme.quick) { overlayHint = nil }
                }
            }, perform: {})
    }

    // MARK: 控制层

    private func controlsLayer(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar

            Spacer()

            VStack(spacing: 10) {
                if vm.isBuffering && vm.position < 0.5 {
                    ProgressView().tint(.white).scaleEffect(0.9)
                }

                HStack(spacing: 10) {
                    Text(timeText(scrubbing ? scrubValue : vm.position))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 46, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { scrubbing ? scrubValue : vm.position },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(vm.duration, 1),
                        onEditingChanged: { editing in
                            if editing {
                                scrubbing = true
                                scrubValue = vm.position
                            } else {
                                vm.seek(to: scrubValue)
                                pushSeek(scrubValue)
                                scrubbing = false
                            }
                        }
                    )
                    .tint(LuTheme.accent)

                    Text(timeText(vm.duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 46, alignment: .trailing)
                }

                HStack(spacing: 28) {
                    Button { skip(-10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }

                    Button { togglePlay() } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                    }

                    Button { skip(10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }

                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                            Button {
                                vm.setRate(Float(value))
                            } label: {
                                if abs(vm.rate - Float(value)) < 0.01 {
                                    Label("\(value, specifier: "%g")x", systemImage: "checkmark")
                                } else {
                                    Text("\(value, specifier: "%g")x")
                                }
                            }
                        }
                    } label: {
                        Text("\(Double(vm.rate), specifier: "%g")x")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 42, minHeight: 30)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .background {
                LinearGradient(colors: [.clear, .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .offset(y: 20)
                    .allowsHitTesting(false)
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(subject.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(currentEpisode.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    if sync.role != .none {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(LuTheme.accent)
                        Text(sync.roomCode.isEmpty ? sync.role.title : sync.roomCode)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LuTheme.accent)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                vm.danmakuEnabled.toggle()
                LuHUD.shared.show(vm.danmakuEnabled ? "弹幕已开" : "弹幕已关")
            } label: {
                Image(systemName: vm.danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(vm.danmakuEnabled ? LuTheme.accent : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }

            Menu {
                Button {
                    subtitleSheetShown = true
                } label: {
                    Label(subtitleTrack == nil ? "加载字幕" : "字幕（已加载）",
                          systemImage: "captions.bubble")
                }
                Button {
                    optionsSheetShown = true
                } label: {
                    Label("播放设置（音轨 / 比例 / 增强）", systemImage: "slider.horizontal.3")
                }
                Button {
                    downloadPrompt = true
                } label: {
                    Label("下载本集", systemImage: "arrow.down.circle")
                }
                Button {
                    castSheetShown = true
                } label: {
                    Label("投屏到电视", systemImage: "airplayvideo")
                }
                if LuPiPController.shared.isAvailable {
                    Button {
                        LuPiPController.shared.toggle()
                    } label: {
                        Label(LuPiPController.shared.isActive ? "退出画中画" : "画中画",
                              systemImage: "pip.enter")
                    }
                }
                Button {
                    captureFrame()
                } label: {
                    Label("保存当前画面", systemImage: "camera")
                }
                if episodes.count > 1 {
                    Button {
                        episodeSheetShown = true
                    } label: {
                        Label("选集", systemImage: "list.bullet")
                    }
                }
                Divider()
                Button {
                    if sync.role == .none {
                        LuHUD.shared.show("先到「一起看」页开房或加入")
                    } else {
                        LuHUD.shared.show("\(sync.role.title) · \(sync.roomCode) · \(sync.members) 人")
                    }
                } label: {
                    Label(sync.role == .none ? "一起看未开启" : "一起看 \(sync.roomCode)",
                          systemImage: "person.2")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 选集

    private var episodeSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        Button {
                            episodeSheetShown = false
                            switchTo(episode)
                        } label: {
                            HStack {
                                Text(episode.displayName)
                                    .font(.system(size: 15))
                                    .foregroundStyle(LuTheme.label)
                                    .lineLimit(1)
                                Spacer()
                                if episode.id == currentEpisode.id {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(LuTheme.accent)
                                        .font(.system(size: 13))
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 16)
                    }
                }
            }
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { episodeSheetShown = false }
                }
            }
        }
    }

    private func switchTo(_ episode: AnimeEpisode) {
        guard episode.id != currentEpisode.id else { return }
        isSwitching = true
        Task { @MainActor in
            defer { isSwitching = false }
            if let stream = await resolveStream(episode) {
                currentEpisode = episode
                vm.switchStream(stream)
                subtitleTrack = nil
                subtitleOffset = 0
                loadDanmaku()
                sync.pushEpisode("\(subject.id)-\(episode.id)")
                LuHUD.shared.show("已切换到 \(episode.displayName)")
            } else {
                LuHUD.shared.show("这一集解析失败")
            }
        }
    }

    // MARK: 动作

    private func togglePlay() {
        vm.togglePlay()
        if vm.isPlaying {
            sync.pushPlay(position: vm.position, episodeKey: "\(subject.id)-\(currentEpisode.id)")
        } else {
            sync.pushPause(position: vm.position, episodeKey: "\(subject.id)-\(currentEpisode.id)")
        }
        scheduleHide()
    }

    private func skip(_ delta: Double) {
        vm.skip(delta)
        pushSeek(vm.position)
    }

    private func pushSeek(_ position: Double) {
        sync.pushSeek(position: position, paused: !vm.isPlaying,
                      episodeKey: "\(subject.id)-\(currentEpisode.id)")
    }

    private func startDownload() {
        DownloadManager.shared.enqueue(stream: vm.stream,
                                       subjectID: subject.id,
                                       subjectName: subject.displayName,
                                       episodeID: currentEpisode.id,
                                       episodeName: currentEpisode.displayName)
        LuHUD.shared.show("已加入下载队列")
    }

    private func captureFrame() {
        guard let image = vm.snapshot() else {
            LuHUD.shared.show("这一帧还没解出来，稍等再试")
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        LuHUD.shared.show("截图已保存到相册")
        luLogInfo("Player", "截图 \(Int(image.size.width))x\(Int(image.size.height))")
    }

    private func loadSidecarSubtitle() {
        guard subtitleTrack == nil, vm.stream.url.isFileURL else { return }
        guard let sidecar = SubtitleParser.sidecarURL(for: vm.stream.url),
              let data = try? Data(contentsOf: sidecar) else { return }
        subtitleTrack = SubtitleParser.parse(data: data, url: sidecar)
    }

    private func loadDanmaku() {
        guard settings.danmakuEnabled,
              settings.danmakuSource != DanmakuSourceKind.off.rawValue else { return }
        let query = DanmakuQuery(
            title: subject.displayName,
            originalTitle: subject.originalName,
            bangumiID: subject.id,
            episode: currentEpisode.sort,
            episodeTitle: currentEpisode.nameCN.isEmpty ? currentEpisode.name : currentEpisode.nameCN
        )
        Task { await vm.loadDanmaku(query: query) }
    }

    private func persistProgress() {
        guard settings.rememberPosition, vm.duration > 0 else { return }
        app.recordPlayback(subject: subject, episode: currentEpisode,
                           position: vm.position, duration: vm.duration)
    }

    private func toggleControls() {
        withAnimation(LuTheme.quick) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(LuTheme.quick) { controlsVisible = false }
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
