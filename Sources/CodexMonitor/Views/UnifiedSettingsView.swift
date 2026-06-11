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
        case about

        var label: String {
            switch self {
            case .accounts: return L10n.settingsTabAccounts
            case .preferences: return L10n.settingsTabPreferences
            case .about: return L10n.settingsTabAbout
            }
        }

        var icon: String {
            switch self {
            case .accounts: return "person.2"
            case .preferences: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    init(accountStore: AccountStore, initialTab: SettingsTab = .accounts) {
        self.accountStore = accountStore
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                SettingsTopToolbar(selectedTab: $selectedTab)

                Divider()
                    .opacity(0.8)

                Group {
                    switch selectedTab {
                    case .accounts:
                        AccountManagementContentView(accountStore: accountStore)
                    case .preferences:
                        PreferencesContentView()
                    case .about:
                        AboutSettingsContentView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }

            TrafficLightsView()
                .padding(.top, 16)
                .padding(.leading, 16)
        }
        .frame(width: 540, height: 640)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
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

// MARK: - Settings Toolbar

struct SettingsTopToolbar: View {
    @Binding var selectedTab: UnifiedSettingsView.SettingsTab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(UnifiedSettingsView.SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 25, weight: selectedTab == tab ? .medium : .regular))
                            .symbolRenderingMode(.monochrome)
                            .frame(height: 26)

                        Text(tab.label)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selectedTab == tab ? Color(hex: "111827") : Color(hex: "6B7280"))
                    .frame(width: 64, height: 52)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(hex: "F3F4F6").opacity(0.9))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color.white)
    }
}

struct TrafficLightsView: View {
    var body: some View {
        HStack(spacing: 10) {
            trafficLight(color: Color(hex: "FF5F56"), border: Color(hex: "E0443E")) {
                NSApp.keyWindow?.close()
            }
            trafficLight(color: Color(hex: "FFBD2E"), border: Color(hex: "DEA123")) {
                NSApp.keyWindow?.miniaturize(nil)
            }
            trafficLight(color: Color(hex: "27C93F"), border: Color(hex: "1AAB29")) {
                NSApp.keyWindow?.zoom(nil)
            }
        }
    }

