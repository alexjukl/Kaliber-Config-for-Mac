# Kaliber Gaming KORONA (GME631) — HID protocol

Reverse-engineered from IOGEAR's `GME631_SW_V1.0.6` (`OemDrv.exe`, Sinowealth "BY8832"
OEM tool, `FwProtocol=7`, `Apply_M_AJ_8832_3`) and verified on hardware
(firmware string `XCQ501`). Not official.

USB: VID `0x258A` (SINOWEALTH), PID `0x1007`, product "Game Mouse".
Interface 1 carries a vendor collection (usage page `0xFF00`, usage 1). On macOS the
IOHIDDevice for that interface is a *keyboard-class* device, so opening it needs the
**Input Monitoring** permission (TCC). Open it non-exclusively.

Wait ~20 ms after every transfer (the vendor tool does); reading immediately after a
write can return a garbled report.

| Report | Type | Payload | Purpose |
|---|---|---|---|
| `0x04` | feature get/set | 58 B | "general data": DPI stages, LED, DPI colours |
| `0x08` | feature get/set | 8 B | "mode": active mode + polling rate per mode; byte 4 on read = live DPI level |
| `0x06` | feature get/set | 1144 B | macro slots + button matrix |
| `0x07` | input | 4 B | notification (seen `01 b1 03 00` when the RGB on/off button was pressed) |
| `0x05` | feature | 5 B | **STALLs** on this firmware — the Glorious-style command channel is not used |

## Report 0x04 — general data (58 bytes, payload offsets)

| Off | Meaning |
|---|---|
| 0 | hi nibble: DPI level the *host* wants (not live; see 0x08[4]) |
| 1 | hi nibble: active mode (1–3, written by host), lo nibble: number of enabled DPI stages |
| 2 | hi nibble: sensor code (`0xB` = PMW3325 → sensor table in `Cfg.ini`), bit 0: XY-independent DPI |
| 3 | `HandOft` byte (unused here, 0) |
| 4–19 | 8 DPI stages, one byte each (16 bytes reserved; with XY-independent, X,Y pairs). Value = `DPI/100 − 1` (200→1 … 5000→49; 5500→50, 6000→51 … 10000→59 per `DPISET`/`DPIHW`). Bit 7 set = stage disabled. Unused stages are `0x80`. |
| 20 | hi nibble: LED mode 1–11 (0 = off), lo nibble: speed (1–3) for animated modes, brightness code 1–8 for Steady |
| 21 | Breathing (3): colour count; Colorful Streaming (1) / Streaming (9): `0x80` = reverse direction; Response (8): `0x80` = random colour, else colour count; otherwise 0 |
| 22–42 | up to 7 colours, **R,G,B** each (verified on hardware) |
| 43–50 | 8 per-stage DPI indicator colour codes: 0 off, 1 red, 2 green, 3 blue, 4 cyan, 5 yellow, 6 magenta, 7 white |
| 51 | flags: bit 0 = "LED indicator" option, bit 1 = LED off, bit 5 always set (`0x20`) |
| 52–57 | firmware/product string, ASCII (`XCQ501`), echoed back on write |

LED modes (vendor names): 1 Colorful Streaming, 2 Steady, 3 Breathing, 4 Tail, 5 Neon,
6 Colorful Steady, 7 Flicker, 8 Response, 9 Streaming, 10 Wave, 11 Trailing, 0/12 Off.
Steady brightness codes 1–8 map to vendor slider values 0x05,0x15,…,0x75 (9 = default).

Writing: read the report, change fields, write the whole 58 bytes back (report id `0x04`).
The device stores it in flash immediately. Verified: DPI stage write, LED off, Steady
colour + brightness, restore.

## Report 0x08 — mode / polling ("SetMode")

Write `[mode(1–3), rate_mode1, rate_mode2, rate_mode3, 0, 0, 0, 0]` with rate codes
1 = 125 Hz, 2 = 250 Hz, 3 = 500 Hz, 4 = 1000 Hz. The vendor tool sets `[4]=target
mode, [5]=3, [6]=1` for a "reset to mode" operation. On **read**, byte 4 is the current
DPI level (1-based) and updates live when the DPI buttons are used; bytes 5–7 echo the
last write.

## Report 0x06 — macros + button matrix (1144 bytes)

* `[0..1023]` — 8 macro slots × 128 bytes (`MacProtocol=2`):
  `[0..1]` repeat count big-endian (0 → `00 01`), then events from `[2]`:
  2-byte event `[flags|delay, usage]` with flags bit 7 = release, delay 1–127 ms (0 → 1);
  delays > 127 ms use the 4-byte form `[flags|delay%100, usage, delay/100, 0x03]`.
  Usage: HID keyboard usage, modifiers `0xE0` Ctrl, `0xE1` Shift, `0xE2` Alt, `0xE3` GUI,
  mouse `0xF0` left, `0xF1` right, `0xF2` middle. Terminated by `00 00`.
* `[1024..1143]` — 3 modes × 10 buttons × `uint32 LE`; value = `hw_code | button_index(1–10)`
  in the low nibble; bits 12–15 = macro slot (1–8) for macro codes.

Hardware codes (low nibble is replaced by the button index):

| Code | Function | Notes |
|---|---|---|
| `0xF010` | Left click | `0xF0` + button bit index: 0 L, 1 R, 2 M, 3 button4 (back), 4 button5 (forward) |
| `0xF110` | Right click | |
| `0xF210` | Middle click | |
| `0xF310` | Button 4 (back) | |
| `0xF410` | Button 5 (forward) | |
| `0x0232F020` | Double click | fire-type: count 2, interval 0x32, button L |
| `0x??8040` | Fire key | `((rate_code & 0xF) << 8) | 0x8040` |
| `0x0130` | Scroll up (vendor code 0x17) | scroll down unverified |
| `0x0150` | Disabled | factory default for unused slots and modes 2/3 |
| `0x0040` | DPI loop | **verified** (live level cycles) |
| `0x2040` | DPI + | factory button 6 |
| `0x4040` | DPI − | factory button 7 |
| `0x0250` | RGB on/off | **verified** (flags bit 1 toggles) |
| `0x0650` | Polling rate switch | unverified (no visible/reported change) |
| `0x0450` | Mode switch | unverified |
| `0x0750` | RGB switch (next LED mode) | unverified |
| `0x??0020` | Keyboard key | `[0x20, usage, modifier, 0]` bytes LE → `usage<<8 | mod<<16 | 0x20` |
| `0x????0060` | Key combination | `[0x60, modifier mask, key1 usage, key2 usage]` |
| `0x????0070` | Multimedia | `[0x70, consumerA, consumerB, browser]` bit masks, see below |
| `0x0190` / `0x0290` / `0x0490` | Macro: repeat N / until released / until any key | slot in bits 12–15 |
| `0x??00 \| value` | DPI lock (vendor 0xAD) | raw DPI code `<< 8`?, unverified |

Multimedia masks: byte1 (consumer): next 0x01, previous 0x02, stop 0x04, play/pause 0x08,
mute 0x10, vol+ 0x40, vol− 0x80; byte2: media player 0x01, explorer 0x02, e-mail 0x10,
calculator 0x20; byte3 (browser): search 0x01, home 0x02, back 0x04, forward 0x08,
stop 0x10, refresh 0x20, favourites 0x40.

Modifier mask: 0x01 Ctrl, 0x02 Shift, 0x04 Alt, 0x08 Win (left-hand only).

Apply order used by the vendor: general (0x04) → mode (0x08) → matrix (0x06), 20 ms apart.
Each is independently effective on this firmware (verified individually).
