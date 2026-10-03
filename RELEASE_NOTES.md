# CodexMonitor 0.7.14

Claude limit-reset credits now appear alongside quota usage, with the same compact card and wording as Codex.

## Reset credits

- Show the number of available Claude resets, their expiration date, reset scope, and any requirement to reach a limit before use.
- Use one detail template for Codex and Claude: expiration first, followed by available grant details. Avoid repeating a single reset count or showing missing-date placeholders beside known details.
- Open Claude's official usage page from the expanded card; the app does not consume reset credits.
- Ignore expired, paused, future, duplicate, or malformed grants, and distinguish unavailable data from zero credits.
- Read grants in the existing Claude usage request and preserve request coalescing, caching, rate-limit backoff, and non-interactive credential access from v0.7.13.

## Validation

- Regression coverage for grant decoding, request metadata, cached grant expiration, malformed data, and existing Claude usage recovery and backoff behavior.
- Release checks include the new reset-credit decoder tests alongside existing account, quota, and provider tests.
