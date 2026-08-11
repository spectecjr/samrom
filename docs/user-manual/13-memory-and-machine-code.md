# 13. Memory and Machine Code

← [Errors and debugging](12-errors-and-debugging.md) · [Contents](README.md) · [Next: System variables →](14-system-variables.md)

---

## 13.1 The machine's memory

The Z80 can only see 64K at a time, but a SAM has 256K or 512K. The address
space is four 16K **sections**, each of which can be pointed at any physical
16K **page**:

| Section | Addresses | Normal contents while BASIC runs |
|---|---|---|
| A | 0–16383 | ROM 0 |
| B | 16384–32767 | The **system page** — physical page 0 |
| C | 32768–49151 | Whatever is being worked on |
| D | 49152–65535 | The page above section C's, or ROM 1 |

All the system variables, buffers, the calculator stack and the heap live in
page 0. The BASIC program starts in the same page — immediately after the
channel table — and grows upwards across pages 1, 2, … up to `RAMTOP`.

[memory-map.md](../memory-map.md) has the full region-by-region layout.

## 13.2 The 0–524287 address model

`PEEK`, `DPEEK`, `POKE`, `DPOKE`, `CALL`, `USR` and `USR$` all use one
addressing scheme that reaches every byte of a 512K machine with a single
number. The value is interpreted **relative to the context's base page** —
page 0 for a normal BASIC program — and the ROM pages the target in for you:

| Address *N* | Reaches | Paging |
|---|---|---|
| 0 – 16383 | ROM 0 at *N* | Section A |
| 16384 – 32767 | The base (system) page | Section B |
| 32768 – 49151 | Page base+1 | Section C |
| 49152 – 65535 | Page base+2 | Section D |
| ≥ 65536 | Offset *N* mod 16384 of page base + ⌊*N*/16384⌋ − 1 | Section C |

So:

* `PEEK 23611` reads a system variable in page 0.
* `PEEK 0` reads the first byte of the ROM.
* `PEEK 229385` reaches offset 9 of RAM page 13 on a 256K machine
  (229385 = 14 × 16384 + 9).

`FREE` gives the free space and `RAMTOP` the current top address, both in
this scheme.

## 13.3 Reading and writing memory

```
PEEK  address                   one byte
DPEEK address                   a 16-bit word, low byte first
POKE  address, value [, value …]
POKE  address, string
DPOKE address, word
```

`POKE` accepts up to 32 values in one statement, stored ascending from the
address. A **string** argument is block-copied to the address, which is by
far the fastest way to move data from BASIC:

```basic
10 POKE 32768, 1, 2, 3, 4, 5
20 POKE 32768, "Hello"                 : REM five bytes
30 DPOKE 32768, 1000
40 PRINT PEEK 32768, DPEEK 32768
```

The reverse direction is `MEM$`:

```basic
LET block$ = MEM$(32768 TO 33023)      : REM 256 bytes as a string
```

Between them, `POKE address, string$` and `MEM$(a TO b)` give you a complete
memory copy facility with no loops at all.

## 13.4 Reserving memory

There are two quite different ways to get memory that BASIC will not touch.

### Lowering `RAMTOP` — `CLEAR`

```
CLEAR [address]
```

`CLEAR` erases the variables and the stacks. With an address, it also moves
`RAMTOP` there, so everything above is out of BASIC's reach.

```basic
CLEAR 32767            : REM BASIC keeps only the system page
```

An address that would leave no usable room gives error 48, *Invalid CLEAR
address*.

### Reserving whole pages — `OPEN` and `CLOSE`

```
OPEN n           reserve n more 16K pages for this context
OPEN TO n        reserve or release so that exactly n pages are owned
CLOSE n          release n pages
```

These operate on the page allocation table, which records who owns each 16K
page of physical memory. A page must be free to be claimed; otherwise you get
error 1, *Out of memory*.

```basic
10 OPEN 2                      : REM two more 16K pages
20 PRINT RAMTOP
```

This is the right mechanism for large data — sample banks, tile maps, extra
screens — because it does not fragment the BASIC area.

Note that screens are allocated from the same pool, two consecutive pages at
a time on an even boundary, so reserving pages and opening screens compete
for the same memory.

## 13.5 Hardware ports

```
IN  port            read a byte
OUT port, value     write a byte
```

The ports you are most likely to want:

| Port | Name | Purpose |
|---|---|---|
| 248 (&F8) | `CLUTPORT` | Palette; also returns the light-pen position when read |
| 249 (&F9) | `STATPORT` | Interrupt status on read; line-interrupt scan number on write |
| 250 (&FA) | `LMPR` | Page for sections A and B, plus the ROM enable bits |
| 251 (&FB) | `HMPR` | Page for sections C and D |
| 252 (&FC) | `VIDPORT` | Displayed screen page and mode |
| 253 (&FD) | MIDI/network | |
| 254 (&FE) | Keyboard | Key rows, border colour, tape output, speaker |
| 255 (&FF) | Sound data | The address register is at 511 (&01FF) |

`OUT`ing to the paging ports from BASIC will crash the machine — the
interpreter is running from those pages. Repage only from machine code, and
restore the state before returning.

## 13.6 Calling machine code

```
CALL address [, parameter …]
USR  address                    numeric result
USR$ address                    string result
```

All three resolve the address through the model in §13.2 and **page it in for
you**. Your code runs at the mapped address with:

| Register | Contents |
|---|---|
| HL | The address your code is running at |
| BC | The same |
| A | For `CALL`: the number of parameters. For `USR`/`USR$`: junk |
| SP | The normal machine stack — a plain `RET` returns to BASIC |

`IX` is saved and restored by the ROM. Section C/D paging is restored after
your `RET`, so you may repage freely.

