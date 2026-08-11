# 8. The Screen and Colour

← [Input and output](07-input-and-output.md) · [Contents](README.md) · [Next: Graphics →](09-graphics.md)

---

## 8.1 Screen modes

```
MODE n
```

*n* is 1 to 4. Anything else gives error 34, *Invalid screen mode*.

| `MODE` | Resolution | Colours | Layout | Memory |
|---|---|---|---|---|
| 1 | 256 × 192 | 2 per 8 × 8 cell | ZX Spectrum layout, separate attribute block | 6.75K |
| 2 | 256 × 192 | 2 per 8 × 1 cell | Linear, one attribute byte per byte of pixels | 14K |
| 3 | 512 × 192 | 4 | Linear, 2 bits per pixel | 24K |
| 4 | 256 × 192 | 16 | Linear, 4 bits per pixel | 24K |

`MODE` clears the screen, rebuilds the pixel expansion tables and resets the
windows.

Modes 3 and 4 need 24K, which is why every screen occupies **two** 16K pages.

Internally the ROM calls these modes 0 to 3; you will see those numbers in
system variables and in the ROM documentation. User `MODE n` is internal mode
*n* − 1.

## 8.2 Character size

```
CSIZE width, height
```

* **width** must be 6 or 8. A width of 6 only has any effect in `MODE 3`,
  where it gives 85 columns instead of 64. In modes 1, 2 and 4 characters are
  always 8 pixels wide.
* **height** may be 6 to 32. Heights of 16 or more are drawn double-height,
  by doubling every scan of the 8-byte bitmap.

Anything outside those ranges gives error 30.

| Situation | Result |
|---|---|
| Height 6 or 7 | Cell filled; the glyph is truncated to its first *h* bytes |
| Height 8 | Cell filled exactly |
| Height 9–15 | 8 scans drawn, *h*−8 blank scans below |
| Height 16 | Cell filled exactly (each byte doubled) |
| Height 17–32 | 16 scans drawn, *h*−16 blank |

So box-drawing characters only join up vertically at heights 6, 7, 8 and 16.
[font-rendering.md](../font-rendering.md) works through the bit-level detail,
including how to design a font that reads correctly at both widths.

### Default sizes and the resulting layout

| Mode | Default cell | Text rows | Upper window | Lower window | Columns |
|---|---|---|---|---|---|
| 1 | 8 × 8 | 24 | 0–21 | 22–23 | 32 |
| 2 | 8 × 9 | 21 | 0–18 | 19–20 | 32 |
| 3 | 8 × 9 | 21 | 0–18 | 19–20 | 64 (85 at width 6) |
| 4 | 8 × 9 | 21 | 0–18 | 19–20 | 32 |

The lower window is always two rows. Any scan lines left over — three of
them at height 9 — become a gap between the two windows (`LSOFF`).

## 8.3 Pixel width — `FATPIX`

```
FATPIX 0    thin pixels: MODE 3 addresses all 512 columns
FATPIX 1    fat pixels:  each pixel is doubled, so X runs 0-255
```

`MODE 3` is 512 pixels wide but BASIC's coordinate system is nominally 256
wide. `FATPIX 1` doubles each pixel so the two agree; `FATPIX 0` gives you
access to every column.

Changing the setting rescales both the current graphics X coordinate and the
`xrg` pseudo-variable, so nothing moves on screen when you switch.

`FATPIX` only means anything in `MODE 3`.

## 8.4 Windows

```
WINDOW left, right, top, bottom
WINDOW
```

Restricts printing and clearing to a rectangle of character cells. A bare
`WINDOW` restores the whole upper screen.

```basic
10 MODE 4: CLS
20 WINDOW 4, 27, 2, 16
30 PAPER 1: CLS 1
40 FOR i = 1 TO 40: PRINT "text in a box "; : NEXT i
50 WINDOW
```

The values are validated against the mode's limits — the lowest usable row
and the rightmost column — and an out-of-range window gives error 54,
*Invalid WINDOW*. After the change the print position moves to the new
top-left corner.

`AT`, `TAB`, scrolling and `CLS 1` all work within the current window.

## 8.5 Colour

### The commands

| Command | Values | Effect |
|---|---|---|
| `PEN n` / `INK n` | 0–15, 16, 17 | Foreground colour |
| `PAPER n` | 0–15, 16, 17 | Background colour |
| `BRIGHT n` | 0, 1, 8 | Brightness (modes 1 and 2), or +8 on the colour (modes 3 and 4) |
| `FLASH n` | 0, 1, 8 | Flashing (modes 1 and 2) |
| `INVERSE n` | 0, 1 | Swap ink and paper while printing |
| `OVER n` | 0–3 | Combining mode |

`INK` and `PEN` are the *same command*. Typing `INK` stores the `PEN` token,
so `INK 3` lists back as `PEN 3`.

Special colour values:

| Value | Meaning |
|---|---|
| 16 | **Transparent** — leave whatever is already there |
| 17 | **Contrasting** — choose black or white to contrast with the other colour |

