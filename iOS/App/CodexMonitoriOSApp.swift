import SwiftUI

@main
struct CodexMonitoriOSApp: App {
    @StateObject private var accountStore = MobileAccountStore()

    var body: some Scene {
        WindowGroup {
            CodexMonitorRootView()
                .environmentObject(accountStore)
                .onOpenURL { url in
                    guard url.scheme == "codexmonitor" else { return }
                    if url.host == "refresh" || url.path == "/refresh" {
                        accountStore.refreshFromWidgetDeepLink()
                    }
                }
        }
    }
}
