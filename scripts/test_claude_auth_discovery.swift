import Foundation
import Security

private enum FakeError: Error { case failed }

private actor FakeClaudeBackend {
    var stored: ClaudeStoredCredentials?
    var readCount = 0
    var writeCount = 0
    var refreshCount = 0
    var failReads = false
    var failWritesRemaining = 0
    var failRefreshes = false
    var readDelayNanoseconds: UInt64 = 0
    var refreshed = ClaudeTokenRefreshResponse(
        accessToken: "rotated-access",
        refreshToken: "rotated-refresh",
        expiresIn: 3_600
    )
    var refreshTokens: [String] = []

    init(stored: ClaudeStoredCredentials?) {
        self.stored = stored
    }

    func read() async throws -> ClaudeStoredCredentials? {
        readCount += 1
        if readDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: readDelayNanoseconds)
        }
        if failReads { throw FakeError.failed }
        return stored
    }

    func write(_ value: ClaudeStoredCredentials) throws {
        writeCount += 1
        if failWritesRemaining > 0 {
            failWritesRemaining -= 1
            throw FakeError.failed
        }
        stored = value
    }

    func refresh(_ refreshToken: String) -> ClaudeTokenRefreshResponse {
        refreshCount += 1
        refreshTokens.append(refreshToken)
        return refreshed
    }

    func refreshOrThrow(_ refreshToken: String) throws -> ClaudeTokenRefreshResponse {
        if failRefreshes {
            refreshCount += 1
            refreshTokens.append(refreshToken)
            throw FakeError.failed
        }
        return refresh(refreshToken)
    }

    func setStored(_ value: ClaudeStoredCredentials?) { stored = value }
    func setFailReads(_ value: Bool) { failReads = value }
    func setFailWrites(_ count: Int) { failWritesRemaining = count }
    func setFailRefreshes(_ value: Bool) { failRefreshes = value }
    func setRefreshed(_ value: ClaudeTokenRefreshResponse) { refreshed = value }
    func setReadDelay(_ value: UInt64) { readDelayNanoseconds = value }
    func counts() -> (read: Int, write: Int, refresh: Int) {
        (readCount, writeCount, refreshCount)
    }
    func seenRefreshTokens() -> [String] { refreshTokens }
}

