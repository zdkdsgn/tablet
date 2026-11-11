# Tablet

**English** · [Čeština](README.cs.md)

A native macOS app that brings the **Wacom Intuos Pro M (PTH-651)** graphics tablet back to life on current
versions of macOS, which Wacom no longer supports with a driver. At a basic level it also works with other
tablets that OpenTabletDriver supports.

## Installation

Download `Tablet-x.y.dmg` from [Releases](https://github.com/zdkdsgn/tablet/releases) and drag Tablet into
Applications. On first launch, open **System Settings → Privacy & Security** and click **Open Anyway**
(the app is not notarised by Apple). Then allow Tablet under **Accessibility** and **Input Monitoring**.

![icon](Resources/icon.png)

## How it works

- The pen and ExpressKeys are handled by the **OpenTabletDriver** daemon, which is **bundled inside the app**
  (`Tablet.app/Contents/Helpers/OpenTabletDriver.Daemon`). You don't need to install OpenTabletDriver separately.
  If you have it, Tablet stops its daemon on launch and starts its own, so only one driver talks to the tablet.
- **Tablet** replaces OpenTabletDriver's settings window: it writes `settings.json`
  (`~/Library/Application Support/OpenTabletDriver`) and hands it straight to the daemon over its JSON-RPC socket
  (`$TMPDIR/CoreFxPipe_OpenTabletDriver.Daemon`, method `SetSettings`).
- The Touch Ring, its button and the lights are handled by Tablet directly through IOKit HID. It doesn't seize the
  device, so OpenTabletDriver keeps working.

## Features

- **Tablet:** a drawing of the tablet with labels. ExpressKeys get shortcuts recorded by pressing them (physical
  keys, so they work with any keyboard layout, e.g. Czech QWERTZ), mouse clicks and custom names.
  Optionally an on-screen notice appears when a key is pressed. Instead of a shortcut a key can have an
  **app function**:
  - **Precision mode:** while you hold the key, the pen moves more finely.
  - **Next display:** switches which display the tablet maps to.
  - **Radial menu:** hold the key, pick one of 8 actions with the pen and release the key.
- **Touch Ring:** smooth zoom towards the cursor (fine scrolling with ⌥ or ⌘ depending on the app). The centre
  button cycles the chosen modes (up to 4, one per light): Zoom, Brush size, History, Scroll and
  Rotate canvas (Photoshop). Accidental ring touches while pressing the centre button are ignored.
- **Lights:** ring lights and the four area corner lights (brightness, on/off, breathing) and animations.
  An easter egg unlocks when you hold the ring's centre button.
- **Pen:** a **pressure curve** (graph with a draggable point, Soft / Linear / Firm presets, "full pressure at"),
  **stroke smoothing**, precision mode settings, a test pad with a pressure meter, tip threshold, pressure and
  tilt on/off, and the pen buttons and eraser. Tablet applies the curve, smoothing and precision mode to the
  driver's pen events (event tap), so they work in every app.
- **Screen edges:** the pen cursor stays inside the screen and "pushes" outward at the edge, so an auto-hidden
  Dock appears with the pen too, and the cursor doesn't flicker.
- **Area & display:** display choice, a tablet area you move by dragging, keep aspect ratio and a left-handed mode.
- **Presets:** saved setups that switch automatically with the app in front. Open at login.
- **Touch:** trackpad-like gestures. Implemented, but on the tested unit the touch layer sends no data, so it is
  not verified.
- **Express View:** resting a finger on the ExpressKeys shows what every key does, next to the screen edge
  (key touches are reported in byte 5 of the pad report).
- **Touch-sensitive keys:** sliding a finger along a group of four ExpressKeys works as a slider (brush size,
  history, zoom, scroll, custom shortcuts). The lights can stay dimmed when idle and light up when touched.
- **Menu bar icon:** connection status, ring mode, presets and quick toggles.
- **Driver check:** once a day it checks whether a newer OpenTabletDriver has been released.
- **Tap / hold and combinations:** an ExpressKey can send one shortcut on a tap and hold other keys down while held
  (⌥ for the eyedropper, Space for the hand). Two such keys pressed together can send a third shortcut.
- **Eraser switching:** flipping the pen sends the app's eraser key, flipping back sends the brush key
  (the tool ID comes from the pen's proximity report).
- **Map to window:** a key, menu toggle or shortcut maps the tablet to the front window only; again = whole screen.
- **Where you draw:** a heat map of your strokes on the tablet area and a suggested smaller, more precise area.
- **Ring per app, volume, brightness, acceleration:** the ring mode switches with the app in front; extra modes
  for Mac volume and display brightness; faster turns take bigger steps.
- **Light alerts and breaks:** the lights flash on low battery, after a long drawing session (counting only time
  with the pen in hand) or when anything sends `tablet://notify?title=…`.
- **Shortcuts, Siri and Control Center:** Tablet's actions (ring mode, precision, map to window, flash the lights)
  are in the Shortcuts app, and `tablet://` links work from anywhere (`open -g tablet://ring/brush`). Controls for
  Control Center / the menu bar on macOS 26+.
- **Backup:** all settings and presets in one `.tabletsettings` file.
- **Updates:** Tablet checks GitHub Releases, verifies the DMG's SHA-256 and replaces itself.
- **Pen identity and per-pen settings:** each pen is recognised by its serial number and can keep its own pressure
  curve, buttons and tap settings.
- **Tap sensitivity and calm tap:** a tip threshold slider with a live meter of your last tap, and a calm tap that
  holds the cursor still for a moment after the tip touches down, so a tap clicks instead of dragging.
- **Notch island (MacBooks with a notch):** the pen's live tilt from the side and from above while the pen is over
  the tablet, stats when you move the pen into the notch, milestones and achievements.
- **Odometer and achievements:** how far the pen has travelled today and in total, with funny comparisons and
  22 achievements (some secret).
- **Strokes:** every stroke of the day on white paper, with replay, colour by time and PNG export (kept for 30 days).
- **Wireless kit:** battery level in the sidebar and menu bar, notices at 15 % and 5 % and when charging or
  charged, and a battery saver that turns the lights off after 30 s without work.
- **Touch:** contact size, palm rejection by size and the side touch switch.
- **Area screen:** device previews with a live pen dot, real 1:1 size, arrow-key nudging and undo with ⌘Z.
- **Appearance:** light, dark or following macOS.
- **Setup guide:** permissions, monitor and pen sensitivity step by step on first launch (Obecné → Průvodce
  nastavením, or `tablet://setup`).
- **Help and diagnostics:** in-app help (⌘?) with tablet tips, shortcuts and `tablet://` links; "Save diagnostics…"
  packs the logs, driver settings and app state into one .zip for a bug report (nothing is sent anywhere).
- **Homebrew:** `brew install --cask zdkdsgn/tap/tablet` (cask in `Casks/tablet.rb`).
- **Language:** Czech and English, following the macOS language. Translations live in `Resources/en.lproj`
  and are generated by `Resources/translations-en.py`.

### Supported tablets

| Level | Tablets | Features |
|---|---|---|
| Enhanced | Intuos Pro 2013 (PTH-451/651/851), Intuos5 (PTK-450/650/850, PTH-450/650/850) | everything above |
| Basic | other tablets supported by OpenTabletDriver | pen, pressure curve, smoothing, area, display, ExpressKeys and wheel through OpenTabletDriver, presets |

Only verified with the PTH-651. Reports about other tablets are welcome.

## Building

You need macOS 14 or later and Xcode (or the Command Line Tools with Swift 5.10 or later).

```bash
./make-app.sh            # downloads and verifies OpenTabletDriver (first time only) and builds build/Tablet.app
./make-app.sh --install  # and copies it to /Applications
./make-dmg.sh            # installer build/Tablet-<version>.dmg
```

With Xcode installed, `make-app.sh` also extracts the App Intents metadata (Shortcuts / Siri actions) and builds
the Control Center extension (`Extensions/Controls`). With the Command Line Tools only, the app builds without them
and `tablet://` links still work.

The app is ad-hoc signed with a designated requirement bound only to the bundle identifier, so macOS keeps the
granted permissions across rebuilds. You can change the identifier in `make-app.sh`.

`swift test` runs the tests (HID report decoding on real reports from the tablet, the stroke and tap files,
version comparison, the pressure curve, and a check that every Czech UI text has an English translation).
`make-dmg.sh` builds a release only when they pass. English strings are generated from
`Resources/translations-en.py` on every build.

### Signing and notarisation (optional)

With an Apple Developer account the app can be signed with a Developer ID and notarised, so it opens without
"Open Anyway":

```bash
xcrun notarytool store-credentials tablet-notary --apple-id you@example.com --team-id TEAMID   # once
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=tablet-notary ./make-dmg.sh
```

The driver is signed with the hardened runtime and the JIT entitlements .NET needs. Without `SIGN_IDENTITY`
the build stays ad hoc, as before.

### Permissions (System Settings → Privacy & Security)

- **Accessibility:** posting events (zoom, keys, cursor).
- **Input Monitoring:** reading the ring, keys and touch from the tablet.

## Hardware notes (PTH-651, USB 056A:0315)

- Pad reports (report ID 3, pen interface 0xFF0D): byte 2 = Touch Ring (bit 7 = finger on the ring,
  values 0–71), byte 3 bit 0 = centre button, byte 4 = ExpressKeys pressed, byte 5 = ExpressKeys touched.
- Lights: feature report `0x20`, byte 1 = `corner_brightness << 4 | ring_brightness << 2 | led`. Brightness 0 is low,
  1 medium, 2 high and 3 off. This is what Linux's `wacom` driver does too. The LEDs re-apply late after each
  report, so fast dithering between levels flickers; fades are shown as stepped levels.
- Pen: report ID 2; `[1] & 0xFC == 0xC0` is "tool entered proximity" with the tool ID, bit 3 set = eraser.
- Touch: interface 0xFF00, 64-byte reports (report ID 2).

## Licence

The app's code is MIT-licensed. [OpenTabletDriver](https://github.com/OpenTabletDriver/OpenTabletDriver) is a separate
project under LGPL-3.0. This repository doesn't contain it: `make-app.sh` downloads its official release (version and
SHA-256 are in the script) and bundles the unmodified daemon together with its licence
(`Contents/Resources/OpenTabletDriver-LICENSE.txt`). The daemon can be replaced with another version at any time.
