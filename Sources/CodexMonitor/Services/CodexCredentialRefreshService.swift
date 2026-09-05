import Foundation

struct CodexRefreshedCredential: Sendable {
    let accessToken: String
    let authBundleData: Data
}

enum CodexCredentialRefreshError: LocalizedError, Sendable {
    case missingCredentials
    case invalidResponse
    case accountMismatch
    case refreshRejected(String)
    case temporarilyUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "This Codex account has no saved refresh credentials. Switch to it in Codex and try again."
        case .invalidResponse:
            return "Codex returned an invalid credential refresh response."
        case .accountMismatch:
            return "Codex refreshed a different account. Switch to this account and sign in again."
        case .refreshRejected(let reason):
            return reason
        case .temporarilyUnavailable(let reason):
            return reason.isEmpty
                ? "Codex credential refresh is temporarily unavailable."
                : "Codex credential refresh is temporarily unavailable: \(reason)"
        }
    }
}

actor CodexCredentialRefreshService {
    static let shared = CodexCredentialRefreshService()

    // Keep these aligned with the official Codex managed-ChatGPT refresh contract.
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private var permanentFailures: [UUID: (refreshToken: String, reason: String)] = [:]

    private struct RefreshRequest: Encodable {
        let clientID: String
        let grantType: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case grantType = "grant_type"
            case refreshToken = "refresh_token"
        }
    }

    private struct RefreshResponse: Decodable {
        let idToken: String?
        let accessToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    func credential(
        for account: Account,
        forceRefresh: Bool = false,
        rejectedAccessToken: String? = nil
    ) async throws -> CodexRefreshedCredential {
        guard account.provider == .codex else {
            throw CodexCredentialRefreshError.missingCredentials
        }

        let savedBundleData = CodexAuthBundleStore.load(accountID: account.id)
        let candidates = CodexAuthSourceDiscoveryService.candidates(
            for: account,
            savedBundleData: savedBundleData
        )

        if forceRefresh,
           let alternative = candidates.first(where: {
               $0.bundle.accessToken != rejectedAccessToken
                   && isCurrentlyUsable($0.bundle.accessToken)
           }) {
            return adopt(alternative, for: account)
        }

        guard let candidate = candidates.first else {
            if !forceRefresh, isCurrentlyUsable(account.authToken) {
                return CodexRefreshedCredential(
                    accessToken: account.authToken,
                    authBundleData: Data()
                )
            }
            throw CodexCredentialRefreshError.missingCredentials
        }
        let bundle = candidate.bundle

        guard forceRefresh || bundle.needsRefresh() else {
            return adopt(candidate, for: account)
        }

        if let failure = permanentFailures[account.id],
           failure.refreshToken == bundle.refreshToken {
            throw CodexCredentialRefreshError.refreshRejected(failure.reason)
        }

        do {
            let refreshedData = try await refresh(bundle)
            guard let refreshedBundle = CodexStoredAuthBundle(data: refreshedData) else {
                throw CodexCredentialRefreshError.invalidResponse
            }
            guard refreshedBundle.matches(accountID: bundle.accountID),
                  refreshedTokenMatchesAccount(
                      refreshedBundle.accessToken,
                      expectedAccountID: bundle.accountID
                  )
            else {
                throw CodexCredentialRefreshError.accountMismatch
            }

            permanentFailures.removeValue(forKey: account.id)
            CodexAuthBundleStore.save(accountID: account.id, authJSONData: refreshedData)
            CodexAuthSourceDiscoveryService.writeBack(
                refreshedData: refreshedData,
                to: candidate,
                expectedRefreshToken: bundle.refreshToken
            )
            return CodexRefreshedCredential(
                accessToken: refreshedBundle.accessToken,
                authBundleData: refreshedData
            )
        } catch {
            if case .refreshRejected(let reason) = error as? CodexCredentialRefreshError {
                permanentFailures[account.id] = (bundle.refreshToken, reason)
            }
            // A proactive refresh may fail during a short network outage while the current
            // access token is still usable. Let the request try that token; a real 401 will
            // immediately return through the force-refresh path exactly once.
            if !forceRefresh, isCurrentlyUsable(bundle.accessToken) {
                return CodexRefreshedCredential(
                    accessToken: bundle.accessToken,
                    authBundleData: bundle.data
                )
            }
            throw error
        }
    }

    private func adopt(
        _ candidate: CodexAuthSourceCandidate,
        for account: Account
    ) -> CodexRefreshedCredential {
        let selectedData = CodexAuthBundleStore.save(
            accountID: account.id,
            authJSONData: candidate.bundle.data
        ) ?? candidate.bundle.data
        let selectedBundle = CodexStoredAuthBundle(data: selectedData) ?? candidate.bundle
        if permanentFailures[account.id]?.refreshToken != selectedBundle.refreshToken {
            permanentFailures.removeValue(forKey: account.id)
        }
        return CodexRefreshedCredential(
            accessToken: selectedBundle.accessToken,
            authBundleData: selectedBundle.data
        )
    }

    private func refresh(_ bundle: CodexStoredAuthBundle) async throws -> Data {
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(RefreshRequest(
            clientID: Self.clientID,
            grantType: "refresh_token",
            refreshToken: bundle.refreshToken
        ))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CodexCredentialRefreshError.temporarilyUnavailable(
                safeMessage(error.localizedDescription)
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw CodexCredentialRefreshError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw refreshError(statusCode: http.statusCode, data: data)
        }
        guard let response = try? JSONDecoder().decode(RefreshResponse.self, from: data),
              let accessToken = response.accessToken,
              !accessToken.isEmpty,
              let refreshedData = bundle.replacingTokens(
                  idToken: response.idToken,
                  accessToken: accessToken,
                  refreshToken: response.refreshToken,
                  refreshedAt: Date()
              )
        else {
            throw CodexCredentialRefreshError.invalidResponse
        }
        return refreshedData
    }

    private func refreshError(statusCode: Int, data: Data) -> CodexCredentialRefreshError {
        let code = refreshErrorCode(in: data)?.lowercased()
        switch code {
        case "refresh_token_expired":
            return .refreshRejected("Codex refresh token expired. Switch to this account and sign in again.")
        case "refresh_token_reused":
            return .refreshRejected("Codex refresh token was already used. Switch to this account and sign in again.")
        case "refresh_token_invalidated":
            return .refreshRejected("Codex refresh token was revoked. Switch to this account and sign in again.")
        case "invalid_grant":
            return .refreshRejected("Codex login can no longer be refreshed. Switch to this account and sign in again.")
        default:
            if statusCode == 401 || statusCode == 403 {
                return .refreshRejected("Codex rejected the saved login. Switch to this account and sign in again.")
            }
            return .temporarilyUnavailable("HTTP \(statusCode)")
        }
    }

    private func refreshErrorCode(in data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let code = root["code"] as? String { return code }
        if let code = root["error"] as? String { return code }
        if let error = root["error"] as? [String: Any] {
            return error["code"] as? String ?? error["type"] as? String
        }
        return nil
    }

    private func refreshedTokenMatchesAccount(
        _ accessToken: String,
        expectedAccountID: String
    ) -> Bool {
        let identity = AuthTokenIdentityParser.parse(accessToken: accessToken)
        guard let accountID = identity.accountID else { return false }
        return accountID.caseInsensitiveCompare(expectedAccountID) == .orderedSame
    }

    private func isCurrentlyUsable(_ accessToken: String) -> Bool {
        guard let expirationDate = CodexStoredAuthBundle.expirationDate(of: accessToken) else {
            return true
        }
        return expirationDate > Date()
    }

    private func safeMessage(_ value: String) -> String {
        String(value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .prefix(240))
    }
}
