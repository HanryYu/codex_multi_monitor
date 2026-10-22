import CryptoKit
import Foundation

/// Fetches server-calculated OpenCode Go quota windows via the official usage API
/// or the signed-in dashboard. Model multipliers are already included by the server.
final class OpenCodeGoUsageService {
    static let shared = OpenCodeGoUsageService()

    private let dashboardHost = "opencode.ai"
    private let workspaceServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private let cacheLifetime: TimeInterval = 30 * 60
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(
            configuration: configuration,
            delegate: OpenCodeGoRedirectGuard(),
            delegateQueue: nil
        )
    }

    func fetchUsage(
        accountID: UUID,
        credential: String,
        workspaceIDOverride: String?
    ) async throws -> UsageResponse {
        let credential = try normalizedCredential(credential)
        let usesAPIKey = isAPIKeyCredential(credential)
        let workspaceOverride = usesAPIKey ? nil : try normalizedWorkspaceID(workspaceIDOverride)
        var attemptedFingerprints: [String] = []

        do {
            if usesAPIKey {
                let fingerprint = credentialFingerprint(cookie: credential, workspaceID: nil)
                attemptedFingerprints.append(fingerprint)
                let usage = try await fetchAPIUsage(apiKey: credential)
                cacheDashboardUsage(usage, accountID: accountID, fingerprint: fingerprint)
                return usage
            }

            let workspaceIDs: [String]
            if let workspaceOverride {
                workspaceIDs = [workspaceOverride]
            } else {
                workspaceIDs = try await fetchWorkspaceIDs(cookie: credential)
            }
            guard !workspaceIDs.isEmpty else {
                throw APIError.message("OpenCode Go workspace was not found. Add the Workspace ID shown in the dashboard URL.")
            }
            var lastError: Error = APIError.invalidResponse
            for workspaceID in workspaceIDs {
                let fingerprint = credentialFingerprint(cookie: credential, workspaceID: workspaceID)
                attemptedFingerprints.append(fingerprint)
                do {
                    let usage = try await fetchWorkspaceUsage(cookie: credential, workspaceID: workspaceID)
                    cacheDashboardUsage(usage, accountID: accountID, fingerprint: fingerprint)
                    return usage
                } catch {
                    if !canUseCache(after: error) {
                        discardCachedDashboardUsage(accountID: accountID, fingerprint: fingerprint)
                        attemptedFingerprints.removeAll { $0 == fingerprint }
                    }
                    lastError = error
                }
            }
            throw lastError
        } catch {
            // Auto-discovery must confirm the cached workspace still belongs to
            // this session. A different workspace cannot inherit its quota.
            if canUseCache(after: error) {
                for fingerprint in attemptedFingerprints {
                    if let cached = loadCachedDashboardUsage(accountID: accountID, fingerprint: fingerprint) {
                        print("[CodexMonitor] OpenCode Go refresh failed; showing recent server data")
                        return cached
                    }
                }
            }
            if !canUseCache(after: error) {
                for fingerprint in attemptedFingerprints {
                    discardCachedDashboardUsage(accountID: accountID, fingerprint: fingerprint)
                }
            }
            if !usesAPIKey, case APIError.unauthorized = error {
                throw APIError.message("OpenCode Go session expired or moved to Console. Sign in at opencode.ai/console and paste the __Host-console_session Cookie, or use an OpenCode Go API key.")
            }
            throw mapError(error)
        }
    }

    func isAPIKeyCredential(_ rawCredential: String) -> Bool {
        apiKeyValue(rawCredential).hasPrefix("sk-")
    }

    func normalizedCredential(_ rawCredential: String) throws -> String {
        let value = apiKeyValue(rawCredential)
        if value.hasPrefix("sk-") {
            guard value.range(of: #"^sk-[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                throw APIError.message("OpenCode Go API key format is invalid.")
            }
            return value
        }
        return try normalizedCookieHeader(rawCredential)
    }

    private func apiKeyValue(_ rawCredential: String) -> String {
        var value = rawCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    func normalizedCookieHeader(_ rawCredential: String) throws -> String {
        var credential = rawCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        if credential.lowercased().hasPrefix("cookie:") {
            credential = String(credential.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !credential.isEmpty else {
            throw APIError.message("OpenCode Go session cookie is required.")
        }

        if !credential.contains("=") {
            guard credential.hasPrefix("Fe26.2**"),
                  credential.range(of: #"^[A-Za-z0-9.\-_*]+$"#, options: .regularExpression) != nil else {
                throw APIError.message("OpenCode Go session cookie format is invalid.")
            }
            return "auth=\(credential)"
        }

        let authCookies = credential
            .split(separator: ";")
            .compactMap { component -> String? in
                let pair = component.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = pair.firstIndex(of: "=") else { return nil }
                let name = String(pair[..<separator])
                let value = String(pair[pair.index(after: separator)...])
                guard ["auth", "__Host-auth", "__Host-console_session"].contains(name), !value.isEmpty,
                      !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
                return "\(name)=\(value)"
            }

        guard !authCookies.isEmpty else {
            throw APIError.message(
                "OpenCode Go auth cookie was not found. Paste the __Host-console_session Cookie from opencode.ai/console (legacy auth / __Host-auth are also supported)."
            )
        }
        return authCookies.joined(separator: "; ")
    }

    func parseWorkspaceIDs(_ text: String) -> [String] {
        matches(pattern: #"\bid[\"']?\s*:\s*[\"']((?:wrk|wk)_[A-Za-z0-9]+)[\"']"#, text: text, capture: 1)
    }

    private func fetchAPIUsage(apiKey: String) async throws -> UsageResponse {
        let url = URL(string: "https://\(dashboardHost)/zen/go/v1/usage")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 403 {
            throw APIError.message("This API key does not have an active OpenCode Go subscription.")
        }
        try validate(response: response)
        return try parseAPIUsage(data)
    }

    func parseAPIUsage(_ data: Data, now: Date = Date()) throws -> UsageResponse {
        guard data.count <= 1_000_000 else { throw APIError.invalidResponse }
        let payload = try JSONDecoder().decode(APIUsagePayload.self, from: data)
        let rolling = try apiWindow(payload.usage.rolling, duration: 5 * 60 * 60, now: now)
        let weekly = try apiWindow(payload.usage.weekly, duration: 7 * 24 * 60 * 60, now: now)
        let monthly = try apiWindow(payload.usage.monthly, duration: 30 * 24 * 60 * 60, now: now)
        return usageResponse(rolling: rolling, weekly: weekly, monthly: monthly)
    }

    private func apiWindow(_ value: APIUsageWindow, duration: Int, now: Date) throws -> WindowUsage {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var resetDate = formatter.date(from: value.resetsAt)
        if resetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            resetDate = formatter.date(from: value.resetsAt)
        }
        guard let resetDate,
              value.percent.isFinite, value.percent >= 0,
              value.status == "ok" || value.status == "rate-limited",
              resetDate.timeIntervalSince1970 >= 0,
              resetDate.timeIntervalSince1970 < Double(Int.max),
              resetDate.timeIntervalSince(now) < Double(Int.max)
        else { throw APIError.invalidResponse }
        return WindowUsage(
            usedPercent: displayPercent(value.percent, limited: value.status == "rate-limited"),
            limitWindowSeconds: duration,
            resetAfterSeconds: Int(max(0, resetDate.timeIntervalSince(now).rounded(.up))),
            resetAt: Int(resetDate.timeIntervalSince1970)
        )
    }

    private func displayPercent(_ percent: Double, limited: Bool) -> Int {
        // Never round 99.x up to a false exhausted state. Dashboard percentages
        // may already be rounded to 100.0 while the server still reports "ok".
        limited ? 100 : Int(min(99, max(0, percent.rounded(.down))))
    }

    private func usageResponse(rolling: WindowUsage, weekly: WindowUsage?, monthly: WindowUsage?) -> UsageResponse {
        let limited = [rolling, weekly, monthly].compactMap { $0 }.contains { $0.usedPercent >= 100 }
        return UsageResponse(
            planType: "OpenCode Go",
            rateLimit: RateLimit(
                allowed: !limited,
                limitReached: limited,
                primaryWindow: rolling,
                secondaryWindow: weekly,
                tertiaryWindow: monthly
            )
        )
    }

    func parseDashboardUsage(_ text: String) throws -> UsageResponse {
        guard text.utf8.count <= 10_000_000 else {
            throw APIError.message("OpenCode Go dashboard response was too large.")
        }
        guard let rolling = dashboardWindow(named: "rollingUsage", duration: 5 * 60 * 60, text: text),
              let weekly = dashboardWindow(named: "weeklyUsage", duration: 7 * 24 * 60 * 60, text: text)
        else {
            let lower = text.lowercased()
            if lower.contains("auth/authorize") || lower.contains("actor of type \"public\"") {
                throw APIError.unauthorized
            }
            throw APIError.message("OpenCode Go dashboard did not return its 5-hour and weekly quota windows.")
        }

        let monthly = dashboardWindow(
            named: "monthlyUsage",
            duration: 30 * 24 * 60 * 60,
            text: text
        )
        if usageBlock(named: "monthlyUsage", text: text) != nil, monthly == nil {
            throw APIError.invalidResponse
        }
        return usageResponse(rolling: rolling, weekly: weekly, monthly: monthly)
    }

    private func fetchLegacyWorkspaceIDs(cookie: String) async throws -> [String] {
        var components = URLComponents(string: "https://\(dashboardHost)/_server")
        components?.queryItems = [URLQueryItem(name: "id", value: workspaceServerID)]
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(workspaceServerID, forHTTPHeaderField: "X-Server-Id")
        request.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
        request.setValue("https://\(dashboardHost)", forHTTPHeaderField: "Origin")
        request.setValue("https://\(dashboardHost)", forHTTPHeaderField: "Referer")
        request.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        guard let text = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
        return parseWorkspaceIDs(text)
    }

    private func fetchLegacyWorkspaceUsage(cookie: String, workspaceID: String) async throws -> UsageResponse {
        guard let url = URL(string: "https://\(dashboardHost)/workspace/\(workspaceID)/go") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://\(dashboardHost)", forHTTPHeaderField: "Origin")
        request.setValue("https://\(dashboardHost)", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        guard let text = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
        return try parseDashboardUsage(text)
    }

    func normalizedWorkspaceID(_ rawValue: String?) throws -> String? {
        var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme == "https", url.host == dashboardHost {
            let parts = url.pathComponents
            if parts.count >= 3, parts[1] == "console" || parts[1] == "workspace" {
                value = parts[2]
            }
        }
        guard value.range(of: #"^(wrk|wk|org)_[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw APIError.message("OpenCode Go Workspace ID must start with org_, wrk_ or wk_, or be an opencode.ai Console URL.")
        }
        return value
    }

    // Migrated dashboards are SPA shells, with quota available only from Console JSON.
    // The legacy session is separate, so a Console 401 must still allow old auth cookies.
    private func hasLegacyCookie(_ cookie: String) -> Bool {
        cookie.split(separator: ";").contains {
            let pair = $0.trimmingCharacters(in: .whitespaces)
            return pair.hasPrefix("auth=") || pair.hasPrefix("__Host-auth=")
        }
    }

    private func fetchWorkspaceIDs(cookie: String) async throws -> [String] {
        do {
            let data = try await fetchConsole(path: "orgs", cookie: cookie, workspaceID: nil)
            let ids = try parseConsoleWorkspaceIDs(data)
            guard !ids.isEmpty else {
                throw APIError.message("No OpenCode Console workspace was found for this session.")
            }
            return ids
        } catch {
            guard hasLegacyCookie(cookie) else { throw error }
            let consoleError = error
            do {
                let ids = try await fetchLegacyWorkspaceIDs(cookie: cookie)
                guard !ids.isEmpty else { throw consoleError }
                return ids
            } catch {
                if case APIError.unauthorized = consoleError { throw consoleError }
                throw error
            }
        }
    }

    private func fetchWorkspaceUsage(cookie: String, workspaceID: String) async throws -> UsageResponse {
        do {
            let data = try await fetchConsole(path: "go/status", cookie: cookie, workspaceID: workspaceID)
            return try parseConsoleUsage(data)
        } catch {
            // A valid Console response with no subscription is authoritative.
            if error is NoConsoleSubscription { throw error }
            guard hasLegacyCookie(cookie), !workspaceID.hasPrefix("org_") else { throw error }
            let consoleError = error
            do {
                return try await fetchLegacyWorkspaceUsage(cookie: cookie, workspaceID: workspaceID)
            } catch {
                if case APIError.unauthorized = consoleError { throw consoleError }
                throw error
            }
        }
    }

    private func fetchConsole(path: String, cookie: String, workspaceID: String?) async throws -> Data {
        let url = URL(string: "https://\(dashboardHost)/console/api/\(path)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(workspaceID, forHTTPHeaderField: "x-org-id")
        request.setValue("https://\(dashboardHost)/console/\(workspaceID.map { "\($0)/go" } ?? "")", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        guard data.count <= 1_000_000 else { throw APIError.invalidResponse }
        return data
    }

    func parseConsoleWorkspaceIDs(_ data: Data) throws -> [String] {
        let rows = try JSONDecoder().decode([ConsoleWorkspace].self, from: data)
        var ids: [String] = []
        for row in rows {
            if let id = try? normalizedWorkspaceID(row.id), !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    func parseConsoleUsage(_ data: Data, now: Date = Date()) throws -> UsageResponse {
        guard data.count <= 1_000_000 else { throw APIError.invalidResponse }
        let payload = try JSONDecoder().decode(ConsoleUsagePayload?.self, from: data)
        guard let access = payload?.access else { throw NoConsoleSubscription() }
        let rolling = try consoleWindow(access.meters.fiveHour, duration: 5 * 60 * 60, now: now)
        let weekly = try access.meters.week.map { try consoleWindow($0, duration: 7 * 24 * 60 * 60, now: now) }
        let monthly = try access.meters.month.map {
            try consoleWindow($0, duration: 30 * 24 * 60 * 60, now: now, fallbackReset: access.endsAt)
        }
        return usageResponse(rolling: rolling, weekly: weekly, monthly: monthly)
    }

    private func consoleWindow(_ meter: ConsoleMeter, duration: Int, now: Date, fallbackReset: String? = nil) throws -> WindowUsage {
        let used = meter.usedMicroCents.value
        let limit = meter.limitMicroCents.value
        guard used.isFinite, used >= 0, limit.isFinite, limit > 0 else { throw APIError.invalidResponse }
        let percent = used / limit * 100
        guard percent.isFinite else { throw APIError.invalidResponse }
        var resetAt = 0
        var resetAfter = 0
        if let timestamp = meter.resetsAt ?? fallbackReset {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: timestamp)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: timestamp)
            }
            guard let date, date.timeIntervalSince1970 >= 0,
                  date.timeIntervalSince1970 < Double(Int.max),
                  date.timeIntervalSince(now) < Double(Int.max) else { throw APIError.invalidResponse }
            resetAt = Int(date.timeIntervalSince1970)
            resetAfter = Int(max(0, date.timeIntervalSince(now).rounded(.up)))
        }
        return WindowUsage(usedPercent: displayPercent(percent, limited: used >= limit),
                           limitWindowSeconds: duration, resetAfterSeconds: resetAfter, resetAt: resetAt)
    }

    private func dashboardWindow(named name: String, duration: Int, text: String) -> WindowUsage? {
        guard let body = usageBlock(named: name, text: text) else { return nil }
        let fields = objectFields(body)
        guard let reset = number(fields["resetInSec"]),
              reset >= 0, reset <= 366 * 24 * 60 * 60
        else { return nil }

        // New dashboard data includes weighted quota usage and its limit in the
        // same microcent unit. Do not sum dollar costs or apply multipliers again.
        let percent: Double
        if fields["usage"] != nil || fields["limit"] != nil {
            guard let usage = number(fields["usage"]), usage >= 0,
                  let limit = number(fields["limit"]), limit > 0 else { return nil }
            percent = usage / limit * 100
        } else {
            guard let value = number(fields["usagePercent"]), value >= 0 else { return nil }
            percent = value
        }
        guard percent.isFinite else { return nil }
        let status = fields["status"].map(unquoted)
        guard status == nil || status == "ok" || status == "rate-limited" else { return nil }
        let usedPercent = displayPercent(percent, limited: status.map { $0 == "rate-limited" } ?? (percent >= 100))
        let resetAfter = Int(reset.rounded(.up))
        let resetAt = resetAfter > 0 ? Int(Date().timeIntervalSince1970) + resetAfter : 0
        return WindowUsage(
            usedPercent: usedPercent,
            limitWindowSeconds: duration,
            resetAfterSeconds: resetAfter,
            resetAt: resetAt
        )
    }

    private func usageBlock(named name: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b[\"']?\s*:"#
        ) else { return nil }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: fullRange) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let searchStart = matchRange.upperBound
            let remainder = text[searchStart...].drop(while: { $0.isWhitespace })
            // Solid's serializer may assign an object to a reference before using
            // it. Never scan past a null value into the next window's object.
            guard let prefix = remainder.range(of: #"^(?:\(?[A-Za-z_$][A-Za-z0-9_$]*(?:\[\d+\])?\s*=\s*)?\{"#,
                                               options: .regularExpression) else { continue }
            let openBrace = remainder.index(before: prefix.upperBound)
            var depth = 0
            var quote: Character?
            var escaped = false
            var cursor = openBrace
            while cursor < text.endIndex {
                let character = text[cursor]
                if let activeQuote = quote {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == activeQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: cursor)
                        let block = String(text[openBrace..<end])
                        let fields = objectFields(block)
                        if fields["resetInSec"] != nil,
                           fields["usagePercent"] != nil || fields["usage"] != nil {
                            return block
                        }
                        break
                    }
                }
                cursor = text.index(after: cursor)
            }
        }
        return nil
    }

    private func objectFields(_ object: String) -> [String: String] {
        var fields: [String: String] = [:]
        var depth = 0
        var quote: Character?
        var escaped = false
        var component = ""
        func appendField() {
            guard let colon = component.firstIndex(of: ":") else { return }
            let key = unquoted(String(component[..<colon]))
            fields[key] = String(component[component.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for character in object.dropFirst().dropLast() {
            if let activeQuote = quote {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" || character == "[" || character == "(" {
                depth += 1
            } else if character == "}" || character == "]" || character == ")" {
                depth -= 1
            } else if character == ",", depth == 0 {
                appendField()
                component = ""
                continue
            }
            component.append(character)
        }
        appendField()
        return fields
    }

    private func unquoted(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = value.first, (first == "\"" || first == "'"), value.last == first {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private func number(_ value: String?) -> Double? {
        guard let value, let number = Double(unquoted(value)), number.isFinite else { return nil }
        return number
    }

    private func matches(pattern: String, text: String, capture: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > capture,
                  let range = Range(match.range(at: capture), in: text)
            else { return nil }
            let value = String(text[range])
            return seen.insert(value).inserted ? value : nil
        }
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch response.statusCode {
        case 200: return
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.httpError(statusCode: response.statusCode)
        }
    }

    private func canUseCache(after error: Error) -> Bool {
        // Server rejection must be visible even when a recent snapshot exists.
        if error is NoConsoleSubscription { return false }
        if case APIError.unauthorized = error { return false }
        return true
    }

    private func mapError(_ error: Error) -> APIError {
        if error is NoConsoleSubscription {
            return .message("This OpenCode Console workspace does not have an active Go subscription. Select the workspace with your Go plan.")
        }
        if let error = error as? APIError { return error }
        if let error = error as? URLError {
            return .message("OpenCode Go network error: \(error.localizedDescription)")
        }
        return .message("OpenCode Go usage could not be loaded: \(error.localizedDescription)")
    }

    private func credentialFingerprint(cookie: String, workspaceID: String?) -> String {
        let digest = SHA256.hash(data: Data("\(cookie)\n\(workspaceID ?? "")".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheKey(accountID: UUID) -> String {
        "CodexMonitor.openCodeGoDashboardCache.v3.\(accountID.uuidString)"
    }

    private func cacheDashboardUsage(_ usage: UsageResponse, accountID: UUID, fingerprint: String) {
        let entry = DashboardCacheEntry(savedAt: Date(), fingerprint: fingerprint, usage: usage)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey(accountID: accountID))
        }
    }

    private func discardCachedDashboardUsage(accountID: UUID, fingerprint: String) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID: accountID)),
              let entry = try? JSONDecoder().decode(DashboardCacheEntry.self, from: data),
              entry.fingerprint == fingerprint else { return }
        UserDefaults.standard.removeObject(forKey: cacheKey(accountID: accountID))
    }

    private func loadCachedDashboardUsage(accountID: UUID, fingerprint: String) -> UsageResponse? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID: accountID)),
              let entry = try? JSONDecoder().decode(DashboardCacheEntry.self, from: data),
              entry.fingerprint == fingerprint,
              Date().timeIntervalSince(entry.savedAt) < cacheLifetime
        else { return nil }

        guard let rateLimit = entry.usage.rateLimit else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let windows = [rateLimit.primaryWindow, rateLimit.secondaryWindow, rateLimit.tertiaryWindow].compactMap { $0 }
        // A reset invalidates the snapshot; only the server can tell us how much
        // quota has been used in the new window. Do not invent a recovered value.
        guard !windows.contains(where: { $0.resetAt > 0 && $0.resetAt <= now }) else { return nil }
        let refreshed = RateLimit(
            allowed: rateLimit.allowed,
            limitReached: rateLimit.limitReached,
            primaryWindow: refreshedCachedWindow(rateLimit.primaryWindow),
            secondaryWindow: refreshedCachedWindow(rateLimit.secondaryWindow),
            tertiaryWindow: refreshedCachedWindow(rateLimit.tertiaryWindow)
        )
        return UsageResponse(
            planType: "Cached OpenCode Go",
            rateLimit: refreshed,
            credits: entry.usage.credits,
            rateLimitReachedType: entry.usage.rateLimitReachedType,
            spendControl: entry.usage.spendControl,
            rateLimitResetCredits: entry.usage.rateLimitResetCredits
        )
    }

    private func refreshedCachedWindow(_ window: WindowUsage?) -> WindowUsage? {
        guard let window else { return nil }
        let resetAfter = window.resetAt > 0
            ? max(0, window.resetAt - Int(Date().timeIntervalSince1970))
            : 0
        return WindowUsage(
            usedPercent: window.usedPercent,
            limitWindowSeconds: window.limitWindowSeconds,
            resetAfterSeconds: resetAfter,
            resetAt: window.resetAt
        )
    }
}

private struct APIUsagePayload: Decodable {
    let usage: Windows
    struct Windows: Decodable {
        let rolling: APIUsageWindow
        let weekly: APIUsageWindow
        let monthly: APIUsageWindow
    }
}

private struct APIUsageWindow: Decodable {
    let status: String
    let percent: Double
    let resetsAt: String
}

private struct DashboardCacheEntry: Codable {
    let savedAt: Date
    let fingerprint: String
    let usage: UsageResponse
}

private final class OpenCodeGoRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let destinationHost = request.url?.host?.lowercased()
        guard originalHost == destinationHost, request.url?.scheme == "https" else {
            completionHandler(nil)
            return
        }
        var redirectedRequest = request
        redirectedRequest.setValue(
            task.originalRequest?.value(forHTTPHeaderField: "Cookie"),
            forHTTPHeaderField: "Cookie"
        )
        redirectedRequest.setValue(
            task.originalRequest?.value(forHTTPHeaderField: "Authorization"),
            forHTTPHeaderField: "Authorization"
        )
        completionHandler(redirectedRequest)
    }
}

private struct ConsoleWorkspace: Decodable {
    let id: String
}

private struct NoConsoleSubscription: Error {}

private struct ConsoleUsagePayload: Decodable {
    let access: Access?
    enum CodingKeys: String, CodingKey { case access }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Missing access is a changed/invalid schema; explicit null means no plan.
        access = try container.decode(Access?.self, forKey: .access)
    }
    struct Access: Decodable {
        let endsAt: String?
        let meters: Meters
    }
    struct Meters: Decodable {
        let fiveHour: ConsoleMeter
        let week: ConsoleMeter?
        let month: ConsoleMeter?
    }
}

private struct ConsoleMeter: Decodable {
    let usedMicroCents: ConsoleAmount
    let limitMicroCents: ConsoleAmount
    let resetsAt: String?
}

/// Console serializes money as strings; some deployments return JSON numbers.
private struct ConsoleAmount: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let number = Double(string) {
            value = number
        } else {
            value = try container.decode(Double.self)
        }
    }
}
