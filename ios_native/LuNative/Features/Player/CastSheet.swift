import SwiftUI

/// DLNA 投屏面板。扫描局域网里的 MediaRenderer，选中后把当前流推过去。
struct CastSheet: View {
    let stream: PlayStream
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var devices: [DLNADevice] = []
    @State private var isScanning = false
    @State private var castingDevice: DLNADevice?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(LuTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LuTheme.label)
                                .lineLimit(1)
                            Text(stream.url.absoluteString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(LuTheme.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .luGlass(.thin, cornerRadius: 12)

                    HStack {
                        Text("附近的播放器")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LuTheme.secondary)
                        Spacer()
                        Button {
                            Task { await scan() }
                        } label: {
                            HStack(spacing: 4) {
                                if isScanning { ProgressView().scaleEffect(0.6) }
                                Text(isScanning ? "扫描中" : "重新扫描")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(LuTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isScanning)
                    }

                    if devices.isEmpty && !isScanning {
                        LuEmptyState(symbol: "airplayvideo",
                                     title: "没有发现设备",
                                     message: "确认电视与手机在同一 Wi-Fi，且电视支持 DLNA 投屏")
                    } else {
                        LuGroup {
                            ForEach(devices.indices, id: \.self) { index in
                                let device = devices[index]
                                Button {
                                    Task { await cast(to: device) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "tv")
                                            .font(.system(size: 15))
                                            .foregroundStyle(LuTheme.accent)
                                            .frame(width: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                                .font(.system(size: 15))
                                                .foregroundStyle(LuTheme.label)
                                                .lineLimit(1)
                                            Text(device.modelName.isEmpty ? "DLNA 播放器" : device.modelName)
                                                .font(.system(size: 11))
                                                .foregroundStyle(LuTheme.tertiary)
                                        }
                                        Spacer()
                                        if castingDevice?.id == device.id {
                                            Text("投屏中")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.green)
                                        } else if busy {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(LuTheme.tertiary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 54)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < devices.count - 1 {
                                    Rectangle().fill(LuTheme.hairline)
                                        .frame(height: 0.5).padding(.leading, 50)
                                }
                            }
                        }
                    }

                    if let castingDevice {
                        LuGroup(title: "正在投屏") {
                            HStack(spacing: 18) {
                                control("播放") { try await DLNAController.shared.play(device: castingDevice) }
                                control("暂停") { try await DLNAController.shared.pause(device: castingDevice) }
                                control("停止") {
                                    try await DLNAController.shared.stop(device: castingDevice)
                                    self.castingDevice = nil
                                }
                            }
                            .padding(12)
                        }
                    }

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }

                    Text("投屏是把视频地址交给电视自己拉流，手机不能锁屏休眠。部分电视不支持带 Referer 的直链，遇到黑屏可以换一个源。")
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                        .lineSpacing(3)
                }
                .padding(16)
            }
            .navigationTitle("投屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await scan() }
        }
    }

    private func control(_ title: String, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                do {
                    try await action()
                    LuHUD.shared.show("\(title)已发送")
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LuTheme.label)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Color(uiColor: .tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func scan() async {
        isScanning = true
        error = nil
        devices = await DLNADiscovery.shared.discover(timeout: 3)
        isScanning = false
    }

    @MainActor
    private func cast(to device: DLNADevice) async {
        busy = true
        error = nil
        do {
            try await DLNAController.shared.cast(device: device, stream: stream, title: title)
            castingDevice = device
            LuHUD.shared.show("已投到 \(device.name)")
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
