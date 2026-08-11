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
| `DEVICE D` | Disk drive 1 |
| `DEVICE D2` | Disk drive 2 |
| `DEVICE D4` | **`[MD]`** RAM disk 4 |

The trailing colon you often see written — `DEVICE D1:` — is just the
statement separator; it is harmless and reads well.

The letter and number are stored in `PSLD` (system variable offsets &06 and
&07) and copied to a working pair for the duration of each file command.

The ROM accepts **any** letter. It special-cases only `T` (tape) and `N`
(network), which it handles itself; everything else has its number defaulted
to 1 and is passed to the resident DOS, giving error 53, *No DOS*, if there
is none. Both SAMDOS 2 and MasterDOS use `D` for a disk drive — the same
letter as the `"D1:name"` prefix you can put on a file name.

Drive numbers are 1 and 2 with SAMDOS 2. **`[MD]`** MasterDOS keeps those for
physical drives and adds 3 to 7 as RAM disks.

The machine starts up with `DEVICE T`.

### Drive prefixes on a file name — **`[DOS]`**

Any file name given to a DOS command may name its drive directly, overriding
the current `DEVICE` for that one command:

```
"d1:name"       drive 1
"d2:name"       drive 2
"d4:name"       [MD] RAM disk 4
"name"          whatever DEVICE currently selects
```

The letter is **`D`**, and it is not optional. Both DOSes parse a prefix as a
letter, then up to two digits, then a colon, and then check the letter: SAMDOS
2 does it at the end of `evfile`, MasterDOS in `CKDISC`. Anything else gives
error 10, *Invalid device*.

> **A bare number is not a drive prefix.** `"1:name"` is not drive 1 — the
> parser takes the `1` as the device *letter*, finds it is not `D`, and stops
> with *Invalid device*. Write `"d1:name"`.

Case does not matter; the letter is folded to upper case before it is tested,
so `"d1:"` and `"D1:"` are the same.

**`[MD]`** MasterDOS extends this in two ways: `"t:"` selects tape, and a
prefix with no name after it — `"d1"` or `"d1:"` — is expanded to `"d1:*"`,
so `DIR "d2:"` lists the whole of drive 2.

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

## 11.7 Files through streams — OPENTYPE files

Everything so far loads or saves a file *whole*. A **serial file** is read or
written a piece at a time through a stream, so a program can process more
data than fits in memory. The whole mechanism needs a DOS: the ROM supplies
only `OPEN #`, `CLOSE #` and the stream plumbing, and hands anything it does
not recognise to the DOS.

Such a file has its own type — **type 10, "OPENTYPE"**, which is what a `DIR`
listing shows — and unlike every other type it has no fixed length recorded
when it is created. It grows as you write to it.

### Opening

```
OPEN #stream; "filename" OUT      create a new file and write to it
OPEN #stream; "filename" IN       open an existing file for reading
OPEN #stream; "filename" RND      open for random access          [MD]
```

The channel letter for a disk file is `D`, which the DOS installs. You never
name it: supplying a filename rather than a single-character channel name is
what tells the ROM to hand the `OPEN` to the DOS.

```basic
OPEN #5; "results" OUT
```

### Reading and writing

Once open, a stream behaves like any other:

```basic
PRINT #5; "some text"          : REM write a line
INPUT #5; a$                   : REM read a line back
```

**`[MD]`** `INP$` is the faster alternative to `INPUT #`, and does not
disturb the lower screen:

```basic
LET a$ = INP$(#5, 20)          : REM exactly 20 characters
LET a$ = INP$(#5, 0)           : REM up to the next carriage return
```

**`[SD2]`** **`[MD]`** `READ` and `WRITE` handle fixed-length records rather
than lines, and `PTR` moves the file pointer for random access.

### Closing — and why it matters

```basic
CLOSE #5                       : REM one stream
CLOSE #                        : REM every open file
```

**Closing is not optional.** Until a file is closed the DOS still holds
buffered data that has not reached the disk, and the directory entry does not
yet record the final length. A program that stops without closing leaves a
truncated or unusable file. Put `CLOSE #` in your tidy-up procedure *and* in
your `ON ERROR` handler.

### Status functions

