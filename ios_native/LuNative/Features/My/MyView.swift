import SwiftUI

struct MyView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var plugins: PluginStore
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LuPageHeader(title: "我的")

                    profileCard

                    LuGroup(title: "内容") {
                        NavigationLink(value: Route.history) {
                            LuListRow(title: "观看历史", symbol: "clock.arrow.circlepath",
                                      value: "\(app.history.count)", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.timeline) {
                            LuListRow(title: "时间表", symbol: "calendar", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.downloads) {
                            LuListRow(title: "离线下载", symbol: "arrow.down.circle",
                                      value: "\(DownloadManager.shared.records.count) 个", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.webdav) {
                            LuListRow(title: "WebDAV 网盘", symbol: "externaldrive.badge.icloud",
                                      value: settings.webdavURL.isEmpty ? "未配置" : "已配置",
                                      chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    LuGroup(title: "播放") {
                        NavigationLink(value: Route.plugins) {
                            LuListRow(title: "播放源插件", symbol: "puzzlepiece.extension",
                                      value: "\(plugins.enabledPlugins.count) 个启用", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.embySettings) {
                            LuListRow(title: "Emby 服务器", symbol: "externaldrive",
                                      value: settings.embySession?.userName ?? "未连接", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    LuGroup(title: "工具") {
                        NavigationLink(value: Route.urlParser) {
                            LuListRow(title: "直链解析", symbol: "wand.and.stars", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.backup) {
                            LuListRow(title: "备份与恢复", symbol: "externaldrive.badge.timemachine",
                                      value: "\(app.collects.count) 部追番", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    LuGroup(title: "其他") {
                        NavigationLink(value: Route.settings) {
                            LuListRow(title: "设置", symbol: "gearshape", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.update) {
                            LuListRow(title: "检查更新", symbol: "arrow.triangle.2.circlepath",
                                      value: UpdateChecker.currentVersion, chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.logs) {
                            LuListRow(title: "运行日志", symbol: "doc.text.magnifyingglass",
                                      value: "\(LuLog.shared.entries.count) 条", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        divider
                        NavigationLink(value: Route.about) {
                            LuListRow(title: "关于 LU", symbol: "info.circle", chevron: true)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var divider: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 52)
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [LuTheme.accent, .purple.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("本地模式")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LuTheme.label)
                HStack(spacing: 14) {
                    stat("\(app.collectCount)", "追番")
                    stat("\(app.history.count)", "看过")
                    stat("\(PluginStore.shared.enabledPlugins.count)", "源")
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luLiquidGlass(cornerRadius: 18, frost: 0.55, saturation: 1.4, aberration: 0.5)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(LuTheme.label)
            Text(label).font(.system(size: 10)).foregroundStyle(LuTheme.secondary)
        }
    }
}
