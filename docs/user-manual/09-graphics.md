# 9. Graphics

← [The screen and colour](08-the-screen-and-colour.md) · [Contents](README.md) · [Next: Sound →](10-sound.md)

---

## 9.1 The coordinate system

Graphics coordinates have their **origin at the bottom left**, unlike text
coordinates which count rows from the top.

* **X** runs 0 to 255 — or 0 to 511 in `MODE 3` with `FATPIX 0`.
* **Y** runs from −*ORGOFF* to 191 − *ORGOFF*, where *ORGOFF* is twice the
  current character height.

With the default cell height of 9, *ORGOFF* is 18, so Y runs **−18 to 173**.
In `MODE 1`, where the default height is 8, Y runs −16 to 175. Y = 0 is the
baseline of the bottom text row, which is why the origin sits above the
bottom of the screen at all: it leaves room for the two-line lower window.

Plotting outside the screen gives error 32, *Off screen*.

## 9.2 Moving the origin — the four pseudo-variables

Four ordinary numeric variables rescale and shift the coordinate system.
They are created by `RUN` and `CLEAR`, and you assign to them with `LET`:

| Variable | Default | Effect |
|---|---|---|
| `xos` | 0 | Added to every absolute X |
| `yos` | 0 | Added to every absolute Y |
| `xrg` | 256 (512 with thin pixels) | The X value that corresponds to the right edge |
| `yrg` | 192 | The Y value that corresponds to the top |

Each is applied only when it differs from its normal value, so a program that
never touches them pays almost nothing.

```basic
10 MODE 4: CLS
20 LET xrg = 100: LET yrg = 100      : REM work in percentages
30 FOR i = 0 TO 100 STEP 5
40   PLOT i, i
50 NEXT i
```

```basic
10 LET xos = 128: LET yos = 88        : REM origin at the centre
20 FOR a = 0 TO 2*PI STEP 0.05
30   PLOT 60*COS a, 60*SIN a
40 NEXT a
```

`DRAW` in its **relative** form applies the ranges but not the offsets — a
displacement should not be shifted by where the origin happens to be.
`DRAW TO` applies both.

## 9.3 `PLOT`

```
PLOT [colour items ;] x, y
```

Plots one point and makes it the current graphics position.

```basic
PLOT 128, 88
PLOT PEN 3; 10, 10
PLOT OVER 1; x, y            : REM XOR - plot twice to erase
```

Colour items before the coordinates behave exactly as they do in `PRINT`:
they apply to this statement only.

Which of the per-mode plotting routines is used, and which of the four `OVER`
combinations, is decided once before the operation rather than per point,
which is why `DRAW` and `CIRCLE` are as fast as they are.

## 9.4 `DRAW`

```
DRAW [colour items ;] x, y            relative line from the current position
DRAW [colour items ;] TO x, y         absolute line to a point
DRAW [colour items ;] x, y, angle     a curve, bulging by angle radians
```

```basic
10 MODE 4: CLS
20 PLOT 20, 20
30 DRAW 100, 0
40 DRAW 0, 100
50 DRAW -100, 0
60 DRAW 0, -100
70 PLOT 150, 50: DRAW 60, 60, PI      : REM a half circle
```

Lines are drawn with Bresenham's algorithm. Before it starts, `DRAW` works
out whether the line *can* leave the screen; if it cannot, no per-point range
check is done at all.

The curved form approximates the arc with up to four straight chords. Very
small angles, and arcs whose chords come out under a pixel, are drawn as a
single straight line.

## 9.5 `CIRCLE`

```
CIRCLE [colour items ;] x, y, radius
```

```basic
10 MODE 4: CLS
20 FOR r = 5 TO 80 STEP 5
30   CIRCLE PEN r/5; 128, 88, r
40 NEXT r
```

A midpoint circle algorithm using eightfold symmetry: one octant is stepped
and each position generated there yields eight points.

## 9.6 `FILL` — textured flood fill

```
FILL [USING pattern$ ,] [colour items ,] x, y [, flag]
```

| Form | Effect |
|---|---|
| `FILL x,y` | Solid fill in the current ink |
| `FILL INK 3, x, y` | Solid fill in ink 3 |
| `FILL USING a$, x, y` | Fill with the pattern in *a$* |
| `FILL USING a$, INK 3, x, y` | Solid — an explicit ink overrides the pattern |

The fourth argument, if given, is 0 (or absent) to build the check screen
afresh, or 1 to reuse the one already built — useful when filling several
regions of the same shape.

