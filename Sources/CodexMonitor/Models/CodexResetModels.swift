import Foundation

struct CodexResetSchedule: Equatable {
    let announcedAt: Date
    let expectedAt: Date
    let sourceURL: URL?
    let originalTimeLabel: String
    let isApproximate: Bool

    func isActive(at date: Date) -> Bool {
        announcedAt <= date && date <= expectedAt.addingTimeInterval(2 * 60 * 60)
    }
}

struct CodexResetForecast: Codable, Equatable {
    let mode: String?
    let updatedAt: String
    let probabilities: Probabilities
    let confidence: String
    let confidenceNote: String?
    let lastResetAt: String?
    let officialSignal: OfficialSignal?

    struct Probabilities: Codable, Equatable {
        let rounded24h: Int
        let rounded48h: Int
        let commitmentFloorPercent: Int?

        enum CodingKeys: String, CodingKey {
            case rounded24h = "rounded_24h"
            case rounded48h = "rounded_48h"
            case commitmentFloorPercent = "commitment_floor_percent"
        }
    }

    struct OfficialSignal: Codable, Equatable {
        let tweetID: String
        let summary: String
        let at: String
        let url: URL?
        let window: Window?
        let isApproximate: Bool?

        struct Window: Codable, Equatable {
            let label: String?
            let startAt: String?
            let endAt: String?

            enum CodingKeys: String, CodingKey {
                case label
                case startAt = "start_at"
                case endAt = "end_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tweetID = "tweet_id"
            case summary
            case at
            case url
            case window
            case isApproximate
        }

        func isCurrent(at date: Date = Date()) -> Bool {
            guard let startsAt = at.codexResetDate,
                  let endsAt = window?.endAt?.codexResetDate else { return false }
            return startsAt <= date && date <= endsAt
        }
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case updatedAt = "updated_at"
        case probabilities
        case confidence
        case confidenceNote = "confidence_note"
        case lastResetAt = "last_reset_at"
        case officialSignal = "official_signal"
    }
}

struct CodexResetFeed: Codable, Equatable {
    let fetchedAt: String
    let stale: Bool
    let contentAgeDays: Double?
    let newestPostAt: String?
    let profile: Profile
    let signal: Signal?
    let tweets: [Tweet]

    struct Profile: Codable, Equatable {
        let handle: String
        let name: String
        let followers: Int?
    }

    struct Signal: Codable, Equatable {
        let tweetID: String
        let summary: String
        let at: String
        let url: URL?
        let kind: String?
        let active: Bool

        enum CodingKeys: String, CodingKey {
            case tweetID = "tweet_id"
            case summary
            case at
            case url
            case kind
            case active
        }
    }

    struct Tweet: Codable, Equatable, Identifiable {
        let id: String
        let url: URL?
        let text: String
        let at: String
        let kind: String
        let replies: Int?
        let likes: Int?
        let resetVerification: ResetVerification?
        let resetVerificationCandidate: Bool?
        let resetVerificationStatus: String?

        struct ResetVerification: Codable, Equatable {
            let status: String
            let evidenceSummary: String?
            let observationResult: String?
            let observedPercentage: Int?

            enum CodingKeys: String, CodingKey {
                case status
                case evidenceSummary = "evidence_summary"
                case observationResult = "observation_result"
                case observedPercentage = "observed_percentage"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case url
            case text
            case at
            case kind
            case replies
            case likes
            case resetVerification = "reset_verification"
            case resetVerificationCandidate = "reset_verification_candidate"
            case resetVerificationStatus = "reset_verification_status"
        }

        var verificationStatus: String? {
            resetVerification?.status ?? resetVerificationStatus
        }

        var observationResult: String? {
            resetVerification?.observationResult
        }
    }

    enum CodingKeys: String, CodingKey {
        case fetchedAt = "fetched_at"
        case stale
        case contentAgeDays = "content_age_days"
        case newestPostAt = "newest_post_at"
        case profile
        case signal
        case tweets
    }
}

struct CodexResetSnapshot: Codable, Equatable {
    let forecast: CodexResetForecast
    let feed: CodexResetFeed

    var probability24h: Int { forecast.probabilities.rounded24h }
    var probability48h: Int { forecast.probabilities.rounded48h }

    var activeSignal: CodexResetFeed.Signal? {
        resolvedActiveSignal()
    }

    func resolvedActiveSignal(at date: Date = Date()) -> CodexResetFeed.Signal? {
        guard let signal = feed.signal, signal.active else { return nil }
        guard let signalDate = signal.at.codexResetDate else { return nil }
        let age = date.timeIntervalSince(signalDate)
        guard age >= 0 && age <= 24 * 60 * 60 else { return nil }
        guard let tweet = signalTweet else { return signal }
        let rejectedStatuses = ["rejected", "expired", "unverified"]
        if let status = tweet.verificationStatus?.lowercased(),
           rejectedStatuses.contains(status) {
            return nil
        }
        if let result = tweet.observationResult?.lowercased(),
           ["unchanged", "unverified"].contains(result) {
            return nil
        }
        return signal
    }

