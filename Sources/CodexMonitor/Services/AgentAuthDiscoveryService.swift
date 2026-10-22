import Foundation

enum AgentAuthDiscoveryService {
    static func discover() async -> [DiscoveredAgentAuth] {
        async let claude = discoverClaude()
        async let grok = discoverGrok()
        let claudeResult = await claude
        let grokResult = await grok
        return [claudeResult, grokResult].compactMap { $0 }
    }

    static func forceRefreshGrok() async throws -> DiscoveredAgentAuth {
        try await GrokCredentialRefreshCoordinator.shared.credential(forceRefresh: true)
    }

    /// Refresh the local CLI credential only when it belongs to the saved
    /// account. This overload is used by AccountStore after a Grok 401.
    static func forceRefreshGrok(for account: Account) async throws -> DiscoveredAgentAuth {
        try await GrokCredentialRefreshCoordinator.shared.credential(
            forceRefresh: true,
            matching: grokIdentity(for: account)
        )
    }

    static func currentGrokCredential() async throws -> DiscoveredAgentAuth {
        try await GrokCredentialRefreshCoordinator.shared.credential(forceRefresh: false)
    }

    static func currentGrokCredential(for account: Account) async throws -> DiscoveredAgentAuth {
        try await GrokCredentialRefreshCoordinator.shared.credential(
            forceRefresh: false,
            matching: grokIdentity(for: account)
        )
    }

    private static func grokIdentity(for account: Account) -> GrokCredentialRecovery.AccountIdentity {
        let tokenIdentity = AuthTokenIdentityParser.parse(accessToken: account.authToken)
        return GrokCredentialRecovery.AccountIdentity(
            credential: account.authToken,
            accountID: account.accountID ?? tokenIdentity.accountID,
            email: account.accountEmail ?? tokenIdentity.email
        )
    }

