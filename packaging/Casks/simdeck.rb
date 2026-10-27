cask "simdeck" do
  version "0.1.0"
  sha256 "69a33a503b3c954db87d70879b7cfdb4c57a1ed03a4ae1f3d37c3e81366baafc"

  url "https://github.com/cuong/simdeck/releases/download/v#{version}/SimDeck-#{version}.dmg"
  name "SimDeck"
  desc "Virtual device manager for Android emulators and iOS simulators"
  homepage "https://github.com/cuong/simdeck"

  depends_on macos: ">= :monterey"
  depends_on formula: "ffmpeg"                 # only needed for recording
  depends_on cask: "android-platform-tools"    # adb; the emulator and avdmanager still come from the Android SDK

  app "SimDeck.app"

  caveats <<~EOS
    SimDeck needs the Android SDK (emulator, avdmanager) and Xcode for iOS.
    If macOS says "SimDeck is damaged", run:
      xattr -dr com.apple.quarantine "/Applications/SimDeck.app"
  EOS
end
