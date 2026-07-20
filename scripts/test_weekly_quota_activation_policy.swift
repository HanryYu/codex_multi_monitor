import Foundation

@main
struct WeeklyQuotaActivationPolicyTests {
    static func main() {
        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "same-key",
                previousResetKey: "same-key",
                currentUsedPercent: 0,
                previousUsedPercent: 72,
                fullActivationResetKey: "same-key"
            ) == .usageRestored(previousUsedPercent: 72),
            "usage restoration must trigger even when reset key is unchanged"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "unknown",
                previousResetKey: "unknown",
                currentUsedPercent: 0,
                previousUsedPercent: 41,
                fullActivationResetKey: "unknown"
            ) == .usageRestored(previousUsedPercent: 41),
            "usage restoration must trigger without a reset timestamp"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "new-key",
                previousResetKey: "old-key",
                currentUsedPercent: 18,
                previousUsedPercent: 64,
                fullActivationResetKey: "old-key"
            ) == nil,
            "automatic activation must never spend a partially used weekly quota"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "same-key",
                previousResetKey: "same-key",
                currentUsedPercent: 0,
                previousUsedPercent: 0,
                fullActivationResetKey: "same-key",
                scheduledActivationIsDue: true
            ) == .scheduledCycleDue,
            "a persisted seven-day cycle must recover a missed reset signal"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "same-key",
                previousResetKey: "same-key",
                currentUsedPercent: 1,
                previousUsedPercent: 1,
                fullActivationResetKey: "same-key",
                scheduledActivationIsDue: true
            ) == nil,
            "a due schedule must wait until the weekly quota is fully available"
        )

        expect(
            WeeklyQuotaActivationPolicy.nextScheduledActivationTimestamp(after: 1_000)
                == 605_800,
            "a successful activation must schedule the same account seven days later"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "first-key",
                previousResetKey: nil,
                currentUsedPercent: 0,
                previousUsedPercent: nil,
                fullActivationResetKey: nil
            ) == .fullyReset,
            "a newly observed full weekly quota must trigger once"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "handled-key",
                previousResetKey: "handled-key",
                currentUsedPercent: 0,
                previousUsedPercent: 0,
                fullActivationResetKey: "handled-key"
            ) == nil,
            "an already handled full quota must not trigger repeatedly"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: "previous-week"
            ) == .weeklyWindowMissing,
            "a disappearing weekly window must trigger activation"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: nil
            ) == .weeklyWindowMissing,
            "a missing weekly window must be initialized once on upgrade"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: WeeklyQuotaActivationPolicy.missingWindowResetKey
            ) == nil,
            "a handled missing weekly window must not trigger repeatedly"
        )

        expect(
            WeeklyQuotaActivationPolicy.wasWaitingForMissingWindowToReturn(
                WeeklyQuotaActivationPolicy.missingWindowResetKey
            ),
            "a returned weekly window must be baselined after missing-window activation"
        )

        expect(
            WeeklyQuotaActivationPolicy.shouldManuallyActivate(
                hasRateLimit: true,
                weeklyUsedPercent: 0
            ),
            "manual activation must include a 100%-remaining weekly window"
        )

        expect(
            WeeklyQuotaActivationPolicy.shouldManuallyActivate(
                hasRateLimit: true,
                weeklyUsedPercent: nil
            ),
            "manual activation must include the official missing-window reset shape"
        )

        expect(
            !WeeklyQuotaActivationPolicy.shouldManuallyActivate(
                hasRateLimit: true,
                weeklyUsedPercent: 1
            ),
            "manual activation must skip partially used weekly quota"
        )

        expect(
            !WeeklyQuotaActivationPolicy.shouldManuallyActivate(
                hasRateLimit: false,
                weeklyUsedPercent: nil
            ),
            "manual activation must skip unavailable usage data"
        )

        print("WeeklyQuotaActivationPolicy tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
