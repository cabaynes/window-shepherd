#!/bin/bash
# Build a release: Developer ID signing, notarization, stapling, and a DMG.
#   scripts/release.sh 0.1.0
# Needs (see docs/RELEASING.md — none of these are ever committed):
#   DEVELOPER_ID_NAME  e.g. "Charles Baynes (TEAMID1234)" — the name of your
#                      "Developer ID Application" certificate in Keychain
#   NOTARY_PROFILE     the keychain profile saved with `xcrun notarytool store-credentials`
# Without DEVELOPER_ID_NAME it builds an unsigned DMG for local packaging tests only.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
BUILD="$(git rev-list --count HEAD)"
scripts/fetch-sparkle.sh
(cd App && xcodegen generate --quiet)
mkdir -p dist build

SIGNED=0
EXTRA_SETTINGS=()
if [ -n "${DEVELOPER_ID_NAME:-}" ]; then
  SIGNED=1
  IDENTITY="Developer ID Application: $DEVELOPER_ID_NAME"
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE (see docs/RELEASING.md)}"
else
  echo "Apple Developer enrollment needed for a signed release — see docs/RELEASING.md."
  echo "Building an unsigned DMG for local packaging tests instead."
  IDENTITY="-"
  # Ad-hoc signing has no Team ID, so the hardened runtime would refuse the
  # embedded Sparkle unless library validation is relaxed (as in Debug builds).
  EXTRA_SETTINGS=("CODE_SIGN_ENTITLEMENTS=$PWD/App/WindowShepherd/WindowShepherd-Debug.entitlements")
fi

xcodebuild -project App/WindowShepherd.xcodeproj -scheme WindowShepherd -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ${EXTRA_SETTINGS[@]+"${EXTRA_SETTINGS[@]}"} build >build/release.log 2>&1 \
  || { grep -E "error:" build/release.log | head -20; echo "build failed: build/release.log"; exit 1; }
APP="build/DerivedData/Build/Products/Release/Window Shepherd.app"

notarize() {   # notarize <file> — waits for Apple's verdict
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ "$SIGNED" = 1 ]; then
  # Sparkle ships its helpers signed ad-hoc; notarization needs every one
  # signed with our Developer ID and the hardened runtime, inside out
  # (https://sparkle-project.org/documentation/sandboxing/#code-signing).
  FW="$APP/Contents/Frameworks/Sparkle.framework"
  sign() { codesign -f -s "$IDENTITY" -o runtime --timestamp "$@"; }
  sign "$FW/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
  sign "$FW/Versions/B/Autoupdate"
  sign "$FW/Versions/B/Updater.app"
  sign "$FW"
  sign --entitlements App/WindowShepherd/WindowShepherd.entitlements "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  ditto -c -k --keepParent "$APP" build/notarize.zip
  notarize build/notarize.zip
  xcrun stapler staple "$APP"
  DMG="dist/Window-Shepherd-$VERSION.dmg"
else
  DMG="dist/Window Shepherd $VERSION (unsigned).dmg"
fi

STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Window Shepherd" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ "$SIGNED" = 1 ]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo
echo "DMG:    $DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
