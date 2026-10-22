import Foundation

@main
struct GrokCredentialRecoveryTests {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("FAILED: unexpected test error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let rotatedAccount = GrokCredentialRecovery.AccountIdentity(
            credential: "rejected-cli-token",
            accountID: "user-a",
            email: "a@example.test"
        )
        let rotatedLocal = GrokCredentialRecovery.LocalCredential(
            credential: "rotated-cli-token",
            accountID: "user-a",
            email: "a@example.test"
        )
        check(
            GrokCredentialRecovery.matches(rotatedAccount, rotatedLocal),
            "same stable identity accepts a rotated local token"
        )
        check(
            !GrokCredentialRecovery.shouldForceRefresh(
                requested: rotatedAccount.credential,
                local: rotatedLocal.credential
            ),
            "a rotated local token does not force another refresh"
        )

        let exactButStaleIdentity = GrokCredentialRecovery.LocalCredential(
            credential: "rejected-cli-token",
            accountID: "user-b",
            email: "other@example.test"
        )
        check(
            GrokCredentialRecovery.matches(rotatedAccount, exactButStaleIdentity),
            "exact credential match wins over stale identity metadata"
        )

        let emailConflict = GrokCredentialRecovery.LocalCredential(
            credential: "different-token",
            accountID: "user-a",
            email: "other@example.test"
        )
        check(
            !GrokCredentialRecovery.matches(rotatedAccount, emailConflict),
            "same ID with conflicting email is rejected"
        )

        let idConflict = GrokCredentialRecovery.LocalCredential(
            credential: "different-token",
            accountID: "user-b",
            email: "a@example.test"
        )
        check(
            !GrokCredentialRecovery.matches(rotatedAccount, idConflict),
            "same email with conflicting ID is rejected"
        )

        let missingID = GrokCredentialRecovery.LocalCredential(
            credential: "different-token",
            email: "a@example.test"
        )
        check(
            !GrokCredentialRecovery.matches(rotatedAccount, missingID),
            "email cannot bridge a missing stable ID"
        )

        let emailOnlyAccount = GrokCredentialRecovery.AccountIdentity(
            credential: "old-token",
            email: "A@example.test"
        )
        let emailOnlyLocal = GrokCredentialRecovery.LocalCredential(
            credential: "new-token",
            email: "a@example.test"
        )
        check(
            GrokCredentialRecovery.matches(emailOnlyAccount, emailOnlyLocal),
            "matching email is a fallback when both IDs are absent"
        )

        let cookieAccount = GrokCredentialRecovery.AccountIdentity(
            credential: "sso=synthetic-cookie",
            email: "a@example.test"
        )
        check(
            GrokCredentialRecovery.isCookieCredential(cookieAccount.credential),
            "single sso cookie is detected"
        )
        check(
            !GrokCredentialRecovery.matches(cookieAccount, rotatedLocal),
            "cookie account cannot use a local CLI credential"
        )
        check(
            GrokCredentialRecovery.isCookieCredential("Cookie: sso=synthetic; foo=bar"),
            "full Cookie header is detected"
        )
        check(
            GrokCredentialRecovery.isCookieCredential("__Host-auth=synthetic"),
            "single host auth cookie is detected"
        )

        check(
            GrokCredentialRecovery.shouldForceRefresh(
                requested: "Bearer same-token",
                local: "same-token"
            ),
            "Bearer prefix is ignored for an exact retry"
        )
        check(
            GrokCredentialRecovery.shouldForceRefresh(
                requested: "Authorization: Bearer same-token",
                local: "same-token"
            ),
            "Authorization prefix is ignored for an exact retry"
        )

        let preferred = GrokCredentialRecovery.preferredLocalEntryKey([
            "legacy-scope",
            "https://auth.x.ai::synthetic-client",
            "other-entry",
        ])
        check(
            preferred == "https://auth.x.ai::synthetic-client",
            "current x.ai entry is preferred for automatic import"
        )

        let counter = SyntheticRefreshCallCounter()
        let coalescer = GrokCredentialRefreshCoalescer<String>()
        let operation: @Sendable () async throws -> String = {
            await counter.increment()
            try await Task.sleep(nanoseconds: 20_000_000)
            return "rotated-result"
        }
        async let first = coalescer.value(for: "synthetic-refresh-token", operation: operation)
        async let second = coalescer.value(for: "synthetic-refresh-token", operation: operation)
        let results = try await (first, second)
        check(results.0 == "rotated-result" && results.1 == "rotated-result",
              "concurrent callers receive the same refresh result")
        let refreshCalls = await counter.value
        check(refreshCalls == 1, "concurrent callers perform one refresh operation")

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-monitor-grok-recovery-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let originalRoot: [String: Any] = [
            "current": ["key": "old-token", "refresh_token": "old-refresh", "email": "a@example.test"],
            "other": ["key": "other-token", "refresh_token": "other-refresh"],
        ]

