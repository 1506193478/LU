import SwiftUI
import UniformTypeIdentifiers

struct PluginListView: View {
    @EnvironmentObject private var store: PluginStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImport = false
    @State private var importText = ""
    @State private var importError: String?
    @State private var showFileImporter = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LuPageHeader(title: "播放源插件", subtitle: "\(store.enabledPlugins.count) 个启用") {
                        HStack(spacing: 8) {
                            NavigationLink(value: Route.pluginEditor(id: nil)) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(LuTheme.label)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(.ultraThinMaterial))
                                    .overlay(Circle().strokeBorder(LuTheme.hairline, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            LuIconButton(symbol: "plus") { showImport = true }
                        }
                    }

                    if store.plugins.isEmpty {
                        LuEmptyState(symbol: "puzzlepiece.extension",
                                     title: "还没有插件",
                                     message: "点右上角 + 粘贴 Kazumi 格式的插件 JSON")
                    } else {
                        LuGroup {
                            ForEach(store.plugins.indices, id: \.self) { index in
                                let plugin = store.plugins[index]
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(plugin.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(LuTheme.label)
                                        Text("v\(plugin.version) · \(host(plugin.baseURL))")
                                            .font(.system(size: 11))
                                            .foregroundStyle(LuTheme.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { plugin.enabled },
                                        set: { _ in store.toggle(id: plugin.id) }
                                    ))
                                    .labelsHidden()
                                    .tint(LuTheme.accent)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 56)

                                if index < store.plugins.count - 1 {
                                    Rectangle().fill(LuTheme.hairline)
                                        .frame(height: 0.5).padding(.leading, 12)
                                }
                            }
                        }

                        Text("插件规则使用 XPath 提取。导入后可在详情页直接搜源播放。")
                            .font(.system(size: 12))
                            .foregroundStyle(LuTheme.tertiary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)

            VStack {
                HStack {
                    LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
        .sheet(isPresented: $showImport) { importSheet }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("粘贴插件 JSON（Kazumi 格式）")
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)

                TextEditor(text: $importText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .tertiarySystemFill)))
                    .frame(minHeight: 240)

                if let importError {
                    Text(importError)
                        .font(LuTheme.caption())
                        .foregroundStyle(.red)
                }

                Button {
                    do {
                        try store.importJSON(importText)
                        importText = ""
                        importError = nil
                        showImport = false
                        LuHUD.shared.show("插件已导入")
                    } catch {
                        importError = error.localizedDescription
                    }
                } label: {
                    Text("导入")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(importText.isEmpty ? Color.gray : LuTheme.accent))
                }
                .disabled(importText.isEmpty)

                Button {
                    showFileImporter = true
                } label: {
                    Text("从文件导入 JSON")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LuTheme.accent)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("导入插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showImport = false }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.json, .text]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        importError = "读取文件失败"
                        return
                    }
                    do {
                        try store.importJSON(text)
                        importError = nil
                        showImport = false
                        LuHUD.shared.show("插件已导入")
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func host(_ raw: String) -> String {
        URL(string: raw)?.host ?? raw
    }
}

struct PluginDetailView: View {
    let pluginID: String
    @EnvironmentObject private var store: PluginStore
    @Environment(\.dismiss) private var dismiss

    private var plugin: PluginManifest? {
        store.plugins.first { $0.id == pluginID }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LuPageHeader(title: plugin?.name ?? "插件")

                    if let plugin {
                        LuGroup(title: "信息") {
                            LuListRow(title: "版本", value: plugin.version).padding(.horizontal, 12)
                            line
                            LuListRow(title: "作者", value: plugin.author.isEmpty ? "—" : plugin.author)
                                .padding(.horizontal, 12)
                            line
                            LuListRow(title: "站点", value: plugin.baseURL).padding(.horizontal, 12)
                        }

                        LuGroup(title: "规则") {
                            ruleRow("搜索列表", plugin.searchList)
                            line
                            ruleRow("名称", plugin.searchName)
                            line
                            ruleRow("链接", plugin.searchResult)
                            line
                            ruleRow("线路", plugin.chapterRoads)
                            line
                            ruleRow("剧集", plugin.chapterResult)
                        }

                        NavigationLink(value: Route.pluginEditor(id: plugin.id)) {
                            Text("编辑规则")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12).fill(LuTheme.accent))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.remove(id: plugin.id)
                            dismiss()
                        } label: {
                            Text("删除插件")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .luGlass(.thin, cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)

            VStack {
                HStack {
                    LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
    }

    private var line: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 12)
    }

    private func ruleRow(_ title: String, _ xpath: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(LuTheme.label)
            Text(xpath.isEmpty ? "—" : xpath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LuTheme.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