| Function | | Result |
|---|---|---|
| `EOF #s` | **`[DOS]`** | Non-zero at end of file |
| `PTR #s` | **`[DOS]`** | The current file pointer; used for random access |
| `PATH$` | **`[DOS]`** | The current directory path |
| `DVAR n` | **`[DOS]`** | The address of DOS variable *n*, used like `SVAR` |
| `FSTAT(name$, n)` | **`[MD]`** | Directory information about a file — see below |
| `DIR$(pattern$)` | **`[MD]`** | The next matching file name, as a string |
| `FPAGES` | **`[MD]`** | Free pages |
| `DSTAT` | **`[MD]`** | Disk status |

Reading past the end gives error 22, *End of file*.

**`[MD]`** `FSTAT` takes an option number, extended by MasterBASIC to eight:

| *n* | Result |
|---|---|
| 1 | File number in the directory; 0 if not found, −1 if no disk |
| 2 | Length in bytes, excluding any header |
| 3 | File type |
| 4 | File type, plus 64 if protected, plus 128 if hidden |
| 5 | Start address |
| 6 | Auto-start line, or execute address for `CODE`; 0 if none |
| 7 | Date, as e.g. 231291 for 23/12/91; 0 if undated |
| 8 | Flags: bit 1 cannot be stopped, bit 2 compressed, bit 3 `SAVE MODE 3` `SCREEN$` |

### A worked example

```basic
  10 REM ---- write a file, then read it back
  20 ON ERROR tidy up
  30 OPEN #5; "notes" OUT
  40 FOR i = 1 TO 20
  50   PRINT #5; "line "; i
  60 NEXT i
  70 CLOSE #5
  80
  90 OPEN #5; "notes" IN
 100 DO
 110   EXIT IF EOF #5
 120   INPUT #5; a$
 130   PRINT a$
 140 LOOP
 150 CLOSE #5
 160 STOP
 170
1000 DEF PROC tidy up
1010   CLOSE #
1020   PRINT "error "; error; " at "; lino
1030 END PROC
```

## 11.8 Disk operations and the filesystem

The disk commands do not just move data about — each changes the disk's
bookkeeping in a particular way, and knowing which explains a good deal of
otherwise surprising behaviour.

### What is on a disk

| Structure | Purpose |
|---|---|
| **Directory** | One entry per file: name, type, attributes, length, start address and — with MasterDOS — the date. It occupies the first few tracks; MasterDOS uses four by default and can be told to use more when the disk is formatted |
| **Sector allocation map** | A bitmap recording which sectors are in use. `FORMAT` clears it; `ERASE` frees bits in it |
| **File data** | The sectors themselves |
| **Sub-directories** **`[MD]`** | Themselves files, of type 21, tagged so their entries can be filtered out of the parent listing |

### What each command changes

| Command | Directory entry | Data sectors | Allocation map |
|---|---|---|---|
| `SAVE` | Created | Written | Sectors claimed |
| `LOAD`, `VERIFY`, `MERGE` | Read | Read | Untouched |
| `ERASE` | Cleared | **Left as they were** | Sectors freed |
| `RENAME` | Name changed | Untouched | Untouched |
| `PROTECT`, `HIDE` | Attribute byte changed | Untouched | Untouched |
| `COPY` | New entry created | Copied | Sectors claimed |
| `MOVE` **`[MD]`** | Entry moved or recreated | Copied only across drives | Adjusted |
| `FORMAT` | **Emptied** | **Lost** | **Cleared** |
| `FORMAT … TO …` | **Emptied, then overwritten from the second drive** | **Lost, then copied over** | **Copied over** |
| `BACKUP` **`[MD]`** | Whole disk duplicated | | |
| `OPEN … OUT` | Created, length not yet known | Written as you print | Claimed as it grows |
| `CLOSE` | **Length finalised** | Flushed | — |

Three consequences worth remembering:

* **`ERASE` does not destroy data.** It clears the directory entry and frees
  the sectors. Until something else claims them the contents remain — which
  is why an accidental `ERASE` is often recoverable with the right tool, and
  why a disk holding anything sensitive should be reformatted rather than
  erased.
