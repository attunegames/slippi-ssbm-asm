"""Apply a Slippi .diff to a stock Melee file.

Slippi does not ship replacements for most of the files it changes - it ships
VCDIFF patches next to them, and Dolphin applies one to the copy off the disc
before the game ever sees it. So the file on the disc is NOT the file the game
loads, and any offset read out of the disc copy is wrong.

That cost a build: the stage picture's joint was found in the ISO's MnSlMap.usd,
636811 bytes, while the game loads the patched one at 659327 and the offsets
landed in the middle of something else.

    python vcdiff.py MnSlMap.usd MnSlMap.usd.diff out.usd

RFC 3284, default code table, no secondary compressor - which is what Slippi's
patches use, and the decoder refuses anything else rather than guessing.
"""
import argparse, sys

NOOP, ADD, RUN, COPY = 0, 1, 2, 3


def code_table():
    """The default table, built the way RFC 3284 section 5.4 lays it out."""
    t = []
    t.append((RUN, 0, 0, NOOP, 0, 0))                       # 0
    for size in [0] + list(range(1, 18)):                   # 1..18
        t.append((ADD, size, 0, NOOP, 0, 0))
    for mode in range(9):                                   # 19..162
        for size in [0] + list(range(4, 19)):
            t.append((COPY, size, mode, NOOP, 0, 0))
    for mode in range(7):                                   # 163..246
        for asz in range(1, 5):
            for csz in range(4, 7):
                t.append((ADD, asz, 0, COPY, csz, mode))
    for mode in range(9):                                   # 247..255
        t.append((COPY, 4, mode, ADD, 1, 0))
    assert len(t) == 256, len(t)
    return t


class Reader:
    def __init__(self, b, at=0):
        self.b = b; self.i = at

    def byte(self):
        v = self.b[self.i]; self.i += 1; return v

    def varint(self):
        """Big-endian base-128, high bit set on every byte but the last."""
        v = 0
        while True:
            c = self.byte()
            v = (v << 7) | (c & 0x7F)
            if not (c & 0x80):
                return v

    def take(self, n):
        v = self.b[self.i:self.i + n]; self.i += n; return v


class Cache:
    """The near and same caches COPY addresses are encoded against."""

    def __init__(self, near=4, same=3):
        self.nsize, self.ssize = near, same
        self.near = [0] * near
        self.same = [0] * (same * 256)
        self.next_slot = 0

    def update(self, addr):
        if self.nsize:
            self.near[self.next_slot] = addr
            self.next_slot = (self.next_slot + 1) % self.nsize
        if self.ssize:
            self.same[addr % (self.ssize * 256)] = addr

    def decode(self, mode, here, r):
        if mode == 0:
            addr = r.varint()
        elif mode == 1:
            addr = here - r.varint()
        elif mode < 2 + self.nsize:
            addr = self.near[mode - 2] + r.varint()
        else:
            m = mode - (2 + self.nsize)
            addr = self.same[m * 256 + r.byte()]
        self.update(addr)
        return addr


def apply(source, delta):
    if delta[0:3] != b"\xd6\xc3\xc4":
        raise SystemExit("not a VCDIFF file")
    r = Reader(delta, 3)
    if r.byte() != 0:
        raise SystemExit("VCDIFF version is not 0")
    hdr = r.byte()
    if hdr & 0x01:
        raise SystemExit("this patch brings a secondary compressor - not handled")
    if hdr & 0x02:
        raise SystemExit("this patch brings its own code table - not handled")
    if hdr & 0x04:
        r.take(r.varint())                 # application header, ignored

    table = code_table()
    out = bytearray()

    while r.i < len(delta):
        win = r.byte()
        src_len = src_pos = 0
        if win & 0x03:
            src_len = r.varint(); src_pos = r.varint()
        r.varint()                          # length of the delta encoding
        tgt_len = r.varint()
        if r.byte() != 0:
            raise SystemExit("a compressed window - not handled")
        data_len = r.varint(); inst_len = r.varint(); addr_len = r.varint()
        data = Reader(r.take(data_len))
        inst = Reader(r.take(inst_len))
        addrs = Reader(r.take(addr_len))

        if win & 0x01:
            base = source[src_pos:src_pos + src_len]
        elif win & 0x02:
            base = bytes(out[src_pos:src_pos + src_len])
        else:
            base = b""

        target = bytearray()
        cache = Cache()
        while len(target) < tgt_len:
            i1, s1, m1, i2, s2, m2 = table[inst.byte()]
            for op, size, mode in ((i1, s1, m1), (i2, s2, m2)):
                if op == NOOP:
                    continue
                if size == 0:
                    size = inst.varint()
                if op == ADD:
                    target += data.take(size)
                elif op == RUN:
                    target += data.byte().to_bytes(1, "big") * size
                else:
                    here = len(base) + len(target)
                    a = cache.decode(mode, here, addrs)
                    for _ in range(size):
                        target.append(base[a] if a < len(base)
                                      else target[a - len(base)])
                        a += 1
        out += target[:tgt_len]
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source"); ap.add_argument("diff"); ap.add_argument("out")
    a = ap.parse_args()
    src = open(a.source, "rb").read()
    dl = open(a.diff, "rb").read()
    res = apply(src, dl)
    open(a.out, "wb").write(res)
    print("%s + %s -> %s, %d bytes" % (a.source, a.diff, a.out, len(res)))


main()
