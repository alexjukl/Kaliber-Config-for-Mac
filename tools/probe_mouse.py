#!/usr/bin/env python3
"""Read-only probe for the Kaliber KORONA (Sinowealth 258a:1007) mouse.

Usage:
  probe_mouse.py dump [label]     # firmware + config/button dumps, saved to dumps/
  probe_mouse.py diff A B         # diff two saved .hex dumps
  probe_mouse.py raw <cmd-hex>    # send 05 <cmd> and read back 0x05/0x04/0x06 (read-only)
"""
import hid, sys, time, os, datetime

VID, PID = 0x258A, 0x1007
REPORT_CMD, REPORT_CFG, REPORT_LONG, REPORT_8 = 0x05, 0x04, 0x06, 0x08
CMD_SIZE = 6
HERE = os.path.dirname(os.path.abspath(__file__))
DUMPS = os.path.join(HERE, "dumps")


def open_vendor():
    # hidapi on macOS seizes devices by default; the keyboard interface is in use, so open shared.
    import ctypes
    try:
        ctypes.CDLL(hid.__file__).hid_darwin_set_open_exclusive(0)
    except AttributeError:
        pass
    for d in hid.enumerate(VID, PID):
        if d["usage_page"] == 0xFF00:
            h = hid.device()
            h.open_path(d["path"])
            return h
    raise SystemExit("vendor collection (usage page 0xFF00) not found - is the mouse plugged in?")


def hx(b):
    return " ".join(f"{x:02x}" for x in b)


def cmd(h, c, args=(0, 0, 0, 0)):
    buf = [REPORT_CMD, c, *args][:CMD_SIZE]
    buf += [0] * (CMD_SIZE - len(buf))
    h.send_feature_report(bytes(buf))
    time.sleep(0.05)


def get(h, rid, size):
    r = h.get_feature_report(rid, size)
    return bytes(r)


def dump_block(h, c, label):
    cmd(h, c)
    out = {}
    for rid, size in ((REPORT_CFG, 59), (REPORT_LONG, 1145)):
        try:
            out[rid] = get(h, rid, size)
        except Exception as e:
            out[rid] = None
            print(f"  [{label}] get report 0x{rid:02x} failed: {e}")
    return out


def save(name, data):
    os.makedirs(DUMPS, exist_ok=True)
    p = os.path.join(DUMPS, name)
    with open(p, "w") as f:
        for i in range(0, len(data), 16):
            f.write(f"{i:04x}: {hx(data[i:i+16])}\n")
    return p


def do_dump(label):
    h = open_vendor()
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    cmd(h, 0x01)
    fw = get(h, REPORT_CMD, CMD_SIZE)
    print("firmware reply:", hx(fw), "->", bytes(fw[2:6]).decode("ascii", "replace"))
    cmd(h, 0x02)
    prof = get(h, REPORT_CMD, CMD_SIZE)
    print("profile reply :", hx(prof))
    for c, what in ((0x11, "cfg-p1"), (0x12, "btn-p1"), (0x21, "cfg-p2"), (0x22, "btn-p2"), (0x31, "cfg-p3"), (0x32, "btn-p3")):
        blocks = dump_block(h, c, what)
        for rid, data in blocks.items():
            if data is None:
                continue
            # strip trailing zero padding for display only
            nz = len(data.rstrip(b"\x00"))
            print(f"cmd 0x{c:02x} ({what}) report 0x{rid:02x}: {len(data)} bytes, last non-zero @ {nz}")
            print("   ", hx(data[:64]))
            save(f"{ts}-{label}-{what}-r{rid:02x}.hex", data)
    try:
        r8 = get(h, REPORT_8, 9)
        print("report 0x08 :", hx(r8))
    except Exception as e:
        print("report 0x08 : failed", e)
    h.close()
    print("saved to", DUMPS)


def load(p):
    data = bytearray()
    for line in open(p):
        data += bytes.fromhex(line.split(":", 1)[1].replace(" ", ""))
    return bytes(data)


def do_diff(a, b):
    A, B = load(a), load(b)
    n = 0
    for i, (x, y) in enumerate(zip(A, B)):
        if x != y:
            print(f"  @{i:4d} (0x{i:03x}): {x:02x} -> {y:02x}")
            n += 1
    if len(A) != len(B):
        print("  length differs", len(A), len(B))
    print(f"{n} differing bytes")


def do_raw(c):
    h = open_vendor()
    cmd(h, int(c, 16))
    print("0x05:", hx(get(h, REPORT_CMD, CMD_SIZE)))
    for rid, size in ((REPORT_CFG, 59), (REPORT_LONG, 1145)):
        d = get(h, rid, size)
        nz = len(d.rstrip(b"\x00"))
        print(f"0x{rid:02x}: {hx(d[:96])} ... (last nz @ {nz})")
    h.close()


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] == "dump":
        do_dump(a[1] if len(a) > 1 else "dump")
    elif a[0] == "diff":
        do_diff(a[1], a[2])
    elif a[0] == "raw":
        do_raw(a[1])
    else:
        print(__doc__)
