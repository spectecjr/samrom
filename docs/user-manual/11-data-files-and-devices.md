# 11. Data, Files and Devices

← [Sound](10-sound.md) · [Contents](README.md) · [Next: Errors and debugging →](12-errors-and-debugging.md)

---

## 11.1 `DATA`, `READ` and `RESTORE`

```
DATA item [, item …]
READ variable [, variable …]
READ LINE string-variable
RESTORE [line]
```

`DATA` statements hold constants; `READ` takes the next one and assigns it.

```basic
 10 FOR i = 1 TO 4: READ n$, age: PRINT n$; " is "; age: NEXT i
 20 DATA "Alice", 30, "Bob", 25
 30 DATA "Carol", 41, "Dave", 19
```

`DATA` does nothing at run time; falling into one is harmless. Its items are
validated when you *enter* the line, so a syntax error in `DATA` is reported
immediately rather than when it is eventually read.

A `DATA` item may be any constant expression, because plain `READ` evaluates
it as a full expression:

```basic
10 READ x: PRINT x
20 DATA 2*PI
```

`RESTORE` moves the read pointer. `RESTORE` with no argument, or `RESTORE 0`,
goes back to the start of the program; `RESTORE 100` starts reading from line
100. Running off the end of the data gives error 3, *DATA has all been read*.

### `READ LINE`

```
READ LINE string-variable
```

Takes the raw characters up to the next comma, colon or end of line, without
evaluating them. Use it for text you do not want to quote:

```basic
10 READ LINE a$: PRINT a$
20 DATA this is plain text, no quotes needed
```

### `ITEM` — what is left

`ITEM` reports on the *current* `DATA` statement:

| Result | Meaning |
|---|---|
| 0 | Nothing left in this statement |
| 1 | The next item is a string |
| 2 | The next item is a number |

```basic
10 DO WHILE ITEM
20   IF ITEM = 1 THEN READ a$: PRINT "str: "; a$
30   IF ITEM = 2 THEN READ n:  PRINT "num: "; n
40 LOOP
50 DATA "one", 1, "two", 2
```

`ITEM` is what makes `DEF PROC name DATA` (chapter 6) genuinely useful: a
procedure can adapt to however many arguments it was given, of whatever types.

## 11.2 Choosing a device — `DEVICE`

```
DEVICE letter [number]
```

| Form | Meaning |
|---|---|
| `DEVICE T` | Tape at the standard speed |
| `DEVICE T45` | Tape at speed 45 |
| `DEVICE N` | Network, station 0 |
| `DEVICE N5` | Network, station 5 |
| `DEVICE M` | Disk drive 1 |
| `DEVICE M2` | Disk drive 2 |
| `DEVICE D` … | Any other letter is a DOS device |

The trailing colon you often see written — `DEVICE M:` — is just the
statement separator; it is harmless and reads well.

The letter and number are stored in `PSLD` (system variable offsets &06 and
&07) and copied to a working pair for the duration of each file command.

Devices `T` (tape) and `N` (network with no DOS) are handled by the ROM
itself. Everything else is passed to the resident DOS through its hooks, and
gives error 53, *No DOS*, if there is none.

The machine starts up with `DEVICE T`.

## 11.3 `SAVE`

```
SAVE [OVER] "name"
SAVE [OVER] "name" LINE n
SAVE [OVER] "name" CODE start, length [, execute]
SAVE [OVER] "name" SCREEN$
SAVE [OVER] "name" DATA array()
```

| Form | What is saved | Type |
|---|---|---|
| Plain | Program plus all variables | 16 |
| `LINE n` | The same, with auto-run at line *n* | 16 |
| `CODE` | A block of memory | 19 |
| `SCREEN$` | The current screen, its palette and its line-interrupt list | 20 |
| `DATA a()` | One numeric array | 17 |
| `DATA a$()` | One string array | 18 |

```basic
SAVE "myprog"
SAVE "myprog" LINE 10
SAVE "font" CODE 32768, 768
SAVE "picture" SCREEN$
SAVE "scores" DATA score()
```

`OVER` permits an existing file of the same name to be replaced; without it,
a DOS will normally refuse.

`SAVE "name" CODE` needs at least a start and a length. A third number is an
execution address, which makes the file auto-run when loaded.

A `SCREEN$` file includes the 40-byte palette table and the line-interrupt
colour list after the picture data, so colours and mid-frame palette changes
are restored with it.

### Invisible and protected files

A `SAVE` name may begin with a control character 0 to 3 carrying two flags:

| First character | Invisible | Protected |
|---|---|---|
| `CHR$ 0` | no | no |
| `CHR$ 1` | yes | no |
| `CHR$ 2` | no | yes |
| `CHR$ 3` | yes | yes |

```basic
SAVE CHR$ 3 + "secret" CODE 32768, 1024, 32768
```

*Invisible* means the name is not printed while a tape is being searched;
*protected* means an auto-run code file cannot be stopped. The character is
not part of the name.

File names are up to 10 characters on tape, and up to 14 on other devices.

## 11.4 `LOAD`, `VERIFY` and `MERGE`

```
LOAD   "name" [type-clause]
VERIFY "name" [type-clause]
MERGE  "name"
```

The type clauses are the same as for `SAVE`, with three differences:

* `VERIFY "name" LINE n` is not allowed.
* `MERGE "name" DATA …` is not allowed.
* `LOAD "name" CODE` may give no addresses at all, in which case the block
  goes back to where it was saved from. `LOAD "name" CODE start` relocates it.

```basic
LOAD ""                     : REM the next program on tape
LOAD "myprog"
LOAD "font" CODE
LOAD "font" CODE 49152      : REM somewhere else
LOAD "picture" SCREEN$
LOAD "scores" DATA score()
```

An empty name loads the next file of the right type, whatever it is called.

