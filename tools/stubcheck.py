#!/usr/bin/env python3
"""Check that the launch stub is position independent.

The stub in src/launch.S is assembled at its natural address inside the
program and executed from a copy somewhere below $2000, because the program it
is loading lands on top of where it was assembled. So it must not contain a
jsr or jmp to a label inside itself: that assembles perfectly, and at run time
jumps to an address that now holds whatever was just loaded. The machine does
something unrepeatable and the bug looks like a fault in the program being
launched.

Branches are fine -- they are relative, so they move with the code. Absolute
references to things that do not move are fine too: the MLI entry point, and
the parameter blocks, which live below $2000 on purpose.

Nothing else in the assembler or the linker checks this, and no test can:
getting it wrong destroys the machine's memory before anything can report.

Usage: stubcheck.py [file ...]   (default: src/launch.S)
"""
import pathlib, re, sys

START = re.compile(r"^STUB\b")
END = re.compile(r"^STUBEND\b")
# label in column 1, then whitespace, then the opcode
CODE = re.compile(r"^(\S*)\s+(\S+)\s*(.*)$")

def check(path):
    lines = path.read_text().splitlines()
    try:
        first = next(i for i, l in enumerate(lines) if START.match(l))
        last = next(i for i, l in enumerate(lines) if END.match(l))
    except StopIteration:
        return [f"{path}: no STUB/STUBEND pair -- has the stub been renamed?"]

    body = lines[first:last]
    labels = set()
    for line in body:
        m = CODE.match(line)
        if m and m.group(1):
            labels.add(m.group(1))
        # local labels are scoped to the enclosing global one, so a bare
        # :name inside the stub is inside the stub
        if line.startswith(":"):
            labels.add(line.split()[0])

    bad = []
    for n, line in enumerate(body, start=first + 1):
        if line.lstrip().startswith("*") or not line.strip():
            continue
        m = CODE.match(line)
        if not m:
            continue
        op = m.group(2).lower()
        if op not in ("jsr", "jmp"):
            continue
        operand = m.group(3).split(";")[0].strip()
        # jmp (SOMETHING) reads a pointer at a fixed address: that is fine
        # wherever the stub itself has been put.
        if operand.startswith("("):
            continue
        target = operand.split()[0] if operand else ""
        if target in labels:
            bad.append(
                f"{path}:{n}: {op} {target} -- inside the stub, so it will "
                f"jump into the loaded program instead. Use a branch.")
    return bad

def main(argv):
    paths = [pathlib.Path(a) for a in argv[1:]] or [pathlib.Path("src/launch.S")]
    problems = []
    for p in paths:
        if p.exists():
            problems += check(p)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("launch stub is position independent")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
