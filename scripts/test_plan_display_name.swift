import Foundation

@main
struct PlanDisplayNameTests {
    static func main() {
        let cases = [
            ("pro", "Pro 20x"),
            ("PRO", "Pro 20x"),
            ("pro_light", "Pro 5x"),
            ("ProLight", "Pro 5x"),
            ("pro-lite", "Pro 5x"),
            ("pro lite", "Pro 5x"),
            ("team", "Team")
        ]

        for (rawValue, expectedValue) in cases {
            let usage = UsageResponse(planType: rawValue, rateLimit: nil)
            expect(
                usage.displayPlanType == expectedValue,
                "expected \(rawValue) to display as \(expectedValue), got \(usage.displayPlanType)"
            )
        }

        print("Plan display name tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
