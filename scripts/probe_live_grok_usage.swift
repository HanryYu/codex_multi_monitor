import Foundation

@main
enum LiveGrokUsageProbe {
    static func main() async throws {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
        let data = try Data(contentsOf: authURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = root.values.compactMap({ $0 as? [String: Any] }).first(where: {
                  (($0["key"] as? String) ?? "").isEmpty == false
              }),
              let token = auth["key"] as? String
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let usage = try await APIService.shared.fetchGrokUsage(authToken: token)
        let primary = usage.rateLimit?.primaryWindow
        print(
            "Grok live usage: plan=\(usage.planType) used=\(primary?.usedPercent.description ?? "unavailable") "
                + "period=\(primary?.limitWindowSeconds.description ?? "unavailable") "
                + "reset=\(primary?.resetAt.description ?? "unavailable")"
        )
    }
}
