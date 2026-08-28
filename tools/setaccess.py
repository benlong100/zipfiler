#!/usr/bin/env python3
"""Set a file's ProDOS access byte inside a disk image.

    tools/setaccess.py <image> <filename> <hex>     e.g. 21 to lock, e3 to not
    tools/setaccess.py <image> <filename>           just report it

AppleCommander can lock a file on a real ProDOS volume but not conveniently
inside an image from a script, and the suite needs to build a locked one on
purpose: a bootable volume very often ships with its system files LOCKED, and
that is a case no floppy image built by mkdisk.sh has ever had.

It is the case that broke the quit patcher in the field. Every image tested
here was a 140K floppy with PRODOS write-enabled, so "ProDOS refuses to write
to a locked file" never came up until somebody pointed the patcher at a 32MB
volume that had been shipped properly.

The common values:

    $E3   write, read, rename, destroy, and needs backing up -- the usual
    $21   read only, needs backing up -- what a locked system file looks like
    $01   read only
"""
import pathlib, sys

def entry_offset(image, want):
    """Byte offset of that file's 39-byte directory entry, or None."""
    want = want.encode("ascii")
    with open(image, "rb") as f:
        blk = 2
        while blk:
            f.seek(blk * 512)
            b = f.read(512)
            if len(b) < 512:
                return None
            nxt = b[2] | (b[3] << 8)
            for i in range(13):
                off = 4 + i * 39
                e = b[off:off + 39]
                if (e[0] >> 4) in (1, 2, 3, 0xD):
                    if e[1:1 + (e[0] & 0x0F)] == want:
                        return blk * 512 + off
            blk = nxt
    return None

def main(argv):
    if len(argv) not in (3, 4):
        sys.exit("usage: setaccess.py <image> <filename> [hex]")
    image, name = pathlib.Path(argv[1]), argv[2]
    off = entry_offset(image, name)
    if off is None:
        sys.exit(f"{image}: no file called {name} in the volume directory")
    with open(image, "rb") as f:
        f.seek(off + 0x1E)
        now = f.read(1)[0]
    if len(argv) == 3:
        state = "write-enabled" if now & 0x02 else "LOCKED"
        print(f"{name}: access ${now:02X}  {state}")
        return
    new = int(argv[3], 16)
    with open(image, "r+b") as f:
        f.seek(off + 0x1E)
        f.write(bytes([new]))
    was = "write-enabled" if now & 0x02 else "LOCKED"
    isn = "write-enabled" if new & 0x02 else "LOCKED"
    print(f"{name}: ${now:02X} ({was}) -> ${new:02X} ({isn})")

if __name__ == "__main__":
    main(sys.argv)
