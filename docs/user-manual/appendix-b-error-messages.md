# Appendix B — Error Messages and Reports

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · **Appendix B** · [Appendix C](appendix-c-character-codes.md) · [Appendix D](appendix-d-tokens-and-priorities.md)

---

A report is printed as

```
number message, line:statement
```

with line 0 for a direct command. Error 2 prints the offending variable name
before the message.

Codes 0 and 14 to 17 are **not faults** — they report a normal end or a
deliberate stop. Codes 81 (&51) and above are DOS errors, whose text comes
from the DOS rather than the ROM.

Inside an `ON ERROR` handler, the code is available as the variable `error`,
the line as `lino` and the statement as `stat`.

---

## 0–13 — Program structure

| # | Message | Cause and cure |
|---|---|---|
| 0 | `OK` | The program ran off the end. Not an error |
| 1 | `Out of memory` | The heap and the BASIC stack met, or there is no free page for a screen or an `OPEN`. Try `CLEAR` to defragment, shorten strings, or free pages |
| 2 | `<name> not found` | An undefined variable. Usually a typo — remember that spaces inside a name are ignored but underscores are not |
| 3 | `DATA has all been read` | `READ` ran past the last `DATA` item. Use `RESTORE`, or guard with `ITEM` |
| 4 | `Subscript wrong` | An array index or string slice outside its range. Subscripts start at **1**, not 0 |
| 5 | `NEXT without FOR` | The `NEXT` variable is not currently a `FOR` control variable — often because the `FOR` was jumped over |
| 6 | `FOR without NEXT` | A `FOR` whose loop cannot run has no matching `NEXT` to skip to |
| 7 | `FN without DEF FN` | No `DEF FN` of that name. Check spelling and that the definition is in the program |
| 8 | `RETURN without GOSUB` | No `GOSUB` frame on the stack. Often caused by falling into a subroutine |
| 9 | `Missing LOOP` | A `DO` with no matching `LOOP` |
| 10 | `LOOP without DO` | A `LOOP` with no `DO` frame — often caused by jumping into the middle of a loop |
| 11 | `No POP data` | `POP` with an empty BASIC stack |
| 12 | `Missing DEF PROC` | No procedure of that name. **The usual cause is a missing `LET`** — `x = 1` is read as a call to procedure `x` |
| 13 | `No END PROC` | A `DEF PROC` with no `END PROC` |

## 14–17 — Stops, not errors

| # | Message | Meaning |
|---|---|---|
| 14 | `BREAK - CONTINUE to repeat` | BREAK during input or output. `CONTINUE` re-runs the same statement |
| 15 | `BREAK into program` | BREAK between statements. `CONTINUE` resumes at the next one |
| 16 | `STOP statement` | A `STOP` was executed |
| 17 | `STOP in INPUT` | BREAK was pressed during `INPUT` |

## 18–22 — Files and devices

| # | Message | Cause and cure |
|---|---|---|
| 18 | `Invalid file name` | Empty name on `SAVE`, or a name longer than the device allows (10 characters on tape, 14 elsewhere) |
| 19 | `Loading error` | A tape or network block failed its parity or timing check. Adjust the volume, or the tape speed with `DEVICE T`*n* |
| 20 | `Invalid device` | A channel with no input side was read, or an unknown device letter |
| 21 | `Invalid stream number` | A stream outside 0 to 16 |
| 22 | `End of file` | Reading past the end of a file |

## 23–25 — Colour

| # | Message | Cause and cure |
|---|---|---|
| 23 | `Invalid colour` | `PEN`/`PAPER` above 17, `BRIGHT`/`FLASH` other than 0, 1, 8 or 16, `INVERSE` other than 0 or 1, `OVER` above 3 |
| 24 | `Invalid palette colour` | A palette entry outside 0–15 or a colour outside 0–127 |
| 25 | `Too many palette changes` | More than 127 `PALETTE … LINE` entries on one screen. A bare `PALETTE` clears the list |

## 26–31 — Arguments and syntax

| # | Message | Cause and cure |
|---|---|---|
| 26 | `Parameter error` | A procedure call whose argument count or types do not match the definition |
| 27 | `Invalid argument` | A mathematically impossible argument: `SQR` of a negative, `LN` of zero or less, `ASN`/`ACS` outside −1 to 1, `UDG` of anything but a single character |
| 28 | `Number too large` | Floating-point overflow, or a literal outside the machine's range (about ±1.7 × 10³⁸) |
| 29 | `Not understood` | The general syntax error: a type mismatch, a malformed statement, or a DOS command with no DOS present |
| 30 | `Integer out of range` | A value that had to be a whole number in 0–65535 was not — common with `BAND`/`BOR`, `POKE`, `CHR$`, `CSIZE`, `SOUND` registers and `LIST FORMAT` |
| 31 | `Statement doesn't exist` | A jump to a statement number that is not there, usually after the target line was edited |

