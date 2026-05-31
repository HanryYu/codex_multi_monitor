import Foundation
import AppKit
import UserNotifications

/// 监听 ~/.codex/auth.json 文件变化，自动导入和更新本地账户
@MainActor
final class AuthFileMonitor {
    private let accountStore: AccountStore
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

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
            if flags.contains(.delete) || flags.contains(.revoke) {
                // 文件被删除或撤销
                self.handleFileDeleted()
                // 重新打开文件（macOS 上 DispatchSource 需要重新创建）
                self.restartMonitoring()
            } else {
                // 文件内容变化
                self.syncFromAuthFile()
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

        // auth.json 格式: { "account_id_key": "bearer_token", ... }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            print("[AuthFileMonitor] auth.json is not valid JSON dict")
            return
        }

        // 恢复之前因文件删除而失效的账户
        for i in 0..<accountStore.accounts.count {
            if accountStore.accounts[i].source == .localAuth && accountStore.accounts[i].localAuthInvalid {
                accountStore.accounts[i].localAuthInvalid = false
            }
        }

        // 收集当前 auth.json 中的 accountID
        let remoteAccountIDs = Set(entries.keys)

        // 更新或添加账户
        for (accountID, token) in entries {
            if let index = accountStore.accounts.firstIndex(where: { $0.source == .localAuth && $0.accountID == accountID }) {
                // 已存在：检查 token 是否变化
                if accountStore.accounts[index].authToken != token {
                    accountStore.accounts[index].authToken = token
                    accountStore.accounts[index].localAuthInvalid = false
                    print("[AuthFileMonitor] Updated token for local account: \(accountID)")
                }
            } else {
                // 新账户：自动添加
                let newAccount = Account(
                    name: accountID,
                    authToken: token,
                    source: .localAuth,
                    accountID: accountID
                )
                accountStore.accounts.append(newAccount)
                sendNotification(
                    title: "CodexMonitor",
                    body: "已自动导入本地账户: \(accountID)"
                )
                print("[AuthFileMonitor] Imported new local account: \(accountID)")
            }
        }

        // 移除 auth.json 中不再存在的 localAuth 账户
        accountStore.accounts.removeAll { account in
            account.source == .localAuth && !remoteAccountIDs.contains(account.accountID ?? "")
        }

        accountStore.saveAccounts()
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
                body: "~/.codex/auth.json 已删除，本地导入账户已标记为失效"
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
}
