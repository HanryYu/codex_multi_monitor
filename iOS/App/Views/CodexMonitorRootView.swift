import SwiftUI

struct CodexMonitorRootView: View {
    @EnvironmentObject private var accountStore: MobileAccountStore
    @AppStorage(MobilePreferenceKeys.refreshInterval, store: AppGroupConstants.defaults) private var refreshIntervalRaw = MobileRefreshInterval.fiveMinutes.rawValue

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            await accountStore.refreshAll()
        }
        .task(id: refreshIntervalRaw) {
            await runForegroundRefreshLoop()
        }
    }

    private func runForegroundRefreshLoop() async {
        let interval = MobileRefreshInterval(rawValue: refreshIntervalRaw) ?? .fiveMinutes
        guard interval != .off else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval.rawValue) * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await accountStore.refreshAll()
        }
    }
}
