import Foundation

struct DiscoveredAgentAuth: Sendable {
    let provider: AccountProvider
    let token: String
    let email: String?
    let accountID: String?

    var displayName: String {
        if let email, !email.isEmpty { return email }
        return provider.displayName
    }
}

enum ClaudeCredentialStorage: Sendable, Equatable {
    case file(URL)
    case keychain
}

struct ClaudeStoredCredentials: Sendable, Equatable {
    let data: Data
    let storage: ClaudeCredentialStorage
}

struct ClaudeTokenRefreshResponse: Decodable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum ClaudeAuthDiscoveryError: LocalizedError, Sendable {
    case missingCredentials
    case invalidCredentials
    case invalidRefreshResponse
    case refreshRejected(statusCode: Int)
    case allRefreshEndpointsFailed
    case credentialEncodingFailed
    case fileReadFailed(code: Int)
    case fileWriteFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Claude credentials were not found."
        case .invalidCredentials: return "Claude credentials could not be decoded."
        case .invalidRefreshResponse: return "Claude returned an invalid token refresh response."
        case .refreshRejected(let statusCode): return "Claude rejected token refresh (HTTP \(statusCode))."
        case .allRefreshEndpointsFailed: return "Claude token refresh could not reach a supported endpoint."
        case .credentialEncodingFailed: return "Claude credentials could not be encoded."
        case .fileReadFailed(let code): return "Claude credential file read failed (code \(code))."
        case .fileWriteFailed(let code): return "Claude credential file write failed (code \(code))."
        }
    }

    var isExpectedAbsence: Bool {
        if case .missingCredentials = self { return true }
        return false
    }
}

struct ClaudeAuthDependencies: @unchecked Sendable {
    let read: @Sendable () async throws -> ClaudeStoredCredentials?
    let write: @Sendable (ClaudeStoredCredentials) async throws -> Void
    let refresh: @Sendable (String) async throws -> ClaudeTokenRefreshResponse
    let accountEmail: @Sendable () -> String?

    static let live = ClaudeAuthDependencies(
        read: {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fileURL = home.appendingPathComponent(".claude/.credentials.json")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    return ClaudeStoredCredentials(
                        data: try Data(contentsOf: fileURL),
                        storage: .file(fileURL)
                    )
                } catch {
                    throw ClaudeAuthDiscoveryError.fileReadFailed(code: (error as NSError).code)
                }
            }

            guard let data = try NonInteractiveKeychain.copyGenericPassword(
                service: "Claude Code-credentials"
            ) else { return nil }
            return ClaudeStoredCredentials(data: data, storage: .keychain)
        },
        write: { stored in
            switch stored.storage {
            case .file(let url):
                do {
                    try stored.data.write(to: url, options: [.atomic])
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: url.path
                    )
                } catch {
                    throw ClaudeAuthDiscoveryError.fileWriteFailed(code: (error as NSError).code)
                }
            case .keychain:
                try NonInteractiveKeychain.updateGenericPassword(
                    stored.data,
                    service: "Claude Code-credentials"
                )
            }
        },
        refresh: { refreshToken in
            try await ClaudeOAuthClient.refresh(refreshToken: refreshToken)
        },
        accountEmail: {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = root["oauthAccount"] as? [String: Any]
            else { return nil }
            return account["emailAddress"] as? String ?? account["email"] as? String
        }
    )
}

struct ClaudeAuthConfiguration: Sendable {
    var successfulCacheTTL: TimeInterval = 5 * 60
    var failureBackoff: TimeInterval = 15 * 60
    var expirationLeeway: TimeInterval = 60
}

struct ClaudeCredentialResolution: Sendable {
    let credential: DiscoveredAgentAuth
    let persistenceErrorDescription: String?
}

