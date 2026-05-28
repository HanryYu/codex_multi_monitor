import SwiftUI
import AppKit

@main
struct CodexMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var accountStore: AccountStore!
    var timer: Timer?
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        accountStore = AccountStore()

        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.fill.60percent", accessibilityDescription: "CodexMonitor")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover with glass-like appearance
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 520)
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

        scheduleRefreshTimer()

        Task { @MainActor in
            await accountStore.refreshAll()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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

    @MainActor
    func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }

        let status = accountStore.overallStatus
        let symbolName: String
        let tintColor: NSColor

        switch status {
        case .healthy:
            symbolName = "gauge.with.dots.fill.60percent"
            tintColor = .systemGreen
        case .warning:
            symbolName = "gauge.with.dots.fill.60percent"
            tintColor = .systemYellow
        case .critical:
            symbolName = "gauge.with.dots.fill.60percent"
            tintColor = .systemRed
        case .noAccounts:
            symbolName = "gauge.with.dots.fill.60percent"
            tintColor = .secondaryLabelColor
        }

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CodexMonitor")?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
            button.contentTintColor = tintColor
        }

        // Update title with usage summary
        updateStatusBarTitle()
    }

    @MainActor
    func updateStatusBarTitle() {
        guard let button = statusItem.button else { return }

        let percentages = accountStore.topUsagePercentages
        if percentages.isEmpty {
            button.title = ""
        } else if percentages.count == 1 {
            button.title = " \(percentages[0])%"
        } else {
            let labels = percentages.map { "\($0)%" }.joined(separator: " / ")
            button.title = " \(labels)"
        }
    }
}