`LOAD` of a program clears the variables and does a `RESTORE`; if the file was
saved with `LINE n`, it runs.

`LOAD "name" DATA a()` will create the array if it does not exist. `SAVE` and
`VERIFY` of a non-existent array are errors.

`MERGE` loads a program and splices it into the current one: lines replace
lines of the same number, numeric variables are re-created one at a time, and
strings and arrays replace any of the same name. Everything else is left
alone. It is the way to combine a library of procedures with a main program.

### Prompts

Tape operations print `Start tape and then press a key` and the names of the
files they pass. Both can be suppressed through the `TPROMPTS` system
variable (offset &33):

| Bit | Effect |
|---|---|
| 0 | Suppress file names during `LOAD` |
| 1 | Suppress prompts during `SAVE` |

```basic
POKE SVAR &33, 3            : REM silence both
```

## 11.5 The file header

Every file carries an 80-byte header. The parts you may want to read or write
are:

| Offset | Contents |
|---|---|
| 0 | Type: 16 BASIC, 17 numeric array, 18 string array, 19 code, 20 `SCREEN$` |
| 1–10 | Name, space padded |
| 11–14 | Extra name characters for non-tape devices |
| 15 | Flags: bit 0 invisible, bit 1 protected |
| 16 | `SCREEN$` mode, or for a program the length excluding variables |
| 16–26 | For an array, its type/length byte and name |
| 31–33 | Start address (page form) |
| 34–36 | Data length (page form) |
| 37–39 | Execution address, or the auto-run line number |
| 40–79 | **Comment — not initialised, free for you to poke** |

The header being requested or built is at address 19200 (`HDR`); the one just
read from the device is at 19280 (`HDL`). The last forty bytes of a header
are yours: poke a comment into `HDR+40` before a `SAVE` and read it back from
`HDL+40` after a `LOAD`.

[file-formats.md](../file-formats.md) has the complete field list.

## 11.6 `BOOT`

```
BOOT
BOOT 0
BOOT 1
```

`BOOT` with no parameter, or `BOOT 0`, auto-loads only if DOS is already
resident. `BOOT 1` forces a full boot or reboot from disk, with no auto-load
afterwards.

The loader talks to the disk controller directly — there is no DOS yet to ask.
It finds a free 16K page, steps the head to track 4, reads sector 1, checks
that the first four bytes read `BOOT`, and jumps into the loaded code. A disk
that is missing or not bootable gives error 55, *Missing disk*.

Function key F9 types `BOOT`.

## 11.7 Files through streams

Once a DOS is loaded, `OPEN #` can attach a stream to a file, and then `PRINT
#` and `INPUT #` do sequential I/O:

```basic
OPEN #4, "data.txt"
PRINT #4; "a line of text"
CLOSE #4
```

Three functions report on such a stream, and all three are implemented by DOS:

| Function | Result |
|---|---|
| `EOF #s` | Non-zero at end of file |
| `PTR #s` | The current file pointer |
| `PATH$` | The current directory path |
| `DVAR n` | The value of DOS variable *n* |

Reading past the end gives error 22, *End of file*.

## 11.8 Commands reserved for DOS

The following are recognised by the tokeniser but have no implementation in
the ROM. With a DOS loaded they work; without one they give *Not understood*:

`DIR`, `FORMAT`, `ERASE`, `MOVE`, `RENAME`, `PROTECT`, `HIDE`

(Note that `FORMAT` *is* used by the ROM in one place — `LIST FORMAT n` — but
as a bare command it belongs to DOS.)

External commands beginning with a full stop are the other DOS extension
mechanism:

```basic
.dir
.copy "a" TO "b"
```

The ROM plays no part in these: it does not recognise `.` at the start of a
statement, so they exist only while something has claimed the `CMDV` vector.
See [extending-basic.md](../extending-basic.md).

## 11.9 A worked example: a high-score file

```basic
  10 REM ---- load, update, save
  20 DIM name$(10,12): DIM score(10)
  30 ON ERROR GOTO 200                : REM no file yet? start fresh
  40 LOAD "scores" DATA name$()
  50 LOAD "scoreN" DATA score()
  60 ON ERROR STOP
  70
  80 INPUT "Your name: "; who$
  90 INPUT "Your score: "; pts
 100 FOR i = 1 TO 10
 110   IF pts > score(i)
 120     FOR j = 10 TO i+1 STEP -1
 130       LET name$(j) = name$(j-1): LET score(j) = score(j-1)
 140     NEXT j
 150     LET name$(i) = who$: LET score(i) = pts
 160     EXIT IF 1
 170   END IF
 180 NEXT i
 190 GOTO 220
 200 REM ---- first run
 210 ON ERROR STOP
 220 FOR i = 1 TO 10: PRINT i; " "; name$(i); " "; score(i): NEXT i
 230 SAVE OVER "scores" DATA name$()
 240 SAVE OVER "scoreN" DATA score()
```

---

## Summary

* `DATA`/`READ`/`RESTORE`; `READ LINE` takes raw text; `ITEM` says what is
  left.
* `DEVICE T`, `N`, `M` (with an optional number) selects tape, network or
  disk.
* `SAVE`/`LOAD`/`VERIFY` take `LINE n`, `CODE s,l[,e]`, `SCREEN$` or
  `DATA a()`; `MERGE` splices a program into the current one.
* `OVER` allows replacement; a leading `CHR$ 1`–`CHR$ 3` marks a file
  invisible and/or protected.
* Header bytes 40–79 are a free comment area you can poke and peek.
* `EOF`, `PTR`, `PATH$`, `DVAR` and the disk commands all need a DOS.

---

← [Sound](10-sound.md) · [Contents](README.md) · [Next: Errors and debugging →](12-errors-and-debugging.md)
