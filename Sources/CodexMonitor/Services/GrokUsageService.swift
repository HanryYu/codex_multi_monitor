import Foundation

/// Grok billing reads use an isolated session and one bounded retry for transient failures.
final class GrokUsageService {
    static let shared = GrokUsageService()
    private let session: URLSession
    private let sleep: (TimeInterval) async throws -> Void

    init(session: URLSession? = nil,
         sleep: @escaping (TimeInterval) async throws -> Void = { delay in
             try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
         }) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config, delegate: GrokRedirectGuard(), delegateQueue: nil)
        }
        self.sleep = sleep
    }

    static func isCookieCredential(_ value: String) -> Bool {
        GrokCredentialRecovery.isCookieCredential(value)
    }

    private enum Source { case credits, webCookie, webBearer, monthly }

    func fetchUsage(authToken: String) async throws -> UsageResponse {
        if Self.isCookieCredential(authToken) {
            return try await fetch(authToken: authToken, source: .webCookie)
        }
        let credits = try await fetch(authToken: authToken, source: .credits)
        guard credits.rateLimit == nil else { return credits }
        // Unified billing may omit the weekly percentage. Ask the same account's
        // web billing before falling back to a distinctly monthly subscription budget.
        do {
            return try await fetch(authToken: authToken, source: .webBearer)
        } catch {
            if case APIError.unauthorized = error { throw error }
            try Task.checkCancellation()
        }
        do {
            let monthly = try await fetch(authToken: authToken, source: .monthly)
            if monthly.rateLimit != nil { return monthly }
        } catch {
            if case APIError.unauthorized = error { throw error }
            try Task.checkCancellation()
        }
        return credits // No surface published usage; never fabricate 0%.
    }

    private func fetch(authToken: String, source: Source) async throws -> UsageResponse {
        let web = source == .webCookie || source == .webBearer
        let request = try makeRequest(authToken: authToken, source: source)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                if let delay = retryDelay(http), attempt == 0 {
                    try await sleep(delay)
                    continue
                }
                try validate(http)
                guard data.count <= 2_000_000 else { throw APIError.invalidResponse }
                do {
                    if web {
                        // gRPC can report an error in an HTTP 200 response's headers or trailers.
                        if let status = http.value(forHTTPHeaderField: "grpc-status") {
                            guard let code = Int(status) else { throw APIError.invalidResponse }
                            if code != 0 { throw GrokWebUsageDecoder.DecodeError.rpcStatus(code) }
                        }
                        let payload = try GrokWebUsageDecoder.decode(data)
                        return usage(percent: payload.usedPercent, resetAt: payload.resetAt,
                                     duration: payload.periodSeconds, plan: source == .webCookie ? "Grok Web" : "Grok")
                    }
                    let payload = try source == .monthly
                        ? GrokBillingUsageDecoder.decodeMonthly(data) : GrokBillingUsageDecoder.decode(data)
                    guard let percent = payload.usedPercent else {
                        return UsageResponse(planType: payload.planType, rateLimit: nil)
                    }
                    return usage(percent: percent, resetAt: payload.resetAt,
                                 duration: payload.periodSeconds, plan: payload.planType)
                } catch GrokWebUsageDecoder.DecodeError.rpcStatus(let code) {
                    if attempt == 0, [4, 13, 14].contains(code) {
                        try await sleep(0.5)
                        continue
                    }
                    switch code {
                    case 16: throw APIError.unauthorized
                    case 7: throw APIError.message("Grok denied access to usage. Check this account's permissions or update its web session.")
                    case 8: throw APIError.rateLimited
                    default: throw APIError.message("Grok usage service returned gRPC status \(code). Try again later.")
                    }
                } catch let error as APIError {
                    throw error
                } catch {
                    throw APIError.upstreamFormatChanged(provider: "Grok", underlying: error)
                }
            } catch let error as URLError {
                if attempt == 0, [.timedOut, .networkConnectionLost, .cannotConnectToHost,
                                  .dnsLookupFailed, .cannotFindHost].contains(error.code) {
                    try await sleep(0.5)
                    continue
                }
                throw error
            }
        }
        throw APIError.invalidResponse
    }

    private func usage(percent: Double, resetAt: Int, duration: Int, plan: String) -> UsageResponse {
        // 99.x must not produce a false exhausted state just because the UI uses integers.
        let percent = Int(min(100, max(0, percent.rounded(.down))))
        let window = WindowUsage(usedPercent: percent, limitWindowSeconds: duration,
                                 resetAfterSeconds: resetAt > 0 ? max(0, resetAt - Int(Date().timeIntervalSince1970)) : 0,
                                 resetAt: resetAt)
        return UsageResponse(planType: plan, rateLimit: RateLimit(allowed: percent < 100,
                             limitReached: percent >= 100, primaryWindow: window, secondaryWindow: nil))
    }

    private func makeRequest(authToken: String, source: Source) throws -> URLRequest {
        var token = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let web = source == .webCookie || source == .webBearer
        let cookie = source == .webCookie
        let url = web
            ? "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig"
            : "https://cli-chat-proxy.grok.com/v1/billing" + (source == .credits ? "?format=credits" : "")
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 15
        if web {
            if cookie, token.lowercased().hasPrefix("cookie:") {
                token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            request.httpMethod = "POST"
            request.httpBody = Data([0, 0, 0, 0, 2, 8, 0])
            request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("1", forHTTPHeaderField: "x-grpc-web")
            request.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
            request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
            request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        }
        if !cookie {
            if token.lowercased().hasPrefix("authorization:") {
                token = String(token.dropFirst(14)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if token.lowercased().hasPrefix("bearer ") {
                token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !web {
                request.setValue(Self.installedGrokVersion(), forHTTPHeaderField: "x-grok-client-version")
                request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
            }
        }
        guard !token.isEmpty, !token.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }) else {
            throw APIError.message("Grok credential is empty or contains invalid characters.")
        }
        request.setValue(cookie ? token : "Bearer \(token)", forHTTPHeaderField: cookie ? "Cookie" : "Authorization")
        return request
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401: throw APIError.unauthorized
        case 403:
            // A browser challenge/access denial is not evidence that an OAuth token expired.
            throw APIError.message("Grok denied the usage request (HTTP 403). Open Grok to check this account's access or renew its web session.")
        case 429: throw APIError.rateLimited
        default: throw APIError.httpError(statusCode: response.statusCode)
        }
    }

    private func retryDelay(_ response: HTTPURLResponse) -> TimeInterval? {
        guard [408, 429, 500, 502, 503, 504].contains(response.statusCode) else { return nil }
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let delay = Double(header) ?? formatter.date(from: header)?.timeIntervalSinceNow
            guard let delay, delay.isFinite, delay >= 0, delay <= 2 else { return nil }
            return delay
        }
        return 0.5
    }

    private static func installedGrokVersion() -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/version.json")
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1_024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? String,
              version.range(of: #"^[0-9]+(?:\.[0-9]+)+(?:[-+][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil
        else { return "1.0.13" }
        return version
    }
}

private final class GrokRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // These are fixed API endpoints. Login redirects must not receive account credentials.
        completionHandler(nil)
    }
}
