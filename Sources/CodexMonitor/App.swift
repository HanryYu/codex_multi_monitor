import SwiftUI
import AppKit
import UserNotifications
import Combine

@main
struct CodexMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    private var additionalStatusItems: [NSStatusItem] = []
    private var statusButtonAccounts: [ObjectIdentifier: UUID] = [:]
    private let accountNavigation = MenuBarAccountNavigation()
    private var statusBarSubscriptions: Set<AnyCancellable> = []
    var popover: NSPopover!
    var accountStore: AccountStore!
    var codexResetService: CodexResetService!
    var authFileMonitor: AuthFileMonitor?
    var timer: Timer?
    var eventMonitor: Any?
    var fiveHourRefreshScheduler: FiveHourQuotaRefreshScheduler?
    var weeklyQuotaActivationScheduler: WeeklyQuotaActivationScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        migratePreferenceDefaults()

        // Register default preference values so features work out-of-the-box
        // before the user opens Settings for the first time.
        UserDefaults.standard.register(defaults: [
            PreferencesKeys.usageWarningNotificationEnabled: true,
            PreferencesKeys.recoveryNotificationEnabled: true,
            PreferencesKeys.quotaActivationEnabled: false,
            PreferencesKeys.autoImportEnabled: true,
            PreferencesKeys.automaticUpdatesEnabled: true,
            PreferencesKeys.alertThreshold: 80,
            PreferencesKeys.showResetRadar: true,
            PreferencesKeys.showQuotaAllowanceSummary: true,
        ])

        accountStore = AccountStore()
        codexResetService = CodexResetService()
        fiveHourRefreshScheduler = FiveHourQuotaRefreshScheduler(accountStore: accountStore)
        if UserDefaults.standard.bool(forKey: PreferencesKeys.fiveHourRefreshEnabled) {
            fiveHourRefreshScheduler?.start()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fiveHourRefreshDidChange),
            name: .fiveHourRefreshChanged,
            object: nil
        )
        weeklyQuotaActivationScheduler = WeeklyQuotaActivationScheduler(accountStore: accountStore)
        if UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled) {
            weeklyQuotaActivationScheduler?.start()
        }

        // Setup WindowManager
        WindowManager.shared.accountStore = accountStore

        // Setup AuthFileMonitor
        authFileMonitor = AuthFileMonitor(accountStore: accountStore)
        if UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled) {
            authFileMonitor?.startMonitoring()
        }

        // Request notification permissions
        requestNotificationPermission()

        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatusBarIcon()

        // Receive on the next main-loop turn: @Published emits before the value is stored.
        accountStore.$accounts.combineLatest(accountStore.$usageData)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBarIcon() }
            .store(in: &statusBarSubscriptions)
        LocaleManager.shared.$currentLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBarIcon() }
            .store(in: &statusBarSubscriptions)

        NSApp.publisher(for: \.effectiveAppearance)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBarIcon() }
            .store(in: &statusBarSubscriptions)

        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 520)
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuBarView(
            accountStore: accountStore,
            codexResetService: codexResetService,
            accountNavigation: accountNavigation
        )
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Close popover on outside click (extra safety)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }

        // Listen for refresh interval changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshIntervalDidChange),
            name: .refreshIntervalChanged,
            object: nil
        )

        // Listen for display mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayModeDidChange),
            name: .displayModeChanged,
            object: nil
        )

        // Listen for menu bar text toggle changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarTextChanged),
            name: .menuBarTextChanged,
            object: nil
        )

        // Listen for auto import toggle changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoImportDidChange),
            name: .autoImportChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quotaActivationDidChange),
            name: .quotaActivationChanged,
            object: nil
        )

        scheduleRefreshTimer()

        Task { @MainActor in
            await accountStore.refreshAll()
        }

        GitHubReleaseUpdater.shared.checkAutomaticallyIfNeeded()
    }

    private func migratePreferenceDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PreferencesKeys.usageWarningNotificationEnabled) == nil,
           let oldValue = defaults.object(forKey: PreferencesKeys.usageAlertEnabled) as? Bool {
            defaults.set(oldValue, forKey: PreferencesKeys.usageWarningNotificationEnabled)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        authFileMonitor?.stopMonitoring()
        fiveHourRefreshScheduler?.stop()
        weeklyQuotaActivationScheduler?.stop()
    }

    @MainActor
    @objc func togglePopover(_ sender: NSStatusBarButton) {
        let availableIDs = accountStore.accounts.filter { !$0.isHidden }.map(\.id)
        let mappedID = statusButtonAccounts[ObjectIdentifier(sender)]
        let accountID = mappedID.flatMap { availableIDs.contains($0) ? $0 : nil }
        if popover.isShown, accountNavigation.request.accountID == accountID {
            popover.performClose(nil)
            return
        }
        if !availableIDs.isEmpty,
           MenuBarQuotaPreferences.selectedAccountIDs(available: availableIDs).isEmpty {
            popover.performClose(nil)
            WindowManager.shared.openSettingsWindow(initialTab: .preferences)
            return
        }
        // Switching rings while open should open the new account at the clicked ring's anchor.
        if popover.isShown { popover.performClose(nil) }
        accountNavigation.focus(accountID: accountID)
        refreshCodexResetIfEnabled()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refreshIntervalDidChange() {
        scheduleRefreshTimer()
    }

    @MainActor
    @objc private func fiveHourRefreshDidChange() {
        if UserDefaults.standard.bool(forKey: PreferencesKeys.fiveHourRefreshEnabled) {
            fiveHourRefreshScheduler?.start()
        } else {
            fiveHourRefreshScheduler?.stop()
        }
    }

    @objc func displayModeDidChange() {
        Task { @MainActor in
            updateStatusBarTitle()
        }
    }

    @objc func menuBarTextChanged() {
        Task { @MainActor in
            updateStatusBarTitle()
        }
    }

    @objc func autoImportDidChange() {
        Task { @MainActor in
            let enabled = UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled)
            if enabled {
                authFileMonitor?.startMonitoring()
            } else {
                authFileMonitor?.stopMonitoring()
            }
        }
    }

    @objc func quotaActivationDidChange() {
        let enabled = UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled)
        WeeklyQuotaLogger.log("automatic preference changed enabled=\(enabled)")
        Task { @MainActor [weak self] in
            if enabled {
                self?.weeklyQuotaActivationScheduler?.start(runInitialCheck: true)
            } else {
                self?.weeklyQuotaActivationScheduler?.stop()
            }
        }
    }

    func scheduleRefreshTimer() {
        timer?.invalidate()
        timer = nil

        let seconds = UserDefaults.standard.integer(forKey: PreferencesKeys.refreshInterval)
        let interval = RefreshInterval(rawValue: seconds) ?? .fiveMinutes

        guard interval != .off else { return }

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval.rawValue), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.accountStore.refreshAll()
            }
        }
    }

    private func refreshCodexResetIfEnabled() {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.showResetRadar) else { return }
        Task { @MainActor [weak self] in
            await self?.codexResetService.refreshIfNeeded()
        }
    }

    // MARK: - Notification Permission

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self
        AppDelegate.requestNotificationAuthorization()
    }

    /// Static method that can be called from settings to request notification permission
    static func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Status Bar Icon

    @MainActor
    func updateStatusBarIcon() {
        guard statusItem != nil else { return }
        let defaults = UserDefaults.standard
        let available = accountStore.accounts.filter { !$0.isHidden }
        let selectedIDs = MenuBarQuotaPreferences.selectedAccountIDs(available: available.map(\.id))
        MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: selectedIDs)
        let selected = selectedIDs.compactMap { id in available.first { $0.id == id } }
        let requiredExtraItems = max(0, selected.count - 1)
        while additionalStatusItems.count > requiredExtraItems {
            NSStatusBar.system.removeStatusItem(additionalStatusItems.removeLast())
        }
        while additionalStatusItems.count < requiredExtraItems {
            additionalStatusItems.append(NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength))
        }

        let showRemaining = (defaults.string(forKey: PreferencesKeys.displayMode)
            ?? DisplayMode.remaining.rawValue) != DisplayMode.used.rawValue
        let showPercentage = defaults.bool(forKey: PreferencesKeys.showMenuBarText)
        let style = MenuBarQuotaPreferences.iconStyle()
        let appearance = MenuBarQuotaAppearance.load()
        let numberPosition = appearance.effectiveNumberPosition(iconStyle: style)
        let showNumberInside = showPercentage && numberPosition == .inside
        let items = [statusItem!] + additionalStatusItems
        statusButtonAccounts.removeAll(keepingCapacity: true)

        for (index, item) in items.enumerated() {
            guard let button = item.button else { continue }
            let account = selected.indices.contains(index) ? selected[index] : nil
            if let account { statusButtonAccounts[ObjectIdentifier(button)] = account.id }
            let usage: UsageResponse?
            if let account, case .success(let value) = accountStore.usageData[account.id] {
                usage = value
            } else {
                usage = nil
            }
            let preferredWindow = account.map { MenuBarQuotaPreferences.quotaWindow(for: $0.id) } ?? .fiveHour
            let snapshot = MenuBarQuotaSnapshot(usage: usage, preferredWindow: preferredWindow)
            if style == .ring {
                button.image = MenuBarQuotaRing.image(snapshot: snapshot, showRemaining: showRemaining,
                                                     appearance: appearance, showNumberInside: showNumberInside)
            } else {
                let image = NSImage(systemSymbolName: "gauge.with.dots.fill.60percent",
                                    accessibilityDescription: "CodexMonitor")
                    ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "CodexMonitor")
                image?.isTemplate = true
                button.image = image
            }
            let percentage = snapshot.percentage(showRemaining: showRemaining)
            let numberText = percentage.map { "\($0)%" } ?? "—"
            button.title = showPercentage && !showNumberInside
                ? (numberPosition == .leading ? "\(numberText) " : " \(numberText)") : ""
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = numberPosition == .leading ? .imageTrailing : .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self

            let detail = percentage.map { showRemaining ? L10n.percentLeft($0) : L10n.percentUsed($0) }
                ?? MenuBarQuotaL10n.noUsage
            let period = MenuBarQuotaL10n.windowLabel(snapshot.actualWindow ?? preferredWindow)
            let label = account.map { "\($0.provider.displayName) · \($0.name) · \(period): \(detail)" }
                ?? "CodexMonitor · \(MenuBarQuotaL10n.selectAccount)"
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }
    }

    @MainActor
    func updateStatusBarTitle() {
        updateStatusBarIcon()
    }
}
