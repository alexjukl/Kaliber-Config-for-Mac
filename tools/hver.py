"""Probe for the Kaliber HVER PRO X (GKB730, SONiX 0C45:8503). Read-only unless you call write_*."""
import hid, ctypes, time, sys

VID, PID = 0x0C45, 0x8503

def hx(b): return " ".join(f"{x:02x}" for x in b)

class Hver:
    def __init__(self):
        try: ctypes.CDLL(hid.__file__).hid_darwin_set_open_exclusive(0)
        except AttributeError: pass
        path = [d for d in hid.enumerate(VID, PID) if d["usage_page"] == 0xFF1C][0]["path"]
        self.h = hid.device(); self.h.open_path(path); self.h.set_nonblocking(1)

    def close(self): self.h.close()

    def packet(self, cmd, data=b"", addr=0, length=None):
        p = bytearray(64); p[0] = 4; p[3] = cmd
        p[4] = len(data) if length is None else length
        p[5] = addr & 0xFF; p[6] = (addr >> 8) & 0xFF; p[7] = 0
        p[8:8+len(data)] = data
        s = sum(p[3:64]); p[1] = s & 0xFF; p[2] = (s >> 8) & 0xFF
        return bytes(p)

    def xfer(self, cmd, data=b"", addr=0, length=None, timeout=1.0):
        """Send one packet, wait for the reply with the same command byte. Returns the 63-byte reply payload."""
        pkt = self.packet(cmd, data, addr, length)
        while self.h.read(64): pass          # drain
        n = self.h.write(pkt)
        assert n == 64, f"write returned {n}: {self.h.error()}"
        t0 = time.time()
        while time.time() - t0 < timeout:
            r = self.h.read(64)
            if r:
                r = bytes(r)
                if r[0] == 4 and r[3] == cmd:
                    if r[7] in (0xFF, 0xFE): raise RuntimeError(f"cmd 0x{cmd:02x} failed, status 0x{r[7]:02x}: {hx(r[:12])}")
                    return r
            time.sleep(0.005)
        raise TimeoutError(f"no reply to cmd 0x{cmd:02x}")

    def read_info(self):           # 0x03: 44-byte struct
        return self.xfer(0x03, length=0x2c)[8:8+0x2c]

    def read_mem(self, addr, n):   # 0x05
        out = b""
        while len(out) < n:
            chunk = min(0x38, n - len(out))
            r = self.xfer(0x05, addr=addr + len(out), length=chunk)
            out += r[8:8+chunk]
        return out

    def read_profile_keys(self, profile):   # 0x07, 378 bytes
        out = b""
        while len(out) < 0x17A:
            chunk = min(0x38, 0x17A - len(out))
            r = self.xfer(0x07, addr=profile * 0x17A + len(out), length=chunk)
            out += r[8:8+chunk]
        return out

    def read_default_keys(self):            # 0x0f
        out = b""
        while len(out) < 0x17A:
            chunk = min(0x38, 0x17A - len(out))
            r = self.xfer(0x0F, addr=len(out), length=chunk); out += r[8:8+chunk]
        return out

    def read_led_page(self, page, key0=0, n=0x38):   # 0x10
        r = self.xfer(0x10, addr=page * 0x200 + key0 * 3, length=n); return r[8:8+n]

    # ---- writes (vendor wraps every change in begin 0x01 ... end 0x02) ----
    def begin(self): self.xfer(0x01)
    def end(self): time.sleep(0.01); self.xfer(0x02)
    def write_mem(self, addr, data):        # 0x06, <=56 bytes per packet
        for i in range(0, len(data), 0x38):
            self.xfer(0x06, data=bytes(data[i:i+0x38]), addr=addr + i)

    def write_led_page(self, page, data):   # 0x11, addr = page*0x200 + key*3, 18 keys per packet
        for i in range(0, len(data), 0x36):
            self.xfer(0x11, data=bytes(data[i:i+0x36]), addr=page * 0x200 + i)

if __name__ == "__main__":
    k = Hver()
    info = k.read_info(); print("info (0x03):", hx(info))
    mem = k.read_mem(0, 3 * 0x2A)
    for p in range(3): print(f"profile{p} block:", hx(mem[p*0x2A:(p+1)*0x2A]))
    k.close()