    private func trafficLight(color: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay {
                    Circle()
                        .stroke(border.opacity(0.55), lineWidth: 1)
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
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
            HStack(alignment: .center) {
                Text(L10n.monitoredAccountList)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "1F2937"))

                Spacer()

                Button(action: { showingAddForm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(L10n.addAccount)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(hex: "3B82F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.55)
                .padding(.horizontal, 24)

            if accountStore.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.noAccountsYet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button(action: { showingAddForm = true }) {
                        Text(L10n.addAccount)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "3B82F6"))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(accountStore.accounts.enumerated()), id: \.element.id) { index, account in
                            AccountSettingsRow(
                                account: account,
                                status: accountStatus(for: account),
                                showDivider: index != accountStore.accounts.count - 1,
                                editAction: { editingAccount = account },
                                deleteAction: { accountStore.deleteAccount(id: account.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
        .background(Color.white)
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

    private func accountStatus(for account: Account) -> AccountSettingsStatus? {
        guard let result = accountStore.usageData[account.id] else { return nil }

        switch result {
        case .success(let usage):
            if let label = resolvedLimitLabel(for: usage) {
                return AccountSettingsStatus(text: label, color: Color(hex: "EF4444"))
            } else if let percent = usage.rateLimit?.primaryWindow?.usedPercent {
                return AccountSettingsStatus(
                    text: "\(percent)%",
                    color: percent >= 80 ? Color(hex: "F97316") : Color(hex: "22C55E")
                )
            } else if let credits = usage.credits {
                if credits.unlimited {
                    return AccountSettingsStatus(text: "∞", color: Color(hex: "22C55E"))
                } else if let balance = credits.balance {
                    return AccountSettingsStatus(
                        text: balance,
                        color: credits.hasCredits ? Color(hex: "22C55E") : Color(hex: "EF4444")
                    )
                }
            }
            return AccountSettingsStatus(text: "—", color: Color(hex: "9CA3AF"))
        case .failure:
            return AccountSettingsStatus(text: "!", color: Color(hex: "EF4444"))
        }
    }
}

private struct AccountSettingsStatus {
    let text: String
    let color: Color
}

private struct AccountSettingsRow: View {
    let account: Account
    let status: AccountSettingsStatus?
    let showDivider: Bool
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.2")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "6B7280"))
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(primaryLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "111827"))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(detailLabel)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                if let status {
                    Text(status.text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .frame(minWidth: 62, alignment: .trailing)
                }

                HStack(spacing: 1) {
                    Button(action: editAction) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: "9CA3AF"))
                    .help(L10n.editAccount)

                    Button(action: deleteAction) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: "9CA3AF"))
                    .help(L10n.deleteAccount)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(hex: "F9FAFB"))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(hex: "E5E7EB"), lineWidth: 0.5)
                }
            }
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .opacity(0.45)
            }
        }
    }

    private var primaryLabel: String {
        if let email = account.accountEmail, !email.isEmpty {
            return email
        }
        return account.name
    }

    private var detailLabel: String {
        var parts = [maskedToken(account.authToken)]
        if let email = account.accountEmail, !email.isEmpty {
            parts.append(email)
        } else {
            parts.append(account.name)
        }
        return parts.joined(separator: " · ")
    }

    private func maskedToken(_ token: String) -> String {
        guard token.count > 12 else { return "••••••••" }
        return "\(token.prefix(4))...\(token.suffix(4))"
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
            VStack(alignment: .leading, spacing: 0) {
                displaySettingsSection
                notificationSettingsSection
                generalSettingsSection
                updateSettingsSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .onAppear {
            loadPreferences()
        }
        .onChange(of: localeManager.currentLanguage) { _, _ in
            selectedLanguage = localeManager.currentLanguageOption
        }
    }

    private var displaySettingsSection: some View {
        SettingGroupCard(label: L10n.displaySection, systemImage: "eye") {
            SettingsCheckbox(
                title: L10n.showTextInMenuBar,
                description: L10n.showTextInMenuBarDesc,
                isChecked: $showMenuBarText
            )
            .onChange(of: showMenuBarText) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: PreferencesKeys.showMenuBarText)
                NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
            }

            CardDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingTextBlock(
                    title: L10n.resetTimeFormat,
                    description: L10n.resetTimeFormatDesc
                )

                Spacer(minLength: 12)

                SettingsSegmentedControl(
                    selection: $resetTimeFormat,
                    options: [
                        .init(label: L10n.relativeTime, value: .relative),
                        .init(label: L10n.absoluteTime, value: .absolute)
                    ]
                )
                .onChange(of: resetTimeFormat) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.resetTimeFormat)
                    NotificationCenter.default.post(name: .resetTimeFormatChanged, object: nil)
                }
            }
        }
    }

    private var notificationSettingsSection: some View {
        SettingGroupCard(label: L10n.notificationSection, systemImage: "bell") {
            SettingsCheckbox(
                title: L10n.limitNotificationLabel,
                description: L10n.limitNotificationDesc,
                isChecked: $limitNotificationEnabled
            )
            .onChange(of: limitNotificationEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: PreferencesKeys.limitNotificationEnabled)
                if newValue { requestNotificationPermissionIfNeeded() }
            }

            CardDivider()

            SettingsCheckbox(
                title: L10n.usageWarningNotificationLabel,
                description: L10n.usageWarningNotificationDesc,
                isChecked: $usageWarningNotificationEnabled
            )
            .onChange(of: usageWarningNotificationEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: PreferencesKeys.usageWarningNotificationEnabled)
                if newValue { requestNotificationPermissionIfNeeded() }
            }

            if usageWarningNotificationEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.usageAlertThreshold)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "4B5563"))

                        Spacer()

                        Text("\(Int(alertThreshold))%")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(hex: "3B82F6"))
                    }

                    Slider(value: $alertThreshold, in: 50...95, step: 5)
                        .tint(Color(hex: "3B82F6"))
                        .onChange(of: alertThreshold) { _, newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: PreferencesKeys.alertThreshold)
                        }

                    Text(L10n.usageAlertThresholdDesc)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 24)
                .padding(.top, 1)
            }

            CardDivider()

            HStack(alignment: .center, spacing: 12) {
                SettingsCheckbox(
                    title: L10n.recoveryNotificationLabel,
                    description: L10n.recoveryNotificationDesc,
                    isChecked: $recoveryNotificationEnabled
                )
                .onChange(of: recoveryNotificationEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recoveryNotificationEnabled)
                    NotificationCenter.default.post(name: .recoveryNotificationEnabledChanged, object: nil)
                    if newValue { requestNotificationPermissionIfNeeded() }
                }

                Spacer(minLength: 12)

                SettingsActionButton(title: L10n.testNotificationButton, action: sendTestNotification)
            }

            if notificationNeedsSettings {
                SettingsActionButton(title: L10n.openNotificationSettingsButton, action: openNotificationSettings)
            }

            if let notificationTestStatus {
                Text(notificationTestStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(notificationNeedsSettings ? Color.red : Color(hex: "6B7280"))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var generalSettingsSection: some View {
        SettingGroupCard(label: L10n.generalSection, systemImage: "display") {
            SettingsCheckbox(
                title: L10n.launchAtLogin,
                description: nil,
                isChecked: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                toggleLaunchAtLogin(enable: newValue)
            }

            CardDivider()

            SettingsCheckbox(
                title: L10n.autoImportLocalAccounts,
                description: L10n.autoImportLocalAccountsDesc,
                isChecked: $autoImportEnabled
            )
            .onChange(of: autoImportEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: PreferencesKeys.autoImportEnabled)
                NotificationCenter.default.post(name: .autoImportChanged, object: nil)
            }

            CardDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingTextBlock(
                    title: L10n.dataRefreshInterval,
                    description: L10n.dataRefreshIntervalDesc
                )

                Spacer(minLength: 12)

                SettingsDropdown(selection: $refreshInterval, options: RefreshInterval.allCases.map {
                    .init(label: $0.label, value: $0)
                })
                .onChange(of: refreshInterval) { _, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: PreferencesKeys.refreshInterval)
                    NotificationCenter.default.post(name: .refreshIntervalChanged, object: nil)
                }
            }

            CardDivider()

            HStack(alignment: .center, spacing: 16) {
                Text(L10n.language)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "1F2937"))

                Spacer(minLength: 12)

                SettingsDropdown(selection: $selectedLanguage, options: LanguageOption.allCases.map {
                    .init(label: $0.displayName, value: $0)
                })
                .onChange(of: selectedLanguage) { _, newValue in
                    LocaleManager.shared.setLanguage(newValue)
                }
            }
        }
    }

    private var updateSettingsSection: some View {
        SettingGroupCard(label: L10n.updateSection, systemImage: "arrow.clockwise") {
            HStack(alignment: .top, spacing: 12) {
                SettingsCheckbox(
                    title: L10n.automaticUpdates,
                    description: updater.statusText,
                    isChecked: $automaticUpdatesEnabled
                )
                .onChange(of: automaticUpdatesEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: PreferencesKeys.automaticUpdatesEnabled)
                    if newValue {
                        GitHubReleaseUpdater.shared.checkAutomaticallyIfNeeded()
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    SettingsActionButton(
                        title: updater.isChecking || updater.isDownloading
                            ? L10n.updateCheckingButton
                            : L10n.checkForUpdatesButton,
                        disabled: updater.isChecking || updater.isDownloading
                    ) {
                        Task {
                            await updater.checkForUpdates(downloadIfAvailable: true, userInitiated: true)
                        }
                    }

                    SettingsActionButton(
                        title: L10n.installUpdateButton,
                        disabled: updater.downloadedURL == nil
                    ) {
                        updater.installDownloadedUpdate()
                    }
                }
                .padding(.top, 2)
            }
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

// MARK: - About Content

struct AboutSettingsContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 76)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "3B82F6"), Color(hex: "2563EB")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "60A5FA").opacity(0.5), lineWidth: 1)
                }

            Text("Codex Monitor")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: "1F2937"))
                .padding(.top, 20)

            Text(L10n.aboutVersion(version: AppVersion.current))
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "6B7280"))
                .padding(.top, 4)

            Spacer()

            Text(L10n.aboutCopyright)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "9CA3AF"))
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - TSX Settings Components

