import SwiftUI

/// 网络诊断：把关键链路的可达性一次跑完，结果写进日志并展示。
/// 对照 Flutter 侧 4.1.2 的 `hg_diag.dart`，这里只保留通用部分
/// （Bangumi / B 站弹幕 / GitHub / 首个插件的站点）。
enum LuDiagnostics {

    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let ok: Bool
        let detail: String
    }

    static func run() async -> [Item] {
        var results: [Item] = []

        results.append(await probe(name: "Bangumi API",
                                   url: "https://api.bgm.tv/calendar"))

        let bilibili = (try? await BilibiliDanmaku.shared.searchSeasons("孤独摇滚")) ?? []
        results.append(Item(name: "B 站弹幕搜索",
                            ok: !bilibili.isEmpty,
                            detail: bilibili.isEmpty ? "没有结果（可能被风控）"
                                : "命中 \(bilibili.count) 个季度"))

        results.append(await probe(name: "GitHub Releases",
                                   url: "https://api.github.com/repos/1506193478/LU/releases?per_page=1"))

        if let plugin = PluginStore.shared.enabledPlugins.first,
           let url = URL(string: plugin.baseURL) {
            results.append(await probe(name: "插件站点 \(plugin.name)", url: url.absoluteString))
        } else {
            results.append(Item(name: "插件站点", ok: false, detail: "没有启用的插件"))
        }

        if !AppSettings.shared.webdavURL.isEmpty,
           let client = WebDAVClient.fromSettings(AppSettings.shared) {
            do {
                let entries = try await client.list("/")
                results.append(Item(name: "WebDAV", ok: true, detail: "根目录 \(entries.count) 项"))
            } catch {
                results.append(Item(name: "WebDAV", ok: false, detail: error.localizedDescription))
            }
        }

        for item in results {
            let line = "\(item.ok ? "OK" : "FAIL") · \(item.name) · \(item.detail)"
            if item.ok {
                luLogInfo("Diag", line)
            } else {
                luLogWarn("Diag", line)
            }
        }
        return results
    }

    private static func probe(name: String, url: String) async -> Item {
        guard let target = URL(string: url) else {
            return Item(name: name, ok: false, detail: "地址无效")
        }
        let start = Date()
        do {
            var request = URLRequest(url: target)
            request.timeoutInterval = 12
            request.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let cost = Int(Date().timeIntervalSince(start) * 1000)
            return Item(name: name, ok: (200..<400).contains(code),
                        detail: "HTTP \(code) · \(cost)ms")
        } catch {
            return Item(name: name, ok: false, detail: error.localizedDescription)
        }
    }
}

struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [LuDiagnostics.Item] = []
    @State private var running = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if running {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在逐项探测…")
                                .font(LuTheme.caption())
                                .foregroundStyle(LuTheme.secondary)
                        }
                        .padding(.vertical, 16)
                    }

                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(item.ok ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(LuTheme.label)
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(LuTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .luGlass(.thin, cornerRadius: 10)
                    }

                    Text("结果同时写入了运行日志，排查时可以直接导出。")
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .navigationTitle("网络诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                items = await LuDiagnostics.run()
                running = false
            }
        }
    }
}
