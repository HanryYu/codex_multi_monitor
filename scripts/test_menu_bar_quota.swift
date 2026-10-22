import AppKit
import Foundation

// The production name lives in PreferencesView; keep this standalone probe UI-independent.
extension Notification.Name {
    static let menuBarTextChanged = Notification.Name("CodexMonitor.menuBarTextChanged")
}

@main
enum MenuBarQuotaTests {
    static func usage(_ percentages: [Int], limited: Bool = false) -> UsageResponse {
        let durations = [5 * 3600, 7 * 86400, 30 * 86400]
        let windows = percentages.enumerated().map { WindowUsage(usedPercent: $0.element, limitWindowSeconds: durations[$0.offset],
                                                     resetAfterSeconds: 100, resetAt: 1000) }
        return UsageResponse(planType: "test", rateLimit: RateLimit(
            allowed: !limited, limitReached: limited,
            primaryWindow: windows.indices.contains(0) ? windows[0] : nil,
            secondaryWindow: windows.indices.contains(1) ? windows[1] : nil,
            tertiaryWindow: windows.indices.contains(2) ? windows[2] : nil))
    }

    static func main() throws {
        let unknown = MenuBarQuotaSnapshot(usage: nil)
        precondition(unknown.level == .unknown && unknown.remainingPercent == nil)
        precondition(MenuBarQuotaSnapshot(usage: usage([])).usedPercent == nil)
        precondition(MenuBarQuotaSnapshot(usage: UsageResponse(planType: "test", rateLimit: nil)).usedPercent == nil)
        precondition(MenuBarQuotaSnapshot(usage: usage([10, 65, 85])).remainingPercent == 90)
        precondition(MenuBarQuotaSnapshot(usage: usage([10, 65, 85]), preferredWindow: .weekly).remainingPercent == 35)
        precondition(MenuBarQuotaSnapshot(usage: usage([0], limited: true)).remainingPercent == 100)
        precondition(MenuBarQuotaSnapshot(usage: UsageResponse(planType: "test", rateLimit: nil,
            rateLimitReachedType: RateLimitReached(type: "weekly")), preferredWindow: .weekly).remainingPercent == 0)
        for (used, level) in [(0, MenuBarQuotaSnapshot.Level.healthy), (49, .healthy),
                              (50, .warning), (79, .warning), (80, .critical), (100, .critical)] {
            let snapshot = MenuBarQuotaSnapshot(usage: usage([used]))
            precondition(snapshot.level == level)
            precondition(snapshot.percentage(showRemaining: false) == used)
            precondition(snapshot.percentage(showRemaining: true) == 100 - used)
        }

        let onlyFiveHour = MenuBarQuotaSnapshot(usage: usage([28]), preferredWindow: .weekly)
        precondition(onlyFiveHour.remainingPercent == 72 && onlyFiveHour.actualWindow == .fiveHour)
        let weeklyExhausted = usage([20, 100], limited: true)
        precondition(MenuBarQuotaSnapshot(usage: weeklyExhausted).remainingPercent == 80)
        precondition(MenuBarQuotaSnapshot(usage: weeklyExhausted, preferredWindow: .weekly).remainingPercent == 0)
        let fiveHourExhausted = usage([100, 20], limited: true)
        precondition(MenuBarQuotaSnapshot(usage: fiveHourExhausted, preferredWindow: .weekly).remainingPercent == 80)
        let fiveHour = WindowUsage(usedPercent: 25, limitWindowSeconds: 18000, resetAfterSeconds: 1, resetAt: 1)
        let week = WindowUsage(usedPercent: 60, limitWindowSeconds: 604800, resetAfterSeconds: 1, resetAt: 1)
        let month = WindowUsage(usedPercent: 90, limitWindowSeconds: 2592000, resetAfterSeconds: 1, resetAt: 1)
        let reversed = UsageResponse(planType: "test", rateLimit: RateLimit(allowed: true, limitReached: false,
            primaryWindow: week, secondaryWindow: fiveHour, tertiaryWindow: month))
        precondition(MenuBarQuotaSnapshot(usage: reversed).remainingPercent == 75)
        precondition(MenuBarQuotaSnapshot(usage: reversed, preferredWindow: .weekly).remainingPercent == 40)
        let typedPrimaryLimit = UsageResponse(planType: "test", rateLimit: reversed.rateLimit,
            rateLimitReachedType: RateLimitReached(type: "primary"))
        precondition(MenuBarQuotaSnapshot(usage: typedPrimaryLimit).remainingPercent == 75)
        precondition(MenuBarQuotaSnapshot(usage: typedPrimaryLimit, preferredWindow: .weekly).remainingPercent == 0)
        let monthOnly = UsageResponse(planType: "test", rateLimit: RateLimit(allowed: true, limitReached: false,
            primaryWindow: month, secondaryWindow: nil))
        precondition(MenuBarQuotaSnapshot(usage: monthOnly).usedPercent == nil)
        precondition(MenuBarQuotaSnapshot(usage: monthOnly, preferredWindow: .weekly).usedPercent == nil)
        let weekOnly = UsageResponse(planType: "test", rateLimit: RateLimit(allowed: true, limitReached: false,
            primaryWindow: nil, secondaryWindow: week))
        precondition(MenuBarQuotaSnapshot(usage: weekOnly).usedPercent == nil)
        precondition(MenuBarQuotaSnapshot(usage: weekOnly, preferredWindow: .weekly).remainingPercent == 40)
        let periodlessLimit = UsageResponse(planType: "test", rateLimit: RateLimit(allowed: false, limitReached: true,
            primaryWindow: nil, secondaryWindow: nil))
        precondition(MenuBarQuotaSnapshot(usage: periodlessLimit).usedPercent == nil)

        // Isolated preference suite: these tests never read or change the user's configuration.
        let suite = "CodexMonitor.RingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID(), deleted = UUID()
        precondition(MenuBarQuotaPreferences.iconStyle(defaults: defaults) == .ring)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [], defaults: defaults).isEmpty)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first], defaults: defaults) == [first])
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first, second], defaults: defaults).isEmpty)
        MenuBarQuotaPreferences.saveAccountIDs([second, first, second, deleted], defaults: defaults)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first, second], defaults: defaults) == [second, first])
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [second], defaults: defaults) == [second])
        MenuBarQuotaPreferences.saveAccountIDs([deleted], defaults: defaults)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first], defaults: defaults).isEmpty)
        MenuBarQuotaPreferences.saveAccountIDs([], defaults: defaults)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first], defaults: defaults).isEmpty)
        defaults.set("invalid JSON", forKey: MenuBarQuotaPreferences.accountIDsKey)
        precondition(MenuBarQuotaPreferences.selectedAccountIDs(available: [first, second], defaults: defaults).isEmpty)

        // Period selection is keyed by account identity, never by row position or a global value.
        precondition(MenuBarQuotaPreferences.quotaWindow(for: first, defaults: defaults) == .fiveHour)
        MenuBarQuotaPreferences.setQuotaWindow(.weekly, for: first, defaults: defaults)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: first, defaults: defaults) == .weekly)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: second, defaults: defaults) == .fiveHour)
        MenuBarQuotaPreferences.saveAccountIDs([second, first], defaults: defaults)
        let firstSnapshot = MenuBarQuotaSnapshot(usage: usage([10, 70]),
            preferredWindow: MenuBarQuotaPreferences.quotaWindow(for: first, defaults: defaults))
        let secondSnapshot = MenuBarQuotaSnapshot(usage: usage([10, 70]),
            preferredWindow: MenuBarQuotaPreferences.quotaWindow(for: second, defaults: defaults))
        precondition(firstSnapshot.remainingPercent == 30 && firstSnapshot.actualWindow == .weekly)
        precondition(secondSnapshot.remainingPercent == 90 && secondSnapshot.actualWindow == .fiveHour)
        MenuBarQuotaPreferences.saveAccountIDs([second], defaults: defaults)
        MenuBarQuotaPreferences.saveAccountIDs([first, second], defaults: defaults)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: first, defaults: defaults) == .weekly)

        MenuBarQuotaPreferences.setQuotaWindow(.fiveHour, for: first, defaults: defaults)
        defaults.set("weekly", forKey: "CodexMonitor.menuBarAppearance.quotaWindow")
        MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: [], defaults: defaults)
        precondition(defaults.string(forKey: "CodexMonitor.menuBarAppearance.quotaWindow") == "weekly")
        MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: [first, second], defaults: defaults)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: first, defaults: defaults) == .fiveHour)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: second, defaults: defaults) == .weekly)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: deleted, defaults: defaults) == .fiveHour)
        precondition(defaults.object(forKey: "CodexMonitor.menuBarAppearance.quotaWindow") == nil)
        MenuBarQuotaPreferences.setQuotaWindow(.fiveHour, for: second, defaults: defaults)
        MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: [first, second], defaults: defaults)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: second, defaults: defaults) == .fiveHour)
        // A fresh defaults instance resolves the same independent settings after relaunch.
        let reopened = UserDefaults(suiteName: suite)!
        precondition(MenuBarQuotaPreferences.quotaWindow(for: first, defaults: reopened) == .fiveHour)
        precondition(MenuBarQuotaPreferences.quotaWindow(for: second, defaults: reopened) == .fiveHour)

        var appearance = MenuBarQuotaAppearance.load(defaults: defaults)
        precondition(appearance.colorMode == .quota && appearance.numberPosition == .trailing)
        appearance.colorMode = .monochrome
        appearance.numberPosition = .inside
        appearance.save(defaults: defaults)
        let savedAppearance = MenuBarQuotaAppearance.load(defaults: defaults)
        precondition(savedAppearance.numberPosition == .inside && savedAppearance.colorMode == .monochrome)
        precondition(savedAppearance.effectiveNumberPosition(iconStyle: .ring) == .inside)
        precondition(savedAppearance.effectiveNumberPosition(iconStyle: .standard) == .trailing)
        appearance.numberPosition = .leading
        precondition(appearance.effectiveNumberPosition(iconStyle: .standard) == .leading)
        defaults.set("custom", forKey: "CodexMonitor.menuBarAppearance.colorMode")
        defaults.set("AA22FF", forKey: "CodexMonitor.menuBarAppearance.customColor")
        defaults.set("123456", forKey: "CodexMonitor.menuBarAppearance.healthyColor")
        let migratedAppearance = MenuBarQuotaAppearance.load(defaults: defaults)
        precondition(migratedAppearance.colorMode == .monochrome)
        migratedAppearance.save(defaults: defaults)
        precondition(defaults.object(forKey: "CodexMonitor.menuBarAppearance.customColor") == nil)
        precondition(defaults.object(forKey: "CodexMonitor.menuBarAppearance.healthyColor") == nil)
        defaults.set("invalid", forKey: "CodexMonitor.menuBarAppearance.numberPosition")
        precondition(MenuBarQuotaAppearance.load(defaults: defaults).numberPosition == .trailing)

        precondition(MenuBarQuotaSnapshot(usedPercent: -10).remainingPercent == 100)
        precondition(MenuBarQuotaSnapshot(usedPercent: 110).remainingPercent == 0)

        if let output = CommandLine.arguments.dropFirst().first {
            try renderPreview(to: output)
        }
        print("Menu bar quota tests passed: window selection, missing data, limits, color boundaries, display mode, account selection, appearance persistence and number positions.")
    }

    static func renderPreview(to output: String) throws {
        _ = NSApplication.shared
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 320,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let inside = CommandLine.arguments.contains("inside")
        var appearance = MenuBarQuotaAppearance()
        if CommandLine.arguments.contains("monochrome") {
            appearance.colorMode = .monochrome
        }
        for row in 0..<2 {
            let dark = row == 0
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : .white).setFill()
                NSRect(x: 0, y: row * 160, width: 1120, height: 160).fill()
                for (column, remaining) in [100, 75, 50, 20, 0, -1].enumerated() {
                    let snapshot = remaining < 0 ? MenuBarQuotaSnapshot(usage: nil)
                        : MenuBarQuotaSnapshot(usage: usage([100 - remaining]))
                    let x = CGFloat(column * 180 + 20), y = CGFloat(row * 160 + 90)
                    for (offset, showRemaining) in [(0.0, true), (-55.0, false)] {
                        let ring = MenuBarQuotaRing.image(snapshot: snapshot, showRemaining: showRemaining, appearance: appearance, showNumberInside: inside)
                        precondition(!ring.isTemplate && ring.size == NSSize(width: inside ? 22 : 18, height: inside ? 22 : 18))
                        ring.draw(in: NSRect(x: x, y: y + offset, width: inside ? 44 : 36, height: inside ? 44 : 36))
                        let value = snapshot.percentage(showRemaining: showRemaining).map { "\($0)%" } ?? "—"
                        let text = "\(value) \(showRemaining ? "left" : "used")" as NSString
                        text.draw(at: NSPoint(x: x + 52, y: y + offset + 7), withAttributes: [
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium),
                            .foregroundColor: dark ? NSColor.white : NSColor.black,
                        ])
                    }
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    }
}
