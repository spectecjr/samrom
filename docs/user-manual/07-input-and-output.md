# 7. Input and Output

← [Procedures and functions](06-procedures-and-functions.md) · [Contents](README.md) · [Next: The screen and colour →](08-the-screen-and-colour.md)

---

## 7.1 `PRINT`

```
PRINT [#stream] [item] [separator [item] …]
```

An item is any expression, a positioning keyword, a colour item, or a
parenthesised group. Separators both delimit the items and do something:

| Separator | Effect |
|---|---|
| `;` | Nothing — the next item follows immediately |
| `,` | Move to the next column stop |
| `'` | Start a new line |

A **trailing separator suppresses the final newline**, which is how you build
a line from several `PRINT` statements:

```basic
10 PRINT "Loading";
20 FOR i = 1 TO 3: PRINT ".";: PAUSE 25: NEXT i
30 PRINT " done"
```

The column stops for `,` are 16 columns apart by default. The system variable
`TABVAR` (offset &2F) selects: 0 gives 16 columns, non-zero gives 8.

```basic
POKE SVAR &2F, 1        : REM eight-column tabs
```

### Positioning items

| Item | Effect |
|---|---|
| `AT row, column` | Move the print position |
| `TAB column` | Move to that column, wrapping to the next line if needed |

```basic
PRINT AT 10,5; "centred-ish"
PRINT "Name"; TAB 20; "Score"
```

Both are relative to the current window (§8.4), not to the whole screen.

### Colour items

Any of `PEN`/`INK`, `PAPER`, `FLASH`, `BRIGHT`, `INVERSE` and `OVER` may
appear as an item, and then applies **only to that statement**:

```basic
PRINT PEN 2; "red"; PEN 4; "green"
PRINT PAPER 1; INK 7; "white on blue"
```

That is because SAM keeps two sets of colour variables: the *permanent* set
that the colour commands change, and a *temporary* set refreshed from it at
the start of every print or plot. An inline item alters only the temporary
copy. Chapter 8 has the detail.

### Nested print items

Brackets group a sub-print, which is mostly useful inside `INPUT`:

```basic
INPUT "old: "; (x); " new: "; x
```

### Printing to a stream

`PRINT #s;` selects stream *s* for the rest of the statement:

```basic
PRINT #3; "to the printer"
PRINT #0; "to the lower screen"
```

The `#` may also appear part-way through a statement to redirect mid-flow.

## 7.2 Control codes

Codes below 32 embedded in printed output are commands rather than
characters. `CHR$` lets you emit them from anywhere:

| Code | Meaning | Operands |
|---|---|---|
| 6 | Column tab (what `,` does) | — |
| 7 | EDIT | — |
| 8 | Cursor left | — |
| 9 | Cursor right | — |
| 10 | Cursor down | — |
| 11 | Cursor up | — |
| 12 | Delete left | — |
| 13 | Carriage return | — |
| 14 | Delete right | — |
| 15 | Keypad toggle | — |
| 16 | `INK` | 1 |
| 17 | `PAPER` | 1 |
| 18 | `FLASH` | 1 |
| 19 | `BRIGHT` | 1 |
| 20 | `INVERSE` | 1 |
| 21 | `OVER` | 1 |
| 22 | `AT` | 2 (row, column) |
| 23 | `TAB` | 2 (column, ignored) |

```basic
PRINT CHR$ 22 + CHR$ 10 + CHR$ 5 + "at 10,5"
PRINT CHR$ 16 + CHR$ 2 + "red"
```

Storing these in a string is the fastest way to replay a formatted screen.

## 7.3 `INPUT`

```
INPUT [items and variables …]
```

`INPUT` accepts the *same* item list as `PRINT` — separators, `AT`, `TAB`,
colour items and parenthesised groups — mixed freely with the variables being
read:

```basic
10 INPUT "Name? "; n$
20 INPUT AT 0,0; PAPER 1; "Age? "; age
30 INPUT "x, y: "; x, y
```

Reading a value runs the full line editor over a workspace buffer, so every
editing key works while the user types. For a string variable the buffer is
primed with a pair of quotes and the cursor placed between them; for a
numeric variable the buffer starts empty and the result is syntax-checked as
an expression — so a user may type `2*3` and get 6.

A typing mistake restarts the edit rather than aborting the program, but only
when reading from the keyboard: a stream attached to a file has no way to
retry.

Pressing BREAK during `INPUT` gives report 17, *STOP in INPUT*.

### `INPUT LINE`

```
INPUT LINE string-variable
```

Takes the raw characters typed, with no quotes and no expression checking.
Use it whenever you want exactly what the user typed:

```basic
10 INPUT LINE "Comment: "; c$
```

The lower screen grows upward as an `INPUT` prompt gets longer, so long
prompts are fine.

## 7.4 `GET` — one keypress

```
GET variable
```

Waits for a single key and assigns it:

* A **string** variable receives the character.
* A **numeric** variable receives its value as a hexadecimal digit — `"0"` to
  `"9"` give 0 to 9, `"A"` to `"F"` give 10 to 15.

```basic
10 PRINT "Press a key..."
20 GET k$
30 PRINT "You pressed "; k$; " (code "; CODE k$; ")"
```

`GET` waits, and BREAK still works while it does. If you do not want to wait,
use `INKEY$`, which returns `""` when no key is down.

`INKEY$` performs a fresh keyboard scan rather than reading the buffered
last-key value, so a key released before the call is *not* reported. That
makes it correct for "is this key held down now?" tests:

```basic
10 DO
20   LET k$ = INKEY$
30   IF k$ = "z" THEN left
40   IF k$ = "x" THEN right
50 LOOP
```

## 7.5 Streams and channels

A **channel** is a device. A **stream** is a small number you quote as `#n`
that is attached to a channel.

