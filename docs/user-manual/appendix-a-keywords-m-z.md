# Appendix A — Keyword Reference, M to Z

[Contents](README.md) · [A–L](appendix-a-keywords-a-l.md) · **M–Z**

---

Jump to: [M](#m) · [N](#n) · [O](#o) · [P](#p) · [R](#r) · [S](#s) ·
[T](#t) · [U](#u) · [V](#v) · [W](#w) · [X](#x) · [Y](#y) · [Z](#z) ·
[Extensions](#keywords-added-by-the-extensions)

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
[end of this file](#keywords-added-by-the-extensions) and covered in full by
[dos-and-extensions.md](../dos-and-extensions.md).

---

## M

### `MEM$`

```
MEM$(n1 TO n2)
```

Memory from address *n1* to *n2* as a string, using the 0–524287 address
model. The natural partner of `POKE address, string$`, and together they give
you block copy in both directions with no loops.

```basic
LET block$ = MEM$(32768 TO 33023)     : REM 256 bytes
POKE 40000, block$                    : REM put them back somewhere else
```

### `MERGE`

```
MERGE "name"
```

Loads a program and splices it into the current one: lines replace lines of
the same number, numeric variables are re-created one at a time, and strings
and arrays replace any of the same name. Everything else is left untouched.

`MERGE "name" DATA …` is not allowed.

The way to combine a library of procedures with a main program.

### `MOD`

```
a MOD b
```

Priority **14** — tighter than `*` and `/`, which is a common trap. The
remainder, computed as `a - b*INT(a/b)`.

```basic
PRINT 17 MOD 5              : REM 2
PRINT 10 * 7 MOD 3          : REM 10, i.e. 10*(7 MOD 3)
```

### `MODE`

```
MODE n
```

Selects a screen mode, 1 to 4. Anything else gives error 34, *Invalid screen
mode*.

| Mode | Resolution | Colours | Notes |
|---|---|---|---|
| 1 | 256 × 192 | 2 per 8 × 8 cell | ZX layout, separate attribute block |
| 2 | 256 × 192 | 2 per 8 × 1 cell | Linear |
| 3 | 512 × 192 | 4 | The only mode with 6-pixel characters |
| 4 | 256 × 192 | 16 | |

Clears the screen, rebuilds the pixel expansion tables and resets the
windows. Function key F3 types `MODE`.

### `MOVE` — **`[MD]`**

```
MOVE "source" TO "destination"
```

Moves a file, copying it and erasing the original. The two names may be on
different drives, in which case the data is transferred; on the same drive
only the directory entry changes.

Reserved for a DOS by the ROM. SAMDOS 2 does not implement it — MasterDOS
does.

```basic
MOVE "d1:report" TO "d2:report"
```

---

## N

### `NEW`

```
NEW
```

Erases the program, all variables, the screens above screen 1 and the key
definitions, and resets the machine. Ends by printing the copyright banner
and **waiting for a keypress**, which is why it cannot usefully be run from a
program.

The last five system variables — the screen list, `LASTPAGE`, `RAMTOP` and
the fitted-RAM size — are not cleared.

### `NEXT`

```
NEXT variable
```

Ends a `FOR` loop. The variable name is required, and must be the loop's
control variable. Error 5, *NEXT without FOR*, if it is not currently one.

### `NOT`

```
NOT n
```

Priority 4. 1 if *n* is zero, 0 otherwise.

Note the low priority: `NOT a = b` is `NOT (a = b)`, which is usually what
you want, but `NOT a AND b` is `(NOT a) AND b`.

---

## O

### `OFF` — **`[DOS]`**

Tokenised by the ROM as a qualifier but never used by it. Both SAMDOS 2 and
MasterDOS use it to *clear* a file attribute, as `PROTECT OFF "name"` and
`HIDE OFF "name"`.

### `ON`

```
ON expression : statement : statement : …
```

Runs the *n*'th of the statements that follow on the line, then abandons the
rest of the line.

A `GOTO` as the selected statement simply jumps; a `GOSUB` or procedure call
returns to the statement after the whole `ON`.

```basic
ON state: idle : running : finished
```

### `ON ERROR`

```
ON ERROR statement
ON ERROR STOP
```

Records where it is and skips the statement that follows it. When an error
occurs, execution re-enters that statement and the handler runs.

Three numeric variables are created for the handler: `error` (the error
number), `lino` (the line it happened in) and `stat` (the statement number).

The arming is consumed when the handler fires, so an error inside the handler
stops the program properly. `END PROC` re-arms it — so a handler written as a
procedure works every time.

`ON ERROR STOP` disarms. Used as a direct command, `ON ERROR` merely disarms.

```basic
  10 ON ERROR recover
1000 DEF PROC recover
1010   PRINT "error "; error; " at "; lino; ":"; stat
1020 END PROC
```

### `OPEN`

```
OPEN #stream, channel$
OPEN #stream; "filename" [IN | OUT | RND]     [DOS]
OPEN DIR "name"                               [MD]
OPEN BLOCKS n                                 [MB]
OPEN SCREEN n, mode
OPEN n
OPEN TO n
```

* `OPEN #s, "x"` attaches a stream to a built-in channel. The name must be a
  single character — `k`, `s`, `p`, `$` or `b`. Anything longer or different
  is passed to the DOS.
* **`[DOS]`** `OPEN #s; "name" OUT` creates a serial (OPENTYPE) file and
  attaches the stream to it; `IN` opens an existing one for reading, and
  `RND` (**`[MD]`**) opens it for random access. See
  [chapter 11](11-data-files-and-devices.md#118-disk-operations-and-the-filesystem).
* **`[MD]`** `OPEN DIR "name"` creates a sub-directory.
* **`[MB]`** `OPEN BLOCKS n` pre-allocates *n* file buffers so that later
  `OPEN`s do not move the BASIC program.
* `OPEN SCREEN n, mode` allocates two consecutive pages for a new screen.
* `OPEN n` reserves *n* more 16K pages for BASIC; `OPEN TO n` reserves or
  releases so that exactly *n* are owned.

`OPEN #16` is not permitted — use `RECORD`.

| Error | Cause |
|---|---|
| 45 | *Stream is already open* |
| 44 | *Screen is already open* |
| 1 | *Out of memory* — no free pages |

```basic
OPEN #4, "s"
OPEN #5; "results" OUT
```

### `OR`

```
a OR b
```

Priority 2. 1 if *b* is non-zero, otherwise *a*.

### `OUT`

```
OUT port, value
```

Writes a byte to a hardware port. Writing to the paging ports (250, 251) from
BASIC will crash the machine.

### `OVER`

```
OVER n
```

A command or print item, 0 to 3:

| Value | Effect |
|---|---|
| 0 | Replace |
| 1 | XOR — draw twice to erase |
| 2 | OR (graphics only) |
| 3 | AND (graphics only) |

Values 0 and 1 affect both text and graphics; 2 and 3 affect graphics, `PUT`
and plotting. Anything else gives error 23.

---

## P

### `PALETTE`

```
PALETTE
PALETTE i, c
PALETTE i, b, c
PALETTE i, c LINE y
PALETTE i, b, c LINE y
PALETTE i LINE y
```

Maps colour number *i* (0–15) onto one of 128 hardware colours *c* (0–127).
Two colours make the entry flash, swapping every `SPEEDINK` frames; if they
are equal, nothing flashes. A bare `PALETTE` resets every entry and clears
the line-interrupt list.

`LINE y` schedules the change part-way down the frame, using BASIC's Y
coordinate convention (175 down to −16 for scan lines 0 to 191). Line 175 is
rejected — there is no preceding scan on which to raise the interrupt. Up to
127 changes may be queued per screen. `PALETTE i LINE y` deletes one.

The colour byte is `G1 R1 B1 BRIGHT G0 R0 B0` in bits 6 to 0.

| Error | Cause |
|---|---|
| 24 | *Invalid palette colour* |
| 25 | *Too many palette changes* |

```basic
PALETTE 1, 127
PALETTE 0, 0, 127                     : REM flashing
FOR y = 170 TO -16 STEP -12: PALETTE 0, RND(127) LINE y: NEXT y
```

### `PAPER`

```
PAPER n
```

A command or print item. Background colour, 0 to 15, plus 16 (transparent)
and 17 (contrasting). 18 or more gives error 23.

In modes 1 and 2, values above 7 select the colour minus 8 with `BRIGHT 1`.

### `PATH$` — **`[DOS]`**

```
PATH$
```

The current directory path.

### `PAUSE`

```
PAUSE [n]
```

Waits *n* frames (fiftieths of a second) or until a key is pressed. `PAUSE 0`
— or a bare `PAUSE`, which means the same — waits for a key with no time
limit.

Only genuine frame interrupts decrement the count, so line and MIDI
interrupts do not shorten the wait.

### `PEEK`

```
PEEK address
```

The byte at *address*, using the 0–524287 model.

### `PEN`

```
PEN n
```

A command or print item. Foreground colour, 0 to 15, plus 16 (transparent)
and 17 (contrasting). 18 or more gives error 23.

`INK` is a synonym: typing `INK` stores the `PEN` token, so `INK 3` lists
back as `PEN 3`.

In modes 1 and 2, values above 7 select the colour minus 8 with `BRIGHT 1`.
In `MODE 4`, `PEN i` with `BRIGHT 1` selects ink *i* + 8.

### `PI`

```
PI
```

3.14159265.

### `PLOT`

```
PLOT [colour items ;] x, y
```

Plots one point and makes it the current graphics position.

```basic
PLOT PEN 3; 128, 88
```

### `POINT`

```
POINT(x, y)
```

The colour index of a pixel: 0 or 1 in modes 1 and 2, 0–3 in `MODE 3`, 0–15
in `MODE 4`.

### `POKE`

```
POKE address, value [, value …]
POKE address, string
```

Writes bytes. Up to 32 values may follow the address, stored ascending. A
**string** argument is block-copied to the address — the fastest way to move
data from BASIC.

```basic
POKE 32768, 1, 2, 3
POKE 32768, "Hello"
POKE 32768, MEM$(40000 TO 40255)
```

### `POP`

```
POP [numeric-variable]
```

Discards the top entry of the BASIC stack, whatever kind it is — `DO`,
`GOSUB` or `PROC`. With a variable, the line number that frame referred to is
assigned to it. For a `PROC` frame, that procedure's locals are discarded
too.

The way to leave a loop or subroutine with a `GOTO` without leaking a frame.
Error 11, *No POP data*, if the stack is empty.

### `POW`

```
POW
```

A canned sound effect: a percussive hit. Takes no parameters.

### `PRINT`

```
PRINT [#stream] [item] [separator [item] …]
```

Items are expressions, `AT r,c`, `TAB c`, colour items, or parenthesised
groups. Separators:

| Separator | Effect |
|---|---|
| `;` | Nothing |
| `,` | Column tab (16 columns, or 8 if `TABVAR` is non-zero) |
| `'` | Newline |

A trailing separator suppresses the final newline.

```basic
PRINT "Name"; TAB 20; "Score"
PRINT PEN 2; "red"; PEN 4; "green"
PRINT AT 10,5; "positioned"
PRINT #3; "to the printer"
```

Function key F2 types `PRINT :`.

### `PROTECT` — **`[DOS]`**

```
PROTECT [OFF] "name"
```

Sets the protect attribute on a file, so that it cannot be erased or
overwritten. `PROTECT OFF "name"` clears it again.

The attribute lives in the file's directory entry, in the same byte as the
hidden flag. Use `FSTAT("name",4)` to read both (**`[MD]`**): the file type
plus 64 if protected, plus 128 if hidden.

```basic
PROTECT "master"
PROTECT OFF "master"
```

### `PTR` — **`[DOS]`**

```
PTR #stream
```

The file pointer of a stream.

### `PUT`

```
PUT [colour items ;] x, y, block$ [, mask$]
```

Writes a block captured by `GRAB` back to the screen. Requires `MODE 3` or
`MODE 4`. Honours `OVER` 0 to 3 and `INVERSE`.

With a *mask$* of the same size, only the pixels where the mask has one-bits
are altered — the way to draw an irregularly shaped sprite.

| Error | Cause |
|---|---|
| 37 | *Invalid PUT block* — the string's header is wrong |
| 38 | *PUT mask mismatch* — the mask is a different size |

```basic
PUT OVER 1; x, y, sprite$
PUT x, y, sprite$, mask$
```

---

## R

### `RAMTOP`

```
RAMTOP
```

The current `RAMTOP` address — the highest address BASIC will use. Set it
with `CLEAR n`.

### `RANDOMIZE`

```
RANDOMIZE [n]
```

Seeds the random number generator. A bare `RANDOMIZE`, or `RANDOMIZE 0`,
seeds from the frame counter and so is unpredictable. Any other value seeds
deterministically, which is what you want when debugging.

### `READ`

```
READ variable [, variable …]
READ LINE string-variable
```

Takes the next item from the `DATA` statements. Plain `READ` evaluates the
item as a full expression; `READ LINE` takes the raw characters up to the
next comma, colon or end of line.

Error 3, *DATA has all been read*, when the data runs out.

Inside a `DEF PROC name DATA`, `READ` takes the caller's arguments.

### `RECORD`

```
RECORD TO string-variable
RECORD STOP
```

Arms stream 16 so that printing to it appends to the named string, and makes
every graphics command append a `BLITZ` record to it as well.

`PRINT` is deliberately excluded from graphics recording, so
`PRINT PEN 5;` does not record a pen change. Only fat-pixel drawing is
recorded, since `BLITZ` coordinates are single bytes.

```basic
LET pic$ = ""
RECORD TO pic$
CIRCLE 128, 88, 40
RECORD STOP
BLITZ pic$
```

### `REF`

```
DEF PROC name REF parameter [, …]
```

A qualifier inside a `DEF PROC` parameter list, not a command — used alone it
gives *Not understood*.

Marks a parameter as passed by reference. A `REF` numeric argument must be a
variable name and its final value is copied back on return. A `REF` string or
array is passed by *renaming* the caller's variable, so no copy is made — the
efficient way to pass a large array.

### `REM`

```
REM anything at all
```

A comment. **Tokenising stops for the rest of the line**, so everything after
`REM` is stored exactly as typed and no keyword in it is turned into a token.

### `RENAME` — **`[DOS]`**

```
RENAME "old" TO "new"
RENAME TO "diskname"
```

Renames a file. The second form, with no source name, renames the **disk**
itself rather than a file.

Only the directory entry changes; no data is moved.

```basic
RENAME "draft" TO "final"
RENAME TO "Backups 1993"
```

### `RENUM`

```
RENUM [first] [TO [last]] [LINE n] [STEP m]
```

Renumbers the program, rewriting every reference to a line number as well —
in `GOTO`, `GOSUB`, `RESTORE`, `RUN`, `LIST`, `DELETE`, `SAVE … LINE` and so
on. `LINE` and `STEP` both default to 10.

Needs about 6K of free memory to build its translation table and refuses if
there is less.

`LINE` is treated as introducing a line number only when it follows a closing
quote or a `$`, so `INPUT LINE a$` and `PALETTE 1,7 LINE 100` are left alone.

Function key F1 types `RENUM :`.

```basic
RENUM
RENUM 500 TO 900 LINE 1000 STEP 5
```

### `RESTORE`

```
RESTORE [line]
```

Moves the `DATA` read pointer. `RESTORE` alone, or `RESTORE 0`, goes back to
the start of the program.

### `RETURN`

```
RETURN
```

Returns from a `GOSUB` to the statement after the call. Error 8, *RETURN
without GOSUB*, if there is no `GOSUB` frame on the stack.

### `RND`

```
RND
RND(n)
```

`RND` gives a random number *r* with 0 ≤ *r* < 1. `RND(n)` gives a whole
number from 0 to *n* inclusive.

A 16-bit linear congruential generator over the `SEED` system variable
(23670). See `RANDOMIZE`.

### `ROLL`

```
ROLL direction [, pixels [, x, y, width, length]]
```

Moves screen data, **wrapping** whatever falls off the edge back in at the
other side. Requires `MODE 3` or `MODE 4`.

| Direction | Value |
|---|---|
| Left | 1 |
| Up | 2 |
| Right | 3 |
| Down | 4 |

With one argument, one pixel of the whole screen. With two, the whole screen
by that many pixels. With six, an arbitrary rectangle — *x*, *y* is the
top-left corner in graphics coordinates, *width* is in **bytes** and *length*
in scan lines.

Error 36, *Stored area too big*, beyond the 8K buffer.

```basic
DO: ROLL 1, 2: PAUSE 1: LOOP
```

### `RUN`

```
RUN [line]
```

Equivalent to `CLEAR 0`, `RESTORE 0` and `GOTO line` — so it erases the
variables, recreates the graphics pseudo-variables and starts at the first
line, or at *line* if given.

Before running, the compile pass resolves every `FN` and `PROC` calling
buffer and assigns every `LABEL`'s line number to its variable.

Function key F4 types `RUN`.

---

## S

### `SAVE`

```
SAVE [OVER] "name"
SAVE [OVER] "name" LINE n
SAVE [OVER] "name" CODE start, length [, execute]
SAVE [OVER] "name" SCREEN$
SAVE [OVER] "name" DATA array()
```

| Form | Contents | Type |
|---|---|---|
| Plain | Program plus all variables | 16 |
| `LINE n` | The same, auto-running at line *n* | 16 |
| `CODE` | A block of memory | 19 |
| `SCREEN$` | The screen, its palette and its line-interrupt list | 20 |
| `DATA a()` | One numeric array | 17 |
| `DATA a$()` | One string array | 18 |

`OVER` permits an existing file to be replaced. `SAVE … CODE` requires at
least a start and a length; a third number is an execution address, making
the file auto-run.

A name may begin with `CHR$ 0` to `CHR$ 3` to set the invisible (bit 0) and
protected (bit 1) flags; that character is not part of the name. Names may be
10 characters on tape, 14 elsewhere.

```basic
SAVE "myprog" LINE 10
SAVE "font" CODE 32768, 768
SAVE CHR$ 3 + "secret" CODE 32768, 1024, 32768
```

### `SCREEN`

```
SCREEN n
```

Makes screen *n* the one that `PRINT`, `PLOT` and everything else draws on.
Each screen carries its own mode, windows, colours, cursor position and
palette, so nothing needs re-establishing after the switch.

Unless `DISPLAY` has fixed the display elsewhere, the display follows.

Error 43, *Invalid screen number*, if that screen is not open.

### `SCREEN$`

```
SCREEN$(row, column)
```

The character at that cell, or `""` if the pixels match none. It works
backwards — reading the cell, reducing it to one bit per pixel, and searching
the character set — so it will not recognise a cell that has been drawn over.

### `SCROLL`

```
SCROLL direction [, pixels [, x, y, width, length]]
SCROLL CLEAR
SCROLL RESTORE
```

As `ROLL`, but data that falls off the edge is **discarded** and the vacated
area is filled with paper.

`SCROLL CLEAR` and `SCROLL RESTORE` are unrelated to scrolling the display:
they suppress and restore the `scroll?` prompt.

### `SGN`

```
SGN n
```

−1 if *n* is negative, 0 if zero, 1 if positive.

### `SIN`

```
SIN n
```

Sine of *n* radians.

### `SOUND`

```
SOUND register, value [; register, value …]
```

Writes the SAA1099 sound chip's registers. Registers are 0 to 31; up to 127
pairs may be given, and they are all written together after the whole list
has been evaluated.

Unlike `BEEP`, `SOUND` returns immediately — the chip keeps playing while the
program continues.

| Error | Cause |
|---|---|
| 30 | Register outside 0–31 |
| 33 | More than 127 pairs |

```basic
SOUND 28,2; 28,1; 16,4; 8,128; 20,1; 0,&FF
```

See [chapter 10](10-sound.md#102-sound--the-sound-chip) for the register map.

### `SQR`

```
SQR n
```

Square root. A negative argument gives error 27, *Invalid argument*.

### `STEP`

```
FOR v = a TO b STEP s
RENUM … STEP m
```

A qualifier, not a command.

### `STOP`

```
STOP
```

Halts with report 16, *STOP statement*. `CONTINUE` resumes at the next
statement.

### `STR$`

```
STR$ n
```

*n* as the text `PRINT` would produce: up to nine significant digits,
trailing zeros dropped, `E` notation where appropriate.

### `STRING$`

```
STRING$(n, a$)
```

*a$* repeated *n* times. The result is limited to 511 characters.

```basic
PRINT STRING$(30, "-")
PRINT STRING$(3, "ab")          : REM ababab
```

### `SVAR`

```
SVAR n
```

The **address** of system variable *n* — 23040 + *n*. It does not read the
variable, so you normally write `PEEK SVAR n` or `POKE SVAR n, v`.

See [chapter 14](14-system-variables.md).

```basic
POKE SVAR &2F, 1                : REM eight-column comma tabs
```

---

## T

### `TAB`

```
TAB column
```

A print item. Moves to that column, wrapping to the next line if the position
is already past it.

Equivalent to `CHR$ 23 + CHR$ column + CHR$ 0`.

### `TAN`

```
TAN n
```

Tangent of *n* radians.

### `THEN`

```
IF condition THEN statements
```

A qualifier. Its presence is what makes an `IF` the single-line form.
Internally it also acts as a statement separator, so statement numbering
counts `THEN` as well as `:`.

### `TO`

```
a$(m TO n)          FOR v = a TO b          LIST a TO b
DELETE a TO b       RENUM a TO b            MEM$(a TO b)
OPEN TO n
```

A qualifier used by slicing, ranges and `OPEN`.

### `TRUNC$`

```
TRUNC$ a$
```

*a$* with trailing spaces removed. Useful with string arrays, whose fixed
width means every slot is space-padded.

```basic
DIM n$(10,12)
LET n$(1) = "Alice"
PRINT "["; TRUNC$ n$(1); "]"        : REM [Alice]
```

---

## U

### `UDG`

```
UDG a$
```

The address of the 8-byte bitmap for the single character *a$*. Three ranges,
three base pointers:

| Codes | Base |
|---|---|
| 32–127 | `CHARS` (23606) |
| 128–168 | `UDG` (23675) |
| 169–255 | `HUDG` (23677) |

Error 27, *Invalid argument*, unless the string is exactly one character of
code 32 or more.

> `HUDG` is zero on a freshly booted machine and the ROM never sets it, so
> codes 169 and above have no font until you provide one. See
> [hudg.md](../hudg.md).

```basic
FOR i = 0 TO 7: READ b: POKE UDG "A"+i, b: NEXT i
```

### `UNTIL`

```
DO UNTIL condition
LOOP UNTIL condition
```

A qualifier on `DO` and `LOOP`.

### `USING`

```
FILL USING pattern$, x, y
```

A qualifier, used only by `FILL`. (There is no `PRINT USING` in SAM BASIC.)

### `USR`

```
USR address
```

Calls machine code and returns whatever the routine leaves in the **BC**
register pair as the function's value.

BC arrives holding the entry address, so a routine that returns nothing
meaningful still returns something — load BC deliberately.

```basic
PRINT USR 32768
```

### `USR$`

```
USR$ address
```

Calls machine code and takes A = page, DE = start, BC = length on return as a
string descriptor. The text must be somewhere stable — the workspace obtained
from the `WKROOM` jump-table entry is the intended place.

---

## V

### `VAL`

```
VAL a$
```

Evaluates *a$* as a numeric expression. It runs the full pipeline — tokenise,
syntax check, evaluate — so it accepts anything you could type, including
variables and spelled-out keywords.

Powerful and slow. Keep it out of loops.

```basic
LET a = 3
PRINT VAL "a*2 + SIN 0"         : REM 6
```

### `VAL$`

```
VAL$ a$
```

As `VAL`, but the expression must yield a string.

```basic
PRINT VAL$ """hello"""          : REM hello
```

### `VERIFY`

```
VERIFY "name" [type-clause]
```

Compares a file against memory without loading it. Accepts the same clauses
as `LOAD`, except that `VERIFY "name" LINE n` is not allowed, and `VERIFY` of
a non-existent array is an error.

---

## W

### `WHILE`

```
DO WHILE condition
LOOP WHILE condition
```

A qualifier on `DO` and `LOOP`.

### `WINDOW`

```
WINDOW left, right, top, bottom
WINDOW
```

Restricts printing, scrolling and `CLS 1` to a rectangle of character cells.
A bare `WINDOW` restores the whole upper screen. The print position moves to
the new top-left corner.

The values are validated against the mode's limits; an impossible window
gives error 54, *Invalid WINDOW*.

```basic
WINDOW 4, 27, 2, 16
PAPER 1: CLS 1
```

### `WRITE` — **`[SD2]`** **`[MD]`**

Tokenised by the ROM as a qualifier but never used by it. Both DOSes claim it
as a command, for writing to a record file.

---

## X

### `XMOUSE`

```
XMOUSE
```

The mouse's X coordinate. Requires a driver installed in the `MOUSV` vector
(23292); without one it reads whatever is in the mouse coordinate variables.

### `XPEN`

```
XPEN
```

The light pen's X position, read from the palette port.

---

## Y

### `YMOUSE`

```
YMOUSE
```

The mouse's Y coordinate. See `XMOUSE`.

### `YPEN`

```
YPEN
```

The light pen's Y position.

---

## Z

### `ZAP`

```
ZAP
```

A canned sound effect: six short bursts at a fixed period. Takes no
parameters.

### `ZOOM`

```
ZOOM
```

A canned sound effect: a downward sweep. Takes no parameters.

---

## Operators, for completeness

Operators are not keywords in the alphabetical sense, but here they are in
priority order. The full discussion is in
[chapter 4](04-expressions-and-operators.md).

| Priority | Operators |
|---|---|
| 15 | All functions, `^` |
| 14 | `MOD`, `DIV` |
| 9 | unary `−` |
| 8 | `*`, `/` |
| 6 | `+`, `−` |
| 5 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 4 | `NOT` |
| 3 | `AND`, `BAND` |
| 2 | `OR`, `BOR` |

---

## Keywords added by the extensions

None of these exist in ROM 3.0. They are listed here so that a keyword met in
someone else's program can be identified; the syntax is from the products'
own documentation and has not been verified against them.
[dos-and-extensions.md](../dos-and-extensions.md) has the detail, including
token values and how each product attaches itself to the ROM.

| Tag | Needs |
|---|---|
| **`[DOS]`** | Any disk operating system |
| **`[SD2]`** | SAMDOS 2 |
| **`[MD]`** | MasterDOS |
| **`[MB]`** | MasterBASIC |

### Commands

| Keyword | | Purpose |
|---|---|---|
| `ALTER` *(ref)* `TO` *(ref)* | **`[MB]`** | Search and replace through the program |
| `ALTER DEVICE` *drive* `TO` *drive* | **`[MB]`** **`[MD]`** | Reassign a drive |
| `ALTER DISPLAY` *n* `TO` *n* `LINE` *n* | **`[MB]`** | Split-mode display |
| `BACKUP` | **`[MD]`** | Copy a whole disk |
| `BLITZ SOUND` *a$* | **`[MB]`** | Replay recorded sound |
| `BLOCKS 2` | **`[MB]`** | A third block-graphics mode, giving extra UDGs |
| `CLS *` | **`[MB]`** | Clear to black on white |
| `COPY SCREEN` *n* `TO` *n* | **`[MB]`** | Copy between screens |
| `DATE` | **`[MD]`** | Set the date |
| `DIR` | **`[DOS]`** | Directory listing |
| `EDIT` *variable* | **`[MB]`** | Edit a variable's value |
| `ERASE` | **`[DOS]`** | Delete a file |
| `FORMAT` | **`[DOS]`** | Format a disk |
| `HIDE` | **`[DOS]`** | Make a file invisible |
| `JOIN` | **`[MB]`** | Join two program lines |
| `JOIN TO` *a$*`,`*b$* | **`[MB]`** | Append one string or string array to another |
| `MERGE *` | **`[MB]`** | Faster `MERGE` |
| `MOVE` | **`[MD]`** | Move a file |
| `PROTECT` | **`[DOS]`** | Protect a file |
| `READ` *(record files)* | **`[SD2]`** **`[MD]`** | Read a record file |
| `RECORD SOUND TO` *a$* | **`[MB]`** | Record sound-chip output into a string |
| `RECORD SOUND OFF` / `STOP` | **`[MB]`** | End a sound recording |
| `RENAME` | **`[DOS]`** | Rename a file |
| `SAVE MODE` *n* | **`[MB]`** | Save with compression, 1 to 3 |
| `SORT` *a$* | **`[MB]`** | Sort a string or string array; also `SORT ABS` and `SORT ABS INVERSE` |
| `SOUND CLEAR` *[size]* | **`[MB]`** | Allocate or free the sound buffer |
| `TIME` | **`[MD]`** | Set the time; `TIME +` and `TIME -` adjust it |
| `WRITE` | **`[SD2]`** **`[MD]`** | Write a record file |
| `EXIT PROC` / `EXIT DO` / `EXIT FOR` | **`[MB]`** | Leave a procedure or loop early |

### Functions

| Keyword | | Result |
|---|---|---|
| `DATE$` | **`[MD]`** | The date as text |
| `DIR$` | **`[MD]`** | Directory entry as text |
| `DSTAT` | **`[MD]`** | Disk status |
| `EQU(`*a$*`,`*b$*`)` | **`[MB]`** | Case-insensitive string comparison |
| `FPAGES` | **`[MD]`** | Free pages |
| `FSTAT` | **`[MD]`** | File status |
| `INARRAY(`*a$(n)*`,`*target$*`)` | **`[MB]`** | Search a string array |
| `INP$` | **`[MD]`** | Serial input |
| `LOCN(`*start*`,`*length*`,`*a$*`)` | **`[MB]`** | Search memory for a string; `,ABS` for a case-insensitive search |
| `NVAL` *a$* | **`[MB]`** | Convert a compact `SVAL$` string back to a number |
| `RESERVED(`*space*`)` | **`[MB]`** | Reserve heap space; a negative value releases it |
| `SCRAD` | **`[MB]`** | Screen address |
| `SHIFT$(`*a$*`,`*n*`)` | **`[MB]`** | Change the capitalisation of a string |
| `SVAL$(`*number*`,`*characters*`)` | **`[MB]`** | Convert a number to a compact 2–5 character string |
| `TICS` | **`[MB]`** **`[MD]`** | Elapsed time — needs a clock |
| `TIME$` | **`[MD]`** | The time as text |
| `USING$(`*format$*`,`*number*`)` | **`[MB]`** | Format a number to a fixed layout |
| `XVAR` *n* | **`[MB]`** | Address of MasterBASIC system variable *n* |

`DVAR` *n* is in the ROM's keyword table but only works with a DOS; it
returns the address of DOS variable *n*, so it is used like `SVAR`.

---

[Contents](README.md) · [A–L](appendix-a-keywords-a-l.md) · **M–Z**
