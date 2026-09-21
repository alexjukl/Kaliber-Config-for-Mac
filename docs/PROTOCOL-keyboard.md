# Kaliber Gaming HVER PRO X (GKB730) — HID protocol

Reverse-engineered from IOGEAR's `GKB730-BN_Setup` (`KG HVER PRO X.exe` + `HidServ.dll`) and
verified on hardware (lighting mode/colour/brightness writes). Not official.

USB: VID `0x0C45` (SONiX), PID `0x8503`, product "USB DEVICE". Interface 1 exposes a vendor
collection (usage page `0xFF1C`, usage `0x92`) with **report ID 4**: 63-byte output + 63-byte
input reports. macOS classes the interface as a keyboard → Input Monitoring permission needed.

## Packet (64 bytes incl. report ID, both directions)

| Off | Meaning |
|---|---|
| 0 | `0x04` report ID |
| 1–2 | checksum: 16-bit little-endian sum of bytes 3..63 |
| 3 | command |
| 4 | data length (≤ 0x38 = 56) |
| 5–6 | address / offset, little-endian |
| 7 | status: 0 in requests; in replies `0xFF`/`0xFE` = error |
| 8–63 | data |

Send the output report, then read input reports until one arrives with the same command
byte. The vendor tool retries 3× with a 1 s timeout.

| Cmd | Meaning |
|---|---|
| `0x01` | begin transaction (vendor sends before every write) |
| `0x02` | end / commit (after every write; small delay first) |
| `0x03` | read 44-byte info block (len `0x2C`) |
| `0x04` | write the 44-byte info block |
| `0x05` | read `len` bytes of the settings area at `addr` |
| `0x06` | write `len` bytes of the settings area at `addr` |
| `0x07` | read key map: 378 bytes per profile at `addr = profile*378` (56-byte chunks) |
| `0x08` | write key map (same addressing) |
| `0x0A` | write macro area from address 0 (56-byte chunks) |
| `0x0F` | read the factory default key map (378 bytes) |
| `0x10` | read per-key colours: `addr = page*0x200 + led*3`, `page = profile*3 + set` |
| `0x11` | write per-key colours, same addressing, ≤ 54 bytes (18 keys) per packet |
| `0x0B`,`0x0C`,`0x0D`,`0x0E` | no-argument commands (unknown; not used) |
| `EE EE` at bytes 3–4 | **enter bootloader** (firmware update). Never sent by this app. |

## Info block (cmd 0x03/0x04, 44 bytes)

`aa 55 ff 02 | 45 0c | 03 85 | 02 01 | [10]=active profile (0–2) | 50 | 00 00 00 00 | 01 02 … 0f 11 10 12 14 | 00…`
Bytes 16–34 list the available lighting mode IDs. The vendor changes profiles by reading this
block, patching byte 10 and writing it back with `0x04`.

## Settings area (cmd 0x05/0x06): three 42-byte (0x2A) profile blocks at `profile*0x2A`

| Off | Meaning | Verified |
|---|---|---|
| 0 | lighting mode ID (see below) | yes |
| 1 | brightness 0–4 | 0 and 1 written, visibly dim/off |
| 2 | speed, wire 0 (fast) … 3 (slow); vendor slider shows it reversed | read only |
| 3 | direction: `0x00` / `0xFF` | read only |
| 4 | colour flag: `0x00` fixed colour, `0x01`/`0xFF` colourful / cycling | yes (0 with RGB) |
| 5–7 | R, G, B | yes |
| 8 | unknown (`0x08` on profiles 1–2) | |
| 0x0F | USB report rate index 0=125, 1=250, 2=500, 3=1000 Hz (vendor radio order) | unverified |
| 0x11 | unknown toggle (vendor UI checkbox) | |
| 0x12 | active per-key colour set (0–2) for mode 20 | yes |
| 0x13, 0x19–0x1C, 0x1E–0x21 | second/third light zone colour + flag (profile 0 addresses) | |

Fn shortcuts (Fn+PgUp/PgDn brightness) change the live state but are **not** written back to
this area.

Lighting mode IDs (`[MODE]` in Lang0409.ini): 1 Rainbow Ripple, 2 Rainbow Ebb and Flow,
3 Rainbow Rotation, 4 7-Colour Cycle, 5 Rainbow Breathing, 6 Rainbow Fixed, 7 Rainbow Following
Keys, 8 Rainbow Explosion Keys, 9 Rainbow Split Keys, 10 Rainbow Flash Keys, 11 Rainbow Pulse
Keys, 12 Falling Rainbow, 13 Rainbow Twist, 14 Rainbow Waves, 15 Rainbow Rain, 16 Rainbow Scan,
17 Fixed Single Colour, 18 Rainbow Eruption, 20 Custom (per-key).

## Key map (cmd 0x07/0x08/0x0F): 126 entries × 3 bytes, column-major 6 rows × 21 columns

Entry `[type, kind, code]`: `02 02 <HID usage>` normal key, `02 01 <bit>` modifier
(bit 0x01 Ctrl, 0x02 Shift, 0x04 Alt, 0x08 GUI, high nibble = right side), `00 00 00` no key.
Other `type` values (macro, media, function) exist in the vendor tool but are not decoded yet.
Factory map (matrix order, first entries): Esc, `, Tab, CapsLock, LShift, LCtrl, F1, 1, Q, A,
non-US-\, LGUI, F2, 2, W, S, …

## Per-key colours (cmd 0x10/0x11, pattern 20 "Custom")

Each profile has three 378-byte colour sets (pages `profile*3 + set`, 0x200 bytes apart, RGB per
key). The profile block byte `0x12` selects which set the Custom pattern shows. **LED index is
row-major** in the same 6×21 matrix as the key map: `led = row*21 + col` while the key map uses
`index = col*6 + row` (verified on hardware: Esc → 0, F1…F12 → 1…12, A → 64). IOGEAR pre-loads
patterns into all nine pages; writing a page takes effect immediately.