```basic
10 MODE 4: CLS
20 CIRCLE 128, 88, 60
30 FILL PEN 4; 128, 88
```

### How it works, and why it is fast

`FILL` does not test the screen directly. It first builds a **check screen** —
a one-bit-per-pixel bitmap in which a set bit means "not part of the region",
either because the pixel differed from the seed colour or because the fill has
already reached it. The flood is then the classic scanline-stack algorithm
over that bitmap, which makes the boundary test a single `AND` and makes
`MODE 3` and `MODE 4` identical from the algorithm's point of view.

The stack is moved to a dedicated area for the duration, because a
complicated region can need far more space than the BASIC stack has.

### Patterns

The pattern is a 128-byte tile that repeats every 8 bytes horizontally and
every 16 scans vertically. The easiest way to make one is to draw it and
`GRAB` it:

```basic
10 MODE 4: CLS
20 REM draw a 16x16 pixel motif at 0,176
30 FOR i = 0 TO 15: PLOT i, 176+i: PLOT 15-i, 176+i: NEXT i
40 GRAB pat$, 0, 176, 8, 16          : REM 8 bytes wide, 16 scans
50 CLS
60 CIRCLE 128, 88, 70
70 FILL USING pat$; 128, 88
```

`FILL` always works in the thin-pixel coordinate system, so in `MODE 3` with
`FATPIX 1` the X coordinate is doubled for you.

## 9.7 Reading the screen back

| Function | Result |
|---|---|
| `POINT(x, y)` | The colour index of a pixel |
| `ATTR(row, column)` | The attribute byte of a character cell |
| `SCREEN$(row, column)` | The character at that cell, or `""` |

`POINT` returns 0 or 1 in modes 1 and 2, 0 to 3 in `MODE 3`, 0 to 15 in
`MODE 4`.

`ATTR` only works in modes 1 and 2, which are the only modes with per-cell
attributes; elsewhere it gives error 34. The byte it returns is the ZX-style
attribute: ink in bits 0–2, paper in 3–5, bright in 6, flash in 7.

`SCREEN$` works backwards: it reads the pixels of the cell, reduces them to
one bit per pixel, and searches the character set for a match. It returns the
empty string if nothing matches — so it will not see a cell that has been
drawn over, or one showing a character in the wrong colours.

```basic
10 PRINT AT 5,10; "X"
20 PRINT SCREEN$(5,10)        : REM X
30 PRINT POINT(80, 100)
```

## 9.8 Block graphics — `GRAB` and `PUT`

```
GRAB string-variable, x, y, width, length
PUT [colour items ;] x, y, block$ [, mask$]
```

`GRAB` captures a rectangle of screen into a string; `PUT` writes one back.
Both require `MODE 3` or `MODE 4`, whose screens are linear and free of
attributes.

* **width** is in *bytes*, not pixels — 1 byte is 4 pixels in `MODE 3` and 2
  pixels in `MODE 4`.
* **length** is in scan lines.
* *x*, *y* is the **top-left** corner in graphics coordinates.

```basic
10 MODE 4: CLS
20 CIRCLE 20, 170, 10
30 GRAB ball$, 10, 180, 12, 22        : REM capture it
40 CLS
50 FOR x = 0 TO 200 STEP 4
60   PUT OVER 1; x, 100, ball$        : REM draw
70   PAUSE 2
80   PUT OVER 1; x, 100, ball$        : REM erase (XOR twice)
90 NEXT x
```

### The block format

A grabbed block is an ordinary string, so it can be assigned, saved, passed
to a procedure, or built by hand:

| Byte | Contents |
|---|---|
| 0 | `&00` — a control code marking this as a `PUT` block |
| 1 | Width in bytes |
| 2 | Length in scan lines |
| 3… | The pixel data, one row of *width* bytes per scan line |

`PUT` validates the header, so an arbitrary string cannot be mistaken for a
block — that is error 37, *Invalid PUT block*.

### `PUT` modes

`PUT` honours `OVER` 0 to 3 and `INVERSE`:

| Setting | Effect |
|---|---|
| `OVER 0` | Replace |
| `OVER 1` | XOR — put twice to erase cleanly |
| `OVER 2` | OR |
| `OVER 3` | AND |
| `INVERSE 1` | Invert the block as it is drawn |

### Masks

A second string is a **mask**: only the pixels where the mask has one-bits
are altered. This is how you draw an irregularly shaped sprite without
disturbing the background around it.

```basic
PUT x, y, sprite$, mask$
```

The mask must have the same width and length as the block, or you get
error 38, *PUT mask mismatch*.

