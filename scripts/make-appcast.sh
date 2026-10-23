#!/bin/bash
# Add a release to the Sparkle update feed (docs/appcast.xml, served by GitHub
# Pages at https://cabaynes.github.io/window-shepherd/appcast.xml).
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
[ -f docs/appcast.xml ] && cp docs/appcast.xml "$STAGE/appcast.xml"
vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/cabaynes/window-shepherd/releases/download/v$VERSION/" \
  --link "https://windowshepherd.com" \
  "$STAGE"
cp "$STAGE/appcast.xml" docs/appcast.xml
echo "Updated docs/appcast.xml — commit and push it after the GitHub release is published."
