# CodexMonitor 0.7.2

This release makes weekly Codex quota activation reliable across every saved account and keeps reset controls usable when a quota is exhausted.

## Smarter weekly quota activation

- Activates every saved Codex account that has a complete captured auth bundle, rather than relying on the currently signed-in account.
- Detects normal weekly reset-time changes and usage returning from a nonzero value to `0%`.
- Detects the newer API behavior where `secondary_window` disappears after an official weekly reset instead of returning `used_percent: 0`.
- Reuses previously captured per-account auth bundles even when automatic import is later disabled.
- Refreshes all account usage shortly after successful activation so the menu reflects the latest server state.

## Reliability

- Records a weekly reset as handled only after the isolated Codex request succeeds.
- Retries failed activations and prevents duplicate requests for the same account while one is already running.
- Migrates away from stale activation state written by older versions before a request had actually completed.
- Avoids sending a second activation request when the weekly window returns with its new reset time.

## Menu bar

- Keeps banked reset-credit controls interactive when the quota-limit overlay is visible.
- Preserves the existing menu and account-card appearance while limiting the visual treatment to the exhausted quota area.
