#!/usr/bin/env bash
# Builds the `emu` helper as one universal binary and signs it ad-hoc.
# Usage: scripts/build-helper.sh [path-to-emu-checkout]
set -euo pipefail

EMU_DIR="${1:-$HOME/Workspace/emu}"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"

cd "$EMU_DIR"
export PATH="$HOME/.cargo/bin:$PATH"

# Universal unless SIMDECK_ARM64_ONLY=1.
cargo build --release --target aarch64-apple-darwin
mkdir -p "$OUT_DIR"
if [ "${SIMDECK_ARM64_ONLY:-0}" = "1" ]; then
  cp target/aarch64-apple-darwin/release/emu "$OUT_DIR/emu-universal"
else
  rustup target add x86_64-apple-darwin >/dev/null 2>&1 || true
  cargo build --release --target x86_64-apple-darwin
  lipo -create \
    target/aarch64-apple-darwin/release/emu \
    target/x86_64-apple-darwin/release/emu \
    -output "$OUT_DIR/emu-universal"
fi

# Ad-hoc signature with the hardened runtime, so the app can ship without an
# Apple Developer ID (spec §12.3).
codesign --force --sign - --options runtime --timestamp=none "$OUT_DIR/emu-universal"

echo "helper: $OUT_DIR/emu-universal"
lipo -info "$OUT_DIR/emu-universal"
codesign -dvv "$OUT_DIR/emu-universal" 2>&1 | grep -E 'Runtime|Signature' || true
