#!/usr/bin/env python3
"""Compare two ProDOS images block by block.

The point of this program is that a file manager's bugs are not visible on
the screen. A delete that also freed somebody else's blocks, or a copy that
wrote past its file, shows up here and nowhere else -- so an operation is
checked by taking the image before, taking it after, and asking exactly which
512-byte blocks moved.

  imgblocks.py before.po after.po            list the blocks that differ
  imgblocks.py before.po after.po --expect 2 6 7    and insist on which
"""
import sys

BLOCK = 512

def blocks(path):
    d = open(path, "rb").read()
    return [d[i:i+BLOCK] for i in range(0, len(d), BLOCK)]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        sys.exit(__doc__)
    a, b = blocks(args[0]), blocks(args[1])
    if len(a) != len(b):
        print(f"images differ in size: {len(a)} vs {len(b)} blocks")
        return 1
    changed = [i for i in range(len(a)) if a[i] != b[i]]

    if "--expect" in sys.argv:
        want = sorted(int(x) for x in args[2:])
        if changed == want:
            print(f"changed exactly the expected blocks: {changed}")
            return 0
        print(f"changed {changed}")
        print(f"expected {want}")
        extra = [x for x in changed if x not in want]
        missing = [x for x in want if x not in changed]
        if extra:   print(f"  unexpectedly changed: {extra}")
        if missing: print(f"  expected to change but did not: {missing}")
        return 1

    if not changed:
        print("identical")
    else:
        print(f"{len(changed)} block(s) changed: {changed}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
