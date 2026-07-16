cask "scratio" do
  version "1.0.0"
  sha256 "replace_with_sha256_of_release_dmg"

  url "https://github.com/emilshr/scratio/releases/download/v#{version}/Scratio-#{version}.dmg"
  name "Scratio"
  desc "Menu bar screenshot app with aspect-ratio selection"
  homepage "https://github.com/emilshr/scratio"

  depends_on macos: ">= :sequoia"

  app "Scratio.app"

  zap trash: [
    "~/Library/Application Support/scratio",
    "~/Library/Preferences/emilshr.scratio.plist",
  ]

  caveats <<~EOS
    Scratio requires Screen Recording permission:
      System Settings → Privacy & Security → Screen Recording
    Enable Scratio, then quit and reopen the app if prompted.
  EOS
end
