import Foundation

@main
enum QuotaAllowanceSummaryProbe {
    static func main() {
        let fiveHour = WindowUsage(
            usedPercent: 28,
            limitWindowSeconds: 5 * 60 * 60,
            resetAfterSeconds: 120,
            resetAt: 10_000
        )
        let weekly = WindowUsage(
            usedPercent: 46,
            limitWindowSeconds: 7 * 24 * 60 * 60,
            resetAfterSeconds: 240,
            resetAt: 20_000
        )
        let rateLimit = RateLimit(
            allowed: true,
            limitReached: false,
            primaryWindow: weekly,
            secondaryWindow: fiveHour
        )

        let openCode = QuotaAllowanceSummary.make(
            from: rateLimit,
            provider: .openCodeGo,
            calibratedCapacityRatio: nil
        )
        precondition(openCode?.weeklyRemainingPercent == 54)
        precondition(openCode?.capacityRatio == 2.5)
        precondition(openCode?.remainingFiveHourEquivalents == 1.35)
        precondition(openCode?.source == .exactOpenCodeGo)

        let codexBaseline = QuotaAllowanceSummary.make(
            from: rateLimit,
            provider: .codex,
            calibratedCapacityRatio: nil
        )
        precondition(codexBaseline?.capacityRatio == 6.5)
        precondition(codexBaseline?.remainingFiveHourEquivalents == 3.51)
        precondition(codexBaseline?.source == .estimatedBaseline)

        let unusedFiveHour = WindowUsage(
            usedPercent: 0,
            limitWindowSeconds: 5 * 60 * 60,
            resetAfterSeconds: 120,
            resetAt: 10_000
        )
        let unusedFiveHourRateLimit = RateLimit(
            allowed: true,
            limitReached: false,
            primaryWindow: weekly,
            secondaryWindow: unusedFiveHour
        )
        let sameWeeklyWithUnusedFiveHour = QuotaAllowanceSummary.make(
            from: unusedFiveHourRateLimit,
            provider: .codex,
            calibratedCapacityRatio: nil
        )
        precondition(
            sameWeeklyWithUnusedFiveHour?.remainingFiveHourEquivalents
                == codexBaseline?.remainingFiveHourEquivalents
        )

        let userExampleWeekly = WindowUsage(
            usedPercent: 19,
            limitWindowSeconds: 7 * 24 * 60 * 60,
            resetAfterSeconds: 240,
            resetAt: 20_000
        )
        let userExample = QuotaAllowanceSummary.make(
            from: RateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: userExampleWeekly,
                secondaryWindow: unusedFiveHour
            ),
            provider: .codex,
            calibratedCapacityRatio: nil
        )
        precondition(abs((userExample?.remainingFiveHourEquivalents ?? 0) - 5.265) < 0.0001)

        let learned = QuotaAllowanceSummary.make(
            from: rateLimit,
            provider: .claude,
            calibratedCapacityRatio: 5
        )
        precondition(learned?.remainingFiveHourEquivalents == 2.7)
        precondition(learned?.source == .learned)

        var calibration = QuotaEquivalenceCalibration()
        calibration.observe(.init(
            fiveHourUsedPercent: 10,
            weeklyUsedPercent: 2,
            fiveHourResetAt: 10_000,
            weeklyResetAt: 20_000
        ))
        calibration.observe(.init(
            fiveHourUsedPercent: 15,
            weeklyUsedPercent: 3,
            fiveHourResetAt: 10_020,
            weeklyResetAt: 20_020
        ))
        precondition(calibration.capacityRatio == 5)
        calibration.observe(.init(
            fiveHourUsedPercent: 20,
            weeklyUsedPercent: 4,
            fiveHourResetAt: 10_040,
            weeklyResetAt: 20_040
        ))
        precondition(calibration.capacityRatio == 5)

        calibration.observe(.init(
            fiveHourUsedPercent: 1,
            weeklyUsedPercent: 4,
            fiveHourResetAt: 40_000,
            weeklyResetAt: 20_060
        ))
        precondition(calibration.anchor?.fiveHourUsedPercent == 1)

        print("Quota allowance equivalence probe passed")
    }
}
