#!/bin/sh
# Prints the tag for the next release, from .version:
#   v<version>                     if that tag doesn't exist yet (the version was bumped)
#   v<version>-rc-<YYYYMMDDHHMMSS>  otherwise (same version as the last release), UTC
# Needs the repo's tags fetched (`git fetch --tags`).
set -e
cd "$(dirname "$0")/.."
VERSION=$(tr -d ' \n' < .version)
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "v$VERSION-rc-$(date -u +%Y%m%d%H%M%S)"
else
  echo "v$VERSION"
fi
