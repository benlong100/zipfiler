#!/usr/bin/env python3
"""Replace the ProDOS quit routine in a disk image, and put it back.

    tools/quitpatch.py install <image.po> [routine.bin]
    tools/quitpatch.py restore <image.po>
    tools/quitpatch.py status  <image.po>

WHAT IT DOES

MLI QUIT ($65) copies four pages out of the language card's second bank down
to $1000 and jumps there. Those 1024 bytes ARE the quit routine -- on ProDOS
2.4 they are Bitsy Bye. They live verbatim inside the PRODOS file, so putting
a different routine there changes what happens when any program quits.

This works on a DISK IMAGE and never on a mounted card or a live boot volume.
Copy the patched image across yourself, deliberately. See docs/design.md 12.

REVERSIBLE, WHICH IS THE POINT

`install` writes the original 1024 bytes to <image>.quitsave before it changes
anything, and `restore` puts them back.

It refuses to patch an image that is ALREADY patched, so the saved copy is
never a previous patch and there is always a way back. That judgement is made
by looking at the image, not at whether a save file exists: rebuilding an image
throws the patch away and leaves the .quitsave behind, and a freshly built disk
has to stay patchable. That is the ordinary case after any change to ZipFiler.

FINDING THE BLOCK

Not at a fixed offset: PRODOS is not the same length or layout in every
version, and hard-coding $3A00 would silently patch the wrong kilobyte of a
ProDOS that moved it. The block is found by its first instructions, which are
the same in every quit routine because they are what a quit routine has to do
first -- clear decimal, bank the ROM in, re-enable interrupts:

    D8        CLD
    AD 82 C0  LDA $C082
    58        CLI

That signature is checked against the running code as well: see the
"quit routine" section of tests/run.sh, which boots a patched image and quits
into it.
"""
import pathlib, shutil, subprocess, sys

QUITLEN = 1024
SIGNATURE = bytes([0xD8, 0xAD, 0x82, 0xC0, 0x58])   # cld / lda $C082 / cli

def ac(*args, stdin=None):
    root = pathlib.Path(__file__).resolve().parent.parent
    return subprocess.run([str(root / "tools" / "ac"), *args],
                          input=stdin, capture_output=True)

def read_prodos(image):
    r = ac("-g", str(image), "PRODOS")
    if r.returncode != 0 or not r.stdout or b"No match" in r.stdout:
        sys.exit(f"{image}: no PRODOS file on it -- is this a bootable image?")
    return r.stdout

# Fields in a ProDOS directory entry that describe the file rather than where
# its blocks are. Deleting and re-adding a file loses every one of them, and
# the access byte is the one that matters: a bootable volume very often ships
# with PRODOS LOCKED, and coming back unlocked is a change nobody asked for.
ENTRY_ATTRS = [0x10] + list(range(0x18, 0x25))   # type, dates, version, access, aux

def entry_offset(image, want=b"PRODOS"):
    """Where that file's 39-byte directory entry starts in the image."""
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

def read_attrs(image):
    off = entry_offset(image)
    if off is None:
        return None
    with open(image, "rb") as f:
        f.seek(off)
        e = f.read(39)
    return {a: e[a] for a in ENTRY_ATTRS}

def write_attrs(image, attrs):
    off = entry_offset(image)
    if off is None or not attrs:
        return
    with open(image, "r+b") as f:
        for a, v in attrs.items():
            f.seek(off + a)
            f.write(bytes([v]))

def write_prodos(image, data):
    # AppleCommander will not overwrite, so the old one goes first -- and that
    # throws away the file's attributes, so they are put back afterwards.
    attrs = read_attrs(image)
    ac("-d", str(image), "PRODOS")
    r = ac("-p", str(image), "PRODOS", "SYS", stdin=data)
    if r.returncode != 0:
        sys.exit(f"{image}: could not write PRODOS back: {r.stderr.decode()}")
    write_attrs(image, attrs)

def find_quit(prodos):
    hits = []
    i = prodos.find(SIGNATURE)
    while i >= 0:
        hits.append(i)
        i = prodos.find(SIGNATURE, i + 1)
    if not hits:
        sys.exit("could not find the quit routine: none of the PRODOS file "
                 "starts with cld / lda $C082 / cli. If this is a ProDOS "
                 "older or newer than the ones tested, check by hand before "
                 "patching anything.")
    if len(hits) > 1:
        sys.exit(f"found {len(hits)} places that look like the quit routine "
                 f"({', '.join(hex(h) for h in hits)}). Refusing to guess.")
    off = hits[0]
    if off + QUITLEN > len(prodos):
        sys.exit(f"the quit routine at {hex(off)} would run past the end of "
                 f"the PRODOS file. Something is wrong; nothing written.")
    return off

