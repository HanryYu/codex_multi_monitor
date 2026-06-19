# Codex Monitor iOS

This folder contains the iOS companion app and Widget extension for Codex Monitor.

## Open

```bash
cd iOS
xcodegen generate
open CodexMonitoriOS.xcodeproj
```

Use the `CodexMonitoriOS` scheme for the app. The app supports iOS 16 and newer.

## Sync Contract

- macOS publishes the added account snapshot to iCloud Key-Value Store.
- iOS reads the synced account snapshot and refreshes usage with the existing usage API.
- Widget settings and cached widget snapshots are shared through `group.com.henry.codex-monitor`.
- Account management remains on macOS; iOS does not add or delete accounts.

## Signing

The app and widget use:

- App Group: `group.com.henry.codex-monitor`
- iCloud KVS identifier: `$(TeamIdentifierPrefix)com.henry.codex-monitor`

Configure the same Apple Developer Team for both targets before installing on a device.
