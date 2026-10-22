import Foundation

enum APIError: LocalizedError {
    case invalidResponse, unauthorized, rateLimited
    case httpError(statusCode: Int)
    case upstreamFormatChanged(provider: String, underlying: Error)
    case message(String)
}

@main enum GrokUsageServiceTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrokURLProtocol.self]
        var delays: [TimeInterval] = []
        let service = GrokUsageService(session: URLSession(configuration: config), sleep: { delays.append($0) })
        let json = Data(#"{"config":{"creditUsagePercent":99.9,"currentPeriod":{"type":"WEEKLY","end":"2030-01-01T00:00:00Z"}}}"#.utf8)
        let rawWeb = Data([10, 5, 13, 0, 0, 92, 66]) // config.usagePercent = 55
        var requests: [URLRequest] = []
        func replies(_ responses: [(Int, Data, [String: String])]) {
            requests = []; delays = []
            GrokURLProtocol.handler = { request in
                let index = requests.count
                requests.append(request)
                precondition(index < responses.count, "Unexpected retry/fallback")
                return responses[index]
            }
        }
        replies([(503, Data(), [:]), (200, json, [:])])
        let usage = try await service.fetchUsage(authToken: "Bearer test-token")
        precondition(usage.rateLimit?.primaryWindow?.usedPercent == 99)
        precondition(usage.rateLimit?.allowed == true)
        precondition(requests.count == 2 && delays == [0.5])
        precondition(requests[0].value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli")
        precondition(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        precondition(requests[0].value(forHTTPHeaderField: "Cookie") == nil)

        requests = []; delays = []
        GrokURLProtocol.handler = { request in
            requests.append(request)
            if requests.count == 1 { throw URLError(.networkConnectionLost) }
            return (200, json, [:])
        }
        _ = try await service.fetchUsage(authToken: "test-token")
        precondition(requests.count == 2 && delays == [0.5])

        for status in [401, 403, 429] {
            replies([(status, Data(), ["Retry-After": "30"])])
            do { _ = try await service.fetchUsage(authToken: "test-token"); preconditionFailure("Must fail") }
            catch APIError.unauthorized { precondition(status == 401) }
            catch APIError.message { precondition(status == 403) }
            catch APIError.rateLimited { precondition(status == 429) }
            precondition(requests.count == 1 && delays.isEmpty)
        }
        replies([(429, Data(), ["Retry-After": "0.1"]), (200, json, [:])])
        _ = try await service.fetchUsage(authToken: "test-token")
        precondition(delays == [0.1])
        replies([(503, Data(), [:]), (503, Data(), [:])])
        do { _ = try await service.fetchUsage(authToken: "test-token"); preconditionFailure("Bounded retries") }
        catch APIError.httpError(let status) { precondition(status == 503) }
        precondition(requests.count == 2)

        for cookie in ["sso=web-session", "auth=web-session", "Cookie: sso=web-session; sso-rw=rw"] {
            replies([(200, rawWeb, [:])])
            let usage = try await service.fetchUsage(authToken: cookie)
            precondition(usage.rateLimit?.primaryWindow?.usedPercent == 55)
            precondition(requests[0].url?.host == "grok.com")
            precondition(requests[0].httpMethod == "POST")
            precondition(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("web-session") == true)
            precondition(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
            precondition(requests[0].value(forHTTPHeaderField: "Origin") == "https://grok.com")
            precondition(body(requests[0]) == Data([0, 0, 0, 0, 2, 8, 0]))
        }
        func trailer(_ status: Int) -> Data {
            let body = Data("grpc-status:\(status)\r\n".utf8)
            return Data([128, 0, 0, 0, UInt8(body.count)]) + body
        }
        replies([(200, trailer(14), [:]), (200, rawWeb, [:])])
        _ = try await service.fetchUsage(authToken: "sso=web-session")
        precondition(requests.count == 2 && delays == [0.5])
        for headers in [false, true] {
            replies([(200, headers ? rawWeb : trailer(16), headers ? ["grpc-status": "16"] : [:])])
            do { _ = try await service.fetchUsage(authToken: "sso=expired"); preconditionFailure("gRPC authentication failure") }
            catch APIError.unauthorized { }
            precondition(requests.count == 1 && delays.isEmpty)
        }
        replies([(200, Data("<html>blocked</html>".utf8), [:])])
        do { _ = try await service.fetchUsage(authToken: "sso=session"); preconditionFailure("Invalid body") }
        catch APIError.upstreamFormatChanged { }
        precondition(requests.count == 1)

        let noPercent = Data(#"{"config":{"currentPeriod":{"type":"WEEKLY","end":"2030-01-01T00:00:00Z"}}}"#.utf8)
        replies([(200, noPercent, [:]), (200, rawWeb, [:])])
        let fallback = try await service.fetchUsage(authToken: "test-token")
        precondition(fallback.rateLimit?.primaryWindow?.usedPercent == 55)
        precondition(requests[1].url?.host == "grok.com")
        precondition(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        precondition(requests[1].value(forHTTPHeaderField: "Cookie") == nil)

        let monthly = Data(#"{"used":{"val":25},"monthlyLimit":{"val":100},"billingPeriodEnd":"2030-02-01T00:00:00Z"}"#.utf8)
        replies([(200, noPercent, [:]), (403, Data(), [:]), (200, monthly, [:])])
        let monthlyUsage = try await service.fetchUsage(authToken: "test-token")
        precondition(monthlyUsage.rateLimit?.primaryWindow?.usedPercent == 25)
        precondition(monthlyUsage.rateLimit?.primaryWindow?.limitWindowSeconds == 30 * 24 * 60 * 60)
        precondition(monthlyUsage.rateLimit?.primaryWindow?.resetAt == 1_896_134_400)

        replies([(200, noPercent, [:]), (401, Data(), [:])])
        do { _ = try await service.fetchUsage(authToken: "test-token"); preconditionFailure("No fallback after rejection") }
        catch APIError.unauthorized { }
        precondition(requests.count == 2)

        replies([(200, noPercent, [:]), (403, Data(), [:]), (200, Data("{}".utf8), [:])])
        let unknown = try await service.fetchUsage(authToken: "test-token")
        precondition(unknown.rateLimit == nil)
        precondition(requests[2].url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing")

        replies([(503, Data(), [:])])
        let cancelled = GrokUsageService(session: URLSession(configuration: config), sleep: { _ in throw CancellationError() })
        do { _ = try await cancelled.fetchUsage(authToken: "test-token"); preconditionFailure("Cancellation should stop retry") }
        catch is CancellationError { }
        precondition(requests.count == 1)
        print("Grok usage routing, transient retry, gRPC status, fallback and cancellation tests passed")
    }

    static func body(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            output.append(buffer, count: count)
        }
        return output
    }
}

private final class GrokURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data, [String: String]))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data, headers) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