A block larger than the 8K staging buffer gives error 36, *Stored area too
big*.

## 9.9 `BLITZ` — replaying graphics from a string

```
BLITZ string
```

Executes a string of packed graphics commands. It is dramatically faster than
the equivalent BASIC because there is no interpretation overhead per command.

### The command codes

| Code | Bytes | Meaning |
|---|---|---|
| 0 or &FF | `sign, x, sign, y` | Relative `DRAW` (sign byte is `&00` or `&FF`) |
| 1 | `x, y` | `PLOT` |
| 2 | `x, y` | `DRAW TO` |
| 3 | `x, y, r` | `CIRCLE` |
| 4 | `over` | `OVER` |
| 5 | `ink` | `PEN` |
| 6 | `0` or `1` | `CLS` (whole screen / window) |
| 7 | `frames` | `PAUSE` |

An unrecognised code gives error 35, *Invalid BLITZ code*.

You could build these strings by hand, but you do not have to.

## 9.10 `RECORD` — capturing graphics into a `BLITZ` string

```
RECORD TO string-variable
RECORD STOP
```

While recording is on, every graphics command **also** appends its `BLITZ`
record to the named string. Draw the picture once slowly, then replay it as
often as you like at speed.

```basic
  10 MODE 4: CLS
  20 LET pic$ = ""
  30 RECORD TO pic$
  40 PEN 6
  50 PLOT 100, 60: DRAW 56, 0: DRAW -28, 48: DRAW -28, -48
  60 CIRCLE 128, 76, 40
  70 RECORD STOP
  80
  90 FOR i = 1 TO 20
 100   CLS
 110   PEN RND(15)
 120   BLITZ pic$
 130 NEXT i
```

Notes:

* Only *fat*-pixel drawing is recorded, since `BLITZ` coordinates are single
  bytes.
* `PRINT` is deliberately excluded, so `PRINT PEN 5;` does not record a pen
  change that was only a print modifier.
* `RECORD` is turned off while a `BLITZ` runs, so replaying inside a
  recording does not record everything twice.
* `RECORD TO` also arms stream 16, so ordinary `PRINT #16` output goes into
  the same string. See chapter 7.

## 9.11 A worked example

```basic
  10 REM Bouncing ball with a background
  20 MODE 4: CLS: BORDER 0
  30 PAPER 0: PEN 7
  40 REM --- draw the ball once and grab it
  50 CIRCLE 12, 160, 6
  60 FILL 12, 160
  70 GRAB ball$, 6, 167, 8, 14
  80 CLS
  90 REM --- a background so we can see the mask working
 100 FOR i = 0 TO 250 STEP 10: PEN 1: DRAW TO i, 0: PLOT i, 170: NEXT i
 110 REM --- animate
 120 LET x = 20: LET y = 100: LET dx = 3: LET dy = 2
 130 DO
 140   PUT OVER 1; x, y, ball$
 150   PAUSE 1
 160   PUT OVER 1; x, y, ball$
 170   LET x = x + dx: LET y = y + dy
 180   IF x < 2 OR x > 240 THEN LET dx = -dx
 190   IF y < 16 OR y > 168 THEN LET dy = -dy
 200   EXIT IF INKEY$ <> ""
 210 LOOP
```

## 9.12 Performance notes

* `BLITZ` is the fastest way to redraw a fixed picture.
* `PUT` with `OVER 1` is the standard sprite technique: draw, pause, draw
  again to erase.
* Keeping coordinates as whole numbers keeps arithmetic on the integer fast
  path.
* Leaving `xos`, `yos`, `xrg` and `yrg` at their defaults saves a scaling
  step on every coordinate.
* `FILL` builds a whole check screen each time; pass the flag `1` to reuse it
  when filling several regions of the same picture.

---

## Summary

* Graphics origin is bottom-left; Y runs from −2×(cell height) upward.
* `xos`, `yos`, `xrg` and `yrg` shift and rescale the coordinate system.
* `PLOT`, `DRAW`, `DRAW TO`, `DRAW x,y,angle`, `CIRCLE`, `FILL`.
* `POINT`, `ATTR` and `SCREEN$` read the screen back.
* `GRAB`/`PUT` move rectangles in `MODE 3` and `MODE 4`; width is in bytes,
  and a mask string gives shaped sprites.
* `RECORD TO a$` captures drawing as a `BLITZ` string; `BLITZ a$` replays it
  at speed.

---

← [The screen and colour](08-the-screen-and-colour.md) · [Contents](README.md) · [Next: Sound →](10-sound.md)
