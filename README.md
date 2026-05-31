     1|# CodexMonitor
     2|
     3|[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple)](https://www.apple.com/macos/)[![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org/)[![License](https://img.shields.io/badge/License-GPLv3-green.svg)](LICENSE)[![Release](https://img.shields.io/github/v/release/HanryYu/codex_multi_monitor)](https://github.com/HanryYu/codex_multi_monitor/releases/latest)[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%2F%20Intel-lightgrey)](https://github.com/HanryYu/codex_multi_monitor)

<div align="right">

[English](README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

</div>
     4|
     5|A macOS menu bar app that monitors your ChatGPT Codex usage in real-time.
     6|
     7|<p align="center">
     8|  <img src="https://raw.githubusercontent.com/HanryYu/codex_multi_monitor/main/assets/codexmonitor-screenshot.png" alt="CodexMonitor Screenshot" width="420">
     9|</p>
    10|
    11|---
    12|
    13|## Table of Contents
    14|
    15|- [Features](#features)
    16|- [Requirements](#requirements)
    17|- [Installation](#installation)
    18|- [Getting Your API Token](#getting-your-api-token)
    19|- [Usage](#usage)
    20|- [Status Colors](#status-colors)
    21|- [Automation & CI/CD](#automation--cicd)
    22|- [Troubleshooting](#troubleshooting)
    23|- [License](#license)
    24|
    25|---
    26|
    27|## Features
    28|
    29|- 🎯 **Menu Bar App** — Lives in your macOS menu bar, no Dock icon
    30|- 📊 **Real-time Monitoring** — Track rate limits for 5-hour and weekly windows
    31|- 🔐 **Secure Storage** — AES-256 encrypted local token storage
    32|- 🔄 **Auto-refresh** — Configurable refresh interval (1–60 min, default 5 min)
    33|- 🎨 **Status Indicator** — Color-coded icon (green/yellow/red) based on usage
    34|- 👥 **Multi-account** — Monitor multiple ChatGPT accounts simultaneously
    35|- 🤖 **Auto Account Sync** — Automatically detects and imports accounts from `~/.codex/auth.json` — works with [cc-switch](https://github.com/HanryYu/cc-switch) or manual token rotation
    36|- ⚙️ **Unified Settings** — Single settings window with tabbed interface
    37|- 📐 **Display Modes** — Show remaining or used percentage
    38|- ⏱️ **Reset Time Format** — Relative ("in 3h 20m") or absolute ("15:06")
    39|- 🔔 **Smart Notifications** — Usage alerts when threshold exceeded, recovery alerts when limits reset
    40|- 🌐 **Multi-language** — English, 简体中文, 繁體中文, 日本語
    41|
    42|## Requirements
    43|
    44|- macOS 15.0 (Sequoia) or later
    45|- Swift 6.0+
    46|- ChatGPT Plus / Pro / Enterprise subscription
    47|
    48|## Installation
    49|
    50|### Download DMG (Recommended)
    51|
    52|1. Go to [Releases](https://github.com/HanryYu/codex_multi_monitor/releases/latest)
    53|2. Download the `.dmg` file
    54|3. Open and drag **CodexMonitor** to Applications
    55|
    56|### Build from Source
    57|
    58|```bash
    59|git clone https://github.com/HanryYu/codex_multi_monitor.git
    60|cd codex_multi_monitor
    61|swift build -c release
    62|```
    63|
    64|The binary will be at `.build/release/CodexMonitor`.
    65|
    66|## Getting Your API Token
    67|
    68|### Method 1: Codex CLI Auth File (Recommended)
    69|
    70|If you have the [Codex CLI](https://github.com/openai/codex) installed, the token is stored locally:
    71|
    72|```bash
    73|cat ~/.codex/auth.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tokens']['access_token'])"
    74|```
    75|
    76|Copy the output and paste it into CodexMonitor.
    77|
    78|### Method 2: Browser Network Tab
    79|
    80|1. Open [chatgpt.com/codex/cloud/settings/analytics](https://chatgpt.com/codex/cloud/settings/analytics) in your browser and **log in**
    81|2. Open Developer Tools (`⌘⌥I` on Mac) → **Network** tab
    82|3. The page will automatically load usage data — look for a request to `wham/usage`
    83|4. Click the request → **Headers** → copy the `Authorization: Bearer *** value
    84|5. Paste the token (without `Bearer ` prefix) into CodexMonitor
    85|
    86|## Usage
    87|
    88|1. **Launch** — The app appears as a gauge icon in your menu bar
    89|2. **Click** — Opens the monitoring panel showing all accounts
    90|3. **Add Account** — Click "+" (or open Settings) and paste your token
    91|4. **Monitor** — View real-time usage statistics per account
    92|
    93|### Settings
    94|
    95|Open via the gear icon:
    96|
    97|- **Accounts** — Add, edit, remove, or reorder accounts (drag to reorder)
    98|- **Preferences** — Display mode, reset time format, refresh interval, launch at login, notifications
    99|
   100|## Status Colors
   101|
   102|| Color | Meaning |
   103||-------|---------|
   104|| 🟢 Green | Healthy usage (< 60%) |
   105|| 🟡 Yellow | Approaching limit (60–80%) |
   106|| 🔴 Red | At or near limit (> 80%) |
   107|
   108|## Automation & CI/CD
   109|
   110|The project uses GitHub Actions for automated release builds:
   111|
   112|- **Release workflow** triggers on version tag push (`v*`)
   113|- Builds a release binary with `swift build -c release`
   114|- Code signs with Developer ID (via GitHub Secrets)
   115|- Creates a DMG installer
   116|- Publishes a GitHub Release with the DMG attached
   117|
   118|To create a new release:
   119|
   120|```bash
   121|git tag v1.0.0
   122|git push origin v1.0.0
   123|```
   124|
   125|The workflow will automatically build, sign, and publish the release.
   126|
   127|## Troubleshooting
   128|
   129|**"Unauthorized" Error**
   130|- Token may have expired — get a fresh token using the console one-liner above
   131|
   132|**No Data Showing**
   133|- Check your internet connection
   134|- Verify the token is valid
   135|- Click the refresh button in the popover
   136|
   137|**App Not Appearing**
   138|- Check if it's running: `ps aux | grep CodexMonitor`
   139|- Look for the gauge icon in your menu bar
   140|- The app doesn't show in Dock (by design)
   141|
   142|## License
   143|
   144|[GPLv3](LICENSE)
   145|