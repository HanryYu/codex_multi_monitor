#!/bin/bash
set -euo pipefail

APP_NAME="CodexMonitor"
DMG_NAME="CodexMonitor"
VERSION="${1:-0.7.2}"
BUNDLE_ID="com.henry.codex-monitor"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
MAC_PROVISIONING_PROFILE="${MAC_PROVISIONING_PROFILE:-}"
MAC_PROVISIONING_PROFILE_BASE64="${MAC_PROVISIONING_PROFILE_BASE64:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ARM64_BUILD_DIR="$PROJECT_DIR/.build/arm64/arm64-apple-macosx/release"
X86_64_BUILD_DIR="$PROJECT_DIR/.build/x86_64/x86_64-apple-macosx/release"
UNIVERSAL_BUILD_DIR="$PROJECT_DIR/.build/universal"
APP_BUNDLE="$PROJECT_DIR/.build/$APP_NAME.app"
DMG_OUTPUT="$PROJECT_DIR/.build/$DMG_NAME-$VERSION.dmg"

echo "🔨 Building $APP_NAME $VERSION (Universal release)..."
cd "$PROJECT_DIR"
swift build -c release \
    --triple arm64-apple-macosx15.0 \
    --scratch-path "$PROJECT_DIR/.build/arm64" 2>&1
swift build -c release \
    --triple x86_64-apple-macosx15.0 \
    --scratch-path "$PROJECT_DIR/.build/x86_64" 2>&1

ARM64_BINARY="$ARM64_BUILD_DIR/$APP_NAME"
X86_64_BINARY="$X86_64_BUILD_DIR/$APP_NAME"
if [[ ! -f "$ARM64_BINARY" || ! -f "$X86_64_BINARY" ]]; then
    echo "❌ Architecture-specific release binaries not found"
    exit 1
fi

mkdir -p "$UNIVERSAL_BUILD_DIR"
BINARY="$UNIVERSAL_BUILD_DIR/$APP_NAME"
/usr/bin/lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$BINARY"
/usr/bin/lipo "$BINARY" -verify_arch arm64 x86_64

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
    <string>$BUNDLE_ID</string>
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

# Copy app icon
ICON_SRC="$PROJECT_DIR/Sources/CodexMonitor/Resources/AppIcon.icns"
ENTITLEMENTS_TEMPLATE="$PROJECT_DIR/Sources/CodexMonitor/CodexMonitor.entitlements"
ENTITLEMENTS_SRC="$UNIVERSAL_BUILD_DIR/CodexMonitor.entitlements"
EMBEDDED_PROFILE="$APP_BUNDLE/Contents/embedded.provisionprofile"
ENTITLEMENTS_TO_SIGN=""
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "   ✅ App icon copied"
else
    echo "   ⚠️  AppIcon.icns not found at $ICON_SRC"
fi

GITHUB_ICON_SRC="$PROJECT_DIR/Sources/CodexMonitor/Resources/GitHub_Invertocat_Black.png"
if [ -f "$GITHUB_ICON_SRC" ]; then
    cp "$GITHUB_ICON_SRC" "$APP_BUNDLE/Contents/Resources/GitHub_Invertocat_Black.png"
    echo "   ✅ GitHub icon copied"
fi

for PROVIDER_ICON in ProviderCodex.png ProviderClaude.png ProviderGrok.png; do
    PROVIDER_ICON_SRC="$PROJECT_DIR/Sources/CodexMonitor/Resources/$PROVIDER_ICON"
    if [ -f "$PROVIDER_ICON_SRC" ]; then
        cp "$PROVIDER_ICON_SRC" "$APP_BUNDLE/Contents/Resources/$PROVIDER_ICON"
    fi
done

TEAM_IDENTIFIER_PREFIX="${TEAM_IDENTIFIER_PREFIX:-}"
if [[ -z "$TEAM_IDENTIFIER_PREFIX" && -n "$CODE_SIGN_IDENTITY" ]]; then
    TEAM_IDENTIFIER_PREFIX="$(
        printf "%s" "$CODE_SIGN_IDENTITY" \
            | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p' \
            | head -n 1
    )"
