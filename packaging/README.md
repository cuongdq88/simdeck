# Packaging

SimDeck ships as a Homebrew cask. The app binary is inside `SimDeck.app`;
the Rust `emu` helper lives in `SimDeck.app/Contents/Resources/emu` and is
signed before the bundle.

## Build a release

```bash
bash scripts/release.sh 0.1.0        # writes build/SimDeck-0.1.0.dmg and prints its sha256
```

`scripts/release.sh` runs `scripts/build-helper.sh` (universal arm64+x86_64
`emu`, ad-hoc signed with hardened runtime), builds the Flutter app with
`--dart-define=SIMDECK_NO_UPDATE=true`, copies the helper into the bundle,
signs inside-out, and packs the dmg.

## What the user needs

The cask installs the app, `adb` and `ffmpeg` — not the Android SDK. Without
Android Studio, the SDK comes from Homebrew:

```bash
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "emulator" "platforms;android-36"
```

The helper resolves the SDK from `ANDROID_HOME`, then `ANDROID_SDK_ROOT`,
then `~/Library/Android/sdk`, then `/opt/homebrew/share/android-commandlinetools`.
System images are installed from the app (toolbar › System images); the
`emulator` binary itself still comes from `sdkmanager`.

## Publish

1. Bump `app/pubspec.yaml` and `macos/Runner/Configs/AppInfo.xcconfig`.
2. Build the dmg.
3. Put the new `sha256` into `packaging/Casks/simdeck.rb`.
4. Push the dmg to a GitHub release tagged `v<version>`.
5. Copy `Casks/simdeck.rb` into the `cuongdq88/homebrew-simdeck` tap and commit
   `simdeck <version>`.

Users install with:

```bash
brew install --cask cuongdq88/simdeck/simdeck
```

## Gatekeeper

Without an Apple Developer ID the app is ad-hoc signed and macOS may say it
is damaged. The cask caveats and the README tell users to run
`xattr -dr com.apple.quarantine "/Applications/SimDeck.app"`. With a
Developer ID, sign both the helper and the app with that identity and
notarize the dmg instead; do not ship ad-hoc then.

## Self-update

`SIMDECK_NO_UPDATE=1` (or `--dart-define`) makes the app register no update
cubit at all, so `brew upgrade` stays the only update path.
