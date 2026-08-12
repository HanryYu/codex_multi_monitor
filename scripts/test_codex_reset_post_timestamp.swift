import Foundation

@main
struct CodexResetPostTimestampTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00:00 UTC

        precondition(CodexResetPostTimestamp.text(for: now.addingTimeInterval(-30), relativeTo: now) == "<1m")
        precondition(CodexResetPostTimestamp.text(for: now.addingTimeInterval(-15 * 60), relativeTo: now) == "15m")
        precondition(CodexResetPostTimestamp.text(for: now.addingTimeInterval(-8 * 3_600), relativeTo: now) == "8h")
        precondition(CodexResetPostTimestamp.text(for: now.addingTimeInterval(-4 * 86_400), relativeTo: now) == "4d")

        print("Codex reset post timestamp tests passed")
    }
}
