import CryptoKit
import Foundation

/// Fetches authoritative OpenCode Go quota windows from the signed-in web dashboard.
/// OpenCode API keys and local usage history do not expose the account's real limits.
final class OpenCodeGoUsageService {
    static let shared = OpenCodeGoUsageService()

    private let dashboardHost = "opencode.ai"
    private let workspaceServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    private let cacheLifetime: TimeInterval = 30 * 60
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(
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
        let cookie = try normalizedCookieHeader(credential)
        let workspaceOverride = try normalizedWorkspaceID(workspaceIDOverride)
        let fingerprint = credentialFingerprint(cookie: cookie, workspaceID: workspaceOverride)

        do {
            let usage = try await fetchDashboardUsage(
                cookie: cookie,
                workspaceIDOverride: workspaceOverride
            )
            cacheDashboardUsage(usage, accountID: accountID, fingerprint: fingerprint)
            return usage
        } catch {
            if let cached = loadCachedDashboardUsage(accountID: accountID, fingerprint: fingerprint) {
                print("[CodexMonitor] OpenCode Go refresh failed; showing recent dashboard data")
                return cached
            }
            throw mapError(error)
        }
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
            guard credential.range(of: #"^[A-Za-z0-9.\-_*]+$"#, options: .regularExpression) != nil else {
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
                guard (name == "auth" || name == "__Host-auth"), !value.isEmpty else { return nil }
                return "\(name)=\(value)"
            }

        guard !authCookies.isEmpty else {
            throw APIError.message(
                "OpenCode Go auth cookie was not found. Paste the auth or __Host-auth Cookie value from opencode.ai."
            )
        }
        return authCookies.joined(separator: "; ")
    }

    func parseWorkspaceIDs(_ text: String) -> [String] {
        matches(pattern: #"\bid\s*:\s*[\"']((?:wrk|wk)_[A-Za-z0-9]+)[\"']"#, text: text, capture: 1)
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
        let windows = [rolling, weekly, monthly].compactMap { $0 }
        let limited = windows.contains { $0.usedPercent >= 100 }
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

    private func fetchDashboardUsage(
        cookie: String,
        workspaceIDOverride: String?
    ) async throws -> UsageResponse {
        let workspaceIDs: [String]
        if let workspaceIDOverride {
            workspaceIDs = [workspaceIDOverride]
        } else {
            workspaceIDs = try await fetchWorkspaceIDs(cookie: cookie)
        }

        guard !workspaceIDs.isEmpty else {
            throw APIError.message(
                "OpenCode Go workspace was not found. Add the Workspace ID shown in the dashboard URL."
            )
        }

        var lastError: Error = APIError.invalidResponse
        for workspaceID in workspaceIDs {
            do {
                return try await fetchWorkspaceUsage(cookie: cookie, workspaceID: workspaceID)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func fetchWorkspaceIDs(cookie: String) async throws -> [String] {
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

    private func fetchWorkspaceUsage(cookie: String, workspaceID: String) async throws -> UsageResponse {
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
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        guard value.range(of: #"^(wrk|wk)_[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            throw APIError.message("OpenCode Go Workspace ID must start with wrk_ or wk_.")
        }
        return value
    }

    private func dashboardWindow(named name: String, duration: Int, text: String) -> WindowUsage? {
        guard let body = usageBlock(named: name, text: text),
              let percent = directNumber(named: "usagePercent", objectText: body),
              let reset = directNumber(named: "resetInSec", objectText: body)
        else { return nil }

        let usedPercent = min(100, max(0, Int(percent.rounded())))
        let resetAfter = max(0, Int(reset))
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
            let searchEnd = text.index(searchStart, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
            guard let openBrace = text[searchStart..<searchEnd].firstIndex(of: "{") else { continue }
            var depth = 0
            var cursor = openBrace
            while cursor < text.endIndex {
                if text[cursor] == "{" { depth += 1 }
                if text[cursor] == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: cursor)
                        let block = String(text[openBrace..<end])
                        if directNumber(named: "usagePercent", objectText: block) != nil,
                           directNumber(named: "resetInSec", objectText: block) != nil {
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

    private func directNumber(named field: String, objectText: String) -> Double? {
        let pattern = #"[\"']?"# + NSRegularExpression.escapedPattern(for: field)
            + #"[\"']?\s*:\s*[\"']?(-?[0-9]+(?:\.[0-9]+)?)[\"']?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: objectText,
                range: NSRange(objectText.startIndex..<objectText.endIndex, in: objectText)
              ),
              let capture = Range(match.range(at: 1), in: objectText),
              let value = Double(objectText[capture]),
              value.isFinite
        else { return nil }
        return value
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

    private func mapError(_ error: Error) -> APIError {
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
        "CodexMonitor.openCodeGoDashboardCache.v2.\(accountID.uuidString)"
    }

    private func cacheDashboardUsage(_ usage: UsageResponse, accountID: UUID, fingerprint: String) {
        let entry = DashboardCacheEntry(savedAt: Date(), fingerprint: fingerprint, usage: usage)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey(accountID: accountID))
        }
    }

    private func loadCachedDashboardUsage(accountID: UUID, fingerprint: String) -> UsageResponse? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID: accountID)),
              let entry = try? JSONDecoder().decode(DashboardCacheEntry.self, from: data),
              entry.fingerprint == fingerprint,
              Date().timeIntervalSince(entry.savedAt) < cacheLifetime
        else { return nil }

        guard let rateLimit = entry.usage.rateLimit else { return nil }
        let refreshed = RateLimit(
            allowed: rateLimit.allowed,
            limitReached: rateLimit.limitReached,
            primaryWindow: refreshedCachedWindow(rateLimit.primaryWindow),
            secondaryWindow: refreshedCachedWindow(rateLimit.secondaryWindow),
            tertiaryWindow: refreshedCachedWindow(rateLimit.tertiaryWindow)
        )
        return UsageResponse(
            planType: "Cached dashboard",
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
        completionHandler(redirectedRequest)
    }
}
