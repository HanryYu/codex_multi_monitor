# CodexMonitor

A macOS menu bar application that monitors your ChatGPT Codex usage in real-time.

## Features

- 🎯 **Menu Bar App** - Lives in your macOS menu bar, no Dock icon
- 📊 **Real-time Monitoring** - Track rate limits for 5-hour and weekly windows
- 🔐 **Secure Token Storage** - AES-256 encrypted local storage — no system password prompts
- 🔄 **Auto-refresh** - Configurable refresh interval (1–60 min, default 5 min)
- 🎨 **Status Indicator** - Color-coded icon (green/yellow/red) based on usage
- 👥 **Multi-account Support** - Monitor multiple ChatGPT accounts simultaneously
- ⚙️ **Unified Settings** - Single settings window with tabbed interface (Accounts + Preferences)
- 📐 **Display Modes** - Show remaining percentage or used percentage
- ⏱️ **Reset Time Format** - Display reset time as relative ("in 3h 20m") or absolute ("15:06")

## Screenshots

The app displays usage information like:

```
【Work Account】 Plus
⏱ 5 hours: Used 25% · Remaining 75% · Resets 15:06
📅 Weekly:  Used 9%  · Remaining 91% · Resets Sunday 03:08
```

## Requirements

- macOS 15.0 (Sequoia) or later
- Swift 6.0+ / Swift Tools 6.0
- ChatGPT Plus/Pro/Enterprise subscription

## Installation

### Option 1: Build from Source

1. **Clone or download** this repository

2. **Build the project**:
   ```bash
   cd codex_multi_monitor
   swift build
   ```

3. **Run the app**:
   ```bash
   swift run
   ```

### Option 2: Create Xcode Project

1. **Generate Xcode project**:
   ```bash
   cd codex_multi_monitor
   swift package generate-xcodeproj
   ```

2. **Open in Xcode**:
   ```bash
   open CodexMonitor.xcodeproj
   ```

3. **Build and Run** (⌘R)

4. **Set LSUIElement**:
   - In Xcode, select the project
   - Go to Info tab
   - Add "Application is agent (UIElement)" = YES

## Getting Your API Token

### Quick Method (Console One-liner)