actor ClaudeCredentialCoordinator {
    static let shared = ClaudeCredentialCoordinator(dependencies: .live)

    private struct OAuth: Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    private struct Snapshot: Sendable {
        let stored: ClaudeStoredCredentials
        let oauth: OAuth
        let credential: DiscoveredAgentAuth
    }

    private struct Attempt: Sendable {
        let snapshot: Snapshot
        let pendingPersistence: PendingPersistence?
        let persistenceErrorDescription: String?
    }

    private struct Cache: Sendable {
        let snapshot: Snapshot
        let validUntil: Date
    }

    private struct PendingPersistence: Sendable {
        let baseline: ClaudeStoredCredentials
        let rotated: ClaudeStoredCredentials
    }

    private let dependencies: ClaudeAuthDependencies
    private let configuration: ClaudeAuthConfiguration
    private var cache: Cache?
    private var retryAfter: Date?
    private var pendingPersistence: PendingPersistence?
    private var inFlight: Task<Attempt, Error>?

    init(
        dependencies: ClaudeAuthDependencies,
        configuration: ClaudeAuthConfiguration = ClaudeAuthConfiguration()
    ) {
        self.dependencies = dependencies
        self.configuration = configuration
    }

    func credential(now: Date = Date()) async throws -> ClaudeCredentialResolution {
        if let cache, now < cache.validUntil {
            return ClaudeCredentialResolution(credential: cache.snapshot.credential, persistenceErrorDescription: nil)
        }
        if let retryAfter, now < retryAfter {
            if let cache, cache.snapshot.oauth.expiresAt.map({ $0 > now }) ?? true {
                return ClaudeCredentialResolution(credential: cache.snapshot.credential, persistenceErrorDescription: nil)
            }
            throw ClaudeAuthDiscoveryError.missingCredentials
        }
        if let inFlight {
            let attempt = try await inFlight.value
            return ClaudeCredentialResolution(
                credential: attempt.snapshot.credential,
                persistenceErrorDescription: attempt.persistenceErrorDescription
            )
        }

        let dependencies = self.dependencies
        let configuration = self.configuration
        let pending = pendingPersistence
        let task = Task {
            try await Self.performAttempt(
                dependencies: dependencies,
                configuration: configuration,
                pendingPersistence: pending,
                now: now
            )
        }
        inFlight = task

        do {
            let attempt = try await task.value
            inFlight = nil
            retryAfter = attempt.persistenceErrorDescription == nil
                ? nil
                : now.addingTimeInterval(configuration.failureBackoff)
            pendingPersistence = attempt.pendingPersistence
            cache = Cache(
                snapshot: attempt.snapshot,
                validUntil: Self.cacheDeadline(
                    oauth: attempt.snapshot.oauth,
                    now: now,
                    configuration: configuration
                )
            )
            return ClaudeCredentialResolution(
                credential: attempt.snapshot.credential,
                persistenceErrorDescription: attempt.persistenceErrorDescription
            )
        } catch {
            inFlight = nil
            retryAfter = now.addingTimeInterval(configuration.failureBackoff)
            // During failure backoff discovery returns no replacement. The
            // account store therefore keeps its existing token, while an
            // expired or unreadable cached document is never surfaced again.
            cache = nil
            throw error
        }
    }

    private static func performAttempt(
        dependencies: ClaudeAuthDependencies,
        configuration: ClaudeAuthConfiguration,
        pendingPersistence: PendingPersistence?,
        now: Date
    ) async throws -> Attempt {
        let stored: ClaudeStoredCredentials
        var nextPending = pendingPersistence
        var persistenceError: String?

        if let pendingPersistence {
            do {
                guard let current = try await dependencies.read() else {
                    let retained = try makeSnapshot(
                        stored: pendingPersistence.rotated,
                        accountEmail: dependencies.accountEmail()
                    )
                    if retained.oauth.expiresAt.map({ $0 <= now }) ?? false {
                        throw ClaudeAuthDiscoveryError.missingCredentials
                    }
                    return Attempt(
                        snapshot: retained,
                        pendingPersistence: pendingPersistence,
                        persistenceErrorDescription: "Claude credential persistence retry was deferred because current storage is unavailable."
                    )
                }
                if current == pendingPersistence.rotated {
                    stored = current
                    nextPending = nil
                } else if current == pendingPersistence.baseline {
                    stored = pendingPersistence.rotated
                } else {
                    // Claude Code changed credentials after our failed write.
                    // Adopt that external state and never overwrite it with stale rotation data.
                    stored = current
                    nextPending = nil
                }
            } catch {
                let retained = try makeSnapshot(
                    stored: pendingPersistence.rotated,
                    accountEmail: dependencies.accountEmail()
                )
                if retained.oauth.expiresAt.map({ $0 <= now }) ?? false {
                    throw ClaudeAuthDiscoveryError.missingCredentials
                }
                return Attempt(
                    snapshot: retained,
                    pendingPersistence: pendingPersistence,
                    persistenceErrorDescription: "Claude credential persistence retry was deferred because current storage could not be read non-interactively."
                )
            }
        } else {
            guard let loaded = try await dependencies.read() else {
                throw ClaudeAuthDiscoveryError.missingCredentials
            }
            stored = loaded
        }

        var snapshot = try makeSnapshot(stored: stored, accountEmail: dependencies.accountEmail())

        if shouldRefresh(snapshot.oauth, now: now, leeway: configuration.expirationLeeway) {
            guard let refreshToken = snapshot.oauth.refreshToken, !refreshToken.isEmpty else {
                throw ClaudeAuthDiscoveryError.invalidCredentials
            }
            let refreshed = try await dependencies.refresh(refreshToken)
            let refreshedStored = try replacingOAuth(
                in: stored,
                response: refreshed,
                previousRefreshToken: refreshToken,
                now: now
            )
            snapshot = try makeSnapshot(stored: refreshedStored, accountEmail: dependencies.accountEmail())
            nextPending = PendingPersistence(
                baseline: nextPending?.baseline ?? stored,
                rotated: refreshedStored
            )
        }

        if let toPersist = nextPending {
            do {
                try await dependencies.write(toPersist.rotated)
                nextPending = nil
            } catch {
                // Keep the rotated document in memory so later retries never fall
                // back to an invalidated refresh token from disk or Keychain.
                persistenceError = error.localizedDescription
            }
        }

        return Attempt(
            snapshot: snapshot,
            pendingPersistence: nextPending,
            persistenceErrorDescription: persistenceError
        )
    }

    private static func makeSnapshot(
        stored: ClaudeStoredCredentials,
        accountEmail: String?
    ) throws -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: stored.data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty
        else { throw ClaudeAuthDiscoveryError.invalidCredentials }

        let refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expiresMilliseconds: Int64?
        switch oauth["expiresAt"] {
        case let value as NSNumber:
            expiresMilliseconds = value.int64Value
        case let value as Int64:
            expiresMilliseconds = value
        case let value as Int:
            expiresMilliseconds = Int64(value)
        case let value as Double:
            expiresMilliseconds = Int64(value)
        default:
            expiresMilliseconds = nil
        }
        let expiresAt = expiresMilliseconds.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0) / 1_000) : nil
        }
        let identity = AuthTokenIdentityParser.parse(accessToken: accessToken)
        let credential = DiscoveredAgentAuth(
            provider: .claude,
            token: accessToken,
            email: identity.email ?? accountEmail,
            accountID: identity.accountID
        )
        return Snapshot(
            stored: stored,
            oauth: OAuth(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt),
            credential: credential
        )
    }

    private static func replacingOAuth(
        in stored: ClaudeStoredCredentials,
        response: ClaudeTokenRefreshResponse,
        previousRefreshToken: String,
        now: Date
    ) throws -> ClaudeStoredCredentials {
        guard response.expiresIn > 0,
              !response.accessToken.isEmpty,
              var root = try? JSONSerialization.jsonObject(with: stored.data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any]
        else { throw ClaudeAuthDiscoveryError.invalidRefreshResponse }

        oauth["accessToken"] = response.accessToken
        oauth["refreshToken"] = response.refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? previousRefreshToken
        oauth["expiresAt"] = Int64(now.addingTimeInterval(TimeInterval(response.expiresIn)).timeIntervalSince1970 * 1_000)
        root["claudeAiOauth"] = oauth
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            throw ClaudeAuthDiscoveryError.credentialEncodingFailed
        }
        return ClaudeStoredCredentials(data: data, storage: stored.storage)
    }

    private static func shouldRefresh(_ oauth: OAuth, now: Date, leeway: TimeInterval) -> Bool {
        guard oauth.refreshToken != nil else { return false }
        guard let expiresAt = oauth.expiresAt else { return true }
        return expiresAt <= now.addingTimeInterval(leeway)
    }

    private static func cacheDeadline(
        oauth: OAuth,
        now: Date,
        configuration: ClaudeAuthConfiguration
    ) -> Date {
        let ttlDeadline = now.addingTimeInterval(configuration.successfulCacheTTL)
        guard oauth.refreshToken != nil, let expiresAt = oauth.expiresAt else { return ttlDeadline }
        return min(ttlDeadline, expiresAt.addingTimeInterval(-configuration.expirationLeeway))
    }
}

private enum ClaudeOAuthClient {
    static func refresh(refreshToken: String) async throws -> ClaudeTokenRefreshResponse {
        let endpoints = [
            "https://platform.claude.com/v1/oauth/token",
            "https://console.anthropic.com/v1/oauth/token",
            "https://claude.ai/v1/oauth/token",
        ]
        let fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        ]
        let body = fields.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        var lastStatusCode: Int?

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard http.statusCode == 200 else {
                    lastStatusCode = http.statusCode
                    continue
                }
                guard let refreshed = try? JSONDecoder().decode(ClaudeTokenRefreshResponse.self, from: data) else {
                    throw ClaudeAuthDiscoveryError.invalidRefreshResponse
                }
                return refreshed
            } catch let error as ClaudeAuthDiscoveryError {
                throw error
            } catch {
                continue
            }
        }
        if let lastStatusCode {
            throw ClaudeAuthDiscoveryError.refreshRejected(statusCode: lastStatusCode)
        }
        throw ClaudeAuthDiscoveryError.allRefreshEndpointsFailed
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