For `BRIGHT` and `FLASH`, the transparent value is 8 (16 is accepted and
treated as 8). Values of 18 or more for `INK`/`PAPER`, or anything else for
the rest, give error 23, *Invalid colour*.

`OVER` values:

| Value | Effect |
|---|---|
| 0 | Replace |
| 1 | XOR |
| 2 | OR (graphics only) |
| 3 | AND (graphics only) |

`OVER 0` and `OVER 1` affect both text and graphics; 2 and 3 affect graphics,
`PUT` and plotting only.

### Per-mode behaviour

* **Modes 1 and 2** have one attribute byte holding a 3-bit ink, a 3-bit
  paper, a bright bit and a flash bit. `INK n` for *n* > 7 therefore selects
  ink *n*−8 with `BRIGHT 1`.
* **Mode 3** has four colours. `BRIGHT` is ignored (though the mode 1/2
  variables still change).
* **Mode 4** has sixteen. `BRIGHT 1` adds 8 to both the ink and paper colour
  numbers, so `INK 3: BRIGHT 1` is the same as `INK 11`.

### Permanent and temporary colour

Every colour attribute exists twice: a **permanent** copy set by the
commands, and a **temporary** copy refreshed from it at the start of every
print or plot. An inline colour item changes only the temporary copy.

```basic
10 PEN 2                   : REM permanent
20 PRINT "red"
30 PRINT PEN 4; "green"    : REM temporary, this statement only
40 PRINT "red again"
```

Graphics always draw on the *upper* screen and use only the ink part of the
attribute.

## 8.6 The palette

The sixteen colour numbers are indexes into a palette; each entry selects one
of 128 actual colours.

```
PALETTE                        reset every entry, clear the line-interrupt list
PALETTE i, c                   set entry i to colour c
PALETTE i, b, c                set entry i to alternate between b and c (flashing)
PALETTE i, c LINE l            change entry i to c from scan line l downwards
PALETTE i, b, c LINE l         likewise, alternating
PALETTE i LINE l               delete the change to entry i at line l
```

*i* is 0 to 15 and colours are 0 to 127. An out-of-range entry gives error 24.

### The colour byte

A palette value is not an index — it is the hardware encoding, seven bits
laid out as:

```
bit  6   5   4   3   2   1   0
     G1  R1  B1  BR  G0  R0  B0
```

Green, red and blue each have a high bit and a low bit, and bit 3 is a
brightness bit shared by all three. That gives four levels per channel.

| Colour | Value | Binary |
|---|---|---|
| Black | 0 | `0000000` |
| Blue | 16 | `0010000` |
| Red | 32 | `0100000` |
| Magenta | 48 | `0110000` |
| Green | 64 | `1000000` |
| Cyan | 80 | `1010000` |
| Yellow | 96 | `1100000` |
| White | 120 | `1111000` |
| Bright blue | 17 | `0010001` |
| Bright white | 127 | `1111111` |

Those ten are the initial palette (entries 0–7 and 8–15 respectively, with
bright black equal to black).

```basic
PALETTE 1, 127            : REM entry 1 becomes bright white
PALETTE 0, 0, 127         : REM entry 0 flashes black/white
```

Alternating entries swap every `SPEEDINK` frame interrupts (system variable
offset &08, initially 17). If the two colours are the same, nothing flashes.

### Line interrupts — colour bars

`PALETTE … LINE l` schedules a palette change part-way down the frame, giving
you more colours on screen than the palette holds.

The `LINE` value uses BASIC's Y coordinate convention, which runs 175 down to
−16 for scan lines 0 to 191. Line 175 is rejected because there is no
preceding scan on which to raise the interrupt. Up to **127** changes may be
queued per screen; beyond that you get error 25, *Too many palette changes*.

```basic
10 MODE 4: CLS
20 FOR y = 170 TO -16 STEP -12
30   PALETTE 0, RND(127) LINE y
40 NEXT y
```

## 8.7 The border

```
BORDER n
```

Sets the border colour, 0 to 7 (the border has its own three-bit colour plus
brightness, driven from the keyboard port rather than the palette).

`BORDER` also chooses the lower screen's attribute so that it contrasts with
the border, which is why changing the border changes the look of the typing
area.

## 8.8 Clearing

| Form | Effect |
|---|---|
| `CLS` | Clear the whole screen and reset the graphics origin |
| `CLS 1` | Clear only the current window |
| `CLS #` | Reset the windows, streams and colours as well as clearing |

`CLS #` is the "put everything back to normal" command, and it is what
function key F6 types.

The clear is done by pointing the stack pointer at the screen and using
`PUSH`, which writes two bytes per instruction — about as fast as a Z80 can
fill memory.

## 8.9 Block graphics — `BLOCKS`

```
BLOCKS 0    character codes 128-143 come from the user-defined graphics
BLOCKS 1    they are synthesised as quarter-cell block shapes
```

Codes 128 to 143 are the sixteen combinations of four quarter-cell blocks.
`BLOCKS 1` draws them from the pattern of the code itself, at whatever cell
size is current; `BLOCKS 0` makes them ordinary UDGs read from the font.

