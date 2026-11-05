#!/bin/zsh
# Builds Tablet.app into ./build (and, with --install, copies it to /Applications).
set -euo pipefail
cd "$(dirname "$0")"

# OpenTabletDriver daemon that ships inside the app (LGPL-3.0, https://github.com/OpenTabletDriver/OpenTabletDriver)
OTD_VERSION=0.6.8.1
OTD_SHA256=bbd3957ba5a8809e377cda0b746c9a0578d382970375a8ee3f51db68f7b2e328
OTD_CACHE=.build/otd-$OTD_VERSION
if [[ ! -x "$OTD_CACHE/OpenTabletDriver.Daemon" ]]; then
  mkdir -p "$OTD_CACHE"
  echo "Stahuji OpenTabletDriver $OTD_VERSION…"
  curl -fsSL -o "$OTD_CACHE/otd.tar.gz" \
    "https://github.com/OpenTabletDriver/OpenTabletDriver/releases/download/v$OTD_VERSION/OpenTabletDriver-${OTD_VERSION}_osx-arm64.tar.gz"
  echo "$OTD_SHA256  $OTD_CACHE/otd.tar.gz" | shasum -a 256 -c -
  tar -xzf "$OTD_CACHE/otd.tar.gz" -C "$OTD_CACHE" OpenTabletDriver.app/Contents/MacOS/OpenTabletDriver.Daemon
  mv "$OTD_CACHE/OpenTabletDriver.app/Contents/MacOS/OpenTabletDriver.Daemon" "$OTD_CACHE/"
  rm -rf "$OTD_CACHE/OpenTabletDriver.app" "$OTD_CACHE/otd.tar.gz"
  curl -fsSL -o "$OTD_CACHE/LICENSE" "https://raw.githubusercontent.com/OpenTabletDriver/OpenTabletDriver/v$OTD_VERSION/LICENSE"
fi

swift build -c release
# assemble + sign outside ~/Documents: iCloud/File Provider keeps adding extended attributes there,
# which codesign rejects
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/tablet-build.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Tablet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$OTD_CACHE/OpenTabletDriver.Daemon" "$APP/Contents/Helpers/OpenTabletDriver.Daemon"
cp "$OTD_CACHE/LICENSE" "$APP/Contents/Resources/OpenTabletDriver-LICENSE.txt"
cp .build/release/Tablet "$APP/Contents/MacOS/Tablet"
[[ -f Resources/AppIcon.icns ]] || { swift Resources/make-icon.swift Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns; }
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tablet</string>
  <key>CFBundleDisplayName</key><string>Tablet</string>
  <key>CFBundleIdentifier</key><string>local.zdeko.tablet</string>
  <key>CFBundleExecutable</key><string>Tablet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleDevelopmentRegion</key><string>cs</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Ad-hoc signature with a designated requirement on the bundle id only, so macOS keeps the
# Input Monitoring / Accessibility permissions across rebuilds (default ad-hoc pins the exact build).
xattr -cr "$APP"   # downloaded files carry quarantine/Finder attributes that codesign rejects
codesign --force --sign - --identifier net.opentabletdriver.daemon "$APP/Contents/Helpers/OpenTabletDriver.Daemon"
codesign --force --sign - --identifier local.zdeko.tablet \
  --requirements '=designated => identifier "local.zdeko.tablet"' "$APP"
codesign --verify --deep --strict "$APP"
rm -rf build/Tablet.app && mkdir -p build && ditto "$APP" build/Tablet.app
echo "Hotovo: $PWD/build/Tablet.app"

if [[ "${1:-}" == "--install" ]]; then
  # stop the running app and its bundled daemon so the new copy starts clean
  pkill -f '/Applications/Tablet.app/Contents/MacOS/Tablet' || true
  pkill -f '/Applications/Tablet.app/Contents/Helpers/OpenTabletDriver.Daemon' || true
  sleep 1
  rm -rf /Applications/Tablet.app
  ditto "$APP" /Applications/Tablet.app
  codesign --verify --deep --strict /Applications/Tablet.app
  echo "Nainstalováno: /Applications/Tablet.app"
fi