fi
if [[ -z "$TEAM_IDENTIFIER_PREFIX" && -n "$CODE_SIGN_IDENTITY" ]]; then
    TEAM_IDENTIFIER_PREFIX="$(
        security find-certificate -c "$CODE_SIGN_IDENTITY" -p 2>/dev/null \
            | openssl x509 -noout -subject 2>/dev/null \
            | sed -nE 's/.*OU[[:space:]]*=[[:space:]]*([^,\/]*).*/\1/p' \
            | head -n 1
    )"
fi
TEAM_IDENTIFIER_PREFIX="$(
    printf "%s" "$TEAM_IDENTIFIER_PREFIX" \
        | sed -E 's/^[[:space:]=]+//; s/[[:space:]]+$//; s/\.+$//'
)"
if [[ -n "$MAC_PROVISIONING_PROFILE_BASE64" ]]; then
    printf "%s" "$MAC_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$EMBEDDED_PROFILE"
    echo "   ✅ Embedded provisioning profile from MAC_PROVISIONING_PROFILE_BASE64"
elif [[ -n "$MAC_PROVISIONING_PROFILE" ]]; then
    if [[ ! -f "$MAC_PROVISIONING_PROFILE" ]]; then
        echo "❌ MAC_PROVISIONING_PROFILE does not exist: $MAC_PROVISIONING_PROFILE"
        exit 1
    fi
    cp "$MAC_PROVISIONING_PROFILE" "$EMBEDDED_PROFILE"
    echo "   ✅ Embedded provisioning profile from $MAC_PROVISIONING_PROFILE"
fi

if [[ -f "$EMBEDDED_PROFILE" ]]; then
    if [[ -n "$TEAM_IDENTIFIER_PREFIX" ]]; then
        TEAM_IDENTIFIER_PREFIX="$TEAM_IDENTIFIER_PREFIX."
    fi
    sed "s/\$(TeamIdentifierPrefix)/$TEAM_IDENTIFIER_PREFIX/g" "$ENTITLEMENTS_TEMPLATE" > "$ENTITLEMENTS_SRC"
    ENTITLEMENTS_TO_SIGN="$ENTITLEMENTS_SRC"
else
    echo "   ⚠️  No provisioning profile supplied; skipping restricted iCloud entitlements so the app can launch under Developer ID"
fi

codesign_app_bundle() {
    local identity="$1"
    local include_timestamp="$2"
    local args=(--force --identifier "$BUNDLE_ID")

    if [[ -n "$ENTITLEMENTS_TO_SIGN" ]]; then
        args+=(--entitlements "$ENTITLEMENTS_TO_SIGN")
    fi

    args+=(--options runtime)

    if [[ "$include_timestamp" == "true" ]]; then
        args+=(--timestamp)
    fi

    args+=(--sign "$identity" "$APP_BUNDLE")
    codesign "${args[@]}"
}

echo "🔏 Signing .app bundle..."
if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    if [[ "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        codesign_app_bundle "$CODE_SIGN_IDENTITY" true
    else
        codesign_app_bundle "$CODE_SIGN_IDENTITY" false
    fi
    echo "   ✅ Signed with $CODE_SIGN_IDENTITY"
else
    codesign_app_bundle - false
    echo "   ⚠️  No Developer ID identity supplied; created an ad-hoc signed local build"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

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

if [[ "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_OUTPUT"
    codesign --verify --verbose=2 "$DMG_OUTPUT"
    echo "   ✅ DMG signed with Developer ID"
elif [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$DMG_OUTPUT"
    codesign --verify --verbose=2 "$DMG_OUTPUT"
    echo "   ⚠️  DMG signed with a development certificate; Developer ID is required for Homebrew distribution"
fi

echo ""
echo "✅ Done!"
echo "   App bundle: $APP_BUNDLE"
echo "   DMG:        $DMG_OUTPUT"
echo "   Size:       $(du -h "$DMG_OUTPUT" | cut -f1)"
