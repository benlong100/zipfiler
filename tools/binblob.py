#!/usr/bin/env python3
"""Turn a binary into Merlin `dfb` lines so a program can carry it.

    tools/binblob.py src/ZFQUIT.BIN QUITCODE 1024 > src/zfquitdata.S

Merlin32 has no way to include a binary, and QPATCH has to carry the whole
replacement quit routine inside itself: it runs on the Apple, where there is
no second file to read it out of and no Mac to hand it over.

The length is padded to exactly what the quit block holds, because the patcher
writes a fixed number of bytes and a short blob would leave the tail of the old
routine behind -- half Bitsy Bye, half this, and no way to tell from looking.
"""
import pathlib, sys

def main(argv):
    if len(argv) != 4:
        sys.exit("usage: binblob.py <file> <label> <padded-length>")
    src, label, length = pathlib.Path(argv[1]), argv[2], int(argv[3])
    data = src.read_bytes()
    if len(data) > length:
        sys.exit(f"{src} is {len(data)} bytes and will not fit in {length}")
    data = data + bytes(length - len(data))

    out = [
        "*" + "-" * 37,
        f"* GENERATED from {src} by tools/binblob.py -- DO NOT EDIT.",
        "*",
        f"* The replacement quit routine, {len(src.read_bytes())} bytes of code",
        f"* padded to {length}: the patcher writes the whole block, so a short",
        "* one would leave the tail of the old routine in place.",
        "*" + "-" * 37,
        "",
        label,
    ]
    for i in range(0, len(data), 8):
        row = ",".join(f"${b:02x}" for b in data[i:i + 8])
        out.append(f"             dfb   {row}")
    out.append(f"{label}LEN   equ   {length}")
    print("\n".join(out))

if __name__ == "__main__":
    main(sys.argv)
