#!/bin/bash
# Fetch the pinned Sparkle release (the update framework) into vendor/Sparkle/.
# Pinned by version and SHA-256; vendor/ is gitignored. Called by build.sh.
# (A plain download rather than Swift Package Manager: SPM's own downloader
# can't fetch Sparkle's prebuilt framework on every machine.)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DEST=vendor/Sparkle
[ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ] && exit 0
mkdir -p vendor
TAR="vendor/Sparkle-$VERSION.tar.xz"
if [ ! -f "$TAR" ]; then
  /usr/bin/curl -fsSL -o "$TAR" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
fi
echo "$SHA256  $TAR" | shasum -a 256 -c - >/dev/null || { echo "Sparkle download doesn't match its checksum"; rm -f "$TAR"; exit 1; }
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xJf "$TAR" -C "$DEST"
echo "$VERSION" > "$DEST/.version"
echo "Sparkle $VERSION ready in $DEST"
