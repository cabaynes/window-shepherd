# Homebrew cask for cabaynes/homebrew-tap (copy to Casks/window-shepherd.rb there).
# Fill in version and sha256 from scripts/release.sh's output for each release.
cask "window-shepherd" do
  version "0.1.0"
  sha256 "REPLACE_WITH_THE_DMG_SHA256"

  url "https://github.com/cabaynes/window-shepherd/releases/download/v#{version}/Window-Shepherd-#{version}.dmg"
  name "Window Shepherd"
  desc "Moves windows between screens and puts them back when monitors change"
  homepage "https://windowshepherd.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Window Shepherd.app"

  uninstall quit: "com.windowshepherd.WindowShepherd"

  zap trash: [
    "~/Library/Application Support/Window Shepherd",
    "~/Library/Logs/Window Shepherd",
    "~/Library/Preferences/com.windowshepherd.WindowShepherd.plist",
  ]
end
