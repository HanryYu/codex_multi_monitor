import AppKit
import Foundation

@MainActor
final class WeeklyQuotaActivationScheduler {
    private static let pollInterval: TimeInterval = 60 * 60

    private weak var accountStore: AccountStore?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(accountStore: AccountStore) {
        self.accountStore = accountStore
    }

    func start() {
        stop()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfStale()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfStale()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func refreshIfStale() {
        guard let accountStore,
              accountStore.accounts.contains(where: { $0.provider == .codex })
        else { return }

        if let lastRefreshTime = accountStore.lastRefreshTime,
           Date().timeIntervalSince(lastRefreshTime) < Self.pollInterval {
            return
        }

        Task {
            await accountStore.refreshAll()
        }
    }
}
