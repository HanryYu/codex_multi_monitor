import Foundation

enum CodexResetPostTimestamp {
    static func text(for date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))

        if elapsed < 60 { return "<1m" }
        if elapsed < 3_600 { return "\(elapsed / 60)m" }
        if elapsed < 86_400 { return "\(elapsed / 3_600)h" }
        if elapsed < 604_800 { return "\(elapsed / 86_400)d" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = formatter.calendar.component(.year, from: date)
            == formatter.calendar.component(.year, from: now) ? "M/d" : "yyyy/M/d"
        return formatter.string(from: date)
    }
}