    var confirmedActiveSignal: CodexResetFeed.Signal? {
        resolvedConfirmedActiveSignal()
    }

    func resolvedConfirmedActiveSignal(at date: Date = Date()) -> CodexResetFeed.Signal? {
        guard let signal = resolvedActiveSignal(at: date),
              let tweet = signalTweet else { return nil }
        let status = tweet.verificationStatus?.lowercased()
        let result = tweet.observationResult?.lowercased()
        return status == "confirmed" || result == "reset_observed" ? signal : nil
    }

    func hasRecentConfirmedReset(at date: Date = Date()) -> Bool {
        resolvedConfirmedActiveSignal(at: date) != nil
    }

    var latestTweet: CodexResetFeed.Tweet? {
        feed.tweets.dropFirst().reduce(feed.tweets.first) { latest, candidate in
            guard let latest else { return candidate }
            guard let candidateDate = candidate.at.codexResetDate else { return latest }
            guard let latestDate = latest.at.codexResetDate else { return candidate }
            return candidateDate > latestDate ? candidate : latest
        }
    }

    var signalTweet: CodexResetFeed.Tweet? {
        guard let signalID = feed.signal?.tweetID else { return nil }
        return feed.tweets.first { $0.id == signalID }
    }

    func resetSchedule(at date: Date = Date()) -> CodexResetSchedule? {
        if let signal = forecast.officialSignal,
           signal.isCurrent(at: date),
           let expectedAt = signal.window?.endAt?.codexResetDate {
            return CodexResetSchedule(
                announcedAt: signal.at.codexResetDate ?? date,
                expectedAt: expectedAt,
                sourceURL: signal.url,
                originalTimeLabel: signal.window?.label ?? "Official reset window",
                isApproximate: signal.isApproximate ?? true
            )
        }

        return feed.tweets
            .filter { $0.kind.lowercased() == "signal" }
            .sorted { ($0.at.codexResetDate ?? .distantPast) > ($1.at.codexResetDate ?? .distantPast) }
            .compactMap(CodexResetScheduleParser.parse)
            .first { $0.isActive(at: date) }
    }

    func primaryProbability24h(at date: Date = Date()) -> Int {
        if hasRecentConfirmedReset(at: date) { return 100 }
        if let schedule = resetSchedule(at: date),
           schedule.expectedAt <= date.addingTimeInterval(24 * 60 * 60) {
            return 100
        }
        if forecast.officialSignal?.isCurrent(at: date) == true,
           let floor = forecast.probabilities.commitmentFloorPercent {
            return max(floor, probability24h)
        }
        return probability24h
    }

    func primaryProbability48h(at date: Date = Date()) -> Int {
        if hasRecentConfirmedReset(at: date) { return 100 }
        if let schedule = resetSchedule(at: date),
           schedule.expectedAt <= date.addingTimeInterval(48 * 60 * 60) {
            return 100
        }
        return probability48h
    }
}

struct CodexResetObservatoryResponse: Decodable, Equatable {
    let schemaVersion: String
    let checkedAt: String
    let updatedAt: String?
    let dataHealth: DataHealth
    let viewModel: ViewModel
    let latestTiboActivity: TiboActivity?

    struct DataHealth: Decodable, Equatable {
        let overall: String
        let stale: Bool
        let generatedAt: String
        let sources: Sources

        struct Sources: Decodable, Equatable {
            let supabaseSignals: Source
            let openAIStatus: Source
        }

        struct Source: Decodable, Equatable {
            let state: String
            let detail: String?
        }
    }

    struct ViewModel: Decodable, Equatable {
        let status: String
        let expectation: String
        let probability24h: Double?
        let probability48h: Double?
        let lastUpdated: String?
        let activeWindow: ActiveWindow
        let displayReasoningSummary: String?
        let recentHistory: [HistoryItem]

        struct ActiveWindow: Decodable, Equatable {
            let active: Bool
            let kind: String
            let noticeKind: String?
            let label: String
            let summary: String
            let openedAt: String?
            let expectedAt: String?
            let expectedEndAt: String?
            let expectedPrecision: String?
            let expectedTimeZone: String?
            let source: URL?
            let sourceLabel: String?
            let isOverduePending: Bool?
            let overdueText: String?
        }

        struct HistoryItem: Decodable, Equatable {
            let key: String
            let recordKind: String?
            let date: String?
            let resetAt: String?
        }
    }

    struct TiboActivity: Decodable, Equatable {
        let classification: String
        let text: String?
        let createdAt: String
        let sourceUrl: URL?
        let isReply: Bool
    }

