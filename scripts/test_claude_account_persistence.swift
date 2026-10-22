import Foundation

// Only the backup DTOs are exercised; no account store, files, panels or credentials are accessed.
@MainActor
final class AccountStore {
    var accounts: [Account] = []
    func addAccount(_ account: Account) { accounts.append(account) }
}

@main
struct ClaudeAccountPersistenceTests {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let organization = "11111111-2222-3333-4444-555555555555"
        let account = Account(name: "Cookie fixture", authToken: "sessionKey=synthetic",
                              provider: .claude, isHidden: true, claudeOrganizationID: organization)
        let data = try encoder.encode(account)
        let restored = try decoder.decode(Account.self, from: data)
        precondition(restored.id == account.id, "Ring selections must retain the account UUID")
        precondition(restored.claudeOrganizationID == organization)
        precondition(restored.authToken == account.authToken && restored.provider == .claude && restored.isHidden)

        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "claudeOrganizationID")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyAccount = try decoder.decode(Account.self, from: legacyData)
        precondition(legacyAccount.claudeOrganizationID == nil)
        precondition(legacyAccount.id == account.id && legacyAccount.authToken == account.authToken)

        let synced = CloudSyncedAccount(id: account.id, name: account.name, authToken: account.authToken,
                                        createdAt: account.createdAt, source: account.source.rawValue,
                                        accountID: nil, accountEmail: nil, localAuthInvalid: false,
                                        provider: "claude", isHidden: true,
                                        claudeOrganizationID: organization, updatedAt: Date())
        let cloudData = try encoder.encode(CloudAccountSyncPayload(accounts: [synced]))
        let cloudRestored = try decoder.decode(CloudAccountSyncPayload.self, from: cloudData)
        precondition(cloudRestored.accounts == [synced])
        var legacyCloud = try JSONSerialization.jsonObject(with: encoder.encode(synced)) as! [String: Any]
        legacyCloud.removeValue(forKey: "claudeOrganizationID")
        let legacyCloudAccount = try decoder.decode(CloudSyncedAccount.self,
                                                   from: JSONSerialization.data(withJSONObject: legacyCloud))
        precondition(legacyCloudAccount.claudeOrganizationID == nil && legacyCloudAccount.id == account.id)

        let backup = BackupService.BackupAccount(name: account.name, authToken: account.authToken,
                                                  source: .manual, accountID: nil, accountEmail: nil,
                                                  provider: .claude, isHidden: true, openCodeWorkspaceID: nil,
                                                  claudeOrganizationID: organization)
        let backupData = try encoder.encode(backup)
        let backupRestored = try decoder.decode(BackupService.BackupAccount.self, from: backupData)
        precondition(backupRestored.claudeOrganizationID == organization && backupRestored.authToken == account.authToken)
        var legacyBackup = try JSONSerialization.jsonObject(with: backupData) as! [String: Any]
        legacyBackup.removeValue(forKey: "claudeOrganizationID")
        let legacyBackupAccount = try decoder.decode(BackupService.BackupAccount.self,
                                                    from: JSONSerialization.data(withJSONObject: legacyBackup))
        precondition(legacyBackupAccount.claudeOrganizationID == nil && legacyBackupAccount.provider == .claude)
        print("Claude account persistence tests passed: local/cloud/backup round trips, legacy decoding, stable account UUID and visibility.")
    }
}
