import Foundation

enum WeeklyQuotaActivationTrigger: Equatable {
    case usageRestored(previousUsedPercent: Int)
    case scheduledCycleDue
    case resetKeyChanged(previousResetKey: String)
    case weeklyWindowMissing

    var marksFullReset: Bool {
        switch self {
        case .usageRestored, .scheduledCycleDue, .weeklyWindowMissing:
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
        case .resetKeyChanged(let previousResetKey):
            return "weekly reset changed from \(previousResetKey)"
        case .weeklyWindowMissing:
            return "weekly window disappeared after its observed reset time"
        }
    }
}

enum WeeklyQuotaActivationPolicy {
    static let missingWindowResetKey = "weekly-window-missing"
    static let cycleDuration: TimeInterval = 7 * 24 * 60 * 60
    static let retryInterval: TimeInterval = 60 * 60

    static func shouldManuallyActivate(
        hasRateLimit: Bool,
        weeklyUsedPercent: Int?
    ) -> Bool {
        guard hasRateLimit else { return false }
        // Manual refresh is an explicit user override. A missing weekly window remains eligible
        // here, while the automatic policy still requires a reliable cycle/reset signal.
        return weeklyUsedPercent == nil || weeklyUsedPercent == 0
    }

    static func triggerForMissingWindow(
        previousResetKey: String?,
        scheduledActivationIsDue: Bool,
        now: TimeInterval
    ) -> WeeklyQuotaActivationTrigger? {
        if scheduledActivationIsDue {
            return .scheduledCycleDue
        }

        guard let previousResetKey,
              previousResetKey != missingWindowResetKey,
              let observedResetAt = TimeInterval(previousResetKey),
              now >= observedResetAt
        else { return nil }

        return .weeklyWindowMissing
    }

    static func wasWaitingForMissingWindowToReturn(_ resetKey: String?) -> Bool {
        resetKey == missingWindowResetKey
    }

    static func shouldBaselineReturnedWindow(
        previousResetKey: String?,
        isPendingVerification: Bool
    ) -> Bool {
        isPendingVerification || wasWaitingForMissingWindowToReturn(previousResetKey)
    }

    static func trigger(
        currentResetKey: String,
        previousResetKey: String?,
        currentUsedPercent: Int?,
        previousUsedPercent: Int?,
        scheduledActivationIsDue: Bool = false
    ) -> WeeklyQuotaActivationTrigger? {
        // Any non-zero value means the account is known to have consumed weekly quota.
        // Never spend more quota merely because a stored timer or reset key changed.
        guard currentUsedPercent == 0 else { return nil }

        if currentUsedPercent == 0,
           let previousUsedPercent,
           previousUsedPercent > 0 {
            return .usageRestored(previousUsedPercent: previousUsedPercent)
        }

        if currentUsedPercent == 0, scheduledActivationIsDue {
            return .scheduledCycleDue
        }

        if currentUsedPercent == 0,
           let previousResetKey,
           previousResetKey != missingWindowResetKey,
           previousResetKey != currentResetKey {
            return .resetKeyChanged(previousResetKey: previousResetKey)
        }

        return nil
    }

    static func nextScheduledActivationTimestamp(after timestamp: TimeInterval) -> TimeInterval {
        timestamp + cycleDuration
    }

    static func verifiedNextActivationTimestamp(
        existing: TimeInterval?,
        observedResetAt: Int?
    ) -> TimeInterval? {
        guard let observedResetAt, observedResetAt > 0 else {
            return existing
        }
        return TimeInterval(observedResetAt)
    }

    static func provisionalManualRefreshNextActivationTimestamp(
        existing: TimeInterval?,
        observedResetAt: Int?,
        now: TimeInterval
    ) -> TimeInterval {
        if let observedResetAt,
           TimeInterval(observedResetAt) > now {
            return TimeInterval(observedResetAt)
        }
        if let existing, existing > now {
            return existing
        }
        return nextScheduledActivationTimestamp(after: now)
    }

    static func nextRetryTimestamp(after timestamp: TimeInterval) -> TimeInterval {
        timestamp + retryInterval
    }

    static func migratedNextActivationTimestamp(
        legacyTimestamp: TimeInterval,
        activationResetKey: String?
    ) -> TimeInterval {
        guard activationResetKey == missingWindowResetKey else {
            return legacyTimestamp
        }
        return legacyTimestamp + cycleDuration - retryInterval
    }
}