    func makeSnapshot() throws -> CodexResetSnapshot {
        guard schemaVersion == "public-v1" else {
            throw CodexResetObservatoryMappingError.unsupportedSchema(schemaVersion)
        }
        guard let raw24h = viewModel.probability24h,
              let raw48h = viewModel.probability48h else {
            throw CodexResetObservatoryMappingError.missingProbabilities
        }

        let activeWindow = viewModel.activeWindow
        let isForcedNotice = activeWindow.active
            && activeWindow.kind == "official"
            && activeWindow.noticeKind != "banked"
        let isExecuted = latestTiboActivity?.classification == "reset_executed"
        let sourceURL = latestTiboActivity?.sourceUrl ?? activeWindow.source
        let activityAt = latestTiboActivity?.createdAt
            ?? activeWindow.openedAt
            ?? checkedAt
        let sourceID = sourceURL?.lastPathComponent.nonEmpty
            ?? "observatory-\(activityAt)"
        let activityText = latestTiboActivity?.text?.nonEmpty
            ?? activeWindow.summary.nonEmpty
            ?? "No recent reset activity was returned."
        let signalIsActive = isForcedNotice || isExecuted
        let signalSummary = isForcedNotice ? activeWindow.summary : activityText

        let resetVerification: CodexResetFeed.Tweet.ResetVerification? = isExecuted
            ? .init(
                status: "confirmed",
                evidenceSummary: "Codex Reset Observatory classified this signal as reset_executed.",
                observationResult: "reset_observed",
                observedPercentage: 100
            )
            : nil

        let tweet = CodexResetFeed.Tweet(
            id: sourceID,
            url: sourceURL,
            text: activityText,
            at: activityAt,
            kind: activityKind,
            replies: nil,
            likes: nil,
            resetVerification: resetVerification,
            resetVerificationCandidate: signalIsActive ? true : nil,
            resetVerificationStatus: resetVerification?.status
        )

        let signal = signalIsActive
            ? CodexResetFeed.Signal(
                tweetID: sourceID,
                summary: signalSummary,
                at: activityAt,
                url: sourceURL,
                kind: isExecuted ? "confirmed" : "signal",
                active: true
            )
            : nil

        let expectedAt = activeWindow.expectedAt ?? activeWindow.expectedEndAt
        let officialSignal: CodexResetForecast.OfficialSignal? = isForcedNotice && expectedAt != nil
            ? .init(
                tweetID: sourceID,
                summary: activeWindow.summary,
                at: activeWindow.openedAt ?? activityAt,
                url: activeWindow.source ?? sourceURL,
                window: .init(
                    label: originalTimeLabel(
                        expectedAt: expectedAt,
                        timeZoneAbbreviation: activeWindow.expectedTimeZone
                    ) ?? activeWindow.label,
                    startAt: activeWindow.openedAt ?? activityAt,
                    endAt: expectedAt
                ),
                isApproximate: activeWindow.expectedPrecision != "exact_time"
                    || activityText.lowercased().contains("around")
                    || activityText.lowercased().contains("about")
            )
            : nil

        let latestGlobalResetAt = viewModel.recentHistory
            .filter { $0.recordKind == "confirmed_global" }
            .compactMap { item -> (String, Date)? in
                let timestamp = item.resetAt ?? item.date
                guard let timestamp, let date = timestamp.codexResetDate else { return nil }
                return (timestamp, date)
            }
            .max { $0.1 < $1.1 }?
            .0

        let checkedDate = checkedAt.codexResetDate
        let activityDate = activityAt.codexResetDate
        let contentAgeDays = checkedDate.flatMap { checked in
            activityDate.map { max(0, checked.timeIntervalSince($0) / 86_400) }
        }
        let isStale = dataHealth.stale
            || dataHealth.overall != "ok"
            || dataHealth.sources.supabaseSignals.state != "ok"

        return CodexResetSnapshot(
            forecast: CodexResetForecast(
                mode: isForcedNotice ? "announced" : "model",
                updatedAt: viewModel.lastUpdated ?? checkedAt,
                probabilities: .init(
                    rounded24h: Self.percentage(raw24h),
                    rounded48h: Self.percentage(raw48h),
                    commitmentFloorPercent: nil
                ),
                confidence: viewModel.expectation.lowercased(),
                confidenceNote: viewModel.displayReasoningSummary,
                lastResetAt: latestGlobalResetAt,
                officialSignal: officialSignal
            ),
            feed: CodexResetFeed(
                fetchedAt: checkedAt,
                stale: isStale,
                contentAgeDays: contentAgeDays,
                newestPostAt: activityAt,
                profile: .init(handle: "thsottiaux", name: "Tibo", followers: nil),
                signal: signal,
                tweets: [tweet]
            )
        )
    }

