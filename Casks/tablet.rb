# Homebrew cask for Tablet. Published in the tap github.com/zdkdsgn/homebrew-tap:
#   brew install --cask zdkdsgn/tap/tablet
cask "tablet" do
  version "1.3.2"
  sha256 "f4bac92bbd4bfe7f39f23395c9729ecef670c800c2c82d31bcc1306f6baff807"

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
