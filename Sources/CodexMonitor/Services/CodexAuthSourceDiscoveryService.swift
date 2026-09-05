import Foundation

struct CodexAuthSourceCandidate: Sendable {
    enum Source: String, Sendable {
        case savedBundle
        case activeCodexHome
        case appManagedHome
        case paseoProfile
        case ccSwitch
    }

    let bundle: CodexStoredAuthBundle
    let source: Source
    let writableURL: URL?
}

enum CodexAuthSourceDiscoveryService {
    private static let maximumAuthBytes = 1_048_576
    private static let maximumConfigBytes = 2_097_152
    private static let maximumDatabaseOutputBytes = 16_777_216

    static func candidates(
        for account: Account,
        savedBundleData: Data?
    ) -> [CodexAuthSourceCandidate] {
        guard let accountID = account.accountID, !accountID.isEmpty else { return [] }

        var candidates: [CodexAuthSourceCandidate] = []
        var seenPaths: Set<String> = []

        if let savedBundleData,
           let bundle = CodexStoredAuthBundle(data: savedBundleData),
           bundle.matches(accountID: accountID) {
            candidates.append(CodexAuthSourceCandidate(
                bundle: bundle,
                source: .savedBundle,
                writableURL: nil
            ))
        }

        for authURL in codexAuthFileURLs() {
            let standardizedPath = authURL.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted,
                  let data = readBoundedFile(authURL, maximumBytes: maximumAuthBytes),
                  let bundle = CodexStoredAuthBundle(data: data),
                  bundle.matches(accountID: accountID)
            else { continue }

            candidates.append(CodexAuthSourceCandidate(
                bundle: bundle,
                source: source(for: authURL),
                writableURL: authURL
            ))
        }

        candidates.append(contentsOf: ccSwitchCandidates(accountID: accountID))
        return candidates.sorted(by: isPreferred)
    }

    static func appManagedAuthURL(accountID: UUID) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexMonitor/AuthHomes", isDirectory: true)
            .appendingPathComponent(accountID.uuidString, isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    static func writeBack(
        refreshedData: Data,
        to candidate: CodexAuthSourceCandidate,
        expectedRefreshToken: String
    ) {
        guard let url = candidate.writableURL,
              let refreshedBundle = CodexStoredAuthBundle(data: refreshedData),
              let currentData = readBoundedFile(url, maximumBytes: maximumAuthBytes),
              let currentBundle = CodexStoredAuthBundle(data: currentData),
              currentBundle.matches(accountID: refreshedBundle.accountID)
        else { return }

        // Compare-and-swap: never overwrite a credential another process already rotated.
        guard currentBundle.refreshToken == expectedRefreshToken else { return }
        let preferredData = CodexStoredAuthBundle.preferred(
            existing: currentData,
            candidate: refreshedData
        )
        guard preferredData != currentData else { return }

        do {
            try preferredData.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            WeeklyQuotaLogger.log(
                "credential source writeback failed source=\(candidate.source.rawValue) error=\(safeMessage(error.localizedDescription))"
            )
        }
    }

    private static func codexAuthFileURLs() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var urls: [URL] = []

        if let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !configuredHome.isEmpty {
            urls.append(URL(fileURLWithPath: configuredHome, isDirectory: true)
                .appendingPathComponent("auth.json"))
        }
        urls.append(home.appendingPathComponent(".codex/auth.json"))

        let managedHomes = home.appendingPathComponent(
            "Library/Application Support/CodexMonitor/AuthHomes",
            isDirectory: true
        )
        if let accountDirectories = try? fileManager.contentsOfDirectory(
            at: managedHomes,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for directory in accountDirectories.prefix(200) {
                urls.append(directory.appendingPathComponent("auth.json"))
            }
        }

        let paseoConfigURL = home.appendingPathComponent(".paseo/config.json")
        if let data = readBoundedFile(paseoConfigURL, maximumBytes: maximumConfigBytes),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agents = root["agents"] as? [String: Any],
           let providers = agents["providers"] as? [String: Any] {
            for value in providers.values {
                guard let provider = value as? [String: Any],
                      let environment = provider["env"] as? [String: Any],
                      let codexHome = environment["CODEX_HOME"] as? String,
                      !codexHome.isEmpty
                else { continue }
                urls.append(URL(fileURLWithPath: codexHome, isDirectory: true)
                    .appendingPathComponent("auth.json"))
            }
        }

        let profilesRoot = home.appendingPathComponent(
            ".paseo/plugin-data/codex-account-watch/profiles",
            isDirectory: true
        )
        if let profileDirectories = try? fileManager.contentsOfDirectory(
            at: profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for directory in profileDirectories.prefix(200) {
                urls.append(directory
                    .appendingPathComponent("home", isDirectory: true)
                    .appendingPathComponent("auth.json"))
            }
        }

        return urls
    }

    private static func ccSwitchCandidates(accountID: String) -> [CodexAuthSourceCandidate] {
        let databaseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db")
        guard FileManager.default.isReadableFile(atPath: databaseURL.path),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3")
        else { return [] }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-json",
            databaseURL.path,
            "SELECT settings_config FROM providers WHERE app_type = 'codex' LIMIT 200;",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  data.count <= maximumDatabaseOutputBytes,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }

            return rows.compactMap { row in
                guard let settings = row["settings_config"] as? String,
                      let settingsData = settings.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
                      let auth = (object["auth"] as? [String: Any]) ?? object as [String: Any]?,
                      let authData = try? JSONSerialization.data(withJSONObject: auth),
                      let bundle = CodexStoredAuthBundle(data: authData),
                      bundle.matches(accountID: accountID)
                else { return nil }
                return CodexAuthSourceCandidate(
                    bundle: bundle,
                    source: .ccSwitch,
                    writableURL: nil
                )
            }
        } catch {
            return []
        }
    }

    private static func readBoundedFile(_ url: URL, maximumBytes: Int) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              size.intValue <= maximumBytes
        else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func isPreferred(
        _ lhs: CodexAuthSourceCandidate,
        _ rhs: CodexAuthSourceCandidate
    ) -> Bool {
        let preferred = CodexStoredAuthBundle.preferred(
            existing: rhs.bundle.data,
            candidate: lhs.bundle.data
        )
        if preferred == lhs.bundle.data, preferred != rhs.bundle.data { return true }
        if preferred == rhs.bundle.data, preferred != lhs.bundle.data { return false }
        return sourceRank(lhs.source) < sourceRank(rhs.source)
    }

    private static func sourceRank(_ source: CodexAuthSourceCandidate.Source) -> Int {
        switch source {
        case .appManagedHome: return 0
        case .activeCodexHome: return 1
        case .paseoProfile: return 2
        case .savedBundle: return 3
        case .ccSwitch: return 4
        }
    }

    private static func isPaseoProfile(_ url: URL) -> Bool {
        url.path.contains("/.paseo/plugin-data/codex-account-watch/profiles/")
    }

    private static func source(for url: URL) -> CodexAuthSourceCandidate.Source {
        if url.path.contains("/Library/Application Support/CodexMonitor/AuthHomes/") {
            return .appManagedHome
        }
        if isPaseoProfile(url) { return .paseoProfile }
        return .activeCodexHome
    }

    private static func safeMessage(_ value: String) -> String {
        String(value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .prefix(240))
    }
}
