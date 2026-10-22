import Foundation

/// A ring represents the selected quota period for one account.
struct MenuBarQuotaSnapshot: Equatable {
    enum Level { case healthy, warning, critical, unknown }

    let usedPercent: Int?
    let actualWindow: MenuBarQuotaWindow?

    init(usedPercent: Int?) {
        actualWindow = nil
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
    }

    init(usage: UsageResponse?, preferredWindow: MenuBarQuotaWindow = .fiveHour) {
        guard let usage else {
            usedPercent = nil
            actualWindow = nil
            return
        }
        let windows: [(name: String, value: WindowUsage)] = [
            ("primary", usage.rateLimit?.primaryWindow),
            ("secondary", usage.rateLimit?.secondaryWindow),
            ("tertiary", usage.rateLimit?.tertiaryWindow),
        ].compactMap { name, value in value.map { (name, $0) } }
        let reachedType = usage.rateLimitReachedType?.type.lowercased() ?? ""
        let reachedWindow: MenuBarQuotaWindow?
        if let referenced = windows.first(where: { $0.name == reachedType }) {
            reachedWindow = Self.period(seconds: referenced.value.limitWindowSeconds)
        } else if reachedType.contains("week") || reachedType.contains("7d") || reachedType.contains("seven_day") {
            reachedWindow = .weekly
        } else if reachedType.contains("5h") || reachedType.contains("5_hour") || reachedType.contains("five_hour") {
            reachedWindow = .fiveHour
        } else {
            reachedWindow = nil
        }

        if let selected = windows.first(where: { preferredWindow.matches(seconds: $0.value.limitWindowSeconds) }) {
            actualWindow = preferredWindow
            usedPercent = reachedWindow == preferredWindow ? 100 : min(100, max(0, selected.value.usedPercent))
        } else if reachedWindow == preferredWindow {
            // A period-specific exhausted response is usable even without its percentage window.
            actualWindow = preferredWindow
            usedPercent = 100
        } else if preferredWindow == .weekly,
                  let fiveHour = windows.first(where: { MenuBarQuotaWindow.fiveHour.matches(seconds: $0.value.limitWindowSeconds) }) {
            actualWindow = .fiveHour
            usedPercent = reachedWindow == .fiveHour ? 100 : min(100, max(0, fiveHour.value.usedPercent))
        } else {
            actualWindow = nil
            usedPercent = nil
        }
        // An aggregate limitReached flag may belong to another period; never apply it to this one.
    }

    private static func period(seconds: Int) -> MenuBarQuotaWindow? {
        if MenuBarQuotaWindow.fiveHour.matches(seconds: seconds) { return .fiveHour }
        if MenuBarQuotaWindow.weekly.matches(seconds: seconds) { return .weekly }
        return nil
    }

    var remainingPercent: Int? { usedPercent.map { 100 - $0 } }

    var level: Level {
        guard let remainingPercent else { return .unknown }
        if remainingPercent <= 20 { return .critical }
        if remainingPercent <= 50 { return .warning }
        return .healthy
    }

    func percentage(showRemaining: Bool) -> Int? {
        showRemaining ? remainingPercent : usedPercent
    }
}
