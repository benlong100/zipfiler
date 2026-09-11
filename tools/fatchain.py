#!/usr/bin/env python3
"""Report the cluster-chain extents of files in a FAT12/16/32 volume.

    fatchain.py <device-or-image> [NAME.EXT ...]

With no names, reports every disk image in the root directory.
Reads by seeking, so it is safe on a 15GB device.
"""
import sys, struct, os

path = sys.argv[1]
wanted = [a.upper() for a in sys.argv[2:]]
f = open(path, 'rb')

# A RAW DEVICE ONLY ACCEPTS ALIGNED READS. /dev/rdiskNsM can be opened while the
# volume is mounted, which the block device cannot, but every read has to start
# on a sector boundary and be a whole number of sectors. So everything goes
# through a sector cache -- which also keeps following a cluster chain from
# costing one device read per cluster.
SEC = 512
_sec = {}
def sector(i):
    b = _sec.get(i)
    if b is None:
        f.seek(i * SEC)
        b = f.read(SEC)
        if len(_sec) < 20000:
            _sec[i] = b
    return b

def rd(off, n):
    out = bytearray()
    i, skip = off // SEC, off % SEC
    while len(out) < n + skip:
        chunk = sector(i)
        if not chunk: break
        out += chunk
        i += 1
    return bytes(out[skip:skip+n])

b = rd(0, 512)
bps   = struct.unpack_from('<H', b, 0x0B)[0]
spc   = b[0x0D]
resv  = struct.unpack_from('<H', b, 0x0E)[0]
nfat  = b[0x10]
rootn = struct.unpack_from('<H', b, 0x11)[0]
spf16 = struct.unpack_from('<H', b, 0x16)[0]
spf   = spf16 if spf16 else struct.unpack_from('<I', b, 0x24)[0]
fat32 = (spf16 == 0)
fat_off  = resv * bps
root_off = fat_off + nfat * spf * bps
data_off = root_off + rootn * 32
root_clu = struct.unpack_from('<I', b, 0x2C)[0] if fat32 else None
print(f"{'FAT32' if fat32 else 'FAT16'}  cluster {spc*bps} bytes  "
      f"{nfat} FATs of {spf} sectors")

def clu_off(c): return data_off + (c - 2) * spc * bps
FATEND = 0x0FFFFFF8 if fat32 else 0xFFF8
def fat_next(c):
    if fat32:
        return struct.unpack_from('<I', rd(fat_off + c*4, 4), 0)[0] & 0x0FFFFFFF
    return struct.unpack_from('<H', rd(fat_off + c*2, 2), 0)[0]

entries = []
def scan(buf):
    for i in range(0, len(buf), 32):
        e = buf[i:i+32]
        if len(e) < 32 or e[0] == 0: return True
        if e[0] == 0xE5 or e[11] == 0x0F or (e[11] & 0x08): continue
        nm = e[0:8].decode('ascii','replace').strip()
        ex = e[8:11].decode('ascii','replace').strip()
        name = (nm + '.' + ex).strip('.').upper()
        lo = struct.unpack_from('<H', e, 0x1A)[0]
        hi = struct.unpack_from('<H', e, 0x14)[0] if fat32 else 0
        size = struct.unpack_from('<I', e, 0x1C)[0]
        entries.append((name, (hi<<16)|lo, size))
    return False

if fat32:
    c = root_clu
    while 2 <= c < FATEND:
        if scan(rd(clu_off(c), spc*bps)): break
        c = fat_next(c)
else:
    scan(rd(root_off, rootn*32))

IMGEXT = ('.PO', '.DSK', '.2MG', '.HDV', '.2IMG')
todo = [e for e in entries if (e[0] in wanted) or
        (not wanted and e[0].endswith(IMGEXT))]
if not todo:
    print("no matching files in the root directory"); sys.exit(2)

worst = 0
for name, start, size in todo:
    runs, c, prev, n = [], start, None, 0
    while 2 <= c < FATEND:
        if prev is not None and c == prev + 1: runs[-1][1] += 1
        else: runs.append([c, 1])
        prev = c; c = fat_next(c); n += 1
        if n > 2000000: break
    worst = max(worst, len(runs))
    tag = "CONTIGUOUS" if len(runs) == 1 else f"FRAGMENTED into {len(runs)}"
    print(f"\n{name}: {size} bytes, {n} clusters -- {tag}")
    for st, ln in runs[:8]:
        print(f"   clusters {st}..{st+ln-1}  ({ln})")
    if len(runs) > 8: print(f"   ... and {len(runs)-8} more extents")
sys.exit(0 if worst == 1 else 3)
