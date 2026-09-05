import Foundation

struct CodexStoredAuthBundle: Sendable {
    let data: Data
    let accountID: String
    let accessToken: String
    let refreshToken: String
    let lastRefresh: Date?

    init?(data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String,
              let accessToken = tokens["access_token"] as? String,
              let refreshToken = tokens["refresh_token"] as? String,
              !accountID.isEmpty,
              !accessToken.isEmpty,
              !refreshToken.isEmpty
        else { return nil }

        self.data = data
        self.accountID = accountID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.lastRefresh = Self.parseISODate(root["last_refresh"] as? String)
    }

    func matches(accountID expectedAccountID: String?) -> Bool {
        guard let expectedAccountID, !expectedAccountID.isEmpty else { return false }
        return accountID.caseInsensitiveCompare(expectedAccountID) == .orderedSame
    }

    func needsRefresh(now: Date = Date(), leeway: TimeInterval = 5 * 60) -> Bool {
        guard let expirationDate = Self.expirationDate(of: accessToken) else {
            return true
        }
        return expirationDate.timeIntervalSince(now) <= leeway
    }

    func replacingTokens(
        idToken: String?,
        accessToken: String,
        refreshToken: String?,
        refreshedAt: Date
    ) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any]
        else { return nil }

        tokens["access_token"] = accessToken
        if let idToken, !idToken.isEmpty { tokens["id_token"] = idToken }
        if let refreshToken, !refreshToken.isEmpty { tokens["refresh_token"] = refreshToken }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: refreshedAt)
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    static func expirationDate(of token: String) -> Date? {
        var normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("bearer ") {
            normalized = String(normalized.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let parts = normalized.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiration = (object["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        return Date(timeIntervalSince1970: expiration)
    }

    static func preferred(existing: Data?, candidate: Data) -> Data {
        guard let candidateBundle = CodexStoredAuthBundle(data: candidate) else {
            return existing ?? candidate
        }
        guard let existing,
              let existingBundle = CodexStoredAuthBundle(data: existing),
              existingBundle.accountID.caseInsensitiveCompare(candidateBundle.accountID) == .orderedSame
        else { return candidate }

        if existingBundle.accessToken == candidateBundle.accessToken {
            switch (existingBundle.lastRefresh, candidateBundle.lastRefresh) {
            case let (existingDate?, candidateDate?) where existingDate > candidateDate:
                return existing
            default:
                return candidate
            }
        }

        switch (
            expirationDate(of: existingBundle.accessToken),
            expirationDate(of: candidateBundle.accessToken)
        ) {
        case let (existingExpiration?, candidateExpiration?):
            return existingExpiration > candidateExpiration ? existing : candidate
        case (.some, nil):
            return existing
        case (nil, .some):
            return candidate
        case (nil, nil):
            switch (existingBundle.lastRefresh, candidateBundle.lastRefresh) {
            case let (existingDate?, candidateDate?):
                return existingDate > candidateDate ? existing : candidate
            case (.some, nil):
                return existing
            default:
                return candidate
            }
        }
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
