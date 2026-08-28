#!/bin/bash
# tests/run.sh -- regression suite, driven through Virtual ][.
#
# Two rules from docs/design.md section 12, and they are not negotiable:
#
#   * the suite runs against a fixture image built fresh every time, never
#     against a real card and never against anybody's boot volume;
#   * an operation is checked by comparing the image block by block, not by
#     reading the screen. A file manager's worst bugs -- a delete that frees
#     somebody else's blocks, a copy that writes past its file -- leave the
#     screen looking perfectly correct.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VII="$ROOT/tools/vii.sh"
FIXTURE="$ROOT/build/FIXTURE.po"
LAUNCH="$ROOT/build/LAUNCH.po"
BEFORE="$ROOT/build/FIXTURE-before.po"

# One suite at a time: there is a single front machine, and a second run
# steers it out from under the first.
LOCK="${TMPDIR:-/tmp}/a2filer-suite.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    other="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
        echo "another test run (pid $other) holds the emulator" >&2
        exit 2
    fi
    echo "clearing a stale lock from pid ${other:-unknown}" >&2
    rm -rf "$LOCK"; mkdir "$LOCK" || exit 2
fi
echo "$$" > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM

ONLY="${1:-}"
section() { case "$1" in *"$ONLY"*) echo "$1"; return 0 ;; *) return 1 ;; esac }

