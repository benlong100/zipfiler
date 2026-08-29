# Design: a two-panel file manager for the Enhanced Apple //e

**ZipFiler**, which pairs with ZipEdit. It was called ZipFiler in this document
as a placeholder and is now the name.

Not *Filer*: Apple's own System Utilities ship a `FILER.SYSTEM`, and two of
them on one card is somebody's bad afternoon. `ZIPFILER.SYSTEM` is exactly
fifteen characters, which is exactly what ProDOS allows -- one more and it
would land truncated, stop looking like a `.SYSTEM` file, and the disk would
quietly boot to BASIC. ZipEdit hit that wall with `ZIPEDIT2P.SYSTEM` at
sixteen; this one fits by a single character.

The repository is `a2-filer`, beside `a2-editor`, the way `a2-editor` is not
called `zipedit`.

## 1. Goals and non-goals

ProDOS 8 already has file utilities. They want a full pathname typed at them,
and they are large enough that loading one is a decision rather than a reflex.
This is the other thing: two directories on screen at once, the cursor keys to
pick from them, and single letters to act.

**Goals**

- 80 columns, two panels, a catalogue in each.
- Navigate into and out of subdirectories without typing a path, ever.
- Lock, unlock, delete, rename and copy, on one file or a tagged set.
- Small enough that loading it is not a decision.

**Non-goals, at least to begin with**

- Copying a directory and its contents. Deferred — see §11.
- Checking free space before a copy. Deferred, with a caveat in §7.
- Viewing or editing file contents. ~~`RET` opens directories and nothing
  else.~~ It runs programs too now -- see §14. Viewing is still not a goal.
- DOS 3.3, Pascal or CP/M volumes. ProDOS only.
- Sorting. See §4.

## 2. The screen

24 rows, 80 columns. One row of paths, a rule, twenty entries, a status row
and a hint row.

```
>/WORK/DOCS                            | /BACKUP
---------------------------------------+----------------------------------------
> CHAPTER.ONE     TXT    14            |  ARCHIVE         DIR     4
  CHAPTER.TWO     TXT     9            | *README          TXT     2
> NOTES           TXT     3            |
 *ZIPEDIT.SYSTEM  SYS    21            |
  OLD             DIR     2            |
2 tagged, 17 blocks                    |
        TAB panel  SPC tag  RET open  C copy  R name  L ock  D el  S wap
```

Columns: 39 for the left panel, one separator, 40 for the right. An entry line
spends 26 of its 39 — a tag column, a lock column, fifteen for the name, three
for the type and five for the blocks used. The remaining thirteen are left
empty deliberately. There is room there for a modification date and it is not
worth the space it would cost on screen or the four bytes an entry it would
cost in memory.

