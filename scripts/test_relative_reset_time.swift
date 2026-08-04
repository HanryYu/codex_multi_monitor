import Foundation

@main
struct RelativeResetTimeTests {
    static func main() {
        expect(RelativeResetTime(seconds: 0), days: 0, hours: 0, minutes: 0, description: "0m")
        expect(RelativeResetTime(seconds: 59), days: 0, hours: 0, minutes: 0, description: "0m")
        expect(RelativeResetTime(seconds: 65), days: 0, hours: 0, minutes: 1, description: "1m")
        expect(RelativeResetTime(seconds: 7_500), days: 0, hours: 2, minutes: 5, description: "2h 5m")
        expect(RelativeResetTime(seconds: 93_900), days: 1, hours: 2, minutes: 5, description: "1d 2h 5m")
        expect(RelativeResetTime(seconds: 691_500), days: 8, hours: 0, minutes: 5, description: "8d 5m")
        expect(RelativeResetTime(seconds: 86_400), days: 1, hours: 0, minutes: 0, description: "1d")
        expect(RelativeResetTime(seconds: -1), days: 0, hours: 0, minutes: 0, description: "0m")
        print("Relative reset time tests passed")
    }

    private static func expect(
        _ value: RelativeResetTime,
        days: Int,
        hours: Int,
        minutes: Int,
        description: String
    ) {
        precondition(
            value == RelativeResetTime(days: days, hours: hours, minutes: minutes),
            "expected \(days)d \(hours)h \(minutes)m, got \(value.days)d \(value.hours)h \(value.minutes)m"
        )
        precondition(
            value.compactDescription == description,
            "expected \(description), got \(value.compactDescription)"
        )
    }
}

private extension RelativeResetTime {
    init(days: Int, hours: Int, minutes: Int) {
        self.init(seconds: days * 86_400 + hours * 3_600 + minutes * 60)
    }
}
