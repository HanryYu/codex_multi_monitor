import Foundation
import SwiftUI
import AppKit
import UserNotifications

@MainActor
class AccountStore: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var usageData: [UUID: Result<UsageResponse, APIError>] = [:]
    @Published var resetCreditsData: [UUID: Result<RateLimitResetCredits, APIError>] = [:]
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "saved_accounts"
    private let limitedStateKey = "CodexMonitor.limitedNotificationState.v1"
    private let sentNotificationKeysKey = "CodexMonitor.sentNotificationKeys.v1"
    private let scheduledRecoveryNotificationPrefix = "quota_recovery_"
    private let scheduledRecoverySentKeyPrefix = "scheduled-recovery:"
    private let weeklyQuotaActivationStateKey = "CodexMonitor.weeklyQuotaActivationState.v1"
    private let weeklyQuotaFullActivationStateKey = "CodexMonitor.weeklyQuotaFullActivationState.v1"
    private let cloudRevisionKey = "CodexMonitor.iCloudAccountRevision.v1"
    private let cloudSyncStore = ICloudAccountSyncStore()
    private var cloudSyncObserver: NSObjectProtocol?
    private var recoveryNotificationObserver: NSObjectProtocol?
    
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
        reconcileAccountsFromICloudOnLaunch()
        startICloudAccountSync()
        if !accounts.isEmpty {
            publishAccountsToICloud()
        }

        recoveryNotificationObserver = NotificationCenter.default.addObserver(
            forName: .recoveryNotificationEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRecoveryNotificationPreferenceChanged()
            }
        }
    }

    deinit {
        if let cloudSyncObserver {
            cloudSyncStore.removeObserver(cloudSyncObserver)
        }
        if let recoveryNotificationObserver {
            NotificationCenter.default.removeObserver(recoveryNotificationObserver)
        }
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
    
    func saveAccounts(syncToCloud: Bool = true) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(accounts)
            userDefaults.set(data, forKey: accountsKey)

            // Save tokens to encrypted local storage
            for account in accounts {
                SecureTokenStore.save(accountID: account.id.uuidString, token: account.authToken)
            }

            if syncToCloud {
                publishAccountsToICloud()
            }
        } catch {
            print("Failed to save accounts: \(error)")
        }
    }

    private func reconcileAccountsFromICloudOnLaunch() {
        cloudSyncStore.synchronize()
        guard let payload = cloudSyncStore.loadPayload() else { return }

        let lastRevision = userDefaults.object(forKey: cloudRevisionKey) as? Date ?? .distantPast
        if accounts.isEmpty || payload.revision > lastRevision {
            applyCloudPayload(payload)
        }
    }

    private func startICloudAccountSync() {
        cloudSyncObserver = cloudSyncStore.observeRemoteChanges { [weak self] payload in
            Task { @MainActor in
                self?.applyRemoteCloudPayloadIfNewer(payload)
            }
        }
    }

    private func applyRemoteCloudPayloadIfNewer(_ payload: CloudAccountSyncPayload?) {
        guard let payload else { return }
        let lastRevision = userDefaults.object(forKey: cloudRevisionKey) as? Date ?? .distantPast
        guard payload.revision > lastRevision else { return }
        applyCloudPayload(payload)
    }

    private func applyCloudPayload(_ payload: CloudAccountSyncPayload) {
        accounts = payload.accounts
            .sorted { $0.createdAt < $1.createdAt }
            .map { synced in
                Account(
                    id: synced.id,
                    name: synced.name,
                    authToken: synced.authToken,
                    createdAt: synced.createdAt,
                    source: AccountSource(rawValue: synced.source) ?? .manual,
                    accountID: synced.accountID,
                    accountEmail: synced.accountEmail,
                    localAuthInvalid: synced.localAuthInvalid,
                    provider: AccountProvider(rawValue: synced.provider ?? "codex") ?? .codex
                )
            }

        userDefaults.set(payload.revision, forKey: cloudRevisionKey)
        saveAccounts(syncToCloud: false)
    }

    private func publishAccountsToICloud() {
        let revision = Date()
        let syncedAccounts = accounts.map { account in
            CloudSyncedAccount(
                id: account.id,
                name: account.name,
                authToken: account.authToken,
                createdAt: account.createdAt,
                source: account.source.rawValue,
                accountID: account.accountID,
                accountEmail: account.accountEmail,
                localAuthInvalid: account.localAuthInvalid,
                provider: account.provider.rawValue,
                updatedAt: revision
            )
        }

        if let savedRevision = cloudSyncStore.saveAccounts(syncedAccounts, revision: revision) {
            userDefaults.set(savedRevision, forKey: cloudRevisionKey)
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

    func syncLocalAgentAccounts() async {
        let discovered = await AgentAuthDiscoveryService.discover()
        var changed = false

        for auth in discovered {
            if let index = accounts.firstIndex(where: {
                $0.provider == auth.provider && $0.source == .localAuth
            }) {
                if accounts[index].authToken != auth.token {
                    accounts[index].authToken = auth.token
                    changed = true
                }
                if accounts[index].accountEmail != auth.email {
                    accounts[index].accountEmail = auth.email
                    changed = true
                }
                if accounts[index].accountID != auth.accountID {
                    accounts[index].accountID = auth.accountID
                    changed = true
                }
                if accounts[index].localAuthInvalid {
                    accounts[index].localAuthInvalid = false
                    changed = true
                }
            } else {
                accounts.append(Account(
                    name: auth.displayName,
                    authToken: auth.token,
                    source: .localAuth,
                    accountID: auth.accountID,
                    accountEmail: auth.email,
                    provider: auth.provider
                ))
                changed = true
            }
        }

        if changed { saveAccounts() }
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
            CodexAuthBundleStore.delete(accountID: account.id)
            usageData.removeValue(forKey: account.id)
            resetCreditsData.removeValue(forKey: account.id)
            cancelScheduledRecoveryNotifications(for: account.id)
            removeScheduledRecoverySentKeys(for: account.id)
        }
        accounts.remove(atOffsets: offsets)
        saveAccounts()
    }
    
    func deleteAccount(id: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == id }) {
            SecureTokenStore.delete(accountID: id.uuidString)
            CodexAuthBundleStore.delete(accountID: id)
            usageData.removeValue(forKey: id)
            resetCreditsData.removeValue(forKey: id)
            cancelScheduledRecoveryNotifications(for: id)
            removeScheduledRecoverySentKeys(for: id)
            accounts.remove(at: index)
            saveAccounts()
        }
    }
    
    func refreshAll() async {
        if UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled) {
            await syncLocalAgentAccounts()
        }
        guard !accounts.isEmpty else { return }
        
        isLoading = true
        print("[CodexMonitor] refreshAll: refreshing \(accounts.count) accounts")
        
        await withTaskGroup(of: AccountRefreshResult.self) { group in
            for account in accounts {
                group.addTask {
                    let usageResult: Result<UsageResponse, APIError>
                    let resetCreditsResult: Result<RateLimitResetCredits, APIError>

                    do {
                        let usage = try await APIService.shared.fetchUsage(for: account)
                        print("[CodexMonitor] refreshAll: [\(account.name)] success — plan=\(usage.planType), rateLimit=\(usage.rateLimit != nil ? "yes" : "nil"), credits=\(usage.credits != nil ? "yes" : "nil")")
                        usageResult = .success(usage)
                    } catch let error as APIError {
                        print("[CodexMonitor] refreshAll: [\(account.name)] APIError: \(error.localizedDescription)")
                        usageResult = .failure(error)
                    } catch {
                        print("[CodexMonitor] refreshAll: [\(account.name)] unexpected error: \(error)")
                        usageResult = .failure(.invalidResponse)
                    }

                    do {
                        guard account.provider == .codex else {
                            throw APIError.unsupported
                        }
                        let resetCredits = try await APIService.shared.fetchRateLimitResetCredits(
                            authToken: account.authToken,
                            accountID: account.accountID
                        )
                        print("[CodexMonitor] refreshAll: [\(account.name)] reset credits available=\(resetCredits.availableCount)")
                        resetCreditsResult = .success(resetCredits)
                    } catch let error as APIError {
                        print("[CodexMonitor] refreshAll: [\(account.name)] reset credits APIError: \(error.localizedDescription)")
                        resetCreditsResult = .failure(error)
                    } catch {
                        print("[CodexMonitor] refreshAll: [\(account.name)] reset credits unexpected error: \(error)")
                        resetCreditsResult = .failure(.invalidResponse)
                    }

                    return AccountRefreshResult(
                        accountID: account.id,
                        usage: usageResult,
                        resetCredits: resetCreditsResult
                    )
                }
            }
            
            for await result in group {
                usageData[result.accountID] = result.usage
                resetCreditsData[result.accountID] = result.resetCredits
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
        var weeklyQuotaActivationState = loadWeeklyQuotaActivationState()
        var weeklyQuotaFullActivationState = loadWeeklyQuotaFullActivationState()
        let activeAccountIDs = Set(accounts.map { $0.id.uuidString })
        nextLimitedState = nextLimitedState.filter { activeAccountIDs.contains($0.key) }
        weeklyQuotaActivationState = weeklyQuotaActivationState.filter { activeAccountIDs.contains($0.key) }
        weeklyQuotaFullActivationState = weeklyQuotaFullActivationState.filter { activeAccountIDs.contains($0.key) }

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
            scheduleLimitRecoveryNotificationsIfNeeded(
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
            scheduleWeeklyQuotaActivationIfNeeded(
                account: account,
                windows: windows,
                activationState: &weeklyQuotaActivationState,
                fullActivationState: &weeklyQuotaFullActivationState
            )

            nextLimitedState[account.id.uuidString] = currentLimited.isEmpty ? nil : currentLimited
        }

        saveSentNotificationKeys(sentKeys)
        saveLimitedNotificationState(nextLimitedState)
        saveWeeklyQuotaActivationState(weeklyQuotaActivationState)
        saveWeeklyQuotaFullActivationState(weeklyQuotaFullActivationState)
    }

    private func handleRecoveryNotificationPreferenceChanged() {
        if userDefaults.bool(forKey: PreferencesKeys.recoveryNotificationEnabled) {
            scheduleRecoveryNotificationsForCurrentUsage()
        } else {
            cancelScheduledRecoveryNotifications()
            removeScheduledRecoverySentKeys()
        }
    }

    private func scheduleRecoveryNotificationsForCurrentUsage() {
        var sentKeys = loadSentNotificationKeys()

        for account in accounts {
            guard case .success(let usage) = usageData[account.id] else { continue }
            scheduleLimitRecoveryNotificationsIfNeeded(
                account: account,
                windows: notificationWindows(for: usage),
                sentKeys: &sentKeys
            )
        }

        saveSentNotificationKeys(sentKeys)
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

    private func scheduleLimitRecoveryNotificationsIfNeeded(
        account: Account,
        windows: [UsageNotificationWindow],
        sentKeys: inout Set<String>
    ) {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.recoveryNotificationEnabled) else { return }

        for window in windows where window.isLimited {
            guard let resetAt = window.resetAt, resetAt > 0 else { continue }

            let key = scheduledRecoverySentKey(
                accountID: account.id,
                stateID: window.id,
                resetKey: window.resetKey
            )
            guard !sentKeys.contains(key) else { continue }

            scheduleRecoveryNotification(
                accountID: account.id,
                accountName: account.name,
                limitType: window.limitType,
                stateID: window.id,
                resetAt: resetAt
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
        for (stateID, previousState) in previous where current[stateID] == nil {
            let key = "recovery:\(account.id.uuidString):\(stateID):\(previousState.resetKey)"
            guard !sentKeys.contains(key) else { continue }

            cancelScheduledRecoveryNotification(
                accountID: account.id,
                stateID: stateID,
                resetKey: previousState.resetKey
            )

            let scheduledKey = scheduledRecoverySentKey(
                accountID: account.id,
                stateID: stateID,
                resetKey: previousState.resetKey
            )
            let scheduledRecoveryWasQueued = sentKeys.contains(scheduledKey)
            let hasFixedRecoveryTime = previousState.resetAt != nil

            if UserDefaults.standard.bool(forKey: PreferencesKeys.recoveryNotificationEnabled),
               hasFixedRecoveryTime,
               !scheduledRecoveryWasQueued {
                sendRecoveryNotification(accountName: account.name, limitType: previousState.limitType)
            }

            if CodexQuotaActivationService.isWeeklyRecovery(stateID: stateID) {
                Task {
                    await CodexQuotaActivationService.shared.activate(account: account)
                }
            }

            sentKeys.insert(key)
        }
    }

    private func scheduleWeeklyQuotaActivationIfNeeded(
        account: Account,
        windows: [UsageNotificationWindow],
        activationState: inout [String: String],
        fullActivationState: inout [String: String]
    ) {
        guard account.provider == .codex else { return }
        guard let weeklyWindow = windows.first(where: {
            CodexQuotaActivationService.isWeeklyRecovery(stateID: $0.id)
        }) else { return }

        let currentResetKey = weeklyWindow.resetKey
        guard currentResetKey != "unknown" else { return }

        let accountKey = account.id.uuidString
        let previousResetKey = activationState[accountKey]
        let weeklyQuotaFullyReset = weeklyWindow.usedPercent == 0

        if weeklyQuotaFullyReset, fullActivationState[accountKey] != currentResetKey {
            switch requestWeeklyQuotaActivation(
                account: account,
                currentResetKey: currentResetKey,
                reason: "weekly quota is fully reset"
            ) {
            case .scheduled:
                activationState[accountKey] = currentResetKey
                fullActivationState[accountKey] = currentResetKey
            case .disabled:
                activationState[accountKey] = currentResetKey
            case .missingAuthBundle:
                break
            }
            return
        }

        guard previousResetKey != currentResetKey else { return }

        guard let previousResetKey else {
            activationState[accountKey] = currentResetKey
            return
        }

        switch requestWeeklyQuotaActivation(
            account: account,
            currentResetKey: currentResetKey,
            reason: "\(previousResetKey) -> \(currentResetKey)"
        ) {
        case .scheduled:
            activationState[accountKey] = currentResetKey
        case .disabled:
            activationState[accountKey] = currentResetKey
        case .missingAuthBundle:
            return
        }
    }

    private func requestWeeklyQuotaActivation(
        account: Account,
        currentResetKey: String,
        reason: String
    ) -> WeeklyQuotaActivationScheduleResult {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled) else {
            return .disabled
        }

        guard CodexQuotaActivationService.hasUsableAuthBundle(for: account) else {
            print("[CodexMonitor] Weekly quota activation pending for \(account.name): missing full Codex auth bundle")
            return .missingAuthBundle
        }

        Task {
            await CodexQuotaActivationService.shared.activate(account: account)
        }
        print("[CodexMonitor] Weekly quota activation scheduled for \(account.name): \(reason), resetKey=\(currentResetKey)")
        return .scheduled
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
        guard rateLimit.limitReached else { return false }

        // When reachedType is available, use it to determine which window is actually limited.
        // Weekly limit takes priority — if weekly is hit, 5-hour is no longer relevant.
        if let reachedType {
            if preferredType == "primary" {
                // Only mark primary as limited if reachedType explicitly says primary/5h
                return reachedType == "primary"
                    || reachedType.contains("5h")
                    || reachedType.contains("5hour")
                    || reachedType.contains("hour")
            } else {
                // Only mark secondary as limited if reachedType explicitly says secondary/weekly
                return reachedType == "secondary"
                    || reachedType.contains("weekly")
                    || reachedType.contains("7d")
                    || reachedType.contains("week")
            }
        }

        // Fallback: no reachedType info — mark window as limited if at 100%
        return window.usedPercent >= 100
    }

    private func limitTypeLabel(seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 168 {
            return L10n.weeklyLimit()
        }
        return L10n.hourlyLimit(hours: max(hours, 1))
    }

    private func limitTypeLabel(reachedType: String) -> String {
        let type = reachedType.lowercased()
        if type.contains("5h") || type.contains("5hour") || type.contains("hour") || type == "primary" {
            return L10n.hourlyLimit(hours: 5)
        }
        if type.contains("weekly") || type.contains("7d") || type.contains("week") || type == "secondary" {
            return L10n.weeklyLimit()
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

    private func sendRecoveryNotification(accountName: String, limitType: String) {
        let content = RecoveryNotificationContent.make(accountName: accountName, limitType: limitType)

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

    private func scheduleRecoveryNotification(
        accountID: UUID,
        accountName: String,
        limitType: String,
        stateID: String,
        resetAt: Int
    ) {
        let recoveryDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let timeInterval = max(recoveryDate.timeIntervalSinceNow, 1)
        let content = RecoveryNotificationContent.make(accountName: accountName, limitType: limitType)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: scheduledRecoveryNotificationIdentifier(
                accountID: accountID,
                stateID: stateID,
                resetKey: String(resetAt)
            ),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[CodexMonitor] Failed to schedule recovery notification: \(error)")
            } else {
                print("[CodexMonitor] Scheduled recovery notification for \(accountName) at \(recoveryDate)")
            }
        }
    }

    private func cancelScheduledRecoveryNotification(accountID: UUID, stateID: String, resetKey: String) {
        let identifier = scheduledRecoveryNotificationIdentifier(
            accountID: accountID,
            stateID: stateID,
            resetKey: resetKey
        )
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func cancelScheduledRecoveryNotifications(for accountID: UUID? = nil) {
        let prefix: String
        if let accountID {
            prefix = "\(scheduledRecoveryNotificationPrefix)\(accountID.uuidString)_"
        } else {
            prefix = scheduledRecoveryNotificationPrefix
        }

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }

            if !identifiers.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    private func scheduledRecoveryNotificationIdentifier(
        accountID: UUID,
        stateID: String,
        resetKey: String
    ) -> String {
        let safeStateID = stateID
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(scheduledRecoveryNotificationPrefix)\(accountID.uuidString)_\(safeStateID)_\(resetKey)"
    }

    private func scheduledRecoverySentKey(accountID: UUID, stateID: String, resetKey: String) -> String {
        "\(scheduledRecoverySentKeyPrefix)\(accountID.uuidString):\(stateID):\(resetKey)"
    }

    private func removeScheduledRecoverySentKeys(for accountID: UUID? = nil) {
        let prefix: String
        if let accountID {
            prefix = "\(scheduledRecoverySentKeyPrefix)\(accountID.uuidString):"
        } else {
            prefix = scheduledRecoverySentKeyPrefix
        }

        let filtered = loadSentNotificationKeys().filter { !$0.hasPrefix(prefix) }
        saveSentNotificationKeys(filtered)
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

    private func loadWeeklyQuotaActivationState() -> [String: String] {
        userDefaults.dictionary(forKey: weeklyQuotaActivationStateKey) as? [String: String] ?? [:]
    }

    private func saveWeeklyQuotaActivationState(_ state: [String: String]) {
        userDefaults.set(state, forKey: weeklyQuotaActivationStateKey)
    }

    private func loadWeeklyQuotaFullActivationState() -> [String: String] {
        userDefaults.dictionary(forKey: weeklyQuotaFullActivationStateKey) as? [String: String] ?? [:]
    }

    private func saveWeeklyQuotaFullActivationState(_ state: [String: String]) {
        userDefaults.set(state, forKey: weeklyQuotaFullActivationStateKey)
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

private enum WeeklyQuotaActivationScheduleResult {
    case scheduled
    case disabled
    case missingAuthBundle
}

private struct AccountRefreshResult {
    let accountID: UUID
    let usage: Result<UsageResponse, APIError>
    let resetCredits: Result<RateLimitResetCredits, APIError>
}
