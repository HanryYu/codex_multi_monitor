import Foundation

enum AppGroupConstants {
    static let identifier = "group.com.henry.codex-monitor"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

enum MobilePreferenceKeys {
    static let refreshInterval = "ios.refreshIntervalSeconds"
    static let displayMode = "ios.displayMode"
    static let resetTimeFormat = "ios.resetTimeFormat"
    static let usageWarningNotificationEnabled = "ios.usageWarningNotificationEnabled"
    static let limitNotificationEnabled = "ios.limitNotificationEnabled"
    static let alertThreshold = "ios.alertThreshold"
}

enum WidgetPreferenceStore {
    private static let selectedAccountIDsKey = "widget.selectedAccountIDs"

    static func selectedAccountIDs() -> Set<UUID> {
        let values = AppGroupConstants.defaults.stringArray(forKey: selectedAccountIDsKey) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func saveSelectedAccountIDs(_ ids: Set<UUID>) {
        AppGroupConstants.defaults.set(ids.map(\.uuidString), forKey: selectedAccountIDsKey)
    }

    static func isSelected(_ accountID: UUID) -> Bool {
        selectedAccountIDs().contains(accountID)
    }

    static func setSelected(_ selected: Bool, accountID: UUID) {
        var ids = selectedAccountIDs()
        if selected {
            ids.insert(accountID)
        } else {
            ids.remove(accountID)
        }
        saveSelectedAccountIDs(ids)
    }
}

struct WidgetAccountSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var accountEmail: String?
    var planType: String?
    var primaryUsedPercent: Int?
    var primaryResetAt: Int?
    var primaryWindowSeconds: Int?
    var secondaryUsedPercent: Int?
    var secondaryResetAt: Int?
    var secondaryWindowSeconds: Int?
    var creditsBalance: String?
    var creditsUnlimited: Bool
    var hasCredits: Bool?
    var isLimited: Bool
    var errorMessage: String?
    var refreshedAt: Date?

    var displayName: String {
        if let accountEmail, !accountEmail.isEmpty {
            return accountEmail
        }
        return name
    }

    init(
        id: UUID,
        name: String,
        accountEmail: String?,
        planType: String? = nil,
        primaryUsedPercent: Int? = nil,
        primaryResetAt: Int? = nil,
        primaryWindowSeconds: Int? = nil,
        secondaryUsedPercent: Int? = nil,
        secondaryResetAt: Int? = nil,
        secondaryWindowSeconds: Int? = nil,
        creditsBalance: String? = nil,
        creditsUnlimited: Bool = false,
        hasCredits: Bool? = nil,
        isLimited: Bool = false,
        errorMessage: String? = nil,
        refreshedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.accountEmail = accountEmail
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryResetAt = primaryResetAt
        self.primaryWindowSeconds = primaryWindowSeconds
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryResetAt = secondaryResetAt
        self.secondaryWindowSeconds = secondaryWindowSeconds
        self.creditsBalance = creditsBalance
        self.creditsUnlimited = creditsUnlimited
        self.hasCredits = hasCredits
        self.isLimited = isLimited
        self.errorMessage = errorMessage
        self.refreshedAt = refreshedAt
    }

    init(account: CloudSyncedAccount, result: Result<UsageResponse, APIError>?, refreshedAt: Date?) {
        switch result {
        case .success(let usage):
            self.init(account: account, usage: usage, refreshedAt: refreshedAt)
        case .failure(let error):
            self.init(
                id: account.id,
                name: account.name,
                accountEmail: account.accountEmail,
                errorMessage: error.localizedDescription,
                refreshedAt: refreshedAt
            )
        case .none:
            self.init(
                id: account.id,
                name: account.name,
                accountEmail: account.accountEmail,
                refreshedAt: refreshedAt
            )
        }
    }

    init(account: CloudSyncedAccount, usage: UsageResponse, refreshedAt: Date?) {
        self.init(
            id: account.id,
            name: account.name,
            accountEmail: account.accountEmail,
            planType: usage.planType,
            primaryUsedPercent: usage.rateLimit?.primaryWindow?.usedPercent,
            primaryResetAt: usage.rateLimit?.primaryWindow?.resetAt,
            primaryWindowSeconds: usage.rateLimit?.primaryWindow?.limitWindowSeconds,
            secondaryUsedPercent: usage.rateLimit?.secondaryWindow?.usedPercent,
            secondaryResetAt: usage.rateLimit?.secondaryWindow?.resetAt,
            secondaryWindowSeconds: usage.rateLimit?.secondaryWindow?.limitWindowSeconds,
            creditsBalance: usage.credits?.balance,
            creditsUnlimited: usage.credits?.unlimited ?? false,
            hasCredits: usage.credits?.hasCredits,
            isLimited: UsagePresentation.isRateLimited(usage),
            refreshedAt: refreshedAt
        )
    }
}

enum WidgetSnapshotStore {
    private static let snapshotsKey = "widget.accountSnapshots.v1"
    private static let availableAccountsKey = "widget.availableAccounts.v1"

    static func saveAvailableAccounts(_ accounts: [CloudSyncedAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        AppGroupConstants.defaults.set(data, forKey: availableAccountsKey)
    }

    static func loadAvailableAccounts() -> [CloudSyncedAccount] {
        guard let data = AppGroupConstants.defaults.data(forKey: availableAccountsKey),
              let accounts = try? JSONDecoder().decode([CloudSyncedAccount].self, from: data)
        else { return [] }
        return accounts
    }

    static func saveSnapshots(_ snapshots: [WidgetAccountSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        AppGroupConstants.defaults.set(data, forKey: snapshotsKey)
    }

    static func loadSnapshots() -> [WidgetAccountSnapshot] {
        guard let data = AppGroupConstants.defaults.data(forKey: snapshotsKey),
              let snapshots = try? JSONDecoder().decode([WidgetAccountSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }

    static func saveSnapshot(
        accounts: [CloudSyncedAccount],
        usageData: [UUID: Result<UsageResponse, APIError>],
        refreshedAt: Date?
    ) {
        saveAvailableAccounts(accounts)
        let snapshots = accounts.map {
            WidgetAccountSnapshot(account: $0, result: usageData[$0.id], refreshedAt: refreshedAt)
        }
        saveSnapshots(snapshots)
    }
}