### The built-in channels

| Letter | Device |
|---|---|
| `K` | Keyboard, with output going to the lower screen |
| `S` | Screen (upper) |
| `R` | The edit line — printing to it inserts text at the cursor |
| `P` | Printer |
| `$` | Append to a string variable (see `RECORD`) |
| `B` | Raw byte output to the printer port |

### The default streams

| Stream | Channel |
|---|---|
| −5 | B |
| −4 | $ |
| −3 | K |
| −2 | S |
| −1 | R |
| 0 | K |
| 1 | K |
| 2 | S |
| 3 | P |
| 4–15 | closed |
| 16 | $ (see `RECORD`) |

Streams −5 to −1 are fixed system streams. `PRINT` defaults to stream 2 and
`LPRINT` to stream 3.

### Attaching and detaching

```
OPEN  #stream, channel$
CLOSE #stream
```

```basic
OPEN #4, "s"           : REM stream 4 to the screen
PRINT #4; "hello"
CLOSE #4
```

The channel name must be a single character — `k`, `s`, `p`, `$` or `b`, in
either case. Anything else, or a longer name, is passed to DOS, which is how
a disk system installs channels of its own:

```basic
OPEN #4, "myfile"      : REM handled by DOS
```

Closing streams 0 to 3 restores their default channels rather than leaving
them unattached; 4 to 15 simply become closed. Reading or printing to a
closed stream gives error 47, *Stream is not open*; opening one that is
already attached to a non-reassignable channel gives error 45.

## 7.6 Output into a string — stream 16 and `RECORD`

Stream 16 appends everything printed to it onto a named string variable.

```
RECORD TO string-variable
RECORD STOP
```

```basic
10 DIM a$(0)
20 LET a$ = ""
30 RECORD TO a$
40 PRINT #16; "TESTING"
50 RECORD STOP
60 PRINT LEN a$          : REM 8 -- "TESTING" plus a carriage return
```

This gives you, essentially for free:

* **Serial files** — accumulate output and save the string.
* **Token expansion into a string** — `LIST #16` captures a listing.
* **A directory into a string** — `DIR #16` if DOS is present.
* **Graphics recording** — while `RECORD` is active, graphics commands append
  `BLITZ` records to the string as well as drawing. See chapter 9.

`OPEN #16` and `CLOSE #16` are not permitted; `RECORD` is how you arm it.

## 7.7 The printer

| Statement | Effect |
|---|---|
| `LPRINT …` | As `PRINT`, but to stream 3 |
| `LLIST …` | As `LIST`, but to stream 3 |
| `DUMP` | Text screen dump |
| `DUMP CHR$` | Graphics screen dump |

There is **no printer driver in the ROM**. `DUMP` calls through the `DMPV`
vector, and if nothing is installed there it does nothing at all. The `P`
channel sends characters to the printer port; the `B` channel sends raw
bytes.

Printer behaviour is controlled by these system variables:

| Variable | Offset | Default | Meaning |
|---|---|---|---|
| `PRRHS` | &0E | 79 | Right margin — the column at which a line wraps |
| `AFTERCR` | &0F | — | Byte sent after a carriage return: 10 for auto line feed, 0 for none |
| `LPTPRT1` | &10 | — | Printer control port, then the strobe value (2 bytes) |
| `DMPV` | &DA | 0 | The dump/copy vector (2 bytes) |

```basic
POKE SVAR &0E, 132       : REM 132-column printer
POKE SVAR &0F, 0         : REM printer supplies its own line feed
```

Offsets &12 to &2E of the system variable block are reserved for a dump
driver's own use.

## 7.8 The scroll prompt

When output fills the window, the ROM prints `scroll?` and waits. `SCRCT`
(23692) counts the lines that may still scroll before the prompt appears;
setting it to a large value postpones the prompt:

```basic
POKE 23692, 255
```

or turn it off entirely with `SCROLL CLEAR`, and back on with
`SCROLL RESTORE`.

## 7.9 A formatted-output example

```basic
  10 MODE 4: CLS
  20 DIM item$(5,12)
  30 FOR i = 1 TO 5: READ item$(i): NEXT i
  40 DATA "Sword","Shield","Potion","Rope","Lamp"
  50 DIM cost(5)
  60 FOR i = 1 TO 5: READ cost(i): NEXT i
  70 DATA 120, 80, 25, 10, 45
  80
  90 PRINT PEN 6; "Item"; TAB 16; "Cost"
 100 PRINT PEN 6; STRING$(24, "-")
 110 FOR i = 1 TO 5
 120   PRINT item$(i); TAB 16; cost(i)
 130 NEXT i
 140 PRINT
 150 LET total = 0
 160 FOR i = 1 TO 5: LET total = total + cost(i): NEXT i
 170 PRINT INVERSE 1; "Total"; TAB 16; total
```

---

## Summary

* `PRINT` items are separated by `;` (nothing), `,` (column tab) or `'`
  (newline); a trailing separator suppresses the final newline.
* `AT r,c` and `TAB c` position; colour items apply for one statement only.
* `INPUT` takes the same item list as `PRINT`, runs the full editor, and
  syntax-checks numeric answers as expressions. `INPUT LINE` takes raw text.
* `GET` waits for one key; `INKEY$` does not.
* Channels are `K S R P $ B`; streams 0–3 default to K K S P; `OPEN #n,"x"`
  attaches, `CLOSE #n` detaches.
* Stream 16 plus `RECORD TO a$` turns printed output into a string.
* `DUMP` needs a printer driver in the `DMPV` vector; the ROM has none.

---

← [Procedures and functions](06-procedures-and-functions.md) · [Contents](README.md) · [Next: The screen and colour →](08-the-screen-and-colour.md)
