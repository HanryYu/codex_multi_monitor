import Foundation
import Security

struct DiscoveredAgentAuth {
    let provider: AccountProvider
    let token: String
    let email: String?
    let accountID: String?

    var displayName: String {
        if let email, !email.isEmpty { return email }
        return provider.displayName
    }
}

enum AgentAuthDiscoveryService {
    static func discover() async -> [DiscoveredAgentAuth] {
        async let claude = discoverClaude()
        async let grok = discoverGrok()
        let claudeResult = await claude
        let grokResult = await grok
        return [claudeResult, grokResult].compactMap { $0 }
    }

    private static func discoverClaude() async -> DiscoveredAgentAuth? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = home.appendingPathComponent(".claude/.credentials.json")
        var data = try? Data(contentsOf: fileURL)
        var storage: ClaudeCredentialStorage = .file(fileURL)

        #if os(macOS)
        if data == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    data = output.fileHandleForReading.readDataToEndOfFile()
                    storage = .keychain
                }
            } catch { }
        }
        #endif

        guard let credentialData = data,
              var root = try? JSONSerialization.jsonObject(with: credentialData) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }

        if shouldRefreshClaude(oauth),
           let refreshed = await refreshClaude(oauth: oauth) {
            oauth["accessToken"] = refreshed.accessToken
            oauth["refreshToken"] = refreshed.refreshToken
            oauth["expiresAt"] = Int64(Date().timeIntervalSince1970 * 1000) + Int64(refreshed.expiresIn * 1000)
            root["claudeAiOauth"] = oauth
            if let encoded = try? JSONSerialization.data(withJSONObject: root) {
                persistClaudeCredentials(encoded, storage: storage)
            }
        }

        guard let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }

        let identity = AuthTokenIdentityParser.parse(accessToken: token)
        return DiscoveredAgentAuth(
            provider: .claude,
            token: token,
            email: identity.email ?? claudeAccountEmail(),
            accountID: identity.accountID
        )
    }

    private static func shouldRefreshClaude(_ oauth: [String: Any]) -> Bool {
        guard let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty else { return false }
        let expiresAt = (oauth["expiresAt"] as? NSNumber)?.int64Value ?? 0
        return expiresAt == 0 || expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) + 60_000
    }

    private static func refreshClaude(oauth: [String: Any]) async -> ClaudeTokenRefreshResponse? {
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else { return nil }
        let endpoints = [
            "https://platform.claude.com/v1/oauth/token",
            "https://console.anthropic.com/v1/oauth/token",
            "https://claude.ai/v1/oauth/token",
        ]
        let form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        ]
        let body = form.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }.joined(separator: "&").data(using: .utf8)

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let refreshed = try? JSONDecoder().decode(ClaudeTokenRefreshResponse.self, from: data)
            else { continue }
            return refreshed
        }
        return nil
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private static func persistClaudeCredentials(_ data: Data, storage: ClaudeCredentialStorage) {
        switch storage {
        case .file(let url):
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        case .keychain:
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: "Claude Code-credentials",
            ]
            SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }

    private static func claudeAccountEmail() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["emailAddress"] as? String ?? account["email"] as? String
    }

    private static func discoverGrok() async -> DiscoveredAgentAuth? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let entry = root.first(where: { (_, value) in
            ((value as? [String: Any])?["key"] as? String)?.isEmpty == false
        }), var auth = entry.value as? [String: Any] else { return nil }

        if shouldRefreshGrok(auth), let refreshed = await refreshGrok(auth: auth) {
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

        guard let token = auth["key"] as? String, !token.isEmpty else { return nil }
        return DiscoveredAgentAuth(
            provider: .grok,
            token: token,
            email: auth["email"] as? String,
            accountID: auth["user_id"] as? String ?? auth["principal_id"] as? String
        )
    }

    private static func shouldRefreshGrok(_ auth: [String: Any]) -> Bool {
        guard let refresh = auth["refresh_token"] as? String, !refresh.isEmpty else { return false }
        guard let value = auth["expires_at"] as? String,
              let date = parseISODate(value) else { return true }
        return date.timeIntervalSinceNow <= 60
    }

    private static func refreshGrok(auth: [String: Any]) async -> OIDCTokenRefreshResponse? {
        guard let refreshToken = auth["refresh_token"] as? String,
              let clientID = auth["oidc_client_id"] as? String,
              let issuer = auth["oidc_issuer"] as? String else { return nil }

        let discoveryURL = issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/.well-known/openid-configuration"
        guard let url = URL(string: discoveryURL),
              let (metadataData, metadataResponse) = try? await URLSession.shared.data(from: url),
              let metadataHTTP = metadataResponse as? HTTPURLResponse,
              metadataHTTP.statusCode == 200,
              let metadata = try? JSONDecoder().decode(OIDCMetadata.self, from: metadataData),
              let tokenURL = URL(string: metadata.tokenEndpoint) else { return nil }

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

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(OIDCTokenRefreshResponse.self, from: data)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum ClaudeCredentialStorage {
    case file(URL)
    case keychain
}

private struct ClaudeTokenRefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
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
