import Foundation

@main
enum GrokBillingUsageDecoderTests {
    static func main() throws {
        let legacy = try decode(#"""
        {
          "config": {
            "creditUsagePercent": 42.4,
            "subscriptionTier": "SuperGrok",
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "end": "2030-09-10T06:01:41.380346+00:00"
            }
          }
        }
        """#)
        expect(legacy.usedPercent == 42.4, "scalar proxy percentage should decode")
        expect(legacy.planType == "SuperGrok", "subscription tier should be preserved")
        expect(legacy.periodSeconds == 7 * 24 * 60 * 60, "weekly period should decode")
        expect(legacy.resetAt > 0, "server period end should become resetAt")

        let explicitZero = try decode(#"""
        {"config":{"creditUsagePercent":0,"currentPeriod":{"type":"WEEKLY"}}}
        """#)
        expect(explicitZero.usedPercent == 0, "explicit zero should remain zero")

        let omittedPercent = try decode(#"""
        {
          "config": {
            "billingPeriodEnd": "2030-09-10T06:01:41.380346+00:00",
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "end": "2030-09-10T06:01:41.380346+00:00"
            },
            "onDemandCap": {"val": 0},
            "onDemandUsed": {"val": 0},
            "prepaidBalance": {"val": 0},
            "isUnifiedBillingUser": true,
            "history": [
              {"creditUsagePercent": 17.5, "billingCycle": {"type": "MONTHLY"}}
            ]
          }
        }
        """#)
        expect(omittedPercent.usedPercent == nil, "missing current percent must stay unknown")
        expect(omittedPercent.planType == "Grok", "proxy fallback plan label should be clear")
        expect(omittedPercent.periodSeconds == 7 * 24 * 60 * 60, "current period wins")
        expect(omittedPercent.resetAt > 0, "current period reset should be retained")

        let historyOnly = try decode(#"""
        {
          "config": {
            "history": [
              {"creditUsagePercent": 17.5, "billingCycle": {"type": "MONTHLY", "end": "2030-10-01T00:00:00Z"}}
            ]
          }
        }
        """#)
        expect(historyOnly.usedPercent == nil, "previous period usage must not replace current usage")
        expect(historyOnly.resetAt == 0, "previous period reset must not replace current reset")

        let monthly = try decodeMonthly(#"""
        {
          "config": {
            "used": {"val": "250"},
            "monthlyLimit": {"val": 1000},
            "subscriptionTier": "SuperGrok",
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_MONTHLY",
              "end": "2030-09-10T06:01:41.380346+00:00"
            }
          }
        }
        """#)
        expect(monthly.usedPercent == 25, "used.val and monthlyLimit.val should share server units")
        expect(monthly.planType == "SuperGrok", "monthly plan label should preserve subscription tier")
        expect(monthly.periodSeconds == 30 * 24 * 60 * 60, "monthly fallback must expose a monthly window")
        expect(monthly.resetAt > 0, "monthly fallback must use server reset")

        let monthlyFlat = try decodeMonthly(#"""
        {
          "used": {"val": 500},
          "monthlyLimit": {"val": "2000"},
          "billingPeriodEnd": "2030-09-10T06:01:41.380346+00:00"
        }
        """#)
        expect(monthlyFlat.usedPercent == 25, "flat monthly response should decode")
        expect(monthlyFlat.planType == "Grok Monthly", "missing tier should use an explicit monthly label")
        expect(monthlyFlat.periodSeconds == 30 * 24 * 60 * 60, "flat monthly response should remain monthly")
        expect(monthlyFlat.resetAt > 0, "billingPeriodEnd should become resetAt")

        let zeroLimit = try decodeMonthly(#"""
        {"config":{"used":{"val":100},"monthlyLimit":{"val":0}}}
        """#)
        expect(zeroLimit.usedPercent == nil, "zero limit cannot establish a percentage")

        expectFailure("non-object JSON") { _ = try decode("[]") }
        expectFailure("unknown object") { _ = try decode(#"{"error":"upstream failure"}"#) }
        expectFailure("NaN percent") { _ = try decode(#"{"config":{"creditUsagePercent":"NaN"}}"#) }
        expectFailure("infinite percent") { _ = try decode(#"{"config":{"creditUsagePercent":"Infinity"}}"#) }
        expectFailure("boolean percent") { _ = try decode(#"{"config":{"creditUsagePercent":true}}"#) }
        expectFailure("negative percent") { _ = try decode(#"{"config":{"creditUsagePercent":-1}}"#) }
        expectFailure("malformed current period") {
            _ = try decode(#"{"config":{"creditUsagePercent":1,"currentPeriod":true}}"#)
        }
        expectFailure("malformed reset date") {
            _ = try decode(#"{"config":{"creditUsagePercent":1,"currentPeriod":{"end":"soon"}}}"#)
        }
        expectFailure("monthly NaN amount") {
            _ = try decodeMonthly(#"{"config":{"used":{"val":"NaN"},"monthlyLimit":{"val":100}}}"#)
        }
        expectFailure("monthly infinite limit") {
            _ = try decodeMonthly(#"{"config":{"used":{"val":1},"monthlyLimit":{"val":"Infinity"}}}"#)
        }
        expectFailure("negative monthly usage") {
            _ = try decodeMonthly(#"{"config":{"used":{"val":-1},"monthlyLimit":{"val":100}}}"#)
        }
        expectFailure("negative monthly limit") {
            _ = try decodeMonthly(#"{"config":{"used":{"val":1},"monthlyLimit":{"val":-100}}}"#)
        }
        expectFailure("wrong monthly amount shape") {
            _ = try decodeMonthly(#"{"config":{"used":1,"monthlyLimit":{"val":100}}}"#)
        }
        expectFailure("boolean monthly amount") {
            _ = try decodeMonthly(#"{"config":{"used":{"val":true},"monthlyLimit":{"val":100}}}"#)
        }

        if let liveFixturePath = CommandLine.arguments.dropFirst().first {
            let liveData = try Data(contentsOf: URL(fileURLWithPath: liveFixturePath))
            let live = try GrokBillingUsageDecoder.decode(liveData)
            let usageText = live.usedPercent.map { String($0) } ?? "unavailable"
            print(
                "Live Grok billing response decoded: usage=\(usageText) "
                    + "period=\(live.periodSeconds) reset=\(live.resetAt)"
            )
        }

        print("Grok billing usage decoder tests passed")
    }

    private static func decode(_ json: String) throws -> GrokBillingUsagePayload {
        try GrokBillingUsageDecoder.decode(Data(json.utf8))
    }

    private static func decodeMonthly(_ json: String) throws -> GrokBillingUsagePayload {
        try GrokBillingUsageDecoder.decodeMonthly(Data(json.utf8))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func expectFailure(_ label: String, _ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected \(label) to be rejected")
        } catch {
            // Expected: malformed or unsupported upstream data must not become a quota.
        }
    }
}