* **An unclosed `OPEN … OUT` file has no valid length.** The entry exists but
  records the file as empty or short. This is the commonest way to lose data
  on a SAM.
* **`FORMAT … TO …` destroys the disk named *first*.** It formats that one and
  copies the second onto it, so it reads backwards from `COPY` and `MOVE`.
  See [`FORMAT`](appendix-a-keywords-a-l.md#format--dos) in appendix A.

### Open files move your program

This is the trap that catches people, and it is worth stating plainly.

**`[MD]`** Each open file needs a buffer, and MasterDOS puts those buffers in
an area **immediately before the BASIC program**. Opening or closing a file
therefore *moves the whole program*, which invalidates:

* addresses obtained earlier from `LENGTH(0, name)`;
* any address a procedure recorded for itself;
* machine code poked into a string.

**`[MB]`** MasterBASIC's answer is `OPEN BLOCKS n`, which reserves room for
*n* buffers up front so that later `OPEN`s do not move anything:

```basic
10 OPEN BLOCKS 3          : REM room for three files; the program settles here
20 OPEN #5; "a" OUT
30 OPEN #6; "b" OUT       : REM neither of these moves the program
```

Without MasterBASIC, the workaround is to open every file you will need
before taking any addresses — or to re-fetch addresses after every `OPEN` and
`CLOSE`.

### Practical rules

* Open every file you need at the start; close them all at the end.
* Put `CLOSE #` in the `ON ERROR` handler as well as in the normal exit.
* Re-fetch `LENGTH(0, …)` addresses after any `OPEN` or `CLOSE`, unless you
  have used `OPEN BLOCKS`.
* Check `FSTAT(name$, 1)` before writing if you care whether a file already
  exists; `SAVE OVER` and `ERASE OVER` suppress the prompts.
* `PROTECT` a master copy before working on it — it costs nothing and blocks
  both `ERASE` and overwriting.

## 11.9 Commands reserved for DOS

The following are recognised by the tokeniser but have no implementation in
the ROM. With a DOS loaded they work; without one they give *Not understood*:

`DIR`, `FORMAT`, `ERASE`, `MOVE`, `RENAME`, `PROTECT`, `HIDE`

SAMDOS 2 implements all of these except `MOVE`; MasterDOS implements all of
them, and adds `BACKUP`, `TIME` and `DATE` plus seven functions of its own.
MasterBASIC adds four more commands and nineteen more functions on top.
[dos-and-extensions.md](../dos-and-extensions.md) is the full list, with the
tokens each uses.

(Note that `FORMAT` *is* used by the ROM in one place — `LIST FORMAT n` — but
as a bare command it belongs to DOS.)

You may also see **external commands** written with a leading full stop, as
`.something`. Neither the ROM nor either DOS provides them: the ROM rejects a
statement beginning with `.`, and SAMDOS 2 and MasterDOS both dispatch on the
command *token* instead. A dot command works only where some later utility
has claimed the `CMDV` vector to implement it. See
[extending-basic.md](../extending-basic.md#9-external-commands).

## 11.10 A worked example: a high-score file

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
* `DEVICE T`, `N`, `D` (with an optional number) selects tape, network or
  disk.
* `SAVE`/`LOAD`/`VERIFY` take `LINE n`, `CODE s,l[,e]`, `SCREEN$` or
  `DATA a()`; `MERGE` splices a program into the current one.
* `OVER` allows replacement; a leading `CHR$ 1`–`CHR$ 3` marks a file
  invisible and/or protected.
* Header bytes 40–79 are a free comment area you can poke and peek.
* `EOF`, `PTR`, `PATH$`, `DVAR` and the disk commands all need a DOS.
* `OPEN #s; "name" OUT` creates a serial (OPENTYPE, type 10) file that grows
  as you print to it; `CLOSE` is what finalises its length, so an unclosed
  file is unusable.
* `ERASE` frees sectors and clears the directory entry but leaves the data.
* With MasterDOS, opening or closing a file **moves the BASIC program**;
  MasterBASIC's `OPEN BLOCKS n` pre-allocates the buffers to prevent that.

---

← [Sound](10-sound.md) · [Contents](README.md) · [Next: Errors and debugging →](12-errors-and-debugging.md)
