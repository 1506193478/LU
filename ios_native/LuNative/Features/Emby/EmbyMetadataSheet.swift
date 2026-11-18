import SwiftUI

/// Emby 元数据修正（路线 A：走服务端 RemoteSearch / Apply，不把 TMDB Key 放进客户端）。
struct EmbyMetadataSheet: View {
    let item: EmbyItem

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var keyword: String
    @State private var year: String
    @State private var results: [EmbyRemoteResult] = []
    @State private var isLoading = false
    @State private var applyingID: String?
    @State private var error: String?
    @State private var applied = false

    init(item: EmbyItem) {
        self.item = item
        _keyword = State(initialValue: item.seriesName ?? item.name)
        _year = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LuGroup(title: "搜索词") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("名称", text: $keyword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 14))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(uiColor: .tertiarySystemFill)))
                            HStack {
                                TextField("年份（可选）", text: $year)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 14))
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 9)
                                        .fill(Color(uiColor: .tertiarySystemFill)))
                                Button {
                                    Task { await search() }
                                } label: {
                                    Text(isLoading ? "搜索中…" : "搜索")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 84, height: 42)
                                        .background(RoundedRectangle(cornerRadius: 9)
                                            .fill(keyword.isEmpty ? Color.gray : LuTheme.accent))
                                }
                                .buttonStyle(.plain)
                                .disabled(keyword.isEmpty || isLoading)
                            }
                            Text("由 Emby 服务端去 TMDB 搜索。返回结果点一下就会替换条目元数据与图片。")
                                .font(.system(size: 11))
                                .foregroundStyle(LuTheme.tertiary)
                        }
                        .padding(12)
                    }

                    if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    }

                    if applied {
                        Text("已应用，返回媒体库下拉刷新即可看到新封面。")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }

                    if !results.isEmpty {
                        LuGroup(title: "结果（\(results.count)）") {
                            ForEach(results.indices, id: \.self) { index in
                                let result = results[index]
                                Button {
                                    Task { await apply(result) }
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        LuRemoteImage(url: result.imageURL)
                                            .frame(width: 58, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(result.name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(LuTheme.label)
                                                    .lineLimit(1)
                                                if let year = result.year {
                                                    Text(String(year))
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(LuTheme.tertiary)
                                                }
                                            }
                                            Text(result.overview.isEmpty ? "无简介" : result.overview)
                                                .font(.system(size: 11))
                                                .foregroundStyle(LuTheme.secondary)
                                                .lineLimit(3)
                                        }
                                        Spacer(minLength: 4)
                                        if applyingID == result.id {
                                            ProgressView().scaleEffect(0.7)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < results.count - 1 {
                                    Rectangle().fill(LuTheme.hairline)
                                        .frame(height: 0.5).padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("修正元数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func search() async {
        guard let session = settings.embySession else { return }
        isLoading = true
        error = nil
        do {
            results = try await EmbyAPI.shared.remoteSearch(session: session, item: item,
                                                            name: keyword,
                                                            year: Int(year))
            if results.isEmpty { error = "没有搜到结果，换个名字试试" }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func apply(_ result: EmbyRemoteResult) async {
        guard let session = settings.embySession else { return }
        applyingID = result.id
        error = nil
        do {
            try await EmbyAPI.shared.applyRemoteResult(session: session, item: item,
                                                       payload: result.payload)
            applied = true
            LuHUD.shared.show("元数据已更新")
        } catch {
            self.error = error.localizedDescription
        }
        applyingID = nil
    }
}
