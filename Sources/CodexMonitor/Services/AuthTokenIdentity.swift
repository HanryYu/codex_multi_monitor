import Foundation

struct AuthTokenIdentity {
    let accountID: String?
    let email: String?
    let displayName: String?
}

enum AuthTokenIdentityParser {
    static func parse(accessToken: String?, idToken: String? = nil) -> AuthTokenIdentity {
        let accessPayload = decodeJWTPayload(accessToken)
        let idPayload = decodeJWTPayload(idToken)

        let accountID = firstString([
            accountID(in: accessPayload),
            accountID(in: idPayload),
            accessPayload?["account_id"] as? String,
            idPayload?["account_id"] as? String,
            accessPayload?["sub"] as? String,
            idPayload?["sub"] as? String,
        ])

        let email = normalizedEmail(firstString([
            profile(in: accessPayload)?["email"] as? String,
            profile(in: idPayload)?["email"] as? String,
            accessPayload?["email"] as? String,
            idPayload?["email"] as? String,
            auth(in: accessPayload)?["email"] as? String,
            auth(in: idPayload)?["email"] as? String,
        ]))

        let displayName = firstString([
            idPayload?["name"] as? String,
            accessPayload?["name"] as? String,
            email,
            accountID,
        ])

        return AuthTokenIdentity(accountID: accountID, email: email, displayName: displayName)
    }

    static func normalizedEmail(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else { return nil }
        return trimmed
    }

    private static func accountID(in payload: [String: Any]?) -> String? {
        guard let auth = auth(in: payload) else { return nil }
        return firstString([
            auth["chatgpt_account_id"] as? String,
            auth["account_id"] as? String,
            auth["chatgpt_account_user_id"] as? String,
            auth["chatgpt_user_id"] as? String,
        ])
    }

    private static func auth(in payload: [String: Any]?) -> [String: Any]? {
        payload?["https://api.openai.com/auth"] as? [String: Any]
    }

    private static func profile(in payload: [String: Any]?) -> [String: Any]? {
        payload?["https://api.openai.com/profile"] as? [String: Any]
    }

    private static func decodeJWTPayload(_ token: String?) -> [String: Any]? {
        guard var token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func firstString(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
