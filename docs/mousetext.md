# MouseText, and how to draw a box with it

Reference notes, written after looking at a screenshot of **Sneeze 2.2** (Karl
Bunker, ~1992) and finding it drawing box corners that this project had
recorded as impossible.

Everything below was measured, not remembered. The glyph shapes come from
`a2-editor/tests/snapshots/mousetext-glyphs.png`, which `make probe` captured
from a real Enhanced //e; the construction was read pixel by pixel out of
Sneeze's own screen.

## The short version

MouseText has **no corner glyph you need**, and that does not matter, because
it has **two verticals — one on each edge of the cell**:

| | |
|---|---|
| `$5F` | vertical down the **left** edge of its cell |
| `$5A` | vertical down the **right** edge of its cell |

A stroke on a cell edge is a stroke on the *boundary between two cells*. So a
vertical placed with `$5A` lands on the same pixel column where the next cell
begins — and a rule starting in that next cell begins on that same column.
They meet. That is the whole trick, and it is how Sneeze closes all four
corners of a box without a corner glyph.

**`$5A` is the piece this project did not know about.** `docs/design.md` §16
says MouseText's rules and verticals cannot be made to join, and reached that
conclusion having only ever used `$5F`. With `$5F` alone the conclusion is
correct. With both, corners are easy.

## The glyphs that matter

Taken off the hardware probe. Seven columns wide; the cell is eight scanlines
and a vertical fills all of them, so verticals join between character rows
without a break (confirmed on a rendered screen, not assumed).

```
  $4C  rule, TOP of cell        $53  rule, MIDDLE of cell
       #######                       .......
       .......                       .......
       .......                       .......
       .......                       #######
       .......                       .......
       .......                       .......
       .......                       .......

  $5C  rules, TOP and BOTTOM    $54  corner, BOTTOM-LEFT
       #######                       #......
       .......                       #......
       .......                       #......
       .......                       #......
       .......                       #......
       .......                       #......
       #######                       #######

  $5F  vertical, LEFT edge      $5A  vertical, RIGHT edge
       #......                       ......#
       #......                       ......#
       #......                       ......#
       #......                       ......#
       #......                       ......#
       #......                       ......#
       #......                       ......#
```

Also present and occasionally useful: `$4E` solid block (6 of 7 columns),
`$5B` diamond, `$4A`/`$4B` down/up arrows, `$55` right arrow, `$48` left
arrow, `$4D` return arrow, `$40`/`$41` filled and open apple, `$56`/`$57` two
dither patterns, `$58`/`$59` bracket shapes whose strokes are inset and
therefore join nothing.

`$5D` looks like a cross and is not one — it is a hash, two verticals and two
horizontals with a gap through the middle:

```
  $5D  ..#.#..
       ..#.#..
       ###.###
       .......
       ###.###
       ..#.#..
       .......
```

## Building a box

Put the verticals **facing each other**, hugging the rule from outside:

```
   column:   N-1    N ....... M   M+1
   top row:  $5A   $4C ..... $4C  $5F
   middle:   $5A                  $5F
   middle:   $5A                  $5F
   bottom:   $5A   $4C ..... $4C  $5F
```

- `$5A` on the **left** side: its stroke is on that cell's right edge, which is
  where column N starts, which is where `$4C`'s rule starts. Joined.
- `$5F` on the **right** side: its stroke is on that cell's left edge, which is
  where column M ends. Joined.

That is exactly what Sneeze does. Read off its screen, the two cells at the
top-left corner are:

```
   cell N-1 = $5A          cell N = $4C
   ......#                 #######
   ......#                 .......
   ......#                 .......
```

The box therefore occupies **two more columns than its interior** — one for
each vertical — and the verticals live *outside* the ruled span, not at its
ends.

`$54` (bottom-left corner) exists but is not needed for this construction, and
its rule sits on scanline 6 rather than 7, so it does not line up with a `$5C`
bottom rule in the row below. Treat it as a curiosity.

## What still cannot be done

**A cross or a T-junction.** Where a full-width rule is crossed by a vertical,
you would need rule-left, vertical, and rule-right inside one cell. No glyph
does that, `$5D` included. Whatever you do, one of the two lines gets a gap:

| put in the crossing cell | horizontal | vertical |
|---|---|---|
| `$4C` (rule) | unbroken | broken for a whole row |
| `$5F` or `$5A` (vertical) | 6-pixel notch | unbroken |

This is why ZipFiler's chrome is ASCII `-`, `|` and `+`: its layout is one rule
crossed by one divider, and that is the case MouseText genuinely cannot draw.
The ASCII glyphs are centred in their cells and so agree with each other.

**The way out is structural, not typographic.** Sneeze has no crossed rule
because it draws *boxes*. Every junction is a corner, and corners are solvable.
If ZipFiler ever boxes each panel instead of running one rule across a divider,
MouseText becomes the right answer.

## What boxing ZipFiler would cost

Not free, and the cost is listing space:

| | today | boxed |
|---|---|---|
| columns of chrome | 1 (the divider) | 4 borders + 1 gap |
| columns of listing | 79 | 75 |
| rows of chrome | 1 (the rule) | 2 per box, maybe 3 |

Fewer files visible and about four characters less filename. Worth it or not is
a judgement about how the program is used, not about how it is drawn.

## One thing worth stealing regardless

Sneeze sets its `File 1 of 13` counter **into the bottom rule of the box**
rather than on a line of its own. ZipFiler spends a whole row on `19 entries`.
That is a row of listing back, box or no box.

## A note on the machine

MouseText exists only on an Enhanced //e (and the //c and IIgs). An original
//e keeps a second copy of inverse uppercase at `$40-$5F`, so a border built
from these codes draws there as a row of letters. Anything using them needs the
CPU test in `a2-editor/src/machine.S` — decimal `$99 + $01` is `$00` on a 65C02
and `$9A` on a 6502 — and an ASCII fallback.
