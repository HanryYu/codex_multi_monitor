# CodexMonitor 0.7.1

This release adds scheduled Codex quota activation and refines the multi-provider menu bar experience.

## Scheduled 5-hour quota refresh (Beta)

- Starts a fresh 5-hour Codex quota window at a user-selected daily time.
- Uses the minimal prompt `Reply only: hi` with reasoning fixed to Low.
- Supports per-account enablement and schedules in Advanced Settings.
- Loads the current model list through Codex App Server, with Codex's last synced model catalog as a fallback.
- Prefers the lightweight Mini model by default when available.
- Requires automatic Mac wake so refresh requests can run while the computer would otherwise be asleep.
- Uses isolated per-account Codex authentication and persistent daily deduplication.

## Interface improvements

- Groups the 5-hour refresh and weekly quota cycle controls into a clearly labeled Beta section.
- Adds concise localized explanations in English, Japanese, Simplified Chinese, and Traditional Chinese.
- Displays Codex, Claude, and Grok provider icons with consistent circular crops.
- Simplifies menu bar card hierarchy by removing redundant shadows, dividers, and nested borders while preserving the existing colors.
- Adds a cumulative GitHub Release download-count badge to all README variants.

## Reliability

- Adds a grace period after wake so scheduled requests are not missed during system resume.
- Prevents the refresh feature from remaining enabled when automatic wake cannot be configured.
- Avoids overwriting an existing repeating macOS power schedule.
