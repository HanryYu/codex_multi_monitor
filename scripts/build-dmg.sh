#!/bin/bash
set -euo pipefail

APP_NAME="CodexMonitor"
DMG_NAME="CodexMonitor"
VERSION="${1:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/.build/$APP_NAME.app"
DMG_OUTPUT="$PROJECT_DIR/.build/$DMG_NAME-$VERSION.dmg"

echo "🔨 Building $APP_NAME $VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "❌ Binary not found at $BINARY"
    exit 1
fi

echo "📦 Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.henry.codex-monitor</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Codex Monitor</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Create a simple app icon (optional - uses system icon as placeholder)
# To add a real icon, place AppIcon.icns in the Resources folder

echo "💿 Creating DMG..."
rm -f "$DMG_OUTPUT"

# Create temp directory for DMG contents
TEMP_DIR=$(mktemp -d)
cp -R "$APP_BUNDLE" "$TEMP_DIR/"

# Create symlink to Applications
ln -s /Applications "$TEMP_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_OUTPUT" 2>&1

rm -rf "$TEMP_DIR"

echo ""
echo "✅ Done!"
echo "   App bundle: $APP_BUNDLE"
echo "   DMG:        $DMG_OUTPUT"
echo "   Size:       $(du -h "$DMG_OUTPUT" | cut -f1)"
