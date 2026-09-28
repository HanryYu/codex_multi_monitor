import Foundation

class APIService {
    static let shared = APIService()
    
    private let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    private let resetCreditsURL = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"

    func fetchUsage(for account: Account) async throws -> UsageResponse {
        switch account.provider {
        case .codex:
            return try await fetchUsage(authToken: account.authToken)
        case .claude:
            return try await fetchClaudeUsage(authToken: account.authToken)
        case .grok:
            return try await fetchGrokUsage(authToken: account.authToken)
        case .openCodeGo:
            return try await OpenCodeGoUsageService.shared.fetchUsage(
                accountID: account.id,
                credential: account.authToken,
                workspaceIDOverride: account.openCodeWorkspaceID
            )
        }
    }

    func fetchClaudeUsage(authToken: String) async throws -> UsageResponse {
        do {
            return try await ClaudeUsageService.shared.fetchUsage(authToken: authToken)
        } catch let error as ClaudeUsageError {
            switch error {
            case .rateLimited(let retryAt):
                throw APIError.usageRateLimited(retryAt: retryAt)
            case .unauthorized:
                throw APIError.unauthorized
            default:
                throw APIError.message(error.localizedDescription)
            }
        }
    }

    func fetchGrokUsage(authToken: String) async throws -> UsageResponse {
        if isCookieCredential(authToken) {
            return try await fetchGrokWebUsage(cookie: authToken)
        }
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(normalizedToken(authToken))", forHTTPHeaderField: "Authorization")
        request.setValue(Self.installedGrokVersion(), forHTTPHeaderField: "x-grok-client-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        do {
            let payload = try GrokBillingUsageDecoder.decode(data)
            guard let usedPercent = payload.usedPercent else {
                // Unified-billing responses can legitimately omit subscription usage at the
                // beginning of a new period. Do not turn a successful response into a decode
                // failure or infer subscription quota from on-demand currency fields.
                return UsageResponse(planType: payload.planType, rateLimit: nil)
            }
            let percent = Int(usedPercent.rounded())
            let resetAt = payload.resetAt
            let window = WindowUsage(
                usedPercent: percent,
                limitWindowSeconds: payload.periodSeconds,
                resetAfterSeconds: resetAt > 0 ? max(0, resetAt - Int(Date().timeIntervalSince1970)) : 0,
                resetAt: resetAt
            )
            return UsageResponse(
                planType: payload.planType,
                rateLimit: RateLimit(
                    allowed: percent < 100,
                    limitReached: percent >= 100,
                    primaryWindow: window,
                    secondaryWindow: nil
                )
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.upstreamFormatChanged(provider: "Grok", underlying: error)
        }
    }

    private func fetchGrokWebUsage(cookie: String) async throws -> UsageResponse {
        guard let url = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data([0, 0, 0, 0, 0])
        request.setValue(normalizedCookie(cookie), forHTTPHeaderField: "Cookie")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
        request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        do {
            let payload = try GrokWebUsageDecoder.decode(data)
            let resetAt = payload.resetAt
            let seconds = payload.periodSeconds
            let window = WindowUsage(
                usedPercent: Int(payload.usedPercent.rounded()),
                limitWindowSeconds: seconds,
                resetAfterSeconds: resetAt > 0 ? max(0, resetAt - Int(Date().timeIntervalSince1970)) : 0,
                resetAt: resetAt
            )
            return UsageResponse(
                planType: "Grok Web",
                rateLimit: RateLimit(
                    allowed: window.usedPercent < 100,
                    limitReached: window.usedPercent >= 100,
                    primaryWindow: window,
                    secondaryWindow: nil
                )
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.upstreamFormatChanged(provider: "Grok", underlying: error)
        }
    }
    
    func fetchUsage(authToken: String) async throws -> UsageResponse {
        guard let url = URL(string: usageURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(normalizedToken(authToken))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Mimic browser to avoid potential Origin/Referer checks
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
#if DEBUG
                print("[CodexMonitor] API response \(httpResponse.statusCode), bytes: \(data.count)")
#endif
                let decoder = JSONDecoder()
                return try decoder.decode(UsageResponse.self, from: data)
            } catch {
#if DEBUG
                print("[CodexMonitor] Decode failed, bytes: \(data.count)")
                print("[CodexMonitor] Decode error: \(error)")
#endif
                throw APIError.upstreamFormatChanged(provider: "Codex", underlying: error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
#if DEBUG
            print("[CodexMonitor] HTTP \(httpResponse.statusCode), bytes: \(data.count)")
#endif
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func fetchRateLimitResetCredits(authToken: String, accountID: String?) async throws -> RateLimitResetCredits {
        guard let url = URL(string: resetCreditsURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(normalizedToken(authToken))", forHTTPHeaderField: "Authorization")
        if let accountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(RateLimitResetCredits.self, from: data)
            } catch {
                print("[CodexMonitor] Reset credits decode error: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            print("[CodexMonitor] Reset credits HTTP \(httpResponse.statusCode)")
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func normalizedToken(_ authToken: String) -> String {
        var token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private func isCookieCredential(_ value: String) -> Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.lowercased().hasPrefix("cookie:") || (token.contains("=") && token.contains(";"))
    }

    private func normalizedCookie(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("cookie:") else { return trimmed }
        return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200: return
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.httpError(statusCode: http.statusCode)
        }
    }

    private static func installedGrokVersion() -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/version.json")
        guard let data = try? Data(contentsOf: url),
              data.count <= 64 * 1_024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? String,
              !version.isEmpty
        else { return "1.0.13" }
        return version
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case usageRateLimited(retryAt: Date)
    case httpError(statusCode: Int)
    case decodingError(Error)
    case authenticationExpired(provider: String, detail: String?)
    case upstreamFormatChanged(provider: String, underlying: Error)
    case unsupported
    case message(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .unauthorized:
            return "Unauthorized - check token"
        case .rateLimited:
            return "Rate limited"
        case .usageRateLimited(let retryAt):
            return L10n.claudeUsageRateLimited(retryAt: retryAt)
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .authenticationExpired(let provider, let detail):
            if let detail, !detail.isEmpty {
                return "\(provider) authentication unavailable — \(detail)"
            }
            return "\(provider) session expired — sign in to this account again"
        case .upstreamFormatChanged(let provider, _):
            return "\(provider) usage response changed — update CodexMonitor or try again later"
        case .unsupported:
            return "Not supported"
        case .message(let message):
            return message
        }
    }

    var isUnauthorized: Bool {
        switch self {
        case .unauthorized, .authenticationExpired:
            return true
        default:
            return false
        }
    }
}
