cask "simdeck" do
  version "0.1.0"
  sha256 "8c2ed40ab1cbc0e2f043a26032d1ff2481f1ef4afd1736f10517425748336726"

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
