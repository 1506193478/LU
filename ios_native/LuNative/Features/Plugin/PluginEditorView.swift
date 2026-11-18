import SwiftUI
import UIKit

/// 插件可视化编辑器：所有规则可视化改写，改完可以直接跑一次搜索验证。
struct PluginEditorView: View {
    @EnvironmentObject private var store: PluginStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PluginManifest
    @State private var testing = false
    @State private var testKeyword = ""
    @State private var testResult: String?
    @State private var testItems: [PluginSearchItem] = []

    private let isNew: Bool

    init(plugin: PluginManifest?) {
        if let plugin {
            _draft = State(initialValue: plugin)
            isNew = false
        } else {
            _draft = State(initialValue: PluginManifest(
                name: "",
                baseURL: "",
                searchURL: "/search?q=@keyword",
                searchList: "",
                searchName: "",
                searchResult: "",
                chapterRoads: "",
                chapterResult: ""
            ))
            isNew = true
        }
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    field("名称", text: $draft.name, placeholder: "例如 动漫花园")
                    field("作者", text: $draft.author, placeholder: "可选")
                    field("版本", text: $draft.version, placeholder: "1.0")
                } header: {
                    Text("基本信息")
                }

                Section {
                    Picker("搜索规则", selection: $draft.searchMode) {
                        Text("XPath（抓网页）").tag("xpath")
                        Text("API（抓接口）").tag("api")
                    }
                    Picker("剧集规则", selection: $draft.chapterMode) {
                        Text("XPath（抓网页）").tag("xpath")
                        Text("API（抓接口）").tag("api")
                    }
                    Toggle("搜索用 POST 提交", isOn: $draft.usePost)
                } header: {
                    Text("规则类型")
                } footer: {
                    Text("API 模式直接请求 JSON 接口并用 JSONPath 取值，适合新版插件格式；XPath 模式抓 HTML 页面。")
                }

