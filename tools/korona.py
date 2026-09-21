"""Minimal KORONA (Sinowealth 258a:1007, FwProtocol 7) transport + codec for probing."""
import hid, ctypes, time

VID, PID = 0x258A, 0x1007
GENERAL_LEN, MODE_LEN, MATRIX_LEN = 58, 8, 1144


def hx(b):
    return " ".join(f"{x:02x}" for x in b)


class Korona:
    def __init__(self):
        try:
            ctypes.CDLL(hid.__file__).hid_darwin_set_open_exclusive(0)
        except AttributeError:
            pass
        path = [d for d in hid.enumerate(VID, PID) if d["usage_page"] == 0xFF00][0]["path"]
        self.h = hid.device()
        self.h.open_path(path)

    def close(self):
        self.h.close()

    def get(self, rid, n):
        for attempt in range(5):
            r = bytes(self.h.get_feature_report(rid, n + 1))
            if len(r) == n + 1 and r[0] == rid:
                return r[1:]
            time.sleep(0.1)
        raise RuntimeError(f"GetFeature 0x{rid:02x}: bad reply {hx(r[:4])}")

    def set(self, rid, payload):
        buf = bytes([rid]) + bytes(payload)
        for attempt in range(3):
            n = self.h.send_feature_report(buf)
            if n == len(buf):
                time.sleep(0.05)  # vendor app settles 20 ms after every transfer
                return True
            time.sleep(0.2)
        raise RuntimeError(f"SetFeature 0x{rid:02x} failed: {self.h.error()}")

    def general(self):
        return self.get(0x04, GENERAL_LEN)

    def write_general(self, payload):
        assert len(payload) == GENERAL_LEN
        return self.set(0x04, payload)

    def mode(self):
        return self.get(0x08, MODE_LEN)

    def write_mode(self, payload):
        assert len(payload) == MODE_LEN
        return self.set(0x08, payload)

    def matrix(self):
        return self.get(0x06, MATRIX_LEN)

    def write_matrix(self, payload):
        assert len(payload) == MATRIX_LEN
        return self.set(0x06, payload)


def describe_general(g):
    print(" current DPI level :", g[0] >> 4)
    print(" mode / stages     :", g[1] >> 4, "/", g[1] & 0xF)
    print(" sensor code / XY  :", g[2] >> 4, "/", g[2] & 1)
    stages = [((v & 0x7F) + 1) * 100 if not v & 0x80 else f"off({((v&0x7f)+1)*100})" for v in g[4:12]]
    print(" DPI stages        :", stages)
    print(" LED mode/param    :", g[20] >> 4, "/", g[20] & 0xF, " byte21=0x%02x" % g[21])
    print(" LED colours       :", [hx(g[22 + 3 * i:25 + 3 * i]) for i in range(7)])
    print(" DPI colour codes  :", list(g[43:51]))
    print(" flags             : 0x%02x" % g[51], " fw:", g[52:58].decode("ascii", "replace"))
