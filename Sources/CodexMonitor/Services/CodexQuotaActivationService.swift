import Foundation

enum CodexQuotaActivationResult: Sendable, Equatable {
    case succeeded
    case automaticDisabled
    case missingAccountID
    case missingCredentials
    case alreadyInProgress
    case codexNotFound
    case timedOut
    case launchFailed
    case commandFailed(exitStatus: Int32)
    case unexpectedReply

    var succeeded: Bool { self == .succeeded }
}

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
        (await activateDetailed(
            account: account,
            allowWhenAutomaticActivationIsDisabled: allowWhenAutomaticActivationIsDisabled
        )).succeeded
    }

    func activateDetailed(
        account: Account,
        allowWhenAutomaticActivationIsDisabled: Bool = false
    ) async -> CodexQuotaActivationResult {
        guard allowWhenAutomaticActivationIsDisabled
                || UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled)
        else {
            WeeklyQuotaLogger.log("activation skipped account=\(account.name) reason=automatic-disabled")
            return .automaticDisabled
        }

        guard let accountID = account.accountID else {
            WeeklyQuotaLogger.log("activation skipped account=\(account.name) reason=missing-account-id")
            return .missingAccountID
        }

        guard let authBundleData = Self.authBundleData(for: account) else {
            WeeklyQuotaLogger.log("activation skipped account=\(account.name) reason=missing-auth-bundle")
            return .missingCredentials
        }

        guard !activatingAccountIDs.contains(accountID) else {
            WeeklyQuotaLogger.log("activation skipped account=\(account.name) reason=already-in-progress")
            return .alreadyInProgress
        }

        guard let executableURL = Self.codexExecutableURL() else {
            WeeklyQuotaLogger.log("activation skipped account=\(account.name) reason=codex-cli-not-found")
            return .codexNotFound
        }

        activatingAccountIDs.insert(accountID)
        defer { activatingAccountIDs.remove(accountID) }
        WeeklyQuotaLogger.log("activation started account=\(account.name) cli=\(executableURL.path)")

        let result = await Self.runCodex(
            executableURL: executableURL,
            accountID: accountID,
            authBundleData: authBundleData,
            model: nil
        )
        if result.outcome.succeeded {
            if let refreshedAuthBundleData = result.refreshedAuthBundleData {
                CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshedAuthBundleData)
            }
            WeeklyQuotaLogger.log(
                "activation completed account=\(account.name) exitStatus=\(result.exitStatus) durationMs=\(result.durationMilliseconds) reply=\(result.lastMessageSummary)"
            )
            return .succeeded
        } else {
            WeeklyQuotaLogger.log(
                "activation failed account=\(account.name) exitStatus=\(result.exitStatus) durationMs=\(result.durationMilliseconds) reply=\(result.lastMessageSummary) output=\(result.outputSummary)"
            )
            return result.outcome
        }
    }

    func refreshFiveHourQuota(account: Account, model: String?) async -> CodexQuotaActivationResult {
        guard let accountID = account.accountID else {
            WeeklyQuotaLogger.log("5-hour refresh skipped account=\(account.name) reason=missing-account-id")
            return .missingAccountID
        }
        guard let authBundleData = Self.authBundleData(for: account) else {
            WeeklyQuotaLogger.log("5-hour refresh skipped account=\(account.name) reason=missing-auth-bundle")
            return .missingCredentials
        }
        guard let executableURL = Self.codexExecutableURL() else {
            WeeklyQuotaLogger.log("5-hour refresh skipped account=\(account.name) reason=codex-cli-not-found")
            return .codexNotFound
        }

        guard !activatingAccountIDs.contains(accountID) else {
            WeeklyQuotaLogger.log(
                "5-hour refresh skipped account=\(account.name) reason=already-in-progress"
            )
            return .alreadyInProgress
        }

        activatingAccountIDs.insert(accountID)
        defer { activatingAccountIDs.remove(accountID) }
        WeeklyQuotaLogger.log("5-hour refresh started account=\(account.name) cli=\(executableURL.path)")
        let result = await Self.runCodex(
            executableURL: executableURL,
            accountID: accountID,
            authBundleData: authBundleData,
            model: model
        )
        if result.outcome.succeeded, let refreshed = result.refreshedAuthBundleData {
            CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshed)
        }
        if result.outcome.succeeded {
            WeeklyQuotaLogger.log(
                "5-hour refresh completed account=\(account.name) exitStatus=\(result.exitStatus) durationMs=\(result.durationMilliseconds)"
            )
        } else {
            WeeklyQuotaLogger.log(
                "5-hour refresh failed account=\(account.name) exitStatus=\(result.exitStatus) durationMs=\(result.durationMilliseconds) reply=\(result.lastMessageSummary) output=\(result.outputSummary)"
            )
        }
        return result.outcome
    }

    nonisolated static func authBundleData(for account: Account) -> Data? {
        let candidates = CodexAuthSourceDiscoveryService.candidates(
            for: account,
            savedBundleData: CodexAuthBundleStore.load(accountID: account.id)
        )
        guard let candidate = candidates.first else { return nil }
        return CodexAuthBundleStore.save(
            accountID: account.id,
            authJSONData: candidate.bundle.data
        ) ?? candidate.bundle.data
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
        let outcome: CodexQuotaActivationResult
        let refreshedAuthBundleData: Data?
        let exitStatus: Int32
        let durationMilliseconds: Int
        let lastMessageSummary: String
        let outputSummary: String
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
        let lastMessageURL = workingDirectory.appendingPathComponent("last-message.txt")
        let startedAt = Date()

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
                "--color", "never",
                "--output-last-message", lastMessageURL.path
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
                return CodexRunResult(
                    outcome: .timedOut,
                    refreshedAuthBundleData: nil,
                    exitStatus: -1,
                    durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                    lastMessageSummary: "<timeout>",
                    outputSummary: safeOutputSummary(at: logURL)
                )
            }

            let refreshedAuthBundleData = try? Data(contentsOf: authURL)
            let safeRefreshedAuthBundleData: Data?
            if let refreshedAuthBundleData,
               Self.accountID(fromAuthBundleData: refreshedAuthBundleData)?.caseInsensitiveCompare(accountID) == .orderedSame {
                safeRefreshedAuthBundleData = refreshedAuthBundleData
            } else {
                safeRefreshedAuthBundleData = nil
            }

            let lastMessage = (try? String(contentsOf: lastMessageURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let receivedExpectedReply = lastMessage.caseInsensitiveCompare("hi") == .orderedSame
            let outcome: CodexQuotaActivationResult
            if process.terminationStatus != 0 {
                outcome = .commandFailed(exitStatus: process.terminationStatus)
            } else if !receivedExpectedReply {
                outcome = .unexpectedReply
            } else {
                outcome = .succeeded
            }

            return CodexRunResult(
                outcome: outcome,
                refreshedAuthBundleData: safeRefreshedAuthBundleData,
                exitStatus: process.terminationStatus,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                lastMessageSummary: safeTextSummary(lastMessage),
                outputSummary: safeOutputSummary(at: logURL)
            )
        } catch {
            WeeklyQuotaLogger.log("activation launch failed error=\(error.localizedDescription)")
            try? fileManager.removeItem(at: tempRoot)
            return CodexRunResult(
                outcome: .launchFailed,
                refreshedAuthBundleData: nil,
                exitStatus: -1,
                durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                lastMessageSummary: "<launch-failed>",
                outputSummary: safeTextSummary(error.localizedDescription)
            )
        }
    }

    private nonisolated static func safeOutputSummary(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.suffix(2_000), encoding: .utf8)
        else { return "<none>" }
        return safeTextSummary(text)
    }

    private nonisolated static func safeTextSummary(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                token.count > 120 ? "<redacted>" : String(token)
            }
            .joined(separator: " ")
        return normalized.isEmpty ? "<empty>" : String(normalized.prefix(800))
    }
}
