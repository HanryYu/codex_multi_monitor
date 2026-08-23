import Foundation

@main
struct CodexResetRefreshPolicyTests {
    static func main() {
        precondition(CodexResetRefreshPolicy.refreshInterval == 3 * 60)
        precondition(CodexResetRefreshPolicy.failedRetryInterval == 15 * 60)
        precondition(CodexResetRefreshPolicy.failedRetryInterval > CodexResetRefreshPolicy.refreshInterval)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        precondition(!CodexResetRefreshPolicy.shouldRefresh(
            lastSuccessfulAt: now.addingTimeInterval(-(3 * 60 - 1)),
            lastAttemptAt: nil,
            now: now
        ))
        precondition(CodexResetRefreshPolicy.shouldRefresh(
            lastSuccessfulAt: now.addingTimeInterval(-3 * 60),
            lastAttemptAt: nil,
            now: now
        ))
        precondition(!CodexResetRefreshPolicy.shouldRefresh(
            lastSuccessfulAt: now.addingTimeInterval(-4 * 60),
            lastAttemptAt: now.addingTimeInterval(-(15 * 60 - 1)),
            now: now
        ))
        precondition(CodexResetRefreshPolicy.shouldRefresh(
            lastSuccessfulAt: now.addingTimeInterval(-4 * 60),
            lastAttemptAt: now.addingTimeInterval(-15 * 60),
            now: now
        ))

        print("Codex reset refresh policy tests passed")
    }
}
