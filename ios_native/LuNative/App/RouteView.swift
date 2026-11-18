import SwiftUI

/// 统一路由分发。`NavigationStack` 的 destination。
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .detail(let id):
            DetailView(subjectID: id)
        case .search:
            SearchView()
        case .timeline:
            TimelineView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        case .plugins:
            PluginListView()
        case .pluginDetail(let id):
            PluginDetailView(pluginID: id)
        case .about:
            AboutView()
        case .embySettings:
            EmbySettingsView()
        case .downloads:
            DownloadsView()
        case .webdav:
            WebDAVView()
        case .logs:
            LogViewerView()
        case .pluginEditor(let id):
            PluginEditorView(plugin: id.flatMap { target in
                PluginStore.shared.plugins.first { $0.id == target }
            })
        case .update:
            UpdateSheet()
        case .backup:
            BackupView()
        case .urlParser:
            URLResolveView()
        }
    }
}
