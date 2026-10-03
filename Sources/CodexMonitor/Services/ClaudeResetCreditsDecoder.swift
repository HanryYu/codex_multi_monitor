import Foundation
import CoreFoundation

/// Decodes Claude's top-level cedar_ember grant data into the reset-credit display model.
/// This is a pure decoder; it never fetches usage or consumes a reset grant.
enum ClaudeResetCreditsDecoder {
    static func decode(_ data: Data, now: Date = Date()) -> RateLimitResetCredits? {
        guard
            let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let root = value as? [String: Any],
            let rawCedarEmber = root["cedar_ember"],
            !(rawCedarEmber is NSNull),
            let cedarEmber = rawCedarEmber as? [String: Any],
            let eligible = strictBool(cedarEmber["eligible"])
        else {
            return nil
        }

        let grantsValue = cedarEmber["grants"]
        let grants = grantsValue as? [Any]
        if let grantsValue, !(grantsValue is NSNull), grants == nil {
            return nil
        }

        if !eligible {
            let reason: String?
            if let rawReason = cedarEmber["ineligible_reason"], !(rawReason is NSNull) {
                guard let stringReason = rawReason as? String else { return nil }
                reason = stringReason
            } else {
                reason = nil
            }

            if let reason, !isExplicitNoGrantReason(reason) {
                return nil
            }
            if let grants, !grants.isEmpty {
                return nil
            }
            guard reason != nil || grants?.isEmpty == true else { return nil }
            return RateLimitResetCredits(availableCount: 0, credits: [])
        }

        if let rawReason = cedarEmber["ineligible_reason"], !(rawReason is NSNull) {
            guard let reason = rawReason as? String, isExplicitNoGrantReason(reason) else { return nil }
        }
        guard let rawGrants = grants else { return nil }
        guard !rawGrants.isEmpty else {
            return RateLimitResetCredits(availableCount: 0, credits: [])
        }

        var seenIDs = Set<String>()
        var validGrantCount = 0
        var availableCount = 0
        var credits: [RateLimitResetCredit] = []

        for rawGrant in rawGrants {
            guard let grant = parseGrant(rawGrant) else { continue }
            validGrantCount += 1
            guard seenIDs.insert(grant.id).inserted else { continue }

            // The usable_now flag describes immediate consumption. A
            // limit-gated grant is still an owned, unexpired reset and must remain visible.
            guard !grant.paused,
                  grant.resetsLeft > 0,
                  grant.startsAt.map({ $0.date <= now }) ?? true,
                  grant.endsAt.map({ $0.date > now }) ?? true
            else {
                continue
            }

            let (nextCount, overflow) = availableCount.addingReportingOverflow(grant.resetsLeft)
            guard !overflow else { return nil }
            availableCount = nextCount

            credits.append(RateLimitResetCredit(
                id: grant.id,
                resetType: grant.clears.joined(separator: ","),
                status: "available",
                grantedAt: nil,
                expiresAt: grant.endsAt?.rawValue,
                redeemedAt: nil,
                remainingCount: grant.resetsLeft,
                requiresLimit: grant.useRequiresLimit
            ))
        }

        // Do not turn an entirely unrecognized payload into a misleading zero-credit result.
        guard validGrantCount > 0 else { return nil }
        return RateLimitResetCredits(availableCount: availableCount, credits: credits)
    }

    private static func parseGrant(_ value: Any) -> ParsedGrant? {
        guard
            let grant = value as? [String: Any],
            let id = grant["id"] as? String,
            id.range(of: #"^[a-z0-9_-]{1,40}$"#, options: .regularExpression) != nil,
            let resetsLeft = strictInteger(grant["resets_left"]),
            let resetsTotal = strictInteger(grant["resets_total"]),
            resetsLeft >= 0,
            resetsTotal >= resetsLeft,
            let startsAt = optionalDate(grant, key: "starts_at"),
            let endsAt = optionalDate(grant, key: "ends_at"),
            let rawClears = grant["clears"] as? [Any],
            let paused = boolField(grant, key: "paused", defaultValue: false),
            boolField(grant, key: "usable_now", defaultValue: false) != nil,
            let useRequiresLimit = boolField(grant, key: "use_requires_limit", defaultValue: true)
        else {
            return nil
        }

        return ParsedGrant(
            id: id,
            resetsLeft: resetsLeft,
            startsAt: startsAt,
            endsAt: endsAt,
            clears: rawClears.compactMap { $0 as? String },
            paused: paused,
            useRequiresLimit: useRequiresLimit
        )
    }

    private static func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.boolValue
    }

    private static func boolField(_ object: [String: Any], key: String, defaultValue: Bool) -> Bool? {
        guard let value = object[key] else { return defaultValue }
        return strictBool(value)
    }

    private static func isExplicitNoGrantReason(_ reason: String) -> Bool {
        reason == "no_grant"
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              let integer = Int(exactly: doubleValue)
        else {
            return nil
        }
        return integer
    }

    private static func optionalDate(_ object: [String: Any], key: String) -> ParsedDate?? {
        guard let value = object[key] else { return .some(nil) }
        if value is NSNull { return .some(nil) }
        guard let rawValue = value as? String,
              let date = parseISO8601(rawValue)
        else {
            return nil
        }
        return .some(ParsedDate(rawValue: rawValue, date: date))
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct ParsedDate {
        let rawValue: String
        let date: Date
    }

    private struct ParsedGrant {
        let id: String
        let resetsLeft: Int
        let startsAt: ParsedDate?
        let endsAt: ParsedDate?
        let clears: [String]
        let paused: Bool
        let useRequiresLimit: Bool
    }
}