### `CALL` parameters

`CALL address, p1, p2, …` evaluates each parameter left to right onto the
calculator stack, following each with a **type entry**. On entry, A holds the
count and the stack holds, bottom to top:

```
value(p1) type(p1) value(p2) type(p2) … value(pn) type(pn)
```

Pop them with the jump table routine `STKFETCH` at address 292 (&0124), which
returns the five bytes in A, E, D, C, B. **Parameters come off in reverse
order**, type entry first.

A type entry is a small integer whose only meaningful bit is **bit 6: 1 =
numeric, 0 = string**. A value entry is either a 5-byte number or a string
descriptor of `page+flags, start-lo, start-hi, len-lo, len-hi`; mask the page
with 31 and page it into section C to reach the text.

Consume all 2*n* entries — `CALL` does not clean up for you.

### Returning a value

`CALL` cannot return anything directly. Either write results into memory the
program can `PEEK`, write through a passed string descriptor, or use a
function:

* **`USR n`** — whatever your code leaves in **BC** becomes the value.
  Remember BC arrives holding the entry address, so load it deliberately.
* **`USR$ n`** — on return the ROM stacks A = page, DE = start, BC = length
  as a string descriptor. Put the text somewhere stable; workspace obtained
  from the `WKROOM` jump-table entry is the intended place.

Neither `USR` nor `USR$` takes data parameters — their argument *is* the
entry address. Pass data through memory, or use `CALL`.

### A minimal example

```basic
  10 REM machine code that returns 1234 from USR
  20 LET a = 32768
  30 RESTORE 100
  40 FOR i = 0 TO 3: READ b: POKE a+i, b: NEXT i
  50 PRINT USR a
 100 DATA 1, 210, 4          : REM LD BC,1234
 110 DATA 201                : REM RET
```

### Useful entry points

The ROM publishes a jump table of fixed addresses starting at 256 (&0100).
Among the most useful from your own code:

| Address | Name | Purpose |
|---|---|---|
| 262 (&0106) | `HEAPROOM` | Reserve BC bytes of heap |
| 265 (&0109) | `WKROOM` | Open BC bytes at the workspace end |
| 271 (&010F) | `CALBAS` | Execute BASIC line HL from machine code |
| 274 (&0112) | `SETSTRM` | Select stream A |
| 289 (&0121) | `GETINT` | Pop the calculator stack top as an integer into BC |
| 292 (&0124) | `STKFETCH` | Pop five raw bytes |
| 295 (&0127) | `STKSTORE` | Push five bytes |
| 298 (&012A) | `SBUFFET` | Pop a string and copy it to a buffer |
| 301 (&012D) | `FARLDIR` | Cross-page block copy |
| 355 (&0163) | `RECLAIM2` | Close up BC bytes at (HL) |
| 361 (&0169) | `READKEY` | Read the keyboard |

The complete table, the restarts, and the floating-point calculator's
instruction set are documented in
[machine-code-interface.md](../machine-code-interface.md).

> **Errors do not return.** A ROM routine that raises a BASIC error resets the
> stack pointer and long-jumps to BASIC's error handler. Your code will not
> get control back. Validate ranges before calling, or install your own error
> frame.

## 13.7 Where to put machine code

| Place | How | Notes |
|---|---|---|
| Above `RAMTOP` | `CLEAR n` then poke above *n* | Simple; survives `RUN` and `NEW` |
| A reserved page | `OPEN 1`, then address ≥ 65536 | Best for large blocks |
| In a string | `POKE`d into a `DIM`med string | Moves when memory moves — get its address with `LENGTH(0, s$)` **immediately** before calling |
| Loaded from a file | `LOAD "x" CODE` | Header carries the address |

The string approach is convenient but fragile: creating any variable can move
the string area. Fetch the address afresh each time.

## 13.8 Speed and memory in practice

| Technique | Why it helps |
|---|---|
| `POKE addr, string$` | One block copy instead of a `FOR` loop |
| `MEM$(a TO b)` | The same in reverse |
| `LENGTH(0, v)` | Gets an array's address so machine code can work on it |
| `BLITZ` | Replays a whole drawing with no interpretation |
| `PUT`/`GRAB` | Move rectangles at memory-copy speed |
| Whole-number arithmetic | Uses the integer fast path |
| `OPEN n` for bulk data | Avoids fragmenting the BASIC area |
| `CLEAR` between phases | Reclaims fragmented string space |

## 13.9 Extending BASIC

Code you supply can become part of the language without patching the ROM,
through the **vector table** — nineteen routine addresses in the system
variables, each called only if it is non-zero. `MTOKV` sees every word the
tokeniser fails to match, `CMDV` every statement before it is dispatched,
`RST28V` every calculator opcode, and `PRTOKV` every token before it is
listed. External commands (`.name`) would be built on `CMDV` too — nothing in
the ROM or either DOS provides them.

Chapter 15 summarises them; [extending-basic.md](../extending-basic.md) gives
the exact contracts and four complete worked examples.

---

## Summary

* One address model, 0 to 524287, covers all of memory for `PEEK`, `POKE`,
  `CALL` and `USR`; the ROM does the paging.
* `POKE addr, string$` and `MEM$(a TO b)` are block copies in both directions.
* `CLEAR n` lowers `RAMTOP`; `OPEN n` reserves whole 16K pages.
* `CALL` passes parameters with type entries on the calculator stack; `USR`
  returns BC and `USR$` returns a string descriptor.
* Your code is entered at a pre-mapped address, also given in HL and BC, and
  returns with `RET`.

---

← [Errors and debugging](12-errors-and-debugging.md) · [Contents](README.md) · [Next: System variables →](14-system-variables.md)
