import Foundation

enum WeeklyQuotaActivationTrigger: Equatable {
    case usageRestored(previousUsedPercent: Int)
    case scheduledCycleDue
    case fullyReset
    case resetKeyChanged(previousResetKey: String)
    case weeklyWindowMissing

    var marksFullReset: Bool {
        switch self {
        case .usageRestored, .scheduledCycleDue, .fullyReset, .weeklyWindowMissing:
            return true
        case .resetKeyChanged:
            return false
        }
    }

    var reason: String {
        switch self {
        case .usageRestored(let previousUsedPercent):
            return "weekly usage restored \(previousUsedPercent)% -> 0%"
        case .scheduledCycleDue:
            return "stored seven-day weekly cycle is due"
        case .fullyReset:
            return "weekly quota is fully reset"
        case .resetKeyChanged(let previousResetKey):
            return "weekly reset changed from \(previousResetKey)"
        case .weeklyWindowMissing:
            return "weekly window disappeared after official reset"
        }
    }
}

enum WeeklyQuotaActivationPolicy {
    static let missingWindowResetKey = "weekly-window-missing"
    static let cycleDuration: TimeInterval = 7 * 24 * 60 * 60

    static func shouldManuallyActivate(
        hasRateLimit: Bool,
        weeklyUsedPercent: Int?
    ) -> Bool {
        guard hasRateLimit else { return false }
        return weeklyUsedPercent == nil || weeklyUsedPercent == 0
    }

    static func triggerForMissingWindow(
        previousResetKey: String?
    ) -> WeeklyQuotaActivationTrigger? {
        guard previousResetKey != missingWindowResetKey else { return nil }
        return .weeklyWindowMissing
    }

    static func wasWaitingForMissingWindowToReturn(_ resetKey: String?) -> Bool {
        resetKey == missingWindowResetKey
    }

    static func trigger(
        currentResetKey: String,
        previousResetKey: String?,
        currentUsedPercent: Int?,
        previousUsedPercent: Int?,
        fullActivationResetKey: String?,
        scheduledActivationIsDue: Bool = false
    ) -> WeeklyQuotaActivationTrigger? {
        if currentUsedPercent == 0,
           let previousUsedPercent,
           previousUsedPercent > 0 {
            return .usageRestored(previousUsedPercent: previousUsedPercent)
        }

        if currentUsedPercent == 0, scheduledActivationIsDue {
            return .scheduledCycleDue
        }

        if currentUsedPercent == 0,
           fullActivationResetKey != currentResetKey {
            return .fullyReset
        }

        if currentUsedPercent == 0,
           let previousResetKey,
           previousResetKey != currentResetKey {
            return .resetKeyChanged(previousResetKey: previousResetKey)
        }

        return nil
    }

    static func nextScheduledActivationTimestamp(after timestamp: TimeInterval) -> TimeInterval {
        timestamp + cycleDuration
    }
}
