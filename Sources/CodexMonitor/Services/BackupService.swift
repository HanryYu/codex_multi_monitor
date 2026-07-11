import Foundation
import AppKit

/// Handles export/import of account data for cross-device migration.
/// Export format: JSON file with plaintext tokens (re-encrypted on import with local machine key).
enum BackupService {
    private static let backupVersion = 1

    // MARK: - Data Models

    struct BackupFile: Codable {
        let version: Int
        let exportedAt: Date
        let deviceName: String
        let accounts: [BackupAccount]
    }

    struct BackupAccount: Codable {
        let name: String
        let authToken: String
        let source: AccountSource
        let accountID: String?
        let accountEmail: String?
        let provider: AccountProvider?
    }

    // MARK: - Export

    /// Export all accounts (with decrypted tokens) to a JSON file via save panel.
    @MainActor
    static func exportBackup(from accountStore: AccountStore) {
        guard !accountStore.accounts.isEmpty else { return }

        let backup = BackupFile(
            version: backupVersion,
            exportedAt: Date(),
            deviceName: Host.current().localizedName ?? "Unknown",
            accounts: accountStore.accounts.map { account in
                BackupAccount(
                    name: account.name,
                    authToken: account.authToken,
                    source: account.source,
                    accountID: account.accountID,
                    accountEmail: account.accountEmail,
                    provider: account.provider
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(backup)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "CodexMonitor-backup-\(dateStamp()).json"
            panel.title = "Export Backup"

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    showError("Failed to save backup: \(error.localizedDescription)")
                }
            }
        } catch {
            showError("Failed to create backup: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    /// Import accounts from a JSON backup file via open panel.
    /// Returns import result asynchronously via callback.
    @MainActor
    static func importBackup(into accountStore: AccountStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import Backup"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let backup = try decoder.decode(BackupFile.self, from: data)

                guard backup.version <= backupVersion else {
                    showError("This backup was created by a newer version of CodexMonitor. Please update the app first.")
                    return
                }

                let result = mergeAccounts(from: backup, into: accountStore)

                DispatchQueue.main.async {
                    showImportResult(result)
                }
            } catch {
                showError("Failed to read backup file: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Merge Logic

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let total: Int
    }

    /// Merge backup accounts into the store. Skip duplicates (matched by accountID or email).
    @MainActor
    private static func mergeAccounts(from backup: BackupFile, into accountStore: AccountStore) -> ImportResult {
        var imported = 0
        var skipped = 0

        for backupAccount in backup.accounts {
            // Check for duplicate by accountID
            if let accountID = backupAccount.accountID,
               accountStore.accounts.contains(where: { $0.provider == (backupAccount.provider ?? .codex) && $0.accountID == accountID }) {
                skipped += 1
                continue
            }

            // Check for duplicate by email
            if let email = backupAccount.accountEmail,
               !email.isEmpty,
               accountStore.accounts.contains(where: { $0.provider == (backupAccount.provider ?? .codex) && $0.accountEmail == email }) {
                skipped += 1
                continue
            }

            // Check for duplicate by token
            if accountStore.accounts.contains(where: { $0.authToken == backupAccount.authToken }) {
                skipped += 1
                continue
            }

            let account = Account(
                name: backupAccount.name,
                authToken: backupAccount.authToken,
                source: backupAccount.source,
                accountID: backupAccount.accountID,
                accountEmail: backupAccount.accountEmail,
                provider: backupAccount.provider ?? .codex
            )
            accountStore.addAccount(account)
            imported += 1
        }

        return ImportResult(imported: imported, skipped: skipped, total: backup.accounts.count)
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "CodexMonitor"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @MainActor
    private static func showImportResult(_ result: ImportResult) {
        let alert = NSAlert()
        alert.messageText = "Import Complete"
        if result.imported > 0 {
            alert.informativeText = "Imported \(result.imported) account(s)."
            if result.skipped > 0 {
                alert.informativeText += " Skipped \(result.skipped) duplicate(s)."
            }
            alert.alertStyle = .informational
        } else if result.skipped > 0 {
            alert.informativeText = "All \(result.skipped) account(s) already exist — nothing to import."
            alert.alertStyle = .informational
        } else {
            alert.informativeText = "No accounts found in the backup file."
            alert.alertStyle = .warning
        }
        alert.runModal()
    }
}
