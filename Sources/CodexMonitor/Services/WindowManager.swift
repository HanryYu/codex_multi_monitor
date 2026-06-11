import SwiftUI
import AppKit

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Centralized window manager — all extra windows live here instead of as free variables.
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?

    var accountStore: AccountStore?

    // MARK: - Unified Settings Window

    func openSettingsWindow(initialTab: UnifiedSettingsView.SettingsTab = .accounts) {
        guard let accountStore = accountStore else { return }

        if let existing = settingsWindow, existing.isVisible {
            existing.contentView = NSHostingView(
                rootView: UnifiedSettingsView(accountStore: accountStore, initialTab: initialTab)
            )
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.codexMonitorSettings
        window.contentView = NSHostingView(
            rootView: UnifiedSettingsView(accountStore: accountStore, initialTab: initialTab)
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