    private static func discoverClaude() async -> DiscoveredAgentAuth? {
        do {
            let result = try await ClaudeCredentialCoordinator.shared.credential()
            if let warning = result.persistenceErrorDescription {
                print("[CodexMonitor] Claude credential persistence failed: \(warning)")
            }
            return result.credential
        } catch let error as ClaudeAuthDiscoveryError where error.isExpectedAbsence {
            return nil
        } catch {
            print("[CodexMonitor] Claude credential discovery failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func discoverGrok() async -> DiscoveredAgentAuth? {
        do {
            return try await GrokCredentialRefreshCoordinator.shared.credential(forceRefresh: false)
        } catch {
            print("[CodexMonitor] Grok credential refresh failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private enum GrokCredentialRefreshError: LocalizedError {
    case missingCredentials
    case accountMismatch
    case credentialsChangedDuringRefresh
    case incompleteRefreshConfiguration
    case invalidDiscoveryResponse
    case refreshRejected(statusCode: Int)
    case invalidRefreshResponse
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Grok login credentials are missing. Run grok login or update this account's token."
        case .accountMismatch:
            return "Grok local credentials do not match this account."
        case .credentialsChangedDuringRefresh:
            return "Grok credentials changed while refresh was in progress."
        case .incompleteRefreshConfiguration:
            return "Grok login does not include refresh configuration."
        case .invalidDiscoveryResponse:
            return "Grok authentication discovery failed."
        case .refreshRejected(let statusCode):
            return "Grok rejected the token refresh (HTTP \(statusCode))."
        case .invalidRefreshResponse:
            return "Grok returned an invalid token refresh response."
        case .persistenceFailed:
            return "Grok refreshed credentials could not be saved safely."
        }
    }
}

private actor GrokCredentialRefreshCoordinator {
    static let shared = GrokCredentialRefreshCoordinator()
    private let refreshCoalescer = GrokCredentialRefreshCoalescer<OIDCTokenRefreshResponse>()

    func credential(
        forceRefresh: Bool,
        matching identity: GrokCredentialRecovery.AccountIdentity? = nil
    ) async throws -> DiscoveredAgentAuth {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokCredentialRefreshError.missingCredentials
        }

        let candidates: [(key: String, auth: [String: Any], credential: GrokCredentialRecovery.LocalCredential)] =
            root.compactMap { key, value in
                guard let auth = value as? [String: Any],
                      let credential = localCredential(from: auth) else { return nil }
                return (key: key, auth: auth, credential: credential)
            }
        guard !candidates.isEmpty else {
            throw GrokCredentialRefreshError.missingCredentials
        }

        let selected: (key: String, auth: [String: Any], credential: GrokCredentialRecovery.LocalCredential)
        if let identity {
            // Browser sessions must never be replaced by the local CLI token.
            guard !GrokCredentialRecovery.isCookieCredential(identity.credential) else {
                throw GrokCredentialRefreshError.accountMismatch
            }
            guard let match = candidates.first(where: {
                GrokCredentialRecovery.matches(identity, $0.credential)
            }) else {
                throw GrokCredentialRefreshError.accountMismatch
            }
            selected = match
        } else {
            // Dictionary iteration order is not an account-selection policy.
            guard let preferredKey = GrokCredentialRecovery.preferredLocalEntryKey(
                candidates.map(\.key)
            ), let preferred = candidates.first(where: { $0.key == preferredKey }) else {
                throw GrokCredentialRefreshError.missingCredentials
            }
            selected = preferred
        }

        var auth = selected.auth
        let localToken = selected.credential.credential
        let forceSelectedToken = forceRefresh && (identity.map {
            GrokCredentialRecovery.shouldForceRefresh(requested: $0.credential, local: localToken)
        } ?? true)

        // A second caller that observed the old file while the first caller is
        // refreshing must await the same task rather than issue another grant.
        if let refreshToken = auth["refresh_token"] as? String,
           !refreshToken.isEmpty,
           let refreshed = try await refreshCoalescer.valueIfInFlight(for: refreshToken) {
            auth = updated(auth, with: refreshed)
        } else if forceSelectedToken || shouldRefreshGrok(auth) {
            let refreshed = try await refreshGrokCoalesced(
                auth: auth,
                selectedKey: selected.key,
                fileURL: url
            )
            auth = updated(auth, with: refreshed)
        }

        guard let token = auth["key"] as? String, !token.isEmpty else {
            throw GrokCredentialRefreshError.missingCredentials
        }
        return DiscoveredAgentAuth(
            provider: .grok,
            token: token,
            email: firstString(in: auth, keys: ["email", "email_address"]),
            accountID: firstString(in: auth, keys: ["user_id", "principal_id", "account_id"])
        )
    }

    private func localCredential(from auth: [String: Any]) -> GrokCredentialRecovery.LocalCredential? {
        guard let token = auth["key"] as? String, !token.isEmpty else { return nil }
        let tokenIdentity = AuthTokenIdentityParser.parse(accessToken: token)
        return GrokCredentialRecovery.LocalCredential(
            credential: token,
            accountID: firstString(in: auth, keys: ["user_id", "principal_id", "account_id"]) ?? tokenIdentity.accountID,
            email: firstString(in: auth, keys: ["email", "email_address"]) ?? tokenIdentity.email
        )
    }

    private func firstString(in values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func updated(
        _ auth: [String: Any],
        with refreshed: OIDCTokenRefreshResponse
    ) -> [String: Any] {
        var auth = auth
        auth["key"] = refreshed.accessToken
        if let refreshToken = refreshed.refreshToken { auth["refresh_token"] = refreshToken }
        auth["expires_at"] = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        )
        return auth
    }

    private func persist(root: [String: Any], to url: URL) throws {
        do {
            let encoded = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try encoded.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Do not return a rotated access token while the refresh token is
            // still only in memory; the caller receives a non-sensitive error.
            throw GrokCredentialRefreshError.persistenceFailed
        }
    }

    private func refreshGrokCoalesced(
        auth: [String: Any],
        selectedKey: String,
        fileURL: URL
    ) async throws -> OIDCTokenRefreshResponse {
        guard let refreshToken = auth["refresh_token"] as? String, !refreshToken.isEmpty else {
            return try await refreshGrok(auth: auth)
        }
        return try await refreshCoalescer.value(for: refreshToken) { [self] in
            guard let latestData = try? Data(contentsOf: fileURL),
                  let latestRoot = try? JSONSerialization.jsonObject(with: latestData) as? [String: Any],
                  GrokCredentialRecovery.entryMatchesOriginal(
                      in: latestRoot,
                      key: selectedKey,
                      originalCredential: auth["key"] as? String ?? "",
                      originalRefreshToken: refreshToken
                  ) else {
                throw GrokCredentialRefreshError.credentialsChangedDuringRefresh
            }
            let refreshed = try await self.refreshGrok(auth: auth)
            // The file may have changed while the network request was in
            // flight. Merge only this entry into the latest file contents so
            // two accounts cannot overwrite each other's rotations.
            try await self.persistRefreshedEntry(
                refreshed,
                key: selectedKey,
                originalCredential: auth["key"] as? String ?? "",
                originalRefreshToken: refreshToken,
                fileURL: fileURL
            )
            return refreshed
        }
    }

    private func persistRefreshedEntry(
        _ refreshed: OIDCTokenRefreshResponse,
        key: String,
        originalCredential: String,
        originalRefreshToken: String,
        fileURL: URL
    ) throws {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokCredentialRefreshError.credentialsChangedDuringRefresh
        }
        let expiresAt = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        )
        let merged: [String: Any]
        do {
            merged = try GrokCredentialRecovery.mergeRefreshedEntry(
                in: root,
                key: key,
                originalCredential: originalCredential,
                originalRefreshToken: originalRefreshToken,
                refreshed: .init(
                    credential: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: expiresAt
                )
            )
        } catch {
            throw GrokCredentialRefreshError.credentialsChangedDuringRefresh
        }
        try persist(root: merged, to: fileURL)
    }