        let sequenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-monitor-grok-sequence-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: sequenceURL) }
        try JSONSerialization.data(withJSONObject: originalRoot, options: [.sortedKeys])
            .write(to: sequenceURL, options: [.atomic])
        let sequenceCounter = SyntheticRefreshCallCounter()
        let sequenceCoalescer = GrokCredentialRefreshCoalescer<String>()
        let sequenceOperation: @Sendable () async throws -> String = {
            let root = try JSONSerialization.jsonObject(
                with: Data(contentsOf: sequenceURL)
            ) as! [String: Any]
            guard GrokCredentialRecovery.entryMatchesOriginal(
                in: root,
                key: "current",
                originalCredential: "old-token",
                originalRefreshToken: "old-refresh"
            ) else {
                throw GrokCredentialRecovery.MergeError.credentialsChanged
            }
            await sequenceCounter.increment()
            let merged = try GrokCredentialRecovery.mergeRefreshedEntry(
                in: root,
                key: "current",
                originalCredential: "old-token",
                originalRefreshToken: "old-refresh",
                refreshed: .init(
                    credential: "sequence-rotated-token",
                    refreshToken: "sequence-rotated-refresh",
                    expiresAt: "2099-01-01T00:00:00Z"
                )
            )
            try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
                .write(to: sequenceURL, options: [.atomic])
            return "sequence-result"
        }
        _ = try await sequenceCoalescer.value(for: "sequence-refresh", operation: sequenceOperation)
        do {
            _ = try await sequenceCoalescer.value(for: "sequence-refresh", operation: sequenceOperation)
            check(false, "a rotated file blocks a stale second refresh")
        } catch GrokCredentialRecovery.MergeError.credentialsChanged {
            check(true, "a rotated file blocks a stale second refresh")
        }
        let sequenceRefreshCalls = await sequenceCounter.value
        check(sequenceRefreshCalls == 1, "stale sequence does not send a second refresh")

        try JSONSerialization.data(withJSONObject: originalRoot, options: [.sortedKeys])
            .write(to: temporaryURL, options: [.atomic])
        let fileRoot = try JSONSerialization.jsonObject(
            with: Data(contentsOf: temporaryURL)
        ) as! [String: Any]
        let merged = try GrokCredentialRecovery.mergeRefreshedEntry(
            in: fileRoot,
            key: "current",
            originalCredential: "old-token",
            originalRefreshToken: "old-refresh",
            refreshed: .init(
                credential: "new-token",
                refreshToken: "new-refresh",
                expiresAt: "2099-01-01T00:00:00Z"
            )
        )
        try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
            .write(to: temporaryURL, options: [.atomic])
        let mergedRoot = try JSONSerialization.jsonObject(
            with: Data(contentsOf: temporaryURL)
        ) as! [String: Any]
        let current = mergedRoot["current"] as! [String: Any]
        let other = mergedRoot["other"] as! [String: Any]
        check(current["key"] as? String == "new-token" &&
              current["refresh_token"] as? String == "new-refresh",
              "refresh merge persists the selected entry")
        check(other["key"] as? String == "other-token" &&
              other["refresh_token"] as? String == "other-refresh",
              "refresh merge preserves another entry")

        var changedRoot = fileRoot
        changedRoot["current"] = ["key": "new-login-token", "refresh_token": "new-login-refresh"]
        do {
            _ = try GrokCredentialRecovery.mergeRefreshedEntry(
                in: changedRoot,
                key: "current",
                originalCredential: "old-token",
                originalRefreshToken: "old-refresh",
                refreshed: .init(
                    credential: "stale-refresh-result",
                    refreshToken: "stale-refresh",
                    expiresAt: "2099-01-01T00:00:00Z"
                )
            )
            check(false, "changed credentials are rejected before merge")
        } catch GrokCredentialRecovery.MergeError.credentialsChanged {
            check(true, "changed credentials are rejected before merge")
        }

        print("Grok credential recovery policy tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else {
            fputs("FAILED: \(label)\n", stderr)
            exit(1)
        }
        print("PASS: \(label)")
    }
}

private actor SyntheticRefreshCallCounter {
    private var calls = 0

    func increment() {
        calls += 1
    }

    var value: Int { calls }
}
