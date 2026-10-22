import CryptoKit
import Foundation

enum ClaudeUsageError: LocalizedError {
    case rateLimited(retryAt: Date)
    case unauthorized
    case accessBlocked
    case organizationSelectionRequired
    case noOrganizations
    case invalidOrganizationID
    case invalidCredential(String)
    case invalidResponse
    case httpError(statusCode: Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAt):
            return "Claude usage is rate limited until \(retryAt.formatted(date: .abbreviated, time: .shortened))."
        case .unauthorized:
            return "Claude rejected the usage credential."
        case .accessBlocked:
            return "Claude blocked this usage request. Open claude.ai, confirm the session can view usage, then try again."
        case .organizationSelectionRequired:
            return "This Claude session belongs to multiple organizations. Enter the organization UUID or Claude usage URL in account settings."
        case .noOrganizations:
            return "No Claude organizations are available for this session."
        case .invalidOrganizationID:
            return "Enter a valid Claude organization UUID or usage URL."
        case .invalidCredential(let detail):
            return detail
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

    static let live: ClaudeUsageTransport = {
        let configuration = makeEphemeralConfiguration()
        let session = URLSession(
            configuration: configuration,
            delegate: ClaudeRedirectBlockingDelegate(),
            delegateQueue: nil
        )
        return ClaudeUsageTransport { request in
            let (data, response) = try await session.data(for: request)
            return ClaudeUsageHTTPResult(data: data, response: response)
        }
    }()

    static func makeEphemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

private final class ClaudeRedirectBlockingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(ClaudeUsageRedirectPolicy.redirectedRequest(request))
    }
}

enum ClaudeUsageRedirectPolicy {
    static func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        nil
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
        var organizations: [String]? = nil
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
    private var organizationInFlight: [String: Task<[String], Error>] = [:]

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

    func fetchUsage(authToken: String, organizationID: String? = nil) async throws -> UsageResponse {
        let credential: ClaudeUsageCredential
        do {
            credential = try ClaudeUsageCredential.parse(authToken)
        } catch {
            throw ClaudeUsageError.invalidCredential(error.localizedDescription)
        }

        let requestTime = now()
        loadPersistedCacheIfNeeded(now: requestTime)
        if credential.isCookie {
            let selectedOrganizationID: String
            do {
                selectedOrganizationID = try await resolveOrganizationID(
                    credential,
                    explicitValue: organizationID
                )
            } catch let error as ClaudeUsageError {
                throw error
            } catch {
                throw ClaudeUsageError.invalidOrganizationID
            }
            return try await fetchCookieUsage(credential, organizationID: selectedOrganizationID)
        }
        return try await fetchOAuthUsage(credential.normalizedValue)
    }

    private func fetchOAuthUsage(_ token: String) async throws -> UsageResponse {
        let key = Self.tokenDigest(token)
        let requestTime = now()

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

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1") else {
            throw ClaudeUsageError.invalidResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "claude-cli/2.1.288 (external, cli, client-app/CodexMonitor)",
            forHTTPHeaderField: "User-Agent"
        )
        request.httpShouldHandleCookies = false

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

