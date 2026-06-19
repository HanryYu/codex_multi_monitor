import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class MobileAccountStore: ObservableObject {
    @Published var accounts: [CloudSyncedAccount] = []
    @Published var usageData: [UUID: Result<UsageResponse, APIError>] = [:]
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    @Published var cloudRevision: Date?

    private let cloudStore = ICloudAccountSyncStore()
    private var cloudObserver: NSObjectProtocol?

    init() {
        registerDefaults()
        loadAccountsFromICloud()
        startCloudObserver()
    }

    deinit {
        if let cloudObserver {
            cloudStore.removeObserver(cloudObserver)
        }
    }

    var sortedSnapshots: [WidgetAccountSnapshot] {
        accounts.map {
            WidgetAccountSnapshot(account: $0, result: usageData[$0.id], refreshedAt: lastRefreshTime)
        }
    }

    var overallUsedPercent: Int? {
        let values = usageData.values.compactMap { result -> Int? in
            guard case .success(let usage) = result else { return nil }
            let primary = usage.rateLimit?.primaryWindow?.usedPercent
            let secondary = usage.rateLimit?.secondaryWindow?.usedPercent
            return [primary, secondary].compactMap { $0 }.max()
        }
        return values.max()
    }

    var hasLimitedAccount: Bool {
        usageData.values.contains { result in
            guard case .success(let usage) = result else { return false }
            return UsagePresentation.isRateLimited(usage)
        }
    }

    func loadAccountsFromICloud() {
        cloudStore.synchronize()
        guard let payload = cloudStore.loadPayload() else {
            accounts = []
            cloudRevision = nil
            WidgetSnapshotStore.saveAvailableAccounts([])
            return
        }

        cloudRevision = payload.revision
        accounts = payload.accounts.sorted { $0.createdAt < $1.createdAt }
        WidgetSnapshotStore.saveAvailableAccounts(accounts)
        reconcileWidgetSelection()
    }

    func refreshAll() async {
        loadAccountsFromICloud()
        guard !accounts.isEmpty else {
            usageData = [:]
            lastRefreshTime = nil
            WidgetSnapshotStore.saveSnapshot(accounts: [], usageData: [:], refreshedAt: nil)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        isLoading = true
        await withTaskGroup(of: (UUID, Result<UsageResponse, APIError>).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let usage = try await APIService.shared.fetchUsage(authToken: account.authToken)
                        return (account.id, .success(usage))
                    } catch let error as APIError {
                        return (account.id, .failure(error))
                    } catch {
                        return (account.id, .failure(.invalidResponse))
                    }
                }
            }

            var nextUsageData: [UUID: Result<UsageResponse, APIError>] = [:]
            for await (id, result) in group {
                nextUsageData[id] = result
            }
            usageData = nextUsageData
        }

        isLoading = false
        lastRefreshTime = Date()
        WidgetSnapshotStore.saveSnapshot(accounts: accounts, usageData: usageData, refreshedAt: lastRefreshTime)
        WidgetCenter.shared.reloadAllTimelines()
        MobileNotificationService.process(accounts: accounts, usageData: usageData)
    }

    func refreshFromWidgetDeepLink() {
        Task {
            await refreshAll()
        }
    }

    private func startCloudObserver() {
        cloudObserver = cloudStore.observeRemoteChanges { [weak self] _ in
            Task { @MainActor in
                self?.loadAccountsFromICloud()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func reconcileWidgetSelection() {
        let existingIDs = Set(accounts.map(\.id))
        var selectedIDs = WidgetPreferenceStore.selectedAccountIDs().intersection(existingIDs)
        if selectedIDs.isEmpty, let first = accounts.first {
            selectedIDs.insert(first.id)
        }
        WidgetPreferenceStore.saveSelectedAccountIDs(selectedIDs)
    }

    private func registerDefaults() {
        AppGroupConstants.defaults.register(defaults: [
            MobilePreferenceKeys.refreshInterval: MobileRefreshInterval.fiveMinutes.rawValue,
            MobilePreferenceKeys.displayMode: UsageDisplayMode.remaining.rawValue,
            MobilePreferenceKeys.resetTimeFormat: ResetTimeFormat.relative.rawValue,
            MobilePreferenceKeys.usageWarningNotificationEnabled: true,
            MobilePreferenceKeys.limitNotificationEnabled: true,
            MobilePreferenceKeys.alertThreshold: 80,
        ])
    }
}
