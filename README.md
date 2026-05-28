# CodexMonitor

A macOS menu bar application that monitors your ChatGPT Codex usage in real-time.

## Features

- 🎯 **Menu Bar App** - Lives in your macOS menu bar, no Dock icon
- 📊 **Real-time Monitoring** - Track rate limits for 5-hour and weekly windows
- 🔐 **Secure Token Storage** - Uses macOS Keychain for sensitive data
- 🔄 **Auto-refresh** - Updates every 5 minutes automatically
- 🎨 **Status Indicator** - Color-coded icon (green/yellow/red) based on usage
- 👥 **Multi-account Support** - Monitor multiple ChatGPT accounts simultaneously

## Screenshots

The app displays usage information like:

```
【Work Account】 Plus
⏱ 5 hours: Used 25% · Remaining 75% · Resets 15:06
📅 Weekly:  Used 9%  · Remaining 91% · Resets Sunday 03:08
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+ (included in Xcode 15+)
- ChatGPT Plus/Pro/Enterprise subscription

## Installation

### Option 1: Build from Source

1. **Clone or download** this repository

2. **Build the project**:
   ```bash
   cd codex-monitor
   swift build
   ```

3. **Run the app**:
   ```bash
   swift run
   ```

### Option 2: Create Xcode Project

1. **Generate Xcode project**:
   ```bash
   cd codex-monitor
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

1. Open [ChatGPT](https://chatgpt.com) in your browser
2. Open Developer Tools (F12 or ⌘⌥I)
3. Go to **Network** tab
4. Navigate to Codex or use any feature that makes API calls
5. Look for requests to `/backend-api/wham/usage`
6. Copy the `Authorization` header value (remove "Bearer " prefix)
7. Paste the token in CodexMonitor

## Usage

1. **Launch** - The app appears as a gauge icon in your menu bar
2. **Click** - Opens the monitoring panel
3. **Add Account** - Click the "+" button and enter your token
4. **Monitor** - View real-time usage statistics
5. **Auto-refresh** - Data updates every 5 minutes automatically

### Status Colors

- 🟢 **Green** - Usage is healthy (< 60%)
- 🟡 **Yellow** - Approaching limit (60-80%)
- 🔴 **Red** - At or near limit (> 80% or rate limited)

## Project Structure

```
codex-monitor/
├── Package.swift
├── README.md
└── Sources/
    └── CodexMonitor/
        ├── App.swift                 # Main app entry point
        ├── Info.plist                # App configuration
        ├── Models/
        │   ├── Account.swift         # Account data model
        │   └── UsageResponse.swift   # API response models
        ├── Services/
        │   ├── APIService.swift      # Network requests
        │   ├── AccountStore.swift    # Account management
        │   └── KeychainHelper.swift  # Keychain utilities
        └── Views/
            ├── MenuBarView.swift     # Main menu bar view
            └── AddAccountSheet.swift # Add/edit account sheet
```

## API Details

The app uses the ChatGPT internal API:

```
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <your-token>
```

Response includes:
- `plan_type` - Your subscription tier (plus, pro, etc.)
- `rate_limit.primary_window` - 5-hour rolling window usage
- `rate_limit.secondary_window` - Weekly usage limits
- `credits` - API credit balance (if applicable)

## Troubleshooting

### "Unauthorized" Error
- Token may have expired
- Get a fresh token from browser developer tools

### No Data Showing
- Check your internet connection
- Verify the token is valid
- Try manual refresh (click the refresh button)

### App Not Appearing
- Check if it's running: `ps aux | grep CodexMonitor`
- Look for the gauge icon in your menu bar
- The app doesn't show in Dock (by design)

## Security Notes

- Tokens are stored in macOS Keychain (encrypted)
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
