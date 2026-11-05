#!/bin/zsh
# Builds Tablet.app into ./build (and, with --install, copies it to /Applications).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Tablet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
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
codesign --force --sign - --identifier local.zdeko.tablet \
  --requirements '=designated => identifier "local.zdeko.tablet"' "$APP"
echo "Hotovo: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Tablet.app
  cp -R "$APP" /Applications/Tablet.app
  echo "Nainstalováno: /Applications/Tablet.app"
fi
