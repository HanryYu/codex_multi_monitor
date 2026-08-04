import Foundation

@main
enum CodexResetDecodingTests {
    static func main() throws {
        let forecastJSON = #"{"updated_at":"2026-08-04T01:12:07.288Z","probabilities":{"rounded_24h":20,"rounded_48h":30},"confidence":"medium","confidence_note":"Enough history","last_reset_at":"2026-08-01T03:32:37.000Z"}"#.data(using: .utf8)!
        let feedJSON = #"{"fetched_at":"2026-08-04T00:56:13.367Z","stale":false,"content_age_days":0.7,"profile":{"handle":"thsottiaux","name":"Tibo","followers":332050},"signal":{"tweet_id":"1","summary":"Reset soon","at":"2026-08-03T00:00:00Z","url":"https://x.com/thsottiaux/status/1","active":true},"tweets":[{"id":"2","url":"https://x.com/thsottiaux/status/2","text":"Latest post","at":"2026-08-03T08:37:22Z","kind":"candidate","replies":10,"likes":20,"reset_verification_candidate":true,"reset_verification_status":"confirmed","reset_verification":{"status":"confirmed","evidence_summary":"verified"}}]}"#.data(using: .utf8)!

        let forecast = try JSONDecoder().decode(CodexResetForecast.self, from: forecastJSON)
        let feed = try JSONDecoder().decode(CodexResetFeed.self, from: feedJSON)
        let snapshot = CodexResetSnapshot(forecast: forecast, feed: feed)

        precondition(snapshot.probability24h == 20)
        precondition(snapshot.probability48h == 30)
        precondition(snapshot.activeSignal?.summary == "Reset soon")
        precondition(snapshot.latestTweet?.verificationStatus == "confirmed")
        precondition(snapshot.forecast.lastResetAt?.codexResetDate != nil)
        print("Codex Reset decoding tests passed")
    }
}
