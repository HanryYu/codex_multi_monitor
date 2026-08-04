# CodexMonitor 0.7.7

This release adds a community-powered Codex reset forecast to the menu bar, improves long reset countdowns, and introduces a reusable release workflow.

## Codex Reset Radar

- Shows the estimated chance of a community-wide Codex reset in the next 24 hours.
- Displays the latest public Tibo signal in an X-style detail card with status-specific presentation.
- Opens details only after an explicit click, so moving into the account list never triggers the card accidentally.
- Uses a compact, screen-aware pointer that follows the detail card when it moves to either side of the menu.
- Preloads and caches Tibo's avatar locally instead of downloading it on every open.
- Preserves the last successful forecast when the independent community API is temporarily unavailable.

## Attribution and transparency

- Adds localized acknowledgements and direct API references for Codex Reset in Settings → About.
- Clearly identifies the forecast as independent community data that is not affiliated with OpenAI.

## Reset-time readability

- Formats longer countdowns with days, hours, and minutes, such as `1d 2h 5m`.
- Keeps short countdowns compact while avoiding very large hour-only values.

## Release workflow

- Adds a one-command release path with preflight checks, signed artifact validation, GitHub Actions monitoring, and Homebrew cask synchronization.
