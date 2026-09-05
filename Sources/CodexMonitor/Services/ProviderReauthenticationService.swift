import Foundation

enum ProviderReauthenticationError: LocalizedError, Sendable {
    case unsupported
    case executableNotFound(String)
    case timedOut(String)
    case loginFailed(String, Int32)
    case credentialsMissing(String)
    case wrongCodexAccount

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This provider does not support in-app reconnection."
        case .executableNotFound(let provider):
            return "\(provider) CLI was not found."
        case .timedOut(let provider):
            return "\(provider) login timed out."
        case .loginFailed(let provider, let status):
            return "\(provider) login failed (exit \(status))."
        case .credentialsMissing(let provider):
            return "\(provider) login completed without usable credentials."
        case .wrongCodexAccount:
            return "A different Codex account was selected. Retry and sign in to the account shown in this row."
        }
    }
}

actor ProviderReauthenticationService {
    static let shared = ProviderReauthenticationService()

    private static let loginTimeout: TimeInterval = 10 * 60

    func reauthenticateCodex(_ account: Account) async throws -> CodexRefreshedCredential {
        guard let executableURL = CodexQuotaActivationService.codexExecutableURL() else {
            throw ProviderReauthenticationError.executableNotFound("Codex")
        }
        let temporaryAuthData = try await Task.detached(priority: .userInitiated) {
            try Self.runCodexLogin(executableURL: executableURL)
        }.value

        guard let bundle = CodexStoredAuthBundle(data: temporaryAuthData) else {
            throw ProviderReauthenticationError.credentialsMissing("Codex")
        }
        guard bundle.matches(accountID: account.accountID),
              AuthTokenIdentityParser.parse(accessToken: bundle.accessToken).accountID?
                .caseInsensitiveCompare(account.accountID ?? "") == .orderedSame
        else {
            throw ProviderReauthenticationError.wrongCodexAccount
        }

        let managedURL = CodexAuthSourceDiscoveryService.appManagedAuthURL(accountID: account.id)
        try FileManager.default.createDirectory(
            at: managedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try temporaryAuthData.write(to: managedURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: managedURL.path
        )
        let selectedData = CodexAuthBundleStore.save(
            accountID: account.id,
            authJSONData: temporaryAuthData
        ) ?? temporaryAuthData
        guard let selected = CodexStoredAuthBundle(data: selectedData) else {
            throw ProviderReauthenticationError.credentialsMissing("Codex")
        }
        return CodexRefreshedCredential(
            accessToken: selected.accessToken,
            authBundleData: selected.data
        )
    }

    func reauthenticateGrok() async throws -> DiscoveredAgentAuth {
        guard let executableURL = Self.grokExecutableURL() else {
            throw ProviderReauthenticationError.executableNotFound("Grok")
        }
        try await Task.detached(priority: .userInitiated) {
            try Self.runLoginProcess(
                executableURL: executableURL,
                arguments: ["login", "--oauth"],
                environment: Self.loginEnvironment(),
                provider: "Grok"
            )
        }.value
        do {
            return try await AgentAuthDiscoveryService.currentGrokCredential()
        } catch {
            throw ProviderReauthenticationError.credentialsMissing("Grok")
        }
    }

    private nonisolated static func runCodexLogin(executableURL: URL) throws -> Data {
        let fileManager = FileManager.default
        let temporaryHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CodexMonitor-Login-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryHome) }
        try "cli_auth_credentials_store = \"file\"\n[analytics]\nenabled = false\n"
            .write(
                to: temporaryHome.appendingPathComponent("config.toml"),
                atomically: true,
                encoding: .utf8
            )

        var environment = loginEnvironment()
        environment["CODEX_HOME"] = temporaryHome.path
        try runLoginProcess(
            executableURL: executableURL,
            arguments: ["login"],
            environment: environment,
            provider: "Codex"
        )

        let authURL = temporaryHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              data.count <= 1_048_576
        else {
            throw ProviderReauthenticationError.credentialsMissing("Codex")
        }
        return data
    }

    private nonisolated static func runLoginProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        provider: String
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        if completed.wait(timeout: .now() + loginTimeout) == .timedOut {
            process.terminate()
            _ = completed.wait(timeout: .now() + 5)
            throw ProviderReauthenticationError.timedOut(provider)
        }
        guard process.terminationStatus == 0 else {
            throw ProviderReauthenticationError.loginFailed(provider, process.terminationStatus)
        }
    }

    private nonisolated static func loginEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CODEX_ACCESS_TOKEN")
        environment.removeValue(forKey: "CODEX_API_KEY")
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/usr/bin",
            "/bin",
            environment["PATH"] ?? "",
        ].joined(separator: ":")
        return environment
    }

    private nonisolated static func grokExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
            "\(home)/.local/bin/grok",
            "\(home)/.grok/bin/grok",
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
