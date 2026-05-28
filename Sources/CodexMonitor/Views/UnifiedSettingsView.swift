import SwiftUI

// MARK: - Unified Settings Window

struct UnifiedSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var selectedTab: SettingsTab = .accounts

    enum SettingsTab: String, CaseIterable {
        case accounts = "账户管理"
        case preferences = "偏好设置"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
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
                Label("监控账户列表", systemImage: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { showingAddForm = true }) {
                    Label("添加账户", systemImage: "plus")
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
                    Text("No accounts yet")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("Add Account") { showingAddForm = true }
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
                                        Text("限额已达")
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
                            .help("Edit account")

                            Button(action: {
                                accountStore.deleteAccount(id: account.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Delete account")
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
                    Label("数据刷新间隔", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("定期静默拉取最新云端配额用量")
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
                    Label("数值显示模式", systemImage: "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("菜单栏及主卡片所呈现的主数值模式")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $displayMode) {
                        Text("剩余").tag(DisplayMode.remaining)
                        Text("已用").tag(DisplayMode.used)
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
                    Label("重置时间格式", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("卡片底部重置时间的显示维度")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: $resetTimeFormat) {
                        Text("相对时间").tag(ResetTimeFormat.relative)
                        Text("绝对时间").tag(ResetTimeFormat.absolute)
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
                        Label("在系统菜单栏显示文本", systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .onChange(of: showMenuBarText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.showMenuBarText)
                        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
                    }

                    Text("关闭后将仅在菜单栏隐藏保留图标")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.4)

                // Alert Threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("用量预警提醒阈值", systemImage: "bell.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(alertThreshold))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text("当任一监控限额使用率超过该额度时发送横幅通知")
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
                        Label("开机自启", systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enable: newValue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("Bundle ID:")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(bundleIdentifier)
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack(spacing: 4) {
                            Text("Binary:")
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
