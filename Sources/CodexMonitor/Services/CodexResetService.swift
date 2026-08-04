import Foundation

@MainActor
final class CodexResetService: ObservableObject {
    @Published private(set) var snapshot: CodexResetSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let session: URLSession
    private let forecastURL = URL(string: "https://codex-reset.com/api/forecast")!
    private let feedURL = URL(string: "https://codex-reset.com/api/feed")!
    private let minimumRefreshInterval: TimeInterval = 5 * 60
    private var lastAttemptAt: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refreshIfNeeded() async {
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < minimumRefreshInterval {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastAttemptAt = Date()
        defer { isLoading = false }

        do {
            async let forecast: CodexResetForecast = fetch(forecastURL)
            async let feed: CodexResetFeed = fetch(feedURL)
            snapshot = try await CodexResetSnapshot(forecast: forecast, feed: feed)
        } catch {
            errorMessage = error.localizedDescription
            print("[CodexMonitor] Codex Reset fetch failed: \(error)")
        }
    }

    private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMonitor/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexResetServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexResetServiceError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

private enum CodexResetServiceError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid Codex Reset response"
        case .httpStatus(let code):
            return "Codex Reset HTTP \(code)"
        }
    }
}
