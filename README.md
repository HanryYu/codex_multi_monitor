# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/)[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/)[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE)[![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

A macOS menu bar app that monitors your ChatGPT Codex usage in real-time.

<p align="center">
  <img src="https://raw.githubusercontent.com/HanryYu/codex_multi_monitor/main/assets/codexmonitor-screenshot.png" alt="CodexMonitor Screenshot" width="420">
</p>

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Your API Token](#getting-your-api-token)
- [Usage](#usage)
- [Status Colors](#status-colors)
- [Automation & CI/CD](#automation--cicd)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- 🎯 **Menu Bar App** — Lives in your macOS menu bar, no Dock icon
- 📊 **Real-time Monitoring** — Track rate limits for 5-hour and weekly windows
- 🔐 **Secure Storage** — AES-256 encrypted local token storage
- 🔄 **Auto-refresh** — Configurable refresh interval (1–60 min, default 5 min)
- 🎨 **Status Indicator** — Color-coded icon (green/yellow/red) based on usage
- 👥 **Multi-account** — Monitor multiple ChatGPT accounts simultaneously
- ⚙️ **Unified Settings** — Single settings window with tabbed interface
- 📐 **Display Modes** — Show remaining or used percentage
- ⏱️ **Reset Time Format** — Relative ("in 3h 20m") or absolute ("15:06")
- 🔔 **Smart Notifications** — Usage alerts when threshold exceeded, recovery alerts when limits reset
- 🌐 **Multi-language** — English, 简体中文, 繁體中文, 日本語

## Requirements

- macOS 15.0 (Sequoia) or later
- Swift 6.0+
- ChatGPT Plus / Pro / Enterprise subscription

## Installation

### Download DMG (Recommended)

1. Go to [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
2. Download the `.dmg` file
3. Open and drag **CodexMonitor** to Applications

### Build from Source

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
swift build -c release
```

The binary will be at `.build/release/CodexMonitor`.

## Getting Your API Token

### Method 1: Codex CLI Auth File (Recommended)

If you have the [Codex CLI](https://github.com/openai/codex) installed, the token is stored locally:

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

Copy the output and paste it into CodexMonitor.

### Method 2: Browser Network Tab

1. Open [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) in your browser and **log in**
2. Open Developer Tools (`⌘⌥I` on Mac) → **Network** tab
3. The page will automatically load usage data — look for a request to `wham/usage`
4. Click the request → **Headers** → copy the `Authorization: Bearer ` value
5. Paste the token (without `Bearer ` prefix) into CodexMonitor

## Usage

1. **Launch** — The app appears as a gauge icon in your menu bar
2. **Click** — Opens the monitoring panel showing all accounts
3. **Add Account** — Click "+" (or open Settings) and paste your token
4. **Monitor** — View real-time usage statistics per account

### Settings

Open via the gear icon:

- **Accounts** — Add, edit, remove, or reorder accounts (drag to reorder)
- **Preferences** — Display mode, reset time format, refresh interval, launch at login, notifications

## Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | Healthy usage (< 60%) |
| 🟡 Yellow | Approaching limit (60–80%) |
| 🔴 Red | At or near limit (> 80%) |

## Automation & CI/CD

The project uses GitHub Actions for automated release builds:

- **Release workflow** triggers on version tag push (`v*`)
- Builds a release binary with `swift build -c release`
- Code signs with Developer ID (via GitHub Secrets)
- Creates a DMG installer
- Publishes a GitHub Release with the DMG attached

To create a new release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will automatically build, sign, and publish the release.

## Troubleshooting

**"Unauthorized" Error**
- Token may have expired — get a fresh token using the console one-liner above

**No Data Showing**
- Check your internet connection
- Verify the token is valid
- Click the refresh button in the popover

**App Not Appearing**
- Check if it's running: `ps aux | grep CodexMonitor`
- Look for the gauge icon in your menu bar
- The app doesn't show in Dock (by design)

## License

[GPLv3](LICENSE)
