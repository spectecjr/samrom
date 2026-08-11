# Appendix C — Character Codes

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · [Appendix B](appendix-b-error-messages.md) · **Appendix C** · [Appendix D](appendix-d-tokens-and-priorities.md)

---

## C.1 The code space at a glance

| Codes | Contents |
|---|---|
| 0–5 | Editor: inserted literally. Printed: emit `?` |
| 6–15 | Editor keys. Printed: 6 and 8–14 act, 7 and 15 emit `?` |
| 16–23 | Control codes taking operands |
| 24–31 | Not control codes — printed, they emit `?` |
| 32–126 | ASCII |
| 127 | Copyright sign |
| 128–143 | Block graphics, or UDGs when `BLOCKS 0` is in force |
| 144–168 | Extended characters (accented letters and symbols), redefinable |
| 169–255 | High UDGs — **no font in ROM**, see §C.5 |

Codes 133 to 254 are *also* BASIC keyword tokens. The ambiguity is resolved
by context: inside quotes, and everywhere `PRINT` sends output, they are
characters; when listing a program outside quotes they expand to keywords.

## C.2 Control codes

**Two different contexts.** A code below 32 means one thing to the *editor*,
which is reading keystrokes, and another to the *print* routine. They agree
for 8–14 and 16–23. Elsewhere they differ: the editor acts on 7 (EDIT) and 15
(keypad toggle) and inserts 0–5 literally, whereas printing any of 0–5, 7, 15
or 24–31 produces a `?`. The table below is the print behaviour, which is
what `CHR$` gives you; chapter 2 covers the editor side.

| Code | Operands | Effect |
|---|---|---|
| 6 | — | Column tab (what `,` does in `PRINT`) |
| 7 | — | EDIT — *editor only*; printed it gives `?` |
| 8 | — | Cursor left |
| 9 | — | Cursor right |
| 10 | — | Cursor down |
| 11 | — | Cursor up |
| 12 | — | Delete left |
| 13 | — | Carriage return |
| 14 | — | Delete right |
| 15 | — | Keypad toggle — *editor only*; printed it gives `?` |
| 16 | 1 | `INK` |
| 17 | 1 | `PAPER` |
| 18 | 1 | `FLASH` |
| 19 | 1 | `BRIGHT` |
| 20 | 1 | `INVERSE` |
| 21 | 1 | `OVER` |
| 22 | 2 | `AT` row, column |
| 23 | 2 | `TAB` column (second operand ignored) |

Operand bytes follow the code in the output stream. The print routine
collects them by temporarily redirecting the channel's output address.

```basic
PRINT CHR$ 22 + CHR$ 10 + CHR$ 5 + "at row 10, column 5"
PRINT CHR$ 16 + CHR$ 2 + "in ink 2"
```

Storing a formatted screen as a string of codes and printing it in one go is
much faster than a sequence of `PRINT AT` statements.

> The character fetcher used by the interpreter skips every byte from 0 to 32
> except carriage return, which is why stray control bytes and spaces in a
> program line are harmless outside strings.

## C.3 Printable characters, 32–127

Codes 32 to 126 are standard ASCII: space, punctuation, digits, upper case,
lower case.

| Code | Character |
|---|---|
| 32 | space |
| 33–47 | `! " # $ % & ' ( ) * + , - . /` |
| 48–57 | `0`–`9` |
| 58–64 | `: ; < = > ? @` |
| 65–90 | `A`–`Z` |
| 91–96 | `[ \ ] ^ _ £` |
| 97–122 | `a`–`z` |
| 123–126 | `{ \| } ~` |
| **127** | **copyright sign** |

Code 127 is the copyright sign rather than the usual delete — it is what the
switch-on banner prints.

The ROM's own font occupies codes 32 to 168, unpacked at boot from a
five-bits-per-scan compressed table. Each glyph is 8 bytes, one per scan,
with bit 7 leftmost.

## C.4 Block graphics, 128–143

With `BLOCKS 1` (the default) these are **synthesised** rather than read from
a font, so they scale to whatever `CSIZE` is current and always tile
perfectly.

The low four bits of the code select which quarters of the cell are set:

| Bit | Value | Quadrant |
|---|---|---|
| 0 | 1 | Top right |
| 1 | 2 | Top left |
| 2 | 4 | Bottom right |
| 3 | 8 | Bottom left |

