import Foundation
import AppKit
import UserNotifications

/// 监听 ~/.codex/auth.json 文件变化，自动导入和更新本地账户
@MainActor
final class AuthFileMonitor {
    private let accountStore: AccountStore
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pendingSyncWorkItem: DispatchWorkItem?

    /// auth.json 文件路径
    static let authFilePath: String = {
        NSString("~/.codex/auth.json").expandingTildeInPath
    }()

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
    }

    // MARK: - Public API

    /// 启动文件监听
    func startMonitoring() {
        guard dispatchSource == nil else { return }

        let path = Self.authFilePath
        ensureDirectoryExists()

        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor < 0 {
            // 文件不存在时先尝试创建目录，然后不报错（首次可能还没有 auth.json）
            print("[AuthFileMonitor] auth.json not found at \(path), will watch for creation")
            startDirectoryMonitoring()
            return
        }

        startFileMonitoring(at: path)

        // 首次启动时立即同步一次
        syncFromAuthFile()
    }

    /// 停止文件监听
    func stopMonitoring() {
        pendingSyncWorkItem?.cancel()
        pendingSyncWorkItem = nil
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        dirDispatchSource?.cancel()
        dirDispatchSource = nil
        if dirFileDescriptor >= 0 {
            close(dirFileDescriptor)
            dirFileDescriptor = -1
        }
    }

    // MARK: - Directory Monitoring (when auth.json doesn't exist yet)

    private var dirDispatchSource: DispatchSourceFileSystemObject?
    private var dirFileDescriptor: Int32 = -1

    private func startDirectoryMonitoring() {
        let dirPath = NSString("~/.codex").expandingTildeInPath
        // 确保目录存在
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true,
            attributes: nil
        )

        dirFileDescriptor = open(dirPath, O_EVTONLY)
        guard dirFileDescriptor >= 0 else {
            print("[AuthFileMonitor] Cannot watch directory: \(dirPath)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // 目录变化时检查 auth.json 是否已创建
            let path = AuthFileMonitor.authFilePath
            if FileManager.default.fileExists(atPath: path) {
                self.dirDispatchSource?.cancel()
                self.dirDispatchSource = nil
                if self.dirFileDescriptor >= 0 {
                    close(self.dirFileDescriptor)
                    self.dirFileDescriptor = -1
                }
                self.startMonitoring()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.dirFileDescriptor >= 0 {
                close(self.dirFileDescriptor)
                self.dirFileDescriptor = -1
            }
        }
        dirDispatchSource = source
        source.resume()
    }

    // MARK: - File Monitoring

    private func startFileMonitoring(at path: String) {
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.dispatchSource?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                // auth.json is commonly replaced atomically by tools like CC Switch.
                // A DispatchSource follows the old inode, so recreate it on rename.
                self.restartMonitoring()
            } else {
                self.scheduleSyncFromAuthFile()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()
    }

    private func restartMonitoring() {
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        // 稍等片刻再重新监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let path = AuthFileMonitor.authFilePath
            if FileManager.default.fileExists(atPath: path) {
                self.fileDescriptor = open(path, O_EVTONLY)
                if self.fileDescriptor >= 0 {
                    self.startFileMonitoring(at: path)
                    self.syncFromAuthFile()
                }
            } else {
                // 文件仍不存在，标记所有 localAuth 账户失效
                self.handleFileDeleted()
                // 切回目录监听
                self.startDirectoryMonitoring()
            }
        }
    }

    // MARK: - Sync Logic

    /// 从 auth.json 读取并同步账户
    private func syncFromAuthFile() {
        let path = Self.authFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            handleFileDeleted()
            return
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            print("[AuthFileMonitor] Cannot read auth.json")
            return
        }

        guard let entries = parseAuthEntries(from: data) else {
            print("[AuthFileMonitor] auth.json is not a supported auth format")
            return
        }

        var hasChanges = false

        // 恢复之前因文件删除而失效的账户
        for i in 0..<accountStore.accounts.count {
            if accountStore.accounts[i].source == .localAuth && accountStore.accounts[i].localAuthInvalid {
                accountStore.accounts[i].localAuthInvalid = false
                hasChanges = true
            }
        }

        let remoteAccountIDs = Set(entries.map(\.accountID))
        let remoteEmails = Set(entries.compactMap(\.accountEmail))

        // 更新或添加账户
        for entry in entries {
            let accountID = entry.accountID
            let token = entry.authToken
            if let index = matchingAccountIndex(for: entry) {
                if accountStore.accounts[index].authToken != token {
                    accountStore.accounts[index].authToken = token
                    hasChanges = true
                    print("[AuthFileMonitor] Updated token for local account: \(accountID)")
                }

                if accountStore.accounts[index].accountID != entry.accountID {
                    accountStore.accounts[index].accountID = entry.accountID
                    hasChanges = true
                }

                if let email = entry.accountEmail, accountStore.accounts[index].accountEmail != email {
                    accountStore.accounts[index].accountEmail = email
                    hasChanges = true
                }

                if accountStore.accounts[index].source == .localAuth,
                   accountStore.accounts[index].name.hasPrefix("Codex ") || accountStore.accounts[index].name == accountID {
                    accountStore.accounts[index].name = entry.displayName
                    hasChanges = true
                }

                if accountStore.accounts[index].source == .localAuth && accountStore.accounts[index].localAuthInvalid {
                    accountStore.accounts[index].localAuthInvalid = false
                    hasChanges = true
                }
            } else {
                // 新账户：自动添加
                let newAccount = Account(
                    name: entry.displayName,
                    authToken: token,
                    source: .localAuth,
                    accountID: accountID,
                    accountEmail: entry.accountEmail
                )
                accountStore.accounts.append(newAccount)
                hasChanges = true
                sendNotification(
                    title: "CodexMonitor",
                    body: L10n.localAccountImported(accountName: entry.displayName)
                )
                print("[AuthFileMonitor] Imported new local account: \(accountID)")
            }
        }

        // 移除 auth.json 中不再存在的 localAuth 账户
        let beforeCount = accountStore.accounts.count
        let accountSnapshot = accountStore.accounts
        accountStore.accounts.removeAll { account in
            guard account.source == .localAuth else { return false }
            let accountIDMissing = !remoteAccountIDs.contains(account.accountID ?? "")
            let emailMissing = account.accountEmail.map { !remoteEmails.contains($0) } ?? true
            let duplicatedByManualAccount = accountSnapshot.contains { other in
                other.id != account.id && other.source != .localAuth && identifiersMatch(lhs: account, rhs: other)
            }
            return (accountIDMissing && emailMissing) || duplicatedByManualAccount
        }
        if beforeCount != accountStore.accounts.count {
            hasChanges = true
        }

        if hasChanges {
            accountStore.saveAccounts()
            Task { @MainActor in
                await accountStore.refreshAll()
            }
        }
    }

    /// 文件被删除时标记所有 localAuth 账户失效
    private func handleFileDeleted() {
        var hasChanges = false
        for i in 0..<accountStore.accounts.count {
            if accountStore.accounts[i].source == .localAuth {
                accountStore.accounts[i].localAuthInvalid = true
                hasChanges = true
            }
        }
        if hasChanges {
            accountStore.saveAccounts()
            sendNotification(
                title: "CodexMonitor",
                body: L10n.localAuthFileMissingNotification
            )
            print("[AuthFileMonitor] auth.json deleted, marked local accounts as invalid")
        }
    }

    // MARK: - Helpers

    private func ensureDirectoryExists() {
        let dirPath = NSString("~/.codex").expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "auth_file_monitor_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AuthFileMonitor] Notification error: \(error)")
            }
        }
    }

    private func scheduleSyncFromAuthFile() {
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncFromAuthFile()
        }
        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func parseAuthEntries(from data: Data) -> [LocalAuthEntry]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let root = object as? [String: Any],
           let tokens = root["tokens"] as? [String: Any],
           let accessToken = tokens["access_token"] as? String,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let identity = AuthTokenIdentityParser.parse(
                accessToken: accessToken,
                idToken: tokens["id_token"] as? String
            )
            let accountID = (tokens["account_id"] as? String)
                ?? identity.accountID
                ?? "codex-local-auth"
            let email = identity.email

            return [LocalAuthEntry(
                accountID: accountID,
                accountEmail: email,
                displayName: localAccountDisplayName(accountID: accountID, email: email),
                authToken: accessToken
            )]
        }

        if let legacyEntries = object as? [String: String] {
            let entries = legacyEntries.compactMap { accountID, token -> LocalAuthEntry? in
                let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !accountID.isEmpty, !trimmedToken.isEmpty else { return nil }
                let identity = AuthTokenIdentityParser.parse(accessToken: trimmedToken)
                return LocalAuthEntry(
                    accountID: accountID,
                    accountEmail: identity.email,
                    displayName: localAccountDisplayName(accountID: accountID, email: identity.email),
                    authToken: trimmedToken
                )
            }
            return entries.isEmpty ? nil : entries
        }

        return nil
    }

    private func matchingAccountIndex(for entry: LocalAuthEntry) -> Int? {
        if let email = entry.accountEmail,
           let index = accountStore.accounts.firstIndex(where: { $0.accountEmail == email }) {
            return index
        }

        if let index = accountStore.accounts.firstIndex(where: { $0.accountID == entry.accountID }) {
            return index
        }

        return nil
    }

    private func identifiersMatch(lhs: Account, rhs: Account) -> Bool {
        if let lhsEmail = lhs.accountEmail, let rhsEmail = rhs.accountEmail, lhsEmail == rhsEmail {
            return true
        }
        if let lhsAccountID = lhs.accountID, let rhsAccountID = rhs.accountID, lhsAccountID == rhsAccountID {
            return true
        }
        return false
    }

    private func localAccountDisplayName(accountID: String, email: String?) -> String {
        if let email {
            return email
        }
        let shortID = accountID.count > 8 ? String(accountID.prefix(8)) : accountID
        return "Codex \(shortID)"
    }
}

private struct LocalAuthEntry {
    let accountID: String
    let accountEmail: String?
    let displayName: String
    let authToken: String
}
