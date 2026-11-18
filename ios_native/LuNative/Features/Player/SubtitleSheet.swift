import SwiftUI
import UniformTypeIdentifiers

/// 外挂字幕面板：从 URL 加载、从文件导入、调时间轴偏移。
struct SubtitleSheet: View {
    @Binding var track: SubtitleTrack?
    @Binding var offset: Double
    var videoURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let track {
                        LuGroup(title: "当前字幕") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(LuTheme.label)
                                Text("\(track.cues.count) 条 · \(track.url.lastPathComponent)")
                                    .font(LuTheme.caption())
                                    .foregroundStyle(LuTheme.secondary)
                                    .lineLimit(1)
                                if let first = track.cues.first {
                                    Text("首条：\(first.text.replacingOccurrences(of: "\n", with: " "))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(LuTheme.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("时间轴偏移")
                                    .font(.system(size: 15))
                                    .foregroundStyle(LuTheme.label)
                                Spacer()
                                Text(String(format: "%+.1f s", offset))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(abs(offset) < 0.05 ? LuTheme.secondary : LuTheme.accent)
                            }
                            Slider(value: $offset, in: -30...30, step: 0.1)
                                .tint(LuTheme.accent)
                            HStack(spacing: 10) {
                                Button("归零") { offset = 0 }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LuTheme.accent)
                                Button("-0.5s") { offset -= 0.5 }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(LuTheme.label)
                                Button("+0.5s") { offset += 0.5 }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(LuTheme.label)
                            }
                        }
                        .padding(12)
                        .luGlass(.thin, cornerRadius: 12)

                        Button {
                            track = nil
                            offset = 0
                            LuHUD.shared.show("已关闭字幕")
                        } label: {
                            Text("关闭字幕")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .luGlass(.thin, cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }

                    LuGroup(title: "加载字幕") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("https://…/subtitle.srt", text: $urlText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(uiColor: .tertiarySystemFill)))

                            HStack(spacing: 10) {
                                Button {
                                    Task { await loadFromURL() }
                                } label: {
                                    Text(isLoading ? "加载中…" : "从链接加载")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(urlText.isEmpty ? Color.gray : LuTheme.accent))
                                }
                                .buttonStyle(.plain)
                                .disabled(urlText.isEmpty || isLoading)

                                Button {
                                    showImporter = true
                                } label: {
                                    Text("选文件")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(LuTheme.label)
                                        .frame(width: 92, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(LuTheme.hairline, lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }

                            if let error {
                                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                            }
                            Text("支持 SRT / ASS / SSA / WebVTT，GB18030 编码会自动识别。")
                                .font(.system(size: 11))
                                .foregroundStyle(LuTheme.tertiary)
                        }
                        .padding(12)
                    }
                }
                .padding(16)
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: subtitleTypes) { result in
                handleImport(result)
            }
        }
    }

    private var subtitleTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for ext in ["srt", "ass", "ssa", "vtt"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    @MainActor
    private func loadFromURL() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else {
            error = "地址无效"
            return
        }
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: url)
            request.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let parsed = SubtitleParser.parse(data: data, url: url) else {
                throw SubtitleLoadError.empty
            }
            track = parsed
            LuHUD.shared.show("字幕已加载：\(parsed.cues.count) 条")
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let parsed = SubtitleParser.parse(data: data, url: url) else {
                error = "解析字幕失败"
                return
            }
            track = parsed
            error = nil
            LuHUD.shared.show("字幕已加载：\(parsed.cues.count) 条")
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }
}

enum SubtitleLoadError: LocalizedError {
    case empty
    var errorDescription: String? { "没有解析到字幕内容" }
}

/// 字幕叠加层：只显示当前时间轴上的那一条，底部居中。
struct SubtitleOverlay: View {
    let cue: SubtitleCue?
    var fontSize: CGFloat = 18

    var body: some View {
        VStack {
            Spacer()
            if let cue {
                Text(cue.text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: cue?.id)
    }
}
