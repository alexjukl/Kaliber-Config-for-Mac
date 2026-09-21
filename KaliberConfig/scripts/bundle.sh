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
# Signing, best available first:
#   1. Developer ID Application (hardened runtime + secure timestamp; what release.sh notarizes)
#   2. the local self-signed "Kaliber Config Local" cert (stable requirement for Input Monitoring during development)
#   3. ad-hoc (CI; macOS forgets the Input Monitoring grant after each rebuild)
# Set SIGN=local to force option 2 on a machine that also has a Developer ID cert.
IDS=$(security find-identity -v -p codesigning 2>/dev/null || true)
DEVID=$(echo "$IDS" | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
LOCAL=$(echo "$IDS" | grep -o '"Kaliber Config Local"' | head -1 | tr -d '"' || true)
if [ -n "$DEVID" ] && [ "${SIGN:-}" != "local" ]; then
    codesign --force --options runtime --timestamp --sign "$DEVID" --identifier com.alexjukl.kaliberconfig "$APP"
else
    codesign --force --sign "${LOCAL:--}" --identifier com.alexjukl.kaliberconfig "$APP"
fi
codesign -d -r- "$APP" 2>&1 | grep designated
echo "Built $APP"
