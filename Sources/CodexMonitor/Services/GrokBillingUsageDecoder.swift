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
        case invalidValue(field: String)
        case invalidDate(field: String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "Grok billing response is not valid JSON."
            case .missingConfig:
                return "Grok billing response is missing its config object."
            case .invalidValue(let field):
                return "Grok billing response contains an invalid \(field) value."
            case .invalidDate(let field):
                return "Grok billing response contains an invalid \(field) date."
            }
        }
    }

    /// Decodes `GET /v1/billing?format=credits`.
    ///
    /// The credits endpoint may omit `creditUsagePercent` when its value is the
    /// proto3 default. That omission is unknown usage here; it is not evidence
    /// of zero usage. A separate gRPC response can establish the zero-usage
    /// case when the caller has that source available.
    static func decode(_ data: Data) throws -> GrokBillingUsagePayload {
        let config = try configuration(from: data)
        return try decodeCredits(config)
    }

    /// Decodes the monthly shape returned by `GET /v1/billing`.
    ///
    /// `used.val` and `monthlyLimit.val` are the same server billing unit. The
    /// monthly percentage is calculated directly from those values. Missing or
    /// non-computable pairs remain unknown; on-demand fields are deliberately
    /// excluded because they are a different allowance.
    static func decodeMonthly(_ data: Data) throws -> GrokBillingUsagePayload {
        let config = try configuration(from: data)
        return try decodeMonthly(config)
    }

    private static func decodeCredits(_ config: [String: Any]) throws -> GrokBillingUsagePayload {
        let reportedPercent = try firstPresentNumber(
            fields: ["creditUsagePercent", "usagePercent"],
            in: config
        )
        if let reportedPercent, reportedPercent < 0 {
            throw DecodeError.invalidValue(field: "creditUsagePercent")
        }
        let period = try periodObject(in: config)
        let resetAt = try resetAt(config: config, period: period)
        let periodSeconds = try periodSeconds(for: period)
        let planType = try planType(in: config, fallback: "Grok")

        return GrokBillingUsagePayload(
            usedPercent: reportedPercent.map { min($0, 100) },
            resetAt: resetAt,
            periodSeconds: periodSeconds,
            planType: planType
        )
    }

    private static func decodeMonthly(_ config: [String: Any]) throws -> GrokBillingUsagePayload {
        let period = try periodObject(in: config)
        let resetAt = try resetAt(config: config, period: period)
        let used = try amount(field: "used", in: config)
        let limit = try amount(field: "monthlyLimit", in: config)
        let usedPercent: Double?

        if let used, used < 0 {
            throw DecodeError.invalidValue(field: "used")
        }
        if let limit, limit < 0 {
            throw DecodeError.invalidValue(field: "monthlyLimit")
        }

        if let used, let limit {
            guard limit > 0 else {
                usedPercent = nil
                return GrokBillingUsagePayload(
                    usedPercent: usedPercent,
                    resetAt: resetAt,
                    periodSeconds: 30 * 24 * 60 * 60,
                    planType: try planType(in: config, fallback: "Grok Monthly")
                )
            }
            guard used >= 0 else { throw DecodeError.invalidValue(field: "used") }
            let percent = used / limit * 100
            guard percent.isFinite else { throw DecodeError.invalidValue(field: "used/monthlyLimit") }
            usedPercent = min(percent, 100)
        } else {
            usedPercent = nil
        }

        return GrokBillingUsagePayload(
            usedPercent: usedPercent,
            resetAt: resetAt,
            periodSeconds: 30 * 24 * 60 * 60,
            planType: try planType(in: config, fallback: "Grok Monthly")
        )
    }

    private static func configuration(from data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalidJSON
        }
        if let rawConfig = root["config"] {
            guard let config = rawConfig as? [String: Any] else {
                throw DecodeError.missingConfig
            }
            return try validatedConfiguration(config)
        }
        return try validatedConfiguration(root)
    }

    private static func validatedConfiguration(_ config: [String: Any]) throws -> [String: Any] {
        let knownFields: Set<String> = [
            "creditUsagePercent", "usagePercent", "currentPeriod", "billingPeriodEnd",
            "history", "onDemandCap", "onDemandUsed", "prepaidBalance",
            "subscriptionTier", "subscription_tier", "planType", "periodType",
            "isUnifiedBillingUser", "used", "monthlyLimit",
        ]
        guard !config.isEmpty,
              knownFields.contains(where: { config[$0] != nil }) else {
            throw DecodeError.missingConfig
        }
        return config
    }

    private static func periodObject(in config: [String: Any]) throws -> [String: Any]? {
        guard let rawPeriod = config["currentPeriod"] else { return nil }
        if rawPeriod is NSNull { return nil }
        guard let period = rawPeriod as? [String: Any] else {
            throw DecodeError.invalidValue(field: "currentPeriod")
        }
        return period
    }

    private static func periodSeconds(for period: [String: Any]?) throws -> Int {
        guard let period else { return 0 }
        guard let rawType = period["type"] else { return 0 }
        guard let type = rawType as? String, !type.isEmpty else {
            throw DecodeError.invalidValue(field: "currentPeriod.type")
        }
        let normalized = type.uppercased()
        if normalized.contains("WEEK") { return 7 * 24 * 60 * 60 }
        if normalized.contains("MONTH") { return 30 * 24 * 60 * 60 }
        return 0
    }

    private static func resetAt(config: [String: Any], period: [String: Any]?) throws -> Int {
        if let period, period["end"] != nil {
            return try parseDateValue(period["end"]!, field: "currentPeriod.end")
        }
        if config["billingPeriodEnd"] != nil {
            return try parseDateValue(config["billingPeriodEnd"]!, field: "billingPeriodEnd")
        }
        return 0
    }

    private static func parseDateValue(_ value: Any, field: String) throws -> Int {
        guard let string = value as? String, !string.isEmpty else {
            throw DecodeError.invalidDate(field: field)
        }
        guard let date = parseISODate(string), date.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970 >= 0,
              date.timeIntervalSince1970 < Double(Int.max) else {
            throw DecodeError.invalidDate(field: field)
        }
        return Int(date.timeIntervalSince1970)
    }

    private static func planType(in config: [String: Any], fallback: String) throws -> String {
        for key in ["subscriptionTier", "subscription_tier", "planType"] {
            guard let rawValue = config[key] else { continue }
            guard let value = rawValue as? String else {
                throw DecodeError.invalidValue(field: key)
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return fallback
    }

    private static func firstPresentNumber(
        fields: [String],
        in config: [String: Any]
    ) throws -> Double? {
        for field in fields {
            guard let rawValue = config[field] else { continue }
            return try number(rawValue, field: field)
        }
        return nil
    }

    private static func amount(field: String, in config: [String: Any]) throws -> Double? {
        guard let rawValue = config[field] else { return nil }
        guard let object = rawValue as? [String: Any], let rawAmount = object["val"] else {
            throw DecodeError.invalidValue(field: field)
        }
        return try number(rawAmount, field: "\(field).val")
    }

    private static func number(_ value: Any, field: String) throws -> Double {
        if let string = value as? String {
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let number = Double(string), number.isFinite else {
                throw DecodeError.invalidValue(field: field)
            }
            return number
        }
        if let number = value as? NSNumber {
            // JSON booleans bridge to NSNumber. They are not billing numbers.
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
                throw DecodeError.invalidValue(field: field)
            }
            let value = number.doubleValue
            guard value.isFinite else { throw DecodeError.invalidValue(field: field) }
            return value
        }
        throw DecodeError.invalidValue(field: field)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