    private var activityKind: String {
        switch latestTiboActivity?.classification {
        case "official_notice": return "signal"
        case "reset_executed": return "signal"
        case "teaser": return "candidate"
        default: return "other"
        }
    }

    private static func percentage(_ value: Double) -> Int {
        min(100, max(0, Int((value * 100).rounded())))
    }

    private func originalTimeLabel(
        expectedAt: String?,
        timeZoneAbbreviation: String?
    ) -> String? {
        guard let expectedAt,
              let date = expectedAt.codexResetDate,
              let abbreviation = timeZoneAbbreviation?.uppercased(),
              let timeZone = Self.timeZone(for: abbreviation) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: date)) \(abbreviation)"
    }

    private static func timeZone(for abbreviation: String) -> TimeZone? {
        switch abbreviation {
        case "PST": return TimeZone(secondsFromGMT: -8 * 60 * 60)
        case "PDT": return TimeZone(secondsFromGMT: -7 * 60 * 60)
        case "PT": return TimeZone(identifier: "America/Los_Angeles")
        case "UTC", "GMT": return TimeZone(secondsFromGMT: 0)
        default: return TimeZone(abbreviation: abbreviation)
        }
    }
}

enum CodexResetObservatoryMappingError: LocalizedError {
    case unsupportedSchema(String)
    case missingProbabilities

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported Codex Reset Observatory schema: \(schema)"
        case .missingProbabilities:
            return "Codex Reset Observatory response is missing forecast probabilities"
        }
    }
}

private enum CodexResetScheduleParser {
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(PST|PDT|PT|UTC|GMT)\b"#,
        options: [.caseInsensitive]
    )

    static func parse(_ tweet: CodexResetFeed.Tweet) -> CodexResetSchedule? {
        let lowercased = tweet.text.lowercased()
        guard lowercased.contains("reset will land")
                || lowercased.contains("reset will arrive")
                || lowercased.contains("reset will be there") else {
            return nil
        }
        guard !lowercased.contains("banked reset"),
              let announcedAt = tweet.at.codexResetDate else { return nil }

        let fullRange = NSRange(tweet.text.startIndex..<tweet.text.endIndex, in: tweet.text)
        guard let match = timePattern.firstMatch(in: tweet.text, range: fullRange),
              let hourText = substring(in: tweet.text, range: match.range(at: 1)),
              let rawHour = Int(hourText),
              let zoneText = substring(in: tweet.text, range: match.range(at: 4))?.uppercased(),
              let timeZone = timeZone(for: zoneText) else { return nil }

        let minute = substring(in: tweet.text, range: match.range(at: 2)).flatMap(Int.init) ?? 0
        let meridiem = substring(in: tweet.text, range: match.range(at: 3))?.lowercased()
        guard minute < 60, let hour = normalizedHour(rawHour, meridiem: meridiem) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var sourceDay = calendar.startOfDay(for: announcedAt)
        if lowercased.contains("tomorrow") {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: sourceDay) else { return nil }
            sourceDay = tomorrow
        }

        var components = calendar.dateComponents([.year, .month, .day], from: sourceDay)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var expectedAt = calendar.date(from: components) else { return nil }

        if !lowercased.contains("tomorrow"), expectedAt <= announcedAt,
           let nextDay = calendar.date(byAdding: .day, value: 1, to: expectedAt) {
            expectedAt = nextDay
        }

        return CodexResetSchedule(
            announcedAt: announcedAt,
            expectedAt: expectedAt,
            sourceURL: tweet.url,
            originalTimeLabel: originalTimeLabel(hour: hour, minute: minute, zone: zoneText),
            isApproximate: lowercased.contains("around") || lowercased.contains("about")
        )
    }

    private static func substring(in text: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func normalizedHour(_ hour: Int, meridiem: String?) -> Int? {
        if hour > 12 {
            return hour < 24 ? hour : nil
        }
        guard hour >= 1 else { return nil }
        switch meridiem {
        case "pm": return hour == 12 ? 12 : hour + 12
        case "am": return hour == 12 ? 0 : hour
        default: return hour
        }
    }

    private static func timeZone(for abbreviation: String) -> TimeZone? {
        switch abbreviation {
        case "PST": return TimeZone(secondsFromGMT: -8 * 60 * 60)
        case "PDT": return TimeZone(secondsFromGMT: -7 * 60 * 60)
        case "PT": return TimeZone(identifier: "America/Los_Angeles")
        case "UTC", "GMT": return TimeZone(secondsFromGMT: 0)
        default: return nil
        }
    }

    private static func originalTimeLabel(hour: Int, minute: Int, zone: String) -> String {
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@ %@", displayHour, minute, meridiem, zone)
    }
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    var codexResetDate: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}
