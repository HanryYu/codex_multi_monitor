import Foundation

@main
enum ClaudeResetCreditsTests {
    static func main() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!

        let oneGrant = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"grant_a","resets_left":1,"resets_total":3,
           "starts_at":"2026-10-03T11:00:00Z","ends_at":"2026-10-04T12:00:00Z",
           "clears":["five_hour","future_window"],"paused":false,
           "usable_now":true,"use_requires_limit":false}
        ],"next_grant_id":null,"cooldown_until":null}}
        """#, now: now)
        precondition(oneGrant?.availableCount == 1)
        precondition(oneGrant?.credits.count == 1)
        precondition(oneGrant?.credits[0].id == "grant_a")
        precondition(oneGrant?.credits[0].resetType == "five_hour,future_window")
        precondition(oneGrant?.credits[0].grantedAt == nil)
        precondition(oneGrant?.credits[0].remainingCount == 1)
        precondition(oneGrant?.credits[0].requiresLimit == false)

        let multipleGrants = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"grant_a","resets_left":2,"resets_total":4,"starts_at":null,"ends_at":null,
           "clears":["five_hour"],"paused":false,"usable_now":true,"use_requires_limit":false},
          {"id":"grant_b","resets_left":3,"resets_total":3,"starts_at":null,"ends_at":null,
           "clears":["weekly"],"paused":false,"usable_now":false,"use_requires_limit":true},
          {"id":"grant_a","resets_left":99,"resets_total":99,"starts_at":null,"ends_at":null,
           "clears":["duplicate"],"paused":false,"usable_now":true,"use_requires_limit":false}
        ]}}
        """#, now: now)
        precondition(multipleGrants?.availableCount == 5, "Sum each unique grant's remaining uses")
        precondition(multipleGrants?.credits.count == 2, "Keep one display item per grant, not per reset")
        precondition(multipleGrants?.credits[1].remainingCount == 3)
        precondition(multipleGrants?.credits[1].requiresLimit == true,
                     "A limit-gated grant remains visible when unusable now")

        let filtered = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"expired","resets_left":2,"resets_total":2,"starts_at":null,"ends_at":"2026-10-03T12:00:00Z","clears":[],"paused":false,"usable_now":false,"use_requires_limit":false},
          {"id":"future","resets_left":2,"resets_total":2,"starts_at":"2026-10-03T12:00:01Z","ends_at":null,"clears":[],"paused":false,"usable_now":false,"use_requires_limit":false},
          {"id":"paused","resets_left":2,"resets_total":2,"starts_at":null,"ends_at":null,"clears":[],"paused":true,"usable_now":false,"use_requires_limit":false},
          {"id":"used","resets_left":0,"resets_total":2,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":false,"use_requires_limit":false},
          {"id":"held","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":false,"use_requires_limit":true}
        ]}}
        """#, now: now)
        precondition(filtered?.availableCount == 1)
        precondition(filtered?.credits.first?.id == "held")

        let explicitNoGrant = try decode(#"{"cedar_ember":{"eligible":false,"ineligible_reason":"no_grant"}}"#, now: now)
        precondition(explicitNoGrant?.availableCount == 0 && explicitNoGrant?.credits.isEmpty == true)
        let explicitlyEmpty = try decode(#"{"cedar_ember":{"eligible":false,"grants":[]}}"#, now: now)
        precondition(explicitlyEmpty?.availableCount == 0 && explicitlyEmpty?.credits.isEmpty == true)
        let noGrants = try decode(#"{"cedar_ember":{"eligible":true,"grants":[]}}"#, now: now)
        precondition(noGrants?.availableCount == 0 && noGrants?.credits.isEmpty == true)

        for unknown in [
            #"{}"#,
            #"{"cedar_ember":null}"#,
            #"{"cedar_ember":{"eligible":"yes","grants":[]}}"#,
            #"{"cedar_ember":{"eligible":true}}"#,
            #"{"cedar_ember":{"eligible":true,"grants":[{"id":"x"}]}}"#,
            #"{"cedar_ember":{"eligible":false,"ineligible_reason":"surface","grants":[]}}"#,
            #"{"cedar_ember":{"eligible":false,"ineligible_reason":"cli_version"}}"#,
            #"{"cedar_ember":{"eligible":false,"ineligible_reason":"unavailable"}}"#
        ] {
            let result = try decode(unknown, now: now)
            precondition(result == nil, "Malformed or absent grant data is unknown")
        }

        let invalidGrantOnly = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"bad_date","resets_left":1,"resets_total":1,"starts_at":null,
           "ends_at":"not-a-date","clears":[],"paused":false,"usable_now":true,"use_requires_limit":false}
        ]}}
        """#, now: now)
        precondition(invalidGrantOnly == nil, "An invalid non-null expiry is unknown, not no expiry")

        let mixedMalformed = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"good","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":true,"use_requires_limit":false},
          {"id":"bad_count","resets_left":-1,"resets_total":2,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":true,"use_requires_limit":false},
          {"id":"bad_total","resets_left":3,"resets_total":2,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":true,"use_requires_limit":false},
          {"id":"bad_fraction","resets_left":1.5,"resets_total":2,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":true,"use_requires_limit":false},
          {"id":"bad_bool","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,"clears":[],"paused":0,"usable_now":true,"use_requires_limit":false},
          {"id":"bad_id!","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,"clears":[],"paused":false,"usable_now":true,"use_requires_limit":false}
        ]}}
        """#, now: now)
        precondition(mixedMalformed?.availableCount == 1)
        precondition(mixedMalformed?.credits.count == 1)

        let defaultedFlags = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"defaults","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,"clears":[]}
        ]}}
        """#, now: now)
        precondition(defaultedFlags?.availableCount == 1)
        precondition(defaultedFlags?.credits.first?.requiresLimit == true,
                     "Official defaults retain the grant as limit-gated")

        let invalidOptionalFlag = try decode(#"""
        {"cedar_ember":{"eligible":true,"grants":[
          {"id":"bad_flag","resets_left":1,"resets_total":1,"starts_at":null,"ends_at":null,
           "clears":[],"paused":false,"usable_now":"false","use_requires_limit":true}
        ]}}
        """#, now: now)
        precondition(invalidOptionalFlag == nil, "Malformed optional booleans must not be defaulted")

        let codexPayload = Data(#"""
        {"available_count":2,"credits":[
          {"id":"codex_1","reset_type":"five_hour","status":"available",
           "granted_at":"2026-10-01T10:00:00Z","expires_at":"2026-11-01T10:00:00Z","redeemed_at":null}
        ]}
        """#.utf8)
        let codexDecoded = try JSONDecoder().decode(RateLimitResetCredits.self, from: codexPayload)
        precondition(codexDecoded.availableCount == 2 && codexDecoded.credits.count == 1)
        precondition(codexDecoded.credits[0].remainingCount == nil)
        precondition(codexDecoded.credits[0].requiresLimit == nil)

        print("Claude reset-credit tests passed: eligibility, grant counts, dates, filtering, limit-gated grants, and Codex compatibility")
    }

    private static func decode(_ json: String, now: Date) throws -> RateLimitResetCredits? {
        ClaudeResetCreditsDecoder.decode(Data(json.utf8), now: now)
    }
}
