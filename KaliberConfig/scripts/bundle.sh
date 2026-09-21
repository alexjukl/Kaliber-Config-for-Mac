#!/bin/bash
# Builds KaliberConfig in release mode and wraps it into dist/KaliberConfig.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
CONF=${1:-release}
swift build -c "$CONF" --product KaliberConfig
BIN="$(swift build -c "$CONF" --show-bin-path)/KaliberConfig"
APP="../dist/KaliberConfig.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KaliberConfig"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>KaliberConfig</string>
    <key>CFBundleIdentifier</key><string>com.alexjukl.kaliberconfig</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Kaliber Config</string>
    <key>CFBundleDisplayName</key><string>Kaliber Config</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Unofficial configurator for Kaliber Gaming devices. Not affiliated with IOGEAR.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
[ -f scripts/AppIcon.icns ] && cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with the local self-signed "Kaliber Config Local" certificate when present (stable designated
# requirement, so the Input Monitoring grant survives rebuilds); otherwise ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Kaliber Config Local"' | head -1 | tr -d '"')
codesign --force --sign "${IDENTITY:--}" --identifier com.alexjukl.kaliberconfig "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated
echo "Built $APP"
