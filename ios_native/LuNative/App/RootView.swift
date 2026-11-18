import SwiftUI

/// 导航目的地。全部用 `NavigationStack` 的值路由，避免字符串路径。
enum Route: Hashable {
    case detail(subjectID: Int)
    case search
    case timeline
    case history
    case settings
    case plugins
    case pluginDetail(id: String)
    case about
    case embySettings
    case downloads
    case webdav
    case logs
    case pluginEditor(id: String?)
    case update
    case backup
    case urlParser
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var appState: AppState
    @State private var tab: Int = 0
    @State private var deepTarget: DeepLinkSubject?
    @Namespace private var tabNamespace

    /// 五项底栏。HG 短剧按需求整块移除，不再保留隐藏入口。
    private let tabs: [LuTabItem] = [
        LuTabItem(id: "popular", title: "推荐", symbol: "play.rectangle.on.rectangle"),
        LuTabItem(id: "collect", title: "追番", symbol: "books.vertical"),
        LuTabItem(id: "syncplay", title: "一起看", symbol: "person.2"),
        LuTabItem(id: "emby", title: "Emby", symbol: "externaldrive.connected.to.line.below"),
        LuTabItem(id: "my", title: "我的", symbol: "person.crop.circle")
    ]

    /// 底栏过滤：设置里可以隐藏不用的 tab
    private var visibleTabs: [LuTabItem] {
        let hidden = Set(settings.hiddenTabs.split(separator: ",").map(String.init))
        let filtered = tabs.filter { !hidden.contains($0.id) }
        return filtered.isEmpty ? [tabs[0]] : filtered
    }

    private var currentTabID: String {
        guard tab >= 0, tab < visibleTabs.count else { return visibleTabs.first?.id ?? "popular" }
        return visibleTabs[tab].id
    }

    var body: some View {
        ZStack {
            LuBackdrop()

            Group {
                switch currentTabID {
                case "popular": PopularView()
                case "collect": CollectView()
                case "syncplay": SyncPlayView()
                case "emby": EmbyView()
                default: MyView()
                }
            }
            .id(settings.accent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LuTabBar(items: visibleTabs, selection: $tab, namespace: tabNamespace)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
        }
        .overlay { LuHUDOverlay() }
        .preferredColorScheme(settings.appearance.colorScheme)
        .fullScreenCover(item: $deepTarget) { target in
            NavigationStack {
                DetailView(subjectID: target.id)
            }
            .environmentObject(settings)
            .environmentObject(appState)
        }
        .onChange(of: appState.pendingSubjectID) { value in
            guard let value else { return }
            deepTarget = DeepLinkSubject(id: value)
            appState.pendingSubjectID = nil
        }
        .onAppear {
            if let index = visibleTabs.firstIndex(where: { $0.id == settings.defaultTab }) {
                tab = index
            }
            settings.applyTokenToAPI()
            LuUpdateReminder.shared.refreshIfNeeded()
            if let pending = appState.pendingSubjectID {
                deepTarget = DeepLinkSubject(id: pending)
                appState.pendingSubjectID = nil
            }
        }
    }
}

private struct DeepLinkSubject: Identifiable {
    let id: Int
}
