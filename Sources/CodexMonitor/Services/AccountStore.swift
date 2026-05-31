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
    
    // Track which accounts have been notified in the current window
    // Key: account UUID + window seconds, Value: true if notified
    private var notifiedAccounts: [String: Bool] = [:]
    
    // Track which accounts were previously limited (for recovery notifications)
    // Key: account UUID, Value: limit type description (e.g. "5小时", "每周")
    private var previouslyLimitedAccounts: [UUID: String] = [:]
    
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
        
        // Snapshot limited accounts before refresh for recovery detection
        let previousLimitedState = previouslyLimitedAccounts
        
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
        
        // Update limited account tracking and check for recovery
        updateLimitedTracking()
        checkRecoveryNotifications(previousLimited: previousLimitedState)
        
        // Check for usage alerts
        checkUsageAlerts()
        
        // Update status bar icon
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusBarIcon()
        }
    }
    
    // MARK: - Limited Account Tracking
    
    /// Update the currently-limited accounts map from latest usage data
    private func updateLimitedTracking() {
        previouslyLimitedAccounts.removeAll()
        for account in accounts {
            guard case .success(let usage) = usageData[account.id] else { continue }
            if let limitType = resolveLimitType(usage: usage) {
                previouslyLimitedAccounts[account.id] = limitType
            }
        }
    }
    
    /// Resolve the limit type label for a usage response
    private func resolveLimitType(usage: UsageResponse) -> String? {
        // Check rate_limit windows first (has more detail)
        if let rl = usage.rateLimit {
            var types: [String] = []
            if let p = rl.primaryWindow, p.usedPercent >= 100 {
                types.append(limitTypeLabel(seconds: p.limitWindowSeconds))
            }
            if let s = rl.secondaryWindow, s.usedPercent >= 100 {
                let label = limitTypeLabel(seconds: s.limitWindowSeconds)
                if !types.contains(label) { types.append(label) }
            }
            if rl.limitReached && types.isEmpty {
                return L10n.limitReached
            }
            return types.isEmpty ? nil : types.joined(separator: " + ")
        }
        // Fallback to rate_limit_reached_type
        if let reachedType = usage.rateLimitReachedType {
            let type = reachedType.type.lowercased()
            if type.contains("5h") || type.contains("5hour") || type.contains("hour") {
                return L10n.fiveHourLimitReached()
            } else if type.contains("weekly") || type.contains("7d") || type.contains("week") {
                return L10n.weeklyLimitReached()
            }
            return L10n.limitReached
        }
        return nil
    }
    
    private func limitTypeLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return L10n.weeklyLimitReached()
        }
        return L10n.fiveHourLimitReached()
    }
    
    /// Check for accounts that recovered from limited state and send notifications
    private func checkRecoveryNotifications(previousLimited: [UUID: String]) {
        for account in accounts {
            guard let previousType = previousLimited[account.id] else { continue }
            // Was limited before — check if now available
            let currentLimited = previouslyLimitedAccounts[account.id] != nil
            if !currentLimited {
                sendRecoveryNotification(accountName: account.name, limitType: previousType)
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
    
    // MARK: - Usage Alerts
    
    private func checkUsageAlerts() {
        let threshold = UserDefaults.standard.integer(forKey: PreferencesKeys.alertThreshold)
        let alertThreshold = threshold > 0 ? threshold : 80
        
        for account in accounts {
            guard case .success(let usage) = usageData[account.id] else { continue }
            
            var shouldNotify = false
            var usedPercent = 0
            var windowSeconds = 0
            var resetAt = 0
            
            if let rateLimit = usage.rateLimit {
                // Check primary window
                if let primary = rateLimit.primaryWindow, primary.usedPercent >= alertThreshold {
                    let key = "\(account.id.uuidString)_\(primary.limitWindowSeconds)"
                    if notifiedAccounts[key] != true {
                        shouldNotify = true
                        usedPercent = primary.usedPercent
                        windowSeconds = primary.limitWindowSeconds
                        resetAt = primary.resetAt
                        notifiedAccounts[key] = true
                    }
                }
                
                // Check secondary window
                if let secondary = rateLimit.secondaryWindow, secondary.usedPercent >= alertThreshold {
                    let key = "\(account.id.uuidString)_\(secondary.limitWindowSeconds)"
                    if notifiedAccounts[key] != true {
                        shouldNotify = true
                        usedPercent = secondary.usedPercent
                        windowSeconds = secondary.limitWindowSeconds
                        resetAt = secondary.resetAt
                        notifiedAccounts[key] = true
                    }
                }
            }
            
            if shouldNotify {
                sendUsageAlert(
                    accountName: account.name,
                    usedPercent: usedPercent,
                    windowSeconds: windowSeconds,
                    resetAt: resetAt
                )
            }
        }
    }
    
    private func sendUsageAlert(accountName: String, usedPercent: Int, windowSeconds: Int, resetAt: Int) {
        let hours = windowSeconds / 3600
        let windowLabel: String
        if hours >= 168 {
            windowLabel = "Weekly"
        } else if hours >= 24 {
            windowLabel = "\(hours / 24)-day"
        } else {
            windowLabel = "\(hours)-hour"
        }
        
        let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let resetTimeStr = formatter.string(from: resetDate)
        
        let content = UNMutableNotificationContent()
        content.title = "CodexMonitor"
        content.body = "[\(accountName)] \(windowLabel) quota used \(usedPercent)%, resets at \(resetTimeStr)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "usage_alert_\(accountName)_\(windowSeconds)",
            content: content,
            trigger: nil // deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
    
    /// Reset notification tracking (call when a new window cycle begins)
    func resetNotificationTracking(for accountID: UUID, windowSeconds: Int) {
        let key = "\(accountID.uuidString)_\(windowSeconds)"
        notifiedAccounts.removeValue(forKey: key)
    }
}
