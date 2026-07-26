import AppKit
import Foundation

@MainActor
final class WeeklyQuotaActivationScheduler {
    private static let pollInterval: TimeInterval = 60 * 60

    private weak var accountStore: AccountStore?
    private var timer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lastLifecycleRefreshAt: Date?

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
    }

    func start(runInitialCheck: Bool = false) {
        stop()
        WeeklyQuotaLogger.log("scheduler started intervalSeconds=3600 wakeCheck=enabled")

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(source: "hourly-timer")
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let lifecycleNotifications: [(Notification.Name, String)] = [
            (NSWorkspace.didWakeNotification, "mac-wake"),
            (NSWorkspace.screensDidWakeNotification, "screens-wake"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session-active"),
        ]
        lifecycleObservers = lifecycleNotifications.map { notificationName, source in
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh(source: source, coalesceLifecycleEvent: true)
                }
            }
        }

        if runInitialCheck {
            refresh(source: "preference-enabled")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in lifecycleObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
        lastLifecycleRefreshAt = nil
    }

    private func refresh(source: String, coalesceLifecycleEvent: Bool = false) {
        guard UserDefaults.standard.bool(forKey: PreferencesKeys.quotaActivationEnabled) else {
            WeeklyQuotaLogger.log("scheduler check skipped source=\(source) reason=automatic-disabled")
            return
        }
        guard let accountStore,
              accountStore.accounts.contains(where: { $0.provider == .codex })
        else {
            WeeklyQuotaLogger.log("scheduler check skipped source=\(source) reason=no-codex-accounts")
            return
        }

        if coalesceLifecycleEvent,
           let lastLifecycleRefreshAt,
           Date().timeIntervalSince(lastLifecycleRefreshAt) < 5 {
            WeeklyQuotaLogger.log("scheduler check coalesced source=\(source) reason=recent-lifecycle-event")
            return
        }
        if coalesceLifecycleEvent {
            lastLifecycleRefreshAt = Date()
        }

        WeeklyQuotaLogger.log("scheduler refreshing usage source=\(source)")
        Task {
            await accountStore.refreshAll()
        }
    }
}
