#!/bin/bash
# Add a release to the Sparkle update feed (site/appcast.xml, published by
# .github/workflows/pages.yml at https://windowshepherd.com/appcast.xml).
#   scripts/make-appcast.sh dist/Window-Shepherd-0.1.0.dmg 0.1.0
# Signs the update with the EdDSA private key that `generate_keys` stored in
# your login Keychain (it never leaves the Keychain, never the repo).
set -euo pipefail
cd "$(dirname "$0")/.."
DMG="${1:?usage: scripts/make-appcast.sh <dmg> <version>}"
VERSION="${2:?usage: scripts/make-appcast.sh <dmg> <version>}"
scripts/fetch-sparkle.sh
STAGE=build/appcast
mkdir -p "$STAGE" docs
cp "$DMG" "$STAGE/"
[ -f site/appcast.xml ] && cp site/appcast.xml "$STAGE/appcast.xml"
vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/cabaynes/window-shepherd/releases/download/v$VERSION/" \
  --link "https://windowshepherd.com" \
  "$STAGE"
cp "$STAGE/appcast.xml" site/appcast.xml
echo "Updated site/appcast.xml — commit and push it after the GitHub release is published."
