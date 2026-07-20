# CodexMonitor 0.7.4

This patch restores user control over automatic weekly quota activation while keeping the new reliable scheduling behavior.

## User-controlled automatic activation

- Restores the Settings toggle for automatic weekly quota activation.
- Runs the hourly fallback check only while the user has enabled the feature.
- Performs an immediate check when enabled and a catch-up check after the Mac wakes.
- Persists a per-account next-check time seven days after every successful activation.
- Sends automatic requests only while the weekly quota is 100% remaining.

## Manual refresh

- Adds a Settings action that refreshes all saved Codex accounts currently showing 100% weekly quota remaining.
- Runs eligible accounts concurrently and reports full success, partial failure, or no eligible accounts.
- Remains available independently of the automatic activation toggle.