private final class GateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@main
enum ClaudeAuthDiscoveryTests {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await testConcurrentSingleFlight(now: now)
        try await testValidCache(now: now)
        try await testFailureBackoff(now: now)
        try await testRefreshFailureBackoff(now: now)
        try await testExpiringCredentialRefresh(now: now)
        try await testWriteFailureKeepsRotatedCredential(now: now)
        try await testExternalCredentialChangeWins(now: now)
        try await testUnavailableStorageDoesNotBlindWrite(now: now)
        try await testExpiredPendingReadFailureBackoff(now: now)
        try testNonInteractiveKeychainControls()
        print("Claude auth discovery tests passed")
    }

    private static func dependencies(_ fake: FakeClaudeBackend) -> ClaudeAuthDependencies {
        ClaudeAuthDependencies(
            read: { try await fake.read() },
            write: { try await fake.write($0) },
            refresh: { try await fake.refreshOrThrow($0) },
            accountEmail: { nil }
        )
    }

    private static func testConcurrentSingleFlight(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "access", refresh: "refresh", expires: now.addingTimeInterval(3_600)))
        await fake.setReadDelay(100_000_000)
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake))
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await coordinator.credential(now: now).credential.token }
            }
            var values: [String] = []
            for try await value in group { values.append(value) }
            return values
        }
        precondition(tokens.count == 20 && tokens.allSatisfy { $0 == "access" })
        let counts = await fake.counts()
        precondition(counts.read == 1, "Concurrent discovery must share one read")
    }

    private static func testValidCache(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "cached", refresh: "refresh", expires: now.addingTimeInterval(3_600)))
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake))
        _ = try await coordinator.credential(now: now)
        _ = try await coordinator.credential(now: now.addingTimeInterval(299))
        let counts = await fake.counts()
        precondition(counts.read == 1, "A valid credential should be cached for five minutes")
    }

    private static func testFailureBackoff(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: nil)
        await fake.setFailReads(true)
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake))
        do { _ = try await coordinator.credential(now: now); preconditionFailure("Expected read failure") } catch {}
        do { _ = try await coordinator.credential(now: now.addingTimeInterval(899)); preconditionFailure("Expected backoff") } catch {}
        var counts = await fake.counts()
        precondition(counts.read == 1, "Failure backoff must suppress repeated reads")
        do { _ = try await coordinator.credential(now: now.addingTimeInterval(900)); preconditionFailure("Expected retry failure") } catch {}
        counts = await fake.counts()
        precondition(counts.read == 2, "Read should retry after backoff")
    }

    private static func testExpiringCredentialRefresh(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(30)))
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake))
        let result = try await coordinator.credential(now: now)
        precondition(result.credential.token == "rotated-access")
        let counts = await fake.counts()
        let refreshTokens = await fake.seenRefreshTokens()
        precondition(counts.refresh == 1 && counts.write == 1)
        precondition(refreshTokens == ["old-refresh"])
    }

    private static func testRefreshFailureBackoff(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(30)))
        await fake.setFailRefreshes(true)
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake))
        do { _ = try await coordinator.credential(now: now); preconditionFailure("Expected refresh failure") } catch {}
        do { _ = try await coordinator.credential(now: now.addingTimeInterval(899)); preconditionFailure("Expected refresh backoff") } catch {}
        var counts = await fake.counts()
        precondition(counts.read == 1 && counts.refresh == 1)
        do { _ = try await coordinator.credential(now: now.addingTimeInterval(900)); preconditionFailure("Expected refresh retry failure") } catch {}
        counts = await fake.counts()
        precondition(counts.read == 2 && counts.refresh == 2, "Refresh failure should retry only after backoff")
    }

    private static func testWriteFailureKeepsRotatedCredential(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(30)))
        await fake.setFailWrites(1)
        var config = ClaudeAuthConfiguration()
        config.successfulCacheTTL = 1
        config.failureBackoff = 1
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake), configuration: config)
        let first = try await coordinator.credential(now: now)
        precondition(first.credential.token == "rotated-access" && first.persistenceErrorDescription != nil)
        let retried = try await coordinator.credential(now: now.addingTimeInterval(2))
        precondition(retried.credential.token == "rotated-access")
        let counts = await fake.counts()
        precondition(counts.refresh == 1 && counts.write == 2, "Persistence retry must not reuse the old refresh token")
    }

    private static func testExternalCredentialChangeWins(now: Date) async throws {
        let baseline = credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(30))
        let fake = FakeClaudeBackend(stored: baseline)
        await fake.setFailWrites(1)
        var config = ClaudeAuthConfiguration()
        config.successfulCacheTTL = 1
        config.failureBackoff = 1
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake), configuration: config)
        _ = try await coordinator.credential(now: now)

        let external = credentials(token: "external-login", refresh: "external-refresh", expires: now.addingTimeInterval(7_200))
        await fake.setStored(external)
        let discovered = try await coordinator.credential(now: now.addingTimeInterval(2))
        precondition(discovered.credential.token == "external-login", "External login must replace pending rotation")
        let counts = await fake.counts()
        precondition(counts.write == 1, "Pending data must not overwrite externally changed credentials")
    }

    private static func testUnavailableStorageDoesNotBlindWrite(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(30)))
        await fake.setFailWrites(1)
        var config = ClaudeAuthConfiguration()
        config.successfulCacheTTL = 1
        config.failureBackoff = 1
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake), configuration: config)
        _ = try await coordinator.credential(now: now)
        await fake.setStored(nil)
        let retained = try await coordinator.credential(now: now.addingTimeInterval(2))
        precondition(retained.credential.token == "rotated-access")
        let counts = await fake.counts()
        precondition(counts.write == 1, "An empty read must never trigger a blind overwrite")
    }

    private static func testExpiredPendingReadFailureBackoff(now: Date) async throws {
        let fake = FakeClaudeBackend(stored: credentials(token: "old", refresh: "old-refresh", expires: now.addingTimeInterval(-1)))
        await fake.setRefreshed(.init(
            accessToken: "short-lived-rotation",
            refreshToken: "short-lived-refresh",
            expiresIn: 2
        ))
        await fake.setFailWrites(1)
        var config = ClaudeAuthConfiguration()
        config.successfulCacheTTL = 1
        config.failureBackoff = 10
        config.expirationLeeway = 0
        let coordinator = ClaudeCredentialCoordinator(dependencies: dependencies(fake), configuration: config)
        let first = try await coordinator.credential(now: now)
        precondition(first.credential.token == "short-lived-rotation")
        precondition(first.persistenceErrorDescription != nil)
        let initialCounts = await fake.counts()
        precondition(initialCounts.refresh == 1 && initialCounts.write == 1)
        await fake.setFailReads(true)

        let expiredFailed: Bool
        do {
            _ = try await coordinator.credential(now: now.addingTimeInterval(11))
            expiredFailed = false
        } catch {
            expiredFailed = true
        }
        precondition(expiredFailed, "Expired pending token must not be returned")

        let backoffFailed: Bool
        do {
            _ = try await coordinator.credential(now: now.addingTimeInterval(12))
            backoffFailed = false
        } catch {
            backoffFailed = true
        }
        precondition(backoffFailed, "Expected pending-read backoff")
        let counts = await fake.counts()
        precondition(counts.read == 2, "An expired pending token read failure must enter backoff")
    }

    private static func testNonInteractiveKeychainControls() throws {
        let read = NonInteractiveKeychain.genericPasswordQuery(service: "test", returningData: true)
        let update = NonInteractiveKeychain.genericPasswordQuery(service: "test", returningData: false)
        for query in [read, update] {
            let uiPolicy = query.first(where: {
                ($0.key as String) == (kSecUseAuthenticationUI as String)
            })?.value as? String
            precondition(uiPolicy == (kSecUseAuthenticationUIFail as String))
        }

        let recorder = GateRecorder()
        let gate = NonInteractiveKeychainGate(client: .init(
            readInteractionAllowed: { (errSecSuccess, true) },
            setInteractionAllowed: { recorder.append($0); return errSecSuccess }
        ))
        do {
            try gate.perform { throw FakeError.failed }
            preconditionFailure("Expected operation failure")
        } catch {}
        precondition(recorder.snapshot() == [false, true], "Interaction state must be disabled and restored exactly once")
    }

    private static func credentials(
        token: String,
        refresh: String,
        expires: Date
    ) -> ClaudeStoredCredentials {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": token,
                "refreshToken": refresh,
                "expiresAt": Int64(expires.timeIntervalSince1970 * 1_000),
            ],
        ]
        return ClaudeStoredCredentials(
            data: try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
            storage: .file(URL(fileURLWithPath: "/tmp/claude-test-credentials"))
        )
    }
}
