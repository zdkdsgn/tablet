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

# App Intents (Shortcuts / Siri actions) need metadata that only Xcode's toolchain can extract:
# the compiler writes the intents' constant values, appintentsmetadataprocessor turns them into
# Contents/Resources/Metadata.appintents. Without Xcode the app still builds (tablet:// links work).
TC=$(xcode-select -p 2>/dev/null)/Toolchains/XcodeDefault.xctoolchain
INTENTS=.build/intents
if [[ -x "$TC/usr/bin/appintentsmetadataprocessor" && -f "$TC/usr/share/swift/SwiftConstantValues/AppIntents.json" ]]; then
  rm -rf "$INTENTS/out" && mkdir -p "$INTENTS/out"  # keep the const values: an up-to-date build does not rewrite them
  swift build -c release \
    -Xswiftc -emit-const-values-path -Xswiftc "$PWD/$INTENTS/Tablet.swiftconstvalues" \
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
    -Xswiftc -Xfrontend -Xswiftc "$TC/usr/share/swift/SwiftConstantValues/AppIntents.json"
  echo "$PWD/$INTENTS/Tablet.swiftconstvalues" > "$INTENTS/constvals.txt"
  find "$PWD/Sources" -name '*.swift' > "$INTENTS/sources.txt"
  "$TC/usr/bin/appintentsmetadataprocessor" --output "$INTENTS/out" --toolchain-dir "$TC" --module-name Tablet \
    --sdk-root "$(xcrun --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
    --platform-family macOS --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
    --source-file-list "$INTENTS/sources.txt" --swift-const-vals-list "$INTENTS/constvals.txt" \
    --binary-file .build/release/Tablet --no-app-shortcuts-localization 2>&1 | grep -v "^20.*appintentsmetadataprocessor" || true
else
  swift build -c release
fi
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
cp -R Resources/en.lproj Resources/cs.lproj "$APP/Contents/Resources/"
[[ -d "$INTENTS/out/Metadata.appintents" ]] && cp -R "$INTENTS/out/Metadata.appintents" "$APP/Contents/Resources/"

# Control Center / menu bar controls (WidgetKit extension, macOS 26+). Optional: skipped when the SDK is older.
CTL="$APP/Contents/PlugIns/TabletControls.appex"
mkdir -p "$CTL/Contents/MacOS"
if xcrun swiftc -parse-as-library -application-extension -target "$(uname -m)-apple-macos26.0" -sdk "$(xcrun --show-sdk-path)" -O \
     Extensions/Controls/Controls.swift -o "$CTL/Contents/MacOS/TabletControls" 2>/dev/null; then
  cat > "$CTL/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.zdeko.tablet.controls</string>
  <key>CFBundleName</key><string>Tablet</string>
  <key>CFBundleDisplayName</key><string>Tablet</string>
  <key>CFBundleExecutable</key><string>TabletControls</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>APP_VERSION</string>
  <key>CFBundleVersion</key><string>APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>CFBundleDevelopmentRegion</key><string>cs</string>
  <key>NSExtension</key>
  <dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict>
</plist>
PLIST
  cp -R Resources/en.lproj Resources/cs.lproj "$CTL/Contents/Resources/" 2>/dev/null || { mkdir -p "$CTL/Contents/Resources"; cp -R Resources/en.lproj Resources/cs.lproj "$CTL/Contents/Resources/"; }
else
  rm -rf "$APP/Contents/PlugIns"
fi

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
  <key>OTDVersion</key><string>OTD_VERSION_PLACEHOLDER</string>
  <key>CFBundleShortVersionString</key><string>1.3.1</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleDevelopmentRegion</key><string>cs</string>
  <key>CFBundleLocalizations</key><array><string>cs</string><string>en</string></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>local.zdeko.tablet</string>
    <key>CFBundleURLSchemes</key><array><string>tablet</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>local.zdeko.tablet.settings</string>
    <key>UTTypeDescription</key><string>Tablet Settings</string>
    <key>UTTypeConformsTo</key><array><string>com.apple.property-list</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>tabletsettings</string></array></dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Tablet Settings</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>local.zdeko.tablet.settings</string></array>
  </dict></array>
</dict>
</plist>
PLIST
sed -i '' "s/OTD_VERSION_PLACEHOLDER/$OTD_VERSION/" "$APP/Contents/Info.plist"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
[[ -f "$CTL/Contents/Info.plist" ]] && sed -i '' "s/APP_VERSION/$APP_VERSION/;s/APP_BUILD/$APP_BUILD/" "$CTL/Contents/Info.plist"

# Ad-hoc signature with a designated requirement on the bundle id only, so macOS keeps the
# Input Monitoring / Accessibility permissions across rebuilds (default ad-hoc pins the exact build).
xattr -cr "$APP"   # downloaded files carry quarantine/Finder attributes that codesign rejects
codesign --force --sign - --identifier net.opentabletdriver.daemon "$APP/Contents/Helpers/OpenTabletDriver.Daemon"
if [[ -d "$CTL" ]]; then
  cat > "$STAGE/controls.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
ENT
  codesign --force --sign - --identifier local.zdeko.tablet.controls --entitlements "$STAGE/controls.entitlements" \
    --requirements '=designated => identifier "local.zdeko.tablet.controls"' "$CTL"
fi
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
