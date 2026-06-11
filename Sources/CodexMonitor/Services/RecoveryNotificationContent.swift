import UserNotifications

enum RecoveryNotificationContent {
    static func make(accountName: String, limitType: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.recoveryNotificationTitle
        content.body = L10n.limitRecovered(accountName: accountName, limitType: limitType)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = "quota-recovery"
        content.categoryIdentifier = "quota-recovery"
        return content
    }
}