    private func resolveOrganizationID(
        _ credential: ClaudeUsageCredential,
        explicitValue: String?
    ) async throws -> String {
        if let explicitValue,
           !explicitValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                if let normalized = try ClaudeUsageCredential.normalizedOrganizationID(explicitValue) {
                    return normalized
                }
            } catch {
                throw ClaudeUsageError.invalidOrganizationID
            }
        }

        let organizations = try await fetchOrganizations(for: credential)
        if let lastActive = credential.lastActiveOrganizationID,
           organizations.contains(lastActive) {
            return lastActive
        }
        if organizations.count == 1, let onlyOrganization = organizations.first {
            return onlyOrganization
        }
        guard !organizations.isEmpty else { throw ClaudeUsageError.noOrganizations }
        throw ClaudeUsageError.organizationSelectionRequired
    }

    private func fetchOrganizations(for credential: ClaudeUsageCredential) async throws -> [String] {
        let namespace = Self.cookieNamespace(for: credential)
        let key = namespace + "organizations"
        let requestTime = now()

        if let entry = entries[key],
           let retryAt = entry.retryAt,
           retryAt > requestTime {
            if let organizations = staleOrganizations(entry: entry, now: requestTime) {
                return organizations
            }
            throw ClaudeUsageError.rateLimited(retryAt: retryAt)
        }

        if let entry = entries[key],
           let organizations = entry.organizations,
           let fetchedAt = entry.fetchedAt,
           requestTime.timeIntervalSince(fetchedAt) >= 0,
           requestTime.timeIntervalSince(fetchedAt) < configuration.successfulCacheTTL {
            return organizations
        }

        if let existing = organizationInFlight[key] {
            return try await existing.value
        }

        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            throw ClaudeUsageError.invalidResponse
        }
        let request = Self.cookieRequest(url: url, credential: credential)
        let task = Task {
            try await self.performOrganizationRequest(
                request,
                key: key,
                cookieNamespace: namespace
            )
        }
        organizationInFlight[key] = task
        do {
            let organizations = try await task.value
            organizationInFlight[key] = nil
            return organizations
        } catch {
            organizationInFlight[key] = nil
            throw error
        }
    }

    private func performOrganizationRequest(
        _ request: URLRequest,
        key: String,
        cookieNamespace: String
    ) async throws -> [String] {
        let result: ClaudeUsageHTTPResult
        do {
            result = try await transport.send(request)
        } catch {
            return try staleOrganizationsOrThrow(key: key, now: now())
        }

        let responseTime = now()
        guard let http = result.response as? HTTPURLResponse else {
            return try staleOrganizationsOrThrow(key: key, now: responseTime)
        }

        switch http.statusCode {
        case 200:
            guard !Self.isHTML(result.data, response: http) else {
                throw ClaudeUsageError.accessBlocked
            }
            do {
                let organizations = try Self.decodeOrganizationIDs(result.data)
                entries[key] = CacheEntry(
                    usage: nil,
                    organizations: organizations,
                    fetchedAt: responseTime,
                    retryAt: nil,
                    consecutiveRateLimits: 0
                )
                persistCache(now: responseTime)
                return organizations
            } catch let error as ClaudeUsageError {
                throw error
            } catch {
                return try staleOrganizationsOrThrow(key: key, now: responseTime)
            }

        case 401:
            clearCookieCache(namespace: cookieNamespace, now: responseTime)
            throw ClaudeUsageError.unauthorized

        case 403:
            throw ClaudeUsageError.accessBlocked

        case 429:
            let retryAt = recordRateLimit(
                key: key,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                now: responseTime
            )
            return try staleOrganizationsOrThrow(key: key, retryAt: retryAt, now: responseTime)

        default:
            return try staleOrganizationsOrThrow(
                key: key,
                error: .httpError(statusCode: http.statusCode),
                now: responseTime
            )
        }
    }

    private func fetchCookieUsage(
        _ credential: ClaudeUsageCredential,
        organizationID: String
    ) async throws -> UsageResponse {
        let namespace = Self.cookieNamespace(for: credential)
        let key = namespace + "usage:" + organizationID
        let requestTime = now()

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

        guard let url = URL(string: "https://claude.ai/api/organizations/\(organizationID)/usage") else {
            throw ClaudeUsageError.invalidResponse
        }
        let request = Self.cookieRequest(url: url, credential: credential)
        let task = Task {
            try await self.performCookieUsageRequest(
                request,
                key: key,
                cookieNamespace: namespace
            )
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

    private func performCookieUsageRequest(
        _ request: URLRequest,
        key: String,
        cookieNamespace: String
    ) async throws -> UsageResponse {
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
            guard !Self.isHTML(result.data, response: http) else {
                throw ClaudeUsageError.accessBlocked
            }
            do {
                let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: result.data)
                guard var usage = payload.usage(now: responseTime) else {
                    throw ClaudeUsageError.invalidResponse
                }
                usage.rateLimitResetCredits = ClaudeResetCreditsDecoder.decode(
                    result.data,
                    now: responseTime
                )
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
            } catch let error as ClaudeUsageError {
                throw error
            } catch {
                return try staleOrThrow(
                    .decoding(error),
                    key: key,
                    retryAt: nil,
                    now: responseTime
                )
            }

        case 401:
            clearCookieCache(namespace: cookieNamespace, now: responseTime)
            throw ClaudeUsageError.unauthorized

        case 403:
            throw ClaudeUsageError.accessBlocked

        case 429:
            let retryAt = recordRateLimit(
                key: key,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
                now: responseTime
            )
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

    private func staleOrganizationsOrThrow(
        key: String,
        retryAt: Date? = nil,
        error: ClaudeUsageError? = nil,
        now: Date
    ) throws -> [String] {
        if let entry = entries[key],
           let organizations = staleOrganizations(entry: entry, now: now) {
            return organizations
        }
        if let error { throw error }
        if let retryAt { throw ClaudeUsageError.rateLimited(retryAt: retryAt) }
        throw ClaudeUsageError.invalidResponse
    }

    private func staleOrganizations(entry: CacheEntry, now: Date) -> [String]? {
        guard let organizations = entry.organizations, let fetchedAt = entry.fetchedAt else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age <= configuration.staleCacheTTL else { return nil }
        return organizations
    }

    private func recordRateLimit(key: String, retryAfter: String?, now: Date) -> Date {
        var entry = entries[key] ?? CacheEntry(
            usage: nil,
            fetchedAt: nil,
            retryAt: nil,
            consecutiveRateLimits: 0
        )
        entry.consecutiveRateLimits += 1
        let retryAt = rateLimitRetryAt(
            retryAfter: retryAfter,
            consecutiveRateLimits: entry.consecutiveRateLimits,
            now: now
        )
        entry.retryAt = retryAt
        entries[key] = entry
        persistCache(now: now)
        return retryAt
    }

    private func clearCookieCache(namespace: String, now: Date) {
        entries = entries.filter { !$0.key.hasPrefix(namespace) }
        persistCache(now: now)
    }

    private static func cookieNamespace(for credential: ClaudeUsageCredential) -> String {
        "cookie:\(tokenDigest(credential.normalizedValue)):"
    }

    private static func cookieRequest(url: URL, credential: ClaudeUsageCredential) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(credential.normalizedValue, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        return request
    }

    private static func decodeOrganizationIDs(_ data: Data) throws -> [String] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ClaudeUsageError.decoding(error)
        }

        let rawOrganizations: [Any]
        if let organizations = value as? [Any] {
            rawOrganizations = organizations
        } else if let root = value as? [String: Any],
                  let organizations = root["organizations"] as? [Any] {
            rawOrganizations = organizations
        } else if let root = value as? [String: Any],
                  let organizations = root["data"] as? [Any] {
            rawOrganizations = organizations
        } else {
            throw ClaudeUsageError.invalidResponse
        }

        var seen = Set<String>()
        let identifiers = rawOrganizations.compactMap { raw -> String? in
            guard let object = raw as? [String: Any],
                  let rawID = (object["uuid"] as? String) ?? (object["id"] as? String)
            else { return nil }
            let identifier: String
            do {
                guard let normalized = try ClaudeUsageCredential.normalizedOrganizationID(rawID) else {
                    return nil
                }
                identifier = normalized
            } catch {
                return nil
            }
            guard seen.insert(identifier).inserted else { return nil }
            return identifier
        }
        guard rawOrganizations.isEmpty || !identifiers.isEmpty else {
            throw ClaudeUsageError.invalidResponse
        }
        return identifiers
    }

    private static func isHTML(_ data: Data, response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") == true {
            return true
        }
        let prefix = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html")
            || prefix.hasPrefix("<head")
            || prefix.hasPrefix("<body")
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
                guard var usage = payload.usage(now: responseTime) else {
                    return try staleOrThrow(
                        .invalidResponse,
                        key: key,
                        retryAt: nil,
                        now: responseTime
                    )
                }
                usage.rateLimitResetCredits = ClaudeResetCreditsDecoder.decode(
                    result.data,
                    now: responseTime
                )
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
            } catch let error as ClaudeUsageError {
                return try staleOrThrow(error, key: key, retryAt: nil, now: responseTime)
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
        if case .accessBlocked = error { throw error }
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
        result.rateLimitResetCredits = unexpiredResetCredits(
            usage.rateLimitResetCredits,
            now: now()
        )
        result.fetchMetadata = UsageFetchMetadata(
            fetchedAt: fetchedAt,
            retryAt: retryAt,
            isStale: isStale
        )
        return result
    }

    private func unexpiredResetCredits(
        _ resetCredits: RateLimitResetCredits?,
        now: Date
    ) -> RateLimitResetCredits? {
        guard let resetCredits else { return nil }

        var credits: [RateLimitResetCredit] = []
        var availableCount = 0
        for credit in resetCredits.credits {
            let remainingCount = credit.remainingCount ?? 1
            guard credit.isAvailable,
                  remainingCount > 0
            else {
                continue
            }

            if let rawExpiry = credit.expiresAt {
                guard !rawExpiry.isEmpty,
                      let expirationDate = credit.expiresDate,
                      expirationDate > now
                else {
                    continue
                }
            }

            let (nextCount, overflow) = availableCount.addingReportingOverflow(remainingCount)
            guard !overflow else { continue }
            availableCount = nextCount
            credits.append(credit)
        }

        return RateLimitResetCredits(availableCount: availableCount, credits: credits)
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
            let hasUsableCache = (entry.usage != nil || entry.organizations != nil) && (entry.fetchedAt.map {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age <= configuration.staleCacheTTL
            } ?? false)
            let hasCooldown = entry.retryAt.map { $0 > now } ?? false
            return hasUsableCache || hasCooldown
        }
    }

    private func persistCache(now: Date) {
        guard let cacheURL else { return }
        let retained = entries.filter { _, entry in
            let hasUsableCache = (entry.usage != nil || entry.organizations != nil) && (entry.fetchedAt.map {
                let age = now.timeIntervalSince($0)
                return age >= 0 && age <= configuration.staleCacheTTL
            } ?? false)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decode(ClaudeUsageWindow.self, forKey: .fiveHour)
        sevenDay = try? container.decode(ClaudeUsageWindow.self, forKey: .sevenDay)
    }

    func usage(now: Date) -> UsageResponse? {
        let primary = fiveHour?.window(seconds: 5 * 60 * 60, now: now)
        let secondary = sevenDay?.window(seconds: 7 * 24 * 60 * 60, now: now)
        guard primary != nil || secondary != nil else { return nil }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try container.decode(Double.self, forKey: .utilization)
        resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)
    }

    func window(seconds: Int, now: Date) -> WindowUsage? {
        guard utilization.isFinite else { return nil }
        let reset = resetsAt.flatMap(Self.parseISODate).map(Self.safeTimestamp) ?? 0
        let nowTimestamp = Self.safeTimestamp(now)
        let resetAfterSeconds: Int
        if reset > 0 {
            let (delta, overflow) = reset.subtractingReportingOverflow(nowTimestamp)
            resetAfterSeconds = overflow ? (reset > nowTimestamp ? Int.max : 0) : max(0, delta)
        } else {
            resetAfterSeconds = 0
        }
        let clampedUtilization = min(max(utilization, 0), 100)
        return WindowUsage(
            usedPercent: Int(clampedUtilization.rounded()),
            limitWindowSeconds: seconds,
            resetAfterSeconds: resetAfterSeconds,
            resetAt: reset
        )
    }

    private static func safeTimestamp(_ date: Date) -> Int {
        let value = date.timeIntervalSince1970
        guard value.isFinite,
              value < Double(Int.max),
              value > Double(Int.min)
        else { return 0 }
        return Int(value)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
