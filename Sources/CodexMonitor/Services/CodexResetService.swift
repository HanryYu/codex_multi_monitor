import Foundation

@MainActor
final class CodexResetService: ObservableObject {
    @Published private(set) var snapshot: CodexResetSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let session: URLSession
    private let cacheURL: URL?
    private let currentURL = URL(string: "https://codex.gussuriworks.com/api/current?locale=en")!
    private var lastAttemptAt: Date?
    private var lastSuccessfulAt: Date?

    private static let cacheProvider = "codex-reset-observatory"

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodexMonitor/CodexReset", isDirectory: true)
        cacheURL = cacheDirectory?.appendingPathComponent("snapshot.json")

        if let cached = Self.loadCache(from: cacheURL),
           cached.provider == Self.cacheProvider {
            snapshot = cached.snapshot
            lastSuccessfulAt = cached.savedAt
        }
    }

    func refreshIfNeeded() async {
        let now = Date()
        guard CodexResetRefreshPolicy.shouldRefresh(
            lastSuccessfulAt: lastSuccessfulAt,
            lastAttemptAt: lastAttemptAt,
            now: now
        ) else { return }
        await performRefresh(cachePolicy: .reloadRevalidatingCacheData)
    }

    func refreshLatest() async {
        await performRefresh(cachePolicy: .reloadIgnoringLocalCacheData, forceFresh: true)
    }

    private func performRefresh(
        cachePolicy: URLRequest.CachePolicy,
        forceFresh: Bool = false
    ) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastAttemptAt = Date()
        defer { isLoading = false }

        do {
            let response: CodexResetObservatoryResponse = try await fetch(
                currentURL,
                cachePolicy: cachePolicy,
                forceFresh: forceFresh
            )
            let refreshedSnapshot = try response.makeSnapshot()
            let savedAt = Date()
            snapshot = refreshedSnapshot
            lastSuccessfulAt = savedAt
            persist(CodexResetCacheEntry(
                provider: Self.cacheProvider,
                savedAt: savedAt,
                snapshot: refreshedSnapshot
            ))
        } catch {
            errorMessage = error.localizedDescription
            print("[CodexMonitor] Codex Reset Observatory fetch failed: \(error)")
        }
    }

    private func fetch<Value: Decodable>(
        _ url: URL,
        cachePolicy: URLRequest.CachePolicy,
        forceFresh: Bool
    ) async throws -> Value {
        let requestURL: URL
        if forceFresh, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "_fresh", value: "1")]
            requestURL = components.url ?? url
        } else {
            requestURL = url
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        request.cachePolicy = cachePolicy
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

    private static func loadCache(from url: URL?) -> CodexResetCacheEntry? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(CodexResetCacheEntry.self, from: data)
        } catch {
            print("[CodexMonitor] Ignoring invalid Codex Reset Observatory cache: \(error)")
            return nil
        }
    }

    private func persist(_ entry: CodexResetCacheEntry) {
        guard let cacheURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entry)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[CodexMonitor] Codex Reset Observatory cache write failed: \(error)")
        }
    }
}

private struct CodexResetCacheEntry: Codable {
    let provider: String?
    let savedAt: Date
    let snapshot: CodexResetSnapshot
}

private enum CodexResetServiceError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid Codex Reset Observatory response"
        case .httpStatus(let code):
            return "Codex Reset Observatory HTTP \(code)"
        }
    }
}
