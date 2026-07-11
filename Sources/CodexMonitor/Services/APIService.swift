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
        }
    }

    func fetchClaudeUsage(authToken: String) async throws -> UsageResponse {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(normalizedToken(authToken))", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        do {
            let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: data)
            let primary = payload.fiveHour?.window(seconds: 5 * 60 * 60)
            let secondary = payload.sevenDay?.window(seconds: 7 * 24 * 60 * 60)
            return UsageResponse(
                planType: "Claude",
                rateLimit: RateLimit(
                    allowed: ![primary, secondary].compactMap { $0 }.contains(where: { $0.usedPercent >= 100 }),
                    limitReached: [primary, secondary].compactMap { $0 }.contains(where: { $0.usedPercent >= 100 }),
                    primaryWindow: primary,
                    secondaryWindow: secondary
                )
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchGrokUsage(authToken: String) async throws -> UsageResponse {
        if isCookieCredential(authToken) {
            return try await fetchGrokWebUsage(cookie: authToken)
        }
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(normalizedToken(authToken))", forHTTPHeaderField: "Authorization")
        request.setValue("0.2.93", forHTTPHeaderField: "x-grok-client-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        do {
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(GrokBillingEnvelope.self, from: data)
            guard let payload = envelope.config else {
                throw APIError.invalidResponse
            }
            let percent = Int(payload.creditUsagePercent.rounded())
            let resetDate = payload.currentPeriod?.end.flatMap(Self.parseISODate)
                ?? payload.billingPeriodEnd.flatMap(Self.parseISODate)
            let resetAt = resetDate.map { Int($0.timeIntervalSince1970) } ?? 0
            let period = payload.currentPeriod?.type.uppercased() ?? ""
            let seconds = period.contains("WEEK") ? 7 * 24 * 60 * 60 : 30 * 24 * 60 * 60
            let window = WindowUsage(
                usedPercent: percent,
                limitWindowSeconds: seconds,
                resetAfterSeconds: resetAt > 0 ? max(0, resetAt - Int(Date().timeIntervalSince1970)) : 0,
                resetAt: resetAt
            )
            return UsageResponse(
                planType: payload.subscriptionTier ?? "Grok",
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
            throw APIError.decodingError(error)
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
            throw APIError.decodingError(error)
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
                throw APIError.decodingError(error)
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

    fileprivate static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct ClaudeUsagePayload: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    func window(seconds: Int) -> WindowUsage {
        let reset = resetsAt.flatMap(APIService.parseISODate(_:)).map { Int($0.timeIntervalSince1970) } ?? 0
        return WindowUsage(
            usedPercent: Int(utilization.rounded()),
            limitWindowSeconds: seconds,
            resetAfterSeconds: reset > 0 ? max(0, reset - Int(Date().timeIntervalSince1970)) : 0,
            resetAt: reset
        )
    }
}

private struct GrokBillingPayload: Decodable {
    let creditUsagePercent: Double
    let currentPeriod: GrokBillingPeriod?
    let billingPeriodEnd: String?
    let subscriptionTier: String?

}

private struct GrokBillingEnvelope: Decodable {
    let config: GrokBillingPayload?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.config) {
            config = try container.decodeIfPresent(GrokBillingPayload.self, forKey: .config)
        } else {
            config = try GrokBillingPayload(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey { case config }
}

private struct GrokBillingPeriod: Decodable {
    let type: String
    let end: String?
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case decodingError(Error)
    case unsupported
    
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
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unsupported:
            return "Not supported"
        }
    }
}
