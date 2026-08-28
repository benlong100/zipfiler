#!/bin/bash
# mkfixture.sh -- build the image the suite runs against.
#
# Known contents, so an assertion can name what it expects rather than
# describe it. Nothing here is precious: the suite writes to this image and
# it is rebuilt from scratch every run.
#
# It is deliberately NOT the boot volume of anybody's real card. See
# docs/design.md section 12.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AC="$ROOT/tools/ac"
OUT="${1:-$ROOT/build/FIXTURE.po}"

cp "$ROOT/build/ZIPFILER-BARE.po" "$OUT"

# Built from the BARE image -- the program and ProDOS, nothing else -- so
# what gets added to the shipped disk cannot move the rows this suite
# counts. See the note beside BARE in the Makefile.

printf 'a note in a subdirectory\r' | "$AC" -p "$OUT" DOCS/NOTE.TXT TXT
printf 'chapter one\r'             | "$AC" -p "$OUT" DOCS/DRAFTS/CH1.TXT TXT
printf 'chapter two\r'             | "$AC" -p "$OUT" DOCS/DRAFTS/CH2.TXT TXT
printf 'read me\r'                 | "$AC" -p "$OUT" README.TXT TXT
printf 'binary-ish\r'              | "$AC" -p "$OUT" DATA.BIN BIN 0x2000
echo "fixture: $OUT"
