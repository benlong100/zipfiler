# a2-filer

**ZipFiler** -- a two-panel file manager for the Enhanced Apple //e, ProDOS 8, in 6502
assembly. Two directories on screen at once, the cursor keys to pick from
them, and single letters to act — so a pathname never has to be typed.

`docs/design.md` is the design and the reasoning behind it.

    make disk      a bootable image, build/ZIPFILER.po
    make fixture   the same with files on it to practise on
    make test      the regression suite
    make card VOL="NAME"   copy an image to a mounted card

Sibling project: [a2-editor](../a2-editor), the ZipEdit Markdown editor,
which is where the toolchain, the display layer and the Virtual ][ test
harness come from.
