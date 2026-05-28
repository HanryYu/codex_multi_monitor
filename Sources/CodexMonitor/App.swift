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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize account store
        accountStore = AccountStore()
        
        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "CodexMonitor")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Setup popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = true
        
        let contentView = MenuBarView(accountStore: accountStore)
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Listen for refresh interval changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshIntervalDidChange),
            name: .refreshIntervalChanged,
            object: nil
        )
        
        // Start timer with saved interval
        scheduleRefreshTimer()
        
        // Initial refresh
        Task { @MainActor in
            await accountStore.refreshAll()
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Activate app to bring popover to front
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
            symbolName = "gauge"
            tintColor = .systemGreen
        case .warning:
            symbolName = "gauge"
            tintColor = .systemYellow
        case .critical:
            symbolName = "gauge"
            tintColor = .systemRed
        case .noAccounts:
            symbolName = "gauge"
            tintColor = .secondaryLabelColor
        }
        
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CodexMonitor")?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
            button.contentTintColor = tintColor
        }
    }
}