pass=0; fail=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; shift; [ $# -gt 0 ] && printf '       %s\n' "$@"; fail=$((fail+1)); }

KEYSLEEP="${KEYSLEEP:-0.4}"
k() { "$VII" "$@" >/dev/null; sleep "$KEYSLEEP"; }

SCREEN="$ROOT/build/screen.txt"
snapshot() { "$VII" screen-raw > "$SCREEN"; }

# assert_row <name> <0-based row> <expected substring>
assert_row() {
    local name="$1" row="$2" want="$3" got
    got="$(sed -n "$((row+1))p" "$SCREEN")"
    if [[ "$got" == *"$want"* ]]; then ok "$name"; else
        bad "$name" "row $row wanted: $want" "row $row got:    ${got}"
    fi
}

# A row holds BOTH panels, so a bare substring check on one cannot tell which
# side it found. These cut to a panel first. Three assertions were written
# wrong before these existed.
left_of()  { sed -n "$(($1+1))p" "$SCREEN" | cut -c1-39; }
right_of() { sed -n "$(($1+1))p" "$SCREEN" | cut -c41-80; }

assert_left() {
    if [[ "$(left_of "$2")" == *"$3"* ]]; then ok "$1"; else
        bad "$1" "left panel row $2 wanted: $3" "got: $(left_of "$2")"; fi
}
assert_noleft() {
    if [[ "$(left_of "$2")" != *"$3"* ]]; then ok "$1"; else
        bad "$1" "left panel row $2 should not contain: $3"; fi
}
assert_right() {
    if [[ "$(right_of "$2")" == *"$3"* ]]; then ok "$1"; else
        bad "$1" "right panel row $2 wanted: $3" "got: $(right_of "$2")"; fi
}

# on_image <path> -- is that file there? AppleCommander exits 0 even when it
# prints "No match", so its exit code cannot be asked. This cost an hour.
on_image() {
    ! "$ROOT/tools/ac" -g "$FIXTURE" "$1" 2>&1 | grep -q "No match"
}

# assert_norow <name> <0-based row> <substring that must NOT be there>
assert_norow() {
    local name="$1" row="$2" bad_s="$3" got
    got="$(sed -n "$((row+1))p" "$SCREEN")"
    if [[ "$got" != *"$bad_s"* ]]; then ok "$name"; else
        bad "$name" "row $row should not contain: $bad_s"
    fi
}

# assert_inverse <name> <0-based row> -- the row's even columns live in aux,
# and an inverse screen code is below $80. Inverse text reads back as its own
# ASCII, so the screen cannot answer this and memory has to.
assert_inverse() {
    local name="$1" row="$2" addr got
    addr=$(python3 -c "
lo=[0x00,0x80]*12
hi=[0x04,0x04,0x05,0x05,0x06,0x06,0x07,0x07]*3
base=[0,0x28,0x50][$row//8]
print(hex((hi[$row]<<8)|lo[$row]|base))")
    "$VII" dump "$addr" 8 1 "$ROOT/build/inv.bin" >/dev/null 2>&1
    got=$(python3 -c "
d=open('$ROOT/build/inv.bin','rb').read()
print('yes' if all(b<0x80 for b in d) else 'no')")
    if [ "$got" = "yes" ]; then ok "$name"; else
        bad "$name" "row $row is not drawn inverse"
    fi
}

# A destructive section starts from a fixture nobody has written to yet, so
# sections cannot contaminate each other.
eject_now() {
    osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
    sleep 1
}

fresh_fixture() {
    # Eject FIRST. Virtual ][ buffers writes to a mounted image and flushes
    # them when it is ejected -- so rebuilding the file while the emulator
    # still holds the old one means the next boot's eject writes stale blocks
    # straight over the fresh fixture. That showed up as two blocks changing
    # during a section that does not write at all.
    eject_now
    "$ROOT/tests/mkfixture.sh" >/dev/null
    cp "$FIXTURE" "$BEFORE"
}

# assert_blocks <name> <block> [<block>...] -- exactly these and no others
assert_blocks() {
    local name="$1"; shift
    local out
    out="$(python3 "$ROOT/tools/imgblocks.py" "$BEFORE" "$FIXTURE" --expect "$@" 2>&1)"
    case "$out" in
        changed\ exactly*) ok "$name" ;;
        *) bad "$name" "$out" ;;
    esac
}

assert_identical() {
    local out
    out="$(python3 "$ROOT/tools/imgblocks.py" "$BEFORE" "$FIXTURE" 2>&1)"
    if [ "$out" = "identical" ]; then ok "$1"; else bad "$1" "$out"; fi
}

# left panel in /ZIPFILER, right panel in /ZIPFILER/DOCS, focus back on the left
setup_copy() {
    k key "down arrow"; k line ""      # left into /ZIPFILER
    k ctrl I                           # focus the right panel
    k key "down arrow"; k line ""      # right into /ZIPFILER
    k key "down arrow"; k line ""      # and on into DOCS
    k ctrl I                           # focus back to the left
    "$VII" settle 2 >/dev/null
}

# the prompt opens pre-filled with the existing name
prompt_clear() { local i; for i in $(seq 1 15); do "$VII" key "left arrow" >/dev/null; done; sleep 0.3; }

reboot() {
    "$VII" boot "$FIXTURE" >/dev/null || { echo "boot failed" >&2; exit 1; }
    "$VII" speed maximum >/dev/null
    "$VII" kbdelay 0.2 >/dev/null
    "$VII" await "(volumes)" 60 >/dev/null || { echo "never reached the volume list" >&2; exit 1; }
    "$VII" settle 2 >/dev/null
}

echo "fixture: $FIXTURE"
cp "$FIXTURE" "$BEFORE"

#--------------------------------------
# The volume list, which is what both panels open on.
#--------------------------------------
if section "volume list"; then
reboot
snapshot
assert_row "the left panel names itself"          0 ">(volumes)"
assert_row "and so does the right"                0 "(volumes)"
assert_row "the boot volume is listed"            3 "ZIPFILER"
assert_row "a volume shows as VOL, not a type"    3 "VOL"
# ASCII rather than MouseText, and deliberately -- see docs/design.md 16. The
# three glyphs are centred in their cells and so meet each other; MouseText's
# sit on the cell edges and it has no junction at all.
assert_row "the divider runs down the screen"     2 "|"
assert_row "the rule crosses it"                  1 "+"
assert_row "and the rule runs the width"          1 "----------"
assert_inverse "the cursor line is drawn inverse" 2
fi

#--------------------------------------
# Reading a real directory.
#--------------------------------------
if section "directory"; then
reboot
k key "down arrow"          # onto ZIPFILER
k line ""                   # RET: into it
"$VII" settle 2 >/dev/null
snapshot
assert_row "the path is the volume"               0 "/ZIPFILER"
assert_row "the editor's own SYS file is there"   2 "ZIPFILER.SYSTEM"
assert_row "with its type"                        2 "SYS"
# derived from the image rather than written in, so it does not break every
# time the program changes size -- and it checks the panel against ProDOS's
# own accounting rather than against a number I typed
sysblk=$("$ROOT/tools/ac" -l "$FIXTURE" | awk '/ZIPFILER.SYSTEM/ {print $3+0}')
assert_row "and its size in blocks"               2 "$sysblk"
assert_row "a subdirectory reads as DIR"          3 "DOCS"
assert_row "ProDOS itself is listed"              6 "PRODOS"
assert_row "with the blocks it really occupies"   6 "34"
fi

#--------------------------------------
# Down two levels and back out, ending at the volume list.
#--------------------------------------
if section "navigation"; then
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
k key "down arrow"; k line ""          # into /ZIPFILER/DOCS
"$VII" settle 2 >/dev/null
snapshot
assert_row "two levels down"                      0 "/ZIPFILER/DOCS"
assert_row "and its contents"                     2 "NOTE.TXT"

k key "down arrow"; k line ""          # into /ZIPFILER/DOCS/DRAFTS
"$VII" settle 2 >/dev/null
snapshot
assert_row "three levels down"                    0 "/ZIPFILER/DOCS/DRAFTS"
assert_row "both drafts are there"                2 "CH1.TXT"
assert_row "and the second"                       3 "CH2.TXT"

k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up one"                               0 "/ZIPFILER/DOCS"
k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up two"                               0 "/ZIPFILER"
k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up out of a root is the volume list"  0 "(volumes)"
fi

#--------------------------------------
# Two panels that do not know about each other.
#--------------------------------------
if section "two panels"; then
reboot
k key "down arrow"; k line ""          # left into /ZIPFILER
k key "down arrow"; k line ""          # left into /ZIPFILER/DOCS
"$VII" settle 2 >/dev/null
k ctrl I                               # TAB
"$VII" settle 2 >/dev/null
snapshot
assert_row "focus moved to the right panel"       0 ">(volumes)"
assert_norow "and left the left one unmarked"     0 ">/ZIPFILER/DOCS"
assert_row "the left panel kept its place"        0 "/ZIPFILER/DOCS"
assert_row "the right panel still lists volumes"  2 "RAM"

k key "down arrow"; k line ""          # right into /ZIPFILER
"$VII" settle 2 >/dev/null
snapshot
assert_row "the panels are in different places"   0 "/ZIPFILER/DOCS"
assert_row "each with its own listing"            2 "NOTE.TXT"
assert_row "and the right one has the root"       2 "ZIPFILER.SYSTEM"

k text "S"                             # swap
"$VII" settle 2 >/dev/null
snapshot
assert_row "S exchanges them"                     0 "/ZIPFILER  "
assert_row "the other way round"                  0 "/ZIPFILER/DOCS"
fi

#--------------------------------------
# Tagging. A command acts on the tagged set if there is one and on the cursor
# line if there is not, so there is never a mode to be in -- design.md §6.
#--------------------------------------
if section "tagging"; then
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
"$VII" settle 2 >/dev/null
k text " "                             # tag ZIPFILER.SYSTEM, step down
k text " "                             # tag DOCS, step down
"$VII" settle 2 >/dev/null
snapshot
assert_row "the first is marked"                  2 "> ZIPFILER.SYSTEM"
assert_row "and so is the second"                 3 "> DOCS"
assert_norow "the one after is not"               4 ">"
assert_row "the count is in the status row"      22 "2 tagged"
assert_row "and the blocks they come to"         22 "blocks"

# The blocks are the number worth knowing before a copy, so check the sum
# rather than just its presence: ZIPFILER.SYSTEM plus a one-block directory.
# cut to the left panel first: a row holds both, so the last field of the
# whole line belongs to the other one
blocks=$(sed -n '23p' "$SCREEN" | cut -c1-39 | sed 's/.*tagged, *//;s/ *blocks.*//')
sysblk=$(sed -n '3p'  "$SCREEN" | cut -c1-39 | awk '{print $NF}')
if [ "$blocks" = "$((sysblk + 1))" ]; then
    ok "and the sum is right"
else
    bad "and the sum is right" "status says $blocks, entries say $sysblk + 1"
fi

k key "left arrow"                     # back out: a new listing
"$VII" settle 2 >/dev/null
snapshot
assert_norow "tags go when the listing does"      2 ">"
assert_row "and the status says so"              22 "entries"
fi

#--------------------------------------
# L, and the first thing in the program that writes.
#
# One byte of one directory entry, so the block compare can be exact: if
# anything else moved, something is wrong that the screen would never show.
#--------------------------------------
if section "lock"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
k key "down arrow"; k key "down arrow" # onto README.TXT
"$VII" settle 2 >/dev/null
snapshot
assert_row "README starts out unlocked"           4 "  README.TXT"

k text "L"
"$VII" settle 2 >/dev/null
snapshot
assert_row "L marks it locked"                    4 "*README.TXT"
assert_row "and says what it did"                22 "1 locked"

eject_now
assert_blocks "exactly one directory block moved" 2
if "$ROOT/tools/ac" -l "$FIXTURE" | grep -q '^\* README.TXT'; then
    ok "and ProDOS agrees the file is locked"
else
    bad "and ProDOS agrees the file is locked" \
        "$("$ROOT/tools/ac" -l "$FIXTURE" | grep README)"
fi
fi

#--------------------------------------
# The same key the other way. A lock and an unlock must leave the disk exactly
# as it was found -- not nearly, exactly. Nothing but a block compare can say.
#--------------------------------------
if section "unlock"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
k key "down arrow"; k key "down arrow"
k text "L"                             # lock
"$VII" settle 2 >/dev/null
k text "L"                             # and unlock again
"$VII" settle 2 >/dev/null
snapshot
assert_row "the mark has gone"                    4 "  README.TXT"
assert_row "and it says so"                      22 "1 unlocked"
eject_now
assert_identical "locking and unlocking leaves the disk byte for byte as it was"
fi

#--------------------------------------
# A tagged set, which is what the command is really for.
#--------------------------------------
if section "lock a set"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
"$VII" settle 2 >/dev/null
k text " "                             # tag ZIPFILER.SYSTEM
k text " "                             # tag DOCS
k text " "                             # tag README.TXT
k text "L"
"$VII" settle 2 >/dev/null
snapshot
assert_row "all three are locked"                 2 "*ZIPFILER.SYSTEM"
assert_row "including the directory"              3 "*DOCS"
assert_row "and the third"                        4 "*README.TXT"
assert_row "and it counted them"                 22 "3 locked"
assert_norow "the untagged one is untouched"      5 "*DATA.BIN"
eject_now
assert_blocks "and still only the one block"      2
fi

#--------------------------------------
# A volume has no access byte, so L must say so rather than fail quietly.
#--------------------------------------
if section "lock refuses a volume"; then
fresh_fixture
reboot
k text "L"
"$VII" settle 2 >/dev/null
snapshot
assert_row "it explains itself"                  22 "volume cannot be locked"
eject_now
assert_identical "and wrote nothing"
fi

#--------------------------------------
# R. The only place in the program that takes text, which is what lets every
# other command be a bare letter.
#--------------------------------------
if section "rename"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
k key "down arrow"; k key "down arrow" # onto README.TXT
"$VII" settle 2 >/dev/null
k text "R"
snapshot
assert_row "the prompt opens holding the old name" 22 "NEW NAME: README.TXT"

prompt_clear
k text "NOTES.MD"
k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_row "the listing shows the new name"        4 "NOTES.MD"
assert_norow "and not the old one"                 4 "README"
assert_row "and it says what it did"              22 "renamed"

eject_now
assert_blocks "only the directory block moved"     2
if "$ROOT/tools/ac" -g "$FIXTURE" NOTES.MD 2>/dev/null | grep -q "read me"; then
    ok "and the file still holds what it held"
else
    bad "and the file still holds what it held" "contents lost or unreadable"
fi
fi

#--------------------------------------
# ESC out of the prompt, and a name ProDOS would refuse. Neither may write.
#--------------------------------------
if section "rename refuses"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
k key "down arrow"; k key "down arrow"
"$VII" settle 2 >/dev/null

k text "R"
prompt_clear
k text "SOMETHING"
"$VII" key esc >/dev/null; sleep 0.4
"$VII" settle 2 >/dev/null
snapshot
assert_row "ESC leaves it alone"                   4 "README.TXT"
assert_row "and says so"                          22 "left alone"

k text "R"
prompt_clear
k text "9BAD"                          # a name may not start with a digit
k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_row "a name starting with a digit is refused" 22 "letter first"
assert_row "and the file keeps its name"           4 "README.TXT"

eject_now
assert_identical "neither refusal wrote anything"
fi

#--------------------------------------
# Rename ignores tags: renaming five files to one name means nothing.
#--------------------------------------
if section "rename ignores tags"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
"$VII" settle 2 >/dev/null
k text " "                             # tag ZIPFILER.SYSTEM, cursor moves to DOCS
k text " "                             # tag DOCS, cursor moves to README.TXT
k text "R"
snapshot
assert_row "the prompt offers the CURSOR line"    22 "NEW NAME: README.TXT"
"$VII" key esc >/dev/null; sleep 0.4
eject_now
assert_identical "and nothing was written"
fi

#--------------------------------------
# D. The one command with nothing behind it.
#
# A delete frees blocks, so it must move the directory block AND the volume
# bitmap -- and nothing else. A delete that freed somebody else's blocks would
# look exactly like this one on screen.
#--------------------------------------
if section "delete"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
k key "down arrow"; k key "down arrow"; k key "down arrow"   # onto DATA.BIN
"$VII" settle 2 >/dev/null
snapshot
assert_row "DATA.BIN is there to start with"      5 "DATA.BIN"

k text "D"
snapshot
assert_row "it asks first"                       22 "cannot be undone"
k text "N"
"$VII" settle 2 >/dev/null
snapshot
assert_row "N keeps it"                           5 "DATA.BIN"
assert_row "and says so"                         22 "kept"

k text "D"
k text "Y"
"$VII" settle 2 >/dev/null
snapshot
assert_norow "Y removes it from the listing"      5 "DATA.BIN"
assert_row "and counts it"                       22 "1 deleted"
assert_row "the file below has moved up"          5 "PRODOS"

eject_now
assert_blocks "the directory and the bitmap, and nothing else" 2 6
if "$ROOT/tools/ac" -g "$FIXTURE" README.TXT 2>/dev/null | grep -q "read me"; then
    ok "the files around it are untouched"
else
    bad "the files around it are untouched" "README.TXT no longer reads"
fi
fi

#--------------------------------------
# Declining must write nothing at all.
#--------------------------------------
if section "delete declined"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
k key "down arrow"; k key "down arrow"; k key "down arrow"
k text "D"
k text "N"
"$VII" settle 2 >/dev/null
eject_now
assert_identical "saying no leaves the disk exactly as it was"
fi

#--------------------------------------
# A locked file is not deleted -- the lock is the writer's stated intent, and
# L is one key away. design.md section 7.
#--------------------------------------
if section "delete refuses a locked file"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
k key "down arrow"; k key "down arrow" # onto README.TXT
k text "L"                             # lock it
"$VII" settle 2 >/dev/null
snapshot
assert_row "it is locked"                         4 "*README.TXT"

k text "D"
"$VII" settle 2 >/dev/null
snapshot
assert_row "and D will not take it"              22 "locked, and so not deleted"
assert_row "the file is still there"              4 "README.TXT"

eject_now
# only the lock wrote; a delete would have moved the bitmap as well
assert_blocks "only the lock wrote, not the delete" 2
fi

#--------------------------------------
# A non-empty directory. ProDOS refuses this itself -- verified, error $4E --
# and the refusal is reported as what it is rather than as a lock.
#--------------------------------------
if section "delete refuses a full directory"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
k key "down arrow"                     # onto DOCS
k text "D"
k text "Y"
"$VII" settle 2 >/dev/null
snapshot
assert_row "it says why"                         22 "directory has to be empty"
assert_row "and DOCS survives"                    3 "DOCS"
eject_now
assert_identical "and nothing at all was written"
fi

#--------------------------------------
# A tagged set, which is what the command is really for.
#--------------------------------------
if section "delete a set"; then
fresh_fixture
reboot
k key "down arrow"; k line ""              # into /ZIPFILER
k key "down arrow"; k line ""              # onto DOCS, into it
"$VII" settle 2 >/dev/null
snapshot
assert_row "in DOCS"                              0 "/ZIPFILER/DOCS"
k key "down arrow"; k line ""              # onto DRAFTS, into it
"$VII" settle 2 >/dev/null
snapshot
assert_row "and then in DRAFTS"                   0 "/ZIPFILER/DOCS/DRAFTS"
k text " "                                 # tag CH1.TXT
k text " "                                 # tag CH2.TXT
snapshot
assert_row "two tagged"                          22 "2 tagged"
k text "D"
snapshot
assert_row "it asks about both"                  22 "2 to delete"
k text "Y"
"$VII" settle 2 >/dev/null
snapshot
assert_row "both are gone"                       22 "2 deleted"
assert_norow "the listing is empty"               2 "CH"
fi

#--------------------------------------
# C, always left to right.
#
# The test that matters is not that a file appears but that it is the same
# file: extracted from the image and compared byte for byte against its
# source. A copy that truncated, or that wrote the wrong type, would look
# perfectly right in the listing.
#--------------------------------------
if section "copy"; then
fresh_fixture
reboot
setup_copy
snapshot
assert_row "left panel is the root"               0 "/ZIPFILER "
assert_row "right panel is DOCS"                  0 "/ZIPFILER/DOCS"

k key "down arrow"; k key "down arrow"   # onto README.TXT
k text "C"
"$VII" settle 3 >/dev/null
snapshot
assert_row "it says it copied one"               22 "1 copied"
assert_row "and it is in the right panel"         4 "README.TXT"

eject_now
"$ROOT/tools/ac" -g "$FIXTURE" README.TXT      > "$ROOT/build/src.bin" 2>/dev/null
"$ROOT/tools/ac" -g "$FIXTURE" DOCS/README.TXT > "$ROOT/build/dst.bin" 2>/dev/null
if cmp -s "$ROOT/build/src.bin" "$ROOT/build/dst.bin" && [ -s "$ROOT/build/dst.bin" ]; then
    ok "and it is the same file, byte for byte"
else
    bad "and it is the same file, byte for byte" "$(ls -l "$ROOT"/build/src.bin "$ROOT"/build/dst.bin)"
fi
# the same type and the same size, which a listing would show but a copy
# could still get wrong
srcline=$("$ROOT/tools/ac" -l "$FIXTURE" | grep -c "README.TXT TXT 001")
if [ "$srcline" = "2" ]; then
    ok "both are TXT and one block"
else
    bad "both are TXT and one block" "$("$ROOT/tools/ac" -l "$FIXTURE" | grep README)"
fi
fi

#--------------------------------------
# Asked once for the batch, not once a file.
#--------------------------------------
if section "copy overwrite"; then
fresh_fixture
reboot
setup_copy
k key "down arrow"; k key "down arrow"
k text "C"                             # the first copy
"$VII" settle 3 >/dev/null
k text "C"                             # and again, so it is already there
"$VII" settle 2 >/dev/null
snapshot
assert_row "it asks what to do"                  22 "already there"

k text "S"
"$VII" settle 2 >/dev/null
snapshot
assert_row "S skips it"                          22 "the rest were skipped"

k text "C"
k text "O"
"$VII" settle 3 >/dev/null
snapshot
assert_row "O overwrites it"                     22 "1 copied"
eject_now
if "$ROOT/tools/ac" -g "$FIXTURE" DOCS/README.TXT 2>/dev/null | grep -q "read me"; then
    ok "and what is there is still right"
else
    bad "and what is there is still right" "the overwritten copy does not read"
fi
fi

#--------------------------------------
# Copying a file onto itself is easy to arrange and never wanted.
#--------------------------------------
if section "copy refuses the same directory"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # left into /ZIPFILER
k ctrl I
k key "down arrow"; k line ""          # right into /ZIPFILER too
k ctrl I
"$VII" settle 2 >/dev/null
k text "C"
"$VII" settle 2 >/dev/null
snapshot
assert_row "it says so"                          22 "same directory"
eject_now
assert_identical "and writes nothing"
fi

#--------------------------------------
# A directory, and everything in it.
#
# The listing can only show that a directory appeared. What has to be checked
# is the whole shape underneath it, two levels down, with the contents of
# every file compared against its source.
#--------------------------------------
if section "copy a directory"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # left into /ZIPFILER
"$VII" settle 2 >/dev/null
k text "N"; k text "BACKUP"; k line "" # somewhere to put it
"$VII" settle 2 >/dev/null
k ctrl I                               # the right panel goes into it
k key "down arrow"; k line ""
"$VII" settle 2 >/dev/null
k key "down arrow"; k key "down arrow"; k key "down arrow"; k key "down arrow"
k line ""
"$VII" settle 2 >/dev/null
k ctrl I
snapshot
assert_row "the destination is the new directory"  0 "/ZIPFILER/BACKUP"

k key "down arrow"                     # onto DOCS
k text "C"
"$VII" settle 4 >/dev/null
snapshot
# one thing was asked for -- a directory -- and it came to three files
assert_row "one thing was asked for"              22 "1 copied"
assert_row "and it came to three files"           22 "3 files"
assert_row "and the directory is on the other side" 2 "DOCS"

eject_now
ok_tree=1
for f in DOCS/NOTE.TXT DOCS/DRAFTS/CH1.TXT DOCS/DRAFTS/CH2.TXT; do
    a=$("$ROOT/tools/ac" -g "$FIXTURE" "$f" 2>/dev/null)
    b=$("$ROOT/tools/ac" -g "$FIXTURE" "BACKUP/$f" 2>/dev/null)
    [ -n "$a" ] && [ "$a" = "$b" ] || ok_tree=0
done
if [ "$ok_tree" = "1" ]; then
    ok "and every file two levels down matches its source"
else
    bad "and every file two levels down matches its source" \
        "$("$ROOT/tools/ac" -l "$FIXTURE" | sed -n '9,15p')"
fi
if "$ROOT/tools/ac" -l "$FIXTURE" | grep -q "DRAFTS DIR"; then
    ok "the subdirectory below it was made too"
else
    bad "the subdirectory below it was made too" "no DRAFTS under BACKUP"
fi
fi

#--------------------------------------
# A tagged set, which is what the command is for.
#--------------------------------------
if section "copy a set"; then
fresh_fixture
reboot
setup_copy
k key "down arrow"; k key "down arrow" # onto README.TXT
k text " "                             # tag it; cursor steps to DATA.BIN
k text " "                             # tag that too
snapshot
assert_row "two tagged"                          22 "2 tagged"
k text "C"
"$VII" settle 3 >/dev/null
snapshot
assert_row "both went"                           22 "2 copied"
eject_now
if "$ROOT/tools/ac" -g "$FIXTURE" DOCS/DATA.BIN >/dev/null 2>&1 &&
   "$ROOT/tools/ac" -g "$FIXTURE" DOCS/README.TXT >/dev/null 2>&1; then
    ok "and both are on the other side"
else
    bad "and both are on the other side" "$("$ROOT/tools/ac" -l "$FIXTURE" | sed -n '2,8p')"
fi
fi

#--------------------------------------
# The help screen, and Q.
#--------------------------------------
if section "help and quit"; then
fresh_fixture
reboot
k text "?"
"$VII" settle 2 >/dev/null
snapshot
assert_row "the help screen comes up"             0 "A FILE MANAGER FOR PRODOS 8"
assert_row "it lists the keys"                    6 "ARROWS"
# Two columns, so a row carries one heading from each. The whole point of the
# rewrite was that eighty columns were being used as forty.
assert_row "the left column has the movement keys" 5 "GETTING ABOUT"
assert_row "and the right one the file commands"   5 "WORKING ON FILES"
assert_row "P is listed"                          18 "PR# -- boot a slot"
assert_row "and what RET runs"                    17 "SYS, BIN or BAS"
assert_row "and says how to leave"                21 "press any key"

k text " "
"$VII" settle 2 >/dev/null
snapshot
assert_row "any key puts the panels back"         0 "(volumes)"
assert_row "and the hint row names the new keys" 23 "N ew"
assert_row "including quit"                      23 "Q uit"

# ESC used to quit from here, which was too easy to do by accident
"$VII" key esc >/dev/null; sleep 0.4
"$VII" settle 2 >/dev/null
snapshot
assert_row "ESC no longer drops out of the program" 0 "(volumes)"
fi

#--------------------------------------
# N, a new directory. Needed all the more while a directory cannot be copied.
#--------------------------------------
if section "new directory"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
"$VII" settle 2 >/dev/null
k text "N"
snapshot
assert_row "it asks for a name"                  22 "NEW DIRECTORY:"

k text "ARCHIVE"
k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_row "and it appears as a directory"        6 "ARCHIVE         DIR"
assert_row "and says so"                         22 "made"

# a directory that ProDOS will actually walk into
k key "down arrow"; k key "down arrow"; k key "down arrow"; k key "down arrow"
k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_row "and it can be entered"                0 "/ZIPFILER/ARCHIVE"
assert_row "and starts out empty"                22 "0 entries"

eject_now
if "$ROOT/tools/ac" -l "$FIXTURE" | grep -q "ARCHIVE DIR"; then
    ok "ProDOS agrees it is a directory"
else
    bad "ProDOS agrees it is a directory" "$("$ROOT/tools/ac" -l "$FIXTURE" | grep -i archive)"
fi
fi

#--------------------------------------
# A name ProDOS would refuse must not make anything.
#--------------------------------------
if section "new directory refuses"; then
fresh_fixture
reboot
k key "down arrow"; k line ""
"$VII" settle 2 >/dev/null
k text "N"
k text "9NO"
k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_row "a digit first is refused"            22 "letter first"
k text "N"
"$VII" key esc >/dev/null; sleep 0.4
"$VII" settle 2 >/dev/null
snapshot
assert_row "and ESC abandons it"                 22 "left alone"
eject_now
assert_identical "neither wrote anything"
fi

#--------------------------------------
# M. Copy across, then take the original away.
#
# The thing to check is not that it appeared on one side but that it is gone
# from the other AND still readable -- a move that lost the file would leave
# both listings looking entirely reasonable.
#--------------------------------------
if section "move"; then
fresh_fixture
reboot
setup_copy
k key "down arrow"; k key "down arrow"   # onto README.TXT
"$VII" settle 2 >/dev/null
k text "M"
"$VII" settle 3 >/dev/null
snapshot
assert_row "it says it moved one"                22 "1 moved"
assert_noleft "gone from the left panel"          4 "README.TXT"
assert_right  "and arrived on the right"          4 "README.TXT"

eject_now
if on_image DOCS/README.TXT && "$ROOT/tools/ac" -g "$FIXTURE" DOCS/README.TXT 2>/dev/null | grep -q "read me"; then
    ok "and it still reads at its new place"
else
    bad "and it still reads at its new place" "the moved file does not read"
fi
if on_image README.TXT; then
    bad "and no longer exists at the old one" "the source is still there"
else
    ok "and no longer exists at the old one"
fi
fi

#--------------------------------------
# What M will not do. A directory would need its source tree removed
# afterwards and recursive delete is not built; a locked file is not taken
# away for the same reason D will not take it.
#--------------------------------------
if section "move refuses"; then
fresh_fixture
reboot
setup_copy
k key "down arrow"                     # onto DOCS, a directory
k text "M"
"$VII" settle 2 >/dev/null
snapshot
assert_row "a directory is not moved"            22 "directories and locked"
assert_row "and is still there"                   3 "DOCS"

k key "down arrow"                     # onto README.TXT
k text "L"                             # lock it
"$VII" settle 2 >/dev/null
k text "M"
"$VII" settle 2 >/dev/null
snapshot
assert_row "a locked file is not moved either"   22 "directories and locked"
assert_row "and it is still there, still locked"  4 "*README.TXT"
fi

#--------------------------------------
# A, which is also the only way to clear a set without leaving the directory.
#--------------------------------------
if section "tag all"; then
fresh_fixture
reboot
k key "down arrow"; k line ""          # into /ZIPFILER
"$VII" settle 2 >/dev/null
snapshot
assert_row "nothing tagged to begin with"        22 "entries"

k text "A"
"$VII" settle 2 >/dev/null
snapshot
assert_left "the first is tagged"                 2 "> ZIPFILER.SYSTEM"
assert_left "and the last"                        6 "> PRODOS"
assert_row  "and the count is the whole listing" 22 "5 tagged"

k text "A"
"$VII" settle 2 >/dev/null
snapshot
assert_noleft "pressing it again clears them"     2 ">"
assert_row    "and the status says so"           22 "entries"

# and it acts on the focused panel, not both
k text "A"
k ctrl I
"$VII" settle 2 >/dev/null
snapshot
assert_row "the other panel is untouched"        22 "entries"
fi

#--------------------------------------
# The whole of it is read-only, and this is the assertion that says so.
#
# Everything above navigated, scrolled and swapped. Nothing in the program
# writes, so the image must come back byte for byte -- and a block compare is
# the only thing that can tell us, since a stray write would leave the screen
# looking exactly as correct as it does now.
#--------------------------------------
if section "reads nothing but reads"; then
fresh_fixture
"$VII" boot "$FIXTURE" >/dev/null
"$VII" await "(volumes)" 60 >/dev/null
k key "down arrow"; k line ""
k key "down arrow"; k line ""
k key "left arrow"
k ctrl I
k text "S"
"$VII" settle 2 >/dev/null
osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
sleep 1
out="$(python3 "$ROOT/tools/imgblocks.py" "$BEFORE" "$FIXTURE")"
if [ "$out" = "identical" ]; then
    ok "navigating the image changes not one block of it"
else
    bad "navigating the image changes not one block of it" "$out"
fi
fi

#--------------------------------------
# Launching a program, and booting a slot
#
# These run against their own image -- see tests/mklaunch.sh. Every program on
# it changes what the root listing holds, and a dozen assertions above count
# entries and name the row they are on.
#
# The programs launched here print a phrase ZipFiler cannot draw, then stop.
# That is the only proof the screen can carry that something really started:
# a launcher that clears the screen and hangs looks identical to one that
# worked, right up until you read what is on it.
#
# RUNME also prints the pathname it found at $0280 and the prefix it was given.
# Both are set by the launcher, both are invisible until some real program
# needs them, and neither can be checked any other way.
#--------------------------------------
if section "launching a program"; then
eject_now
"$ROOT/tests/mklaunch.sh" >/dev/null
LAUNCHED="$ROOT/build/launched.txt"

# run_at <steps> [<steps>...] -- boot the launch image, then for each argument
# walk that many rows down and press RET. More than one argument descends: the
# listing is
#     0 ZIPFILER.SYSTEM   3 RUNBIN     6 BASIC.SYSTEM
#     1 RUNME             4 CLASH      7 PRODOS
#     2 PROGS  (DEEP, HELLO)           5 PLAIN.TXT
# Arguments are steps:marker pairs. The marker is text that appears once the
# directory that RET opened has been read -- waited for, not slept through,
# because reading one is slow and this machine has no keyboard buffer: a RET
# sent while ZipFiler is still reading is not queued, it is gone. That cost a
# cascade of failures where the wrong program launched.
launch_boot() {
    "$VII" boot "$LAUNCH" >/dev/null || { echo "boot failed" >&2; exit 1; }
    "$VII" speed maximum >/dev/null
    "$VII" kbdelay 0.2 >/dev/null
    "$VII" await "(volumes)" 60 >/dev/null || { echo "no volume list" >&2; exit 1; }
    "$VII" settle 2 >/dev/null
    k key "down arrow"; k line ""          # into /ZIPFILER
    "$VII" await "ZIPFILER.SYSTEM" 60 >/dev/null || { echo "no root listing" >&2; exit 1; }
    "$VII" settle 2 >/dev/null
}

run_at() {
    launch_boot
    local arg steps marker i
    for arg in "$@"; do
        steps="${arg%%:*}"
        marker="${arg#*:}"
        # NOT $(seq 1 $steps): BSD seq counts DOWNWARDS when the first
        # number is the larger, so "seq 1 0" prints two lines rather than
        # none, and a zero-step move sent two arrows. That launched the file
        # BELOW the one under test, and the failure it produced named the
        # wrong program.
        i=0
        while [ "$i" -lt "$steps" ]; do k key "down arrow"; i=$((i+1)); done
        k line ""
        if [ "$marker" != "$arg" ]; then
            "$VII" await "$marker" 60 >/dev/null || bad "never opened: $marker"
        fi
        "$VII" settle 3 >/dev/null
    done
    "$VII" settle 5 >/dev/null
    "$VII" screen > "$LAUNCHED"
}

launched_says() {
    if grep -q "$2" "$LAUNCHED"; then ok "$1"; else
        bad "$1" "wanted on screen: $2" "got: $(head -4 "$LAUNCHED" | tr '\n' '/')"; fi
}

#--- a SYS file at the root of the volume
run_at 1
launched_says "RET on a SYS file starts it"            "RUNME SAYS HELLO"
launched_says "with the path ProDOS leaves at 0280"    "^/ZIPFILER/RUNME$"
launched_says "and the prefix set to its directory"    "^/ZIPFILER/$"

#--- the same program one level down, which is where a launcher that only ever
#    built a root path would come apart
run_at 2:DEEP 0
launched_says "a program in a subdirectory starts too" "RUNME SAYS HELLO"
launched_says "with the whole path, not just the name" "^/ZIPFILER/PROGS/DEEP$"
launched_says "and the prefix follows it down"         "^/ZIPFILER/PROGS/$"

#--- a BIN, which names its own load address rather than taking $2000
run_at 3
launched_says "RET on a BIN file starts it"            "RUNBIN AT 0300"
launched_says "at the address the FILE named"          "^/ZIPFILER/RUNBIN$"

#--- a BIN that would land on the launcher's own parameter blocks. It has to be
#    refused: reading it in would destroy the block mid-read, and the machine
#    with it. The message matters less than that ZipFiler is still there.
run_at 4
launched_says "a BIN that would land on the loader is refused" "NO ROOM TO LOAD IT SAFELY"
launched_says "and ZipFiler is still running"                  "ZIPFILER"

#--- and something that is not a program at all
run_at 5
launched_says "RET on a text file declines"            "NOT A PROGRAM"
launched_says "and stays where it was"                 "ZIPFILER"

#--- A BASIC program needs BASIC.SYSTEM, and BASIC.SYSTEM has to be told what
#    to run. It keeps that name inside its own image at $2006, holding
#    "STARTUP" as it comes off the disk; the launcher overwrites it between
#    loading the interpreter and entering it. See docs/design.md section 14.
if "$ROOT/tools/ac" -g "$LAUNCH" BASIC.SYSTEM 2>&1 | grep -q "No match"; then
    echo "  (skipping BASIC: no BASIC.SYSTEM to hand -- see tests/mklaunch.sh)"
else
    run_at 2:DEEP 1                           # into PROGS, then RET on HELLO
    "$VII" settle 8 >/dev/null
    "$VII" screen > "$LAUNCHED"
    launched_says "RET on a BASIC program runs it" "BASIC PROGRAM RAN"
    # ...and runs it rather than merely opening BASIC, which is the whole
    # difference. The banner appears when BASIC.SYSTEM has nothing to run.
    if grep -q "PRODOS BASIC" "$LAUNCHED"; then
        bad "and does not stop at the prompt" "the interpreter came up idle"
    else
        ok "and does not stop at the prompt"
    fi
fi

#--- P, which asks for a slot and boots it. ESC has to come back, because the
#    alternative is a machine that reboots on a mistyped key.
"$VII" boot "$LAUNCH" >/dev/null
"$VII" speed maximum >/dev/null
"$VII" kbdelay 0.2 >/dev/null
"$VII" await "(volumes)" 60 >/dev/null
"$VII" settle 2 >/dev/null
k text "P"
"$VII" settle 2 >/dev/null
snapshot
assert_row "P asks which slot"                        22 "PR#"
# The cursor is ONE cell, so assert_inverse -- which wants a whole run of them
# -- is the wrong tool. Column 4 is even, so it lives in aux at half that
# offset, and inverse means the high bit is clear.
_curaddr=$(python3 -c "
lo=[0x00,0x80]*12; hi=[0x04,0x04,0x05,0x05,0x06,0x06,0x07,0x07]*3
base=[0,0x28,0x50][22//8]; print(hex(((hi[22]<<8)|lo[22]|base)+2))")
"$VII" dump "$_curaddr" 1 1 "$ROOT/build/cur.bin" >/dev/null 2>&1
if [ "$(python3 -c "print(open('$ROOT/build/cur.bin','rb').read()[0] < 0x80)")" = "True" ]; then
    ok "with a cursor where the digit goes"
else
    bad "with a cursor where the digit goes" "column 4 of the prompt is not inverse"
fi

# 3 is the //e's own eighty-column firmware rather than a card, so it is not
# offered and must not be taken. Anything that is not a slot leaves the prompt
# up, waiting -- which is what these check: the prompt is still there.
k text "3"
"$VII" settle 2 >/dev/null
snapshot
assert_row "3 is not a slot on this machine"          22 "PR#"
k text "8"
"$VII" settle 2 >/dev/null
snapshot
assert_row "and neither is 8"                         22 "PR#"
k key esc
"$VII" settle 2 >/dev/null
snapshot
assert_row "and ESC comes back to the listing"        22 "entries"

# Somewhere other than the volume list, so that a reboot is visible as a
# reboot rather than as nothing having happened at all.
k key "down arrow"; k line ""
"$VII" settle 2 >/dev/null
snapshot
assert_left "in a directory before booting"            0 "/ZIPFILER"
k text "P"
"$VII" settle 2 >/dev/null
k text "6"
"$VII" await "(volumes)" 60 >/dev/null || bad "PR#6 never came back up"
"$VII" settle 3 >/dev/null
snapshot
assert_left "PR#6 boots the slot and starts over"      0 "(volumes)"
fi

#--------------------------------------
# The quit routine
#
# MLI QUIT copies four pages out of the language card to $1000 and jumps there.
# Those 1024 bytes ARE what happens when any program quits, so replacing them
# is how quitting comes back to ZipFiler instead of Bitsy Bye.
#
# This runs on its own COPY of the image. The patcher only ever writes to a
# file on the Mac, and this makes sure the suite is no exception -- see
# docs/design.md 12 and 15.
#--------------------------------------
if section "the quit routine"; then
QIMG="$ROOT/build/QUITTEST.po"
eject_now
rm -f "$QIMG" "$QIMG.quitsave"
cp "$ROOT/build/ZIPFILER.po" "$QIMG"

# Before anything: the patcher has to find the block and know what is in it.
out="$(python3 "$ROOT/tools/quitpatch.py" status "$QIMG" 2>&1)"
if echo "$out" | grep -q "Bitsy Bye"; then
    ok "a stock image has Bitsy Bye as its quit routine"
else
    bad "a stock image has Bitsy Bye as its quit routine" "$out"
fi

# Restoring one that was never patched must refuse rather than write rubbish.
if python3 "$ROOT/tools/quitpatch.py" restore "$QIMG" >/dev/null 2>&1; then
    bad "restoring an unpatched image is refused"
else
    ok "restoring an unpatched image is refused"
fi

python3 "$ROOT/tools/quitpatch.py" install "$QIMG" >/dev/null 2>&1
out="$(python3 "$ROOT/tools/quitpatch.py" status "$QIMG" 2>&1)"
if echo "$out" | grep -q "ZipFiler"; then
    ok "installing puts ZipFiler's routine in"
else
    bad "installing puts ZipFiler's routine in" "$out"
fi
if [ -f "$QIMG.quitsave" ]; then
    ok "and keeps the original beside it"
else
    bad "and keeps the original beside it" "no $QIMG.quitsave"
fi

# Twice would overwrite the saved copy with a patch, and there would be no way
# back. That is the one mistake this tool must not allow.
if python3 "$ROOT/tools/quitpatch.py" install "$QIMG" >/dev/null 2>&1; then
    bad "installing twice is refused"
else
    ok "installing twice is refused"
fi

# But a REBUILT image is unpatched with a save file still lying beside it, and
# that has to stay patchable -- it is what happens after any change to the
# program, which is the commonest thing anybody will do.
cp "$ROOT/build/ZIPFILER.po" "$QIMG"
if python3 "$ROOT/tools/quitpatch.py" install "$QIMG" >/dev/null 2>&1; then
    ok "a rebuilt image can be patched again"
else
    bad "a rebuilt image can be patched again" \
        "a stale .quitsave blocked it"
fi
out="$(python3 "$ROOT/tools/quitpatch.py" status "$QIMG" 2>&1)"
if echo "$out" | grep -q "ZipFiler"; then
    ok "and the rebuilt one really is patched"
else
    bad "and the rebuilt one really is patched" "$out"
fi

#--- and now the machine. Quitting has to come back to ZipFiler.
"$VII" boot "$QIMG" >/dev/null || { echo "boot failed" >&2; exit 1; }
"$VII" speed maximum >/dev/null
"$VII" kbdelay 0.2 >/dev/null
"$VII" await "(volumes)" 90 >/dev/null || bad "the patched image never booted"
"$VII" settle 2 >/dev/null

# Go somewhere first, so a relaunch is visible as a relaunch rather than as
# nothing at all having happened.
k key "down arrow"; k line ""
"$VII" await "ZIPFILER.SYSTEM" 60 >/dev/null || bad "never entered the volume"
"$VII" settle 2 >/dev/null
snapshot
assert_left "in a directory before quitting"      0 "/ZIPFILER"

k text "Q"
"$VII" await "(volumes)" 90 >/dev/null || bad "quitting never came back"
"$VII" settle 3 >/dev/null
snapshot
assert_left "and quitting comes back to ZipFiler" 0 "(volumes)"

# ...and for a program that is not ZipFiler, which is the whole point: the
# routine belongs to ProDOS now, not to us.
"$ROOT/tools/merlin32" "$ROOT/tools/asminc" "$ROOT/tests/quitter.S" >/dev/null 2>&1
rm -f "$ROOT/tests/_FileInformation.txt" "$ROOT/tests/QUITTER_Output.txt"
"$ROOT/tools/ac" -p "$QIMG" QUITTER SYS 0x2000 < "$ROOT/tests/QUITTER" 2>/dev/null
"$VII" boot "$QIMG" >/dev/null
"$VII" speed maximum >/dev/null; "$VII" kbdelay 0.2 >/dev/null
"$VII" await "(volumes)" 90 >/dev/null
"$VII" settle 2 >/dev/null
k key "down arrow"; k line ""
"$VII" await "QUITTER" 60 >/dev/null || bad "QUITTER never appeared"
"$VII" settle 2 >/dev/null
k key "down arrow"; k key "down arrow"; k line ""
"$VII" await "(volumes)" 90 >/dev/null || bad "another program's quit did not come back"
"$VII" settle 3 >/dev/null
snapshot
assert_left "another program's quit lands here too" 0 "(volumes)"

#--------------------------------------
# ...and the same job done from the Apple, which is the only way to reach a
# volume that is not a .po on the Mac -- a card partition, or one on a share.
#
# This one writes to a LIVE volume, so the order it does things in is the whole
# safety argument: the original goes to QUIT.ORIG and is read back and compared
# BEFORE PRODOS is touched at all. The assertions below check the outcome of
# that; the ordering itself is argued in docs/design.md 15.
#--------------------------------------
eject_now
rm -f "$QIMG" "$QIMG.quitsave"
cp "$ROOT/build/ZIPFILER.po" "$QIMG"

"$VII" boot "$QIMG" >/dev/null || { echo "boot failed" >&2; exit 1; }
"$VII" speed maximum >/dev/null; "$VII" kbdelay 0.2 >/dev/null
"$VII" await "(volumes)" 90 >/dev/null || bad "never booted for the on-Apple patcher"
"$VII" settle 2 >/dev/null
k key "down arrow"; k line ""                    # into /ZIPFILER
"$VII" await "QPATCH" 60 >/dev/null || bad "QPATCH.SYSTEM is not on the disk"
"$VII" settle 2 >/dev/null
k key "down arrow"; k line ""                    # RET on QPATCH.SYSTEM
"$VII" await "WHICH ONE" 90 >/dev/null || bad "the patcher never asked for a volume"
"$VII" settle 3 >/dev/null

# Which number /ZIPFILER got depends on what else is on line, so read it off
# the screen rather than assuming. /RAM is usually first and usually is not.
snapshot
volnum="$(grep -F "/ZIPFILER" "$SCREEN" | head -1 | sed 's/^ *\([0-9]\)\..*/\1/')"
if [ -n "$volnum" ]; then
    ok "the patcher lists the volumes"
else
    bad "the patcher lists the volumes" "$(head -6 "$SCREEN")"
    volnum=2
fi

k text "$volnum"
"$VII" await "QUITTING NOW GOES TO" 90 >/dev/null || bad "it never read PRODOS"
"$VII" settle 3 >/dev/null
snapshot
if grep -q "ORIGINAL" "$SCREEN"; then
    ok "it recognises the original quit routine"
else
    bad "it recognises the original quit routine" "$(head -6 "$SCREEN")"
fi

k text "I"
"$VII" await "DONE" 120 >/dev/null || bad "the on-Apple install never finished"
"$VII" settle 3 >/dev/null
snapshot
if grep -q "REBOOT" "$SCREEN"; then
    ok "and says the change needs a reboot"
else
    bad "and says the change needs a reboot" "$(tail -8 "$SCREEN")"
fi

# The disk is only really changed once Virtual ][ flushes it.
eject_now
out="$(python3 "$ROOT/tools/quitpatch.py" status "$QIMG" 2>&1)"
if echo "$out" | grep -q "ZipFiler"; then
    ok "patching from the Apple really changed PRODOS"
else
    bad "patching from the Apple really changed PRODOS" "$out"
fi
if "$ROOT/tools/ac" -g "$QIMG" QUIT.ORIG 2>&1 | grep -q "No match"; then
    bad "and left the original in QUIT.ORIG" "there is no QUIT.ORIG"
else
    saved="$("$ROOT/tools/ac" -g "$QIMG" QUIT.ORIG | python3 -c "
import sys
d = sys.stdin.buffer.read()
plain = bytes(c & 0x7f for c in d)
print('yes' if len(d) == 1024 and b'BITSY' in plain else 'no')")"
    if [ "$saved" = "yes" ]; then
        ok "and left the real original in QUIT.ORIG"
    else
        bad "and left the real original in QUIT.ORIG" "it is not 1024 bytes of Bitsy Bye"
    fi
fi

#--- and putting Bitsy Bye back really puts Bitsy Bye back. The image was
#    patched from the Apple, which keeps its original in QUIT.ORIG on the
#    volume rather than in a .quitsave on the Mac, so restore it the same way
#    it was patched: with the Mac tool, from a fresh patch of its own.
eject_now
cp "$ROOT/build/ZIPFILER.po" "$QIMG"
rm -f "$QIMG.quitsave"
python3 "$ROOT/tools/quitpatch.py" install "$QIMG" >/dev/null 2>&1
python3 "$ROOT/tools/quitpatch.py" restore "$QIMG" >/dev/null 2>&1
out="$(python3 "$ROOT/tools/quitpatch.py" status "$QIMG" 2>&1)"
if echo "$out" | grep -q "Bitsy Bye"; then
    ok "restoring puts the original back"
else
    bad "restoring puts the original back" "$out"
fi
if [ ! -f "$QIMG.quitsave" ]; then
    ok "and takes the saved copy away with it"
else
    bad "and takes the saved copy away with it" "$QIMG.quitsave is still there"
fi
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
