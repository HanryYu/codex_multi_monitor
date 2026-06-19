import Foundation

enum UsageDisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining: return "Remaining"
        case .used: return "Used"
        }
    }
}

enum ResetTimeFormat: String, CaseIterable, Identifiable {
    case relative
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relative: return "Relative"
        case .absolute: return "Time"
        }
    }
}

enum MobileRefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        }
    }
}

enum UsagePresentation {
    static func isRateLimited(_ usage: UsageResponse) -> Bool {
        if usage.rateLimitReachedType != nil { return true }
        if let rateLimit = usage.rateLimit, rateLimit.limitReached { return true }
        if let credits = usage.credits, credits.overageLimitReached { return true }
        if let spendControl = usage.spendControl, spendControl.reached { return true }
        return false
    }

    static func windowLabel(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Quota" }
        let hours = seconds / 3600
        if hours >= 168 { return "Weekly" }
        if hours > 0 { return "\(hours)h" }
        return "Quota"
    }

    static func displayPercent(usedPercent: Int?, mode: UsageDisplayMode) -> Int? {
        guard let usedPercent else { return nil }
        switch mode {
        case .remaining:
            return max(0, 100 - usedPercent)
        case .used:
            return min(100, max(0, usedPercent))
        }
    }

    static func resetText(resetAt: Int?, format: ResetTimeFormat, now: Date = Date()) -> String? {
        guard let resetAt, resetAt > 0 else { return nil }
        let target = Date(timeIntervalSince1970: TimeInterval(resetAt))

        switch format {
        case .absolute:
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: target)
        case .relative:
            let seconds = max(0, Int(target.timeIntervalSince(now)))
            guard seconds > 0 else { return nil }
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(minutes)m"
        }
    }

    static func freshnessText(_ date: Date?) -> String {
        guard let date else { return "Not refreshed" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
