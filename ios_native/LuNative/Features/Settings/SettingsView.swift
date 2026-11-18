import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDandanSheet = false
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LuPageHeader(title: "设置")

                    // 外观
                    LuGroup(title: "外观") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("主题").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Picker("主题", selection: $settings.appearance) {
                                ForEach(AppAppearance.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(12)
                        line
                        VStack(alignment: .leading, spacing: 10) {
                            Text("强调色").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            HStack(spacing: 12) {
                                ForEach(LuAccent.allCases) { accent in
                                    Button {
                                        settings.accent = accent.rawValue
                                        LuHUD.shared.show("强调色：\(accent.title)")
                                    } label: {
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 28, height: 28)
                                            .overlay {
                                                if settings.accent == accent.rawValue {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                        }
                        .padding(12)
                        line
                        VStack(alignment: .leading, spacing: 8) {
                            Text("底栏显示").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            ForEach(tabItems, id: \.id) { item in
                                Toggle(item.title, isOn: tabBinding(item.id))
                                    .font(.system(size: 14))
                                    .tint(LuTheme.accent)
                            }
                        }
                        .padding(12)
                    }

                    // 通知
                    LuGroup(title: "通知") {
                        rowToggle("追番更新提醒", isOn: reminderBinding)
                        line
                        Text("按收藏里每部番的更新星期，在当天 20:00 发本地通知。")
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }

                    // 播放
                    LuGroup(title: "播放") {
                        rowToggle("自动连播下一集", isOn: $settings.autoPlayNext)
                        line
                        rowToggle("记住播放进度", isOn: $settings.rememberPosition)
                        line
                        rowToggle("播放时禁止锁屏", isOn: $settings.keepScreenOn)
                        line
                        HStack {
                            Text("跳过片头").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Spacer()
                            Picker("跳过片头", selection: $settings.skipIntroSeconds) {
                                Text("关闭").tag(0)
                                Text("30 秒").tag(30)
                                Text("60 秒").tag(60)
                                Text("90 秒").tag(90)
                                Text("120 秒").tag(120)
                            }
                            .pickerStyle(.menu)
                            .tint(LuTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: LuTheme.rowHeight)
                        line
                        HStack {
                            Text("优先清晰度").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Spacer()
                            Picker("清晰度", selection: $settings.preferredQuality) {
                                Text("1080p").tag("1080p")
                                Text("720p").tag("720p")
                                Text("自动").tag("自动")
                            }
                            .pickerStyle(.menu)
                            .tint(LuTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: LuTheme.rowHeight)
                    }

                    // 一起看
                    LuGroup(title: "一起看") {
                        HStack {
                            Text("我的昵称").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Spacer()
                            TextField("昵称", text: $settings.syncPlayName)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15))
                                .foregroundStyle(LuTheme.secondary)
                                .frame(maxWidth: 160)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: LuTheme.rowHeight)
                        line
                        VStack(alignment: .leading, spacing: 4) {
                            Text("跨网中继地址")
                                .font(.system(size: 12))
                                .foregroundStyle(LuTheme.secondary)
                            TextField("wss://lu-sync.deno.dev", text: $settings.syncRelayURL)
                                .font(.system(size: 12, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    // 弹幕
                    LuGroup(title: "弹幕") {
                        rowToggle("显示弹幕", isOn: $settings.danmakuEnabled)
                        line
                        sliderRow("不透明度", value: $settings.danmakuOpacity, range: 0.2...1.0)
                        line
                        sliderRow("字号", value: $settings.danmakuFontSize, range: 12...28)
                        line
                        sliderRow("速度", value: $settings.danmakuSpeed, range: 0.5...2.0)
                        line
                        sliderRow("显示区域（占画面高度）", value: $settings.danmakuArea,
                                  range: 0.2...1.0)
                        line
                        VStack(alignment: .leading, spacing: 6) {
                            Text("屏蔽词（逗号分隔）")
                                .font(.system(size: 13))
                                .foregroundStyle(LuTheme.secondary)
                            TextField("剧透, 广告", text: $settings.shieldWords)
                                .font(.system(size: 14))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .tertiarySystemFill)))
                        }
                        .padding(12)
                    }

                    // 弹幕源
                    LuGroup(title: "弹幕源") {
                        HStack {
                            Text("来源").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Spacer()
                            Picker("来源", selection: $settings.danmakuSource) {
                                ForEach(DanmakuSourceKind.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(LuTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: LuTheme.rowHeight)
                        Text(sourceHint)
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        line
                        HStack {
                            Text("简繁转换").font(.system(size: 15)).foregroundStyle(LuTheme.label)
                            Spacer()
                            Picker("简繁转换", selection: $settings.textConvert) {
                                ForEach(LuOpenCCMode.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(LuTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: LuTheme.rowHeight)
                        line
                        Button {
                            showDandanSheet = true
                        } label: {
                            LuListRow(title: "弹弹play 凭据",
                                      subtitle: settings.dandanplayAppID.isEmpty ? "未配置，切到弹弹play时弹幕为空" : "已配置",
                                      symbol: "key", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    // WebDAV
                    LuGroup(title: "WebDAV") {
                        VStack(alignment: .leading, spacing: 8) {
                            settingsField("服务器地址", text: $settings.webdavURL,
                                          placeholder: "https://dav.example.com/dav", keyboard: .URL)
                            settingsField("用户名", text: $settings.webdavUser,
                                          placeholder: "可选")
                            HStack {
                                Text("密码")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LuTheme.secondary)
                                    .frame(width: 66, alignment: .leading)
                                SecureField("可选", text: $settings.webdavPassword)
                                    .font(.system(size: 13))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            HStack(spacing: 10) {
                                NavigationLink(value: Route.webdav) {
                                    Text("浏览网盘")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .frame(height: 34)
                                        .background(RoundedRectangle(cornerRadius: 9)
                                            .fill(settings.webdavURL.isEmpty ? Color.gray : LuTheme.accent))
                                }
                                .buttonStyle(.plain)
                                .disabled(settings.webdavURL.isEmpty)
                                Text("播放时自动带 Basic 认证头")
                                    .font(.system(size: 11))
                                    .foregroundStyle(LuTheme.tertiary)
                                Spacer()
                            }
                        }
                        .padding(12)
                    }

                    // 其他
                    LuGroup(title: "其他") {
                        NavigationLink(value: Route.logs) {
                            LuListRow(title: "运行日志", symbol: "doc.text.magnifyingglass",
                                      value: "\(LuLog.shared.entries.count) 条", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        line
                        NavigationLink(value: Route.update) {
                            LuListRow(title: "检查更新", symbol: "arrow.triangle.2.circlepath",
                                      value: UpdateChecker.currentVersion, chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        line
                        Button {
                            showDiagnostics = true
                        } label: {
                            LuListRow(title: "网络诊断", symbol: "stethoscope", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        line
                        Button {
                            clearCache()
                        } label: {
                            LuListRow(title: "清理缓存", symbol: "trash.slash",
                                      value: cacheText, chevron: false)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    // 数据
                    LuGroup(title: "数据") {
                        Button {
                            app.clearHistory()
                            LuHUD.shared.show("已清空观看历史")
                        } label: {
                            HStack {
                                Text("清空观看历史").font(.system(size: 15)).foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: LuTheme.rowHeight)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("LU \(UpdateChecker.currentVersion) · 原生 SwiftUI 版")
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
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
        .sheet(isPresented: $showDandanSheet) {
            DandanCredentialSheet()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet()
        }
    }

    private var sourceHint: String {
        (DanmakuSourceKind(rawValue: settings.danmakuSource) ?? .bilibili).detail
    }

    private var cacheText: String {
        let cache = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(cache))
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let temp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: temp,
                                                                    includingPropertiesForKeys: nil) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        LuHUD.shared.show("缓存已清理")
        luLogInfo("Settings", "清理缓存")
    }

    @ViewBuilder
    private func settingsField(_ title: String, text: Binding<String>,
                               placeholder: String,
                               keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(LuTheme.secondary)
                .frame(width: 66, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
        }
    }

    private struct TabOption: Identifiable {
        let id: String
        let title: String
    }

    private let tabItems: [TabOption] = [
        TabOption(id: "popular", title: "推荐"),
        TabOption(id: "collect", title: "追番"),
        TabOption(id: "syncplay", title: "一起看"),
        TabOption(id: "emby", title: "Emby"),
        TabOption(id: "my", title: "我的")
    ]

    private func tabBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: {
                !settings.hiddenTabs.split(separator: ",").map(String.init).contains(id)
            },
            set: { visible in
                var hidden = settings.hiddenTabs.split(separator: ",").map(String.init)
                hidden.removeAll { $0 == id }
                if !visible { hidden.append(id) }
                settings.hiddenTabs = hidden.joined(separator: ",")
            }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { settings.updateReminder },
            set: { LuUpdateReminder.shared.setEnabled($0) }
        )
    }

    private var line: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 12)
    }

    private func rowToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(LuTheme.label)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(LuTheme.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: LuTheme.rowHeight)
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 15)).foregroundStyle(LuTheme.label)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)
            }
            Slider(value: value, in: range).tint(LuTheme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct DandanCredentialSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("AppId", text: $settings.dandanplayAppID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("AppSecret", text: $settings.dandanplaySecret)
                } header: {
                    Text("弹弹play 开放平台")
                } footer: {
                    Text("在 dandanplay.com 注册开发者后获取。未配置时播放不受影响，只是没有弹幕。")
                }
            }
            .navigationTitle("弹幕源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
