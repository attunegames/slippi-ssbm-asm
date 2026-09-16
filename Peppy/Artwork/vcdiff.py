"""Decode a VCDIFF (RFC 3284) delta, which is what Slippi ships its game-file
patches as - open-vcdiff on the Dolphin side.

Only what those patches use: default code table, no secondary compression.
"""
import struct, sys

VCD_SOURCE, VCD_TARGET = 0x01, 0x02
NOOP, ADD, RUN, COPY = 0, 1, 2, 3

def default_code_table():
    t = []
    t.append((RUN, 0, 0, NOOP, 0, 0))
    for size in range(0, 18):
        t.append((ADD, size, 0, NOOP, 0, 0))
    for mode in range(0, 9):
        t.append((COPY, 0, mode, NOOP, 0, 0))
        for size in range(4, 19):
            t.append((COPY, size, mode, NOOP, 0, 0))
    for mode in range(0, 6):
        for asz in range(1, 5):
            for csz in range(4, 7):
                t.append((ADD, asz, 0, COPY, csz, mode))
    for mode in range(6, 9):
        for asz in range(1, 5):
            t.append((ADD, asz, 0, COPY, 4, mode))
    for mode in range(0, 9):
        t.append((COPY, 4, mode, ADD, 1, 0))
    assert len(t) == 256, len(t)
    return t

class Reader:
    def __init__(self, buf, pos=0):
        self.buf, self.pos = buf, pos
    def byte(self):
        b = self.buf[self.pos]; self.pos += 1; return b
    def varint(self):
        v = 0
        while True:
            b = self.byte()
            v = (v << 7) | (b & 0x7F)
            if not (b & 0x80):
                return v

class Cache:
    """Near/same address caches, sized as the RFC's defaults."""
    def __init__(self, near=4, same=3):
        self.s_near, self.s_same = near, same
        self.reset()
    def reset(self):
        self.near = [0] * self.s_near
        self.next = 0
        self.same = [0] * (self.s_same * 256)
    def update(self, addr):
        if self.s_near:
            self.near[self.next] = addr
            self.next = (self.next + 1) % self.s_near
        if self.s_same:
            self.same[addr % (self.s_same * 256)] = addr
    def decode(self, here, mode, addr_r):
        if mode == 0:
            a = addr_r.varint()
        elif mode == 1:
            a = here - addr_r.varint()
        elif mode < 2 + self.s_near:
            a = self.near[mode - 2] + addr_r.varint()
        else:
            m = mode - (2 + self.s_near)
            a = self.same[m * 256 + addr_r.byte()]
        self.update(a)
        return a

def decode(source, delta):
    table = default_code_table()
    r = Reader(delta)
    if r.byte() != 0xD6 or r.byte() != 0xC3 or r.byte() != 0xC4:
        raise SystemExit("not a VCDIFF file")
    r.byte()                    # version
    hdr = r.byte()
    if hdr & 0x01: r.byte()     # compressor id
    if hdr & 0x02: raise SystemExit("custom code table not supported")
    if hdr & 0x04:
        n = r.varint(); r.pos += n

    target = bytearray()
    while r.pos < len(delta):
        win = r.byte()
        src_len = src_pos = 0
        if win & (VCD_SOURCE | VCD_TARGET):
            src_len = r.varint(); src_pos = r.varint()
        r.varint()              # delta encoding length
        tgt_len = r.varint()
        if r.byte() != 0: raise SystemExit("compressed sections not supported")
        data_len, inst_len, addr_len = r.varint(), r.varint(), r.varint()
        data = Reader(delta, r.pos); r.pos += data_len
        inst = Reader(delta, r.pos); r.pos += inst_len
        addr = Reader(delta, r.pos); r.pos += addr_len

        base = source[src_pos:src_pos+src_len] if (win & VCD_SOURCE) else \
               bytes(target[src_pos:src_pos+src_len])
        here0 = len(target)
        out = bytearray()
        cache = Cache()
        while len(out) < tgt_len:
            idx = inst.byte()
            for (typ, size, mode) in ((table[idx][0], table[idx][1], table[idx][2]),
                                      (table[idx][3], table[idx][4], table[idx][5])):
                if typ == NOOP: continue
                if size == 0: size = inst.varint()
                if typ == ADD:
                    out += data.buf[data.pos:data.pos+size]; data.pos += size
                elif typ == RUN:
                    out += bytes([data.byte()]) * size
                else:
                    a = cache.decode(len(base) + len(out), mode, addr)
                    for _ in range(size):
                        out.append(base[a] if a < len(base) else out[a - len(base)])
                        a += 1
        target += out[:tgt_len]
    return bytes(target)

if __name__ == "__main__":
    src = open(sys.argv[1], "rb").read()
    dlt = open(sys.argv[2], "rb").read()
    res = decode(src, dlt)
    open(sys.argv[3], "wb").write(res)
    print("%s  %d bytes" % (sys.argv[3], len(res)))
