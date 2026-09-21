# Kaliber Config for macOS

An unofficial, native macOS configurator for two Kaliber Gaming (IOGEAR) devices that only
ship with Windows software:

* **KORONA RGB gaming mouse (GME631)** — DPI stages (up to 8, 200–5000 DPI, per-stage indicator
  colour), polling rate, 11 lighting effects with colours/speed/brightness, all 7 buttons
  (mouse functions, DPI, keyboard keys, key combos, multimedia, macros, fire key, RGB toggle),
  8 macro slots with a recorder, backup/restore to JSON, factory defaults.
* **HVER PRO X keyboard (GKB730-BN)** — the three on-board profiles: 19 lighting patterns with
  brightness, speed, direction and colour, per-key "Custom" colours (3 sets per profile, painted
  on a key grid), active-profile switch, USB report rate, remapping of any key to any standard
  key (with factory-layout restore), backup/restore.

Both screens have a live preview pane (on the tabs that have something to show) that renders the
pending lighting, DPI indicator or button/key assignments before you press Apply.

Everything the app writes was reverse-engineered from IOGEAR's own tools and verified on the
hardware; unknown bytes are always read from the device and written back unchanged.
Protocol notes: [docs/PROTOCOL-mouse.md](docs/PROTOCOL-mouse.md),
[docs/PROTOCOL-keyboard.md](docs/PROTOCOL-keyboard.md).

## Install (pre-built)

Download `KaliberConfig.app.zip` from the [Releases](../../releases) page, unzip, and on first
launch right-click → **Open** (the build is not notarized; macOS shows an "unidentified
developer" warning once). Then grant Input Monitoring when asked — see below.

## Build & run

Requirements: macOS 14+, Xcode 15+ command-line tools (tested with Xcode 27 on macOS 26).

```bash
cd KaliberConfig && ./scripts/bundle.sh        # builds dist/KaliberConfig.app
open ../dist/KaliberConfig.app
```

`swift test` runs the codec tests (they replay real report dumps from `tools/dumps/`).
`Package.swift` also opens directly in Xcode.

### Input Monitoring permission

Both devices expose their configuration channel on a USB interface that macOS classes as a
keyboard, so the app must be allowed under **System Settings → Privacy & Security → Input
Monitoring**. The app asks on first launch; it never reads keystrokes. The bundle is signed
with a self-signed certificate named "Kaliber Config Local" if one exists in your keychain
(`bundle.sh` looks it up; create one in Keychain Access → Certificate Assistant, type "Code
Signing") so the permission survives rebuilds. Otherwise the bundle is ad-hoc signed and macOS
forgets the grant after every rebuild — reset it with
`tccutil reset ListenEvent com.alexjukl.kaliberconfig` and re-allow.

## Layout

```
KaliberConfig/            Swift package: KaliberHID (IOKit transport + codecs), KaliberConfig (SwiftUI app), tests
tools/                    Python probes used during reverse engineering (hidapi); dumps/ holds device snapshots
docs/                     protocol write-ups and the vendor UI text extracted from the Windows tools
extracted/ (git-ignored)  the Windows installers, unpacked
```

## Known gaps / unverified

* Mouse: "Polling rate switch", "Mode switch" and "Next RGB effect" button codes come from the
  vendor binary but could not be confirmed on this firmware (XCQ501); scroll-down code unknown.
  DPI lock and XY-independent DPI are not exposed.
* Keyboard: report-rate byte mapping and direction values follow the vendor UI but were not
  visually verified; macros and media/Fn-layer key functions are not implemented yet (the
  commands are documented). Fn+PgUp/PgDn brightness changes are volatile
  and do not show up in the app.
* The firmware-update ("enter bootloader") command exists in the keyboard protocol and is
  deliberately never sent.

## Contributing / other devices

Issues and pull requests are welcome. Both devices are generic OEM designs (Sinowealth "BY8832"
mouse firmware, SONiX keyboard firmware) that other brands sell under different names; if you
have a similar device, the probes in `tools/` (`probe_mouse.py`, `hver.py`) dump the reports the
app relies on — attach such a dump to an issue. Keep every write behind a read-first / restore
path as the existing code does, and never send the keyboard's `EE EE` bootloader packet.

## Legal

This is an independent project, not affiliated with or endorsed by IOGEAR, Kaliber Gaming,
Sinowealth or SONiX. Product names are trademarks of their owners. The protocols were
reverse-engineered for interoperability; IOGEAR's software is not included in this repository.
Use at your own risk — the app only writes the same settings blocks the vendor tools write, but
no warranty is given (see LICENSE).
