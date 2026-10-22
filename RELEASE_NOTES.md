# CodexMonitor 0.7.15

Add per-account quota rings to the menu bar and support Claude web Cookies alongside OAuth tokens.

## Menu bar quota rings

- Choose which accounts appear in the menu bar, with a separate ring for each selected account.
- Select the 5-hour or weekly quota independently for each account; use the 5-hour window when weekly usage is unavailable.
- Show used or remaining percentages, place numbers inside or beside the ring, or hide them.
- Choose white monochrome rings or fixed green, orange, and red colors based on remaining quota.
- Clicking a ring opens and scrolls to its account, including when reopening the same account.

## Claude Cookie support

- Detect Cookie and OAuth credentials and send each to its corresponding usage endpoint.
- Accept complete browser Cookie headers, sessionKey values, OAuth Bearer tokens, and local auth JSON.
- Handle browser Cookie values containing JSON, quotes, commas, and other valid characters.
- Select organizations per account and preserve that choice in backups and cloud sync. Ambiguous sessions require a selection instead of displaying an arbitrary organization's usage.
- Keep Cookie credentials separate from local CLI imports, OAuth refresh, and other organizations' caches. Distinguish expired sessions, website access blocks, rate limits, and missing usage.

## Provider reliability

- Support OpenCode Go API keys and migrated Console sessions, with server-reported quota windows and workspace-specific cache handling.
- Improve Grok billing and gRPC-Web decoding, bound transient retries, and prevent web sessions from being replaced with another local CLI account.
- Keep account form actions accessible when optional organization or workspace fields are shown.

## Validation

- Regression coverage for credential parsing, request routing, organization and workspace selection, cache isolation, rate-limit persistence, malformed responses, and account serialization.
- Native quota-ring and account-scroll tests, plus universal Apple Silicon and Intel builds.
- Provider requests were tested with synthetic credentials and mocked responses; authenticated live quota retrieval was not verified for this release.
