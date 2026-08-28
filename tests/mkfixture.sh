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

cp "$ROOT/build/ZIPFILER.po" "$OUT"

# QPATCH.SYSTEM ships on the real disk but has no business in the fixture: a
# dozen assertions here count the root listing and name the row each entry sits
# on, and adding a file to it moved every one of them. The fixture is meant to
# have KNOWN contents, so it holds only what is under test.
#
# The quit-routine section does not use this fixture -- it copies
# build/ZIPFILER.po straight -- so QPATCH being on the shipped disk is still
# checked, where it belongs.
"$AC" -d "$OUT" QPATCH.SYSTEM 2>/dev/null || true

printf 'a note in a subdirectory\r' | "$AC" -p "$OUT" DOCS/NOTE.TXT TXT
printf 'chapter one\r'             | "$AC" -p "$OUT" DOCS/DRAFTS/CH1.TXT TXT
printf 'chapter two\r'             | "$AC" -p "$OUT" DOCS/DRAFTS/CH2.TXT TXT
printf 'read me\r'                 | "$AC" -p "$OUT" README.TXT TXT
printf 'binary-ish\r'              | "$AC" -p "$OUT" DATA.BIN BIN 0x2000
echo "fixture: $OUT"
