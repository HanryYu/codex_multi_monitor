import Foundation

enum QuotaEquivalenceSource: Equatable {
    case exactOpenCodeGo
    case estimatedBaseline
    case learned
    case calibrating
}

struct QuotaAllowanceSummary: Equatable {
    let weeklyRemainingPercent: Int
    let remainingFiveHourEquivalents: Double?
    let capacityRatio: Double?
    let source: QuotaEquivalenceSource

    static func make(
        from rateLimit: RateLimit?,
        provider: AccountProvider,
        calibratedCapacityRatio: Double?
    ) -> QuotaAllowanceSummary? {
        guard let windows = QuotaWindowPair(rateLimit: rateLimit) else { return nil }

        let weeklyRemaining = max(0, 100 - windows.weekly.usedPercent)
        let ratio: Double?
        let source: QuotaEquivalenceSource

        if provider == .openCodeGo {
            // OpenCode Go publishes $12 per 5-hour window and $30 per week.
            ratio = 30.0 / 12.0
            source = .exactOpenCodeGo
        } else if let calibratedCapacityRatio,
                  calibratedCapacityRatio.isFinite,
                  calibratedCapacityRatio > 0 {
            ratio = calibratedCapacityRatio
            source = .learned
        } else if let baseline = provider.fullFiveHourWeeklyCapacityBaseline {
            ratio = baseline
            source = .estimatedBaseline
        } else {
            ratio = nil
            source = .calibrating
        }

        return QuotaAllowanceSummary(
            weeklyRemainingPercent: weeklyRemaining,
            remainingFiveHourEquivalents: ratio.map {
                $0 * Double(weeklyRemaining) / 100.0
            },
            capacityRatio: ratio,
            source: source
        )
    }
}

private extension AccountProvider {
    var fullFiveHourWeeklyCapacityBaseline: Double? {
        switch self {
        case .codex:
            // Current observed Codex windows commonly put one full 5h allowance
            // at roughly 15-16% of the weekly allowance.
            return 6.5
        case .claude:
            // Claude does not publish an absolute weekly/session ratio. Start from
            // a conservative seven-session baseline and replace it with account data.
            return 7.0
        case .openCodeGo:
            return 30.0 / 12.0
        case .grok:
            return nil
        }
    }
}

struct QuotaEquivalenceSample: Codable, Equatable {
    let fiveHourUsedPercent: Int
    let weeklyUsedPercent: Int
    let fiveHourResetAt: Int
    let weeklyResetAt: Int
}

struct QuotaEquivalenceCalibration: Codable, Equatable {
    private struct Delta: Codable, Equatable {
        let fiveHour: Int
        let weekly: Int
    }

    private(set) var anchor: QuotaEquivalenceSample?
    private var deltas: [Delta] = []

    init() {}

    var capacityRatio: Double? {
        let fiveHourDelta = deltas.reduce(0) { $0 + $1.fiveHour }
        let weeklyDelta = deltas.reduce(0) { $0 + $1.weekly }
        // Show an approximate ratio after the first meaningful paired change.
        // Later observations keep smoothing the whole-percentage rounding noise.
        guard fiveHourDelta >= 2, weeklyDelta >= 1 else { return nil }
        let ratio = Double(fiveHourDelta) / Double(weeklyDelta)
        guard (1.0...50.0).contains(ratio) else { return nil }
        return ratio
    }