struct SettingGroupCard<Content: View>: View {
    let label: String
    let systemImage: String
    private let content: Content

    init(label: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(hex: "4B5563"))
                    }

                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "111827"))
            }
            .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F9FAFB").opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "E5E7EB").opacity(0.8), lineWidth: 0.6)
            }
        }
        .padding(.bottom, 24)
    }
}

struct SettingsCheckbox: View {
    let title: String
    let description: String?
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isChecked ? Color(hex: "3B82F6") : Color.white)
                        .frame(width: 16, height: 16)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(isChecked ? Color(hex: "3B82F6") : Color(hex: "D1D5DB"), lineWidth: 1)
                        }
                        .overlay {
                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "1F2937"))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 24)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingTextBlock: View {
    let title: String
    let description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "1F2937"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "6B7280"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsOption<Value: Hashable>: Identifiable {
    let label: String
    let value: Value
    var id: Value { value }
}

struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsOption<Value>]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == option.value ? Color(hex: "111827") : Color(hex: "6B7280"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color(hex: "E5E7EB").opacity(0.8), lineWidth: 0.5)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(hex: "F3F4F6"))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(hex: "E5E7EB").opacity(0.65), lineWidth: 0.6)
        }
    }
}

struct SettingsDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsOption<Value>]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.system(size: 12, weight: .medium))
        .frame(width: 118)
        .background(Color(hex: "F3F4F6"))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingsActionButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: disabled ? {} : action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(disabled ? Color(hex: "9CA3AF") : Color(hex: "1F2937"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(disabled ? Color(hex: "F9FAFB") : Color(hex: "F3F4F6"))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(disabled ? Color(hex: "F3F4F6") : Color(hex: "E5E7EB"), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct CardDivider: View {
    var body: some View {
        Divider()
            .opacity(0.55)
    }
}
