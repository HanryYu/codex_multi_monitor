import SwiftUI
import AppKit

/// Centralized window manager — all extra windows live here instead of as free variables.
final class WindowManager {
    static let shared = WindowManager()

    private var accountManagementWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    var accountStore: AccountStore?

    // MARK: - Account Management Window

    func openAccountManagementWindow() {
        guard let accountStore = accountStore else { return }

        if let existing = accountManagementWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexMonitor - Manage Accounts"
        window.contentView = NSHostingView(rootView: AccountManagementView(accountStore: accountStore))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        accountManagementWindow = window
    }

    func closeAccountManagementWindow() {
        accountManagementWindow?.close()
    }

    // MARK: - Preferences Window

    func openPreferencesWindow() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexMonitor Preferences"
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }
}
