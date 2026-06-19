import Foundation

final class ICloudAccountSyncStore {
    static let accountPayloadKey = "CodexMonitor.syncedAccounts.v1"

    private let store: NSUbiquitousKeyValueStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    @discardableResult
    func synchronize() -> Bool {
        store.synchronize()
    }

    func loadPayload() -> CloudAccountSyncPayload? {
        guard let data = store.data(forKey: Self.accountPayloadKey) else { return nil }
        return try? decoder.decode(CloudAccountSyncPayload.self, from: data)
    }

    @discardableResult
    func saveAccounts(_ accounts: [CloudSyncedAccount], revision: Date = Date()) -> Date? {
        let payload = CloudAccountSyncPayload(revision: revision, accounts: accounts)
        do {
            let data = try encoder.encode(payload)
            store.set(data, forKey: Self.accountPayloadKey)
            guard store.synchronize() else {
                print("[CodexMonitor] iCloud account sync is unavailable or not permitted for this build.")
                return nil
            }
            return payload.revision
        } catch {
            print("[CodexMonitor] Failed to encode iCloud account payload: \(error)")
            return nil
        }
    }

    @discardableResult
    func observeRemoteChanges(_ handler: @escaping (CloudAccountSyncPayload?) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard Self.notificationTouchesAccountPayload(notification) else { return }
            self.store.synchronize()
            handler(self.loadPayload())
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(observer)
    }

    private static func notificationTouchesAccountPayload(_ notification: Notification) -> Bool {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return true
        }
        return changedKeys.contains(accountPayloadKey)
    }
}