    mutating func observe(_ sample: QuotaEquivalenceSample) {
        guard let anchor else {
            self.anchor = sample
            return
        }

        guard sameWindow(anchor.fiveHourResetAt, sample.fiveHourResetAt),
              sameWindow(anchor.weeklyResetAt, sample.weeklyResetAt)
        else {
            self.anchor = sample
            return
        }

        let fiveHourDelta = sample.fiveHourUsedPercent - anchor.fiveHourUsedPercent
        let weeklyDelta = sample.weeklyUsedPercent - anchor.weeklyUsedPercent
        guard fiveHourDelta >= 0, weeklyDelta >= 0 else {
            self.anchor = sample
            return
        }
        guard fiveHourDelta > 0 || weeklyDelta > 0 else { return }

        // If one rounded percentage has not moved yet, keep the older anchor so
        // the next observation includes the complete paired change.
        guard fiveHourDelta > 0, weeklyDelta > 0 else { return }

        deltas.append(Delta(fiveHour: fiveHourDelta, weekly: weeklyDelta))
        if deltas.count > 12 {
            deltas.removeFirst(deltas.count - 12)
        }
        self.anchor = sample
    }

    private func sameWindow(_ lhs: Int, _ rhs: Int) -> Bool {
        if lhs == 0 || rhs == 0 { return lhs == rhs }
        return abs(lhs - rhs) <= 5 * 60
    }
}

final class QuotaEquivalenceEstimator {
    static let shared = QuotaEquivalenceEstimator()

    private struct StoredCalibration: Codable {
        let signature: String
        var calibration: QuotaEquivalenceCalibration
    }

    private let defaults: UserDefaults
    private let keyPrefix = "CodexMonitor.quotaEquivalenceCalibration.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func observe(accountID: UUID, provider: AccountProvider, usage: UsageResponse) {
        guard provider != .openCodeGo,
              let windows = QuotaWindowPair(rateLimit: usage.rateLimit)
        else { return }

        let signature = planSignature(provider: provider, planType: usage.planType)
        var stored = load(accountID: accountID)
        if stored?.signature != signature {
            stored = StoredCalibration(signature: signature, calibration: .init())
        }

        stored?.calibration.observe(QuotaEquivalenceSample(
            fiveHourUsedPercent: windows.fiveHour.usedPercent,
            weeklyUsedPercent: windows.weekly.usedPercent,
            fiveHourResetAt: windows.fiveHour.resetAt,
            weeklyResetAt: windows.weekly.resetAt
        ))
        save(stored, accountID: accountID)
    }

    func capacityRatio(accountID: UUID, provider: AccountProvider, planType: String) -> Double? {
        if provider == .openCodeGo { return 30.0 / 12.0 }
        let signature = planSignature(provider: provider, planType: planType)
        guard let stored = load(accountID: accountID), stored.signature == signature else { return nil }
        return stored.calibration.capacityRatio
    }

    private func planSignature(provider: AccountProvider, planType: String) -> String {
        let normalizedPlan = planType.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(provider.rawValue):\(normalizedPlan)"
    }

    private func key(accountID: UUID) -> String {
        keyPrefix + accountID.uuidString
    }

    private func load(accountID: UUID) -> StoredCalibration? {
        guard let data = defaults.data(forKey: key(accountID: accountID)) else { return nil }
        return try? JSONDecoder().decode(StoredCalibration.self, from: data)
    }

    private func save(_ stored: StoredCalibration?, accountID: UUID) {
        guard let stored, let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key(accountID: accountID))
    }
}

private struct QuotaWindowPair {
    let fiveHour: WindowUsage
    let weekly: WindowUsage

    init?(rateLimit: RateLimit?) {
        guard let rateLimit,
              let fiveHour = rateLimit.allWindows.first(where: { $0.isFiveHourWindow }),
              let weekly = rateLimit.allWindows.first(where: { $0.isWeeklyWindow })
        else { return nil }
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

private extension RateLimit {
    var allWindows: [WindowUsage] {
        [primaryWindow, secondaryWindow, tertiaryWindow].compactMap { $0 }
    }
}

private extension WindowUsage {
    var isFiveHourWindow: Bool {
        (4 * 60 * 60)...(6 * 60 * 60) ~= limitWindowSeconds
    }

    var isWeeklyWindow: Bool {
        (6 * 24 * 60 * 60)...(8 * 24 * 60 * 60) ~= limitWindowSeconds
    }
}
