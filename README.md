# a2-filer

**ZipFiler** — a two-panel file manager for the Enhanced Apple //e, ProDOS 8,
in 6502 assembly. Two directories on screen at once, the cursor keys to pick
from them, and single letters to act — so a pathname never has to be typed.

Apple's own utilities want a pathname typed at a prompt. This one shows you
both ends of the job and lets you point at them.

Requires an Enhanced //e with 128K and ProDOS 8. Eighty columns, and about 9K
on disk.

## Keys

| | |
|---|---|
| `ARROWS` | move the cursor |
| `TAB` | the other panel |
| `RET` | go into a directory — or **run a program** |
| `LEFT` | up a level; out of a volume root it lists the volumes |
| `/` | jump to a name — type as much of it as you need |
| `SPACE` | tag; commands act on the tagged set |
| `A` | tag all, or clear them if all are set already |
| `C` | copy, left panel to right — directories and their contents included |
| `M` | move: copy across, then remove the original |
| `D` `R` `N` | delete, rename, new directory |
| `L` | lock, or unlock if every target is locked already |
| `S` | swap the panels over |
| `P` | `PR#` — boot a slot |
| `Q` | quit to ProDOS |
| `?` | the help screen |

A command with nothing tagged acts on the line the cursor is on, so the common
case needs no tagging at all.

## Running programs

`RET` on a `SYS`, `BIN` or `BAS` file runs it. A `SYS` file is entered at
`$2000`; a `BIN` at the address it names in its own `aux_type`; a `BAS` file
loads `BASIC.SYSTEM` — which must be on the same volume — and is named to it,
so it runs rather than dropping you at a prompt.

Since a program loads over ZipFiler itself, the loader is a position-independent
stub copied below `$2000` first. `docs/design.md` §14 has the details, including
the two approaches that did not work and why.

## Building

    make disk      a bootable image, build/ZIPFILER.po
    make fixture   the same with files on it to practise on
    make test      the regression suite, 170 assertions
    make card VOL="NAME"   copy an image to a mounted card

Merlin32 cross-assembles on the Mac; the suite drives Virtual ][ through
AppleScript and asserts against the emulated screen and emulated RAM. The
suite never points at a real card, and never at anybody's boot volume — see
`docs/design.md` §12.

`docs/design.md` is the design and the reasoning behind it, including the
things that turned out to be harder than they looked.

## Related

[ZipEdit](https://github.com/benlong100/zipedit), a Markdown editor for the
same machine, is where the toolchain, the display layer and the Virtual ][ test
harness come from.

## Licence

MIT — see [LICENSE](LICENSE).
