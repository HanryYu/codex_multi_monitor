# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/HanryYu/codex_multi_monitor/total)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)

A macOS menu bar app that monitors your ChatGPT Codex usage in real-time.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Your API Token](#getting-your-api-token)
- [Usage](#usage)
- [Status Colors](#status-colors)
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

1. Open [chatgpt.com](https://chatgpt.com) in your browser and **log in**
2. Open Developer Tools Console:
   - **Chrome**: `⌘⌥J`
   - **Firefox**: `⌘⌥K`
   - **Safari**: `⌘⌥C` (enable Developer menu first in Safari → Settings → Advanced)
3. Paste this and press **Enter**:

```javascript
fetch('https://chatgpt.com/api/auth/session').then(r=>r.json()).then(d=>{if(d.accessToken){copy(d.accessToken);alert('✅ Token copied!')}else{alert('❌ Not found. Make sure you are logged in.')}})
```

4. The token is now in your clipboard — paste it into CodexMonitor

> **Note:** This must be run on `chatgpt.com` (same-origin). The token is the same one the web app uses for API requests.

## Usage

1. **Launch** — The app appears as a gauge icon in your menu bar
2. **Click** — Opens the monitoring panel showing all accounts
3. **Add Account** — Click "+" (or open Settings) and paste your token
4. **Monitor** — View real-time usage statistics per account

### Settings

Open via the gear icon:

- **Accounts** — Add, edit, remove, or reorder accounts (drag to reorder)
- **Preferences** — Display mode, reset time format, refresh interval, launch at login

## Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | Healthy usage (< 60%) |
| 🟡 Yellow | Approaching limit (60–80%) |
| 🔴 Red | At or near limit (> 80%) |

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

[MIT](LICENSE)
