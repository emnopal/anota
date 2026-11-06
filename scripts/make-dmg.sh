#!/bin/sh
# Package the built app; release signing/notarization is handled by notarize.sh.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(tr -d ' \n' < .version)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Anota.app "$STAGE/Anota.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Anota -srcfolder "$STAGE" -ov -format UDZO "build/Anota-$VERSION.dmg"
