import SwiftUI

// MARK: - Unified Settings Window

struct UnifiedSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var selectedTab: SettingsTab = .accounts

    enum SettingsTab: String, CaseIterable {
        case accounts
        case preferences

        var label: String {
            switch self {
            case .accounts: return L10n.accountManagement
            case .preferences: return L10n.preferences
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            // Tab content
            TabView(selection: $selectedTab) {
                AccountManagementContentView(accountStore: accountStore)
                    .tag(SettingsTab.accounts)

                PreferencesContentView()
                    .tag(SettingsTab.preferences)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 460, height: 480)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Account Management Content (no Done button, no own window management)

struct AccountManagementContentView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var showingAddForm = false
    @State private var editingAccount: Account?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label(L10n.monitoredAccountList, systemImage: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { showingAddForm = true }) {
                    Label(L10n.addAccount, systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.5)

            // Account list
            if accountStore.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.noAccountsYet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button(L10n.addAccount) { showingAddForm = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(accountStore.accounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(maskedToken(account.authToken))
                                    .font(.system(size: 11).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Status indicator
                            if let result = accountStore.usageData[account.id] {
                                switch result {
                                case .success(let usage):
                                    if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
                                        Text("\(percent)%")
                                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(percent >= 80 ? .orange : .green)
                                    } else if let credits = usage.credits {
                                        if credits.unlimited {
                                            Text("∞")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.green)
                                        } else if let balance = credits.balance {
                                            Text(balance)
                                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(credits.hasCredits ? .green : .red)
                                        } else {
                                            Text("—")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if usage.rateLimitReachedType != nil {
                                        Text(L10n.limitReached)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("—")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
                                case .failure:
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                            }

                            Button(action: {
                                editingAccount = account
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.editAccount)

                            Button(action: {
                                accountStore.deleteAccount(id: account.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help(L10n.deleteAccount)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddForm) {
            AddAccountSheet(accountStore: accountStore, isPresented: $showingAddForm)
        }
        .sheet(item: $editingAccount) { account in
            EditAccountSheetWrapper(accountStore: accountStore, account: account, editingAccount: $editingAccount)
        }
    }

    func maskedToken(_ token: String) -> String {
        guard token.count > 12 else { return "••••••••" }
        let prefix = token.prefix(8)
        let suffix = token.suffix(4)
        return "\(prefix)••••\(suffix)"
    }
}

// MARK: - Preferences Content (no Done button, no window close logic)

struct PreferencesContentView: View {
    @State private var refreshInterval: RefreshInterval = .fiveMinutes
    @State private var launchAtLogin: Bool = false
    @State private var bundleIdentifier: String = ""
    @State private var binaryPath: String = ""
    @State private var displayMode: DisplayMode = .remaining
    @State private var alertThreshold: Double = 80
    @State private var showMenuBarText: Bool = false
    @State private var resetTimeFormat: ResetTimeFormat = .relative

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Data Refresh Interval
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.dataRefreshInterval, systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(L10n.dataRefreshIntervalDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: refreshInterval) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.refreshInterval)
                        NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Display Mode Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.displayModeLabel, systemImage: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(L10n.displayModeDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $displayMode) {
                        Text(L10n.remaining).tag(DisplayMode.remaining)
                        Text(L10n.used).tag(DisplayMode.used)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: displayMode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.displayMode)
                        NotificationCenter.default.post(name: .displayModeChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Reset Time Format
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.resetTimeFormat, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(L10n.resetTimeFormatDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $resetTimeFormat) {
                        Text(L10n.relativeTime).tag(ResetTimeFormat.relative)
                        Text(L10n.absoluteTime).tag(ResetTimeFormat.absolute)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: resetTimeFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.resetTimeFormat)
                        NotificationCenter.default.post(name: .resetTimeFormatChanged, object: nil)
                    }
                }

                Divider().opacity(0.4)

                // Menu Bar Text Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $showMenuBarText) {
                        Label(L10n.showTextInMenuBar, systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .onChange(of: showMenuBarText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.showMenuBarText)
                        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
                    }

                    Text(L10n.showTextInMenuBarDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.4)

                // Alert Threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(L10n.usageAlertThreshold, systemImage: "bell.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(alertThreshold))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.usageAlertThresholdDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Slider(value: $alertThreshold, in: 50...95, step: 5)
                        .onChange(of: alertThreshold) { _, newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: PreferencesKeys.alertThreshold)
                        }
                }

                Divider().opacity(0.4)

                // Launch at Login
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $launchAtLogin) {
                        Label(L10n.launchAtLogin, systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enable: newValue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(L10n.bundleIdLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(bundleIdentifier)
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack(spacing: 4) {
                            Text(L10n.binaryLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(binaryPath)
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear {
            loadPreferences()
        }
    }

    private func loadPreferences() {
        let saved = UserDefaults.standard.integer(forKey: PreferencesKeys.refreshInterval)
        if saved == 0 && !UserDefaults.standard.bool(forKey: "has_set_refresh_interval") {
            refreshInterval = .fiveMinutes
            UserDefaults.standard.set(RefreshInterval.fiveMinutes.rawValue, forKey: PreferencesKeys.refreshInterval)
            UserDefaults.standard.set(true, forKey: "has_set_refresh_interval")
        } else {
            refreshInterval = RefreshInterval(rawValue: saved) ?? .fiveMinutes
        }

        bundleIdentifier = defaultBundleIdentifier()
        binaryPath = defaultBinaryPath()

        let plist = readLaunchAgentPlist(bundleID: bundleIdentifier)
        launchAtLogin = plist != nil

        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining

        let savedThreshold = UserDefaults.standard.integer(forKey: PreferencesKeys.alertThreshold)
        alertThreshold = savedThreshold > 0 ? Double(savedThreshold) : 80

        showMenuBarText = UserDefaults.standard.bool(forKey: PreferencesKeys.showMenuBarText)

        let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.resetTimeFormat) ?? ResetTimeFormat.relative.rawValue
        resetTimeFormat = ResetTimeFormat(rawValue: formatString) ?? .relative
    }

    private func toggleLaunchAtLogin(enable: Bool) {
        UserDefaults.standard.set(bundleIdentifier, forKey: PreferencesKeys.bundleIdentifier)
        _ = writeLaunchAgentPlist(bundleID: bundleIdentifier, binaryPath: binaryPath, enable: enable)
    }
}
