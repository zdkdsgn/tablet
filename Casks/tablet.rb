# Homebrew cask for Tablet. Published in the tap github.com/zdkdsgn/homebrew-tap:
#   brew install --cask zdkdsgn/tap/tablet
cask "tablet" do
  version "1.2"
  sha256 "04a439608cd9acc2a071af15e709b53ccaac5183edba11ae8d38d57ae42b73d7"

  url "https://github.com/zdkdsgn/tablet/releases/download/v#{version}/Tablet-#{version}.dmg"
  name "Tablet"
  desc "Native macOS app for the Wacom Intuos Pro M (PTH-651) with a built-in OpenTabletDriver"
  homepage "https://github.com/zdkdsgn/tablet"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Tablet.app"

  postflight do
    # the app is ad-hoc signed, not notarised
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Tablet.app"]
  end

  uninstall quit: "local.zdeko.tablet",
            login_item: "Tablet"

  zap trash: [
    "~/Library/Preferences/local.zdeko.tablet.plist",
    "~/Library/Logs/Tablet.log",
    "~/Library/Logs/Tablet-hid.log",
  ]
end
