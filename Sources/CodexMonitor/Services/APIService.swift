import Foundation

class APIService {
    static let shared = APIService()
    
    private let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    private let resetCreditsURL = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
    
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
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case decodingError(Error)
    
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
        }
    }
}
