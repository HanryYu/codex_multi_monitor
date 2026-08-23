import Foundation

@main
enum CodexResetDecodingTests {
    static func main() throws {
        let forecastJSON = #"{"mode":"announced","updated_at":"2026-08-04T01:12:07.288Z","probabilities":{"rounded_24h":20,"rounded_48h":30,"commitment_floor_percent":85},"confidence":"medium","confidence_note":"Enough history","last_reset_at":"2026-08-01T03:32:37.000Z","official_signal":{"tweet_id":"1","summary":"Reset soon","at":"2026-08-03T00:00:00Z","url":"https://x.com/thsottiaux/status/1","window":{"label":"within an hour","start_at":"2026-08-03T00:00:00Z","end_at":"2026-08-03T01:00:00Z"}}}"#.data(using: .utf8)!
        let feedJSON = #"{"fetched_at":"2026-08-04T00:56:13.367Z","stale":false,"content_age_days":0.7,"newest_post_at":"2026-08-03T08:37:22Z","profile":{"handle":"thsottiaux","name":"Tibo","followers":332050},"signal":{"tweet_id":"1","summary":"Reset soon","at":"2026-08-03T00:00:00Z","url":"https://x.com/thsottiaux/status/1","kind":"candidate","active":true},"tweets":[{"id":"1","url":"https://x.com/thsottiaux/status/1","text":"Reset soon","at":"2026-08-03T00:00:00Z","kind":"candidate","replies":1,"likes":2,"reset_verification_candidate":true,"reset_verification_status":"confirmed","reset_verification":{"status":"confirmed","evidence_summary":"verified","observation_result":"reset_observed","observed_percentage":100}},{"id":"old","url":"https://x.com/thsottiaux/status/old","text":"Older post returned first","at":"2026-08-02T08:37:22Z","kind":"other","replies":3,"likes":4},{"id":"2","url":"https://x.com/thsottiaux/status/2","text":"Latest post","at":"2026-08-03T08:37:22Z","kind":"limits","replies":10,"likes":20}]}"#.data(using: .utf8)!

        let forecast = try JSONDecoder().decode(CodexResetForecast.self, from: forecastJSON)
        let feed = try JSONDecoder().decode(CodexResetFeed.self, from: feedJSON)
        let snapshot = CodexResetSnapshot(forecast: forecast, feed: feed)

        precondition(snapshot.probability24h == 20)
        precondition(snapshot.probability48h == 30)
        precondition(snapshot.resolvedActiveSignal(
            at: "2026-08-03T00:30:00Z".codexResetDate!
        )?.summary == "Reset soon")
        precondition(snapshot.resolvedConfirmedActiveSignal(
            at: "2026-08-03T00:30:00Z".codexResetDate!
        )?.summary == "Reset soon")
        precondition(snapshot.hasRecentConfirmedReset(
            at: "2026-08-03T00:30:00Z".codexResetDate!
        ))
        precondition(snapshot.primaryProbability24h(
            at: "2026-08-03T00:30:00Z".codexResetDate!
        ) == 100)
        precondition(snapshot.primaryProbability24h(
            at: "2026-08-04T01:00:01Z".codexResetDate!
        ) == 20)
        precondition(snapshot.latestTweet?.id == "2")
        precondition(snapshot.latestTweet?.text == "Latest post")
        precondition(snapshot.signalTweet?.verificationStatus == "confirmed")
        precondition(snapshot.signalTweet?.resetVerification?.observedPercentage == 100)
        precondition(snapshot.forecast.lastResetAt?.codexResetDate != nil)

        let rejectedFeedJSON = #"{"fetched_at":"2026-08-17T14:46:08.454Z","stale":false,"content_age_days":0.4,"profile":{"handle":"thsottiaux","name":"Tibo","followers":332050},"signal":{"tweet_id":"3","summary":"Landing soon","at":"2026-08-13T01:01:37.000Z","url":"https://x.com/thsottiaux/status/3","kind":"candidate","active":true},"tweets":[{"id":"4","url":"https://x.com/thsottiaux/status/4","text":"Newest post","at":"2026-08-17T04:23:55.000Z","kind":"limits","replies":94,"likes":843},{"id":"3","url":"https://x.com/thsottiaux/status/3","text":"Landing soon","at":"2026-08-13T01:01:37.000Z","kind":"candidate","replies":3084,"likes":14288,"reset_verification_candidate":true,"reset_verification_status":"rejected","reset_verification":{"status":"rejected","evidence_summary":"weekly_limit_below_100_for_full_window;samples=168;peak=27","observation_result":"unchanged","observed_percentage":27}}]}"#.data(using: .utf8)!
        let rejectedFeed = try JSONDecoder().decode(CodexResetFeed.self, from: rejectedFeedJSON)
        let rejectedSnapshot = CodexResetSnapshot(forecast: forecast, feed: rejectedFeed)
        precondition(rejectedSnapshot.latestTweet?.id == "4")
        precondition(rejectedSnapshot.resolvedActiveSignal(
            at: "2026-08-13T01:30:00Z".codexResetDate!
        ) == nil)
        precondition(rejectedSnapshot.resolvedConfirmedActiveSignal(
            at: "2026-08-13T01:30:00Z".codexResetDate!
        ) == nil)
        precondition(rejectedSnapshot.primaryProbability24h() == 20)
        precondition(rejectedSnapshot.primaryProbability24h(
            at: "2026-08-03T00:30:00Z".codexResetDate!
        ) == 100)

        let scheduledForecastJSON = #"{"mode":"model","updated_at":"2026-08-23T09:09:14.033Z","probabilities":{"rounded_24h":30,"rounded_48h":50,"commitment_floor_percent":null},"confidence":"medium","confidence_note":"Enough history","last_reset_at":"2026-08-13T01:01:37.000Z","official_signal":null}"#.data(using: .utf8)!
        let scheduledFeedJSON = #"{"fetched_at":"2026-08-23T09:11:02.000Z","stale":false,"content_age_days":0.1,"newest_post_at":"2026-08-23T06:39:43.000Z","profile":{"handle":"thsottiaux","name":"Tibo","followers":332050},"signal":null,"tweets":[{"id":"2091412393368945027","url":"https://x.com/thsottiaux/status/2091412393368945027","text":"Reset will land around 14pm PST tomorrow.","at":"2026-08-23T06:29:05.000Z","kind":"signal","replies":232,"likes":1954},{"id":"banked","url":"https://x.com/thsottiaux/status/banked","text":"The banked reset will be there by 8pm PST.","at":"2026-08-21T23:40:34.000Z","kind":"banked","replies":1,"likes":2}]}"#.data(using: .utf8)!
        let scheduledForecast = try JSONDecoder().decode(CodexResetForecast.self, from: scheduledForecastJSON)
        let scheduledFeed = try JSONDecoder().decode(CodexResetFeed.self, from: scheduledFeedJSON)
        let scheduledSnapshot = CodexResetSnapshot(forecast: scheduledForecast, feed: scheduledFeed)
        let beforeReset = "2026-08-23T09:15:00Z".codexResetDate!
        let schedule = scheduledSnapshot.resetSchedule(at: beforeReset)
        precondition(schedule?.expectedAt == "2026-08-23T22:00:00Z".codexResetDate!)
        precondition(schedule?.originalTimeLabel == "2:00 PM PST")
        precondition(schedule?.isApproximate == true)
        precondition(scheduledSnapshot.primaryProbability24h(at: beforeReset) == 100)
        precondition(scheduledSnapshot.primaryProbability48h(at: beforeReset) == 100)
        precondition(scheduledSnapshot.primaryProbability24h(
            at: "2026-08-24T00:00:01Z".codexResetDate!
        ) == 30)

        let observatoryJSON = #"{"schemaVersion":"public-v1","checkedAt":"2026-08-23T09:22:42.467Z","updatedAt":"2026-08-21T23:15:09.000Z","dataHealth":{"overall":"ok","stale":false,"generatedAt":"2026-08-23T09:22:42.467Z","sources":{"supabaseSignals":{"state":"ok"},"openAIStatus":{"state":"ok"}}},"viewModel":{"status":"No resets are currently in progress.","expectation":"Very High","probability24h":0.9,"probability48h":0.96,"lastUpdated":"2026-08-23T09:22:42.467Z","activeWindow":{"active":true,"kind":"official","noticeKind":"forced","label":"Notice available","summary":"An official notice says another reset is planned for Sunday, August 23 at 2:00 PM.","openedAt":"2026-08-23T06:29:05+00:00","expectedAt":"2026-08-23T22:00:00+00:00","expectedEndAt":"2026-08-23T22:00:00+00:00","expectedPrecision":"exact_time","expectedTimeZone":"PST","source":"https://x.com/thsottiaux/status/2091412393368945027","sourceLabel":"Tibo (@thsottiaux)","isOverduePending":false,"overdueText":null},"displayReasoningSummary":"An official reset notice has been confirmed.","recentHistory":[{"key":"banked","recordKind":"banked_distribution","date":"2026-08-22T01:52:00.000Z","resetAt":"2026-08-22T01:52:00.000Z"},{"key":"confirmed","recordKind":"confirmed_global","date":"2026-08-13T03:34:43.341Z","resetAt":"2026-08-13T03:34:43.341Z"}]},"latestTiboActivity":{"classification":"official_notice","text":"Reset will land around 14pm PST tomorrow.","createdAt":"2026-08-23T06:29:05+00:00","sourceUrl":"https://x.com/thsottiaux/status/2091412393368945027","isReply":false}}"#.data(using: .utf8)!
        let observatory = try JSONDecoder().decode(CodexResetObservatoryResponse.self, from: observatoryJSON)
        let observatorySnapshot = try observatory.makeSnapshot()
        let observatoryNow = "2026-08-23T09:30:00Z".codexResetDate!
        precondition(observatorySnapshot.probability24h == 90)
        precondition(observatorySnapshot.probability48h == 96)
        precondition(observatorySnapshot.primaryProbability24h(at: observatoryNow) == 100)
        precondition(observatorySnapshot.primaryProbability48h(at: observatoryNow) == 100)
        precondition(observatorySnapshot.resetSchedule(at: observatoryNow)?.expectedAt == "2026-08-23T22:00:00Z".codexResetDate!)
        precondition(observatorySnapshot.resetSchedule(at: observatoryNow)?.originalTimeLabel == "2:00 PM PST")
        precondition(observatorySnapshot.resetSchedule(at: observatoryNow)?.isApproximate == true)
        precondition(observatorySnapshot.latestTweet?.text == "Reset will land around 14pm PST tomorrow.")
        precondition(observatorySnapshot.forecast.lastResetAt == "2026-08-13T03:34:43.341Z")
        precondition(observatorySnapshot.feed.stale == false)

        let bankedObservatoryJSON = String(data: observatoryJSON, encoding: .utf8)!
            .replacingOccurrences(of: #""noticeKind":"forced""#, with: #""noticeKind":"banked""#)
            .replacingOccurrences(
                of: "Reset will land around 14pm PST tomorrow.",
                with: "The banked reset will be there by 2pm PST."
            )
            .data(using: .utf8)!
        let bankedObservatory = try JSONDecoder().decode(CodexResetObservatoryResponse.self, from: bankedObservatoryJSON)
        let bankedSnapshot = try bankedObservatory.makeSnapshot()
        precondition(bankedSnapshot.forecast.officialSignal == nil)
        precondition(bankedSnapshot.activeSignal == nil)
        precondition(bankedSnapshot.primaryProbability24h(at: observatoryNow) == 90)

        let cachedData = try JSONEncoder().encode(snapshot)
        let cachedSnapshot = try JSONDecoder().decode(CodexResetSnapshot.self, from: cachedData)
        precondition(cachedSnapshot == snapshot)
        print("Codex Reset decoding tests passed")
    }
}
