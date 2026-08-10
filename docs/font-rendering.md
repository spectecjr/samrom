# Character Cell Geometry and Font Rendering

How the ROM turns an 8-byte character bitmap into pixels: how many scans it
draws, which bits of each byte reach the screen at each `CSIZE` width, and
what that means for designing a font that must look right at more than one
cell size.

Sources: [endprint.asm](../endprint.asm) (`EPSUB`, `EPSSR`, `M0PRINT`,
`M1PRINT`, `M2PRINT`, `M3PRINT`, `M2DEADDR`), [tprint.asm](../tprint.asm)
(`ENDOUTP`, `DBCHAR`), [scrsel2.asm](../scrsel2.asm) (`WIDTH`, `MDSR`,
`SUET`, `DBBITS`), [scrfn.asm](../scrfn.asm) (`IMSCSR`).

## Cell geometry by mode

SAM's user-facing `MODE 1`–`MODE 4` are internal modes 0–3 (`MODECMD`
decrements the argument). Each screen mode has its own pixel depth, and the
number of bytes a character cell occupies follows from that:

| User mode | Internal | Resolution | Depth | Bytes/scan | Bytes/column | Columns |
|---|---|---|---|---|---|---|
| `MODE 1` | 0 | 256×192, ZX layout, 8×8 attrs | 1 bpp | 32 | 1 | 32 |
| `MODE 2` | 1 | 256×192, linear, 8×1 attrs | 1 bpp | 32 | 1 | 32 |
| `MODE 3` | 2 | 512×192, 4 colours | 2 bpp | 128 | 2 (8-pixel) or 1.5 (6-pixel) | 64 or **85** |
| `MODE 4` | 3 | 256×192, 16 colours | 4 bpp | 128 | 4 | 32 |

Characters are always real pixels wide — never "fat" pixels. The
byte counts differ only because of colour depth.

## `CSIZE` width: 6 or 8, and only in `MODE 3`

`CSIZE width,height` ([scrsel2.asm](../scrsel2.asm) `WIDTH`) accepts a width
of **6 or 8** and a height of **6–32**; anything else raises error 30. The
width is stored as `FL6OR8` (0 for 6, non-zero for 8) plus `CSIZE+1`.

`MDSR` only applies the narrow geometry after confirming internal mode 2,
and only `M2DEADDR`/`M2PRINT` consult `FL6OR8`. So:

* In `MODE 3`, width 6 gives 85 columns (510 of the 512 pixels used) and
  width 8 gives 64 columns.
* In `MODE 1`, `MODE 2` and `MODE 4`, characters are always 8 pixels wide.
  Setting a width of 6 stores the value but changes nothing on screen.

## Height: how many scans are actually drawn

The bitmap is always **8 bytes, one per scan**. Two clamps decide how many
of them reach the screen:

