import Foundation

struct RelativeResetTime: Equatable {
    let days: Int
    let hours: Int
    let minutes: Int

    init(seconds: Int) {
        let clampedSeconds = max(0, seconds)
        days = clampedSeconds / 86_400
        hours = (clampedSeconds % 86_400) / 3_600
        minutes = (clampedSeconds % 3_600) / 60
    }

    var compactDescription: String {
        [
            days > 0 ? "\(days)d" : nil,
            hours > 0 ? "\(hours)h" : nil,
            minutes > 0 || (days == 0 && hours == 0) ? "\(minutes)m" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