## 32–39 — Screen and graphics

| # | Message | Cause and cure |
|---|---|---|
| 32 | `Off screen` | A plot, draw or `ATTR` outside the display. Check `xos`/`yos`/`xrg`/`yrg` as well as the coordinates |
| 33 | `No room for line` | A program line longer than the maximum, or more than 127 `SOUND` pairs |
| 34 | `Invalid screen mode` | `MODE` outside 1–4, or an operation the current mode does not support — `ATTR` in modes 3 and 4, `GRAB`/`PUT`/`ROLL`/`SCROLL`/`FILL` in modes 1 and 2 |
| 35 | `Invalid BLITZ code` | An unrecognised command byte in a `BLITZ` string |
| 36 | `Stored area too big` | A `GRAB`, `ROLL` or `SCROLL` rectangle larger than the 8K staging buffer |
| 37 | `Invalid PUT block` | The string given to `PUT` does not begin with a valid three-byte block header |
| 38 | `PUT mask mismatch` | The mask string is a different size from the block |
| 39 | `Missing END IF` | A block `IF` with no `END IF` |

## 40–48 — Variables, memory and screens

| # | Message | Cause and cure |
|---|---|---|
| 40 | `Invalid variable name` | A string or array name longer than 10 characters |
| 41 | `BASIC stack full` | Too many nested `DO`/`GOSUB`/`PROC` frames. Usually runaway recursion, or leaving loops with `GOTO` instead of `EXIT IF` — `POP` the frame if you must jump out |
| 42 | `String too long` | A string operation exceeded its limit (511 characters for `STRING$`, 255 for a literal containing doubled quotes) |
| 43 | `Invalid screen number` | `SCREEN`, `DISPLAY` or `CLOSE SCREEN` naming a screen that is not open, or outside 1–16 |
| 44 | `Screen is already open` | `OPEN SCREEN` on a screen that already exists |
| 45 | `Stream is already open` | `OPEN #` on a stream attached to a channel that cannot be reassigned |
| 46 | `Current screen` | `CLOSE SCREEN` on the screen being drawn on. `SCREEN` somewhere else first |
| 47 | `Stream is not open` | Reading from or writing to a closed stream |
| 48 | `Invalid CLEAR address` | A `CLEAR` address that would leave no usable memory |

## 49–55 — Sound, calculator and DOS

| # | Message | Cause and cure |
|---|---|---|
| 49 | `Invalid Note` | A `BEEP` pitch whose frequency falls outside about 8 Hz to 16 kHz |
| 50 | `Note too long` | A `BEEP` duration over 16 seconds |
| 51 | `FPC error` | The floating-point calculator met an opcode it does not recognise. In normal use this means corrupted memory |
| 52 | `Too many definitions` | The `DEF KEYCODE` buffer is full. Its limit is in `DKLIM` (23504) |
| 53 | `No DOS` | A DOS command, DOS function or DOS device was used with no disk operating system loaded. Try `BOOT` |
| 54 | `Invalid WINDOW` | Window edges outside the mode's limits, or inverted |
| 55 | `Missing disk` | `BOOT` found no bootable disk |

## 80 and above

| # | Meaning |
|---|---|
| 80 (&50) | Not an error — the copyright banner, printed at switch-on and by `NEW` |
| 81 (&51) and up | DOS errors. The message text comes from the DOS's own table |

---

## How errors are raised and handled

Every error is raised by a restart carrying the code. The handler:

1. Records where it happened, so the flashing `?` can be positioned.
2. Offers the code to the `RST8V` vector (23278), so a utility can intercept
   it.
3. If a DOS is resident, passes it there; codes 128 and above are **DOS hook
   codes** rather than errors, and are how BASIC asks the DOS to open a file
   or read a directory. Without a DOS they become error 53.
4. Otherwise stores the code and resets the stack pointer from `ERRSP`,
   abandoning whatever was in progress.

That last step is why an error never leaves the interpreter half-finished —
and why machine code that calls a ROM routine cannot catch an error raised
inside it.

---

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · **Appendix B** · [Appendix C](appendix-c-character-codes.md) · [Appendix D](appendix-d-tokens-and-priorities.md)
