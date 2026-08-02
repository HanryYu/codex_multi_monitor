# CodexMonitor 0.7.6

This release makes Codex plan tiers easier to understand and adds a per-account fallback for starting a weekly quota cycle when the displayed percentage is inaccurate.

## Clearer Codex plan names

- Displays the Codex Pro Lite tier as **Pro 5x**.
- Displays the Codex Pro tier as **Pro 20x**.
- Keeps the original API plan value unchanged outside the UI.

## Per-account weekly quota refresh

- Adds a manual refresh action to each Codex account in Settings → Accounts.
- Lets the selected account send one short activation request without requiring the displayed weekly quota to be exactly 100% remaining.
- Shows in-progress, success, and failure feedback directly in the account row.
- Keeps the action hidden for non-Codex providers and reports when a Codex account has no complete saved credentials.

## Safer activation scheduling

- Prevents weekly and scheduled 5-hour refreshes from running concurrently for the same account.
- Preserves existing schedules when a forced request fails.
- Uses the server-provided weekly reset time when available, with a conservative seven-day fallback for missing or stale cycle data.
- Prevents an immediate duplicate request after a successful manual refresh while allowing the next seven-day cycle to run normally.
