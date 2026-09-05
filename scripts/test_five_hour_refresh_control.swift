import Foundation

@main
struct FiveHourRefreshControlTests {
    static func main() {
        typealias State = FiveHourRefreshControl.State
        let on = State(refreshEnabled: true, wakeEnabled: true, ownsWakeSchedule: true)
        let off = State(refreshEnabled: false, wakeEnabled: false, ownsWakeSchedule: false)
        let leftover = State(refreshEnabled: false, wakeEnabled: true, ownsWakeSchedule: true)
        var events: [String] = []

        let disabled = FiveHourRefreshControl.setEnabled(false, current: on) {
            events.append("stop")
        } configureWake: { enabled in
            events.append("wake:\(enabled)")
            return true
        }
        precondition(events == ["stop", "wake:false"], "Stop requests before asking macOS to cancel")
        precondition(disabled.state == off && disabled.failure == nil)

        var attempts = 0
        let cancelled = FiveHourRefreshControl.setEnabled(false, current: on, stopRefreshing: {}) { _ in
            attempts += 1
            return false
        }
        precondition(attempts == 1, "A cancelled permission dialog must not trigger recursive requests")
        precondition(cancelled.state == leftover && cancelled.failure == .disableWake)
        precondition(cancelled.state.needsWakeCleanup, "Cleanup must remain reachable with the main switch off")

        let retried = FiveHourRefreshControl.setEnabled(false, current: cancelled.state, stopRefreshing: {}) { enabled in
            precondition(!enabled)
            return true
        }
        precondition(retried.state == off && retried.failure == nil)

        let staleWakeFlag = State(refreshEnabled: false, wakeEnabled: true, ownsWakeSchedule: false)
        let unowned = FiveHourRefreshControl.setEnabled(false, current: staleWakeFlag, stopRefreshing: {}) { _ in
            preconditionFailure("Do not cancel system schedules that the app does not own")
        }
        precondition(unowned.state == off && unowned.failure == nil)

        let inconsistentFlags = State(refreshEnabled: true, wakeEnabled: false, ownsWakeSchedule: true)
        let repaired = FiveHourRefreshControl.setEnabled(false, current: inconsistentFlags, stopRefreshing: {}) { enabled in
            precondition(!enabled, "Ownership requires cleanup even if the wake UI flag is false")
            return true
        }
        precondition(repaired.state == off)

        let enabled = FiveHourRefreshControl.setEnabled(true, current: off, stopRefreshing: {
            preconditionFailure("Enabling must not stop the scheduler")
        }) { wake in
            precondition(wake)
            return true
        }
        precondition(enabled.state == on && enabled.failure == nil)

        let deniedEnable = FiveHourRefreshControl.setEnabled(true, current: off, stopRefreshing: {}) { _ in false }
        precondition(deniedEnable.state == off && deniedEnable.failure == .enableWake)

        let alreadyOff = FiveHourRefreshControl.setEnabled(false, current: off, stopRefreshing: {}) { _ in
            preconditionFailure("Already disabled needs no system authorization")
        }
        precondition(alreadyOff.state == off && !alreadyOff.state.needsWakeCleanup)

        print("FiveHourRefreshControl: 8 cases passed (no system schedule or preferences modified)")
    }
}
