# Appendix A — Keyword Reference, A to L

[Contents](README.md) · **A–L** · [M–Z](appendix-a-keywords-m-z.md)

---

Every keyword and function in SAM BASIC, alphabetically. Notation:
*italic* items you supply, `[ ]` optional, `…` repeatable.

Every keyword here is in the ROM's own keyword table. A tag on the heading
means the ROM tokenises and lists the word but has no implementation for it:
it gives *Not understood* (29) until the tagged product is loaded.

| Tag | Needs |
|---|---|
| **`[DOS]`** | Any disk operating system |
| **`[SD2]`** | SAMDOS 2 |
| **`[MD]`** | MasterDOS |
| **`[MB]`** | MasterBASIC |

Where a keyword is marked **reserved**, nothing uses it — not the ROM, and
not any of the three extensions. `WRITE` and `OFF` look reserved from the
ROM's side but are both claimed by the DOSes.

Keywords that are not in the ROM's table at all are summarised at the
[end of the M–Z file](appendix-a-keywords-m-z.md#keywords-added-by-the-extensions)
and covered in full by
[dos-and-extensions.md](../dos-and-extensions.md).

Jump to: [A](#a) · [B](#b) · [C](#c) · [D](#d) · [E](#e) · [F](#f) ·
[G](#g) · [H](#h) · [I](#i) · [K](#k) · [L](#l)

---

## A

### `ABS`

```
ABS n
```

The magnitude of *n*, discarding its sign.

```basic
PRINT ABS -3.5        : REM 3.5
```

### `ACS`

```
ACS n
```

Arc cosine, in radians. *n* must be in −1 to 1; outside that gives error 27,
*Invalid argument*.

```basic
PRINT ACS 0           : REM 1.5707963 (pi/2)
```

### `AND`

```
a AND b
a$ AND b
```

Priority 3. With two numbers: *a* if *b* is non-zero, otherwise 0. With a
string on the left: *a$* if *b* is non-zero, otherwise `""`.

```basic
PRINT "Bonus!" AND score > 100
LET capped = n AND n < 100
```

### `ASN`

```
ASN n
```

Arc sine, in radians. *n* must be in −1 to 1.

### `AT`

```
AT row, column
```

A print item, not a command. Moves the print position within the current
window. Usable in `PRINT`, `INPUT` and anything else that takes print items.

```basic
PRINT AT 10,5; "here"
```

Equivalent to `CHR$ 22 + CHR$ row + CHR$ column`.

### `ATN`

```
ATN n
```

Arc tangent, in radians, in the range −π/2 to π/2.

### `ATTR`

```
ATTR(row, column)
```

The attribute byte of a character cell: ink in bits 0–2, paper in 3–5, bright
in bit 6, flash in bit 7.

Only `MODE 1` and `MODE 2` have per-cell attributes; elsewhere you get
error 34, *Invalid screen mode*. A position outside the 24 × 32 grid gives
error 32, *Off screen*.

```basic
MODE 1: PRINT AT 0,0; PAPER 1; INK 6; "X"
PRINT ATTR(0,0)
```

### `AUTO`

```
AUTO [line [, step]]
```

Turns on automatic line numbering while you type. With no parameters it
continues from the current line plus 10.

The step must not exceed the starting line. `AUTO` does not return, so
nothing may follow it on the line. Press ENTER on an empty line to stop.

```basic
AUTO 100, 10
```

---

## B

### `BAND`

```
a BAND b
```

Priority 3. Bitwise AND of two 16-bit integers. Both operands must be 0 to
65535, or you get error 30, *Integer out of range*.

```basic
PRINT BIN$ (BIN 1100 BAND BIN 1010)   : REM 1000
```

### `BEEP`

```
BEEP duration, pitch
```

Sounds a note through the internal speaker. *duration* is in seconds, up to
16; *pitch* is a semitone offset from middle C, giving a frequency of
55 × 2^((*pitch*+27)/12) Hz.

Blocks until finished, with interrupts disabled.

| Error | Cause |
|---|---|
| 49 | *Invalid Note* — frequency outside about 8 Hz to 16 kHz |
| 50 | *Note too long* — duration over 16 seconds |

```basic
FOR n = 0 TO 12: BEEP 0.15, n: NEXT n
```

### `BIN`

```
BIN digits
```

A binary numeric literal — part of the number syntax rather than a function.

```basic
PRINT BIN 10110       : REM 22
```

### `BIN$`

```
BIN$ n
```

*n* as binary text, with no leading zeros. The two digit characters come from
the system variables at offsets &03 and &04, so they can be changed.

```basic
PRINT BIN$ 22         : REM 10110
```

### `BLITZ`

```
BLITZ string
```

Executes a string of packed graphics commands — far faster than the
equivalent BASIC. Strings are normally produced by `RECORD`. See
[chapter 9](09-graphics.md#99-blitz--replaying-graphics-from-a-string) for
the command codes.

`RECORD` is suspended while `BLITZ` runs. An unrecognised code gives
error 35, *Invalid BLITZ code*.

```basic
BLITZ picture$
```

### `BLOCKS`

```
BLOCKS n
```

Chooses what character codes 128 to 143 draw. `BLOCKS 1` synthesises them as
quarter-cell block graphics at whatever cell size is current; `BLOCKS 0`
takes them from the user-defined graphics instead.

### `BOOM`

```
BOOM
```

A canned sound effect: an upward sweep. Takes no parameters. See also `ZAP`,
`POW`, `ZOOM`.

### `BOOT`

```
BOOT [n]
```

`BOOT` or `BOOT 0` auto-loads only if a DOS is already resident. `BOOT 1`
forces a full boot from disk with no auto-load afterwards.

The loader drives the disk controller directly, reads sector 1 of track 4,
checks that it begins `BOOT`, and jumps into it. Error 55, *Missing disk*, if
there is nothing bootable.

Function key F9 types `BOOT`.

### `BOR`

```
a BOR b
```

Priority 2. Bitwise OR of two 16-bit integers. There is no `BXOR`; build one
as `(a BOR b) - (a BAND b)`.

### `BORDER`

```
BORDER n
```

Sets the border colour, 0 to 7. Also chooses a contrasting attribute for the
lower screen, which is why the typing area changes appearance with it.

The border colour is written to the keyboard port, whose top two bits are the
speaker-off and MIDI-through flags rather than colour; `BORDCOL` (23627)
keeps the whole byte.

### `BRIGHT`

```
BRIGHT n
```

A command or a print item. 0 = normal, 1 = bright, 8 = transparent (leave
whatever is there). 16 is accepted and treated as 8; anything else gives
error 23.

In `MODE 4`, `BRIGHT 1` adds 8 to both the ink and paper colour numbers. In
`MODE 3` it is ignored. In modes 1 and 2 it sets the attribute's bright bit.

### `BUTTON`

```
BUTTON n
```

1 if mouse button *n* (1 to 3) is down, 0 if not. `BUTTON 0` tests all three
at once. *n* of 4 or more gives error 30.

Requires a mouse driver installed in the `MOUSV` vector.

---

## C

### `CALL`

```
CALL address [, parameter …]
```

Calls machine code. The address uses the 0–524287 model and the ROM pages it
in. On entry HL and BC hold the entry address and A holds the parameter
count; parameters and their type bytes are on the calculator stack, to be
popped in reverse order.

`CALL` cannot return a value — use `USR` or `USR$`, or write results into
memory. See [chapter 13](13-memory-and-machine-code.md#136-calling-machine-code).

```basic
CALL 32768, x, y, name$
```

### `CHR$`

```
CHR$ n
```

The one-character string whose code is *n* (0 to 255).

```basic
PRINT CHR$ 65         : REM A
PRINT CHR$ 22 + CHR$ 5 + CHR$ 10 + "positioned"
```

### `CIRCLE`

```
CIRCLE [colour items ;] x, y, radius
```

Draws a circle centred on *x*, *y*. Colour items apply to this statement
only.

```basic
CIRCLE PEN 4; 128, 88, 60
```

### `CLEAR`

```
CLEAR [address]
```

Erases all variables, the BASIC stack, the calculator stack and the heap;
recreates the four graphics pseudo-variables; silences the sound chip; turns
off `RECORD` and `ON ERROR`. With an *address*, also moves `RAMTOP` there, so
memory above is out of BASIC's reach.

Error 48, *Invalid CLEAR address*, if the address leaves no usable room.

```basic
CLEAR 32767
```

### `CLOSE`

```
CLOSE #stream
CLOSE #                                       [DOS]
CLOSE SCREEN n
CLOSE n
```

* `CLOSE #s` detaches a stream. Streams 0–3 revert to their defaults; 4–15
  become closed. If the stream was open to a DOS file, the file is flushed
  and its directory entry completed — **an unclosed output file is left
  incomplete on the disk**.
* **`[DOS]`** `CLOSE #` with no number closes *every* open file. Always do
  this before the program ends. (MasterDOS also accepts `CLEAR #`.)
* `CLOSE SCREEN n` frees a screen's two pages. Error 46, *Current screen*, if
  it is the one being drawn on.
* `CLOSE n` releases *n* 16K pages of BASIC's allocation.

```basic
CLOSE #5
CLOSE #
```

### `CLS`

```
CLS
CLS 1
CLS #
```

`CLS` clears the whole screen and resets the graphics origin. `CLS 1` clears
only the current window. `CLS #` also resets the windows, the streams and the
colours — the "put everything back" form, typed by function key F6.

### `CODE`

```
CODE a$
```

The character code of the first character of *a$*, or 0 for an empty string.

```basic
PRINT CODE "A"        : REM 65
```

### `CONTINUE`

```
CONTINUE
```

Resumes the program from where it stopped. After a BREAK during I/O
(report 14) the same statement is re-run; after a stop between statements
(report 15) execution resumes at the next one.

Lines may be edited between the stop and the `CONTINUE`.

### `COPY` — **`[DOS]`**

```
COPY [OVER] "source" TO "destination"
```

Copies a file. `OVER` allows an existing destination to be replaced; without
it a name clash is an error. Either name may carry a drive prefix — `d1:` or
`d2:`, never a bare number.

Reserved by the ROM and implemented by both SAMDOS 2 and MasterDOS. Note that
the ROM's own screen dump is `DUMP`, not `COPY`.

```basic
COPY "data" TO "backup"
COPY OVER "d2:data" TO "d1:data"
```

### `COS`

```
COS n
```

Cosine of *n* radians.

### `CSIZE`

```
CSIZE width, height
```

Sets the character cell size. *width* is 6 or 8 — 6 has an effect only in
`MODE 3`, where it gives 85 columns rather than 64. *height* is 6 to 32;
16 or more is drawn double-height. Anything else gives error 30.

The cell is always the full height, but only `min(height, 8)` scans of the
bitmap are drawn — 16 with doubling — so characters join up vertically only
at heights 6, 7, 8 and 16.

Changing `CSIZE` also changes the number of text rows, the window layout and
the graphics origin.

```basic
MODE 3: CSIZE 6, 8    : REM 85 columns
```

---

## D

### `DATA`

```
DATA item [, item …]
```

Holds constants for `READ`. Inert at run time, so falling into one is
harmless. Items are validated when the line is entered.

An item may be any constant expression, since plain `READ` evaluates it
fully.

```basic
100 DATA "Alice", 30, 2*PI
```

### `DEF FN`

```
DEF FN name[$] ( [parameter [, parameter …]] ) = expression
```

Defines a single-expression function. The name follows variable-name rules
and must end in `$` if and only if the body yields a string. **Parameters
must be single letters**, optionally followed by a dollar sign.

Inert at run time. Call with `FN`.

```basic
1000 DEF FN cube(x) = x*x*x
1010 DEF FN pad$(s$) = s$ + STRING$(20 - LEN s$, " ")
```

### `DEF KEYCODE`

```
DEF KEYCODE n, a$
DEF KEYCODE n : rest-of-line
```

Gives key code *n* (192 or above) an expansion. When the editor receives that
code it inserts the definition, which may contain keyword tokens.

The second form takes everything to the end of the line, which is the easy
way to include keywords.

Error 52, *Too many definitions*, when the buffer (limit in `DKLIM`, 23504)
fills.

```basic
DEF KEYCODE 202: PRINT AT 0,0;
```

### `DEF PROC`

```
DEF PROC name [[REF] parameter [, [REF] parameter …]]
DEF PROC name DATA
```

Defines a procedure, ended by `END PROC`. Call it by writing its name as a
statement.

Parameters are by value unless marked `REF`. A `REF` numeric parameter copies
the final value back to the caller's variable; a `REF` string or array is
passed by renaming, so no copy is made.

`DEF PROC name DATA` binds no parameters — instead the caller's argument list
becomes a `DATA` list, read with `READ` and interrogated with `ITEM`.

Inert at run time: falling into a definition skips the whole body.

```basic
1000 DEF PROC swap REF a, REF b
1010   LOCAL t
1020   LET t = a: LET a = b: LET b = t
1030 END PROC
```

### `DEFAULT`

```
DEFAULT variable = expression
```

Assigns **only if the variable does not already exist**, or holds the "minus
zero" value that unsupplied procedure parameters are given. The idiomatic way
to give a procedure an optional parameter.

```basic
1000 DEF PROC box w, h
1010   DEFAULT w = 10
1020   DEFAULT h = 5
```

### `DELETE`

```
DELETE [first] [TO [last]]
```

Removes a range of program lines in one operation. Both ends are optional.
`DELETE 100` removes just line 100. An inverted range does nothing.

```basic
DELETE 1000 TO 1999
DELETE TO 50
```

### `DEVICE`

```
DEVICE letter [number]
```

Selects where `SAVE` and `LOAD` go. `T` is tape (the number is the speed),
`N` is the network (the number is the station, default 0), and any other
letter is passed to the DOS with the number as a drive, defaulting to 1.

Both SAMDOS 2 and MasterDOS use `D` for a disk drive. Drives 1 and 2 are
physical; **`[MD]`** MasterDOS adds 3 to 7 as RAM disks.

```basic
DEVICE T          : DEVICE T45
DEVICE D          : DEVICE D2
DEVICE N5
```

The trailing colon often written — `DEVICE D1:` — is just a statement
separator.

### `DIM`

```
DIM name(d1 [, d2 …]) [, name(…) …]
```

Creates an array with every element cleared, deleting any existing variable
of the same name. Subscripts run from 1.

Numeric elements are 5 bytes each; string elements are 1 byte, so
`DIM a$(20,12)` is 20 fixed-width slots of 12 characters and `DIM a$(20)` is
a 20-character string.

Names are limited to 10 characters (error 40 if longer). A dimension of 0 or
a subscript out of range gives error 4, *Subscript wrong*.

```basic
DIM score(10), grid(8,8), name$(20,12)
```

### `DIR` — **`[DOS]`**

```
DIR [#stream] [pattern$]
DIR n
DIR = path$
```

Lists the directory. With no argument it lists the current drive to the
screen; a pattern selects matching names, and `#stream` sends the listing
elsewhere — `DIR #16` captures it into a string (see `RECORD`).

`DIR n` lists drive *n*. `DIR = path$` sets the current sub-directory
(**`[MD]`**).

```basic
DIR
DIR "m*"
DIR #3                    : REM to the printer
DIR = "letters"
```

### `DISPLAY`

```
DISPLAY n
```

Chooses which screen is *shown*. `DISPLAY 0` means "show whichever screen is
being drawn on", which is the normal state. Use with `SCREEN` for double
buffering.

### `DIV`

```
a DIV b
```

Priority **14** — tighter than `*` and `/`. Integer division: `INT(a/b)`.

```basic
PRINT 17 DIV 5        : REM 3
```

### `DO`

```
DO
DO WHILE condition
DO UNTIL condition
```

Begins a loop, closed by `LOOP`. The condition may be at the top, the bottom,
both or neither.

Error 9, *Missing LOOP*, if no matching `LOOP` is found.

```basic
DO WHILE ITEM
  READ a$: PRINT a$
LOOP
```

### `DPEEK`

```
DPEEK address
```

The 16-bit word at *address*, low byte first. Uses the 0–524287 address
model.

### `DPOKE`

```
DPOKE address, word
```

Writes a 16-bit word, low byte first.

### `DRAW`

```
DRAW [colour items ;] x, y
DRAW [colour items ;] TO x, y
DRAW [colour items ;] x, y, angle
```

* **Relative**: a line *x*, *y* from the current graphics position. The
  `xrg`/`yrg` ranges are applied, but not the `xos`/`yos` offsets.
* **`TO`**: a line to the absolute point *x*, *y*. Both ranges and offsets
  apply.
* **Curved**: an arc bulging by *angle* radians, approximated by up to four
  chords.

Error 32, *Off screen*, if the line leaves the display.

```basic
PLOT 20,20: DRAW 100,0: DRAW 0,100
DRAW TO 200, 150
DRAW 60, 60, PI
```

### `DUMP`

```
DUMP
DUMP CHR$
```

Screen dump to the printer. Both forms go through the `DMPV` vector (23258),
and **do nothing at all** if no printer driver is installed there — the ROM
contains none.

The two forms are equivalent in practice: both enter the driver with A = &AF,
the "graphics" value. The ROM source labels the `CHR$` branch a text copy but
does not implement it that way; A = 0 reaches the driver only through the
`JTCOPY` jump-table entry at &015D.

### `DVAR` — **`[DOS]`**

```
DVAR n
```

The **address** of DOS variable *n* — the DOS's equivalent of `SVAR`, so it
is used the same way:

```basic
POKE  DVAR 15, 2                : REM MasterDOS: default drive
DPOKE DVAR 151, 0               : REM MasterBASIC: silence the warning BEEP
```

The variables themselves are the DOS's own, and the numbering differs between
SAMDOS 2 and MasterDOS beyond about index 7. See
[dos-and-extensions.md §4.6](../dos-and-extensions.md#46-dvar).

---

## E

### `ELSE`

```
IF condition THEN statements : ELSE statements
```

or, in the block form:

```
IF condition
  …
ELSE
  …
END IF
```

`ELSE IF condition` chains in the block form. `ELSE` is a statement, so in
the single-line form it needs a colon in front of it.

The tokeniser cannot distinguish the two forms; the syntax checker rewrites
the stored token to match the `IF` it belongs to.

### `END IF`

```
END IF
```

Closes a block `IF`. Compulsory in the block form; omitting it gives
error 39, *Missing END IF*.

### `END PROC`

```
END PROC
```

Returns from a procedure. Also discards the procedure's local variables,
copies back any `REF` numeric parameters, restores renamed `REF` strings and
arrays, and **re-arms `ON ERROR`** — which is what makes an error handler
written as a procedure work more than once.

Error 13, *No END PROC*, if a definition has none.

### `EOF` — **`[DOS]`**

```
EOF #stream
```

Non-zero at the end of the file attached to *stream*.

### `ERASE` — **`[DOS]`**

```
ERASE [OVER] "name"
```

Deletes a file. `OVER` suppresses the confirmation prompt. The name may
include wildcards, so `ERASE "*.bak"` removes a set of files.

Erasing frees the file's sectors in the disk's sector-allocation map and
clears its directory entry; the data itself is not overwritten. See
[chapter 11](11-data-files-and-devices.md#118-disk-operations-and-the-filesystem).

```basic
ERASE "oldfile"
ERASE OVER "temp*"
```

### `EXIT IF`

```
EXIT IF condition
```

If the condition is true, leaves the enclosing `DO` loop immediately,
continuing after its `LOOP`. Discards the loop's stack frame correctly.
`EXIT IF 1` is the unconditional form.

### `EXP`

```
EXP n
```

e raised to the power *n*. Error 28, *Number too large*, on overflow.

---

## F

### `FATPIX`

```
FATPIX n
```

`FATPIX 0` selects thin pixels, giving access to all 512 columns of `MODE 3`.
`FATPIX 1` doubles each pixel so that X coordinates run 0–255 as in the other
modes.

Changing it rescales the current X coordinate and `xrg`, so nothing moves on
screen. It has no effect outside `MODE 3`.

### `FILL`

```
FILL [USING pattern$ ,] [colour items ,] x, y [, flag]
```

Flood-fills the region containing *x*, *y*. With `USING`, fills with a
128-byte pattern tile (8 bytes wide, 16 scans tall) — most easily produced
with `GRAB`. An explicit colour item overrides the pattern and gives a solid
fill.

*flag* of 1 reuses the check screen built by the previous `FILL` instead of
rebuilding it.

```basic
CIRCLE 128,88,60
FILL PEN 4; 128, 88
```

### `FLASH`

```
FLASH n
```

A command or print item. 0 = steady, 1 = flashing, 8 = transparent. Only
modes 1 and 2 have a flash attribute bit; in modes 3 and 4 use a flashing
palette entry (`PALETTE i,b,c`) instead.

### `FN`

```
FN name[$] ( [argument …] )
```

Calls a function defined with `DEF FN`. Error 7, *FN without DEF FN*, if
there is no matching definition.

```basic
PRINT FN cube(3)
```

### `FOR`

```
FOR variable = start TO limit [STEP step]
```

Begins a counted loop, closed by `NEXT variable`. The control variable must
be a simple numeric variable — not a string, not an array element.

If no iteration is possible the body is skipped by searching forward for the
matching `NEXT`; if there is none you get error 6, *FOR without NEXT*.

```basic
FOR i = 10 TO 1 STEP -1: PRINT i: NEXT i
```

### `FORMAT` — **`[DOS]`**

```
FORMAT
FORMAT "d1:name"
FORMAT "d1:name", dirtracks                        [MD]
FORMAT "d3:name", dirtracks, totaltracks           [MD]
FORMAT "d1:" TO "d2:"
FORMAT TO "d2:"
```

Formats a disk. The operand is a **drive specifier**, not a plain name: it is
put through the same prefix parser as any other file name, so it takes a
`dn:` prefix and must name a `D` device. With no operand at all the current
`DEVICE` drive is used.

**`[MD]`** The text *after* the prefix becomes the disc's name, written into
track 0. **`[SD2]`** SAMDOS 2 has no disc names and ignores the text
entirely — there, the operand is *only* a way of choosing the drive.

Formatting writes the track and sector structure, an empty directory and an
empty sector-allocation map. Everything previously on the disk is lost.

```basic
FORMAT                     : REM the current DEVICE drive
FORMAT "d2:work disk"      : REM drive 2, named "work disk" under MasterDOS
```

**Format and copy.** The `TO` forms are not a re-label: they format one disk
and then copy another onto it, track by track. **The disk named first is the
one destroyed.**

| Form | Formatted and written | Read from |
|---|---|---|
| `FORMAT "d1:" TO "d2:"` | drive 1 | drive 2 |
| `FORMAT TO "d2:"` | the current `DEVICE` drive | drive 2 |

Read `FORMAT "d1:" TO "d2:"` as "format d1 *to be* d2", not as "copy d1 to
d2" — it is the opposite way round from `COPY` and `MOVE`, and getting it
backwards erases the disk you meant to keep.

Both operands go through the drive-prefix parser, so in practice both need
their prefix: an operand without one takes the current `DEVICE` drive, and
naming the same drive twice is meaningless.

**`[MD]`** RAM disks are rejected in the `TO` forms — the copy works only
between real drives.

```basic
FORMAT "d1:" TO "d2:"      : REM wipe drive 1, make it a copy of drive 2
```

**Extra parameters.** **`[MD]`** MasterDOS lets the directory be sized at
format time. *dirtracks* is 4 to 39 on a real disk (80 to 780 files) and 1 to
39 on a RAM disk; *totaltracks* sizes a RAM disk and may only be given for
one.

```basic
FORMAT "d1:big dir", 8     : REM eight directory tracks
FORMAT "d3:scratch", 1, 40 : REM a 40-track RAM disk
FORMAT "d3:", 0            : REM erase RAM disk 3 entirely
```

The keyword is also used, unrelatedly, by the ROM in `LIST FORMAT n`.

### `FREE`

```
FREE
```

The number of free bytes.

---

## G

### `GET`

```
GET variable
```

Waits for a single keypress. A string variable receives the character; a
numeric variable receives its value as a hexadecimal digit, so `"0"`–`"9"`
give 0–9 and `"A"`–`"F"` give 10–15. BREAK still works while it waits.

```basic
GET k$: PRINT "You pressed "; k$
```

### `GOSUB` (`GO SUB`)

```
GOSUB line
GOSUB ON expression ; line, line, …
```

Calls a subroutine, remembering where to come back to. The plain form accepts
any numeric expression, not just a constant.

The `ON` form selects the *n*'th line in the list; if the index is out of
range, execution simply falls through to the next statement.

Error 8, *RETURN without GOSUB*, if `RETURN` finds no frame.

```basic
GOSUB 1000
GOSUB ON choice; 1000, 2000, 3000
```

### `GOTO` (`GO TO`)

```
GOTO line
GOTO ON expression ; line, line, …
```

As `GOSUB` but without a return. Both spellings, with and without the space,
are accepted and list identically.

Leaving a loop or subroutine with `GOTO` leaves its frame on the BASIC stack
— use `EXIT IF`, or `POP` explicitly.

### `GRAB`

```
GRAB string-variable, x, y, width, length
```

Captures a rectangle of screen into a string. Requires `MODE 3` or `MODE 4`.
*x*, *y* is the top-left corner in graphics coordinates, *width* is in
**bytes** and *length* in scan lines.

The resulting string begins with a three-byte header — `&00`, width, length —
followed by the pixel data.

Error 36, *Stored area too big*, beyond the 8K buffer.

```basic
GRAB sprite$, 10, 180, 12, 22
```

---

## H

### `HEX$`

```
HEX$ n
```

*n* as hexadecimal text.

```basic
PRINT HEX$ 255        : REM FF
```

### `HIDE` — **`[DOS]`**

```
HIDE [OFF] "name"
```

Sets the hidden attribute on a file so that it does not appear in a `DIR`
listing. `HIDE OFF "name"` clears it again. The file is otherwise unaffected
and still loads normally.

The attribute lives in the file's directory entry, in the same byte as the
protect flag.

```basic
HIDE "secret"
HIDE OFF "secret"
```

---

## I

### `IF`

```
IF condition THEN statements [: ELSE statements]

IF condition
  statements
[ELSE IF condition
  statements]
[ELSE
  statements]
END IF
```

The presence of `THEN` decides which form this is. The single-line form ends
at the end of the line; the block form must be closed by `END IF`.

```basic
IF x = 1 THEN PRINT "one": ELSE PRINT "other"

IF score > 100
  PRINT "Excellent"
ELSE IF score > 50
  PRINT "Not bad"
ELSE
  PRINT "Try again"
END IF
```

### `IN`

```
IN port
```

Reads a byte from a hardware port. See
[chapter 13](13-memory-and-machine-code.md#135-hardware-ports).

### `INK`

A synonym for `PEN`. Typing `INK` stores the `PEN` token, so `INK 3` lists
back as `PEN 3`.

### `INKEY$`

```
INKEY$
INKEY$ #stream
```

Without a stream, the key currently held down, or `""` if none. It performs a
**fresh keyboard scan** rather than reading the buffered last key, so a key
released before the call is not reported — which makes it correct for "is
this key down now?" tests.

With a stream, reads one character from that stream.

```basic
DO: LET k$ = INKEY$: LOOP UNTIL k$ <> ""
```

### `INPUT`

```
INPUT [items and variables …]
INPUT [items] LINE string-variable
```

Reads values from the keyboard (or the current stream). Accepts the same item
list as `PRINT` — separators, `AT`, `TAB`, colour items and parenthesised
groups — mixed with the variables being read.

A numeric answer is syntax-checked as an expression, so the user may type
`2*3`. A string answer is edited between a pre-supplied pair of quotes.
`INPUT LINE` takes the raw characters with no quotes and no checking, and
requires a string variable.

A typing mistake restarts the edit, but only when reading from the keyboard.
BREAK gives report 17, *STOP in INPUT*.

```basic
INPUT "Name? "; n$
INPUT AT 0,0; PAPER 1; "Age? "; age
INPUT LINE "Comment: "; c$
```

### `INSTR`

```
INSTR(a$, b$)
INSTR(start, a$, b$)
```

The position of the first occurrence of *b$* within *a$*, counting from 1, or
0 if it is not there. The optional *start* begins the search later.

The character in the system variable at offset &05 — normally `#` — is a
wildcard matching anything.

```basic
PRINT INSTR("hello world", "wor")     : REM 7
PRINT INSTR("hello world", "w#r")     : REM 7
```

### `INT`

```
INT n
```

The **floor** of *n* — the largest whole number not greater than it. Note
`INT -5.9` is `-6`, not `-5`.

### `INVERSE`

```
INVERSE n
```

A command or print item. `INVERSE 1` swaps ink and paper while printing;
`INVERSE 0` restores. It also affects `PUT`. Only 0 and 1 are accepted.

### `ITEM`

```
ITEM
```

What remains in the current `DATA` statement: 0 nothing, 1 the next item is a
string, 2 it is a number.

Together with `DEF PROC name DATA` this lets a procedure adapt to however
many arguments it was given.

```basic
DO WHILE ITEM
  IF ITEM = 1 THEN READ a$ : ELSE READ n
LOOP
```

---

## K

### `KEY`

```
KEY position, value
```

Rewrites one entry of the keyboard translation table, so a key produces a
different code. Positions run 1 to 280 — 70 keys in four planes (unshifted,
CAPS, SYMBOL, CONTROL). Position 0 exists but is unused.

Combine with `DEF KEYCODE` to make a key type a whole command.

### `KEYIN`

```
KEYIN string
```

Tokenises and executes *string* exactly as though it had been typed. It may
run a command, or — if the string begins with a line number — add a line to
the program.

The command body is copied to a private buffer before running, so a `KEYIN`
may safely contain another.

```basic
KEYIN "1000 PRINT ""generated"""
KEYIN "PRINT " + STR$ x
```

---

## L

### `LABEL`

```
LABEL name
```

Inert at run time. The compile pass, which runs before every `RUN`, assigns
the label's line number to the named numeric variable. Jump to the variable
rather than to a literal number — labels survive `RENUM`, insertion and
deletion.

```basic
  10 GOTO mainloop
1000 LABEL mainloop
```

### `LEN`

```
LEN a$
```

The number of characters in *a$*.

### `LENGTH`

```
LENGTH(n, variable)
```

Reports on a variable:

| *n* | Result |
|---|---|
| 0 | The address of the variable's data |
| 1 | The number of elements |
| 2 | The element length |

For a simple string the count is the length and the element length is 1. For
`DIM a$(20,12)` the count is 20 and the element length 12.

`LENGTH(0, …)` is how you hand an array's address to `POKE` or to machine
code — but fetch it afresh each time, since creating a variable can move
things.

```basic
PRINT LENGTH(1, names$); " slots of "; LENGTH(2, names$)
```

### `LET`

```
LET variable = expression
```

Assignment. **`LET` is compulsory** — a statement beginning with a bare name
is read as a procedure call, so `x = 1` gives *Missing DEF PROC*.

The destination may be a simple variable, an array element, or a string
slice:

```basic
LET a$ = "abcdef"
LET a$(2 TO 3) = "XY"       : REM aXYdef
LET grid(3,4) = 99
```

Assigning to a slice overwrites in place without changing the length.

### `LINE`

```
SAVE "name" LINE n
INPUT LINE a$
READ LINE a$
PALETTE i, c LINE y
```

A qualifier used by four unrelated statements; it is not a command in its own
right. `RENUM` treats it as introducing a line number only when it follows a
closing quote or a `$`, which is how it tells `SAVE … LINE 10` from
`INPUT LINE a$`.

### `LIST`

```
LIST [#stream] [,|;] [first] [TO [last]]
LIST FORMAT n
```

Lists the program. The first line listed becomes the current line.

`LIST FORMAT n` sets the pretty-lister: *n* is 0 (off), 1 or 2 columns of
indent per level of nesting, with each statement on its own screen line.
Anything else gives error 30. The indentation is applied when listing and
never stored.

```basic
LIST 100 TO 200
LIST #4; 1000 TO
LIST FORMAT 2
```

### `LLIST`

```
LLIST …
```

As `LIST`, but to stream 3 (the printer).

### `LN`

```
LN n
```

Natural logarithm. *n* must be positive; zero or negative gives error 27,
*Invalid argument*.

### `LOAD`

```
LOAD "name"
LOAD "name" CODE [start [, length [, execute]]]
LOAD "name" SCREEN$
LOAD "name" DATA array()
```

Loads a file. An empty name loads the next file of the right type.

A program load clears the variables and does a `RESTORE`; if the file was
saved with `LINE n`, it runs. `LOAD "x" CODE` with no address returns the
block to where it was saved from. `LOAD "x" DATA a()` creates the array if it
does not exist.

Function keys F7 and F8 type `LOAD ""` and `LOAD "" CODE`.

### `LOCAL`

```
LOCAL variable [, variable …]
```

Hides any global of that name for the duration of the current procedure and
creates a fresh local, discarded by `END PROC`. Locals start out not
existing, so `DEFAULT` works on them.

Works for numbers, strings and arrays alike, because it uses the same
machinery as parameter binding. `LOCAL REF x` is not accepted.

```basic
1000 DEF PROC total REF list
1010   LOCAL i, sum
1020   FOR i = 1 TO LENGTH(1, list): LET sum = sum + list(i): NEXT i
1030   PRINT sum
1040 END PROC
```

### `LOOP`

```
LOOP
LOOP WHILE condition
LOOP UNTIL condition
```

Closes a `DO` loop. Error 10, *LOOP without DO*, if there is no matching
frame.

### `LOOP IF`

```
LOOP IF condition
```

If the condition is true, goes back to the `DO` immediately, skipping the
rest of the loop body. `LOOP IF 1` is the unconditional form.

### `LPRINT`

```
LPRINT …
```

As `PRINT`, but to stream 3 (the printer). Output passes through the `LPRTV`
vector (23288) if one is installed.

---

[Contents](README.md) · **A–L** · [M–Z](appendix-a-keywords-m-z.md)