* `ENDOUTP` ([tprint.asm:95-111](../tprint.asm#L95-L111)) checks the height:
  below 16 it calls `EPSUB` once; at 16 or more it calls `DBCHAR` to double
  every byte into a 16-byte matrix and prints it in two passes, the second
  offset by `DHADJ` = 8 scans.
* `EPSSR` ([endprint.asm:57-67](../endprint.asm#L57-L67)) then limits each
  pass to `min(height, 8)` scans.

The cell, however, is always the full `CSIZE` height. The two never disagree
only at particular sizes:

| Height | Scans drawn | Result |
|---|---|---|
| 6, 7 | 6, 7 | Cell filled — glyph truncated to the first *h* bytes |
| **8** | 8 | Cell filled exactly |
| 9–15 | 8 | \(h-8\) blank scans at the bottom of every cell |
| **16** | 16 (each byte doubled) | Cell filled exactly |
| 17–32 | 16 | \(h-16\) blank scans at the bottom |

Anything that must join vertically between rows — box borders, block
graphics, underlines — is therefore only seamless at heights 6, 7, 8 and 16.

## Bit-to-pixel mapping

Within a byte, **bit 7 is the leftmost pixel**. In modes 0 and 1 the font
byte *is* the screen byte, so that is immediate. In modes 2 and 3 each
nibble is expanded through `CEXTAB` (built by `SUET`/`DBBITS`/`QUADBITS`,
then coloured by `COLEX`), and the expansion places nibble bit 3 leftmost.

The interesting case is `MODE 3`, where both widths share one routine.

### Width 8 — all eight bits

The 8-pixel path does not have its own loop. `M2PRINT` first pre-rotates
each font byte one place right with `RRCA` into a scratch buffer
(`P64AL`, [endprint.asm:159-164](../endprint.asm#L159-L164)), then enters
the 85-column *even* routine with the right-hand over-mask forced equal to
the left-hand one so both screen bytes are written in full. Working the
rotation and the two nibble extractions through:

| Screen byte | Nibble used | Pixels |
|---|---|---|
| First (left) | b7 b6 b5 b4 | 4 |
| Second (right) | b3 b2 b1 b0 | 4 |

Nothing is discarded: the rendered row is **b7 b6 b5 b4 b3 b2 b1 b0**.

### Width 6 — the middle six bits

A 6-pixel cell is 12 bits, so it occupies 1½ screen bytes and alternates
phase. `M2DEADDR` returns Z for an even column (byte-aligned) and NZ for an
odd one (starting mid-byte), and the over-masks are adjusted so the unused
nibble of the part-written byte is preserved:

| Column | First screen byte | Second screen byte |
|---|---|---|
| Even | Full byte ← b4 b3 b2 b1¹ | High nibble ← b6 b5; low nibble preserved (`OR &0F`) |
| Odd | High nibble preserved (`OR &F0`); low nibble ← b6 b5 | Full byte ← b4 b3 b2 b1¹ |

¹ the nibble extractions rotate the byte so the four centre bits land
together; the routine's own comments track the byte as `01234560`, and the
duplicated `0` label at each end is exactly what the masking throws away.

Either way the rendered row is **b6 b5 b4 b3 b2 b1**.

> **At width 6 the ROM draws the middle six bits.** It drops one bit from
> *each* end — b7 and b0 — not two bits from one end.

`SCREEN$` confirms this independently: its 6-pixel capture path rotates the
cell back to centre and masks it with `&7E` = `01111110`, commenting "mask
off bits 7 and 0, which may be junk"
([scrfn.asm:77-96](../scrfn.asm#L77-L96)).

### The ROM's own font

`UPACK` ([misc31.asm](../misc31.asm)) unpacks each character from seven
5-bit slices "with 2 zeros at LHS, 1 at RHS", i.e. b7 = 0, b6 = 0,
b5–b1 = glyph, b0 = 0. At width 6 that reads as five pixels plus a
one-pixel gap; at width 8 it gains a second blank column on the left. The
stock font is designed to sit inside the narrow window.

## Designing a font that works at both widths

Because the 6-pixel window is *centred*, one coincidence makes dual-width
design straightforward:

* Width 8, positions 0–7: the middle pair is **b4 / b3**.
* Width 6, positions 0–5 (= b6…b1): the middle pair is **also b4 / b3**.

A stroke placed on b4 is the left-of-centre column at both widths, and a
stroke that runs out to b7 or b0 reaches the cell edge at width 8 while
automatically reaching the window edge at width 6 through b6 or b1.

### Rules for box-drawing characters

| Element | Encoding | Why it survives both widths |
|---|---|---|
| Vertical `│` | `&10` (b4), or `&18` for a 2-pixel stroke | b4 is left-of-centre at both widths |
| Horizontal `─` | `&FF` on that scan | Fills both windows edge to edge, so runs stay contiguous |
| Left arm `┐ ┘ ┤` | `&F0` — run from b4 out to **b7** | Reaches the cell edge via b7 (width 8) or b6 (width 6) |
| Right arm `┌ └ ├` | `&1F` — run from b4 out to **b0** | Reaches the cell edge via b0 (width 8) or b1 (width 6) |
| Cross `┼` | `&FF` on the crossing scan, `&10` elsewhere | Both of the above |

The single rule is: **strokes must run all the way out to bit 7 and/or
bit 0**. There are no "spare bits" to fill in — b7 and b0 *are* the spare
bits, read only at width 8, and any stroke long enough to reach them has
already set the bit the narrow window needs.

### Worked example — `┌` in an 8-row cell

```text
scan  byte     width 8 (b7..b0)   width 6 (b6..b1)
 0    &00      ........           ......
 1    &00      ........           ......
 2    &00      ........           ......
 3    &1F      ...#####           ..####
 4    &10      ...#....           ..#...
 5    &10      ...#....           ..#...
 6    &10      ...#....           ..#...
 7    &10      ...#....           ..#...
```

The corner sits one column further left at width 6, but it is in the same
place as every other character's centre column, and the horizontal arm still
touches the right-hand edge — so `┌──┐` joins cleanly at either width.

## Related documents

* [hudg.md](hudg.md) — where the bitmaps live and how a character code maps to one.
* [memory-map.md](memory-map.md) — `CHARSVAL`, `EXTAB`/`CEXTAB` and the rest of the system page.
* [source-files.md](source-files.md) — `EPSUB` and the per-mode print routines in context.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
