import Foundation

/// Pure matching rules used before a local Grok CLI credential can replace a
/// saved account credential.  The current credential is deliberately kept as
/// an opaque string; callers must never log it.
enum GrokCredentialRecovery {
    struct AccountIdentity: Sendable, Equatable {
        let credential: String
        let accountID: String?
        let email: String?

        init(credential: String, accountID: String? = nil, email: String? = nil) {
            self.credential = credential
            self.accountID = accountID
            self.email = email
        }
    }

    struct LocalCredential: Sendable, Equatable {
        let credential: String
        let accountID: String?
        let email: String?

        init(credential: String, accountID: String? = nil, email: String? = nil) {
            self.credential = credential
            self.accountID = accountID
            self.email = email
        }
    }

    struct RefreshedCredential: Sendable, Equatable {
        let credential: String
        let refreshToken: String?
        let expiresAt: String

        init(credential: String, refreshToken: String?, expiresAt: String) {
            self.credential = credential
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }
    }

    enum MergeError: Error {
        case credentialsChanged
    }

    /// Returns true only when the local entry is demonstrably the same
    /// account. An exact credential match is the strongest evidence. Otherwise
    /// both sides must provide the same stable identity; an ID/email conflict
    /// rejects the entry even when one of those fields happens to match.
    static func matches(_ account: AccountIdentity, _ local: LocalCredential) -> Bool {
        guard !isCookieCredential(account.credential),
              !isCookieCredential(local.credential) else { return false }

        if normalizedCredential(account.credential) == normalizedCredential(local.credential) {
            return true
        }

        let accountID = normalizedIdentity(account.accountID)
        let localID = normalizedIdentity(local.accountID)
        let accountEmail = normalizedIdentity(account.email)
        let localEmail = normalizedIdentity(local.email)

        // If either side has an ID, require both IDs and reject any conflict.
        // This prevents an email collision from linking two different users.
        if accountID != nil || localID != nil {
            guard let accountID, let localID, accountID == localID else { return false }
            if let accountEmail, let localEmail, accountEmail != localEmail { return false }
            return true
        }

        // Email is a fallback only when neither side has a stable ID.
        guard let accountEmail, let localEmail else { return false }
        return accountEmail == localEmail
    }

    /// A forced retry is safe only while the local entry still has the token
    /// rejected by the request. If the CLI rotated it in the meantime, use the
    /// rotated token and avoid another refresh-token exchange.
    static func shouldForceRefresh(
        requested: String,
        local: String
    ) -> Bool {
        normalizedCredential(requested) == normalizedCredential(local)
    }

    /// Merge one rotated entry into the latest auth file snapshot. Requiring
    /// both original key and refresh token prevents a refresh response for a
    /// previous login from overwriting a newer login under the same entry key.
    static func mergeRefreshedEntry(
        in root: [String: Any],
        key: String,
        originalCredential: String,
        originalRefreshToken: String,
        refreshed: RefreshedCredential
    ) throws -> [String: Any] {
        guard entryMatchesOriginal(
            in: root,
            key: key,
            originalCredential: originalCredential,
            originalRefreshToken: originalRefreshToken
        ), var auth = root[key] as? [String: Any] else {
            throw MergeError.credentialsChanged
        }

        auth["key"] = refreshed.credential
        if let refreshToken = refreshed.refreshToken {
            auth["refresh_token"] = refreshToken
        }
        auth["expires_at"] = refreshed.expiresAt

        var merged = root
        merged[key] = auth
        return merged
    }

    static func entryMatchesOriginal(
        in root: [String: Any],
        key: String,
        originalCredential: String,
        originalRefreshToken: String
    ) -> Bool {
        guard let auth = root[key] as? [String: Any],
              let currentCredential = auth["key"] as? String,
              let currentRefreshToken = auth["refresh_token"] as? String else {
            return false
        }
        return normalizedCredential(currentCredential) == normalizedCredential(originalCredential) &&
            currentRefreshToken == originalRefreshToken
    }

    /// Grok web sessions are never eligible for local CLI credential recovery.
    /// Keep this detector here so AccountStore can make the decision without
    /// loading or printing a credential file.
    static func isCookieCredential(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("cookie:") { return true }

        // A full Cookie header contains several name=value pairs.
        if value.contains("=") && value.contains(";") { return true }

        // Grok's single-cookie form is commonly `sso=...`; accept the known
        // browser session names without treating arbitrary opaque tokens as
        // cookies.
        guard let separator = value.firstIndex(of: "=") else { return false }
        let name = lowercased[..<separator]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["sso", "sso-rw", "sso_read_only", "auth", "__host-auth"].contains(name)
    }

    static func normalizedCredential(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("authorization:") {
            value = String(value.dropFirst(14)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func normalizedIdentity(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    /// Pick a stable entry for automatic import when no saved account is
    /// available to disambiguate the local file. The current x.ai OIDC entry
    /// wins over legacy scope entries, followed by a lexical tie-breaker.
    static func preferredLocalEntryKey(_ keys: [String]) -> String? {
        keys.min { lhs, rhs in
            let left = entrySortKey(lhs)
            let right = entrySortKey(rhs)
            return left < right
        }
    }

    private static func entrySortKey(_ key: String) -> (Int, String) {
        let lowercased = key.lowercased()
        if lowercased.hasPrefix("https://auth.x.ai::") ||
            lowercased.hasPrefix("auth.x.ai::") {
            return (0, lowercased)
        }
        if lowercased.contains("scope") || lowercased.contains("legacy") {
            return (1, lowercased)
        }
        return (2, lowercased)
    }
}

/// Actor-local refresh coalescing that keeps one in-flight operation per
/// refresh token. The operation includes persistence, so waiters never resume
/// between the network response and the atomic auth-file merge.
actor GrokCredentialRefreshCoalescer<Value: Sendable> {
    private var inFlight: [String: Task<Value, Error>] = [:]

    func valueIfInFlight(for key: String) async throws -> Value? {
        guard let existing = inFlight[key] else { return nil }
        return try await existing.value
    }

    func value(
        for key: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await operation() }
        inFlight[key] = task
        do {
            let value = try await task.value
            inFlight[key] = nil
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}
