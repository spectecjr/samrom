# SAM Coupé ROM 3.0 — Machine-Code Interface

How external (user) machine code interacts with the ROM: the public jump
table, the restarts, calling the floating-point calculator, and the
parameter-passing protocol for `CALL`, `USR` and `USR$`.

Assumed context throughout: the paging BASIC gives to called code — ROM0 at
&0000 (section A), the system page at &4000 (section B), your code and data
in sections C/D. If your code changes LMPR (port 250), restore it before
using any of these services.

## Restarts

| RST | Name | Function |
|---|---|---|
| &00 | — | Reset (delay, ROM1 on, full initialisation) |
| &08 | Error | The byte following the RST is the error/hook code; control passes to the error handler (or DOS for codes ≥ 128). **Does not return** unless a DOS hook succeeds |
| &10 | Print | Print the character in A through the current channel |
| &13 | `PRINTSTR` | (CALL &0013) Print BC bytes from (DE) |
| &18 | Get char | A := significant character at (CHAD), spaces/control codes skipped, ROM1 paged out around the read |
| &20 | Next char | Advance CHAD, then as RST &18 |
| &28 | Calculator | Execute the FP-calculator code bytes that follow, until `EXIT` (&33). See [below](#calling-the-floating-point-calculator) |
| &30 | ROM1 link | From ROM0: call/jump into ROM1. **From RAM: vectors through `RST30V`** (&5AF2) — set that vector before using RST &30 in your own code |
| &38 | Interrupt | Maskable-interrupt entry; dispatches via `ANYIV` |

## The jump table at &0100

Fixed public entry points, 3 bytes apart. "ROM" shows where the routine
body lives (calls are made to the table address regardless; the table
handles any paging).

| Addr | Name | ROM | Contract |
|---|---|---|---|
| &0100 | `JSCRN` | 1 | Select screen C (1–16) as current output screen |
| &0103 | `JSVIN` | 0 | Call the routine whose address follows the CALL, with the system page mapped at &4000, ROM0 on/ROM1 off, on a private stack; everything restored on return |
| &0106 | `HEAPROOM` | 1 | Reserve BC bytes of heap (release if negative). Exit: DE = room start (old HEAPEND), HL = new HEAPEND, NC = not enough room (HL = shortfall) |
| &0109 | `WKROOM` | 0 | Open BC bytes at the workspace end. Exit: DE = start, HL = end, room paged in |
| &010C | `MKRBIG` | 0 | Open A×16K + BC bytes at (HL) (paged in), shifting everything above and adjusting all system pointers |
| &010F | `CALBAS` | 0 | Execute BASIC line HL (as a GOSUB from machine code). Exit: Z = OK, else A = error number |
| &0112 | `SETSTRM` | 0 | Select stream A (&FC–&0F… internally −4 to 15; &FC–&FF are the fixed system streams) as current channel |
| &0115 | `POMSG` | 0 | Print message number A from the bit-7-terminated list at DE |
| &0118 | `EXPT1NUM` | 0 | Evaluate a numeric expression at (CHAD); error if string. Result on the calculator stack if running |
| &011B | `EXPTSTR` | 0 | Evaluate a string expression at (CHAD) |
| &011E | `EXPTEXPR` | 0 | Evaluate either kind; Z = string, NZ = numeric; CY = running |
| &0121 | `GETINT` | 0 | Pop the calculator-stack top as an integer to BC (and HL, A=C). BASIC error 30 if negative or ≥ 65536 |
| &0124 | `STKFETCH` | 0 | Pop 5 bytes: A, E, D, C, B (for a string: A=page+flags, DE=start, BC=length) |
| &0127 | `STKSTORE` | 0 | Push 5 bytes A, E, D, C, B onto the calculator stack |
| &012A | `SBUFFET` | 0 | Pop a string descriptor and copy the text to `INSTBUF` (&4F00). Error if length 0 or > 255. Exit: DE = start, BC = A = length |
| &012D | `FARLDIR` | 0 | Copy (PAGCOUNT)×16K + (MODCOUNT) bytes from page A, addr HL to page C, addr DE, ascending, across any page boundaries |
| &0130 | `FARLDDR` | 0 | As FARLDIR, descending (for overlapping upward moves) |
| &0133 | `JPUT` | 0 | PUT block: A = mode 0–5, B = Y, C = X, HL → width/len-prefixed data, HL' → mask |
| &0136 | `JGRAB` | 0 | GRAB block: D=len, E=width(bytes), B=Y, C=X. Exit: DE=start, BC=len of captured data |
| &0139 | `JPLOT` | 0 | Plot: coordinates in C,B (fat) or HL,B (thin) |
| &013C | `JDRAW` | 0 | Draw relative: registers as the DRAW internals (B=Y diff, C/HL=X diff, D/E = sign bytes) |
| &013F | `JDRAWTO` | 0 | Draw to absolute X,Y in C,B / HL,B |
| &0142 | `JCIRCLE` | 0 | Circle: A = radius, C,B = centre, HL = thin-pixel offset |
| &0145 | `JFILL` | 0 | Fill: HL = coords; DE = pattern (0 = solid); A = 0 to build the check screen |
| &0148 | `JBLITZ` | 0 | Execute a BLITZ graphics string: DE = data, BC = length |
| &014B | `JROLL` | 0 | Roll/scroll: B=pixels, C=direction 1–4, HL=top-left coords, D=len, E=width, A=&FF roll/0 scroll |
| &014E | `CLSBL` | 0 | Clear whole screen if A=0, else clear window |
| &0151 | `CLSLOWER` | 0 | Clear the lower screen window, select channel K |
| &0154 | `JPALET` | 1 | Palette set: A = line (&FF if none), B/C = colours, E = palette entry |
| &0157 | `JOPSCR` | 1 | Open screen: B = mode, C = screen number |
| &015A | `MODET` (`MODPT2`) | 1 | Set MODE A (0–3), windows, expansion tables; clears the screen |
| &015D | `JTCOPY` | 1 | Text COPY (via `DMPV` vector — no-op unless a dump driver is installed) |
| &0160 | `JGCOPY` | 1 | Graphics COPY (via `DMPV`) |
| &0163 | `RECLAIM2` | 0 | Close up BC bytes at (HL), adjusting all system pointers |
| &0166 | `KBFLUSH` | 0 | Flush the keyboard queue |
| &0169 | `READKEY` | 0 | Read the keyboard (INKEY$ style). Exit: CY,NZ with A = key, or Z,NC = none |
| &016C | `KYIP2` | 0 | Fetch a queued key: CY with A = key, Z,NC = none (no waiting) |
| &016F | `BEEPP2` | 1 | Sound: DE−1 cycles at period HL (8-T units) |
| &0172 | `SABYTES` | 1 | Save block to tape/net: A = type (1 header/&FF data), HL = start (paged in), CDE = length (page form) |
| &0175 | `LDBYTES` | 1 | Load (CY) or verify (NC) a block: A = expected type, HL = dest, CDE = length |
| &0178 | `JLDVD` (`LDVD2`) | 1 | Load/verify CDE bytes at HL from the current device (tape/net/DOS) |
| &017B | `EDGE2` | 0 | Tape edge timer: C = pulse length, CY = edge found, NC = BREAK/timeout |
| &017E | `JPFSTRS` (`PFSTRS`) | 1 | Convert the calculator-stack top to text: BC digits at (DE) in the print buffer |
| &0181 | `SENDA` (`SNDA2`) | 1 | Send byte A to the printer port |
| &0184 | `IMSCSR` | 0 | SCREEN$ core: DE = line/col. Exit CY: not recognised; NC: (HL) = char, BC = 1 |
| &0187 | `GRCOMP` | 0 | Compress a mode 2/3 character cell to 1-bit form (graphics COPY support) |
| &018A | `JGTTOK` (`GETTOKEN`) | 1 | Keyword match: HL = word list −1 (bit-7-terminated words), A = word count +1, DE = candidate text. Exit: A = 1-based match index, Z = no match |
| &018D | `JCLSCR` | 1 | Close screen C |

## Calling the floating-point calculator

The calculator is a byte-coded stack machine executed by `RST &28`. The
bytes *following the RST in your own code* are its program; execution
resumes after the terminating `EXIT` byte. It works from RAM exactly as
from ROM (the handler makes IX the instruction pointer via `EX (SP),IX`,
pages ROM1 in for the duration, and restores everything on exit).

### The stack

* Entries are **5 bytes** each; `STKEND` (&5C65) points at the first free
  byte; the stack base is `FPSBOT` (&4D00). Roughly 50 entries fit before
  the machine-stack region — plenty.
* Number forms (details in
  [tokenized-program-format.md §9](tokenized-program-format.md#9-the-5-byte-number-format)):
  small integer `00 sign lo hi 00`, or FP `exponent m1 m2 m3 m4` where the
  magnitude is $ m \times 2^{e-128} $ with $ 0.5 \le m < 1 $, the mantissa's
  leading 1 implicit, and its bit 7 replaced by the sign.
* Strings on the same stack are 5-byte descriptors:
  `page+flags, start-lo, start-hi, len-lo, len-hi`.

### Pushing operands

Use `STKSTORE` (&0127), which writes A, E, D, C, B in that order:

| To push | A | E | D | C | B |
|---|---|---|---|---|---|
| Integer n (0–65535) | 0 | 0 | n lo | n hi | 0 |
| Integer −n | 0 | &FF | (−n) lo | (−n) hi (two's complement) | 0 |
| Full FP value | exponent | mantissa 1 | mantissa 2 | mantissa 3 | mantissa 4 |
| String | page | start lo | start hi | len lo | len hi |

Alternatively copy 5 bytes to (`STKEND`) yourself and add 5 to `STKEND`.

### Running a calculation

Example — hypotenuse $ \sqrt{x^2+y^2} $ of the two numbers already on the
stack (x below y):

```z80
        RST  &28
        DB   &25            ; DUP         x, y, y
        DB   &00            ; MULT        x, y*y
        DB   &06            ; SWOP        y*y, x
        DB   &25            ; DUP         y*y, x, x
        DB   &00            ; MULT        y*y, x*x
        DB   &01            ; ADDN        y*y + x*x
        DB   &43            ; SQR         result
        DB   &33            ; EXIT
```

The complete operation set is in
[constants.md](constants.md#fpcmainasm): binary ops &00–&1F, control/stack
ops &20–&34 (jumps take a signed displacement byte; `ONELIT`/`FIVELIT`
take inline literals), functions &39–&5D, memory store/recall &C8–&DD,
constants &E0–&F0. Notes:

* **B register**: the B you hold at the `RST &28` is captured into `BCREG`
  and is what `STKBREG` (&23), `LDBREG` (&21), `DECB` (&22) and `USEB`
  (&24) operate on. BC is restored on exit.
* **Memories**: `STO`/`RCL` 0–5 use the area pointed to by `MEM` (&5C68) —
  by default the six slots at `MEMVAL` (&5121). If BASIC might be using
  them (FOR/NEXT does), point `MEM` at 30 bytes of your own first.
* **Termination**: always end with `EXIT` (&33). `EXIT2` (&34) additionally
  unwinds the RST frame and is only meaningful in ROM-internal contexts —
  do not use it from your own code.
* **Errors**: overflow, "FPC error" etc. execute `RST &08` and long-jump to
  BASIC's error handler via `ERRSP` — your code after the RST will *not*
  regain control. If you need to survive errors, push an error frame first
  (`SETESP` idiom: save `ERRSP`, point it at your own SP with a recovery
  address on the stack) or pre-validate ranges.
* The `RST28V` vector (&5AF0) sees every operation byte before dispatch,
  for extending the instruction set.

### Reading the result

* `GETINT` (&0121): BC/HL = integer (raises BASIC error 30 if negative or
  out of range — see the error caveat above).
* `STKFETCH` (&0124): pops the raw 5 bytes into A,E,D,C,B — safe for any
  value; decode the forms yourself.
* Or read the 5 bytes at (`STKEND`)−5 and subtract 5 from `STKEND`.

## CALL, USR and USR$: parameters and results

### How the start address is passed and mapped

All three keywords take a numeric expression as the start address, evaluate
it onto the calculator stack, and hand it to the shared trampoline `CALLX`
(eval.asm), which pops it and resolves it through `PDPSUBR` (misc1.asm) —
the same 0–524287 address scheme used by PEEK/DPEEK/POKE. The value is
interpreted **relative to the context base page** (page 0 for a normal
BASIC program), and the ROM pages the target in for you:

| Address argument $ N $ | Executes at | Paging while your code runs |
|---|---|---|
| 0 – 16383 | &0000 + N | ROM0 (section A) — i.e. you can CALL ROM0 routines directly |
| 16384 – 32767 | &4000 + (N − 16384) | The base (system) page, section B |
| 32768 – 49151 | &8000 + (N − 32768) | Page base+1 selected into section C |
| 49152 – 65535 | &C000 + (N − 49152) | URPORT = base+1, so the code runs in base+2 via section D |
| ≥ 65536 | &8000 + (N mod 16384) | Page base + $ \lfloor N/16384 \rfloor $ − 1 selected into section C |

(That last row is why the ReadMe's `CALL 229385` reaches offset 9 of RAM
page 13 on a 256K machine: $ 229385 = 14 \times 16384 + 9 $.)

**Register state on entry to your routine** (`CALLX`):

| Register | Contents |
|---|---|
| HL | The mapped entry address — i.e. the address your code is running at |
| BC | A copy of the same entry address |
| A | `CALL` only: the number of parameters (from `TEMPB3`); junk for USR/USR$ |
| IX | Saved by the ROM and restored after you return |
| SP | The normal machine stack; a plain `RET` returns to the ROM |

The original URPORT (section C/D paging) is restored after your `RET`, so
you may repage freely. So the start address is not "passed in" as data you
must decode — it *is* your execution address, pre-mapped, and it is also
handed to you in HL and BC (useful for position-independent code that wants
to know where it is; note that for `USR` this means **BC arrives holding
the entry address and must be overwritten with your result**).

### How CALL passes parameters

`CALL address, p1, p2, …, pn` (misc31.asm `CALLER`) evaluates the address,
then each parameter left to right. After each parameter it also stacks a
**type entry**, keeping the address on top; the address is consumed by the
paging code just before your routine is entered. On entry to your code:

* **A** = number of parameters (0–15; also in `TEMPB3`).
* The calculator stack holds, from bottom to top:

```text
value(p1)  type(p1)  value(p2)  type(p2)  …  value(pn)  type(pn)
                                                        ↑ top (STKEND)
```

* **IX** is saved/restored by the ROM; all other registers are yours.
  Return with `RET` (the stack is otherwise clean); execution continues at
  the next statement.

**Type entries** are 5-byte small integers whose value is the `FLAGS` byte
captured after evaluating that parameter. The only meaningful bit is
**bit 6: 1 = numeric, 0 = string** (other bits — e.g. bit 7 "running" — are
incidental and should be masked off).

**Value entries** are either a 5-byte number (integer or FP form) or, for
strings, a descriptor `page+flags, start-lo, start-hi, len-lo, len-hi`.
Bit 7 of the page byte is an internal "delete after use" flag — mask the
page with &1F. The address is in the &8000–&BFFF window of that page; if
`start+len` crosses &C000, continue in the next page.

### Retrieving them

Pop from the top, i.e. **parameters come off in reverse order** (pn first),
alternating type/value. For each parameter:

```z80
        CALL &0124          ; STKFETCH -> type entry: D = FLAGS value
        BIT  6,D
        JR   Z,is_string

        CALL &0124          ; numeric: A,E,D,C,B = the 5-byte number
        ;    (or CALL &0121 GETINT if you want an integer in BC,
        ;     but note it can raise BASIC error 30)
        JR   next_param

is_string:
        CALL &0124          ; A = page+flags, DE = start, BC = length
        AND  &1F            ; usable page number
        ;    page it into section C: keep URPORT's top bits
        LD   L,A
        IN   A,(251)
        AND  &E0
        OR   L
        OUT  (251),A        ; string text now at DE, length BC
```

(`SBUFFET`, &012A, is a convenient alternative for strings ≤ 255 bytes: it
copies the text into `INSTBUF` at &4F00 for you.)

**Consume all 2n entries.** CALL provides no result channel and does not
clean the stack for you; leftovers linger until the program ends (they
won't crash anything, but they leak calculator-stack space and `STKEND`
must be balanced if BASIC is to keep evaluating expressions correctly).

### Returning values

`CALL` itself cannot return a value — a routine that must hand results back
should either write them into memory the BASIC program can `PEEK`/`DPEEK`
(or into a pre-dimensioned string/array whose address was passed as a
parameter — write through the passed descriptor), or be invoked as a
function instead:

* **`USR address`** — numeric result. The ROM arranges the return so that
  whatever your routine leaves in **BC** is stacked as the function's value
  (0–65535). Remember that BC arrives holding the entry address (see
  [above](#how-the-start-address-is-passed-and-mapped)), so a routine that
  returns nothing meaningful still returns *something* — load BC
  deliberately. Type is implicitly numeric; you cannot signal anything else.
* **`USR$ address`** — string result. On your `RET`, the ROM stacks
  **A = page, DE = start, BC = length** as a string descriptor (`STKSTOS`
  also clears FLAGS bit 6, marking the expression result as a string). The
  text must be somewhere stable — workspace obtained via `WKROOM` (&0109)
  is the intended place.

USR/USR$ receive **no data parameters**: their single numeric argument is
the start address itself, consumed by the mapping described
[above](#how-the-start-address-is-passed-and-mapped) (it reaches your code
only as the entry address in HL/BC — nothing is left on the calculator
stack). Pass data to them through memory, or use CALL when you need the
full parameter machinery and results via memory.

Type information, in both directions, is therefore: *incoming* — the
explicit type entries on the calculator stack (bit 6 of the captured FLAGS
value); *outgoing* — determined by the keyword used (`USR` numeric, `USR$`
string), never by the machine code at run time.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
