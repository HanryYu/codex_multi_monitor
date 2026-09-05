import Foundation

@main
enum CodexStoredAuthBundleTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = jwt(expiration: now.addingTimeInterval(3_600))
        let expiring = jwt(expiration: now.addingTimeInterval(120))

        let freshBundle = try bundle(accessToken: fresh)
        precondition(freshBundle.accountID == "account-123")
        precondition(freshBundle.accessToken == fresh)
        precondition(freshBundle.refreshToken == "refresh-token")
        precondition(freshBundle.matches(accountID: "ACCOUNT-123"))
        precondition(!freshBundle.needsRefresh(now: now))

        let expiringBundle = try bundle(accessToken: expiring)
        precondition(expiringBundle.needsRefresh(now: now))
        precondition(CodexStoredAuthBundle.expirationDate(of: expiring) == now.addingTimeInterval(120))
        precondition(CodexStoredAuthBundle.expirationDate(of: "opaque-token") == nil)

        let rotatedAccessToken = jwt(expiration: now.addingTimeInterval(7_200))
        let rotatedData = try require(expiringBundle.replacingTokens(
            idToken: "rotated-id-token",
            accessToken: rotatedAccessToken,
            refreshToken: "rotated-refresh-token",
            refreshedAt: now
        ))
        let rotatedBundle = try require(CodexStoredAuthBundle(data: rotatedData))
        precondition(rotatedBundle.accessToken == rotatedAccessToken)
        precondition(rotatedBundle.refreshToken == "rotated-refresh-token")
        let rotatedRoot = try require(
            JSONSerialization.jsonObject(with: rotatedData) as? [String: Any]
        )
        precondition(rotatedRoot["last_refresh"] as? String != nil)

        let newerCandidate = try bundle(
            accessToken: jwt(expiration: now.addingTimeInterval(10_800))
        )
        precondition(
            CodexStoredAuthBundle.preferred(
                existing: rotatedData,
                candidate: newerCandidate.data
            ) == newerCandidate.data
        )
        precondition(
            CodexStoredAuthBundle.preferred(
                existing: newerCandidate.data,
                candidate: expiringBundle.data
            ) == newerCandidate.data,
            "An older switched auth.json must not replace a newer saved bundle"
        )

        print("Codex stored auth bundle tests passed")
    }

    private static func bundle(accessToken: String) throws -> CodexStoredAuthBundle {
        let object: [String: Any] = [
            "auth_mode": "chatgpt",
            "tokens": [
                "account_id": "account-123",
                "access_token": accessToken,
                "id_token": "id-token",
                "refresh_token": "refresh-token",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let bundle = CodexStoredAuthBundle(data: data) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return bundle
    }

    private static func jwt(expiration: Date) -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payloadObject: [String: Any] = ["exp": Int(expiration.timeIntervalSince1970)]
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: payloadObject))
        return "\(header).\(payload).signature"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
}