def savepath(image):
    return pathlib.Path(str(image) + ".quitsave")

def identify(block, routine=None):
    """Whose quit routine is this? Asked of the IMAGE, never of the save file.

    Rebuilding an image throws the patch away and leaves the .quitsave behind,
    so "has a save file" does not mean "is patched" -- and treating it that way
    refused to re-patch a freshly built disk, which is the ordinary case after
    any change to the program.
    """
    if routine:
        want = pathlib.Path(routine).read_bytes()
        if block[:len(want)] == want:
            return "ours"
    plain = bytes(c & 0x7f for c in block)
    if b"ZIPFILER" in plain:
        return "ours"
    if b"BITSY" in plain:
        return "bitsy"
    return "unknown"

def cmd_status(image):
    prodos = read_prodos(image)
    off = find_quit(prodos)
    block = prodos[off:off + QUITLEN]
    print(f"{image}")
    print(f"  quit routine at PRODOS offset {hex(off)}, {QUITLEN} bytes")
    routine = "src/ZFQUIT.BIN" if pathlib.Path("src/ZFQUIT.BIN").exists() else None
    kind = identify(block, routine)
    names = {"ours": "ZipFiler's", "bitsy": "Bitsy Bye", "unknown": "not recognised"}
    print(f"  it is: {names[kind]}")
    s = savepath(image)
    if s.exists():
        note = "" if kind == "ours" else "  (STALE: the image is not patched)"
        print(f"  saved original: yes, {s}{note}")
    else:
        print(f"  saved original: none")

def cmd_install(image, routine):
    data = pathlib.Path(routine).read_bytes()
    if len(data) > QUITLEN:
        sys.exit(f"{routine} is {len(data)} bytes and the quit routine has "
                 f"room for {QUITLEN}. Nothing written.")
    data = data + bytes(QUITLEN - len(data))

    prodos = read_prodos(image)
    off = find_quit(prodos)
    block = prodos[off:off + QUITLEN]

    # Refuse on what is IN the image, not on whether a save file is lying
    # about. Patching a patched image would overwrite the saved original with
    # a patch and leave no way back; patching a REBUILT one is the ordinary
    # case and has to keep working.
    if identify(block, routine) == "ours":
        sys.exit(f"{image} already has ZipFiler's quit routine in it. Run "
                 f"restore first if you want to start from the original.")
    s = savepath(image)
    if s.exists():
        print(f"note: {s} was left over from an earlier patch of an image "
              f"that has since been rebuilt. Replacing it.")
    s.write_bytes(block)

    patched = prodos[:off] + data + prodos[off + QUITLEN:]
    assert len(patched) == len(prodos), "the PRODOS file changed length"
    write_prodos(image, patched)
    print(f"patched {image}")
    print(f"  quit routine at {hex(off)} replaced, {len(data)} bytes")
    print(f"  original saved to {s}")
    print(f"  quitting any program on this disk now runs ZIPFILER.SYSTEM")
    a = read_attrs(image)
    if a and not a[0x1E] & 0x02:
        print(f"  PRODOS was locked (access ${a[0x1E]:02X}) and still is")

def cmd_restore(image):
    s = savepath(image)
    if not s.exists():
        sys.exit(f"no {s}, so there is nothing to put back. This image was "
                 f"either never patched or was patched from elsewhere.")
    block = s.read_bytes()
    if len(block) != QUITLEN:
        sys.exit(f"{s} is {len(block)} bytes, not {QUITLEN}. Refusing to use it.")
    prodos = read_prodos(image)
    off = find_quit(prodos)
    patched = prodos[:off] + block + prodos[off + QUITLEN:]
    write_prodos(image, patched)
    s.unlink()
    print(f"restored {image}: the original quit routine is back")

def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__.strip().splitlines()[0] + "\n\n" +
                 "\n".join(l for l in __doc__.splitlines()[2:5]))
    cmd, image = argv[1], pathlib.Path(argv[2])
    if not image.exists():
        sys.exit(f"no such image: {image}")
    if cmd == "status":
        cmd_status(image)
    elif cmd == "install":
        routine = argv[3] if len(argv) > 3 else "src/ZFQUIT.BIN"
        if not pathlib.Path(routine).exists():
            sys.exit(f"no {routine} -- run: make quitcode")
        cmd_install(image, routine)
    elif cmd == "restore":
        cmd_restore(image)
    else:
        sys.exit(f"unknown command {cmd!r}: install, restore or status")

if __name__ == "__main__":
    main(sys.argv)
