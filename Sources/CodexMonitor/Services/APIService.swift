import Foundation

class APIService {
    static let shared = APIService()
    
    private let baseURL = "https://chatgpt.com/backend-api/wham/usage"
    
    func fetchUsage(authToken: String) async throws -> UsageResponse {
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }
        
        // Ensure token doesn't have duplicate "Bearer " prefix
        var token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
                // Debug: log raw JSON for Team plan investigation
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[CodexMonitor] API response (\(httpResponse.statusCode)): \(jsonString.prefix(2000))")
                }
                let decoder = JSONDecoder()
                return try decoder.decode(UsageResponse.self, from: data)
            } catch {
                // Debug: log raw data on decode failure
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("[CodexMonitor] Decode failed. Raw JSON: \(jsonString.prefix(2000))")
                }
                print("[CodexMonitor] Decode error: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            if let body = String(data: data, encoding: .utf8) {
                print("[CodexMonitor] HTTP \(httpResponse.statusCode) response: \(body.prefix(1000))")
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
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
