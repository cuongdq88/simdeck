#!/usr/bin/env bash
# Builds SimDeck.app (Flutter) with the universal emu helper inside, signs
# the bundle from the inside out, and writes build/SimDeck-<version>.dmg.
# Usage: scripts/release.sh <version> [path-to-emu-checkout]
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [emu-checkout]}"
EMU_DIR="${2:-$HOME/Workspace/emu}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"

export PATH="/opt/homebrew/bin:$PATH"
# A brew-managed app must never update itself (spec §12.2).
export SIMDECK_NO_UPDATE=1

bash "$ROOT/scripts/build-helper.sh" "$EMU_DIR"

cd "$ROOT/app"
flutter build macos --release --dart-define=SIMDECK_NO_UPDATE=true

APP=""
for candidate in SimDeck.app SimUtil.app; do
  if [ -d "build/macos/Build/Products/Release/$candidate" ]; then
    APP="build/macos/Build/Products/Release/$candidate"
    break
  fi
done
if [ -z "$APP" ]; then
  echo "release: no .app in build/macos/Build/Products/Release" >&2
  exit 1
fi

mkdir -p "$APP/Contents/Resources"
cp "$BUILD/emu-universal" "$APP/Contents/Resources/emu"
chmod +x "$APP/Contents/Resources/emu"

# Inside out: nested binaries first, then the bundle.
codesign --force --sign - --options runtime --timestamp=none "$APP/Contents/Resources/emu"
codesign --force --deep --sign - --options runtime --timestamp=none "$APP"

STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$BUILD/SimDeck-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "SimDeck $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null

echo "dmg:    $DMG"
echo "sha256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "spctl (expected to be rejected while ad-hoc signed):"
spctl -a -vv "$APP" 2>&1 | head -3 || true
