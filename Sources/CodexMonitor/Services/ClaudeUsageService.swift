import CryptoKit
import Foundation

enum ClaudeUsageError: LocalizedError {
    case rateLimited(retryAt: Date)
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAt):
            return "Claude usage is rate limited until \(retryAt.formatted(date: .abbreviated, time: .shortened))."
        case .unauthorized:
            return "Claude rejected the usage credential."
        case .invalidResponse:
            return "Claude returned an invalid usage response."
        case .httpError(let statusCode):
            return "Claude usage request failed (HTTP \(statusCode))."
        case .decoding(let error):
            return "Claude usage response could not be decoded: \(error.localizedDescription)"
        }
    }
}

struct ClaudeUsageHTTPResult: @unchecked Sendable {
    let data: Data
    let response: URLResponse
}

struct ClaudeUsageTransport: @unchecked Sendable {
    let send: @Sendable (URLRequest) async throws -> ClaudeUsageHTTPResult

    static let live = ClaudeUsageTransport { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return ClaudeUsageHTTPResult(data: data, response: response)
    }
}

struct ClaudeUsageConfiguration: Sendable {
    var successfulCacheTTL: TimeInterval = 5 * 60
    var staleCacheTTL: TimeInterval = 30 * 60
    var initialRateLimitBackoff: TimeInterval = 15 * 60
    var maximumRateLimitBackoff: TimeInterval = 60 * 60
}