- `>` marks a tagged entry, `*` a locked one. (The sketch above said `»`; the
  //e's character set has no such glyph and MouseText offers nothing closer.) The asterisk is the one `CATALOG`
  already puts against a locked file, so it needs no explaining.
- `>` on the path row marks the panel with focus. The cursor line is drawn
  inverse.
- A directory carries `DIR` in the type column, so it reads as somewhere to go.
- The status row carries the tagged count and the blocks they add up to, which
  is the number wanted before a copy, and is where errors and progress appear.
- The hint row is the same idea as ZipEdit's cheat sheet and can be the first
  thing sacrificed for a twenty-first entry if it comes to that.

## 3. Panels and navigation

A panel holds **a path**, not a volume. Two paths rather than two volumes costs
nothing — the panel has to track a path either way — and buys the case that
comes up constantly, which is moving files between two directories of the same
volume.

`TAB` moves focus. `S` swaps the two paths.

**Up from the root of a volume is the volume list.** `ON_LINE` gives every
online volume, and showing them as the parent of every root means there is no
separate "choose a volume" command to design, document or find. Up is just up,
all the way out. A panel's state stays one thing — a path, possibly empty —
rather than a volume plus a path.

`RET` walks into the directory under the cursor, or out of a root into that
list. On a file it does nothing. A viewer is the obvious eventual answer and
the obvious eventual scope creep.

## 4. The listing

Read the directory into memory and keep it there, so moving the cursor costs
nothing and a tag can survive a scroll.

**Parallel arrays, not records.** Names in a block of 16-byte stride, then
separate arrays for file type, storage type, blocks used and access, and the
tags as a bitmap. Indexing a 16-byte stride is a shift rather than a multiply,
a tag costs a bit rather than a byte, and nothing is padded:

| | per entry | 256 entries | both panels |
|---|---|---|---|
| name (length + 15) | 16 | 4,096 | 8K |
| file type, storage type, access | 3 | 768 | 1.5K |
| blocks used | 2 | 512 | 1K |
| tag bitmap | ⅛ | 32 | 64 |
| | **~21** | **~5.4K** | **~10.8K** |

**Capped at 255 entries a panel**, so the count fits in a byte -- 256 was the
design and the difference is not a real one. A 5.25-inch volume is 280 blocks and cannot
physically hold 256 files with anything in them, and a volume directory is
capped at 51 entries whatever the medium — so the cap never bites on a floppy
image. It is only reachable in a large CFFA partition, and there it must be an
honest message rather than a listing that is quietly wrong.

**Physical order, not sorted.** `CATALOG` shows creation order and so does
every other ProDOS tool, so a sorted panel would be the surprising thing. It
also drops the sort code, the index array it would have needed, and the only
part of building a listing that had a per-directory time cost.

What sorting would actually have been for — finding one file among two hundred
— is better served by jumping to a name.

**As built, and not as designed.** A bare letter cannot do it: `C L R D N S`
and `Q` are commands, so a bare-letter jump would work on nineteen letters out
of twenty-six, which is worse than none because you would learn it and then it
would rename something. §4 was written before §5 chose bare letters and the two
conflict.

So it is `/`, and it takes a **prefix** rather than one letter, which is better
for a long listing anyway: one key reaches the C's and three reaches the file.
It searches from the top each time, so rubbing a letter out returns to where
the shorter prefix led.

## 5. Commands

**Bare letters.** ZipEdit puts every command behind Open-Apple because a bare
letter there has to be text. This screen has no text entry at all, so the
letters are free, and free letters are both faster and what anyone who has used
a two-panel manager already expects.

| key | |
|---|---|
| arrows | move the cursor; left/right also move between panels at the edges |
| `TAB` | focus the other panel |
| `SPC` | tag the entry and move down |
| `RET` | into a directory, or out of a root to the volume list |
| a letter | jump to the next entry starting with it |
| `C` | copy — always left panel to right panel |
| `R` | rename |
| `L` | lock or unlock |
| `D` | delete |
| `S` | swap the panels |
| `N` | a new directory |
| `M` | move: copy across, then remove the original |
| `/` | jump to a name |
| `Q` | back to ProDOS |
| `?` | help |

Open-Apple ends up entirely unused, which is somewhere to put confirmations
later, or nothing at all.

**ESC does not quit.** It cancels a prompt and answers no to a question, and
that is all. Quitting is `Q`, because ESC on the main screen was one keystroke
between the writer and losing their place.

**"working" goes up before the slow thing, not after it.** Reading a directory
off a floppy is slow enough to wonder whether the key registered, so the status
row is drawn on its own before a scan starts rather than waiting for the redraw
that follows -- the redraw being the part that takes the time.

**Copy is always left to right.** Fixing the direction means never having to
express one, and `S` covers the other way. The alternative — copy from the
focused panel to the other — needs no swap key and reads consistently with the
other commands, but it makes direction a mode rather than a visible fact, and
the failure when you get it wrong is silent and overwrites something. Dull and
predictable wins.

Rename and any later new-directory command need a text prompt.

**As built.** The prompt is the only place in the program that takes text, and
it opens holding the existing name so that changing an extension is four
keystrokes rather than fifteen. A name is checked here rather than left to the
MLI -- one to fifteen characters, a letter first, then letters, digits and full
stops -- so the writer is told which rule they broke instead of a hex code.
ESC abandons it and says so.

Renaming a volume is a different shape of path and is refused for now with a
message. ProDOS will do it; the command has not been written.

## 6. Tagging

`SPC` tags the entry under the cursor and moves down one, so tagging a run is
tapping the space bar. `A` tags the whole listing -- **or clears it if it is
already tagged**, which is the same shape as `L`: one key that does whichever
thing is not already true. It toggles rather than simply tagging because
otherwise there is no way to clear a set at all without leaving the directory,
which would discard the tags as a side effect of navigating rather than
because anyone asked.

`A` acts on the focused panel alone. No command acts on both.

**A command acts on the tagged set if there is one, and on the cursor line if
there is not.** That removes any question of mode: there is never a state to be
in or to leave. Tags belong to a panel and are cleared when its path changes.

Rename ignores tags and always takes the cursor line, because renaming five
files to one name means nothing.

**A batch reports what it did not do.** "Copied 5 of 7 — 2 were locked" is the
difference between a tool that is trusted and one that is checked afterwards.
That line is also where a full disk surfaces.

## 7. Destructive operations

This is the part where a bug costs somebody their disk rather than a keystroke,
and it is worth more care than the rest of the program put together.

**Copy** reads and writes through one buffer, then carries the file's type, aux
type, dates and access across with `SET_FILE_INFO`. A copy that arrives with
the wrong type is not a copy.

**A name that already exists** is asked about once per batch, with an
all/skip/cancel answer. Refusing outright is tedious the moment you re-copy a
file you have changed, which is the common case; asking per file is right for
one file and miserable for twelve.

**A copy that fails partway must destroy its own output.** The check for free
space is deferred (§11), so the disk filling up is a `WRITE` error partway
through — and at that point there is a truncated file on the destination with a
plausible name and the right type, which is worse than no copy at all because
it looks like it worked. Cleaning that up is not the deferred feature. It is
the first version.

**Copying a file onto itself** needs a guard. It is easy to reach with the same
volume open in both panels.

**As built: `L`.** The access byte is *changed*, not replaced -- destroy,
rename and write go off or on and everything else in it, the backup bit above
all, is left as ProDOS had it. `GET_FILE_INFO` and `SET_FILE_INFO` are given
separate parameter blocks, because the three bytes `SET` requires to be zero
are exactly where `GET` returns the storage type and block count; sharing one
block would write a file's size into a reserved field, which stays invisible
until a directory will not read.

**Delete refuses a locked file** and says so, rather than quietly unlocking it.
The lock is the writer's stated intent and `L` is one key away.

**As built: `D`.** It asks first -- it is the one command with nothing behind
it -- and a locked file is counted and named rather than treated as a failure.
A refusal by ProDOS and a lock the writer set are different things and are
reported differently: the error code is kept at the point of failure, because
the rescan that follows makes its own MLI calls and `MLIERR` would be theirs
by the time anyone looked.

**A non-empty directory is refused by ProDOS itself** -- verified on the
machine, error `$4E` -- so the program does not need its own guard, and says
"a directory has to be empty first" rather than showing a hex code. The block
compare confirms nothing at all was written.

**Copying a directory** takes everything inside it -- see §11, which is built.

**Moving** is `M`: copy to the other panel, and only once it has arrived,
destroy the original. If the copy succeeds and the removal does not it says
so rather than claiming a move -- two copies is the safe failure, none is not.

A same-volume move could instead relocate the directory entry itself: clear it
in one directory, write it into the other, fix its `header_pointer` and the two
`file_count`s, and the data blocks would never move at all. ProDOS 8 has no
MOVE call and `RENAME` will not cross directories, so that means editing
directory blocks by hand and growing the destination out of the volume bitmap
when it is full -- which is the "freed somebody else's blocks" failure this
whole harness exists to catch. Worth having later, with a test that moves a
file and asserts **the bitmap did not change at all**, which is the signature
proving no block was touched.

`M` refuses a directory, because removing the source afterwards would need a
recursive delete that is not built, and copying the tree while leaving the
original behind would be pretending. It refuses a locked file for the reason
`D` does.

**As built: `C`.** Both files are open at once, so the source and destination
each have their own 1K ProDOS buffer and their own parameter blocks; 8K of
main memory is carried between them. `CREATE` takes the source's type, aux
type and creation date, and `SET_FILE_INFO` puts the modification date and the
access back afterwards -- the destination is made unlocked and only protected
once there is something there to protect.

A write that fails destroys its own output before reporting, which is the
whole of §7's argument: the free space check is deferred, so a full disk
arrives as a `WRITE` error partway through, and what it would otherwise leave
behind is a truncated file with a plausible name and the right type.

The overwrite question is asked once for the batch -- overwrite, skip, or
stop -- and the answer is remembered for the rest of it.

The same directory in both panels is refused outright rather than checked file
by file. It is the only way to copy a file onto itself and it is easy to
arrange with `S`.

## 8. Memory

A `SYS` file loads at $2000 and is entered there. Provisional, and the copy
buffer takes whatever is left over:

| | |
|---|---|
| `$0800-$1FFF` | ProDOS I/O buffers, 1K each and page-aligned. Two, for a copy with both files open. |
| `$2000-$4FFF` | code and tables |
| `$5000-$7AFF` | the two catalogue caches, ~10.8K |
| `$7B00-$B7FF` | copy buffer |
| `$B800-$BEFF` | reserved |
| `$BF00-$BFFF` | ProDOS global page |

**Auxiliary memory is not ours, and that is the interesting inversion.**
ZipEdit disconnects `/RAM` because on a 128K machine ProDOS puts it in exactly
the aux the text buffer wants. Here `/RAM` is a volume the user expects to see
and copy to, and making it disappear would be a bug rather than a feature. So
it stays, aux is not available, and the copy buffer lives in main memory. There
is plenty; a smaller buffer only means more passes.

## 9. What ProDOS is asked for

ZipEdit already has the calling convention — `JSR $BF00`, an inline command
byte, a pointer to a parameter block, and the error code captured on return —
and wrappers for `OPEN` `$C8`, `READ` `$CA`, `WRITE` `$CB`, `CLOSE` `$CC`,
`CREATE` `$C0` and `DESTROY` `$C1`.

New here: `ON_LINE` `$C5` to enumerate volumes, `GET_FILE_INFO` `$C4` and
`SET_FILE_INFO` `$C3` for the access byte and for carrying a file's attributes
across a copy, and `RENAME` `$C2`.

ProDOS pathnames are length-prefixed and **low** ASCII, unlike everything else
on this machine, and stop at 64 characters. Directories two or three levels
deep leave that budget comfortable.

## 10. What comes across from ZipEdit

Merlin has no linker — `put` pulls source text in — so these are **copied, not
shared**, and the two programs drift apart from the first commit. That is
expected: the display layer here will grow panel drawing that an editor has no
use for.

- the 80-column display layer, the row table and `geom.S`
- the main loop and the keyboard dispatch table
- the MLI wrappers, the error capture and the hex error reporter
- MouseText detection, which a two-panel layout wants for its rules and borders
- the prompt layer, for rename
- `genhelp.py`, so the help screen cannot drift from the keymap
- the whole Virtual ][ harness, `mkdisk.sh`, `tocard.sh`, `bootstrap.sh`

## 11. Deferred

Both are additive rather than structural, provided the first version is built
so they can be added:

- ~~**Copying a directory and its contents.**~~ **Built, and the prediction
  held**: because copy-one-file was a callable unit taking two full paths, and
  the path builder took a destination buffer, the tree walk wrapped it without
  unpicking anything.

  It is written **flat rather than recursively**. Only one directory is open at
  a time and `DIRBUF` holds one block of it, so descending would lose the
  parent's place -- so the place, which block and which entry, goes on a small
  stack, and the block is read again on the way back up with `SET_MARK` doing
  the seek rather than a scan from the start.

  `PATHWORK` and `PATHNEW` **are** the descent. Appending a component to both
  is going down and taking one off each is coming back up, which is why no
  second pair of buffers was wanted and why `CPYONE` needs no notion of depth:
  it copies whatever those two paths currently name.

  Depth stops at eight, well past what ProDOS's 64-character pathname budget
  allows in practice. `ESC` gives up part way, and a running count is shown,
  because a tree off a floppy is measured in seconds.
- **Checking free space before a copy.** Reading the volume bitmap is a
  precondition that bolts on in front. What cannot be deferred is handling the
  failure — see §7.

## 12. Testing

The bar is higher here than it was for an editor, because the program's whole
purpose is destructive operations on somebody's disks.

- **Fixture images built from the Mac**, with known contents, and compared
  block by block after every operation. AppleCommander does both halves.
- **Never point the suite at a real card, and never at the boot volume.**
- **Eject before rebuilding the fixture.** Virtual ][ buffers writes to a
  mounted image and flushes them when it is ejected, so rebuilding the file
  while the emulator still holds the old one means the next boot's eject
  writes stale blocks over the fresh one. It showed up as two blocks changing
  during a section that does not write at all.
- Assert against emulated RAM rather than the screen wherever possible, which
  is the habit `vii.sh dump` exists to support.
- Build the fixture-and-compare scaffolding **before** the first `DESTROY`
  call, not after it.

**As built.** `tests/mkfixture.sh` makes `build/FIXTURE.po` fresh every run --
two levels of subdirectory, several file types -- and `tests/run.sh` drives it.
`tools/imgblocks.py` compares two images block by block and can be told which
blocks it should find changed, which is how a destructive command will be
checked when there is one: take the image, do the thing, eject, and name the
blocks that were allowed to move.

The assertion that matters most today is the one that says the program does
not write at all. A whole navigating session -- down two levels, back up,
across to the other panel, a swap -- and the image comes back byte for byte.
Nothing on the screen could have told us that. `assert_inverse` is the same
idea in miniature: inverse text reads back as its own ASCII, so whether the
cursor line is really highlighted is a question only screen memory answers.

## 13. Open questions

- Whether the hint row earns its place, or a twenty-first entry is worth more.
- ~~Whether `L` toggles~~. It toggles, defined as *lock unless every target is
  locked already*, so one key always does the thing that is not already true.
- What a batch does when the destination directory fills mid-run: stop, or
  carry on and report? Stopping is probably right, since everything after it
  will fail too.

## 14. Running a program, and booting a slot

Two commands end ZipFiler rather than returning to it: `RET` on a program, and
`P`, which asks `PR#` and boots a slot. Both are as built and tested.

### The awkward part

A `SYS` file loads at $2000, which is where ZipFiler is running. The code doing
the reading would be overwritten partway through its own MLI call, so it cannot
be part of ZipFiler. A small stub is copied below $2000 and the jump is made
from there.

That stub is **position independent**: assembled at its natural address inside
the program, executed from a copy somewhere else. So it contains no `jsr` or
`jmp` to a label inside itself -- branches only, since those are relative and
move with the code. Absolute references are fine when they name something that
does not move: the MLI, the parameter blocks, the entry point.

This is the failure that does not announce itself. A `jsr` inside the stub
assembles perfectly and, at run time, jumps to an address now holding whatever
was just loaded. No test can catch it, because getting it wrong destroys memory
before anything can report. `tools/stubcheck.py` reads the source and refuses
the build, the way `dumcheck.py` does for overlapping `dum` blocks.

**Everything that can fail safely happens first**, while ZipFiler is whole: the
path, the prefix, the file's attributes, the `OPEN`. Any of those failing is a
message on the status row and nothing else. Once the `READ` starts there is no
way back, so the stub's only error path is `QUIT` -- the global page is still
there, and ZipFiler is not.

### The three types

| type | what happens |
|---|---|
| `SYS` $FF | loads at $2000 and is entered. The straightforward one. |
| `BIN` $06 | loads at the address in its own `aux_type` and is entered there. |
| `BAS` $FC | loads `BASIC.SYSTEM` and names the program to it. |

A `BIN` names its own address, and may name ours. `blocks_used` bounds how far
it reaches -- an over-estimate, since the last block is rarely full, which is
the right way for a safety check to be wrong. Three things must not be inside
that range: the stub, the 1K buffer ProDOS reads through, and the zero page and
stack underneath everything. The first two can move, so they do; the stub falls
back to the screen, which is no longer being drawn on. Only a program that
leaves nowhere to put them is refused, and the parameter blocks cannot move at
all, so a `BIN` covering them is refused outright.

### BASIC, and how it is told what to run

A BASIC program needs an interpreter, so what gets loaded is `BASIC.SYSTEM`.
The question is how to tell it *which* program.

**BASIC.SYSTEM keeps that name inside its own image.** At `$2006` there is a
length byte and up to fifteen characters, holding `STARTUP` as it comes off the
disk -- which is why a file of that name runs by itself. Overwrite the field
between loading the interpreter and entering it, and it runs whatever is named
there instead. A **name**, not a path: it is looked up in the prefix, which is
already the program's own directory.

That is what ProDOS 2.4's Bitsy Bye does, and it is the answer to "how does
Bitsy Bye manage it" -- **not** a smaller memory footprint. Footprint has
nothing to do with it. ZipFiler loads and runs `BASIC.SYSTEM` perfectly well;
what was missing was knowing where the interpreter keeps that name.

Two other ways in were tried first. Both were checked on the machine rather
than reasoned about, and both are recorded because they look plausible:

- **The pathname at `$0280`.** ProDOS convention says a launched system program
  finds its own pathname there, and ZipFiler sets it. BASIC.SYSTEM reads it,
  but only to work out a prefix -- it has no bearing on what runs. Confirmed
  both ways: a program called `HELLO` was not run, and the same program renamed
  `STARTUP` was.
- **Typing the command for it.** `KSW` is the hook every character `GETLN` reads
  passes through, so a routine there is indistinguishable from somebody at the
  keyboard, and it survives the load. But BASIC.SYSTEM puts `KSW` back to
  `KEYIN` as it starts, so it is never called. Checked rather than assumed:
  after a launch the feeder was still sitting intact on page 3 with `$38/$39`
  reading `$FD1B`. That code was removed -- dead code that looks like it works
  is worse than no code.

**How it was actually found**, since the method matters more than the answer:
Bitsy Bye and ZipFiler were put on the same disk, so the same launcher, same
`BASIC.SYSTEM` and same program could be compared directly. A do-nothing `SYS`
file was launched by each and the machine dumped afterwards; the two states
differed only in the high bit of the separators in `$0280` -- and setting those
changed nothing, which ruled the theory out. What settled it was disassembling
`BASIC.SYSTEM`'s first page and finding `STARTUP` sitting at `$2007` behind a
length byte.

### Booting a slot

### Booting a slot

`PR#6` is how an Apple II owner says "boot the disk". There is no ProDOS call
for it: the slot's firmware is entered at `$Cn00`. Before jumping, the switches
`DISPINIT` set are undone and `SETSLOTCXROM` is written so `$C100-$CFFF` is the
cards rather than the //e's own ROM -- **slot 3 especially**, where `$C300` is
the 80-column firmware until that is done.

**Slots 1, 2 and 4 to 7.** Not 3: on a //e `$C300` is the eighty-column
firmware rather than a card, and booting it is not what anybody means by
`PR#3`. Every other slot is the writer's business -- an empty one hangs the
machine, but so does `PR#` on a real Apple II, and this program cannot tell
from here which slots are filled.

`ESC` at the prompt returns, and the prompt carries a cursor. The alternative
is a machine that reboots on a mistyped key, which is not a trade anybody would
take.

### What this changes upstream

Section 1 listed "`RET` opens directories and nothing else" as a non-goal. It is
no longer one. Section 2's hint row is now exactly 80 columns, with nothing left
over.

The help screen was rewritten into **two columns**. It had been using eighty
columns as though they were forty, which cost rows it had all along; everything
now fits with room to spare.

**Progress is announced before the work, not after it.** A count printed after
each file is a count nobody sees until the run is over -- and what did appear at
the end was the destination rescan saying "working", which reads as the program
only starting once it had finished. `NITEM` is now the item in hand.

## 15. Replacing the quit routine — as built

Quitting any program on a patched disk comes back to ZipFiler instead of Bitsy
Bye, and the patch goes both ways.

### How quit actually works

`MLI QUIT ($65)` does not call anything. It **copies four pages out of the
second 4K bank of the language card down to `$1000` and jumps there**. That
block *is* the quit routine — on ProDOS 2.4 it is Bitsy Bye, `$D100-$D4FF`
landing at `$1000-$13FF`. Classic ProDOS copied three pages, which is where the
768-byte figure in the old documentation comes from; 2.4 copies four, which is
how Bitsy Bye affords its ~1K.

Every step of that was checked on the disk rather than taken on trust:

| | |
|---|---|
| `QUIT.SYSTEM` is 56 bytes | soft-switch cleanup, then `JSR $BF00` / `$65`. Quit **is** Bitsy Bye. |
| Bitsy Bye's strings in RAM | `$1303`, `$1327` — `$1000` plus their offset in the block |
| the same bytes in the PRODOS file | offset `$3A00`, **1023 of 1024 identical** |
| the one byte that differs | `$10BA`, set at boot; not part of the code |
| extended QUIT (`$EE` + pathname) | **not honoured** — lands in Bitsy Bye regardless |

So the block sits verbatim in the PRODOS file and can simply be replaced. This
is not a new idea: Bird's Better Bye patched itself into ProDOS the same way,
and Dave Cotter's `BYE.SYSTEM` existed to patch it back — which is why this
restores as well as installs.

### What replaces it

`src/zfquit.S`, assembled at `$1000` and 588 bytes of the 1024 available. It
does what a quit routine has to do first — clear decimal mode, bank the ROM
back in so the monitor's routines work, re-enable interrupts, put the screen in
a state something can print on — and then looks for `ZIPFILER.SYSTEM`.

**It scans rather than remembering.** `ON_LINE` gives every volume; each is
tried in turn. A disk gets copied to a card, a card gets repartitioned, a slot
changes — and a quit routine that cannot find its program leaves you with no
way out, because *the thing it replaced was the way out*. Not finding it prints
a message and waits for a key, then looks again: putting a disk in is a
recovery, a hang is not.

Having found it, the rest is the launcher from §14 in miniature: the pathname
to `$0280`, the prefix to the volume, then `OPEN`, `READ` to `$2000`, `CLOSE`,
jump. It needs no relocatable stub because it is already below `$2000`, and
the file lands over the top of it.

### Two patchers, because one is not enough

`tools/quitpatch.py` does it to a disk image on the Mac, and
`src/qpatch.S` -- `QPATCH.SYSTEM`, which ships on the disk -- does it on the
Apple, to a live volume.

The Mac one came first and is safer, and it is still right for a floppy image.
But **a large card partition, or a volume reached over a network share, is not
a `.po` file sitting on the Mac** -- and those are exactly the volumes worth
having ZipFiler come back on. There is no way to reach them except from the
machine they are attached to. §12 says never point the SUITE at a real disk;
that stands. This is a tool the writer aims deliberately, at a volume they
name, having been told what is in it.

**The order the on-Apple one works in is the whole safety argument**, not an
implementation detail, because it is writing to a volume's operating system:

1. Read PRODOS. Find the block by signature. Refuse unless there is **exactly
   one** match -- none, or several, means this is not a ProDOS it knows.
2. Write the original block to `QUIT.ORIG` on that volume.
3. **Read `QUIT.ORIG` back and compare it.** If the save did not survive the
   trip, stop. PRODOS has not been touched and the disk is as it was.
4. Only now write the new block -- `SET_MARK` and 1024 bytes, not a rewrite of
   the whole 17K file, which is a much bigger thing to be halfway through when
   something goes wrong.
5. Read that back and compare too.

It refuses to patch a volume that is already patched, for the same reason the
Mac one does: the saved original would become a patch and there would be no way
back. Restoring reads `QUIT.ORIG`, writes it back, and removes it.

The two keep their originals in different places, which is not an oversight:
the Mac tool has nowhere to put a file on the Apple's disk, and the Apple one
has no Mac. `<image>.quitsave` beside the image; `QUIT.ORIG` on the volume.

Both share three decisions:
- **It finds the block by signature, not by offset.** `D8 AD 82 C0 58` — the
  `cld` / `lda $C082` / `cli` any quit routine has to begin with. Hard-coding
  `$3A00` would silently patch the wrong kilobyte of a ProDOS that moved it.
  More than one match, or none, is refused rather than guessed at.
- **It refuses to install twice.** The original is saved to
  `<image>.quitsave` on the first install; installing again over a patched
  image would overwrite that saved copy with a patch, and there would be no way
  back. Restore first.

### What this does not do

It patches one volume. Every boot volume that should behave this way needs
doing separately, which is inherent: the quit routine lives in that volume's
own copy of PRODOS.

The change takes effect at the next boot of that volume, because what is in
memory was copied out of the language card when ProDOS started.


## 16. Chrome — MouseText tried, and turned down

The rule under the paths and the divider between the panels are ASCII: `-`,
`|` and `+`. MouseText was tried in their place and put back.

It should have won. §10 listed "MouseText detection, which a two-panel layout
wants for its rules and borders" among the things to bring across from ZipEdit,
`ALTCHARSET` has been on since the first day, and `$4C` and `$5F` draw
unbroken lines where the ASCII characters draw a row of dashes and a column of
bars. On its own each is plainly better.

**The junction is what killed it.** Where the divider meets the rule you would
need rule-left, vertical, and rule-right inside one cell, and no glyph does
that. The strokes sit on the EDGES of their cells -- `$4C` along the top, `$5F`
down the left -- so a cell holding one glyph can give:

| | horizontal | vertical |
|---|---|---|
| rule in the crossing cell | unbroken | **14px break**, most of a row |
| vertical in the crossing cell | **6px notch** | unbroken |
| a plus, as before | 7px hole | 14px break |

and nothing better. The plus was worst of all: it is centred, so it lined up
with neither stroke and simply sat in the gap.

That is the whole point. **These three ASCII glyphs are centred in their cells
and therefore agree with each other** -- the dash meets the bar in the middle,
and the plus has both strokes exactly where the other two put theirs. A
worse-looking line that joins beats a better-looking one that does not.

Read off the screen rather than reasoned about: the pixels were dumped from a
screenshot at each variant, because the glyph geometry is not something the
character codes show and the comments about it elsewhere are easy to misread.
Cells are 7x16; `$4C` lands at y=0..1 of its cell and `$5F` at x=0.

**A correction, made later.** The reasoning above said MouseText "has no corner
and no T-junction" and treated the edge-aligned strokes as the obstacle. The
T-junction part is right and is what matters here. The corner part was wrong,
and wrong because this project only ever knew one of the two verticals:

`$5A` draws a vertical down the **right** edge of its cell, where `$5F` draws
down the left. A stroke on a cell edge is a stroke on the boundary between two
cells, so a `$5A` vertical lands exactly where the next cell's `$4C` rule
begins, and they join. That is how Sneeze (Karl Bunker, 1992) closes all four
corners of a box with no corner glyph, and there is a corner glyph too --
`$54`, bottom-left.

None of that rescues the layout ZipFiler actually has, which is one rule
crossed by one divider: a cross still needs three strokes in one cell. But it
means **a boxed layout would be drawable in MouseText**, and the choice between
the two is about listing space rather than about what the character set can do.
See `docs/mousetext.md` for the glyph table, the construction, and what boxing
the panels would cost.

**What this does not settle.** On an original //e MouseText does not exist at
all and those codes are a second copy of inverse uppercase, so a border built
from them comes out as a row of L's. That would have needed detection had it
been kept. It was not, and ASCII draws the same on every machine in the family,
so the question no longer arises.
