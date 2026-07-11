import Foundation

struct CloudSyncedAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var authToken: String
    var createdAt: Date
    var source: String
    var accountID: String?
    var accountEmail: String?
    var localAuthInvalid: Bool
    var provider: String? = nil
    var updatedAt: Date

    var displayName: String {
        if let accountEmail, !accountEmail.isEmpty {
            return accountEmail
        }
        return name
    }
}

struct CloudAccountSyncPayload: Codable, Equatable {
    var version: Int
    var revision: Date
    var accounts: [CloudSyncedAccount]

    init(version: Int = 1, revision: Date = Date(), accounts: [CloudSyncedAccount]) {
        self.version = version
        self.revision = revision
        self.accounts = accounts
    }
}
