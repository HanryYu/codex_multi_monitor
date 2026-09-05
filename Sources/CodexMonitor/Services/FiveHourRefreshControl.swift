import Foundation

/// A user-initiated transition, independent of the lifetime of the settings subviews.
enum FiveHourRefreshControl {
    struct State: Equatable {
        var refreshEnabled: Bool
        var wakeEnabled: Bool
        var ownsWakeSchedule: Bool

        var needsWakeCleanup: Bool { !refreshEnabled && (wakeEnabled || ownsWakeSchedule) }
    }

    enum Failure: Equatable {
        case enableWake
        case disableWake
    }

    struct Result {
        let state: State
        let failure: Failure?
    }

    static func setEnabled(
        _ enabled: Bool,
        current: State,
        stopRefreshing: () -> Void,
        configureWake: (Bool) -> Bool
    ) -> Result {
        var next = current
        if enabled {
            guard configureWake(true) else {
                return Result(state: current, failure: .enableWake)
            }
            next = State(refreshEnabled: true, wakeEnabled: true, ownsWakeSchedule: true)
        } else {
            // Stop future requests even if the user cancels the system authorization dialog.
            stopRefreshing()
            next.refreshEnabled = false
            // Never cancel someone else's system schedule based only on the UI wake toggle.
            if current.ownsWakeSchedule && !configureWake(false) {
                next.wakeEnabled = true
                return Result(state: next, failure: .disableWake)
            }
            next.wakeEnabled = false
            next.ownsWakeSchedule = false
        }
        return Result(state: next, failure: nil)
    }
}

extension Notification.Name {
    static let fiveHourRefreshChanged = Notification.Name("CodexMonitor.fiveHourRefreshChanged")
}