    private func shouldRefreshGrok(_ auth: [String: Any]) -> Bool {
        guard let refresh = auth["refresh_token"] as? String, !refresh.isEmpty else { return false }
        guard let value = auth["expires_at"] as? String,
              let date = parseISODate(value) else { return true }
        return date.timeIntervalSinceNow <= 60
    }

    private func refreshGrok(auth: [String: Any]) async throws -> OIDCTokenRefreshResponse {
        guard let refreshToken = auth["refresh_token"] as? String,
              let clientID = auth["oidc_client_id"] as? String,
              let issuer = auth["oidc_issuer"] as? String else {
            throw GrokCredentialRefreshError.incompleteRefreshConfiguration
        }

        let discoveryURL = issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/.well-known/openid-configuration"
        guard let url = URL(string: discoveryURL) else {
            throw GrokCredentialRefreshError.invalidDiscoveryResponse
        }
        var discoveryRequest = URLRequest(url: url)
        discoveryRequest.timeoutInterval = 15
        discoveryRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (metadataData, metadataResponse) = try await URLSession.shared.data(for: discoveryRequest)
        guard
              let metadataHTTP = metadataResponse as? HTTPURLResponse,
              metadataHTTP.statusCode == 200,
              let metadata = try? JSONDecoder().decode(OIDCMetadata.self, from: metadataData),
              let tokenURL = URL(string: metadata.tokenEndpoint) else {
            throw GrokCredentialRefreshError.invalidDiscoveryResponse
        }

        let fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = fields.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GrokCredentialRefreshError.invalidRefreshResponse
        }
        guard http.statusCode == 200 else {
            throw GrokCredentialRefreshError.refreshRejected(statusCode: http.statusCode)
        }
        guard let refreshed = try? JSONDecoder().decode(OIDCTokenRefreshResponse.self, from: data),
              !refreshed.accessToken.isEmpty,
              refreshed.expiresIn > 0 else {
            throw GrokCredentialRefreshError.invalidRefreshResponse
        }
        return refreshed
    }

    private func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

private struct OIDCMetadata: Decodable {
    let tokenEndpoint: String
    enum CodingKeys: String, CodingKey { case tokenEndpoint = "token_endpoint" }
}

private struct OIDCTokenRefreshResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
