import Foundation

// Standalone compatibility shim for compiling the provider service without the app target.
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case decodingError(Error)
    case unsupported
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        default: return String(describing: self)
        }
    }
}

@main
enum OpenCodeGoUsageProbe {
    static func main() async throws {
        let service = OpenCodeGoUsageService.shared

        let rawTokenCookie = try service.normalizedCookieHeader("Fe26.2**token")
        precondition(rawTokenCookie == "auth=Fe26.2**token")
        let hostCookie = try service.normalizedCookieHeader(
            "theme=dark; __Host-console_session=console; __Host-auth=session; ignored=value"
        )
        precondition(hostCookie == "__Host-console_session=console; __Host-auth=session")
        let cookieHeader = try service.normalizedCookieHeader(
            "Cookie: tracking=x; auth=legacy; __Host-console_session=console; theme=dark"
        )
        precondition(cookieHeader == "auth=legacy; __Host-console_session=console")
        let apiKey = try service.normalizedCredential(" Bearer sk-test_only ")
        precondition(apiKey == "sk-test_only")
        precondition(service.isAPIKeyCredential("Bearer sk-test_only"))
        precondition(!service.isAPIKeyCredential("auth=sk-cookie"))
        expectFailure { _ = try service.normalizedCredential("sk-key\r\nInjected: value") }
        expectFailure { _ = try service.normalizedCredential("not-a-cookie-or-key") }
        precondition(
            service.parseWorkspaceIDs(#"{workspaces:[{id:"wrk_ABC123"},{id:'wk_Z9'}]}"#)
                == ["wrk_ABC123", "wk_Z9"]
        )
        precondition(service.parseWorkspaceIDs(#"{"id":"wrk_JSON123"}"#) == ["wrk_JSON123"])
        let normalizedOrgID = try service.normalizedWorkspaceID("org_CONSOLE")
        let normalizedConsoleURL = try service.normalizedWorkspaceID("https://opencode.ai/console/org_CONSOLE/go")
        let normalizedLegacyURL = try service.normalizedWorkspaceID("https://opencode.ai/workspace/wrk_LEGACY/go")
        precondition(normalizedOrgID == "org_CONSOLE")
        precondition(normalizedConsoleURL == "org_CONSOLE")
        precondition(normalizedLegacyURL == "wrk_LEGACY")
        expectFailure { _ = try service.normalizedWorkspaceID("https://evil.example/console/org_BAD/go") }

        let consoleNow = Date(timeIntervalSince1970: 1_800_000_000)
        let consolePayload = #"""
        {
          "access": {
            "endsAt": "2027-01-15T10:00:00.000Z",
            "meters": {
              "fiveHour": {"usedMicroCents":"250","limitMicroCents":"1000","resetsAt":"2027-01-15T09:00:00.000Z"},
              "week": {"usedMicroCents":510,"limitMicroCents":1000,"resetsAt":null},
              "month": {"usedMicroCents":"900","limitMicroCents":"1000","resetsAt":null}
            }
          }
        }
        """#
        let console = try service.parseConsoleUsage(Data(consolePayload.utf8), now: consoleNow)
        precondition(console.planType == "OpenCode Go")
        precondition(console.rateLimit?.primaryWindow?.usedPercent == 25)
        precondition(console.rateLimit?.primaryWindow?.resetAt == 1_800_003_600)
        precondition(console.rateLimit?.primaryWindow?.resetAfterSeconds == 3_600)
        precondition(console.rateLimit?.secondaryWindow?.usedPercent == 51)
        precondition(console.rateLimit?.secondaryWindow?.resetAt == 0)
        precondition(console.rateLimit?.secondaryWindow?.resetAfterSeconds == 0)
        precondition(console.rateLimit?.tertiaryWindow?.usedPercent == 90)
        precondition(console.rateLimit?.tertiaryWindow?.resetAt == 1_800_007_200)
        precondition(console.rateLimit?.tertiaryWindow?.resetAfterSeconds == 7_200)
        precondition(console.rateLimit?.allowed == true)

        let workspaces = try service.parseConsoleWorkspaceIDs(Data(#"""
        [
          {"id":"org_CONSOLE"}, {"id":"org_CONSOLE"},
          {"id":"wrk_LEGACY"}, {"id":"invalid"}, {"id":"wk_SHORT"}
        ]
        """#.utf8))
        precondition(workspaces == ["org_CONSOLE", "wrk_LEGACY", "wk_SHORT"])
        for invalidConsolePayload in [
            #"{"access":null}"#,
            #"{"access":{"meters":{"fiveHour":{"usedMicroCents":"-1","limitMicroCents":"1000","resetsAt":null}}}}"#,
            #"{"access":{"meters":{"fiveHour":{"usedMicroCents":"1","limitMicroCents":"0","resetsAt":null}}}}"#,
            #"{"access":{"meters":{"fiveHour":{"usedMicroCents":"1","limitMicroCents":"1000","resetsAt":"invalid"}}}}"#,
            #"null"#
        ] {
            expectFailure { _ = try service.parseConsoleUsage(Data(invalidConsolePayload.utf8), now: consoleNow) }
        }
        let onlyFiveHour = try service.parseConsoleUsage(Data(#"""
        {"access":{"meters":{"fiveHour":{"usedMicroCents":"1","limitMicroCents":"1000","resetsAt":null}}}}
        """#.utf8), now: consoleNow)
        precondition(onlyFiveHour.rateLimit?.secondaryWindow == nil)
        precondition(onlyFiveHour.rateLimit?.tertiaryWindow == nil)

        let dashboardHTML = #"""
        <script>window.data={
          rollingUsage:{usagePercent:12,resetInSec:1800},
          weeklyUsage:{usagePercent:34.4,resetInSec:259200},
          monthlyUsage:{usagePercent:56,resetInSec:1728000}
        }</script>
        """#
        let dashboard = try service.parseDashboardUsage(dashboardHTML)
        precondition(dashboard.planType == "OpenCode Go")
        precondition(dashboard.rateLimit?.primaryWindow?.usedPercent == 12)
        precondition(dashboard.rateLimit?.secondaryWindow?.usedPercent == 34)
        precondition(dashboard.rateLimit?.tertiaryWindow?.usedPercent == 56)

        let quotedDashboard = try service.parseDashboardUsage(
            #"{"rollingUsage":{"usagePercent":1,"resetInSec":60},"weeklyUsage":{"usagePercent":2,"resetInSec":120}}"#
        )
        precondition(quotedDashboard.rateLimit?.primaryWindow?.usedPercent == 1)
        precondition(quotedDashboard.rateLimit?.secondaryWindow?.usedPercent == 2)

        expectFailure {
            _ = try service.parseDashboardUsage(
                "rollingUsage:{usagePercent:12,resetInSec:1800}"
            )
        }

        // New dashboard: weighted usage and limit have matching microcent units.
        // A $1 cost with a 4x multiplier uses 4/12 of the shared rolling quota.
        let weighted = try service.parseDashboardUsage(#"""
        rollingUsage:{status:"ok",usage:400000000,limit:1200000000,usagePercent:33.3,resetInSec:1800},
        weeklyUsage:{status:"ok",usage:2999700000,limit:3000000000,usagePercent:100,resetInSec:300},
        monthlyUsage:{status:"rate-limited",usage:6100000000,limit:6000000000,usagePercent:101.7,resetInSec:900}
        """#)
        precondition(weighted.rateLimit?.primaryWindow?.usedPercent == 33)
        precondition(weighted.rateLimit?.secondaryWindow?.usedPercent == 99)
        precondition(weighted.rateLimit?.tertiaryWindow?.usedPercent == 100)
        precondition(weighted.rateLimit?.limitReached == true)

        let nearLimit = try service.parseDashboardUsage(#"""
        rollingUsage:{status:"ok",usagePercent:100,resetInSec:60},
        weeklyUsage:{usagePercent:99.9,resetInSec:120}
        """#)
        precondition(nearLimit.rateLimit?.primaryWindow?.usedPercent == 99)
        precondition(nearLimit.rateLimit?.secondaryWindow?.usedPercent == 99)
        precondition(nearLimit.rateLimit?.allowed == true)

        // Do not parse the following window, nested detail, or a numeric prefix.
        for badWindow in ["null", "{details:{usagePercent:50,resetInSec:60}}",
                          "{usagePercent:1e999,resetInSec:60}",
                          "{usagePercent:12oops,resetInSec:60}",
                          "{usagePercent:12,resetInSec:1e99}",
                          "{usage:12,limit:0,usagePercent:12,resetInSec:60}"] {
            expectFailure {
                _ = try service.parseDashboardUsage("rollingUsage:\(badWindow),weeklyUsage:{usagePercent:2,resetInSec:60}")
            }
        }
        let serialized = try service.parseDashboardUsage(#"""
        rollingUsage:($R[1]={note:"text with } and ,",usagePercent:20,resetInSec:60}),
        weeklyUsage:{usagePercent:30,resetInSec:120}
        """#)
        precondition(serialized.rateLimit?.primaryWindow?.usedPercent == 20)
        let placeholders = try service.parseDashboardUsage(#"""
        rollingUsage:{},weeklyUsage:{},monthlyUsage:{},
        rollingUsage:{usagePercent:12,resetInSec:60},
        weeklyUsage:{usagePercent:34,resetInSec:120},
        monthlyUsage:{usagePercent:56,resetInSec:180}
        """#)
        precondition(placeholders.rateLimit?.primaryWindow?.usedPercent == 12)
        precondition(placeholders.rateLimit?.tertiaryWindow?.usedPercent == 56)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let apiPayload = #"""
        {"usage":{
          "rolling":{"status":"ok","percent":99.9,"resetsAt":"2027-01-15T09:00:00.000Z"},
          "weekly":{"status":"ok","percent":42,"resetsAt":"2027-01-18T08:00:00Z"},
          "monthly":{"status":"rate-limited","percent":100,"resetsAt":"2027-02-01T08:00:00.000Z"}
        }}
        """#
        let api = try service.parseAPIUsage(Data(apiPayload.utf8), now: now)
        precondition(api.rateLimit?.primaryWindow?.usedPercent == 99)
        precondition(api.rateLimit?.primaryWindow?.resetAfterSeconds == 3600)
        precondition(api.rateLimit?.primaryWindow?.resetAt == 1_800_003_600)
        precondition(api.rateLimit?.secondaryWindow?.usedPercent == 42)
        precondition(api.rateLimit?.tertiaryWindow?.usedPercent == 100)
        precondition(api.rateLimit?.limitReached == true)
        for invalid in [apiPayload.replacingOccurrences(of: "rate-limited", with: "unknown"),
                        apiPayload.replacingOccurrences(of: "2027-01-15T09:00:00.000Z", with: "invalid"),
                        apiPayload.replacingOccurrences(of: "99.9", with: "-1"),
                        apiPayload.replacingOccurrences(of: "monthly", with: "missing"),
                        #"{"type":"error","error":{"type":"AuthError"}}"#] {
            expectFailure { _ = try service.parseAPIUsage(Data(invalid.utf8), now: now) }
        }

        try await testRequests(apiPayload: apiPayload, dashboardHTML: dashboardHTML, consolePayload: consolePayload)

        print("OpenCode Go API, weighted dashboard, rounding, request routing, and cache probes passed")
    }

    static func expectFailure(_ action: () throws -> Void) {
        do {
            try action()
            preconditionFailure("Malformed or missing usage must not become valid quota")
        } catch { }
    }

    static func expectAsyncFailureMessage(
        _ action: () async throws -> Void,
        containing expectedText: String
    ) async {
        do {
            try await action()
            preconditionFailure("The request was expected to fail")
        } catch {
            precondition(
                error.localizedDescription.contains(expectedText),
                "Expected error containing \"\(expectedText)\", got \"\(error.localizedDescription)\""
            )
        }
    }

    static func expectAsyncFailure(_ action: () async throws -> Void) async {
        do {
            try await action()
            preconditionFailure("The request was expected to fail")
        } catch { }
    }

    static func testRequests(
        apiPayload: String,
        dashboardHTML: String,
        consolePayload: String
    ) async throws {
        let futureReset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))
        let apiPayload = apiPayload.replacingOccurrences(
            of: #"2027-[0-9T:.\-]+Z"#, with: futureReset, options: .regularExpression
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageURLProtocol.self]
        let service = OpenCodeGoUsageService(session: URLSession(configuration: configuration))
        let futureConsoleReset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
        let futureConsoleMonthReset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(7_200))
        let requestConsolePayload = consolePayload
            .replacingOccurrences(of: "2027-01-15T09:00:00.000Z", with: futureConsoleReset)
            .replacingOccurrences(of: "2027-01-15T10:00:00.000Z", with: futureConsoleMonthReset)

        let apiAccountID = UUID()
        defer { removeCache(for: [apiAccountID]) }
        UsageURLProtocol.handler = { request in
            precondition(request.url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test_only")
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
            return (200, apiPayload)
        }
        let api = try await service.fetchUsage(accountID: apiAccountID, credential: "sk-test_only", workspaceIDOverride: "ignored-for-api")
        precondition(api.rateLimit?.secondaryWindow?.usedPercent == 42)

        UsageURLProtocol.handler = { _ in (503, "unavailable") }
        let cached = try await service.fetchUsage(accountID: apiAccountID, credential: "sk-test_only", workspaceIDOverride: nil)
        precondition(cached.planType.contains("Cached"))
        await expectAsyncFailure({
            _ = try await service.fetchUsage(accountID: apiAccountID, credential: "sk-different", workspaceIDOverride: nil)
        })

        // Console is the primary Cookie flow. Discovery returns multiple orgs;
        // a failed first org must not prevent trying the next one.
        let consoleAccountID = UUID()
        defer { removeCache(for: [consoleAccountID]) }
        var consolePaths: [String] = []
        var consoleOrgIDs: [String] = []
        UsageURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            consolePaths.append(path)
            if path == "/console/api/orgs" {
                precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
                precondition(request.value(forHTTPHeaderField: "x-org-id") == nil)
                precondition(request.value(forHTTPHeaderField: "Cookie") == "__Host-console_session=console-token")
                return (200, #"[{"id":"org_FIRST"},{"id":"org_SECOND"}]"#)
            }
            if path == "/console/api/go/status" {
                let orgID = request.value(forHTTPHeaderField: "x-org-id") ?? ""
                consoleOrgIDs.append(orgID)
                precondition(request.value(forHTTPHeaderField: "Cookie") == "__Host-console_session=console-token")
                precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
                precondition(orgID == "org_FIRST" || orgID == "org_SECOND")
                if orgID == "org_FIRST" { return (503, "temporarily unavailable") }
                return (200, requestConsolePayload)
            }
            preconditionFailure("Unexpected Console request: \(path)")
        }
        let console = try await service.fetchUsage(
            accountID: consoleAccountID,
            credential: "__Host-console_session=console-token; theme=dark",
            workspaceIDOverride: nil
        )
        precondition(console.rateLimit?.primaryWindow?.usedPercent == 25)
        precondition(consoleOrgIDs == ["org_FIRST", "org_SECOND"])
        precondition(consolePaths == ["/console/api/orgs", "/console/api/go/status", "/console/api/go/status"])

        // A Console URL is normalized to its org ID and skips discovery.
        let directAccountID = UUID()
        defer { removeCache(for: [directAccountID]) }
        UsageURLProtocol.handler = { request in
            precondition(request.url?.path == "/console/api/go/status")
            precondition(request.value(forHTTPHeaderField: "x-org-id") == "org_DIRECT")
            precondition(request.value(forHTTPHeaderField: "Cookie") == "auth=legacy; __Host-console_session=console-token")
            return (200, requestConsolePayload)
        }
        let direct = try await service.fetchUsage(
            accountID: directAccountID,
            credential: "tracking=x; auth=legacy; __Host-console_session=console-token",
            workspaceIDOverride: "https://opencode.ai/console/org_DIRECT/go"
        )
        precondition(direct.rateLimit?.tertiaryWindow?.resetAfterSeconds == 7_200)

        // A Console-only session must not fall back to legacy endpoints. The
        // mapped error must explain how to repair the credential.
        let expiredAccountID = UUID()
        defer { removeCache(for: [expiredAccountID]) }
        var consoleOnlyPaths: [String] = []
        UsageURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            consoleOnlyPaths.append(path)
            if path == "/console/api/orgs" {
                return (200, #"[{"id":"org_EXPIRED"}]"#)
            }
            if path == "/console/api/go/status" { return (401, "unauthorized") }
            preconditionFailure("Console-only credentials must not use legacy path \(path)")
        }
        await expectAsyncFailureMessage({
            _ = try await service.fetchUsage(
                accountID: expiredAccountID,
                credential: "__Host-console_session=expired-token",
                workspaceIDOverride: nil
            )
        }, containing: "__Host-console_session")
        precondition(consoleOnlyPaths == ["/console/api/orgs", "/console/api/go/status"])

        // A valid Console response with access:null means the workspace has no
        // Go subscription; it must not be replaced by a stale legacy snapshot.
        let noSubscriptionAccountID = UUID()
        defer { removeCache(for: [noSubscriptionAccountID]) }
        UsageURLProtocol.handler = { request in
            precondition(request.url?.path == "/console/api/go/status")
            return (200, #"{"access":null}"#)
        }
        await expectAsyncFailureMessage({
            _ = try await service.fetchUsage(
                accountID: noSubscriptionAccountID,
                credential: "__Host-console_session=no-subscription",
                workspaceIDOverride: "org_NO_GO"
            )
        }, containing: "does not have an active Go subscription")

        // Legacy auth cookies still try Console first, then use both legacy
        // discovery and the old dashboard only when Console is unauthorized.
        let legacyAccountID = UUID()
        defer { removeCache(for: [legacyAccountID]) }
        var legacyPaths: [String] = []
        UsageURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            legacyPaths.append(path)
            precondition(request.value(forHTTPHeaderField: "Cookie") == "auth=Fe26.2**legacy")
            switch path {
            case "/console/api/orgs", "/console/api/go/status":
                return (401, "unauthorized")
            case "/_server":
                return (200, #"{id:"wrk_LEGACY"}"#)
            case "/workspace/wrk_LEGACY/go":
                return (200, dashboardHTML)
            default:
                preconditionFailure("Unexpected legacy fallback path: \(path)")
            }
        }
        let legacy = try await service.fetchUsage(
            accountID: legacyAccountID,
            credential: "Fe26.2**legacy",
            workspaceIDOverride: nil
        )
        precondition(legacy.rateLimit?.tertiaryWindow?.usedPercent == 56)
        precondition(legacyPaths == ["/console/api/orgs", "/_server", "/console/api/go/status", "/workspace/wrk_LEGACY/go"])

        // Console cache entries are isolated by both credential and workspace.
        let cacheAccountID = UUID()
        defer { removeCache(for: [cacheAccountID]) }
        UsageURLProtocol.handler = { request in
            precondition(request.url?.path == "/console/api/go/status")
            precondition(request.value(forHTTPHeaderField: "x-org-id") == "org_CACHE")
            return (200, requestConsolePayload)
        }
        _ = try await service.fetchUsage(
            accountID: cacheAccountID,
            credential: "__Host-console_session=cache-token",
            workspaceIDOverride: "org_CACHE"
        )
        UsageURLProtocol.handler = { _ in (503, "unavailable") }
        let cachedConsole = try await service.fetchUsage(
            accountID: cacheAccountID,
            credential: "__Host-console_session=cache-token",
            workspaceIDOverride: "org_CACHE"
        )
        precondition(cachedConsole.planType.contains("Cached"))
        await expectAsyncFailure({
            _ = try await service.fetchUsage(
                accountID: cacheAccountID,
                credential: "__Host-console_session=cache-token",
                workspaceIDOverride: "org_OTHER"
            )
        })
        await expectAsyncFailure({
            _ = try await service.fetchUsage(
                accountID: cacheAccountID,
                credential: "__Host-console_session=other-token",
                workspaceIDOverride: "org_CACHE"
            )
        })

        // Auto-discovery must also bind the cache to the newly discovered org.
        let discoveryCacheAccountID = UUID()
        defer { removeCache(for: [discoveryCacheAccountID]) }
        var discoveryPhase = 0
        UsageURLProtocol.handler = { request in
            switch request.url?.path {
            case "/console/api/orgs":
                discoveryPhase += 1
                let org = discoveryPhase == 1 ? "org_DISCOVERED_A" : "org_DISCOVERED_B"
                return (200, "[{\"id\":\"\(org)\"}]")
            case "/console/api/go/status":
                return discoveryPhase == 1 ? (200, requestConsolePayload) : (503, "unavailable")
            default:
                preconditionFailure("Unexpected discovery-cache path")
            }
        }
        _ = try await service.fetchUsage(
            accountID: discoveryCacheAccountID,
            credential: "__Host-console_session=discovery-token",
            workspaceIDOverride: nil
        )
        await expectAsyncFailure({
            _ = try await service.fetchUsage(
                accountID: discoveryCacheAccountID,
                credential: "__Host-console_session=discovery-token",
                workspaceIDOverride: nil
            )
        })

        // A cached exhausted result must not survive a reset into a new window.
        UsageURLProtocol.handler = { _ in
            (200, apiPayload.replacingOccurrences(of: futureReset, with: "2020-01-15T09:00:00.000Z"))
        }
        _ = try await service.fetchUsage(accountID: apiAccountID, credential: "sk-test_only", workspaceIDOverride: nil)
        UsageURLProtocol.handler = { _ in (503, "unavailable") }
        await expectAsyncFailure({
            _ = try await service.fetchUsage(accountID: apiAccountID, credential: "sk-test_only", workspaceIDOverride: nil)
        })
    }

    static func removeCache(for accountIDs: [UUID]) {
        for accountID in accountIDs {
            UserDefaults.standard.removeObject(
                forKey: "CodexMonitor.openCodeGoDashboardCache.v3.\(accountID.uuidString)"
            )
        }
    }
}

private final class UsageURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
