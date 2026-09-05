import Foundation

enum CodexAuthBundleStore {
    private static let keyPrefix = "codex_auth_bundle:"

    @discardableResult
    static func save(accountID: UUID, authJSONData: Data) -> Data? {
        let preferredData = CodexStoredAuthBundle.preferred(
            existing: load(accountID: accountID),
            candidate: authJSONData
        )
        guard let jsonString = String(data: preferredData, encoding: .utf8) else { return nil }
        SecureTokenStore.save(accountID: storageKey(for: accountID), token: jsonString)
        return preferredData
    }

    static func load(accountID: UUID) -> Data? {
        guard let jsonString = SecureTokenStore.load(accountID: storageKey(for: accountID)) else {
            return nil
        }
        return Data(jsonString.utf8)
    }

    static func delete(accountID: UUID) {
        SecureTokenStore.delete(accountID: storageKey(for: accountID))
    }

    private static func storageKey(for accountID: UUID) -> String {
        "\(keyPrefix)\(accountID.uuidString)"
    }
}
