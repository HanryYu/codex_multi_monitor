import Foundation

enum ClaudeUsageCredentialError: LocalizedError, Sendable {
    case empty
    case malformed
    case malformedCookie
    case missingSessionKey
    case duplicateSessionKey
    case invalidOrganizationID

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Claude credential is empty."
        case .malformed:
            return "Claude credential is malformed."
        case .malformedCookie:
            return "Could not parse the Claude Cookie. Paste the Cookie request header or sessionKey value from claude.ai."
        case .missingSessionKey:
            return "Claude Cookie must include a sessionKey value."
        case .duplicateSessionKey:
            return "Claude Cookie must include exactly one sessionKey value."
        case .invalidOrganizationID:
            return "Enter a valid Claude organization UUID or usage URL."
        }
    }
}

struct ClaudeUsageCredential: Sendable, Equatable {
    let normalizedValue: String
    let isCookie: Bool
    let lastActiveOrganizationID: String?

    private init(
        normalizedValue: String,
        isCookie: Bool,
        lastActiveOrganizationID: String? = nil
    ) {
        self.normalizedValue = normalizedValue
        self.isCookie = isCookie
        self.lastActiveOrganizationID = lastActiveOrganizationID
    }

    static func parse(_ input: String) throws -> Self {
        guard !input.isEmpty else { throw ClaudeUsageCredentialError.empty }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeUsageCredentialError.empty }

        if trimmed.first == "{" {
            return try parseAuthFile(trimmed)
        }

        // Permit surrounding line breaks from copy/paste, but reject controls
        // inside a header or token before it can become an HTTP header value.
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ClaudeUsageCredentialError.malformed
        }

        var value = trimmed
        if value.lowercased().hasPrefix("authorization:") {
            value = String(value.dropFirst("authorization:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty else { throw ClaudeUsageCredentialError.empty }

        let lowercased = value.lowercased()
        if lowercased.hasPrefix("cookie:") {
            return try parseCookie(String(value.dropFirst("cookie:".count)))
        }
        if lowercased.hasPrefix("sk-ant-sid01-") {
            guard value.count > "sk-ant-sid01-".count else {
                throw ClaudeUsageCredentialError.malformedCookie
            }
            return try parseCookie("sessionKey=\(value)")
        }
        if lowercased.hasPrefix("sessionkey=")
            || lowercased.hasPrefix("lastactiveorg=")
            || lowercased.hasPrefix("__host-")
            || value.contains(";")
            || looksLikeSingleCookiePair(value) {
            return try parseCookie(value)
        }

        // A plain OAuth credential remains an opaque, non-whitespace token for
        // compatibility with older imports and existing saved accounts.
        guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw ClaudeUsageCredentialError.malformed
        }
        return Self(normalizedValue: value, isCookie: false)
    }

    static func normalizedOrganizationID(_ value: String) throws -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if let uuid = UUID(uuidString: candidate) {
            return uuid.uuidString.lowercased()
        }

        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "claude.ai",
              components.user == nil,
              components.password == nil
        else {
            throw ClaudeUsageCredentialError.invalidOrganizationID
        }

        let path = components.path.split(separator: "/").map(String.init)
        guard path.count >= 4,
              path[0] == "api",
              path[1] == "organizations",
              path[3] == "usage",
              let uuid = UUID(uuidString: path[2])
        else {
            throw ClaudeUsageCredentialError.invalidOrganizationID
        }
        return uuid.uuidString.lowercased()
    }

    private static func parseAuthFile(_ value: String) throws -> Self {
        guard let data = value.data(using: .utf8),
              data.count <= 256 * 1_024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else {
            throw ClaudeUsageCredentialError.malformed
        }
        return try parse(token)
    }

    private static func looksLikeSingleCookiePair(_ value: String) -> Bool {
        guard let separator = value.firstIndex(of: "=") else { return false }
        let name = value[..<separator].trimmingCharacters(in: .whitespaces)
        let suffix = value[value.index(after: separator)...]
        let isBase64Padding = suffix.allSatisfy { $0 == "=" }
        return !isBase64Padding && isCookieName(name)
    }

    private static func parseCookie(_ input: String) throws -> Self {
        let header = input.trimmingCharacters(in: .whitespaces)
        guard !header.isEmpty else { throw ClaudeUsageCredentialError.malformedCookie }

        let fields = header.split(separator: ";", omittingEmptySubsequences: false)
        var normalizedFields: [String] = []
        var sessionKeyCount = 0
        var hasSessionKeyValue = false
        var lastActiveOrganizationID: String?

        for field in fields {
            let trimmedField = field.trimmingCharacters(in: .whitespaces)
            // Ignore empty separators left by copying a header with a trailing semicolon.
            guard !trimmedField.isEmpty else { continue }
            guard let separator = trimmedField.firstIndex(of: "=")
            else {
                throw ClaudeUsageCredentialError.malformedCookie
            }

            let rawName = trimmedField[..<separator]
            let name = rawName.trimmingCharacters(in: .whitespaces)
            let rawValue = trimmedField[trimmedField.index(after: separator)...]
            let cookieValue = rawValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  isCookieName(name),
                  isCookieValue(cookieValue)
            else {
                throw ClaudeUsageCredentialError.malformedCookie
            }

            let normalizedName: String
            if name.caseInsensitiveCompare("sessionKey") == .orderedSame {
                normalizedName = "sessionKey"
                sessionKeyCount += 1
                let sessionValue = unquotedCookieValue(cookieValue)
                // The authentication value itself is opaque and cannot contain spaces
                // or embedded quotes. Preserve valid surrounding quotes in the header.
                guard sessionValue.unicodeScalars.allSatisfy({
                    !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\""
                }) else {
                    throw ClaudeUsageCredentialError.malformedCookie
                }
                hasSessionKeyValue = !sessionValue.isEmpty
            } else {
                normalizedName = name
            }
            if name.caseInsensitiveCompare("lastActiveOrg") == .orderedSame {
                let organizationValue = unquotedCookieValue(cookieValue)
                let decoded = organizationValue.removingPercentEncoding ?? organizationValue
                lastActiveOrganizationID = try? normalizedOrganizationID(decoded)
            }

            normalizedFields.append("\(normalizedName)=\(cookieValue)")
        }

        guard sessionKeyCount > 0 else { throw ClaudeUsageCredentialError.missingSessionKey }
        guard sessionKeyCount == 1 else { throw ClaudeUsageCredentialError.duplicateSessionKey }
        guard hasSessionKeyValue else { throw ClaudeUsageCredentialError.missingSessionKey }

        return Self(
            normalizedValue: normalizedFields.joined(separator: "; "),
            isCookie: true,
            lastActiveOrganizationID: lastActiveOrganizationID
        )
    }

    private static func isCookieName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let byte = scalar.value
            return (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || "!#$%&'*+-.^_`|~".unicodeScalars.contains(scalar)
        }
    }

    private static func unquotedCookieValue(_ value: String) -> String {
        if value.count >= 2, value.first == "\"", value.last == "\"" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func isCookieValue(_ value: String) -> Bool {
        // Browser Cookie values are more permissive than the RFC server grammar:
        // JSON, quotes, commas, spaces and backslashes can occur in consent and
        // analytics cookies. Preserve them; only reject controls and delimiters.
        // https://chromium.googlesource.com/chromium/src/+/HEAD/net/cookies/parsed_cookie.cc
        value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && $0 != ";"
        }
    }
}
