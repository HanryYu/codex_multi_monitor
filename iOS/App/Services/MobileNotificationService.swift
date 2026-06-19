import Foundation
import UserNotifications

enum MobileNotificationService {
    private static let sentKeysKey = "ios.sentNotificationKeys.v1"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func process(accounts: [CloudSyncedAccount], usageData: [UUID: Result<UsageResponse, APIError>]) {
        var sentKeys = Set(AppGroupConstants.defaults.stringArray(forKey: sentKeysKey) ?? [])
        let alertThreshold = max(1, AppGroupConstants.defaults.integer(forKey: MobilePreferenceKeys.alertThreshold))
        let warningEnabled = AppGroupConstants.defaults.bool(forKey: MobilePreferenceKeys.usageWarningNotificationEnabled)
        let limitEnabled = AppGroupConstants.defaults.bool(forKey: MobilePreferenceKeys.limitNotificationEnabled)

        for account in accounts {
            guard case .success(let usage) = usageData[account.id] else { continue }

            if limitEnabled, UsagePresentation.isRateLimited(usage) {
                let key = "limit:\(account.id.uuidString):\(resetKey(for: usage))"
                if !sentKeys.contains(key) {
                    send(
                        title: "Codex Monitor",
                        body: "\(account.displayName) reached a usage limit."
                    )
                    sentKeys.insert(key)
                }
            }

            guard warningEnabled else { continue }
            for usedPercent in usagePercents(for: usage) where usedPercent >= alertThreshold && usedPercent < 100 {
                let key = "warning:\(account.id.uuidString):\(usedPercent):\(resetKey(for: usage)):\(alertThreshold)"
                if !sentKeys.contains(key) {
                    send(
                        title: "Codex Monitor",
                        body: "\(account.displayName) is at \(usedPercent)% usage."
                    )
                    sentKeys.insert(key)
                }
            }
        }

        AppGroupConstants.defaults.set(Array(sentKeys.suffix(500)), forKey: sentKeysKey)
    }

    private static func usagePercents(for usage: UsageResponse) -> [Int] {
        [
            usage.rateLimit?.primaryWindow?.usedPercent,
            usage.rateLimit?.secondaryWindow?.usedPercent,
        ].compactMap { $0 }
    }

    private static func resetKey(for usage: UsageResponse) -> String {
        let values = [
            usage.rateLimit?.primaryWindow?.resetAt,
            usage.rateLimit?.secondaryWindow?.resetAt,
        ].compactMap { $0 }.filter { $0 > 0 }
        return values.map(String.init).joined(separator: "-").ifEmpty("unknown")
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codex-monitor-ios-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
