import Foundation

actor CodexQuotaActivationService {
    static let shared = CodexQuotaActivationService()

    enum Availability {
        case ready
        case codexNotFound
    }

    private static let prompt = "Reply only: hi"
    private static let activationTimeout: TimeInterval = 120
    private var activatingAccountIDs: Set<String> = []

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

    @discardableResult
    func activate(
        account: Account,
        allowWhenAutomaticActivationIsDisabled: Bool = false
    ) async -> Bool {
        guard allowWhenAutomaticActivationIsDisabled
                || UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled)
        else { return false }

        guard let accountID = account.accountID else {
            print("[CodexMonitor] Quota activation skipped: account has no Codex account ID")
            return false
        }

        guard let authBundleData = Self.authBundleData(for: account) else {
            print("[CodexMonitor] Quota activation skipped: no full Codex auth bundle saved for " + account.name)
            return false
        }

        guard !activatingAccountIDs.contains(accountID) else {
            print("[CodexMonitor] Quota activation skipped: request already in progress for " + account.name)
            return false
        }

        guard let executableURL = Self.codexExecutableURL() else {
            print("[CodexMonitor] Quota activation skipped: Codex CLI was not found")
            return false
        }

        activatingAccountIDs.insert(accountID)
        defer { activatingAccountIDs.remove(accountID) }

        let result = await Self.runCodex(
            executableURL: executableURL,
            accountID: accountID,
            authBundleData: authBundleData,
            model: nil
        )
        if result.succeeded {
            if let refreshedAuthBundleData = result.refreshedAuthBundleData {
                CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshedAuthBundleData)
            }
            print("[CodexMonitor] Quota activation request completed for " + account.name)
            return true
        } else {
            print("[CodexMonitor] Quota activation request failed for " + account.name)
            return false
        }
    }

    func refreshFiveHourQuota(account: Account, model: String?) async {
        guard let accountID = account.accountID,
              let authBundleData = Self.authBundleData(for: account),
              let executableURL = Self.codexExecutableURL() else { return }
        let result = await Self.runCodex(
            executableURL: executableURL,
            accountID: accountID,
            authBundleData: authBundleData,
            model: model
        )
        if result.succeeded, let refreshed = result.refreshedAuthBundleData {
            CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshed)
        }
    }

    private nonisolated static func authBundleData(for account: Account) -> Data? {
        let autoImportEnabled = UserDefaults.standard.bool(forKey: PreferencesKeys.autoImportEnabled)

        // Auto import controls whether new local credentials are captured. A bundle that was
        // already captured belongs to this saved account and remains usable for activation.
        if let savedData = CodexAuthBundleStore.load(accountID: account.id),
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

    nonisolated static func codexExecutableURL() -> URL? {
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
        authBundleData: Data,
        model: String?
    ) async -> CodexRunResult {
        await Task.detached(priority: .utility) {
            runCodexBlocking(
                executableURL: executableURL,
                accountID: accountID,
                authBundleData: authBundleData,
                model: model
            )
        }.value
    }

    private nonisolated static func runCodexBlocking(
        executableURL: URL,
        accountID: String,
        authBundleData: Data,
        model: String?
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
            var arguments = [
                "exec",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--color", "never"
            ]
            if let model, !model.isEmpty { arguments.append(contentsOf: ["--model", model]) }
            arguments.append(contentsOf: ["--config", "model_reasoning_effort=\"low\"", prompt])
            process.arguments = arguments
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
