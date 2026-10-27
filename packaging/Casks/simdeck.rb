cask "simdeck" do
  version "0.2.7"
  sha256 "fb061e771a26d197cd8efaf50a432dce0d481c6c63d2f937d3de7a278bacef38"

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
