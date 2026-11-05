#!/bin/sh
# Prints the .changelog section for the version in .version (heading "## v<version>").
cd "$(dirname "$0")/.."
VERSION=$(tr -d ' \n' < .version)
awk -v h="## v$VERSION" '$0 == h { on = 1; next } /^## / && on { exit } on' .changelog