So:

| Code | Set quadrants |
|---|---|
| 128 | none — blank |
| 129 | top right |
| 130 | top left |
| 131 | top half |
| 132 | bottom right |
| 133 | top right + bottom right (right half) |
| 136 | bottom left |
| 138 | left half |
| 140 | bottom half |
| 143 | all four — solid |

```basic
FOR i = 128 TO 143: PRINT CHR$ i;: NEXT i
```

`BLOCKS 0` makes these ordinary characters taken from the font instead, where
the ROM stores accented letters and symbols — which is how the switch-on
banner produces the é in "Coupé".

## C.5 UDGs and the three font pointers

A character's bitmap is found through one of three pointers:

| Codes | Pointer | Address | Arithmetic |
|---|---|---|---|
| 32–127 | `CHARS` | 23606 | (`CHARS`) + code × 8 |
| 128–168 | `UDG` | 23675 | (`UDG`) + (code − 144) × 8 |
| 169–255 | `HUDG` | 23677 | (`HUDG`) + (code − 169) × 8 |

`CHARS` is stored 256 *below* the real base so that code × 8 indexes it
directly. `UDG` points at the bitmap of code 144.

The `UDG` function does this arithmetic for you:

```basic
10 FOR i = 0 TO 7
20   READ b: POKE UDG "A" + i, b
30 NEXT i
40 DATA BIN 00111100, BIN 01000010, BIN 10100101, BIN 10000001
50 DATA BIN 10100101, BIN 10011001, BIN 01000010, BIN 00111100
60 PRINT "A"
```

### The `HUDG` trap

The ROM **reads** `HUDG` but never writes it. On a freshly booted machine it
is zero, so `PRINT CHR$ 200` fetches its bitmap from ROM address 248 and the
whole range 169–255 shows fragments of ROM code rather than blanks.

If you want to use those codes, provide a font and point `HUDG` at it:

```basic
DPOKE 23677, myfont          : REM the bitmap of CHR$ 169
```

[hudg.md](../hudg.md) discusses where such a font can live.

### Redefining the whole character set

`CHARS` may be pointed anywhere:

```basic
DPOKE 23606, mynewfont - 256
```

Remember the −256 bias. Restore it with `DPOKE 23606, 20624` (&5090), or just
`NEW`.

## C.6 How many bits and scans reach the screen

The bitmap is always 8 bytes, but `CSIZE` decides how much of it is drawn:

| Height | Scans drawn | Result |
|---|---|---|
| 6, 7 | 6, 7 | Glyph truncated to its first *h* bytes |
| 8 | 8 | Exact fit |
| 9–15 | 8 | *h*−8 blank scans below every cell |
| 16 | 16 (each byte doubled) | Exact fit |
| 17–32 | 16 | *h*−16 blank scans below |

Within a byte, **bit 7 is the leftmost pixel**. In `MODE 3` at width 6 the
ROM draws the *middle six bits* — bits 6 down to 1 — dropping one bit from
each end. A stroke that runs out to bit 7 or bit 0 therefore reaches the cell
edge at both widths, which is the rule for designing box-drawing characters
that join up.

[font-rendering.md](../font-rendering.md) works this through in full.

## C.7 Keyboard codes

The keyboard is a matrix of 69 keys read in four states — unshifted, CAPS
SHIFT, SYMBOL SHIFT and CONTROL — giving a translation table of 280 entries.
`KEY position, value` rewrites one.

Codes **192 and above** may be given expansions with `DEF KEYCODE`. The
function keys produce 192 to 201 and are pre-defined:

| Key | Code | Types |
|---|---|---|
| F0 | 192 | `LIST` |
| F1 | 193 | `RENUM :` |
| F2 | 194 | `PRINT :` |
| F3 | 195 | `MODE :` |
| F4 | 196 | `RUN` |
| F5 | 197 | `CONTINUE` |
| F6 | 198 | `CLS #` |
| F7 | 199 | `LOAD ""` |
| F8 | 200 | `LOAD "" CODE` |
| F9 | 201 | `BOOT` |

Three more are installed at boot: code 252 (TAB) types a comma tab, and codes
253 and 254 type `INVERSE 1` and `INVERSE 0`.

---

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · [Appendix B](appendix-b-error-messages.md) · **Appendix C** · [Appendix D](appendix-d-tokens-and-priorities.md)