1. Open [ChatGPT](https://chatgpt.com) in your browser and **make sure you are logged in**
2. Open Developer Tools Console:
   - **Chrome**: ⌘⌥J (Mac) or F12 → Console
   - **Firefox**: ⌘⌥K (Mac) or F12 → Console
   - **Safari**: ⌘⌥C (Mac) — enable Developer menu first in Safari → Settings → Advanced
3. Paste this one-liner and press **Enter**:

```javascript
fetch('/api/auth/session').then(r=>r.json()).then(d=>{const t=d.accessToken;if(t){copy(t);alert('✅ Token copied to clipboard!\nPaste it into CodexMonitor.')}else{alert('❌ No accessToken found.\nMake sure you are logged in to ChatGPT.')}}).catch(()=>{const t=document.cookie.match(/__Secure-next-auth\.session-token=([^;]+)/)?.[1];if(t){copy(t);alert('✅ Session token copied (fallback)!\nPaste it into CodexMonitor.')}else{alert('❌ Could not extract token.\nMake sure you are logged in, or use the Network tab method below.')}})
```

4. The token is now in your clipboard — paste it into CodexMonitor

> **How it works:** This first tries to fetch an access token from ChatGPT's `/api/auth/session` endpoint (the same token the web app uses). If that fails, it falls back to extracting the `__Secure-next-auth.session-token` cookie value directly.

### Manual Method (Network Tab)

If the one-liner doesn't work:

1. Open [ChatGPT](https://chatgpt.com) in your browser
2. Open Developer Tools (F12 or ⌘⌥I)
3. Go to **Network** tab
4. Navigate to Codex or use any feature that makes API calls
5. Look for requests to `/backend-api/wham/usage`
6. Copy the `Authorization` header value (remove "Bearer " prefix)
7. Paste the token in CodexMonitor

## Usage

1. **Launch** - The app appears as a gauge icon in your menu bar
2. **Click** - Opens the monitoring panel showing all accounts
3. **Add Account** - Click the "+" button (or open Settings) and enter your token
4. **Monitor** - View real-time usage statistics per account
5. **Auto-refresh** - Data updates automatically at your configured interval

### Settings

Open Settings via the gear icon or menu. Two tabs are available:

- **Accounts** — Add, edit, remove, or reorder accounts. Drag to reorder.
- **Preferences** — Configure display mode (remaining/used %), reset time format (relative/absolute), refresh interval, and launch-at-login.

### Status Colors

- 🟢 **Green** - Usage is healthy (< 60%)
- 🟡 **Yellow** - Approaching limit (60-80%)
- 🔴 **Red** - At or near limit (> 80% or rate limited)

## Project Structure

```
codex_multi_monitor/
├── Package.swift
├── README.md
└── Sources/
    └── CodexMonitor/
        ├── App.swift                 # Main app entry point
        ├── Info.plist                # App configuration
        ├── Models/
        │   ├── Account.swift         # Account data model
        │   └── UsageResponse.swift   # API response models (rate limits, credits, etc.)
        ├── Services/
        │   ├── APIService.swift      # Network requests to ChatGPT API
        │   ├── AccountStore.swift    # Account management & persistence
        │   ├── SecureTokenStore.swift # AES-GCM encrypted token storage
        │   └── WindowManager.swift   # Centralized window management
        └── Views/
            ├── MenuBarView.swift     # Main menu bar popover view
            ├── AddAccountSheet.swift # Add/edit account sheet
            ├── UnifiedSettingsView.swift  # Tabbed settings window (Accounts + Preferences)
            └── PreferencesView.swift     # Display & refresh preferences
```

## API Details

The app uses the ChatGPT internal API:

```
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <token>
```

Response includes:
- `plan_type` - Your subscription tier (plus, pro, etc.)
- `rate_limit.primary_window` - 5-hour rolling window usage
- `rate_limit.secondary_window` - Weekly usage limits
- `credits` - API credit balance (if applicable)
- `spend_control` - Spend control information

## Troubleshooting

### "Unauthorized" Error
- Token may have expired — get a fresh token using the console one-liner above
- If using the cookie fallback, try the `/api/auth/session` method instead (or vice versa)

### No Data Showing
- Check your internet connection
- Verify the token is valid
- Try manual refresh (click the refresh button in the popover)

### App Not Appearing
- Check if it's running: `ps aux | grep CodexMonitor`
- Look for the gauge icon in your menu bar
- The app doesn't show in Dock (by design)

## Security Notes

- Tokens are stored in AES-256 encrypted local files (Application Support/CodexMonitor)
- No data is sent to third-party servers
- All requests go directly to OpenAI's servers
- Token is only transmitted over HTTPS

## Development

### Building for Release

```bash
swift build -c release
```

The binary will be in `.build/release/CodexMonitor`

### Creating a .app Bundle

To create a proper macOS app bundle:

1. Build for release:
   ```bash
   swift build -c release
   ```

2. Create the bundle structure:
   ```bash
   mkdir -p CodexMonitor.app/Contents/MacOS
   mkdir -p CodexMonitor.app/Contents/Resources
   cp .build/release/CodexMonitor CodexMonitor.app/Contents/MacOS/
   cp Sources/CodexMonitor/Info.plist CodexMonitor.app/Contents/
   ```

3. (Optional) Add an icon:
   - Create or find an `.icns` file
   - Place it in `CodexMonitor.app/Contents/Resources/AppIcon.icns`
   - Add to Info.plist:
     ```xml
     <key>CFBundleIconFile</key>
     <string>AppIcon</string>
     ```

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Built with SwiftUI and AppKit
- Inspired by the need to monitor API usage limits
- Thanks to the OpenAI/ChatGPT team for the service

---

**Note**: This app uses an internal ChatGPT API that may change without notice. If the app stops working, check for updates or report an issue.
