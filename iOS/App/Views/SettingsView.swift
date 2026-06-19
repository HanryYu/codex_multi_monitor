import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var accountStore: MobileAccountStore
    @AppStorage(MobilePreferenceKeys.refreshInterval, store: AppGroupConstants.defaults) private var refreshIntervalRaw = MobileRefreshInterval.fiveMinutes.rawValue
    @AppStorage(MobilePreferenceKeys.displayMode, store: AppGroupConstants.defaults) private var displayModeRaw = UsageDisplayMode.remaining.rawValue
    @AppStorage(MobilePreferenceKeys.resetTimeFormat, store: AppGroupConstants.defaults) private var resetTimeFormatRaw = ResetTimeFormat.relative.rawValue
    @AppStorage(MobilePreferenceKeys.usageWarningNotificationEnabled, store: AppGroupConstants.defaults) private var warningNotificationsEnabled = true
    @AppStorage(MobilePreferenceKeys.limitNotificationEnabled, store: AppGroupConstants.defaults) private var limitNotificationsEnabled = true
    @AppStorage(MobilePreferenceKeys.alertThreshold, store: AppGroupConstants.defaults) private var alertThreshold = 80

    private var refreshInterval: Binding<MobileRefreshInterval> {
        Binding(
            get: { MobileRefreshInterval(rawValue: refreshIntervalRaw) ?? .fiveMinutes },
            set: { refreshIntervalRaw = $0.rawValue }
        )
    }

    private var displayMode: Binding<UsageDisplayMode> {
        Binding(
            get: { UsageDisplayMode(rawValue: displayModeRaw) ?? .remaining },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    private var resetTimeFormat: Binding<ResetTimeFormat> {
        Binding(
            get: { ResetTimeFormat(rawValue: resetTimeFormatRaw) ?? .relative },
            set: { resetTimeFormatRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Refresh frequency", selection: refreshInterval) {
                    ForEach(MobileRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }

                Picker("Display", selection: displayMode) {
                    ForEach(UsageDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Reset time", selection: resetTimeFormat) {
                    ForEach(ResetTimeFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            } header: {
                Text("Dashboard")
            } footer: {
                Text("Refresh runs while the app is active. Widgets use the same cadence for their next timeline refresh.")
            }

            Section {
                Toggle("Limit reached", isOn: $limitNotificationsEnabled)
                    .onChange(of: limitNotificationsEnabled) { enabled in
                        if enabled { MobileNotificationService.requestAuthorizationIfNeeded() }
                    }

                Toggle("Usage warning", isOn: $warningNotificationsEnabled)
                    .onChange(of: warningNotificationsEnabled) { enabled in
                        if enabled { MobileNotificationService.requestAuthorizationIfNeeded() }
                    }

                if warningNotificationsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Warning threshold")
                            Spacer()
                            Text("\(alertThreshold)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(alertThreshold) },
                                set: { alertThreshold = Int($0) }
                            ),
                            in: 50...95,
                            step: 5
                        )
                    }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                if accountStore.accounts.isEmpty {
                    Text("No synced accounts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountStore.accounts) { account in
                        WidgetAccountToggle(account: account)
                    }
                }
            } header: {
                Text("Widget Accounts")
            } footer: {
                Text("Small widgets show one account, medium widgets show up to two, and large widgets show up to four selected accounts.")
            }

            Section {
                HStack {
                    Text("iCloud revision")
                    Spacer()
                    Text(accountStore.cloudRevision.map { UsagePresentation.freshnessText($0) } ?? "Not synced")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Account management stays on Mac. iOS reads the synced account snapshot and refreshes usage.")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            MobileNotificationService.requestAuthorizationIfNeeded()
        }
    }
}

private struct WidgetAccountToggle: View {
    let account: CloudSyncedAccount
    @State private var isSelected = false

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(account.source == "localAuth" ? "Local auth" : "Manual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isSelected = WidgetPreferenceStore.isSelected(account.id)
        }
        .onChange(of: isSelected) { selected in
            WidgetPreferenceStore.setSelected(selected, accountID: account.id)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(MobileAccountStore())
        }
    }
}
#endif
