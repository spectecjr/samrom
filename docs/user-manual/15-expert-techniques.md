# 15. Expert Techniques

← [System variables](14-system-variables.md) · [Contents](README.md) · [Appendix A →](appendix-a-keywords-a-l.md)

---

This chapter is about getting the most out of the machine: writing fast code,
understanding what the interpreter does with your program, and extending the
language itself.

## 15.1 What the interpreter actually does with your line

Understanding the pipeline explains most of SAM BASIC's performance
characteristics.

```
EDITOR      collect keystrokes into the edit line
TOKMAIN     replace spelled-out keywords with single token bytes
LINESCAN    syntax-check every statement — and, as a side effect,
            insert the invisible 5-byte value after every numeric literal
            and a 6-byte calling buffer after every FN and PROC name
then either:
  INSERTLN  (the line began with a number) copy it into the program
or:
  COMPILE   resolve the calling buffers
  LINERUN   execute
```

Consequences that matter when you are optimising:

* **Numeric literals cost nothing at run time.** The text you typed is
  skipped and the pre-converted five bytes are copied to the calculator
  stack. A constant is as cheap as a variable — cheaper, in fact, since there
  is no lookup.
* **String literals cost nothing to copy** unless they contain a doubled
  quote. The descriptor points directly into the program line.
* **`FN` and `PROC` calls cost a table lookup, not a search.** The compile
  pass fills in each buffer with the definition's page and address before
  every run.
* **Addresses in a program are never trusted.** They are re-resolved on every
  run, which is why a program survives editing, renumbering, and being loaded
  back at a different address.
* **A stored line is byte-for-byte what the syntax checker left behind.** That
  is why a program takes more memory than the text you typed.

[tokenized-program-format.md](../tokenized-program-format.md) has the full
detail.

## 15.2 Writing fast BASIC

### Arithmetic

| Faster | Slower | Why |
|---|---|---|
| `FOR i = 0 TO 100` | `FOR i = 0 TO 10 STEP 0.1` | Integer fast path |
| `LET n = n + 1` | `LET n = n + 0.5` | Integer add avoids the FP path |
| `x DIV 2` | `INT(x/2)` | One operation instead of two |
| `x BAND 255` | `x - 256*INT(x/256)` | One operation |

Whole numbers in ±65535 use a dedicated integer path through add, subtract
and multiply. Keeping loop counters, coordinates and array indexes integral
is the single biggest arithmetic win.

### Variable lookup

Numeric variables live in 26 chains, one per initial letter, so lookup time
depends on how many variables share the first letter — not on how many exist
in total. Strings and arrays live in one flat list scanned from the start.

* Spread numeric variable names across initial letters in hot code.
* Create frequently used strings and arrays **early**, so they are found
  sooner.
* Prefer a numeric variable to a string one in an inner loop.

### Bulk operations

Never write a loop for something the ROM will do in one go:

| Instead of | Write |
|---|---|
| `FOR i=0 TO n: POKE a+i, PEEK(b+i): NEXT i` | `POKE a, MEM$(b TO b+n)` |
| A loop of `PLOT`s replaying a picture | `BLITZ pic$` |
| A loop drawing a sprite | `PUT x, y, sprite$` |
| A loop clearing a rectangle | `WINDOW …: CLS 1` |
| A loop building a repeated string | `STRING$(n, a$)` |
| A loop searching a string | `INSTR(a$, b$)` |

### Control flow

* Block `IF` locates its `END IF` by searching the program at run time. In an
  inner loop, prefer the single-line form.
* `DO`/`LOOP` is cheap: the frame is four bytes and the return address is
  known.
* `GOSUB` and procedure calls are both cheap; procedures are no slower than
  `GOSUB` and far easier to maintain.
* `EXIT IF` is cheaper than `GOTO` out of a loop, and does not leak a stack
  frame.

### Things to keep out of loops

`VAL`, `VAL$` and `KEYIN` each invoke the tokeniser and the syntax checker.
They are enormously powerful and enormously slow. Hoist them out, or replace
them with `CODE`, `INSTR` and arithmetic.

## 15.3 Memory strategy

| Situation | Approach |
|---|---|
| A large fixed table | `OPEN 1` a page, `POKE` it, address it above 65536 |
| Machine code | `CLEAR n` and put it above `RAMTOP` |
| Many short strings | A single string array, sliced |
| Growing text | Accumulate through stream 16 with `RECORD` |
| Fragmentation | `CLEAR` between phases of the program |

String assignment can move the whole string area, so any address you obtained
from `LENGTH(0, a$)` is stale the moment you create another variable. Fetch
it immediately before you use it.

