import SwiftUI

@main
struct LUApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var pluginStore = PluginStore.shared
    @AppStorage("lu.onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(settings)
                    .environmentObject(appState)
                    .environmentObject(pluginStore)
                    .tint(LuTheme.accent)

                if !onboarded {
                    OnboardingView(done: $onboarded)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: onboarded)
            .onOpenURL { url in
                _ = LuDeepLink.handle(url)
            }
        }
    }
}
