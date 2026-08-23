# CodexMonitor 0.7.9

This release adds authoritative OpenCode Go quota monitoring and rebuilds Codex Reset Radar around a more structured community data source.

## OpenCode Go monitoring

- Adds OpenCode Go as a provider with dedicated account setup, iconography, encrypted session-cookie storage, and optional Workspace ID override.
- Reads authoritative 5-hour, weekly, and monthly quota windows from the signed-in `opencode.ai` dashboard instead of estimating from local usage.
- Shows a compact three-window quota panel and keeps only a recent, clearly labeled cached dashboard result when a refresh fails.

## Reset Radar accuracy

- Replaces the previous forecast/feed source with the public Codex Reset Observatory `public-v1` API.
- Treats confirmed forced-reset notices separately from Banked Reset and regular weekly events.
- Shows **Next Reset Confirmed**, `100%`, and the next reset using the Relative or Absolute time preference when an exact future reset is available.
- Selects the latest confirmed global reset without confusing it with a newer Banked Reset distribution.

## Radar design and reliability

- Uses semantic system colors: blue for a confirmed future reset, green for a completed reset, orange for delayed data, and red for refresh failure.
- Prevents the compact confirmed-reset title and the Tibo handle/timestamp row from wrapping despite available horizontal space.
- Keeps the menu card compact while moving the full signal, local/source times, data-health warnings, refresh action, and source links into the detail panel.
- Invalidates cache entries from the previous provider and validates Observatory schema, probability, forced-reset, Banked Reset, and timing behavior with focused tests.
- Selects app updates by semantic version instead of GitHub publication order, while the release workflow explicitly marks the new version as Latest.

Codex Reset Observatory is an independent community project and is not affiliated with OpenAI.