Numeric variables grow into a 512-byte gap between the numeric area and the
string area; when it fills, the gap is re-opened. So creating numeric
variables is usually cheap but occasionally moves everything above.

## 15.4 The screen as memory

In `MODE 3` and `MODE 4` the screen is linear and attribute-free, which makes
it just another block of memory:

```basic
10 MODE 4
20 LET screen = 32768               : REM the screen page, section C
30 POKE screen, MEM$(mydata TO mydata+6143)
```

`GRAB` and `PUT` are the supported way to do this, and they handle the paging
and the page boundary for you. Direct poking works but you must page the
screen in yourself.

The `MODE 4` screen is 128 bytes per scan line and 192 lines — 24K, which is
why it spans two pages.

## 15.5 Double buffering

```basic
  10 OPEN SCREEN 2, 4
  20 LET front = 1: LET back = 2
  30 DO
  40   SCREEN back
  50   CLS
  60   draw_frame
  70   DISPLAY back
  80   LET t = front: LET front = back: LET back = t
  90   EXIT IF INKEY$ <> ""
 100 LOOP
 110 DISPLAY 0: SCREEN 1: CLOSE SCREEN 2
```

`SCREEN n` selects where drawing goes; `DISPLAY n` selects what is shown.
Because each screen carries its own windows, colours and cursor position,
nothing has to be re-established after the switch.

## 15.6 Interrupt-driven work

Point `FRAMIV` (23266) at a machine-code routine and it will be called fifty
times a second, from the frame interrupt. That is how background music,
clocks and smooth scrolling are done.

```basic
10 DPOKE 23266, myroutine
```

Rules for such a routine:

* Preserve everything you use, including the alternate registers.
* Keep it short — you are inside an interrupt.
* The system page is mapped when you are entered; restore any paging you
  change.
* Point it back at 0 before you `NEW`.

`LINIV` (23268) is the line-interrupt vector, which fires part-way down the
frame — the mechanism behind `PALETTE … LINE`. `COMSV`, `MIPV` and `MOPV`
handle the network and MIDI.

`ANYIV` (23408) is taken by *every* maskable interrupt before the source is
worked out, which is the place to hook if you want to see them all.

## 15.7 Extending BASIC

Four vectors turn the interpreter into an extensible one. Each is called only
if it is non-zero.

| Vector | Address | Called |
|---|---|---|
| `MTOKV` | 23290 | By the tokeniser, whenever a word misses the ROM keyword table. Return an index and the word becomes a token |
| `CMDV` | 23284 | By the statement dispatcher, with the first byte of every statement — on the syntax pass as well as at run time |
| `RST28V` | 23280 | By the floating-point calculator, before every opcode. This is where a new function or operator is actually implemented |
| `PRTOKV` | 23262 | By the lister, before a token is expanded, so a new keyword can list back |

`EVALUV` (23286) sees each function code before the evaluator dispatches it,
but it is a *remapping* hook rather than an implementation one — the
evaluator's continuation points are not published, so a hook cannot leave a
value stacked and rejoin the scan. Queue the work for the calculator instead.

The token budget is small and fixed:

* **Commands** — &D0 is free through either route; &F7–&FE are free but
  reachable only through `CMDV`, since the dispatcher rejects them before the
  address table is consulted. The eight DOS-reserved spellings (`DIR`,
  `FORMAT`, `ERASE`, `MOVE`, `COPY`, `RENAME`, `PROTECT`, `HIDE`) already
  tokenise and list, so claiming one needs `CMDV` alone.
* **Functions** — exactly two free codes, &68 (number → number) and &6A
  (string → number). Their argument and result types are fixed by the ROM's
  priority tables and cannot be chosen.
* **Operators** — one free code, &7D, at priority 2. It is the slot the
  never-implemented `BXOR` was allocated.

### External commands

A statement beginning with a full stop is a convention for commands supplied
from outside BASIC. **Nothing in the ROM or in either DOS implements it** —
the ROM does not recognise `.` at the start of a statement, `XCMDP` (23051)
is reserved for "the first external command list" but never read, and both
SAMDOS 2 and MasterDOS dispatch on command tokens instead.

Should you want to add them, they are built on `CMDV` like everything else,
and need no tokeniser or lister work because the name is never tokenised —
which makes them the cheapest way to add a lot of commands at once:

```basic
.mycommand 1, 2, 3
```

> **[extending-basic.md](../extending-basic.md) is the full treatment**: the
> exact entry and exit contract for every hook, where extension code has to
> live and how to carve room for it, and four complete worked examples — a
> new command on a reserved token, a new command with a new spelling, a new
> function and operator, and an external-command dispatcher.

