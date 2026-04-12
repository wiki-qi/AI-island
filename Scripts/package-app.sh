#!/bin/bash
set -e

cd "$(dirname "$0")/.."
PROJECT_DIR=$(pwd)
OUTPUT_DIR="$PROJECT_DIR/output"
APP_NAME="NotchAgent"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "🔨 Building Release..."
swift build -c release

echo "📦 Creating app bundle..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binaries
cp .build/release/NotchAgent "$APP_BUNDLE/Contents/MacOS/"
cp .build/release/NotchBridge "$APP_BUNDLE/Contents/MacOS/"

# Copy icon if exists
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>NotchAgent</string>
    <key>CFBundleDisplayName</key>
    <string>NotchAgent</string>
    <key>CFBundleIdentifier</key>
    <string>com.notchagent.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>NotchAgent</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>NotchAgent needs AppleEvents access to jump to terminal sessions.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign
echo "🔏 Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Done!"
echo "   App: $APP_BUNDLE"
echo ""
echo "📋 To install:"
echo "   cp -R $APP_BUNDLE ~/Applications/"
echo "   open ~/Applications/$APP_NAME.app"
echo ""
echo "⚠️  First launch: Right-click → Open → Open (to bypass Gatekeeper)"
