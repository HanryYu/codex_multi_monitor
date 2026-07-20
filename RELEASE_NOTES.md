# CodexMonitor 0.7.3

This release makes weekly quota activation self-maintaining and adds a manual action for refreshing every fully recovered Codex account.

## Reliable automatic weekly activation

- Weekly activation is always enabled and can no longer be accidentally turned off.
- Adds an independent hourly fallback check, including a catch-up check after the Mac wakes.
- Persists a per-account next-check time seven days after every successful activation.
- Combines the seven-day schedule with usage returning to `0%`, reset-time changes, and the official missing-weekly-window reset shape.
- Sends an activation request only while the weekly quota is fully available, so a due schedule never consumes partially used quota.

## Manual refresh

- Adds a Settings action that refreshes all saved Codex accounts currently showing 100% weekly quota remaining.
- Runs eligible accounts concurrently and reports full success, partial failure, or no eligible accounts.
- Uses each saved account's complete captured auth bundle instead of relying on the currently signed-in account.

## Quota UI

- Keeps banked reset-credit controls interactive when the quota-limit overlay is visible.
- Preserves the existing menu and account-card appearance while limiting the exhausted-state treatment to quota content.
