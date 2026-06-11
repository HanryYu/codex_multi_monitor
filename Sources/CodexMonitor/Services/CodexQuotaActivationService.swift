import Foundation

actor CodexQuotaActivationService {
    static let shared = CodexQuotaActivationService()

    enum Availability {
        case ready
        case codexNotFound
        case authUnavailable
    }

    private static let prompt = "Please reply with \"Hi\" directly."
    private static let activationTimeout: TimeInterval = 120
    private var lastActivationAtByAccountID: [String: Date] = [:]

    nonisolated static func availability() -> Availability {
        guard codexExecutableURL() != nil else { return .codexNotFound }
        guard activeCodexAccountID() != nil else { return .authUnavailable }
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

    func activate(account: Account) async {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled) else { return }

        guard let accountID = account.accountID,
              let activeAccountID = Self.activeCodexAccountID(),
              accountID.caseInsensitiveCompare(activeAccountID) == .orderedSame
        else {
            print("[CodexMonitor] Quota activation skipped: recovered account is not the active local Codex account")
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

        let succeeded = await Self.runCodex(executableURL: executableURL)
        if succeeded {
            lastActivationAtByAccountID[accountID] = Date()
            print("[CodexMonitor] Quota activation request completed for " + account.name)
        } else {
            print("[CodexMonitor] Quota activation request failed for " + account.name)
        }
    }

    private nonisolated static func activeCodexAccountID() -> String? {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")

        guard let data = try? Data(contentsOf: authURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String,
              !accountID.isEmpty
        else { return nil }

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

    private nonisolated static func runCodex(executableURL: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            runCodexBlocking(executableURL: executableURL)
        }.value
    }

    private nonisolated static func runCodexBlocking(executableURL: URL) -> Bool {
        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexMonitor-QuotaActivation-\(UUID().uuidString)", isDirectory: true)
        let logURL = workingDirectory.appendingPathComponent("codex.log")

        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = fileManager.createFile(atPath: logURL.path, contents: nil)
            let logHandle = try FileHandle(forWritingTo: logURL)
            defer {
                try? logHandle.close()
                try? fileManager.removeItem(at: workingDirectory)
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
            process.environment = environment

            let completion = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in completion.signal() }
            try process.run()

            if completion.wait(timeout: .now() + activationTimeout) == .timedOut {
                process.terminate()
                _ = completion.wait(timeout: .now() + 5)
                return false
            }

            return process.terminationStatus == 0
        } catch {
            print("[CodexMonitor] Failed to launch Codex quota activation: \(error)")
            try? fileManager.removeItem(at: workingDirectory)
            return false
        }
    }
}
