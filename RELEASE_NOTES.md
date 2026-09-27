# CodexMonitor 0.7.12

This release stops recurring Claude Keychain password prompts during background quota refreshes.

## Claude credential reliability

- Reads and updates local Claude credentials without opening macOS authentication dialogs.
- Caches credential discovery, delays failed attempts, and shares concurrent credential refreshes.
- Retains rotated credentials in memory when write-back fails, with delayed persistence retries instead of repeatedly refreshing stale credentials.
- Preserves saved account tokens when local credentials are temporarily unavailable.
- Clarifies manual token entry when local credentials cannot be accessed silently.

## Refresh behavior

- Coalesces overlapping timer, wake, and manual refreshes into one shared refresh cycle.
- Skips legacy Keychain migration for accounts already stored locally.
- Adds regression coverage for credential caching, concurrent refreshes, retry delays, and failed write-back recovery.
- Resolves SwiftPM build output paths dynamically when packaging universal DMGs.
