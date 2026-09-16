"""Encode a VCDIFF (RFC 3284) delta of the shape Slippi ships.

Slippi distributes its game-file edits as `<name>.diff` and SlippiGameFileLoader
applies them to the copy in the user's own ISO, so no Melee data is
redistributed. We were shipping a whole 2.2MB MnMaAll.usd instead, which the
loader prefers over the .diff - about 12x larger, and carrying the menu archive
with it.

vcdiff.py in this folder decodes their patches; this writes one back. Deliberately
the same narrow subset it reads:

  * one window over the whole target, VCD_SOURCE
  * the default code table, no custom table
  * no secondary compression
  * COPY in mode 0 only, so every address is a plain absolute varint and the
    address cache never has to agree with anything

That is more verbose than open-vcdiff would be and still tiny, because the
target is the source with one label image changed and a little appended.

  python vcdiff_encode.py <source> <target> <out.diff>

Verify with the decoder next to it - encode, decode, compare. A delta that does
not round-trip here has no business being shipped.
"""
import struct, sys

RUN, ADD, COPY = 0, 1, 3

# Default code table indices we use. See default_code_table() in vcdiff.py:
# 0 is RUN, 1..18 are ADD (1 takes a varint size), 19 begins COPY mode 0
# (19 takes a varint size).
IDX_ADD_VARINT = 1
IDX_COPY_M0_VARINT = 19

MIN_MATCH = 12          # shorter than this costs more to encode than to inline
CHUNK = 12              # index granularity


def varint(n):
    """RFC 3284 integers: big-endian base-128, high bit set on all but the last."""
    if n == 0:
        return b"\x00"
    out = bytearray()
    while n:
        out.append(n & 0x7F)
        n >>= 7
    out.reverse()
    for i in range(len(out) - 1):
        out[i] |= 0x80
    return bytes(out)


def encode(source, target):
    # Where each CHUNK-byte run of the source begins. First occurrence wins,
    # which keeps addresses small and the table honest.
    index = {}
    for i in range(0, len(source) - CHUNK + 1):
        index.setdefault(source[i:i + CHUNK], i)

    data = bytearray()      # literal bytes for ADD
    inst = bytearray()      # instruction stream
    addr = bytearray()      # addresses for COPY
    pending = bytearray()   # literals not yet flushed

    def flush():
        if not pending:
            return
        inst.append(IDX_ADD_VARINT)
        inst.extend(varint(len(pending)))
        data.extend(pending)
        pending.clear()

    i = 0
    n = len(target)
    while i < n:
        hit = index.get(target[i:i + CHUNK]) if i + CHUNK <= n else None
        if hit is None:
            pending.append(target[i])
            i += 1
            continue

        # Stretch the match as far as it will go.
        length = CHUNK
        while (i + length < n and hit + length < len(source)
               and target[i + length] == source[hit + length]):
            length += 1

        if length < MIN_MATCH:
            pending.append(target[i])
            i += 1
            continue

        flush()
        inst.append(IDX_COPY_M0_VARINT)
        inst.extend(varint(length))
        addr.extend(varint(hit))     # mode 0: absolute, into the source window
        i += length

    flush()

    body = bytearray()
    body.append(0x01)                       # VCD_SOURCE
    body.extend(varint(len(source)))        # source window length
    body.extend(varint(0))                  # source window position
    inner = bytearray()
    inner.extend(varint(len(target)))       # target window length
    inner.append(0x00)                      # delta indicator: nothing compressed
    inner.extend(varint(len(data)))
    inner.extend(varint(len(inst)))
    inner.extend(varint(len(addr)))
    inner.extend(data)
    inner.extend(inst)
    inner.extend(addr)
    body.extend(varint(len(inner)))         # length of the delta encoding
    body.extend(inner)

    out = bytearray(b"\xD6\xC3\xC4\x00")    # magic + version
    out.append(0x00)                        # no compressor, no code table, no app data
    out.extend(body)
    return bytes(out)


if __name__ == "__main__":
    src = open(sys.argv[1], "rb").read()
    tgt = open(sys.argv[2], "rb").read()
    delta = encode(src, tgt)

    import vcdiff
    back = vcdiff.decode(src, delta)
    if back != tgt:
        raise SystemExit("ROUND TRIP FAILED - refusing to write %s" % sys.argv[3])

    open(sys.argv[3], "wb").write(delta)
    print("%s  %d bytes  (target %d, %.1f%% of it)"
          % (sys.argv[3], len(delta), len(tgt), 100.0 * len(delta) / len(tgt)))
