import SwiftUI
import AppKit
import UserNotifications

// MARK: - Unified Settings Window

struct UnifiedSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var localeManager = LocaleManager.shared
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

            // Tab content (conditional rendering to avoid native title bar tab switcher)
            if selectedTab == .accounts {
                AccountManagementContentView(accountStore: accountStore)
            } else {
                PreferencesContentView()
            }
        }
        .frame(width: 460, height: 480)
        .background(.ultraThinMaterial)
        .onChange(of: localeManager.currentLanguage) { _, _ in
            if let window = NSApp.windows.first(where: {
                $0.title.contains("Codex Monitor") || $0.title.contains("CodexMonitor")
                || $0.title.contains("設定") || $0.title.contains("设置")
            }) {
                window.title = L10n.codexMonitorSettings
            }
        }
    }
}

// MARK: - Account Management Content (no Done button, no own window management)

struct AccountManagementContentView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var localeManager = LocaleManager.shared
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
                                HStack(spacing: 4) {
                                    Text(account.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    if account.source == .localAuth {
                                        Text(L10n.sourceLocalBadge)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(maskedToken(account.authToken))
                                    .font(.system(size: 11).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                if let email = account.accountEmail, !email.isEmpty {
                                    Text(email)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                if account.source == .localAuth && account.localAuthInvalid {
                                    Text(L10n.localAuthInvalid)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            // Status indicator
                            if let result = accountStore.usageData[account.id] {
                                switch result {
                                case .success(let usage):
                                    if let label = resolvedLimitLabel(for: usage) {
                                        Text(label)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.red)
                                    } else if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
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

    /// Resolve the limit-reached label for an account's usage data.
    /// Returns nil if the account has not reached any limit.
    func resolvedLimitLabel(for usage: UsageResponse) -> String? {
        if let reachedType = usage.rateLimitReachedType {
            let t = reachedType.type.lowercased()
            if t == "primary" || t.contains("5h") || t.contains("5hour") || t.contains("hour") {
                return L10n.fiveHourLimitReached()
            } else if t == "secondary" || t.contains("weekly") || t.contains("7d") || t.contains("week") {
                return L10n.weeklyLimitReached()
            }
            return L10n.limitReached
        }
        if let rl = usage.rateLimit, rl.limitReached {
            return L10n.limitReached
        }
        return nil
    }
}

// MARK: - Preferences Content (no Done button, no window close logic)

struct PreferencesContentView: View {
    @ObservedObject var localeManager = LocaleManager.shared
    @ObservedObject private var updater = GitHubReleaseUpdater.shared
    @State private var refreshInterval: RefreshInterval = .fiveMinutes
    @State private var launchAtLogin: Bool = false
    @State private var displayMode: DisplayMode = .remaining
    @State private var alertThreshold: Double = 80
    @State private var showMenuBarText: Bool = false
    @State private var resetTimeFormat: ResetTimeFormat = .relative
    @State private var selectedLanguage: LanguageOption = .system
    @State private var autoImportEnabled: Bool = false
    @State private var usageWarningNotificationEnabled: Bool = true
    @State private var limitNotificationEnabled: Bool = true
    @State private var recoveryNotificationEnabled: Bool = true
    @State private var automaticUpdatesEnabled: Bool = true
    @State private var notificationTestStatus: String?
    @State private var notificationNeedsSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Display Card ──
                VStack(alignment: .leading, spacing: 8) {
                SectionHeader(label: L10n.displaySection, systemImage: "eye")

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
                    .frame(maxWidth: .infinity)
                    .onChange(of: displayMode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.displayMode)
                        NotificationCenter.default.post(name: .displayModeChanged, object: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                // Menu Bar Text Toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.showTextInMenuBar, systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $showMenuBarText)
                            .labelsHidden()
                    }
                    .onChange(of: showMenuBarText) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.showMenuBarText)
                        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
                    }

                    Text(L10n.showTextInMenuBarDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

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
                    .frame(maxWidth: .infinity)
                    .onChange(of: resetTimeFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.resetTimeFormat)
                        NotificationCenter.default.post(name: .resetTimeFormatChanged, object: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // ── Notifications Card ──
                VStack(alignment: .leading, spacing: 8) {
                SectionHeader(label: L10n.notificationSection, systemImage: "bell")

                // Limit Notification Toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.limitNotificationLabel, systemImage: "bell.badge.fill")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $limitNotificationEnabled)
                            .labelsHidden()
                    }
                    .onChange(of: limitNotificationEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.limitNotificationEnabled)
                        if newValue { requestNotificationPermissionIfNeeded() }
                    }

                    Text(L10n.limitNotificationDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                // Usage Warning Toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.usageWarningNotificationLabel, systemImage: "bell.fill")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $usageWarningNotificationEnabled)
                            .labelsHidden()
                    }
                    .onChange(of: usageWarningNotificationEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.usageWarningNotificationEnabled)
                        if newValue { requestNotificationPermissionIfNeeded() }
                    }

                    Text(L10n.usageWarningNotificationDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Alert Threshold (conditionally visible)
                if usageWarningNotificationEnabled {
                    CompactDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(L10n.usageAlertThreshold, systemImage: "slider.horizontal.3")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CompactDivider()

                // Recovery Notification Toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.recoveryNotificationLabel, systemImage: "arrow.clockwise.circle")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $recoveryNotificationEnabled)
                            .labelsHidden()
                    }
                    .onChange(of: recoveryNotificationEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recoveryNotificationEnabled)
                        NotificationCenter.default.post(name: .recoveryNotificationEnabledChanged, object: nil)
                        if newValue { requestNotificationPermissionIfNeeded() }
                    }

                    Text(L10n.recoveryNotificationDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                HStack(spacing: 8) {
                    Button(action: sendTestNotification) {
                        Label(L10n.testNotificationButton, systemImage: "paperplane.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if notificationNeedsSettings {
                        Button(action: openNotificationSettings) {
                            Label(L10n.openNotificationSettingsButton, systemImage: "gear")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }

                if let notificationTestStatus {
                    Text(notificationTestStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(notificationNeedsSettings ? Color.red : Color.secondary)
                        .lineLimit(3)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // ── General Card ──
                VStack(alignment: .leading, spacing: 8) {
                SectionHeader(label: L10n.generalSection, systemImage: "gear")

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
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                // Auto Import Local Accounts
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.autoImportLocalAccounts, systemImage: "arrow.down.doc")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $autoImportEnabled)
                            .labelsHidden()
                    }
                    .onChange(of: autoImportEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: PreferencesKeys.autoImportEnabled)
                        NotificationCenter.default.post(name: .autoImportChanged, object: nil)
                    }

                    Text(L10n.autoImportLocalAccountsDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                // Launch at Login
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.launchAtLogin, systemImage: "power")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                    }
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enable: newValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactDivider()

                // Language
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.language, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedLanguage) {
                        ForEach(LanguageOption.allCases, id: \.self) { option in
                            Text(option.displayName)
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: selectedLanguage) { _, newValue in
                        LocaleManager.shared.setLanguage(newValue)
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // ── Updates Card ──
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(label: L10n.updateSection, systemImage: "arrow.down.circle")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(L10n.automaticUpdates, systemImage: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $automaticUpdatesEnabled)
                                .labelsHidden()
                        }
                        .onChange(of: automaticUpdatesEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: PreferencesKeys.automaticUpdatesEnabled)
                            if newValue {
                                GitHubReleaseUpdater.shared.checkAutomaticallyIfNeeded()
                            }
                        }

                        Text(updater.statusText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    CompactDivider()

                    HStack(spacing: 8) {
                        Button(action: {
                            Task {
                                await updater.checkForUpdates(downloadIfAvailable: true, userInitiated: true)
                            }
                        }) {
                            if updater.isChecking || updater.isDownloading {
                                Label(L10n.updateCheckingButton, systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Label(L10n.checkForUpdatesButton, systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(updater.isChecking || updater.isDownloading)

                        Button(action: {
                            updater.installDownloadedUpdate()
                        }) {
                            Label(L10n.installUpdateButton, systemImage: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(updater.downloadedURL == nil)

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear {
            loadPreferences()
        }
        .onChange(of: localeManager.currentLanguage) { _, _ in
            selectedLanguage = localeManager.currentLanguageOption
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

        launchAtLogin = LoginItemService.isEnabled

        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: modeString) ?? .remaining

        let savedThreshold = UserDefaults.standard.integer(forKey: PreferencesKeys.alertThreshold)
        alertThreshold = savedThreshold > 0 ? Double(savedThreshold) : 80

        showMenuBarText = UserDefaults.standard.bool(forKey: PreferencesKeys.showMenuBarText)

        let formatString = UserDefaults.standard.string(forKey: PreferencesKeys.resetTimeFormat) ?? ResetTimeFormat.relative.rawValue
        resetTimeFormat = ResetTimeFormat(rawValue: formatString) ?? .relative

        let langString = UserDefaults.standard.string(forKey: "app_language")
        selectedLanguage = LanguageOption.from(saved: langString)

        autoImportEnabled = UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled)

        // Notification toggles (default true)
        let warningVal = UserDefaults.standard.object(forKey: PreferencesKeys.usageWarningNotificationEnabled) as? Bool
        if let warningVal {
            usageWarningNotificationEnabled = warningVal
        } else {
            usageWarningNotificationEnabled = (UserDefaults.standard.object(forKey: PreferencesKeys.usageAlertEnabled) as? Bool) ?? true
        }

        let limitVal = UserDefaults.standard.object(forKey: PreferencesKeys.limitNotificationEnabled) as? Bool
        limitNotificationEnabled = limitVal ?? true

        let recoveryVal = UserDefaults.standard.object(forKey: PreferencesKeys.recoveryNotificationEnabled) as? Bool
        recoveryNotificationEnabled = recoveryVal ?? true

        let automaticUpdatesVal = UserDefaults.standard.object(forKey: PreferencesKeys.automaticUpdatesEnabled) as? Bool
        automaticUpdatesEnabled = automaticUpdatesVal ?? true
    }

    private func toggleLaunchAtLogin(enable: Bool) {
        let success = LoginItemService.setEnabled(enable)
        launchAtLogin = success ? enable : LoginItemService.isEnabled
    }

    private func sendTestNotification() {
        let center = UNUserNotificationCenter.current()
        notificationNeedsSettings = false

        func enqueueTestNotification() {
            let content = UNMutableNotificationContent()
            content.title = "CodexMonitor"
            content.body = L10n.testNotificationBody
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "notification_test_\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                DispatchQueue.main.async {
                    if let error {
                        notificationTestStatus = notificationErrorMessage(error)
                    } else {
                        notificationTestStatus = L10n.notificationTestSent
                        notificationNeedsSettings = false
                    }
                }
            }
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                enqueueTestNotification()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if granted {
                        enqueueTestNotification()
                    } else {
                        DispatchQueue.main.async {
                            if let error {
                                notificationTestStatus = notificationErrorMessage(error)
                            } else {
                                notificationTestStatus = L10n.notificationPermissionDenied
                                notificationNeedsSettings = true
                            }
                        }
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    notificationTestStatus = L10n.notificationPermissionDenied
                    notificationNeedsSettings = true
                }
            @unknown default:
                DispatchQueue.main.async {
                    notificationTestStatus = L10n.notificationPermissionDenied
                    notificationNeedsSettings = true
                }
            }
        }
    }

    private func notificationErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == UNErrorDomain,
           nsError.code == UNError.Code.notificationsNotAllowed.rawValue {
            notificationNeedsSettings = true
            return L10n.notificationsNotAllowed
        }
        return L10n.notificationTestFailed(
            error: "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        )
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Check notification authorization and request if not yet granted
    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized else { return }
            DispatchQueue.main.async {
                AppDelegate.requestNotificationAuthorization()
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 6)
    }
}

// MARK: - Compact Divider

struct CompactDivider: View {
    var body: some View {
        Divider().opacity(0.3)
    }
}
