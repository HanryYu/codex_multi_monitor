import Foundation

actor CodexQuotaActivationService {
    static let shared = CodexQuotaActivationService()

    enum Availability {
        case ready
        case codexNotFound
    }

    private static let prompt = "Please reply with \"Hi\" directly."
    private static let activationTimeout: TimeInterval = 120
    private var lastActivationAtByAccountID: [String: Date] = [:]

    nonisolated static func availability() -> Availability {
        guard codexExecutableURL() != nil else { return .codexNotFound }
        return .ready
    }

    nonisolated static func isWeeklyRecovery(stateID: String) -> Bool {
        let normalizedStateID = stateID.lowercased()
        return normalizedStateID.hasPrefix("secondary:")
            || normalizedStateID.contains("secondary")
            || normalizedStateID.contains("weekly")
            || normalizedStateID.contains("7d")
            || normalizedStateID.contains("week")
    }

    nonisolated static func hasUsableAuthBundle(for account: Account) -> Bool {
        authBundleData(for: account) != nil
    }

    func activate(account: Account) async {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled) else { return }

        guard let accountID = account.accountID else {
            print("[CodexMonitor] Quota activation skipped: account has no Codex account ID")
            return
        }

        guard let authBundleData = Self.authBundleData(for: account) else {
            print("[CodexMonitor] Quota activation skipped: no full Codex auth bundle saved for " + account.name)
            return
        }

        if let lastActivationAt = lastActivationAtByAccountID[accountID],
           Date().timeIntervalSince(lastActivationAt) < 300 {
            print("[CodexMonitor] Quota activation skipped: account was activated within the last 5 minutes")
            return
        }

        guard let executableURL = Self.codexExecutableURL() else {
            print("[CodexMonitor] Quota activation skipped: Codex CLI was not found")
            return
        }

        let result = await Self.runCodex(
            executableURL: executableURL,
            accountID: accountID,
            authBundleData: authBundleData
        )
        if result.succeeded {
            lastActivationAtByAccountID[accountID] = Date()
            if let refreshedAuthBundleData = result.refreshedAuthBundleData {
                CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshedAuthBundleData)
            }
            print("[CodexMonitor] Quota activation request completed for " + account.name)
        } else {
            print("[CodexMonitor] Quota activation request failed for " + account.name)
        }
    }

    private nonisolated static func authBundleData(for account: Account) -> Data? {
        let autoImportEnabled = UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled)

        if autoImportEnabled,
           let savedData = CodexAuthBundleStore.load(accountID: account.id),
           accountID(fromAuthBundleData: savedData)?.caseInsensitiveCompare(account.accountID ?? "") == .orderedSame {
            return savedData
        }

        guard let accountID = account.accountID,
              let activeAuthData = activeCodexAuthBundleData(),
              Self.accountID(fromAuthBundleData: activeAuthData)?.caseInsensitiveCompare(accountID) == .orderedSame
        else { return nil }

        if autoImportEnabled {
            CodexAuthBundleStore.save(accountID: account.id, authJSONData: activeAuthData)
        }
        return activeAuthData
    }

    private nonisolated static func activeCodexAuthBundleData() -> Data? {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")

        guard let data = try? Data(contentsOf: authURL),
              accountID(fromAuthBundleData: data) != nil
        else {
            return nil
        }

        return data
    }

    private nonisolated static func accountID(fromAuthBundleData data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String,
              !accountID.isEmpty,
              tokens["id_token"] is String,
              tokens["refresh_token"] is String
        else {
            return nil
        }

        return accountID
    }

    private nonisolated static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.bun/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private struct CodexRunResult {
        let succeeded: Bool
        let refreshedAuthBundleData: Data?
    }

    private nonisolated static func runCodex(
        executableURL: URL,
        accountID: String,
        authBundleData: Data
    ) async -> CodexRunResult {
        await Task.detached(priority: .utility) {
            runCodexBlocking(
                executableURL: executableURL,
                accountID: accountID,
                authBundleData: authBundleData
            )
        }.value
    }

    private nonisolated static func runCodexBlocking(
        executableURL: URL,
        accountID: String,
        authBundleData: Data
    ) -> CodexRunResult {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CodexMonitor-QuotaActivation-\(UUID().uuidString)", isDirectory: true)
        let codexHomeDirectory = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
        let workingDirectory = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let authURL = codexHomeDirectory.appendingPathComponent("auth.json")
        let logURL = workingDirectory.appendingPathComponent("codex.log")

        do {
            try fileManager.createDirectory(at: codexHomeDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            try authBundleData.write(to: authURL, options: .atomic)
            _ = fileManager.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            defer {
                try? logHandle.close()
                try? fileManager.removeItem(at: tempRoot)
            }

            let process = Process()
            process.executableURL = executableURL
            process.currentDirectoryURL = workingDirectory
            process.arguments = [
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--color", "never",
                prompt,
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = logHandle
            process.standardError = logHandle

            var environment = ProcessInfo.processInfo.environment
            let requiredPaths = [
                executableURL.deletingLastPathComponent().path,
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
            ]
            let inheritedPath = environment["PATH"].map { [$0] } ?? []
            environment["PATH"] = (requiredPaths + inheritedPath).joined(separator: ":")
            environment["CODEX_HOME"] = codexHomeDirectory.path
            process.environment = environment

            let completion = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in completion.signal() }
            try process.run()

            if completion.wait(timeout: .now() + activationTimeout) == .timedOut {
                process.terminate()
                _ = completion.wait(timeout: .now() + 5)
                return CodexRunResult(succeeded: false, refreshedAuthBundleData: nil)
            }

            let refreshedAuthBundleData = try? Data(contentsOf: authURL)
            let safeRefreshedAuthBundleData: Data?
            if let refreshedAuthBundleData,
               Self.accountID(fromAuthBundleData: refreshedAuthBundleData)?.caseInsensitiveCompare(accountID) == .orderedSame {
                safeRefreshedAuthBundleData = refreshedAuthBundleData
            } else {
                safeRefreshedAuthBundleData = nil
            }

            return CodexRunResult(
                succeeded: process.terminationStatus == 0,
                refreshedAuthBundleData: safeRefreshedAuthBundleData
            )
        } catch {
            print("[CodexMonitor] Failed to launch Codex quota activation: \(error)")
            try? fileManager.removeItem(at: tempRoot)
            return CodexRunResult(succeeded: false, refreshedAuthBundleData: nil)
        }
    }
}
