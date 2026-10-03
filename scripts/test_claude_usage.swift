import Foundation

private enum ClaudeUsageTestError: Error {
    case missingStub
    case expectedRateLimit
    case expectedUnauthorized
    case expectedHTTPError
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Date) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private actor FakeClaudeUsageTransport {
    struct Stub: Sendable {
        let statusCode: Int?
        let headers: [String: String]
        let data: Data
        let delayNanoseconds: UInt64

        static func http(
            _ statusCode: Int,
            headers: [String: String] = [:],
            data: Data = Data(),
            delayNanoseconds: UInt64 = 0
        ) -> Stub {
            Stub(
                statusCode: statusCode,
                headers: headers,
                data: data,
                delayNanoseconds: delayNanoseconds
            )
        }
    }

    private var stubs: [Stub]
    private var requests: [URLRequest] = []

    init(_ stubs: [Stub]) { self.stubs = stubs }

    func send(_ request: URLRequest) async throws -> ClaudeUsageHTTPResult {
        requests.append(request)
        guard !stubs.isEmpty else { throw ClaudeUsageTestError.missingStub }
        let stub = stubs.removeFirst()
        if stub.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: stub.delayNanoseconds)
        }
        let response: URLResponse
        if let statusCode = stub.statusCode {
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
        } else {
            response = URLResponse(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: stub.data.count,
                textEncodingName: "utf-8"
            )
        }
        return ClaudeUsageHTTPResult(data: stub.data, response: response)
    }

    func requestCount() -> Int { requests.count }
    func authorizationHeaders() -> [String] {
        requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }
    func requestURLs() -> [String] {
        requests.compactMap { $0.url?.absoluteString }
    }
    func userAgentHeaders() -> [String] {
        requests.compactMap { $0.value(forHTTPHeaderField: "User-Agent") }
    }
}

