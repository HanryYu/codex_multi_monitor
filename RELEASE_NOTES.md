# CodexMonitor 0.7.13

This release handles Claude usage endpoint rate limits without repeatedly requesting unavailable data or treating query throttling as exhausted account quota.

## Claude usage reliability

- Shares concurrent requests for the same credential and caches successful usage for five minutes.
- Honors Retry-After on HTTP 429, with a minimum 15-minute cooldown and exponential backoff for repeated limits.
- Persists cooldowns across app restarts without storing access tokens.
- Keeps usage snapshots up to 30 minutes old visible during temporary failures, clearly showing when the data was fetched and when requests can resume.
- Shows the retry time when no recent snapshot is available, and clears cached usage when credentials are rejected.
- Excludes stale snapshots from new quota notifications and allowance estimates.

## Validation

- Adds regression coverage for request coalescing, credential isolation, Retry-After parsing, backoff, cache expiry, authentication rejection, and cooldown persistence.
