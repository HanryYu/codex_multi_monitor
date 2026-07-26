import Foundation

@main
struct WeeklyQuotaActivationPolicyTests {
    static func main() {
        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "same-key",
                previousResetKey: "same-key",
                currentUsedPercent: 0,
                previousUsedPercent: 72
            ) == .usageRestored(previousUsedPercent: 72),
            "usage restoration must trigger even when reset key is unchanged"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "unknown",
                previousResetKey: "unknown",
                currentUsedPercent: 0,
                previousUsedPercent: 41
            ) == .usageRestored(previousUsedPercent: 41),
            "usage restoration must trigger without a reset timestamp"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "new-key",
                previousResetKey: "old-key",
                currentUsedPercent: 18,
                previousUsedPercent: 64
            ) == nil,
            "automatic activation must never spend a partially used weekly quota"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "same-key",
                previousResetKey: "same-key",
                currentUsedPercent: 0,
                previousUsedPercent: 0,
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
            WeeklyQuotaActivationPolicy.migratedNextActivationTimestamp(
                legacyTimestamp: 4_600,
                activationResetKey: WeeklyQuotaActivationPolicy.missingWindowResetKey
            ) == 605_800,
            "the old hourly missing-window retry must migrate to seven days after success"
        )

        expect(
            WeeklyQuotaActivationPolicy.migratedNextActivationTimestamp(
                legacyTimestamp: 605_800,
                activationResetKey: "observed-reset"
            ) == 605_800,
            "an existing seven-day visible-window schedule must remain unchanged"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "first-key",
                previousResetKey: nil,
                currentUsedPercent: 0,
                previousUsedPercent: nil
            ) == nil,
            "a newly observed rounded 100% value must be baselined instead of consumed"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "handled-key",
                previousResetKey: "handled-key",
                currentUsedPercent: 0,
                previousUsedPercent: 0
            ) == nil,
            "an already handled full quota must not trigger repeatedly"
        )

        expect(
            WeeklyQuotaActivationPolicy.trigger(
                currentResetKey: "new-key",
                previousResetKey: "old-key",
                currentUsedPercent: 0,
                previousUsedPercent: 0
            ) == .resetKeyChanged(previousResetKey: "old-key"),
            "a changed official cycle key plus zero used quota is a reliable reset signal"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: "1000",
                scheduledActivationIsDue: false,
                now: 1000
            ) == .weeklyWindowMissing,
            "a disappearing weekly window may trigger only after its observed reset time"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: "2000",
                scheduledActivationIsDue: false,
                now: 1000
            ) == nil,
            "a disappearing weekly window before its reset time must not consume quota"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: nil,
                scheduledActivationIsDue: false,
                now: 1000
            ) == nil,
            "an initially missing weekly window is not reliable reset evidence"
        )

        expect(
            WeeklyQuotaActivationPolicy.triggerForMissingWindow(
                previousResetKey: WeeklyQuotaActivationPolicy.missingWindowResetKey,
                scheduledActivationIsDue: true,
                now: 1000
            ) == .scheduledCycleDue,
            "a missing weekly window may activate once when its seven-day cycle is due"
        )

        expect(
            WeeklyQuotaActivationPolicy.wasWaitingForMissingWindowToReturn(
                WeeklyQuotaActivationPolicy.missingWindowResetKey
            ),
            "a returned weekly window must be baselined after missing-window activation"
        )

        expect(
            WeeklyQuotaActivationPolicy.shouldBaselineReturnedWindow(
                previousResetKey: "old-key",
                isPendingVerification: true
            ),
            "the first window after a request must only establish the new cycle baseline"
        )

        expect(
            !WeeklyQuotaActivationPolicy.shouldBaselineReturnedWindow(
                previousResetKey: "same-key",
                isPendingVerification: false
            ),
            "a stable verified window must continue through normal reset evaluation"
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
            "an explicit manual override may include an account whose weekly window is missing"
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
