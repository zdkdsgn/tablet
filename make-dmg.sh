#!/bin/zsh
# Builds Tablet.app and packs it into build/Tablet-<version>.dmg (drag-to-Applications installer).
set -euo pipefail
cd "$(dirname "$0")"

# a release is built only when the tests pass (report decoding, files, translations)
swift test --quiet
./make-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Tablet.app/Contents/Info.plist)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/tablet-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

ditto build/Tablet.app "$STAGE/Tablet.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Jak nainstalovat.txt" <<'TXT'
Tablet – nastavení pro Wacom Intuos Pro (a další tablety podporované OpenTabletDriverem)

1. Přetáhněte Tablet do složky Aplikace.
2. Při prvním spuštění macOS ohlásí, že aplikaci nelze ověřit (není podepsaná u Applu).
   Otevřete Nastavení systému → Soukromí a zabezpečení a klikněte na „Přesto otevřít“.
3. Povolte aplikaci Tablet v Soukromí a zabezpečení → Zpřístupnění a Sledování vstupu.

Ovladač OpenTabletDriver je součástí aplikace, nic dalšího instalovat nemusíte.
https://github.com/zdkdsgn/tablet

---

1. Drag Tablet to Applications.
2. On first launch macOS says the app cannot be verified (it is not notarised).
   Open System Settings → Privacy & Security and click "Open Anyway".
3. Allow Tablet in Privacy & Security → Accessibility and Input Monitoring.
TXT

DMG="build/Tablet-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Tablet $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
# Notarisation (once: xcrun notarytool store-credentials tablet-notary --apple-id … --team-id … ):
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=tablet-notary ./make-dmg.sh
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY (Developer ID)"; exit 1; }
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
shasum -a 256 "$DMG"
echo "Hotovo: $PWD/$DMG"
