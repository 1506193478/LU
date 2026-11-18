import SwiftUI

/// 播放设置：内嵌音轨 / 内嵌字幕 / 画面比例 / 画质增强。
/// 走 `AVMediaSelectionGroup`，只影响当前 item，不动全局设置（增强与比例会写回设置）。
struct PlayerOptionsSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private struct ModeOption: Identifiable {
        let id: String
        let title: String
        var detail: String = ""
    }

    private let aspectModes: [ModeOption] = [
        ModeOption(id: "fit", title: "适应"),
        ModeOption(id: "fill", title: "填充"),
        ModeOption(id: "stretch", title: "拉伸")
    ]
    private let enhanceModes: [ModeOption] = [
        ModeOption(id: "off", title: "关闭", detail: "原画直通，保留 HDR"),
        ModeOption(id: "sharpen", title: "锐化", detail: "提亮边缘，适合低码率"),
        ModeOption(id: "vivid", title: "鲜艳", detail: "提高饱和度与对比"),
        ModeOption(id: "soft", title: "降噪", detail: "压制噪点，适合老番")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    trackSection
                    aspectSection
                    enhanceSection
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.vertical, 16)
            }
            .background(LuTheme.canvas.ignoresSafeArea())
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { vm.refreshMediaOptions() }
        }
    }

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("音轨")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)

            if vm.audioTracks.isEmpty {
                hint("这条视频只有一条音轨，或元数据还没读出来")
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.audioTracks) { track in
                        row(title: track.name, selected: track.isSelected) {
                            vm.selectAudio(track.id)
                        }
                        if track.id != vm.audioTracks.last?.id {
                            Rectangle().fill(LuTheme.hairline).frame(height: 0.5)
                        }
                    }
                }
                .luGlass(.thin, cornerRadius: 12)
            }

            Text("内嵌字幕")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)
                .padding(.top, 6)

            if vm.subtitleTracks.isEmpty {
                hint("这条视频没有内嵌字幕轨；外挂字幕在播放器菜单「字幕」里加载")
            } else {
                VStack(spacing: 0) {
                    row(title: "关闭", selected: !vm.subtitleTracks.contains(where: \.isSelected)) {
                        vm.selectEmbeddedSubtitle(-1)
                    }
                    ForEach(vm.subtitleTracks) { track in
                        Rectangle().fill(LuTheme.hairline).frame(height: 0.5)
                        row(title: track.name, selected: track.isSelected) {
                            vm.selectEmbeddedSubtitle(track.id)
                        }
                    }
                }
                .luGlass(.thin, cornerRadius: 12)
            }
        }
    }

    private var aspectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("画面比例")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            Picker("画面比例", selection: $settings.aspectMode) {
                ForEach(aspectModes, id: \.id) { mode in
                    Text(mode.title).tag(mode.id)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.aspectMode) { value in
                vm.videoGravity = PlayerViewModel.gravity(for: value)
            }
            hint("「填充」会裁掉边缘，「拉伸」会变形；默认「适应」保留黑边。")
        }
    }

    private var enhanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("画质增强")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            VStack(spacing: 0) {
                ForEach(enhanceModes, id: \.id) { mode in
                    Button {
                        settings.videoEnhance = mode.id
                        vm.applyEnhance(mode.id)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(LuTheme.label)
                                Text(mode.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(LuTheme.tertiary)
                            }
                            Spacer()
                            if settings.videoEnhance == mode.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(LuTheme.accent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if mode.id != enhanceModes.last?.id {
                        Rectangle().fill(LuTheme.hairline)
                            .frame(height: 0.5).padding(.leading, 12)
                    }
                }
            }
            .luGlass(.thin, cornerRadius: 12)
            hint("增强走 Core Image 逐帧处理，会关闭 HDR 与部分硬件直通，发热与耗电会上升。")
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(LuTheme.label)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LuTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(LuTheme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
