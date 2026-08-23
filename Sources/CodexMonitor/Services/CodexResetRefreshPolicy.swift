import Foundation

enum CodexResetRefreshPolicy {
    /// Radar data is refreshed on demand when the menu opens, never by background polling.
    // Keep the Observatory snapshot reasonably fresh without polling in the background.
    static let refreshInterval: TimeInterval = 3 * 60
    static let failedRetryInterval: TimeInterval = 15 * 60

    static func shouldRefresh(
        lastSuccessfulAt: Date?,
        lastAttemptAt: Date?,
        now: Date = Date()
    ) -> Bool {
        if let lastSuccessfulAt,
           now.timeIntervalSince(lastSuccessfulAt) < refreshInterval {
            return false
        }
        if let lastAttemptAt,
           now.timeIntervalSince(lastAttemptAt) < failedRetryInterval {
            return false
        }
        return true
    }
}
