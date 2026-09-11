# Changelog

## 1.1 — 10 September 2026

**Changed: a directory is written `<DIR>`.**

In a column of `BAS` and `TXT` and `BIN`, the word `DIR` reads as one more
three-letter type. A directory is not one of those — it is the thing `RET`
goes into — and the angle brackets are what catalogue listings have used to
say so since long before this program.

```
BOOTING.TXT     TXT      10
ARCHIVE         <DIR>     1
PRODOS          SYS      34
```

The type column is five characters wide now rather than three, so the blocks
column sits two further right. An entry line spends 28 of its 39 columns
instead of 26, and the panel had eleven spare either way, so nothing shrank
and the sixteen columns given to the name are untouched.

Volumes still read `VOL`. The volumes panel holds nothing but volumes, so
there is nothing there for them to stand out from.

## 1.0 — 28 August 2026

First release. A two-panel file manager for the Enhanced //e under ProDOS 8,
in about 9K: two directories on screen at once, the cursor keys to pick from
them, and single letters to act, so a pathname never has to be typed.

Copy, move, delete, rename, new directory, lock and unlock, across both
panels, on a tagged set or on the line the cursor is on. `RET` goes into a
directory or **runs a program** — `SYS`, `BIN` or `BAS`, the last of these by
loading `BASIC.SYSTEM` and naming the program to it so it runs rather than
dropping you at a prompt. `/` jumps to a name, `P` boots a slot, `Q` quits.

`QPATCH.SYSTEM` ships on the same disk and patches ProDOS's selector so that
quitting a program comes back to ZipFiler rather than to Bitsy Bye.

The listing is deliberately unsorted, because `CATALOG` is unsorted and a
sorted panel would be the surprising thing. The chrome is ASCII rather than
MouseText — `docs/mousetext.md` records what that character set can and cannot
actually draw, and why the dashes won.
