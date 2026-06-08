import Foundation
import SwiftUI
import AppKit
import UserNotifications

@MainActor
class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var usageData: [UUID: Result<UsageResponse, APIError>] = [:]
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "saved_accounts"
    private let limitedStateKey = "CodexMonitor.limitedNotificationState.v1"
    private let sentNotificationKeysKey = "CodexMonitor.sentNotificationKeys.v1"
    
    enum OverallStatus {
        case healthy, warning, critical, noAccounts
    }
    
    var overallStatus: OverallStatus {
        guard !accounts.isEmpty else { return .noAccounts }
        
        var hasCritical = false
        var hasWarning = false
        
        for account in accounts {
            if case .success(let usage) = usageData[account.id] {
                if let rateLimit = usage.rateLimit {
                    let primaryUsed = rateLimit.primaryWindow?.usedPercent ?? 0
                    let secondaryUsed = rateLimit.secondaryWindow?.usedPercent ?? 0
                    let maxUsed = max(primaryUsed, secondaryUsed)
                    
                    if rateLimit.limitReached {
                        hasCritical = true
                    } else if maxUsed >= 80 {
                        hasWarning = true
                    }
                } else if usage.rateLimitReachedType != nil {
                    // rate_limit 为 null 但 rate_limit_reached_type 有值，视为限额已达
                    hasCritical = true
                }
            }
        }
        
        if hasCritical { return .critical }
        if hasWarning { return .warning }
        return .healthy
    }
    
    /// Returns the top 2 primary_window.usedPercent values from all accounts, sorted descending
    var topUsagePercentages: [Int] {
        guard !accounts.isEmpty else { return [] }
        
        var percentages: [Int] = []
        for account in accounts {
            if case .success(let usage) = usageData[account.id],
               let primaryPercent = usage.rateLimit?.primaryWindow?.usedPercent {
                percentages.append(primaryPercent)
            }
        }
        
        return percentages.sorted(by: >).prefix(2).map { $0 }
    }
    
    init() {
        loadAccounts()
    }
    
    func loadAccounts() {
        guard let data = userDefaults.data(forKey: accountsKey) else { return }

        do {
            let decoder = JSONDecoder()
            accounts = try decoder.decode([Account].self, from: data)

            // Migrate tokens from Keychain on first run after update
            let accountIDs = accounts.map { $0.id.uuidString }
            SecureTokenStore.migrateFromKeychain(accountIDs: accountIDs)

            // Load tokens from encrypted local storage
            for i in 0..<accounts.count {
                if let token = SecureTokenStore.load(accountID: accounts[i].id.uuidString) {
                    accounts[i].authToken = token
                }
            }

            if enrichAccountIdentitiesFromTokens() {
                saveAccounts()
            }
        } catch {
            print("Failed to load accounts: \(error)")
        }
    }
    
    func saveAccounts() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(accounts)
            userDefaults.set(data, forKey: accountsKey)

            // Save tokens to encrypted local storage
            for account in accounts {
                SecureTokenStore.save(accountID: account.id.uuidString, token: account.authToken)
            }
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }

    @discardableResult
    func enrichAccountIdentitiesFromTokens() -> Bool {
        var changed = false

        for index in accounts.indices {
            let identity = AuthTokenIdentityParser.parse(accessToken: accounts[index].authToken)

            if let accountID = identity.accountID, accounts[index].accountID != accountID {
                accounts[index].accountID = accountID
                changed = true
            }

            if let email = identity.email, accounts[index].accountEmail != email {
                accounts[index].accountEmail = email
                changed = true
            }
        }

        return changed
    }
    
    func addAccount(_ account: Account) {
        accounts.append(account)
        saveAccounts()
    }
    
    func updateAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            saveAccounts()
        }
    }
    
    func deleteAccount(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            SecureTokenStore.delete(accountID: account.id.uuidString)
            usageData.removeValue(forKey: account.id)
        }
        accounts.remove(atOffsets: offsets)
        saveAccounts()
    }
    
    func deleteAccount(id: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            SecureTokenStore.delete(accountID: id.uuidString)
            usageData.removeValue(forKey: id)
            accounts.remove(at: index)
            saveAccounts()
        }
    }
    
    func refreshAll() async {
        guard !accounts.isEmpty else { return }
        
        isLoading = true
        print("[CodexMonitor] refreshAll: refreshing \(accounts.count) accounts")
        
        await withTaskGroup(of: (UUID, Result<UsageResponse, APIError>).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let usage = try await APIService.shared.fetchUsage(authToken: account.authToken)
                        print("[CodexMonitor] refreshAll: [\(account.name)] success — plan=\(usage.planType), rateLimit=\(usage.rateLimit != nil ? "yes" : "nil"), credits=\(usage.credits != nil ? "yes" : "nil")")
                        return (account.id, .success(usage))
                    } catch let error as APIError {
                        print("[CodexMonitor] refreshAll: [\(account.name)] APIError: \(error.localizedDescription)")
                        return (account.id, .failure(error))
                    } catch {
                        print("[CodexMonitor] refreshAll: [\(account.name)] unexpected error: \(error)")
                        return (account.id, .failure(.invalidResponse))
                    }
                }
            }
            
            for await (id, result) in group {
                usageData[id] = result
            }
        }
        
        isLoading = false
        lastRefreshTime = Date()
        
        processUsageNotifications()
        
        // Update status bar icon
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusBarIcon()
        }
    }
    
    // MARK: - Usage Notifications

    private func processUsageNotifications() {
        var sentKeys = loadSentNotificationKeys()
        var nextLimitedState = loadLimitedNotificationState()
        let activeAccountIDs = Set(accounts.map { $0.id.uuidString })
        nextLimitedState = nextLimitedState.filter { activeAccountIDs.contains($0.key) }

        for account in accounts {
            guard case .success(let usage) = usageData[account.id] else { continue }

            let windows = notificationWindows(for: usage)
            let currentLimited = Dictionary(
                uniqueKeysWithValues: windows
                    .filter(\.isLimited)
                    .map { ($0.id, PersistedLimitState(limitType: $0.limitType, resetAt: $0.resetAt)) }
            )

            sendWarningNotificationsIfNeeded(
                account: account,
                windows: windows,
                sentKeys: &sentKeys
            )
            sendLimitReachedNotificationsIfNeeded(
                account: account,
                windows: windows,
                sentKeys: &sentKeys
            )
            sendRecoveryNotificationsIfNeeded(
                account: account,
                previous: nextLimitedState[account.id.uuidString] ?? [:],
                current: currentLimited,
                sentKeys: &sentKeys
            )

            nextLimitedState[account.id.uuidString] = currentLimited.isEmpty ? nil : currentLimited
        }

        saveSentNotificationKeys(sentKeys)
        saveLimitedNotificationState(nextLimitedState)
    }

    private func sendWarningNotificationsIfNeeded(
        account: Account,
        windows: [UsageNotificationWindow],
        sentKeys: inout Set<String>
    ) {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.usageWarningNotificationEnabled) else { return }

        let threshold = UserDefaults.standard.integer(forKey: PreferencesKeys.alertThreshold)
        let alertThreshold = threshold > 0 ? threshold : 80

        for window in windows {
            guard let usedPercent = window.usedPercent,
                  usedPercent >= alertThreshold,
                  usedPercent < 100,
                  !window.isLimited
            else { continue }

            let key = "warning:\(account.id.uuidString):\(window.id):\(window.resetKey):\(alertThreshold)"
            guard !sentKeys.contains(key) else { continue }

            sendUsageWarningNotification(
                accountName: account.name,
                limitType: window.limitType,
                usedPercent: usedPercent,
                resetAt: window.resetAt
            )
            sentKeys.insert(key)
        }
    }

    private func sendLimitReachedNotificationsIfNeeded(
        account: Account,
        windows: [UsageNotificationWindow],
        sentKeys: inout Set<String>
    ) {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.limitNotificationEnabled) else { return }

        for window in windows where window.isLimited {
            let key = "limit:\(account.id.uuidString):\(window.id):\(window.resetKey)"
            guard !sentKeys.contains(key) else { continue }

            sendLimitReachedNotification(
                accountName: account.name,
                limitType: window.limitType,
                resetAt: window.resetAt
            )
            sentKeys.insert(key)
        }
    }

    private func sendRecoveryNotificationsIfNeeded(
        account: Account,
        previous: [String: PersistedLimitState],
        current: [String: PersistedLimitState],
        sentKeys: inout Set<String>
    ) {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.recoveryNotificationEnabled) else { return }

        for (stateID, previousState) in previous where current[stateID] == nil {
            let key = "recovery:\(account.id.uuidString):\(stateID):\(previousState.resetKey)"
            guard !sentKeys.contains(key) else { continue }

            sendRecoveryNotification(accountName: account.name, limitType: previousState.limitType)
            sentKeys.insert(key)
        }
    }

    private func notificationWindows(for usage: UsageResponse) -> [UsageNotificationWindow] {
        var windows: [UsageNotificationWindow] = []

        if let rateLimit = usage.rateLimit {
            let reachedType = usage.rateLimitReachedType?.type.lowercased()
            let primaryUsed = rateLimit.primaryWindow?.usedPercent ?? -1
            let secondaryUsed = rateLimit.secondaryWindow?.usedPercent ?? -1

            if let primary = rateLimit.primaryWindow {
                windows.append(UsageNotificationWindow(
                    id: "primary:\(primary.limitWindowSeconds)",
                    limitType: limitTypeLabel(seconds: primary.limitWindowSeconds),
                    usedPercent: primary.usedPercent,
                    resetAt: primary.resetAt > 0 ? primary.resetAt : nil,
                    isLimited: isWindowLimited(
                        window: primary,
                        rateLimit: rateLimit,
                        reachedType: reachedType,
                        preferredType: "primary",
                        maxUsedPercent: max(primaryUsed, secondaryUsed)
                    )
                ))
            }

            if let secondary = rateLimit.secondaryWindow {
                windows.append(UsageNotificationWindow(
                    id: "secondary:\(secondary.limitWindowSeconds)",
                    limitType: limitTypeLabel(seconds: secondary.limitWindowSeconds),
                    usedPercent: secondary.usedPercent,
                    resetAt: secondary.resetAt > 0 ? secondary.resetAt : nil,
                    isLimited: isWindowLimited(
                        window: secondary,
                        rateLimit: rateLimit,
                        reachedType: reachedType,
                        preferredType: "secondary",
                        maxUsedPercent: max(primaryUsed, secondaryUsed)
                    )
                ))
            }
        }

        if let reachedType = usage.rateLimitReachedType, !windows.contains(where: \.isLimited) {
            windows.append(UsageNotificationWindow(
                id: "reached:\(reachedType.type)",
                limitType: limitTypeLabel(reachedType: reachedType.type),
                usedPercent: 100,
                resetAt: nil,
                isLimited: true
            ))
        }

        if let credits = usage.credits, credits.overageLimitReached {
            windows.append(UsageNotificationWindow(
                id: "credits",
                limitType: L10n.creditsLimitReached,
                usedPercent: nil,
                resetAt: nil,
                isLimited: true
            ))
        }

        if let spendControl = usage.spendControl, spendControl.reached {
            windows.append(UsageNotificationWindow(
                id: "spend-control",
                limitType: L10n.spendLimitReached,
                usedPercent: nil,
                resetAt: nil,
                isLimited: true
            ))
        }

        return windows
    }

    private func isWindowLimited(
        window: WindowUsage,
        rateLimit: RateLimit,
        reachedType: String?,
        preferredType: String,
        maxUsedPercent: Int
    ) -> Bool {
        if window.usedPercent >= 100 { return true }
        guard rateLimit.limitReached else { return false }

        if let reachedType {
            if preferredType == "primary" {
                return reachedType == "primary"
                    || reachedType.contains("5h")
                    || reachedType.contains("5hour")
                    || reachedType.contains("hour")
            }
            return reachedType == "secondary"
                || reachedType.contains("weekly")
                || reachedType.contains("7d")
                || reachedType.contains("week")
        }

        return window.usedPercent == maxUsedPercent
    }

    private func limitTypeLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return L10n.weeklyLimitReached()
        }
        return L10n.fiveHourLimitReached()
    }

    private func limitTypeLabel(reachedType: String) -> String {
        let type = reachedType.lowercased()
        if type.contains("5h") || type.contains("5hour") || type.contains("hour") || type == "primary" {
            return L10n.fiveHourLimitReached()
        }
        if type.contains("weekly") || type.contains("7d") || type.contains("week") || type == "secondary" {
            return L10n.weeklyLimitReached()
        }
        return L10n.limitReached
    }

    private func sendUsageWarningNotification(accountName: String, limitType: String, usedPercent: Int, resetAt: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "CodexMonitor"
        content.body = L10n.usageWarningNotification(
            accountName: accountName,
            limitType: limitType,
            usedPercent: usedPercent,
            resetTime: resetTimeString(resetAt)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage_warning_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[CodexMonitor] Failed to send usage warning notification: \(error)")
            }
        }
    }

    private func sendLimitReachedNotification(accountName: String, limitType: String, resetAt: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "CodexMonitor"
        content.body = L10n.limitReachedNotification(
            accountName: accountName,
            limitType: limitType,
            resetTime: resetTimeString(resetAt)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "limit_reached_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[CodexMonitor] Failed to send limit notification: \(error)")
            }
        }
    }

    private func sendRecoveryNotification(accountName: String, limitType: String) {
        let content = UNMutableNotificationContent()
        content.title = "CodexMonitor"
        content.body = L10n.limitRecovered(accountName: accountName, limitType: limitType)
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "limit_recovered_\(accountName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[CodexMonitor] Failed to send recovery notification: \(error)")
            }
        }
    }

    private func resetTimeString(_ resetAt: Int?) -> String? {
        guard let resetAt, resetAt > 0 else { return nil }
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: resetDate)
    }

    private func loadSentNotificationKeys() -> Set<String> {
        let values = userDefaults.stringArray(forKey: sentNotificationKeysKey) ?? []
        return Set(values)
    }

    private func saveSentNotificationKeys(_ keys: Set<String>) {
        let capped = Array(keys).suffix(500)
        userDefaults.set(Array(capped), forKey: sentNotificationKeysKey)
    }

    private func loadLimitedNotificationState() -> [String: [String: PersistedLimitState]] {
        guard let data = userDefaults.data(forKey: limitedStateKey),
              let decoded = try? JSONDecoder().decode([String: [String: PersistedLimitState]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func saveLimitedNotificationState(_ state: [String: [String: PersistedLimitState]]) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: limitedStateKey)
    }
}

private struct UsageNotificationWindow {
    let id: String
    let limitType: String
    let usedPercent: Int?
    let resetAt: Int?
    let isLimited: Bool

    var resetKey: String {
        resetAt.map(String.init) ?? "unknown"
    }
}

private struct PersistedLimitState: Codable {
    let limitType: String
    let resetAt: Int?

    var resetKey: String {
        resetAt.map(String.init) ?? "unknown"
    }
}
