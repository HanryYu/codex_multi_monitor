import Foundation

struct CodexResetForecast: Decodable, Equatable {
    let updatedAt: String
    let probabilities: Probabilities
    let confidence: String
    let confidenceNote: String?
    let lastResetAt: String?

    struct Probabilities: Decodable, Equatable {
        let rounded24h: Int
        let rounded48h: Int

        enum CodingKeys: String, CodingKey {
            case rounded24h = "rounded_24h"
            case rounded48h = "rounded_48h"
        }
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case probabilities
        case confidence
        case confidenceNote = "confidence_note"
        case lastResetAt = "last_reset_at"
    }
}

struct CodexResetFeed: Decodable, Equatable {
    let fetchedAt: String
    let stale: Bool
    let contentAgeDays: Double?
    let profile: Profile
    let signal: Signal?
    let tweets: [Tweet]

    struct Profile: Decodable, Equatable {
        let handle: String
        let name: String
        let followers: Int?
    }

    struct Signal: Decodable, Equatable {
        let tweetID: String
        let summary: String
        let at: String
        let url: URL?
        let active: Bool

        enum CodingKeys: String, CodingKey {
            case tweetID = "tweet_id"
            case summary
            case at
            case url
            case active
        }
    }

    struct Tweet: Decodable, Equatable, Identifiable {
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

        struct ResetVerification: Decodable, Equatable {
            let status: String
            let evidenceSummary: String?

            enum CodingKeys: String, CodingKey {
                case status
                case evidenceSummary = "evidence_summary"
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
    }

    enum CodingKeys: String, CodingKey {
        case fetchedAt = "fetched_at"
        case stale
        case contentAgeDays = "content_age_days"
        case profile
        case signal
        case tweets
    }
}

struct CodexResetSnapshot: Equatable {
    let forecast: CodexResetForecast
    let feed: CodexResetFeed

    var probability24h: Int { forecast.probabilities.rounded24h }
    var probability48h: Int { forecast.probabilities.rounded48h }

    var activeSignal: CodexResetFeed.Signal? {
        guard let signal = feed.signal, signal.active else { return nil }
        return signal
    }

    var latestTweet: CodexResetFeed.Tweet? { feed.tweets.first }
}

extension String {
    var codexResetDate: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}
