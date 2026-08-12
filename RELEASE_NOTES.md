# CodexMonitor 0.7.8

This release refines Codex Reset Radar with a clearer menu-bar presentation, a dedicated detail panel, and more reliable data refresh behavior.

## Radar experience

- Presents Codex Reset Radar as a compact card above account quotas with a dedicated radar icon.
- Opens the X-style feed in a separate floating detail panel by click or a delayed hover.
- Shows the post timestamp alongside Tibo's account information and adapts status presentation to the feed state.
- Adds a localized Settings option to show or hide the Radar.

## Refresh reliability

- Restores cached Radar data immediately at launch instead of waiting for the network.
- Refreshes automatically only when the menu opens and cached data is old enough, avoiding frequent background requests.
- Adds a refresh button inside the detail panel that explicitly requests the latest forecast and feed.
- Shows a visible refreshing state, prevents duplicate requests, and keeps the last successful data if a refresh fails.

## Assets and attribution

- Preloads and caches Tibo's avatar to avoid repeated downloads.
- Includes the Lucide radar icon and its license in the distributed app bundle.
