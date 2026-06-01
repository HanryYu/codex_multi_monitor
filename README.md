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
- [Update Notifications](#update-notifications)
- [Automation & CI/CD](#automation--cicd)
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

### Download DMG (Recommended)

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

1. Visit [chatgpt.com/codex](https://chatgpt.com/codex)
2. Log in with your ChatGPT account
3. Open Developer Tools → **Network** tab
4. Look for API requests to `ab.chatgpt.com` or `chatgpt.com`
5. Find the **Authorization** header — it contains a UUID token (e.g., `3f8c2b1a-...`)
6. Copy this token

> **Tip:** If you've already used Codex locally, the app can auto-detect your account on first launch.

## Usage

1. Launch **CodexMonitor** from your Applications folder
2. Click the menu bar icon to see your accounts
3. Click **+** to add an account, paste your API token
4. The app refreshes data every 30 seconds automatically

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ + N` | Add new account |
| `⌘ + ,` | Open Preferences |
| `⌘ + Q` | Quit |

### Account Token Detection

On first launch, the app will search for existing Codex accounts in `~/Library/Application Support/codex/` and prompt you to import them — no manual token copying needed.

## Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | > 50% quota remaining |
| 🟡 Yellow | 20-50% quota remaining |
| 🔴 Red | < 20% quota remaining |

When a limit is reached (5-hour or weekly), the status area shows a "Limit Reached" overlay with the estimated reset time.

## Update Notifications

CodexMonitor checks for new versions on GitHub Releases automatically. When a new version is available, you'll see a notification in the menu bar and can open the release page directly.

## Automation & CI/CD

CodexMonitor is designed to work seamlessly with OpenAI's Codex GitHub bot for automated code reviews and PR management.

### How It Works

1. **Codex Bot** runs on GitHub via `codex.yaml` workflow
2. **CodexMonitor** tracks API usage and quota across all your accounts
3. When one account hits its limit, switch to another account to keep Codex running

### Setup for Your Repo

Add this to `.github/workflows/codex.yaml` in your repository:

```yaml
name: Codex

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  codex:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '/codex')) ||
      (github.event_name == 'pull_request')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: openai/codex-action@v1
        with:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

## Troubleshooting

**Menu bar icon not showing?**
- Check Activity Monitor — the app may already be running. Force quit and relaunch.

**"No accounts found" on first launch?**
- Make sure you've used Codex locally at least once, or add your token manually via the **+** button.

**DMG won't open / "unidentified developer"?**
- Right-click → Open, or go to System Settings → Privacy & Security → Allow Anyway.

## License

[GPLv3](LICENSE) — © 2025 Henry Yu
