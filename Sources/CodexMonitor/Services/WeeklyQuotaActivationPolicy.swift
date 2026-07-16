import Foundation

enum WeeklyQuotaActivationTrigger: Equatable {
    case usageRestored(previousUsedPercent: Int)
    case fullyReset
    case resetKeyChanged(previousResetKey: String)
    case weeklyWindowMissing

    var marksFullReset: Bool {
        switch self {
        case .usageRestored, .fullyReset, .weeklyWindowMissing:
            return true
        case .resetKeyChanged:
            return false
        }
    }

    var reason: String {
        switch self {
        case .usageRestored(let previousUsedPercent):
            return "weekly usage restored \(previousUsedPercent)% -> 0%"
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
        fullActivationResetKey: String?
    ) -> WeeklyQuotaActivationTrigger? {
        if currentUsedPercent == 0,
           let previousUsedPercent,
           previousUsedPercent > 0 {
            return .usageRestored(previousUsedPercent: previousUsedPercent)
        }

        if currentUsedPercent == 0,
           fullActivationResetKey != currentResetKey {
            return .fullyReset
        }

        if let previousResetKey,
           previousResetKey != currentResetKey {
            return .resetKeyChanged(previousResetKey: previousResetKey)
        }

        return nil
    }
}
