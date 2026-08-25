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
fresh_fixture() {
    "$ROOT/tests/mkfixture.sh" >/dev/null
    cp "$FIXTURE" "$BEFORE"
}

eject_now() {
    osascript -e 'tell application "Virtual ][" to tell (last machine) to eject device "S6D1"' 2>/dev/null || true
    sleep 1
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
assert_row "the boot volume is listed"            3 "FILER"
assert_row "a volume shows as VOL, not a type"    3 "VOL"
assert_row "the divider runs down the screen"     2 "|"
assert_row "the rule crosses it"                  1 "+"
assert_inverse "the cursor line is drawn inverse" 2
fi

#--------------------------------------
# Reading a real directory.
#--------------------------------------
if section "directory"; then
reboot
k key "down arrow"          # onto FILER
k line ""                   # RET: into it
"$VII" settle 2 >/dev/null
snapshot
assert_row "the path is the volume"               0 "/FILER"
assert_row "the editor's own SYS file is there"   2 "FILER.SYSTEM"
assert_row "with its type"                        2 "SYS"
# derived from the image rather than written in, so it does not break every
# time the program changes size -- and it checks the panel against ProDOS's
# own accounting rather than against a number I typed
sysblk=$("$ROOT/tools/ac" -l "$FIXTURE" | awk '/FILER.SYSTEM/ {print $3+0}')
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
k key "down arrow"; k line ""          # into /FILER
k key "down arrow"; k line ""          # into /FILER/DOCS
"$VII" settle 2 >/dev/null
snapshot
assert_row "two levels down"                      0 "/FILER/DOCS"
assert_row "and its contents"                     2 "NOTE.TXT"

k key "down arrow"; k line ""          # into /FILER/DOCS/DRAFTS
"$VII" settle 2 >/dev/null
snapshot
assert_row "three levels down"                    0 "/FILER/DOCS/DRAFTS"
assert_row "both drafts are there"                2 "CH1.TXT"
assert_row "and the second"                       3 "CH2.TXT"

k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up one"                               0 "/FILER/DOCS"
k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up two"                               0 "/FILER"
k key "left arrow"; "$VII" settle 2 >/dev/null; snapshot
assert_row "up out of a root is the volume list"  0 "(volumes)"
fi

#--------------------------------------
# Two panels that do not know about each other.
#--------------------------------------
if section "two panels"; then
reboot
k key "down arrow"; k line ""          # left into /FILER
k key "down arrow"; k line ""          # left into /FILER/DOCS
"$VII" settle 2 >/dev/null
k ctrl I                               # TAB
"$VII" settle 2 >/dev/null
snapshot
assert_row "focus moved to the right panel"       0 ">(volumes)"
assert_norow "and left the left one unmarked"     0 ">/FILER/DOCS"
assert_row "the left panel kept its place"        0 "/FILER/DOCS"
assert_row "the right panel still lists volumes"  2 "RAM"

k key "down arrow"; k line ""          # right into /FILER
"$VII" settle 2 >/dev/null
snapshot
assert_row "the panels are in different places"   0 "/FILER/DOCS"
assert_row "each with its own listing"            2 "NOTE.TXT"
assert_row "and the right one has the root"       2 "FILER.SYSTEM"

k text "S"                             # swap
"$VII" settle 2 >/dev/null
snapshot
assert_row "S exchanges them"                     0 "/FILER  "
assert_row "the other way round"                  0 "/FILER/DOCS"
fi

#--------------------------------------
# Tagging. A command acts on the tagged set if there is one and on the cursor
# line if there is not, so there is never a mode to be in -- design.md §6.
#--------------------------------------
if section "tagging"; then
reboot
k key "down arrow"; k line ""          # into /FILER
"$VII" settle 2 >/dev/null
k text " "                             # tag FILER.SYSTEM, step down
k text " "                             # tag DOCS, step down
"$VII" settle 2 >/dev/null
snapshot
assert_row "the first is marked"                  2 "> FILER.SYSTEM"
assert_row "and so is the second"                 3 "> DOCS"
assert_norow "the one after is not"               4 ">"
assert_row "the count is in the status row"      22 "2 tagged"
assert_row "and the blocks they come to"         22 "blocks"

# The blocks are the number worth knowing before a copy, so check the sum
# rather than just its presence: FILER.SYSTEM plus a one-block directory.
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
k key "down arrow"; k line ""          # into /FILER
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
k key "down arrow"; k line ""          # into /FILER
"$VII" settle 2 >/dev/null
k text " "                             # tag FILER.SYSTEM
k text " "                             # tag DOCS
k text " "                             # tag README.TXT
k text "L"
"$VII" settle 2 >/dev/null
snapshot
assert_row "all three are locked"                 2 "*FILER.SYSTEM"
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
k key "down arrow"; k line ""          # into /FILER
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
k text " "                             # tag FILER.SYSTEM, cursor moves to DOCS
k text " "                             # tag DOCS, cursor moves to README.TXT
k text "R"
snapshot
assert_row "the prompt offers the CURSOR line"    22 "NEW NAME: README.TXT"
"$VII" key esc >/dev/null; sleep 0.4
eject_now
assert_identical "and nothing was written"
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

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