                if draft.searchMode == "xpath" {
                    Section {
                        field("站点根地址", text: $draft.baseURL,
                              placeholder: "https://example.com", keyboard: .URL)
                        field("搜索地址", text: $draft.searchURL,
                              placeholder: "/search?q=@keyword", keyboard: .URL)
                        field("User-Agent", text: uaBinding, placeholder: "可选")
                        field("Referer", text: refererBinding, placeholder: "可选")
                    } header: {
                        Text("请求")
                    } footer: {
                        Text("`@keyword` 会被替换成搜索词。留空 UA / Referer 时使用全局 UA。")
                    }

                    Section {
                        field("搜索结果列表", text: $draft.searchList, xpath: true)
                        field("条目名称", text: $draft.searchName, xpath: true)
                        field("条目链接", text: $draft.searchResult, xpath: true)
                        field("线路分组", text: $draft.chapterRoads, xpath: true)
                        field("剧集节点", text: $draft.chapterResult, xpath: true)
                    } header: {
                        Text("XPath 规则")
                    } footer: {
                        Text("列表类规则用绝对/相对 XPath；名称与链接取相对节点。剧集节点的 href 会被用作播放页地址。")
                    }
                } else {
                    Section {
                        field("站点根地址", text: $draft.baseURL,
                              placeholder: "https://example.com", keyboard: .URL)
                        Picker("请求方法", selection: searchConfig.request.method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                        }
                        field("搜索接口地址", text: searchConfig.request.url,
                              placeholder: "/api/search?wd=@keyword", keyboard: .URL)
                        field("请求体类型", text: searchConfig.request.bodyType,
                              placeholder: "none / json / form")
                    } header: {
                        Text("搜索接口")
                    } footer: {
                        Text("地址和请求体里都可以用 `@keyword`，会被自动转义。")
                    }

                    Section {
                        field("结果列表", text: searchConfig.listPath, xpath: true)
                        field("条目名称", text: searchConfig.namePath, xpath: true)
                        field("条目来源", text: searchConfig.sourcePath, xpath: true)
                        field("详情页模板", text: searchConfig.sourceTemplate, xpath: true)
                    } header: {
                        Text("搜索 JSONPath")
                    } footer: {
                        Text("只支持 `$.a.b`、`$.list[*]`、`$.list[0]`、`$['a-b']` 这类子集。详情页模板里用 `@source` 引用条目来源。")
                    }

                    Section {
                        Picker("章节格式", selection: chapterConfig.format) {
                            Text("嵌套 JSON").tag("nested")
                            Text("分隔符字符串").tag("delimited")
                        }
                        field("章节接口地址", text: chapterConfig.request.url,
                              placeholder: "/api/detail?url=@source", keyboard: .URL)
                    } header: {
                        Text("剧集接口")
                    } footer: {
                        Text("`@source` 是上一步得到的详情页地址。")
                    }

                    if chapterConfig.format.wrappedValue == "nested" {
                        Section {
                            field("线路列表", text: chapterConfig.roadsPath, xpath: true)
                            field("线路名称", text: chapterConfig.roadNamePath, xpath: true)
                            field("剧集列表", text: chapterConfig.episodesPath, xpath: true)
                            field("剧集名称", text: chapterConfig.episodeNamePath, xpath: true)
                            field("剧集地址", text: chapterConfig.episodeUrlPath, xpath: true)
                        } header: {
                            Text("剧集 JSONPath")
                        }
                    } else {
                        Section {
                            field("线路名称", text: chapterConfig.roadNamesPath, xpath: true)
                            field("剧集字段", text: chapterConfig.roadEpisodesPath, xpath: true)
                            field("线路分隔符", text: chapterConfig.roadSeparator)
                            field("剧集分隔符", text: chapterConfig.episodeSeparator)
                            field("字段分隔符", text: chapterConfig.fieldSeparator)
                        } header: {
                            Text("分隔符规则")
                        } footer: {
                            Text("剧集字段形如 `第1集$url1#第2集$url2`，先按剧集分隔符切集，再按字段分隔符切名称与地址。")
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("搜索关键词", text: $testKeyword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await runTest() }
                        } label: {
                            if testing {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("测试").font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .disabled(testing || draft.baseURL.isEmpty)
                    }

                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(testResult.hasPrefix("✅") ? .green : .red)
                    }
                    ForEach(testItems.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 13)).lineLimit(1)
                            Text(item.url.absoluteString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(LuTheme.tertiary)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text("验证")
                } footer: {
                    Text("测试会按当前填写的规则真实请求一次站点，用来确认 XPath 是否命中。")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            store.remove(id: draft.id)
                            dismiss()
                        } label: {
                            Text("删除这个源")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(isNew ? "新建源" : "编辑源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.name.isEmpty || draft.baseURL.isEmpty)
                }
            }
        }
    }

    // MARK: 绑定（可选字段的 String? → String）

    private var uaBinding: Binding<String> {
        Binding(get: { draft.userAgent ?? "" },
                set: { draft.userAgent = $0.isEmpty ? nil : $0 })
    }

    private var refererBinding: Binding<String> {
        Binding(get: { draft.referer ?? "" },
                set: { draft.referer = $0.isEmpty ? nil : $0 })
    }

    private var searchConfig: Binding<LuApiSearchConfig> {
        Binding(get: { draft.searchApi ?? LuApiSearchConfig() },
                set: { draft.searchApi = $0 })
    }

    private var chapterConfig: Binding<LuApiChapterConfig> {
        Binding(get: { draft.chapterApi ?? LuApiChapterConfig() },
                set: { draft.chapterApi = $0 })
    }

    // MARK: 控件

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, placeholder: String = "",
                       keyboard: UIKeyboardType = .default, xpath: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(LuTheme.secondary)
            TextField(placeholder, text: text)
                .font(.system(size: 13, design: xpath ? .monospaced : .default))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
        }
        .padding(.vertical, 2)
    }

    // MARK: 动作

    private func save() {
        var manifest = draft
        if manifest.id.isEmpty { manifest.id = UUID().uuidString }
        if manifest.searchMode == "api", manifest.searchApi == nil {
            manifest.searchApi = LuApiSearchConfig()
        }
        if manifest.chapterMode == "api", manifest.chapterApi == nil {
            manifest.chapterApi = LuApiChapterConfig()
        }
        // API 模式的规则先自校验一遍，避免存进仓库后才在播放时炸
        do {
            if manifest.searchMode == "api" { try manifest.searchApi?.validate() }
            if manifest.chapterMode == "api" { try manifest.chapterApi?.validate() }
        } catch {
            testResult = "❌ \(error.localizedDescription)"
            return
        }
        store.save(manifest)
        draft = manifest
        LuHUD.shared.show("已保存")
        dismiss()
    }

    @MainActor
    private func runTest() async {
        guard !testKeyword.isEmpty else {
            testResult = "先填一个关键词"
            return
        }
        testing = true
        testResult = nil
        testItems = []
        do {
            let items = try await PluginEngine.shared.search(plugin: draft, keyword: testKeyword)
            testItems = items
            testResult = items.isEmpty
                ? "❌ 没有命中，检查搜索列表/名称/链接规则"
                : "✅ 命中 \(items.count) 条"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
        testing = false
    }
}
