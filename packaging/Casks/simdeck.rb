cask "simdeck" do
  version "0.1.0"
  sha256 "e62052918bf9f34318be67f9a572f69a8ab2b99a63a20a4e86341cca19643bf7"

  url "https://github.com/cuong/simdeck/releases/download/v#{version}/SimDeck-#{version}.dmg"
  name "SimDeck"
  desc "Virtual device manager for Android emulators and iOS simulators"
  homepage "https://github.com/cuong/simdeck"

  depends_on macos: ">= :monterey"
  depends_on formula: "ffmpeg"                 # only needed for recording
  depends_on cask: "android-platform-tools"    # adb; the emulator and avdmanager still come from the Android SDK

  app "SimDeck.app"

  caveats <<~EOS
    SimDeck needs the Android SDK (emulator, avdmanager, sdkmanager) and
    Xcode for iOS. Without Android Studio, install the SDK once:
      brew install --cask android-commandlinetools
      sdkmanager "platform-tools" "emulator" "platforms;android-36"
    SimDeck finds the SDK via ANDROID_HOME, else ~/Library/Android/sdk,
    else Homebrew's android-commandlinetools. System images can be
    installed from the app (toolbar > System images).
    If macOS says "SimDeck is damaged", run:
      xattr -dr com.apple.quarantine "/Applications/SimDeck.app"
  EOS
end
