#!/bin/sh
# SIGNING_IDENTITY='Developer ID Application: …' NOTARY_PROFILE=anota sh scripts/notarize.sh
set -eu
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Store credentials with xcrun notarytool store-credentials, then set NOTARY_PROFILE}"
sh scripts/make-app.sh release
APP=build/Anota.app
VERSION=$(tr -d ' \n' < .version)
DMG="build/Anota-$VERSION.dmg"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" build/Anota-notarize.zip
xcrun notarytool submit build/Anota-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
sh scripts/make-dmg.sh
codesign --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized $DMG"
