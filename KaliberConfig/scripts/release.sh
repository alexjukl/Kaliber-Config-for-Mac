#!/bin/bash
# Builds, signs (Developer ID), notarizes, staples and publishes KaliberConfig to GitHub Releases.
#
#   scripts/release.sh v0.2.0            # tag must exist locally and match Info.plist version bump below
#   scripts/release.sh v0.2.0 --no-publish   # stop after stapling (dist/KaliberConfig.app.zip)
#
# One-time setup: a "Developer ID Application" certificate in the login keychain and
#   xcrun notarytool store-credentials kaliber-notary --key <AuthKey.p8> --key-id <id> --issuer <issuer>
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: release.sh vX.Y.Z [--no-publish]}
VERSION=${TAG#v}
PROFILE=${NOTARY_PROFILE:-kaliber-notary}
APP=../dist/KaliberConfig.app
ZIP=../dist/KaliberConfig.app.zip

security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "no Developer ID Application certificate in keychain" >&2; exit 1; }

# version stamp, then build + sign (bundle.sh picks the Developer ID identity)
./scripts/bundle.sh
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
DEVID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
codesign --force --options runtime --timestamp --sign "$DEVID" --identifier com.alexjukl.kaliberconfig "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
echo "notarizing…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
echo "notarized + stapled: $ZIP"

if [ "${2:-}" != "--no-publish" ]; then
    NOTES="Notarized build (signed with Developer ID, no Gatekeeper warning). After unzipping, allow the app under System Settings → Privacy & Security → Input Monitoring when asked."
    if gh release view "$TAG" >/dev/null 2>&1; then
        gh release upload "$TAG" "$ZIP" --clobber
    else
        gh release create "$TAG" "$ZIP" --title "Kaliber Config for Mac $VERSION" --notes "$NOTES"
    fi
    echo "published: $(gh release view "$TAG" --json url -q .url)"
fi
