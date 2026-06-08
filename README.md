# CodexMonitor

[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/) [![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/) [![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE) [![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest) [![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

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
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Real-Time Monitoring** — Track your Codex usage directly from the macOS menu bar
- **Multi-Account Support** — Monitor multiple Codex accounts with easy switching
- **Usage Visualization** — See quota usage with color-coded status indicators
- **Limit Reached Alert** — Visual overlay when 5-hour or weekly limit is reached, with reset countdown
- **Smart Notifications** — Get notified when quota is low or when an account recovers from limit
- **Auto Account Sync** — Automatically detect and add local Codex accounts on launch
- **Multi-Language** — English, 中文, 日本語
- **Update Notifications** — Get notified when a new version is available on GitHub

## Requirements

- macOS 15.0+
- Xcode 16+ (for building from source)
- Swift 6.0+

## Installation

### Homebrew (Recommended)

```bash
brew tap HanryYu/tap
brew install --cask codexmonitor
```

To upgrade:
```bash
brew upgrade --cask codexmonitor
```

### Download DMG

1. Go to [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
2. Download the `CodexMonitor-x.x.x.dmg` file
3. Open the DMG and drag **CodexMonitor** to your **Applications** folder
4. Launch CodexMonitor — it will appear in your menu bar

> **Note:** The app is signed with an Apple Development certificate. On first launch, macOS may show a security warning — right-click the app and select "Open" to bypass it.

### Build from Source

```bash
git clone https://github.com/HanryYu/codex_multi_monitor.git
cd codex_multi_monitor
make install
```

Or manually:

```bash
swift build -c release
cp -f .build/release/CodexMonitor /Applications/CodexMonitor.app/Contents/MacOS/
open /Applications/CodexMonitor.app
```

## Getting Your API Token

### Method 1: Auto Account Management (Recommended)

CodexMonitor can automatically detect and manage your Codex accounts. Simply launch the app — it will scan local auth data, import accounts, and handle token refresh and deduplication automatically.

> If you use [cc-switch](https://github.com/HanryYu/cc-switch) or rotate tokens manually, CodexMonitor will keep accounts in sync without extra steps.

### Method 2: Browser Network Tab

1. Open [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) in your browser and **log in**
2. Open Developer Tools (`⌘⌥I` on Mac) → **Network** tab
3. The page will automatically load usage data — look for a request to `wham/usage`
4. Click the request → **Headers** → copy the `Authorization: Bearer *** value
5. Paste the token (without `Bearer ` prefix) into CodexMonitor

### Method 3: Local Command

If you have [Codex CLI](https://github.com/openai/codex) installed, extract the token locally:

```bash
cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
```

Copy the output and paste it into CodexMonitor.

## Usage

1. Launch **CodexMonitor** from your Applications folder
2. Click the menu bar icon to see your accounts
3. Accounts are auto-detected on launch — or click **+** to add manually
4. The app refreshes data every 30 seconds automatically

## Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | > 50% quota remaining |
| 🟡 Yellow | 20-50% quota remaining |
| 🔴 Red | < 20% quota remaining |

When a limit is reached (5-hour or weekly), the status area shows a "Limit Reached" overlay with the estimated reset time.

## Troubleshooting

**Menu bar icon not showing?**
- Check Activity Monitor — the app may already be running. Force quit and relaunch.

**"No accounts found" on first launch?**
- Make sure you've used Codex locally at least once, or add your token manually via the **+** button.

**DMG won't open / "unidentified developer"?**
- Right-click → Open, or go to System Settings → Privacy & Security → Allow Anyway.

## License

[GPLv3](LICENSE) — © 2025 Henry Yu