### Diverting existing behaviour

| Vector | Address | Diverts |
|---|---|---|
| `DMPV` | 23258 | `DUMP` — install a printer driver here |
| `PRTOKV` | 23262 | Keyword expansion during listing |
| `RST8V` | 23278 | Every error, before it is acted on |
| `RST28V` | 23280 | Every calculator opcode, before dispatch |
| `LPRTV` | 23288 | `LPRINT` output |
| `MOUSV` | 23292 | Mouse reading |
| `KURV` | 23294 | Cursor drawing |
| `EDITV` | 23276 | Editor entry |
| `PATOUT` | 23506 | The routine that renders one printable character |

`PATOUT` is the interesting one for anyone wanting proportional text or a
different font engine: replace it and every character printed goes through
your code.

## 15.8 Self-modifying and generated programs

`KEYIN` runs a string as BASIC, including adding lines:

```basic
10 FOR n = 1 TO 5
20   KEYIN STR$(1000 + n*10) + " PRINT " + CHR$ 34 + "line " + STR$ n + CHR$ 34
30 NEXT n
40 LIST 1000
```

Combined with `RECORD` (which captures output into a string) and `MERGE`
(which splices a saved program into the current one), this makes it
straightforward to write programs that build, save and reload other programs.

Note that `KEYIN` runs the full pipeline, so it is slow. Generate once, then
`SAVE`.

## 15.9 Style for large programs

A program that will be maintained should look like this:

* **No line numbers referenced anywhere.** Use `DEF PROC` and `LABEL`.
* **A short main body** — setup, a `DO` loop, tidy-up, `STOP` — with
  everything else in procedures after it.
* **`LOCAL` for every working variable in a procedure.** It costs nothing and
  makes procedures reusable and recursive.
* **`DEFAULT` for optional parameters.**
* **`REF` for arrays**, which passes them free of charge.
* **Long, readable names.** Spaces inside a name are ignored, so
  `LET number of lives = 3` costs no more than `LET nol = 3` at run time —
  only in program bytes.
* **`LIST FORMAT 2`** while you work, so the structure is visible.
* **An `ON ERROR` handler written as a procedure**, so it re-arms itself.

```basic
   10 REM ======= Main =======
   20 ON ERROR handle error
   30 initialise
   40 DO
   50   read input
   60   EXIT IF finished
   70   update world
   80   draw world
   90 LOOP
  100 shut down
  110 STOP
```

## 15.10 Where to look next

| Document | For |
|---|---|
| [extending-basic.md](../extending-basic.md) | Adding your own commands, functions, operators and external commands: every hook's contract, and four worked examples |
| [dos-and-extensions.md](../dos-and-extensions.md) | What SAMDOS 2, MasterDOS and MasterBASIC add, and how they hook the ROM — the same techniques in production use |
| [machine-code-interface.md](../machine-code-interface.md) | The jump table, the restarts, the FP calculator's instruction set, and the `CALL`/`USR` protocol in full |
| [tokenized-program-format.md](../tokenized-program-format.md) | Exactly what a stored program looks like — needed to write a tokeniser, detokeniser or cross-compiler |
| [memory-map.md](../memory-map.md) | Every region of the system page, with sizes |
| [file-formats.md](../file-formats.md) | The 80-byte header, field by field |
| [font-rendering.md](../font-rendering.md) | Cell geometry, and designing a font that works at every `CSIZE` |
| [hudg.md](../hudg.md) | The three font pointers, and how to populate the dormant high-UDG range |
| [constants.md](../constants.md) | Every named constant in the ROM |
| [source-files.md](../source-files.md) | Routine-by-routine reference to the whole ROM |

---

## Summary

* Literals, `FN` calls and `PROC` calls are pre-resolved, so they are fast;
  `VAL` and `KEYIN` are not.
* Keep arithmetic on whole numbers; use `POKE a, string$`, `MEM$`, `PUT`,
  `BLITZ` and `STRING$` instead of loops.
* Reserve pages with `OPEN n` for bulk data; `CLEAR n` for machine code.
* `FRAMIV` gives you fifty interrupts a second; `MTOKV`, `CMDV`, `RST28V` and
  `PRTOKV` let you add keywords — see [extending-basic.md](../extending-basic.md).
* Write with procedures, `LOCAL`, `LABEL` and `LIST FORMAT` and you will
  never need a line number.

---

← [System variables](14-system-variables.md) · [Contents](README.md) · [Appendix A →](appendix-a-keywords-a-l.md)
