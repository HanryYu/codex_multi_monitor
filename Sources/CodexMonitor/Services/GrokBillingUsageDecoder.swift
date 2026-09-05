import Foundation

struct GrokBillingUsagePayload: Sendable {
    let usedPercent: Double?
    let resetAt: Int
    let periodSeconds: Int
    let planType: String
}

enum GrokBillingUsageDecoder {
    enum DecodeError: LocalizedError {
        case invalidJSON
        case missingConfig

        var errorDescription: String? {
            switch self {
            case .invalidJSON: return "Grok billing response is not valid JSON."
            case .missingConfig: return "Grok billing response is missing its config object."
            }
        }
    }

    static func decode(_ data: Data) throws -> GrokBillingUsagePayload {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalidJSON
        }
        let config = (root["config"] as? [String: Any]) ?? root
        let knownFields = [
            "creditUsagePercent", "usagePercent", "currentPeriod", "billingPeriodEnd",
            "history", "onDemandCap", "onDemandUsed", "prepaidBalance",
            "subscriptionTier", "subscription_tier", "planType",
        ]
        guard knownFields.contains(where: { config[$0] != nil }) else {
            throw DecodeError.missingConfig
        }

        let history = config["history"] as? [[String: Any]] ?? []
        let latestHistory = history.last
        let currentPeriod = config["currentPeriod"] as? [String: Any]
        let reportedPercent = firstDouble([
            config["creditUsagePercent"],
            config["usagePercent"],
            latestHistory?["creditUsagePercent"],
            latestHistory?["usagePercent"],
        ])
        // `creditUsagePercent` is a proto3 scalar. The billing service omits it when
        // the value is its default (zero), while still returning a valid currentPeriod.
        let usedPercent = (reportedPercent ?? (currentPeriod == nil ? nil : 0))
            .map { min(max($0, 0), 100) }

        let latestCycle = latestHistory?["billingCycle"] as? [String: Any]
        let resetDate = firstString([
            currentPeriod?["end"],
            config["billingPeriodEnd"],
            latestCycle?["end"],
            latestHistory?["end"],
        ]).flatMap(parseISODate)
        let resetAt = resetDate.map { Int($0.timeIntervalSince1970) } ?? 0

        let periodName = firstString([
            currentPeriod?["type"],
            latestCycle?["type"],
            config["periodType"],
        ])?.uppercased() ?? ""
        let periodSeconds = periodName.contains("WEEK")
            ? 7 * 24 * 60 * 60
            : 30 * 24 * 60 * 60

        let planType = firstString([
            config["subscriptionTier"],
            config["subscription_tier"],
            config["planType"],
        ]) ?? "Grok"

        return GrokBillingUsagePayload(
            usedPercent: usedPercent,
            resetAt: resetAt,
            periodSeconds: periodSeconds,
            planType: planType
        )
    }

    private static func firstDouble(_ values: [Any?]) -> Double? {
        for value in values {
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String, let number = Double(string) { return number }
            if let object = value as? [String: Any], let number = object["val"] as? NSNumber {
                return number.doubleValue
            }
        }
        return nil
    }

    private static func firstString(_ values: [Any?]) -> String? {
        for value in values {
            if let string = value as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        return nil
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