actor ClaudeUsageService {
    static let shared = ClaudeUsageService()

    private struct CacheEntry: Codable {
        var usage: UsageResponse?
        var fetchedAt: Date?
        var retryAt: Date?
        var consecutiveRateLimits: Int
    }

    private struct PersistedCache: Codable {
        let entries: [String: CacheEntry]
    }

    private let transport: ClaudeUsageTransport
    private let now: @Sendable () -> Date
    private let cacheURL: URL?
    private let configuration: ClaudeUsageConfiguration
    private var didLoadCache = false
    private var entries: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<UsageResponse, Error>] = [:]

    init(
        transport: ClaudeUsageTransport = .live,
        now: @escaping @Sendable () -> Date = { Date() },
        cacheURL: URL? = ClaudeUsageService.defaultCacheURL(),
        configuration: ClaudeUsageConfiguration = ClaudeUsageConfiguration()
    ) {
        self.transport = transport
        self.now = now
        self.cacheURL = cacheURL
        self.configuration = configuration
    }

    func fetchUsage(authToken: String) async throws -> UsageResponse {
        let token = Self.normalizedToken(authToken)
        guard !token.isEmpty else { throw ClaudeUsageError.unauthorized }

        let key = Self.tokenDigest(token)
        let requestTime = now()
        loadPersistedCacheIfNeeded(now: requestTime)

        if let entry = entries[key],
           let retryAt = entry.retryAt,
           retryAt > requestTime {
            if let stale = staleUsage(entry: entry, retryAt: retryAt, now: requestTime) {
                return stale
            }
            throw ClaudeUsageError.rateLimited(retryAt: retryAt)
        }

        if let entry = entries[key],
           let usage = entry.usage,
           let fetchedAt = entry.fetchedAt,
           requestTime.timeIntervalSince(fetchedAt) >= 0,
           requestTime.timeIntervalSince(fetchedAt) < configuration.successfulCacheTTL {
            return annotated(usage, fetchedAt: fetchedAt, retryAt: nil, isStale: false)
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ClaudeUsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let task = Task {
            try await self.performRequest(request, key: key)
        }
        inFlight[key] = task
        do {
            let usage = try await task.value
            inFlight[key] = nil
            return usage
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private func performRequest(_ request: URLRequest, key: String) async throws -> UsageResponse {
        let result: ClaudeUsageHTTPResult
        do {
            result = try await transport.send(request)
        } catch {
            return try staleOrThrow(.invalidResponse, key: key, retryAt: nil, now: now())
        }

        let responseTime = now()
        guard let http = result.response as? HTTPURLResponse else {
            return try staleOrThrow(.invalidResponse, key: key, retryAt: nil, now: responseTime)
        }

        switch http.statusCode {
        case 200:
            do {
                let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: result.data)
                var usage = payload.usage(now: responseTime)
                usage.fetchMetadata = UsageFetchMetadata(
                    fetchedAt: responseTime,
                    retryAt: nil,
                    isStale: false
                )
                entries[key] = CacheEntry(
                    usage: usage,
                    fetchedAt: responseTime,
                    retryAt: nil,
                    consecutiveRateLimits: 0
                )
                persistCache(now: responseTime)
                return usage
            } catch {
                return try staleOrThrow(
                    .decoding(error),
                    key: key,
                    retryAt: nil,
                    now: responseTime
                )
            }

        case 401, 403:
            entries.removeValue(forKey: key)
            persistCache(now: responseTime)
            throw ClaudeUsageError.unauthorized

        case 429:
            var entry = entries[key] ?? CacheEntry(
                usage: nil,
                fetchedAt: nil,
                retryAt: nil,
                consecutiveRateLimits: 0
            )
            entry.consecutiveRateLimits += 1
            let retryAt = rateLimitRetryAt(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                consecutiveRateLimits: entry.consecutiveRateLimits,
                now: responseTime
            )
            entry.retryAt = retryAt
            entries[key] = entry
            persistCache(now: responseTime)
            return try staleOrThrow(
                .rateLimited(retryAt: retryAt),
                key: key,
                retryAt: retryAt,
                now: responseTime
            )

        default:
            return try staleOrThrow(
                .httpError(statusCode: http.statusCode),
                key: key,
                retryAt: nil,
                now: responseTime
            )
        }
    }

    private func staleOrThrow(
        _ error: ClaudeUsageError,
        key: String,
        retryAt: Date?,
        now: Date
    ) throws -> UsageResponse {
        if case .unauthorized = error { throw error }
        if let entry = entries[key],
           let stale = staleUsage(entry: entry, retryAt: retryAt, now: now) {
            return stale
        }
        throw error
    }

    private func staleUsage(entry: CacheEntry, retryAt: Date?, now: Date) -> UsageResponse? {
        guard let usage = entry.usage, let fetchedAt = entry.fetchedAt else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age <= configuration.staleCacheTTL else { return nil }
        return annotated(usage, fetchedAt: fetchedAt, retryAt: retryAt, isStale: true)
    }

    private func annotated(
        _ usage: UsageResponse,
        fetchedAt: Date,
        retryAt: Date?,
        isStale: Bool
    ) -> UsageResponse {
        var result = usage
        result.fetchMetadata = UsageFetchMetadata(
            fetchedAt: fetchedAt,
            retryAt: retryAt,
            isStale: isStale
        )
        return result
    }

    private func rateLimitRetryAt(
        retryAfter: String?,
        consecutiveRateLimits: Int,
        now: Date
    ) -> Date {
        let exponent = min(max(consecutiveRateLimits - 1, 0), 16)
        let multiplier = pow(2.0, Double(exponent))
        let localDelay = min(
            configuration.maximumRateLimitBackoff,
            configuration.initialRateLimitBackoff * multiplier
        )
        let localRetryAt = now.addingTimeInterval(localDelay)
        guard let serverRetryAt = Self.parseRetryAfter(retryAfter, now: now) else {
            return localRetryAt
        }
        return max(localRetryAt, serverRetryAt)
    }

    private func loadPersistedCacheIfNeeded(now: Date) {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let persisted = try? JSONDecoder().decode(PersistedCache.self, from: data)
        else { return }

        entries = persisted.entries.filter { _, entry in
            let hasUsableCache = entry.fetchedAt.map {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age <= configuration.staleCacheTTL
            } ?? false
            let hasCooldown = entry.retryAt.map { $0 > now } ?? false
            return hasUsableCache || hasCooldown
        }
    }

    private func persistCache(now: Date) {
        guard let cacheURL else { return }
        let retained = entries.filter { _, entry in
            let hasUsableCache = entry.fetchedAt.map {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age <= configuration.staleCacheTTL
            } ?? false
            let hasCooldown = entry.retryAt.map { $0 > now } ?? false
            return hasUsableCache || hasCooldown
        }
        guard let data = try? JSONEncoder().encode(PersistedCache(entries: retained)) else { return }
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: cacheURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: cacheURL.path
            )
        } catch {
            // Cache persistence is best-effort; runtime cooldown remains authoritative.
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        var token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func tokenDigest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func parseRetryAfter(_ value: String?, now: Date) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func defaultCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodexMonitor/ClaudeUsage", isDirectory: true)
            .appendingPathComponent("usage-cache.json")
    }
}

private struct ClaudeUsagePayload: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    func usage(now: Date) -> UsageResponse {
        let primary = fiveHour?.window(seconds: 5 * 60 * 60, now: now)
        let secondary = sevenDay?.window(seconds: 7 * 24 * 60 * 60, now: now)
        let windows = [primary, secondary].compactMap { $0 }
        let limitReached = windows.contains(where: { $0.usedPercent >= 100 })
        return UsageResponse(
            planType: "Claude",
            rateLimit: RateLimit(
                allowed: !limitReached,
                limitReached: limitReached,
                primaryWindow: primary,
                secondaryWindow: secondary
            )
        )
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    func window(seconds: Int, now: Date) -> WindowUsage {
        let reset = resetsAt.flatMap(Self.parseISODate).map { Int($0.timeIntervalSince1970) } ?? 0
        return WindowUsage(
            usedPercent: Int(utilization.rounded()),
            limitWindowSeconds: seconds,
            resetAfterSeconds: reset > 0 ? max(0, reset - Int(now.timeIntervalSince1970)) : 0,
            resetAt: reset
        )
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
