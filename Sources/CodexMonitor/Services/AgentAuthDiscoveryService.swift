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

    static func currentGrokCredential() async throws -> DiscoveredAgentAuth {
        try await GrokCredentialRefreshCoordinator.shared.credential(forceRefresh: false)
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
    case incompleteRefreshConfiguration
    case invalidDiscoveryResponse
    case refreshRejected(statusCode: Int)
    case invalidRefreshResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Grok login credentials are missing."
        case .incompleteRefreshConfiguration:
            return "Grok login does not include refresh configuration."
        case .invalidDiscoveryResponse:
            return "Grok authentication discovery failed."
        case .refreshRejected(let statusCode):
            return "Grok rejected the token refresh (HTTP \(statusCode))."
        case .invalidRefreshResponse:
            return "Grok returned an invalid token refresh response."
        }
    }
}

private actor GrokCredentialRefreshCoordinator {
    static let shared = GrokCredentialRefreshCoordinator()

    func credential(forceRefresh: Bool) async throws -> DiscoveredAgentAuth {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokCredentialRefreshError.missingCredentials
        }

        guard let entry = root.first(where: { (_, value) in
            ((value as? [String: Any])?["key"] as? String)?.isEmpty == false
        }), var auth = entry.value as? [String: Any] else {
            throw GrokCredentialRefreshError.missingCredentials
        }

        if forceRefresh || shouldRefreshGrok(auth) {
            let refreshed = try await refreshGrok(auth: auth)
            auth["key"] = refreshed.accessToken
            if let refreshToken = refreshed.refreshToken { auth["refresh_token"] = refreshToken }
            auth["expires_at"] = ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
            )
            root[entry.key] = auth
            if let encoded = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) {
                try? encoded.write(to: url, options: [.atomic])
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }

        guard let token = auth["key"] as? String, !token.isEmpty else {
            throw GrokCredentialRefreshError.missingCredentials
        }
        return DiscoveredAgentAuth(
            provider: .grok,
            token: token,
            email: auth["email"] as? String,
            accountID: auth["user_id"] as? String ?? auth["principal_id"] as? String
        )
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
        let (metadataData, metadataResponse) = try await URLSession.shared.data(from: url)
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
        guard let refreshed = try? JSONDecoder().decode(OIDCTokenRefreshResponse.self, from: data) else {
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

private struct OIDCTokenRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
