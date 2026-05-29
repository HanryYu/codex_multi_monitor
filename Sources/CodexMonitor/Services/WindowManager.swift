import SwiftUI
import AppKit

/// Centralized window manager — all extra windows live here instead of as free variables.
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?

    var accountStore: AccountStore?

    // MARK: - Unified Settings Window

    func openSettingsWindow(initialTab: UnifiedSettingsView.SettingsTab = .accounts) {
        guard let accountStore = accountStore else { return }

        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.codexMonitorSettings
        window.contentView = NSHostingView(rootView: UnifiedSettingsView(accountStore: accountStore))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