## 8.10 Scrolling and rolling

```
ROLL   direction [, pixels [, x, y, width, length]]
SCROLL direction [, pixels [, x, y, width, length]]
```

The two differ only in what happens to the data that falls off the edge:
**`ROLL` wraps it round** to the other side, **`SCROLL` discards it** and
fills the vacated area with paper.

| Direction | Value |
|---|---|
| Left | 1 |
| Up | 2 |
| Right | 3 |
| Down | 4 |

With one argument, one pixel of the whole screen moves. With two, the whole
screen moves *pixels* pixels. With six, an arbitrary rectangle moves —
*x*, *y* is its top-left corner in graphics coordinates, *width* is in
**bytes** and *length* in scan lines.

```basic
10 MODE 4: CLS
20 FOR i = 1 TO 20: PRINT "SAM COUPE ";: NEXT i
30 DO: ROLL 1, 2: PAUSE 1: LOOP
```

Both require internal mode 2 or 3 — that is, `MODE 3` or `MODE 4` — because
they need a linear, attribute-free screen. The staging buffer holds 8K, so an
over-large rectangle gives error 36, *Stored area too big*.

`SCROLL CLEAR` and `SCROLL RESTORE` are unrelated: they turn the `scroll?`
prompt off and on.

## 8.11 Multiple screens

SAM can hold up to 16 screens in memory at once, each with its own mode,
windows, colours, cursor position and palette.

```
OPEN SCREEN n, mode      allocate two pages and initialise a new screen
CLOSE SCREEN n           free them again
SCREEN n                 draw on screen n
DISPLAY n                display screen n
DISPLAY 0                display whichever screen is being drawn on
```

```basic
10 OPEN SCREEN 2, 4          : REM a second MODE 4 screen
20 SCREEN 2: CLS: PRINT "back buffer"
30 SCREEN 1: PRINT "front"
40 PAUSE 100
50 DISPLAY 2                 : REM flip
60 PAUSE 100
70 DISPLAY 0
80 CLOSE SCREEN 2
```

Switching screens saves the outgoing screen's state into its own second page
and loads the incoming one's, which is why every screen keeps its own
settings. Screen 1 always exists.

| Error | Cause |
|---|---|
| 43 | *Invalid screen number* — that screen is not open |
| 44 | *Screen is already open* |
| 46 | *Current screen* — you cannot close the one you are drawing on |
| 1 | *Out of memory* — no pair of free pages |

Because a screen takes two 16K pages, a 256K machine has room for a handful
and a 512K machine for many more.

## 8.12 Character sets and UDGs

Three pointers locate a character's 8-byte bitmap:

| Variable | Address | Covers |
|---|---|---|
| `CHARS` | 23606 | Codes 32–127 (points 256 below the bitmap of code 0) |
| `UDG` | 23675 | Codes 128–168 (points at the bitmap of code 144) |
| `HUDG` | 23677 | Codes 169–255 |

`UDG "x"` returns the address of the bitmap for character *x*, so redefining
a character is a matter of poking eight bytes:

```basic
10 FOR i = 0 TO 7
20   READ b: POKE UDG "A" + i, b
30 NEXT i
40 DATA BIN 00111100, BIN 01000010, BIN 10100101, BIN 10000001
50 DATA BIN 10100101, BIN 10011001, BIN 01000010, BIN 00111100
60 PRINT "A"
```

To point the font somewhere else entirely — for a redefined character set —
`POKE` a new address into `CHARS`, remembering that it is stored 256 low so
that *code* × 8 indexes it directly:

```basic
POKE DPEEK 23606, …             : REM read it
DPOKE 23606, myfont - 256       : REM set it
```

> **`HUDG` is a trap.** The ROM reads it but never writes it, so on a freshly
> booted machine it is zero and `PRINT CHR$ 200` fetches its bitmap from ROM
> address &00F8 — you get garbage, not a blank. If you use codes 169 and
> above, set `HUDG` yourself first. See [hudg.md](../hudg.md).

---

## Summary

* `MODE 1`–`4`; `MODE 3` is the 512-wide four-colour mode and the only one
  where `CSIZE` width 6 does anything.
* `CSIZE w,h`: *w* is 6 or 8, *h* is 6–32, and 16 or more is double height.
* `WINDOW l,r,t,b` restricts printing; bare `WINDOW` restores.
* `PEN`/`INK` and `PAPER` take 0–15 plus 16 (transparent) and 17
  (contrasting). Colour commands are permanent; inline colour items last one
  statement.
* `PALETTE i,c` remaps a colour; `PALETTE … LINE y` gives mid-frame changes,
  up to 127 per screen.
* `ROLL` wraps, `SCROLL` discards; both need `MODE 3` or `MODE 4`.
* `OPEN SCREEN`/`SCREEN`/`DISPLAY` give you up to 16 independent screens.

---

← [Input and output](07-input-and-output.md) · [Contents](README.md) · [Next: Graphics →](09-graphics.md)
