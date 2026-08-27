#!/bin/bash
# mklaunch.sh -- the image the launch tests run against.
#
# Separate from the ordinary fixture on purpose. Every program on here changes
# what the root listing contains, and a dozen assertions in the suite count
# entries and name the row they sit on -- so putting these on the shared
# fixture would break tests that have nothing to do with launching.
#
# It is also a different KIND of image: the tests that use it end with ZipFiler
# gone, replaced by whatever was launched, so each one boots afresh anyway.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"
OUT="${1:-$ROOT/build/LAUNCH.po}"

cp "$ROOT/build/ZIPFILER.po" "$OUT"

# The programs are assembled here rather than committed: they are under 200
# bytes each and they have to match their source, which a checked-in binary
# stops being the moment somebody edits the .S beside it.
build() {
    "$ROOT/tools/merlin32" "$ROOT/tools/asminc" "$ROOT/tests/$1.S" >/dev/null 2>&1
    rm -f "$ROOT/tests/_FileInformation.txt" "$ROOT/tests/$2_Output.txt"
}
build runme RUNME
build runbin RUNBIN

# A SYS file at the root, and the same program one directory down: the launcher
# builds a full path and sets the prefix from it, and neither is exercised by a
# file that happens to live at the top.
"$AC" -p "$OUT" RUNME SYS 0x2000     < "$ROOT/tests/RUNME"
"$AC" -p "$OUT" PROGS/DEEP SYS 0x2000 < "$ROOT/tests/RUNME"

# A BIN, which names its own load address. $0300 rather than $2000, because a
# BIN that loads where a SYS file loads tests none of the part that differs.
"$AC" -p "$OUT" RUNBIN BIN 0x0300 < "$ROOT/tests/RUNBIN"

# A BIN whose load address lands on the launcher's own parameter blocks. It
# must be refused rather than run: $1700 is where they live, and a program
# reading over them mid-launch takes the machine with it.
"$AC" -p "$OUT" CLASH BIN 0x1700 < "$ROOT/tests/RUNBIN"

# Something that is not a program at all, to prove RET still declines.
printf 'not a program\r' | "$AC" -p "$OUT" PLAIN.TXT TXT

# BASIC.SYSTEM is Apple's and is not in this repository, so the BASIC test is
# skipped when it cannot be found rather than failing. See docs/design.md 14.
for cand in "$ROOT/vendor/BASIC.SYSTEM" \
            "$ROOT/../a2-editor/vendor/ProDOS_2_4_3.po"; do
    [ -f "$cand" ] || continue
    case "$cand" in
        *.po) "$AC" -g "$cand" BASIC.SYSTEM > "$ROOT/build/basic.tmp" 2>/dev/null || continue
              [ -s "$ROOT/build/basic.tmp" ] || continue
              "$AC" -p "$OUT" BASIC.SYSTEM SYS 0x2000 < "$ROOT/build/basic.tmp"
              rm -f "$ROOT/build/basic.tmp" ;;
        *)    "$AC" -p "$OUT" BASIC.SYSTEM SYS 0x2000 < "$cand" ;;
    esac
    printf '10 PRINT "BASIC PROGRAM RAN"\n20 END\n' > "$ROOT/build/hello.tmp"
    "$AC" -bas "$OUT" PROGS/HELLO < "$ROOT/build/hello.tmp"
    rm -f "$ROOT/build/hello.tmp"
    break
done

echo "launch image: $OUT"
