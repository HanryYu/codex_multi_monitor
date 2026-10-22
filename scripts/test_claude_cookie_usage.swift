import Foundation

private enum ClaudeCookieTestError: Error {
    case missingStub
    case expectedFailure
}

private final class ClaudeCookieTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Date) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}

private actor ClaudeCookieTestTransport {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let data: Data

        static func http(_ statusCode: Int, headers: [String: String] = [:], data: Data = Data()) -> Stub {
            Stub(statusCode: statusCode, headers: headers, data: data)
        }
    }

    private var stubs: [Stub]
    private var requests: [URLRequest] = []

    init(_ stubs: [Stub]) { self.stubs = stubs }

    func send(_ request: URLRequest) async throws -> ClaudeUsageHTTPResult {
        requests.append(request)
        guard !stubs.isEmpty else { throw ClaudeCookieTestError.missingStub }
        let stub = stubs.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        return ClaudeUsageHTTPResult(data: stub.data, response: response)
    }

    func requestSnapshot() -> [URLRequest] { requests }
}

@main
enum ClaudeCookieUsageTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let orgA = "11111111-2222-3333-4444-555555555555"
    private static let orgB = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    private static let syntheticCookie = "sessionKey=sk-ant-sid01-synthetic-secret"

    static func main() async throws {
        try testCredentialParsingAndValidation()
        try testBrowserCookieCompatibility()
        try testOrganizationIDNormalization()
        try await testBrowserCookieRequestPreservesValues()
        try await testExplicitOrganizationAndCookieRouting()
        try await testLastActiveAndSingleOrganizationSelection()
        try await testAmbiguousOrganizationIsRejected()
        try await testOrganizationScopedAndModeScopedCache()
        try await testOrganizationAndUsageCooldowns()
        try await testCookiePersistentCooldownAndSecretRedaction()
        try await testCookieStaleFallbackExpires()
        try await testUnauthorizedClearsCookieCache()
        try await testAccessBlockedAndHTMLResponses()
        try await testUsagePayloadValidationAndPartialWindows()
        try testRedirectAndSessionPolicy()
        print("Claude Cookie usage tests passed")
    }

    private static func testCredentialParsingAndValidation() throws {
        let oauthInputs = [
            "legacy-oauth-token",
            "Bearer legacy-oauth-token",
            "Authorization: Bearer legacy-oauth-token",
            "YWI=",
            "YWJjZA==",
            """
            {
              "claudeAiOauth": {
                "accessToken": "json-oauth-token",
                "refreshToken": "synthetic-refresh"
              }
            }
            """,
        ]
        let expectedOAuthTokens = [
            "legacy-oauth-token",
            "legacy-oauth-token",
            "legacy-oauth-token",
            "YWI=",
            "YWJjZA==",
            "json-oauth-token",
        ]
        for (input, expected) in zip(oauthInputs, expectedOAuthTokens) {
            let credential = try ClaudeUsageCredential.parse(input)
            precondition(!credential.isCookie)
            precondition(credential.normalizedValue == expected)
        }

        let completeHeader = "Cookie: __Host-csrf=synthetic; SessionKey=sk-ant-sid01-cookie-secret; lastActiveOrg=\(orgB)"
        let parsedHeader = try ClaudeUsageCredential.parse(completeHeader)
        precondition(parsedHeader.isCookie)
        precondition(parsedHeader.normalizedValue == "__Host-csrf=synthetic; sessionKey=sk-ant-sid01-cookie-secret; lastActiveOrg=\(orgB)")
        precondition(parsedHeader.lastActiveOrganizationID == orgB)
        let sessionKeyOnly = try ClaudeUsageCredential.parse("sessionKey=synthetic")
        let rawCookie = try ClaudeUsageCredential.parse("sk-ant-sid01-raw-cookie")
        let copiedOAuth = try ClaudeUsageCredential.parse("\nlegacy-copied-token\n")
        precondition(sessionKeyOnly.normalizedValue == "sessionKey=synthetic")
        precondition(rawCookie.normalizedValue == "sessionKey=sk-ant-sid01-raw-cookie")
        precondition(copiedOAuth.normalizedValue == "legacy-copied-token")

        let invalidCookies = [
            "Cookie: anotherCookie=value",
            "anotherCookie=value",
            "sessionKey=",
            "Cookie: sessionKey=one; SessionKey=two",
            "Cookie: sessionKey=one\r\nAuthorization: Bearer leaked",
            "Cookie: sessionKey=has internal space",
        ]
        for value in invalidCookies {
            do {
                _ = try ClaudeUsageCredential.parse(value)
                throw ClaudeCookieTestError.expectedFailure
            } catch is ClaudeUsageCredentialError {
                // Expected: malformed Cookie input cannot fall through to OAuth.
            }
        }
        do {
            _ = try ClaudeUsageCredential.parse("Bearer token\r\nInjected: header")
            throw ClaudeCookieTestError.expectedFailure
        } catch is ClaudeUsageCredentialError { }
    }

    private static func testBrowserCookieCompatibility() throws {
        // Synthetic browser-style values: consent JSON, quoted IDs and punctuation.
        // None of these unrelated cookies should invalidate a valid sessionKey.
        let header = #"sessionKey=synthetic; consent={"analytics":true,"ads":false}; label="test value"; path=C:\fixture; lastActiveOrg="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee""#
        let credential = try ClaudeUsageCredential.parse("Cookie: " + header)
        precondition(credential.isCookie && credential.normalizedValue == header)
        precondition(credential.lastActiveOrganizationID == orgB)
        let quotedSession = try ClaudeUsageCredential.parse(#"sessionKey="synthetic""#)
        precondition(quotedSession.normalizedValue == #"sessionKey="synthetic""#)
        let singleSpaced = try ClaudeUsageCredential.parse("sessionKey = synthetic")
        precondition(singleSpaced.normalizedValue == "sessionKey=synthetic")
        let copied = try ClaudeUsageCredential.parse("sessionKey = synthetic; ; lastActiveOrg = \(orgA); ")
        precondition(copied.normalizedValue == "sessionKey=synthetic; lastActiveOrg=\(orgA)")
        for invalid in [
            #"sessionKey="""#,
            "sessionKey=one; sessionKey=two; consent={\"ok\":true}",
            "sessionKey=one; consent=ok\r\nAuthorization: Bearer injected",
            "sessionKey=one; consent=ok\u{0}bad",
            "sessionKey=one; consent=ok\u{7F}bad",
            "sessionKey=one; broken-fragment",
        ] {
            do {
                _ = try ClaudeUsageCredential.parse(invalid)
                throw ClaudeCookieTestError.expectedFailure
            } catch is ClaudeUsageCredentialError { }
        }
    }

    private static func testOrganizationIDNormalization() throws {
        let normalizedA = try ClaudeUsageCredential.normalizedOrganizationID("  \(orgA.uppercased())  ")
        let normalizedB = try ClaudeUsageCredential.normalizedOrganizationID(
            "https://claude.ai/api/organizations/\(orgB.uppercased())/usage"
        )
        let emptyValue = try ClaudeUsageCredential.normalizedOrganizationID("  ")
        precondition(normalizedA == orgA)
        precondition(normalizedB == orgB)
        precondition(emptyValue == nil)
        do {
            _ = try ClaudeUsageCredential.normalizedOrganizationID("https://example.test/\(orgA)")
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageCredentialError.invalidOrganizationID { }
    }

    private static func testBrowserCookieRequestPreservesValues() async throws {
        let cookie = #"sessionKey=synthetic; consent={"analytics":true,"ads":false}; label="test value"; path=C:\fixture"#
        let fake = ClaudeCookieTestTransport([.http(200, data: usagePayload(fiveHour: 37))])
        let usage = try await service(fake: fake).fetchUsage(authToken: "Cookie: " + cookie, organizationID: orgA)
        precondition(usage.rateLimit?.primaryWindow?.usedPercent == 37)
        let requests = await fake.requestSnapshot()
        precondition(requests.count == 1)
        assertCookieRequest(requests[0], path: "/api/organizations/\(orgA)/usage", cookie: cookie)
    }

    private static func testExplicitOrganizationAndCookieRouting() async throws {
        let fake = ClaudeCookieTestTransport([.http(200, data: usagePayload(fiveHour: 37))])
        let subject = service(fake: fake)
        let urlValue = "https://claude.ai/api/organizations/\(orgA)/usage"
        let usage = try await subject.fetchUsage(authToken: syntheticCookie, organizationID: urlValue)
        precondition(usage.rateLimit?.primaryWindow?.usedPercent == 37)
        precondition(usage.rateLimit?.secondaryWindow == nil)

        let requests = await fake.requestSnapshot()
        precondition(requests.count == 1, "Explicit organization avoids an unnecessary organization-list request")
        let request = requests[0]
        assertCookieRequest(request, path: "/api/organizations/\(orgA)/usage", cookie: syntheticCookie)
        precondition(request.httpMethod == "GET")
        precondition(request.httpShouldHandleCookies == false)
    }

    private static func testLastActiveAndSingleOrganizationSelection() async throws {
        let list = organizationsPayload([orgA, orgB])
        let activeCookie = "sessionKey=synthetic-active; lastActiveOrg=\(orgB)"
        let activeTransport = ClaudeCookieTestTransport([
            .http(200, data: list),
            .http(200, data: usagePayload(sevenDay: 63)),
        ])
        let activeUsage = try await service(fake: activeTransport).fetchUsage(authToken: activeCookie)
        precondition(activeUsage.rateLimit?.primaryWindow == nil)
        precondition(activeUsage.rateLimit?.secondaryWindow?.usedPercent == 63)
        let activeRequests = await activeTransport.requestSnapshot()
        precondition(activeRequests.count == 2)
        assertCookieRequest(activeRequests[0], path: "/api/organizations", cookie: activeCookie)
        assertCookieRequest(activeRequests[1], path: "/api/organizations/\(orgB)/usage", cookie: activeCookie)

        let singleTransport = ClaudeCookieTestTransport([
            .http(200, data: organizationsPayload([orgA])),
            .http(200, data: usagePayload(fiveHour: 21)),
        ])
        _ = try await service(fake: singleTransport).fetchUsage(authToken: "sessionKey=synthetic-single")
        let singleRequests = await singleTransport.requestSnapshot()
        precondition(singleRequests.count == 2)
        assertCookieRequest(singleRequests[0], path: "/api/organizations", cookie: "sessionKey=synthetic-single")
        assertCookieRequest(singleRequests[1], path: "/api/organizations/\(orgA)/usage", cookie: "sessionKey=synthetic-single")
    }

    private static func testAmbiguousOrganizationIsRejected() async throws {
        let fake = ClaudeCookieTestTransport([.http(200, data: organizationsPayload([orgA, orgB]))])
        do {
            _ = try await service(fake: fake).fetchUsage(authToken: "sessionKey=synthetic-ambiguous")
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.organizationSelectionRequired { }
        let requests = await fake.requestSnapshot()
        precondition(requests.count == 1, "Ambiguous sessions must not select an arbitrary organization")
        assertCookieRequest(requests[0], path: "/api/organizations", cookie: "sessionKey=synthetic-ambiguous")

        let empty = ClaudeCookieTestTransport([.http(200, data: organizationsPayload([]))])
        do {
            _ = try await service(fake: empty).fetchUsage(authToken: "sessionKey=synthetic-no-org")
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.noOrganizations { }
    }

    private static func testOrganizationScopedAndModeScopedCache() async throws {
        let fake = ClaudeCookieTestTransport([
            .http(200, data: usagePayload(fiveHour: 10)),
            .http(200, data: usagePayload(fiveHour: 20)),
            .http(200, data: usagePayload(fiveHour: 30)),
        ])
        let subject = service(fake: fake)
        let first = try await subject.fetchUsage(authToken: syntheticCookie, organizationID: orgA)
        let cached = try await subject.fetchUsage(authToken: syntheticCookie, organizationID: orgA)
        let otherOrganization = try await subject.fetchUsage(authToken: syntheticCookie, organizationID: orgB)
        let oauth = try await subject.fetchUsage(authToken: "same-credential")
        precondition(first.rateLimit?.primaryWindow?.usedPercent == 10)
        precondition(cached.rateLimit?.primaryWindow?.usedPercent == 10)
        precondition(otherOrganization.rateLimit?.primaryWindow?.usedPercent == 20)
        precondition(oauth.rateLimit?.primaryWindow?.usedPercent == 30)
        let requests = await fake.requestSnapshot()
        precondition(requests.count == 3, "Cookie cache is scoped by organization and separate from OAuth")
        precondition(requests[0].url?.host == "claude.ai")
        precondition(requests[1].url?.path == "/api/organizations/\(orgB)/usage")
        precondition(requests[2].url?.host == "api.anthropic.com")
        precondition(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer same-credential")
        precondition(requests[2].value(forHTTPHeaderField: "Cookie") == nil)
    }

    private static func testOrganizationAndUsageCooldowns() async throws {
        let orgRateLimit = ClaudeCookieTestTransport([
            .http(429, headers: ["Retry-After": "1200"]),
        ])
        let orgService = service(fake: orgRateLimit)
        try await expectRateLimit {
            try await orgService.fetchUsage(authToken: "sessionKey=synthetic-org-429")
        }
        try await expectRateLimit {
            try await orgService.fetchUsage(authToken: "sessionKey=synthetic-org-429")
        }
        let orgRequests = await orgRateLimit.requestSnapshot()
        precondition(orgRequests.count == 1, "Organization 429 must enter cooldown")
        assertCookieRequest(orgRequests[0], path: "/api/organizations", cookie: "sessionKey=synthetic-org-429")

        let usageRateLimit = ClaudeCookieTestTransport([
            .http(429, headers: ["Retry-After": "1200"]),
            .http(200, data: usagePayload(fiveHour: 22)),
        ])
        let usageService = service(fake: usageRateLimit)
        try await expectRateLimit {
            try await usageService.fetchUsage(authToken: "sessionKey=synthetic-usage-429", organizationID: orgA)
        }
        try await expectRateLimit {
            try await usageService.fetchUsage(authToken: "sessionKey=synthetic-usage-429", organizationID: orgA)
        }
        let otherOrganization = try await usageService.fetchUsage(
            authToken: "sessionKey=synthetic-usage-429",
            organizationID: orgB
        )
        precondition(otherOrganization.rateLimit?.primaryWindow?.usedPercent == 22)
        let usageRequests = await usageRateLimit.requestSnapshot()
        precondition(usageRequests.count == 2, "A cooldown for one organization must not block another")
        assertCookieRequest(usageRequests[0], path: "/api/organizations/\(orgA)/usage", cookie: "sessionKey=synthetic-usage-429")
        assertCookieRequest(usageRequests[1], path: "/api/organizations/\(orgB)/usage", cookie: "sessionKey=synthetic-usage-429")
    }

    private static func testCookiePersistentCooldownAndSecretRedaction() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("claude-cookie-cache-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = directory.appendingPathComponent("usage-cache.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let credential = "sessionKey=synthetic-cookie-persisted-secret"
        let firstTransport = ClaudeCookieTestTransport([.http(429, headers: ["Retry-After": "1200"])])
        let clock = ClaudeCookieTestClock(now)
        let firstService = service(fake: firstTransport, clock: clock, cacheURL: cacheURL)
        try await expectRateLimit {
            try await firstService.fetchUsage(authToken: credential, organizationID: orgA)
        }

        let cacheText = try String(contentsOf: cacheURL, encoding: .utf8)
        precondition(!cacheText.contains("sessionKey"))
        precondition(!cacheText.contains("synthetic-cookie-persisted-secret"))

        let secondTransport = ClaudeCookieTestTransport([.http(200, data: usagePayload(fiveHour: 55))])
        let rebuiltService = service(fake: secondTransport, clock: clock, cacheURL: cacheURL)
        do {
            _ = try await rebuiltService.fetchUsage(authToken: credential, organizationID: orgA)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.rateLimited { }
        let secondRequests = await secondTransport.requestSnapshot()
        precondition(secondRequests.isEmpty, "Persisted Cookie cooldown must survive service recreation")
    }

    private static func testCookieStaleFallbackExpires() async throws {
        let fake = ClaudeCookieTestTransport([
            .http(200, data: usagePayload(fiveHour: 44)),
            .http(503),
            .http(503),
        ])
        let clock = ClaudeCookieTestClock(now)
        let subject = service(fake: fake, clock: clock)
        _ = try await subject.fetchUsage(authToken: "sessionKey=synthetic-cookie-stale", organizationID: orgA)

        clock.set(now.addingTimeInterval(301))
        let staleUsage = try await subject.fetchUsage(
            authToken: "sessionKey=synthetic-cookie-stale",
            organizationID: orgA
        )
        precondition(staleUsage.rateLimit?.primaryWindow?.usedPercent == 44)
        precondition(staleUsage.fetchMetadata?.isStale == true)

        clock.set(now.addingTimeInterval(1_801))
        do {
            _ = try await subject.fetchUsage(authToken: "sessionKey=synthetic-cookie-stale", organizationID: orgA)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.httpError(let statusCode) {
            precondition(statusCode == 503)
        }
        let requests = await fake.requestSnapshot()
        precondition(requests.count == 3)
        requests.forEach {
            assertCookieRequest($0, path: "/api/organizations/\(orgA)/usage", cookie: "sessionKey=synthetic-cookie-stale")
        }
    }

    private static func testUnauthorizedClearsCookieCache() async throws {
        let fake = ClaudeCookieTestTransport([
            .http(200, data: usagePayload(fiveHour: 44)),
            .http(401),
            .http(500),
        ])
        let clock = ClaudeCookieTestClock(now)
        let subject = service(fake: fake, clock: clock)
        _ = try await subject.fetchUsage(authToken: "sessionKey=synthetic-cookie-401", organizationID: orgA)
        clock.set(now.addingTimeInterval(301))
        do {
            _ = try await subject.fetchUsage(authToken: "sessionKey=synthetic-cookie-401", organizationID: orgA)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.unauthorized { }
        do {
            _ = try await subject.fetchUsage(authToken: "sessionKey=synthetic-cookie-401", organizationID: orgA)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.httpError(let statusCode) {
            precondition(statusCode == 500)
        }
        let requests = await fake.requestSnapshot()
        precondition(requests.count == 3, "401 must discard the cookie usage cache")
    }

    private static func testAccessBlockedAndHTMLResponses() async throws {
        let blocked = ClaudeCookieTestTransport([.http(403)])
        do {
            _ = try await service(fake: blocked).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.accessBlocked { }
        assertCookieRequest((await blocked.requestSnapshot())[0], path: "/api/organizations/\(orgA)/usage", cookie: syntheticCookie)

        for htmlStub in [
            ClaudeCookieTestTransport.Stub.http(200, headers: ["Content-Type": "text/html"], data: Data("challenge".utf8)),
            .http(200, data: Data("<!doctype html><html>challenge</html>".utf8)),
        ] {
            let html = ClaudeCookieTestTransport([htmlStub])
            do {
                _ = try await service(fake: html).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
                throw ClaudeCookieTestError.expectedFailure
            } catch ClaudeUsageError.accessBlocked { }
            assertCookieRequest((await html.requestSnapshot())[0], path: "/api/organizations/\(orgA)/usage", cookie: syntheticCookie)
        }

        let organizationHTML = ClaudeCookieTestTransport([
            .http(200, headers: ["Content-Type": "text/html"], data: Data("<html>verify</html>".utf8)),
        ])
        do {
            _ = try await service(fake: organizationHTML).fetchUsage(authToken: syntheticCookie)
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.accessBlocked { }
        assertCookieRequest(
            (await organizationHTML.requestSnapshot())[0],
            path: "/api/organizations",
            cookie: syntheticCookie
        )
    }

    private static func testUsagePayloadValidationAndPartialWindows() async throws {
        let fiveOnly = ClaudeCookieTestTransport([.http(200, data: usagePayload(fiveHour: 19))])
        let fiveUsage = try await service(fake: fiveOnly).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
        precondition(fiveUsage.rateLimit?.primaryWindow?.usedPercent == 19)
        precondition(fiveUsage.rateLimit?.secondaryWindow == nil)

        let weekOnly = ClaudeCookieTestTransport([.http(200, data: usagePayload(sevenDay: 71))])
        let weekUsage = try await service(fake: weekOnly).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
        precondition(weekUsage.rateLimit?.primaryWindow == nil)
        precondition(weekUsage.rateLimit?.secondaryWindow?.usedPercent == 71)

        for invalidPayload in [Data("{}".utf8), Data(#"{"five_hour":{"utilization":"unknown"}}"#.utf8)] {
            let invalid = ClaudeCookieTestTransport([.http(200, data: invalidPayload)])
            do {
                _ = try await service(fake: invalid).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
                throw ClaudeCookieTestError.expectedFailure
            } catch ClaudeUsageError.invalidResponse { }
        }

        let extreme = ClaudeCookieTestTransport([.http(200, data: usagePayload(fiveHour: 1e308))])
        let extremeUsage = try await service(fake: extreme).fetchUsage(authToken: syntheticCookie, organizationID: orgA)
        precondition(extremeUsage.rateLimit?.primaryWindow?.usedPercent == 100)
    }

    private static func testRedirectAndSessionPolicy() throws {
        let configuration = ClaudeUsageTransport.makeEphemeralConfiguration()
        precondition(configuration.httpCookieStorage == nil)
        precondition(configuration.httpShouldSetCookies == false)
        precondition(configuration.urlCache == nil)
        precondition(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        let request = URLRequest(url: URL(string: "https://example.test/redirect-target")!)
        precondition(ClaudeUsageRedirectPolicy.redirectedRequest(request) == nil)
    }

    private static func service(
        fake: ClaudeCookieTestTransport,
        clock: ClaudeCookieTestClock? = nil,
        cacheURL: URL? = nil
    ) -> ClaudeUsageService {
        let clock = clock ?? ClaudeCookieTestClock(now)
        return ClaudeUsageService(
            transport: ClaudeUsageTransport { try await fake.send($0) },
            now: { clock.now() },
            cacheURL: cacheURL
        )
    }

    private static func assertCookieRequest(_ request: URLRequest, path: String, cookie: String) {
        precondition(request.url?.scheme == "https")
        precondition(request.url?.host == "claude.ai")
        precondition(request.url?.path == path)
        precondition(request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "Cookie") == cookie)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Origin") == "https://claude.ai")
        precondition(request.value(forHTTPHeaderField: "Referer") == "https://claude.ai/settings/usage")
        precondition(request.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
    }

    private static func expectRateLimit(
        _ operation: () async throws -> UsageResponse
    ) async throws {
        do {
            _ = try await operation()
            throw ClaudeCookieTestError.expectedFailure
        } catch ClaudeUsageError.rateLimited { }
    }

    private static func organizationsPayload(_ identifiers: [String]) -> Data {
        let value: [[String: String]] = identifiers.map { ["uuid": $0] }
        return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func usagePayload(fiveHour: Double? = nil, sevenDay: Double? = nil) -> Data {
        let reset = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_900_000_000))
        var root: [String: Any] = [:]
        if let fiveHour { root["five_hour"] = ["utilization": fiveHour, "resets_at": reset] }
        if let sevenDay { root["seven_day"] = ["utilization": sevenDay, "resets_at": reset] }
        return try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

