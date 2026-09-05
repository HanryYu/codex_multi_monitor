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
              "end": "2026-09-10T06:01:41.380346+00:00"
            }
          }
        }
        """#)
        precondition(legacy.usedPercent == 42.4)
        precondition(legacy.planType == "SuperGrok")
        precondition(legacy.periodSeconds == 7 * 24 * 60 * 60)
        precondition(legacy.resetAt > 0)

        let unifiedBilling = try decode(#"""
        {
          "config": {
            "billingPeriodEnd": "2026-09-10T06:01:41.380346+00:00",
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "end": "2026-09-10T06:01:41.380346+00:00"
            },
            "onDemandCap": {"val": 0},
            "onDemandUsed": {"val": 0},
            "prepaidBalance": {"val": 0},
            "isUnifiedBillingUser": true
          }
        }
        """#)
        precondition(unifiedBilling.usedPercent == 0)
        precondition(unifiedBilling.planType == "Grok")
        precondition(unifiedBilling.periodSeconds == 7 * 24 * 60 * 60)

        let historyFallback = try decode(#"""
        {
          "config": {
            "history": [
              {"creditUsagePercent": "17.5", "billingCycle": {"type": "MONTHLY", "end": "2026-10-01T00:00:00Z"}}
            ]
          }
        }
        """#)
        precondition(historyFallback.usedPercent == 17.5)
        precondition(historyFallback.periodSeconds == 30 * 24 * 60 * 60)

        do {
            _ = try decode("[]")
            preconditionFailure("Non-object JSON must be rejected")
        } catch { }

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
}
