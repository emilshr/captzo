cask "captzo" do
  version "1.0.0"
  sha256 "replace_with_sha256_of_release_dmg"

  url "https://github.com/emilshr/captzo/releases/download/v#{version}/Captzo-#{version}.dmg"
  name "Captzo"
  desc "Menu bar screenshot app with aspect-ratio selection"
  homepage "https://github.com/emilshr/captzo"

  depends_on macos: ">= :sequoia"

  app "Captzo.app"

  zap trash: [
    "~/Library/Application Support/captzo",
    "~/Library/Preferences/emilshr.captzo.plist",
  ]

  caveats <<~EOS
    Captzo requires Screen Recording permission:
      System Settings → Privacy & Security → Screen Recording
    Enable Captzo, then quit and reopen the app if prompted.
  EOS
end
