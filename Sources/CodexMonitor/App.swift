import SwiftUI
import AppKit
import UserNotifications

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
    var popover: NSPopover!
    var accountStore: AccountStore!
    var authFileMonitor: AuthFileMonitor?
    var timer: Timer?
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Register default preference values so features work out-of-the-box
        // before the user opens Settings for the first time.
        UserDefaults.standard.register(defaults: [
            PreferencesKeys.usageAlertEnabled: true,
            PreferencesKeys.recoveryNotificationEnabled: true,
            PreferencesKeys.autoImportEnabled: true,
            PreferencesKeys.alertThreshold: 80,
        ])

        accountStore = AccountStore()

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

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "gauge.with.dots.fill.60percent", accessibilityDescription: "CodexMonitor")
                ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "CodexMonitor")
                ?? NSImage(named: NSImage.Name("NSApplicationIcon"))
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Set initial icon template mode
        updateStatusBarIcon()

        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 520)
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuBarView(accountStore: accountStore)
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

        scheduleRefreshTimer()

        Task { @MainActor in
            await accountStore.refreshAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        authFileMonitor?.stopMonitoring()
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func refreshIntervalDidChange() {
        scheduleRefreshTimer()
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
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "gauge.with.dots.fill.60percent", accessibilityDescription: "CodexMonitor")
            ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "CodexMonitor")
            ?? NSImage(named: NSImage.Name("NSApplicationIcon"))
        image?.isTemplate = true
        button.image = image

        // Update title with usage summary
        updateStatusBarTitle()
    }

    @MainActor
    func updateStatusBarTitle() {
        guard let button = statusItem.button else { return }

        let showText = UserDefaults.standard.bool(forKey: PreferencesKeys.showMenuBarText)
        guard showText else {
            button.title = ""
            return
        }

        let modeString = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        let displayMode = DisplayMode(rawValue: modeString) ?? .remaining

        let percentages = accountStore.topUsagePercentages
        if percentages.isEmpty {
            button.title = ""
        } else if percentages.count == 1 {
            let p = percentages[0]
            if displayMode == .remaining {
                button.title = L10n.percentLeft(100 - p)
            } else {
                button.title = L10n.percentUsed(p)
            }
        } else {
            if displayMode == .remaining {
                let labels = percentages.map { L10n.percentLeft(100 - $0) }.joined(separator: " / ")
                button.title = " \(labels)"
            } else {
                let labels = percentages.map { L10n.percentUsed($0) }.joined(separator: " / ")
                button.title = " \(labels)"
            }
        }
    }
}