@main
enum ClaudeUsageServiceTests {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await testConcurrentSingleFlight(now: now)
        try await testSuccessfulCacheTTL(now: now)
        try await testResetCreditsUsageAndCacheExpiry(now: now)
        try await testMalformedResetCreditsDoNotFailUsage(now: now)
        try await testRetryAfterVariants(now: now)
        try await testExponentialBackoff(now: now)
        try await testCredentialIsolation(now: now)
        try await testStaleFallbackAndExpiry(now: now)
        try await testUnauthorizedClearsCache(now: now)
        try await testPersistentCooldownAndNoTokenOnDisk(now: now)
        print("Claude usage service tests passed")
    }

    private static func service(
        fake: FakeClaudeUsageTransport,
        clock: TestClock,
        cacheURL: URL? = nil
    ) -> ClaudeUsageService {
        ClaudeUsageService(
            transport: ClaudeUsageTransport { try await fake.send($0) },
            now: { clock.now() },
            cacheURL: cacheURL
        )
    }

    private static func testConcurrentSingleFlight(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 12), delayNanoseconds: 100_000_000),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let token = index.isMultiple(of: 2) ? " shared-token " : "Bearer shared-token"
                    let usage = try await subject.fetchUsage(authToken: token)
                    return usage.rateLimit?.primaryWindow?.usedPercent ?? -1
                }
            }
            var result: [Int] = []
            for try await value in group { result.append(value) }
            return result
        }
        precondition(values.count == 20 && values.allSatisfy { $0 == 12 })
        let requestCount = await fake.requestCount()
        let authorizationHeaders = await fake.authorizationHeaders()
        precondition(requestCount == 1, "Normalized duplicate credentials must share one request")
        precondition(authorizationHeaders == ["Bearer shared-token"])
    }

    private static func testSuccessfulCacheTTL(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 10)),
            .http(200, data: payload(percent: 20)),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        let first = try await subject.fetchUsage(authToken: "ttl-token")
        precondition(first.fetchMetadata?.isStale == false)
        clock.set(now.addingTimeInterval(299))
        let cached = try await subject.fetchUsage(authToken: "ttl-token")
        precondition(cached.rateLimit?.primaryWindow?.usedPercent == 10)
        var requestCount = await fake.requestCount()
        precondition(requestCount == 1)
        clock.set(now.addingTimeInterval(300))
        let refreshed = try await subject.fetchUsage(authToken: "ttl-token")
        precondition(refreshed.rateLimit?.primaryWindow?.usedPercent == 20)
        requestCount = await fake.requestCount()
        precondition(requestCount == 2)
    }

    private static func testResetCreditsUsageAndCacheExpiry(now: Date) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-reset-credit-cache-tests-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = directory.appendingPathComponent("usage-cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let dateFormatter = ISO8601DateFormatter()
        let expiringAt = dateFormatter.string(from: now.addingTimeInterval(60))
        let alreadyExpiredAt = dateFormatter.string(from: now.addingTimeInterval(-60))
        let grants: [[String: Any]] = [
            [
                "id": "expiring-grant",
                "resets_left": 2,
                "resets_total": 2,
                "starts_at": NSNull(),
                "ends_at": expiringAt,
                "clears": ["five_hour"],
                "paused": false,
                "usable_now": true,
                "use_requires_limit": false,
            ],
            [
                "id": "limit-gated-grant",
                "resets_left": 3,
                "resets_total": 3,
                "starts_at": NSNull(),
                "ends_at": NSNull(),
                "clears": ["seven_day", "unknown_scope"],
                "paused": false,
                "usable_now": false,
                "use_requires_limit": true,
            ],
            [
                "id": "already-expired",
                "resets_left": 9,
                "resets_total": 9,
                "starts_at": NSNull(),
                "ends_at": alreadyExpiredAt,
                "clears": ["weekly"],
                "paused": false,
                "usable_now": false,
                "use_requires_limit": false,
            ],
        ]
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 37, cedarEmber: ["eligible": true, "grants": grants])),
        ])
        let clock = TestClock(now)
        let writer = service(fake: fake, clock: clock, cacheURL: cacheURL)
        let fetched = try await writer.fetchUsage(authToken: "synthetic-reset-token")
        precondition(fetched.rateLimit?.primaryWindow?.usedPercent == 37)
        precondition(fetched.rateLimitResetCredits?.availableCount == 5)
        precondition(fetched.rateLimitResetCredits?.credits.count == 2)
        precondition(fetched.rateLimitResetCredits?.credits[1].remainingCount == 3)
        precondition(fetched.rateLimitResetCredits?.credits[1].requiresLimit == true)

        let requestURLs = await fake.requestURLs()
        let userAgents = await fake.userAgentHeaders()
        precondition(
            requestURLs == ["https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1"],
            "Usage and reset grants must be fetched together"
        )
        precondition(
            userAgents == ["claude-cli/2.1.288 (external, cli, client-app/CodexMonitor)"],
            "Use Claude CLI's verified grant-query User-Agent"
        )

        // Simulate an older saved usage entry without per-grant remaining_count.
        // Cache reads must fall back to one reset per grant and discard the expired item.
        var persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as! [String: Any]
        var entries = persisted["entries"] as! [String: Any]
        let cacheKey = entries.keys.first!
        var entry = entries[cacheKey] as! [String: Any]
        var cachedUsage = entry["usage"] as! [String: Any]
        var cachedCredits = cachedUsage["rate_limit_reset_credits"] as! [String: Any]
        var cachedGrants = cachedCredits["credits"] as! [[String: Any]]
        for index in cachedGrants.indices where cachedGrants[index]["id"] as? String == "limit-gated-grant" {
            cachedGrants[index].removeValue(forKey: "remaining_count")
        }
        cachedCredits["credits"] = cachedGrants
        cachedUsage["rate_limit_reset_credits"] = cachedCredits
        entry["usage"] = cachedUsage
        entries[cacheKey] = entry
        persisted["entries"] = entries
        let modifiedCache = try JSONSerialization.data(withJSONObject: persisted, options: [.sortedKeys])
        try modifiedCache.write(to: cacheURL, options: [.atomic])

        clock.set(now.addingTimeInterval(90))
        let cacheReaderTransport = FakeClaudeUsageTransport([])
        let reader = service(fake: cacheReaderTransport, clock: clock, cacheURL: cacheURL)
        let cached = try await reader.fetchUsage(authToken: "synthetic-reset-token")
        precondition(cached.rateLimitResetCredits?.availableCount == 1,
                     "Recount remaining grants after filtering expiration; legacy entries default to one")
        precondition(cached.rateLimitResetCredits?.credits.count == 1)
        precondition(cached.rateLimitResetCredits?.credits.first?.id == "limit-gated-grant")
        precondition(cached.rateLimitResetCredits?.credits.first?.remainingCount == nil)
        precondition(cached.fetchMetadata?.isStale == false)
        let cacheReadRequestCount = await cacheReaderTransport.requestCount()
        precondition(cacheReadRequestCount == 0, "A valid cached usage response must retain its grants")
    }

    private static func testMalformedResetCreditsDoNotFailUsage(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 28, cedarEmber: ["eligible": "malformed", "grants": []])),
        ])
        let subject = service(fake: fake, clock: TestClock(now))
        let usage = try await subject.fetchUsage(authToken: "synthetic-malformed-grant-token")
        precondition(usage.rateLimit?.primaryWindow?.usedPercent == 28)
        precondition(usage.rateLimitResetCredits == nil,
                     "Malformed grant metadata must not discard valid quota usage")
        let requestCount = await fake.requestCount()
        precondition(requestCount == 1)
    }

    private static func testRetryAfterVariants(now: Date) async throws {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        let httpDate = dateFormatter.string(from: now.addingTimeInterval(1_800))

        let cases: [(String?, TimeInterval)] = [
            ("0", 900),
            ("1200", 1_200),
            (httpDate, 1_800),
            ("not-a-retry-value", 900),
        ]
        for (header, expectedDelay) in cases {
            var headers: [String: String] = [:]
            if let header { headers["Retry-After"] = header }
            let fake = FakeClaudeUsageTransport([.http(429, headers: headers)])
            let clock = TestClock(now)
            let subject = service(fake: fake, clock: clock)
            let retryAt = try await requireRateLimit {
                try await subject.fetchUsage(authToken: "retry-\(header ?? "missing")")
            }
            precondition(abs(retryAt.timeIntervalSince(now) - expectedDelay) < 1)
            _ = try await requireRateLimit {
                try await subject.fetchUsage(authToken: "retry-\(header ?? "missing")")
            }
            let requestCount = await fake.requestCount()
            precondition(requestCount == 1, "Cooldown must block network retries")
        }
    }

    private static func testExponentialBackoff(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(429), .http(429), .http(429),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        let first = try await requireRateLimit {
            try await subject.fetchUsage(authToken: "backoff-token")
        }
        precondition(first == now.addingTimeInterval(900))
        clock.set(first)
        let second = try await requireRateLimit {
            try await subject.fetchUsage(authToken: "backoff-token")
        }
        precondition(second == first.addingTimeInterval(1_800))
        clock.set(second)
        let third = try await requireRateLimit {
            try await subject.fetchUsage(authToken: "backoff-token")
        }
        precondition(third == second.addingTimeInterval(3_600))
    }

    private static func testCredentialIsolation(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 44)),
            .http(429, headers: ["Retry-After": "0"]),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        _ = try await subject.fetchUsage(authToken: "account-a")
        _ = try await requireRateLimit {
            try await subject.fetchUsage(authToken: "account-b")
        }
        let accountA = try await subject.fetchUsage(authToken: "account-a")
        precondition(accountA.rateLimit?.primaryWindow?.usedPercent == 44)
        precondition(accountA.fetchMetadata?.isStale == false)
        let requestCount = await fake.requestCount()
        precondition(requestCount == 2, "Credentials must have isolated cache and cooldown state")
    }

    private static func testStaleFallbackAndExpiry(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 52)),
            .http(429, headers: ["Retry-After": "0"]),
            .http(429, headers: ["Retry-After": "0"]),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        _ = try await subject.fetchUsage(authToken: "stale-token")
        clock.set(now.addingTimeInterval(301))
        let stale = try await subject.fetchUsage(authToken: "stale-token")
        precondition(stale.rateLimit?.primaryWindow?.usedPercent == 52)
        precondition(stale.fetchMetadata?.isStale == true)
        precondition(stale.fetchMetadata?.retryAt == now.addingTimeInterval(1_201))
        let encoded = try JSONEncoder().encode(stale)
        let encodedText = String(decoding: encoded, as: UTF8.self)
        precondition(!encodedText.contains("fetchMetadata") && !encodedText.contains("isStale"))

        _ = try await subject.fetchUsage(authToken: "stale-token")
        var requestCount = await fake.requestCount()
        precondition(requestCount == 2, "Stale cooldown reads must not call the network")

        clock.set(now.addingTimeInterval(1_801))
        _ = try await requireRateLimit {
            try await subject.fetchUsage(authToken: "stale-token")
        }
        requestCount = await fake.requestCount()
        precondition(requestCount == 3, "Cache older than 30 minutes must not be reused")
    }

    private static func testUnauthorizedClearsCache(now: Date) async throws {
        let fake = FakeClaudeUsageTransport([
            .http(200, data: payload(percent: 63)),
            .http(401),
            .http(500),
        ])
        let clock = TestClock(now)
        let subject = service(fake: fake, clock: clock)
        _ = try await subject.fetchUsage(authToken: "unauthorized-token")
        clock.set(now.addingTimeInterval(301))
        try await requireUnauthorized {
            try await subject.fetchUsage(authToken: "unauthorized-token")
        }
        try await requireHTTPError(500) {
            try await subject.fetchUsage(authToken: "unauthorized-token")
        }
        let requestCount = await fake.requestCount()
        precondition(requestCount == 3, "401 must clear stale cache before the next failure")
    }

    private static func testPersistentCooldownAndNoTokenOnDisk(now: Date) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-tests-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = directory.appendingPathComponent("usage-cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let token = "never-persist-this-token"
        let firstTransport = FakeClaudeUsageTransport([
            .http(429, headers: ["Retry-After": "1200"]),
        ])
        let clock = TestClock(now)
        let firstService = service(fake: firstTransport, clock: clock, cacheURL: cacheURL)
        let retryAt = try await requireRateLimit {
            try await firstService.fetchUsage(authToken: token)
        }
        let diskText = String(decoding: try Data(contentsOf: cacheURL), as: UTF8.self)
        precondition(!diskText.contains(token), "Persistent cache must never store a credential")
        precondition(!diskText.contains("Bearer"))

        clock.set(now.addingTimeInterval(60))
        let restartTransport = FakeClaudeUsageTransport([])
        let restarted = service(fake: restartTransport, clock: clock, cacheURL: cacheURL)
        let restoredRetryAt = try await requireRateLimit {
            try await restarted.fetchUsage(authToken: token)
        }
        precondition(restoredRetryAt == retryAt)
        let restartRequestCount = await restartTransport.requestCount()
        precondition(restartRequestCount == 0, "Restart must not bypass persisted cooldown")
    }

    private static func requireRateLimit(
        _ operation: () async throws -> UsageResponse
    ) async throws -> Date {
        do {
            _ = try await operation()
        } catch ClaudeUsageError.rateLimited(let retryAt) {
            return retryAt
        }
        throw ClaudeUsageTestError.expectedRateLimit
    }

    private static func requireUnauthorized(
        _ operation: () async throws -> UsageResponse
    ) async throws {
        do {
            _ = try await operation()
        } catch ClaudeUsageError.unauthorized {
            return
        }
        throw ClaudeUsageTestError.expectedUnauthorized
    }

    private static func requireHTTPError(
        _ statusCode: Int,
        operation: () async throws -> UsageResponse
    ) async throws {
        do {
            _ = try await operation()
        } catch ClaudeUsageError.httpError(let actual) where actual == statusCode {
            return
        }
        throw ClaudeUsageTestError.expectedHTTPError
    }

    private static func payload(percent: Double, cedarEmber: [String: Any]? = nil) -> Data {
        let reset = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_900_000_000))
        var root: [String: Any] = [
            "five_hour": ["utilization": percent, "resets_at": reset],
            "seven_day": ["utilization": percent / 2, "resets_at": reset],
        ]
        if let cedarEmber {
            root["cedar_ember"] = cedarEmber
        }
        return try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
