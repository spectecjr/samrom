# Extending SAM BASIC — New Commands, Functions, Operators and External Commands

How to add your own keywords to the interpreter: what the ROM offers, what it
does *not* offer, where your code has to live, and four complete worked
examples that assemble.

This is the detailed companion to
[user-manual/15-expert-techniques.md §15.7](user-manual/15-expert-techniques.md#157-extending-basic),
which sketches the same ground in a paragraph.

Sources: [mainlp.asm](../mainlp.asm) (`STMTLP3`, `LINESCAN`), [eval.asm](../eval.asm)
(`ABOVLETS`, `OPERATOR`, `IMFNATAB`, `OPPRIORT`, `FNPRIORT`),
[miscx2.asm](../miscx2.asm) (`TOKPT2`, `POSFIRST`), [scrsel2.asm](../scrsel2.asm)
(`GETTOKEN`), [fpcmain.asm](../fpcmain.asm) (`FPCMAIN`, `BREGEN`, `FPATAB`),
[tprint.asm](../tprint.asm) (`PRGR80`, `PRGR802`, `POGEN`), [misc2.asm](../misc2.asm)
(the syntax helpers), [text.asm](../text.asm) (`KEYWTAB`, `CMDADT`),
[vars.asm](../vars.asm) (the vector table).

---

## Contents

1. [What the ROM actually provides](#1-what-the-rom-actually-provides)
2. [Where your code has to live](#2-where-your-code-has-to-live)
3. [The interception points](#3-the-interception-points)
4. [The token budget](#4-the-token-budget)
5. [Services your hook may call](#5-services-your-hook-may-call)
6. [Worked example 1 — claiming a reserved command token](#6-worked-example-1--claiming-a-reserved-command-token)
7. [Worked example 2 — a new command with a new spelling](#7-worked-example-2--a-new-command-with-a-new-spelling)
8. [Worked example 3 — a new function and a new operator](#8-worked-example-3--a-new-function-and-a-new-operator)
9. [External commands](#9-external-commands)
   * [9.1 What the ROM's authors intended](#91-what-the-roms-authors-intended)
   * [9.2 Three routes, compared](#92-three-routes-compared)
   * [9.3 Route A — the dot form, resolved at run time](#93-route-a--the-dot-form-resolved-at-run-time)
   * [9.4 Route B — DEF PROC-style calling buffers](#94-route-b--def-proc-style-calling-buffers)
   * [9.5 XCMDP — a chainable registry](#95-xcmdp--a-chainable-registry)
   * [9.6 How a resident DOS does it differently](#96-how-a-resident-dos-does-it-differently)
   * [9.7 B-DOS and dot commands](#97-b-dos-and-dot-commands)
10. [Chaining, uninstalling and surviving NEW](#10-chaining-uninstalling-and-surviving-new)
11. [Checklist and pitfalls](#11-checklist-and-pitfalls)

---

## 1. What the ROM actually provides

Adding a keyword to SAM BASIC means solving four separate problems, and the
ROM gives you a hook for each:

| Problem | Hook | System variable |
|---|---|---|
| The tokeniser must turn your word into a token | `MTOKV` | 23290 (&5AFA) |
| The lister must turn it back into text | `PRTOKV` | 23262 (&5ADE) |
| The statement dispatcher must run it (commands) | `CMDV` | 23284 (&5AF4) |
| The evaluator/calculator must evaluate it (functions, operators) | `EVALUV`, `RST28V` | 23286, 23280 |

Every one of them is a 16-bit address in the system-variable vector table
that the ROM checks for zero before calling. All start at zero on a cold
machine, and **`NEW` does not clear them** — see §10.

### Two things the ROM does *not* do

Both are widely believed, and neither is true of ROM 3.0:

* **The ROM has no external-command mechanism.** `XCMDP` (23051) is
  documented as "page/address of the first external command list" and is
  initialised to &FF ("none") by the cold start — but **no ROM code ever
  reads it**. A statement beginning with `.` reaches `PROCS`, whose first act
  is `GETALPH`, which accepts only `A`–`Z` and `a`–`z`; so `.dir` gives
  *Not understood* (29) on a bare machine.
* **The `CALLBUFEXT` bit (bit 6 of a call buffer's page byte) is never set
  by the ROM.** `PROCS` tolerates it — it tests only bit 5 for "no
  definition", and `TSURPG` masks the page to five bits — but nothing
  produces it. The compile pass resolves `PROC` call buffers against
  `DEF PROC` statements and nothing else.

Both gaps are the *same* unfinished feature, and the original source is
explicit about what it was meant to be. [§9](#9-external-commands) quotes the
authors' own comments, reconstructs the design, and finishes it.

### The shape of the pipeline

```
EDITOR      collect keystrokes into the edit line
TOKMAIN     tokenise:  keyword table  ->  (miss)  ->  MTOKV
LINESCAN    syntax-check:  statements  ->  CMDV
                           expressions ->  EVALUV
INSERTLN    store the line
...
COMPILE     resolve FN/PROC call buffers
LINERUN     execute:       statements  ->  CMDV
                           expressions ->  EVALUV  ->  RST28V
LIST        detokenise:                     PRTOKV
```

Note that `CMDV` and `EVALUV` are reached **twice** for every line: once
during the syntax pass and once per execution. Your hook must distinguish
them — see §5.

---

## 2. Where your code has to live

This is the first practical obstacle, and it is worth settling before
writing a line of Z80.

### The constraint

When any of these hooks fires, the Z80 sees:

| Section | Addresses | Contents |
|---|---|---|
| A | &0000–&3FFF | ROM 0 |
| B | &4000–&7FFF | The system page (physical page 0) |
| C | &8000–&BFFF | Whatever the interpreter was working on — usually the program |
| D | &C000–&FFFF | The page above C's, or ROM 1 |

Section C changes constantly, and section D is ROM 1 whenever the ROM is
running ROM 1 code — which includes `RST28V` (the calculator lives in ROM 1)
and `PRTOKV` (the print path does too). **The only RAM that is always
addressable is the system page, &4000–&7FFF.** Your hook body must start
there, even if it immediately pages something else in.

### Free space in the system page

| Region | Size | Verdict |
|---|---|---|
| &5881–&58DF (22657–22751) | 95 bytes | The only genuinely unused hole |
| &5A12–&5A2E (23058–23086) | 29 bytes | Reserved for a `DUMP` driver's own use |
| &5BE0–&5BED (23520–23533) | 14 bytes | `PAGER`, "reserved for a paging subroutine" |
| 23649–23652 | 4 bytes | `ZIPLIB`/`ZIPTEMP`, reserved for a third-party compiler |
| Assorted gaps in the &5C00 block | 1–8 bytes each | Trampoline fragments only |
| &4BA0–&4BFF | 96 bytes | Nominally spare, but the interrupt stack descends through it — **unsafe** |

95 bytes is enough for one small hook (example 1 is 53 bytes) and nothing
more.

### Carving as much room as you need

`PROG` (23200) holds the start of the BASIC program area, and nothing outside
the cold start ever resets it. Raising it moves the whole BASIC area up and
leaves a permanent hole below, starting at **23765 (&5CD5)** — which is in
the system page and therefore always addressable.

```basic
10 DPOKE 23200, DPEEK 23200 + 352      : REM carve 352 bytes at 23765
20 LOAD "myprog" LINE 10
```

The hole is stable: `MAKEROOM`/`RECLAIM` never disturb anything below the
point of change, and `LOAD` of a BASIC program rebuilds the area from the
*current* `PROG`. [hudg.md](hudg.md#a-raise-prog-and-carve-space-below-the-program)
works the technique through in full, including why you must not use `NEW`
between the poke and the load, and why a disc auto-load program is the
cleanest place to do it.

Everything below assumes the hole starts at 23765.

### Anything larger

For a substantial extension, put a trampoline in the hole and the body in a
page of its own reserved with `OPEN 1`. The trampoline must:

1. Evaluate any arguments **first**, while the program is still in section C
   (the jump-table routines in §5 do their own paging and leave it as they
   found it).
2. Save `HMPR` (port 251), page its own page into section C, do the work,
   restore `HMPR`.

Because `HMPR` selects sections C **and** D together (D is C's page plus
one), you cannot page your code into D independently; section C is the only
window available, and using it means the program is not addressable while
your code runs.

---

## 3. The interception points

Each contract below is taken from the call site in the ROM.

### 3.1 `CMDV` — the statement dispatcher (23284)

Called from `STMTLP3` in [mainlp.asm](../mainlp.asm), for **every statement**,
on both the syntax pass and every execution.

| | |
|---|---|
| **Entry** | `A` = the first significant byte of the statement (a command token, a letter, or anything else) |
| | `CHAD` points at that byte — the token has **not** been stepped over |
| | `HL` = the vector value itself (the ROM enters through `JP (HL)`) |
| | Machine stack: `[return into the dispatcher]` `[NEXTSTAT]` |
| **Paging** | ROM 0 at &0000, system page at &4000, the program in section C |
| **To decline** | `RET` with `A` unchanged. The ROM stores `A` in `CURCMD`, subtracts &90 and dispatches normally |
| **To re-map** | `RET` with a *different* command token in `A`; the ROM dispatches that instead |
| **To handle it** | `POP HL` to discard the dispatcher's return, do the work, `RET` — which returns to `NEXTSTAT` |

`NEXTSTAT` performs the end-of-statement check for you: it insists on `:`,
`THEN` or a carriage return and reports *Not understood* otherwise. Your hook
does not need to check.

### 3.2 `EVALUV` — the expression evaluator (23286)

Called from `ABOVLETS` in [eval.asm](../eval.asm) as soon as the evaluator
meets the two-byte function prefix &FF.

| | |
|---|---|
| **Entry** | `A` = `E` = the **internal** function code, which is the stored code minus &1A |
| | `CHAD` points at the stored code byte (just past the &FF) |
| | Machine stack: `[return into the evaluator]` |
| **To decline** | `RET` with `A` unchanged |
| **To re-map** | `RET` with a different internal code in **both `A` and `E`** — `A` selects the dispatch path, `E` becomes the operation the calculator will be given |

`EVALUV` is a *remapping* hook, not an implementation hook: the evaluator's
continuation points (`NUMCONT`, `STRCONT`) are not published, so a hook
cannot leave a value stacked and rejoin the scan. Implement the work in
`RST28V` instead and let the evaluator queue it — that is what §8 does.

### 3.3 `RST28V` — the floating-point calculator (23280)

Called from `BREGEN` in [fpcmain.asm](../fpcmain.asm) before **every**
calculator opcode is dispatched, including the ones the expression evaluator
queues through `USEB`.

| | |
|---|---|
| **Entry** | `A` = the opcode, `DE` = `STKEND`, `IX` points past the opcode |
| **Paging** | ROM 1 is in section D — so your hook must be in the system page, and must not disturb `LMPR` |
| **Operands** | Unary: the entry is at `DE`−5. Binary: at `DE`−10 and `DE`−5 |
| **To decline** | `RET` with `A` unchanged |
| **To handle it** | `POP HL` to discard the return, do the work, leave `DE` = the new `STKEND`, `RET` — which returns to `FPCLP`, the calculator's main loop |

`FPCLP` begins each iteration with `LD (STKEND),DE`, which is why `DE` must
be correct on return. The ROM's own `FPBOR`/`FPBAND` are the model to copy:
`GETINT` twice, combine, `STACKBC`.

### 3.4 `MTOKV` — the tokeniser (23290)

Called from `POSFIRST` in [miscx2.asm](../miscx2.asm) whenever a word fails
to match the ROM's own keyword table.

| | |
|---|---|
| **Entry** | `DE` points at a **15-byte copy** of the candidate word, made in the code buffer. There is no terminator — the copy simply contains whatever followed the word in the line |
| **Paging** | The tokeniser runs from RAM at &4D80 with ROM 1 paged **out** |
| **To decline** | Return with `Z` set (e.g. `XOR A : RET`) |
| **To accept** | Return `NZ`, with `A` = a keyword index, `HL` = the word's start in the copy, `DE` = the first character after it |

The index is in the ROM's own numbering, and the tokeniser converts it:

| Index | Produces |
|---|---|
| 1 – &49 | The two-byte function token `&FF` + (index + &3A) |
| &4A – &FF | The single-byte command token (index + &3B) |

So to emit command token *T*, return *T* − &3B; to emit function code *F*,
return *F* − &3A. Index &C4 is unusable: it would produce &FF, which the
tokeniser special-cases into the `PEN` token (that is how `INK` becomes a
synonym for `PEN`).

You must apply the ROM's own rule for what may follow a keyword: a match is
rejected if the next character is a letter, `$` or `_`. That is what stops
`PRINTER` being tokenised as `PRINT` + `ER`, and your hook must do the same
or your keyword will swallow variable names.

### 3.5 `PRTOKV` — the lister (23262)

Called from `PRGR802` in [tprint.asm](../tprint.asm) for every byte of &85 or
above that is being printed **as a token** rather than as a graphic
character. (Inside quotes and in an `INPUT` line the ROM branches away
before reaching the hook, so string data never gets here.)

| | |
|---|---|
| **Entry** | `A` = the byte about to be expanded |
| | Machine stack: `[return into the lister]` |
| **To decline** | `RET` with `A` unchanged — the ROM then expands it from `KEYWTAB` |
| **To handle it** | Print your own text, `POP HL` to discard the lister's return, `RET` |

The ROM's spacing rule, from `POGEN`:

* Print a leading space **unless** bit 0 of `FLAGS` (23611) is set, which
  means a space was just printed.
* Print a trailing space if the keyword's last character is a letter or `$`.

**A function token only offers you its prefix.** A two-byte function is
printed as &FF followed by the code, and `PRTOKV` sees only the &FF; the
ROM's own `POFN` collects the second byte by diverting the channel's output
routine for one character. To intercept a function or operator token you must
do the same thing — §8 shows how.

### 3.6 `CMDADDRT` — replacing the command address table (23514)

The dispatcher indexes a table of routine addresses with
(token − &90) × 2, and the table's base is a system variable. Pointing it at
a copy of your own is a table-driven alternative to `CMDV`.

Three constraints make it the harder route:

* The table is 206 bytes (tokens &90–&F6) and the dispatcher **pages ROM 1
  in** to read it, so your copy must live at &0000–&BFFF — in practice the
  system page, which means carving room for it as well as for your code.
* The original table is in ROM 1 at a fixed address, so building a copy means
  machine code that pages ROM 1 in and copies 206 bytes.
* Tokens &F7–&FE are rejected by `CP TOK_CMDLAST-TOK_CMDFIRST` **before** the
  table is consulted, so they can never be reached this way.

If your routine's address has bit 15 set the dispatcher leaves ROM 1 paged
in; a system-page address (&4xxx–&7xxx) has bit 15 clear, so ROM 1 is paged
out before you are entered — which is what you want.

### 3.7 `RST8V` — the error handler (23278)

Called from `ERROR2` in [misc2.asm](../misc2.asm) for **every** error, report
and DOS hook code, before the ROM decides what to do with it. It is the hook
that lets a utility trap a failure and repair it.

| | |
|---|---|
| **Entry** | `A` = the error code, `DE` -> the code byte (the `DB` after the `RST &08`) |
| | `AF'` holds the erroring routine's `AF`; `BC` is whatever it left |
| | `XPTR`/`XPTRP` have already been set to the error position |
| | Machine stack: `[return into ERROR2]` `[address just past the DB byte]` `…the erroring routine's own stack…` |
| **To decline** | `RET`. Note that the ROM **re-reads the code from `(DE)`** afterwards, so changing `A` achieves nothing |
| **To handle it** | Do not return normally — take control, using the stack layout below |

Two things follow from that entry contract, and both matter:

* **You cannot change the error by changing `A`.** The sequence after the
  call is `LD A,(DOSCNT) : RRCA : LD A,(DE)`, which reloads the code. To
  substitute a different error, raise it yourself.
* **`RET`ting past the `DB` byte is almost never safe.** The second word on
  the stack points at the byte *after* the code, which for most error sites
  is the middle of an unrelated routine. For error 12 it is `PROCSY`, the
  routine that builds a call buffer — running that at execution time would
  corrupt the line.

So a hook that handles an error must know what the stack looked like at the
`RST &08`. That is site-specific, and has to be justified per error. The one
this document uses is worth spelling out:

> **Error 12 (*Missing DEF PROC*) is raised at `MDPERR`, and `PROCS` pushes
> nothing between the dispatcher's `PUSH DE` and that `RST &08`.** So the
> third word on the stack is `NEXTSTAT`, and a hook can `POP` twice and then
> `RET` to continue with the next statement exactly as a command routine
> would. §9.4 does this.

`RST8V` is offered the code **before** a resident DOS sees it, and before the
"is this a hook code?" test, so a hook can intercept codes of 128 and above
as well.

### 3.8 Diverting existing behaviour

These are not for adding keywords but for replacing what the ROM already
does. All follow the same "zero means not installed" convention.

| Vector | Address | Diverts |
|---|---|---|
| `DMPV` | 23258 | `DUMP` — the ROM has no printer driver, so this does nothing until you install one |
| `SETIYV` | 23260 | Plot-routine selection |
| `NMIV` | 23264 | The NMI (super-break) button |
| `FRAMIV` | 23266 | The frame interrupt, 50 times a second |
| `LINIV` | 23268 | Line interrupts |
| `COMSV` | 23270 | The communications interrupt |
| `MIPV` / `MOPV` | 23272 / 23274 | MIDI in and out |
| `EDITV` | 23276 | Editor entry |
| `RST8V` | 23278 | Every error, before it is acted on — see [§3.7](#37-rst8v--the-error-handler-23278) |
| `RST30V` | 23282 | `RST &30` issued from outside ROM 0 |
| `LPRTV` | 23288 | `LPRINT` output |
| `MOUSV` | 23292 | Mouse reading, from the frame interrupt |
| `KURV` | 23294 | Cursor drawing |
| `ANYIV` | 23408 | Every maskable interrupt, before the source is demultiplexed |
| `PATOUT` | 23506 | The routine that renders one printable character — replace it for a proportional or custom font engine |
| `ERRMSGS` | 23508 | The error message table |
| `UMSGS` | 23510 | The utility message table |
| `KBTAB` | 23512 | The keyboard translation table |

---

## 4. The token budget

### Command tokens

| Token | Spelling | Status |
|---|---|---|
| &90 `DIR`, &91 `FORMAT`, &92 `ERASE`, &93 `MOVE` | already in the keyword table | Reserved for DOS; the table entry is *Not understood*. **Free on a machine with no DOS** |
| &CE `REF` | already spelled | Only meaningful inside a `DEF PROC` parameter list; as a statement it is *Not understood* |
| &CF `COPY` | already spelled | Reserved for DOS, unimplemented |
| &E3 `RENAME`, &F1 `PROTECT`, &F2 `HIDE` | already spelled | Reserved for DOS, unimplemented |
| **&D0** | none — the keyword table holds a `-` placeholder | Genuinely free, and reachable through both `CMDV` and `CMDADDRT` |
| **&F7–&FE** | none | Genuinely free, but reachable **only** through `CMDV` |

Claiming a token that already has a spelling is far the easiest route: the
tokeniser and the lister already work, and you need only `CMDV`.

### Function codes

The evaluator subtracts &1A from the stored code, then routes it:

| Internal code | Route |
|---|---|
| below &39 | *Immediate* — dispatched through `IMFNATAB`, a table in ROM |
| &39 – &4E | Queued for the calculator with priority 15, numeric in, numeric out |
| &4F – &5C | Queued for the calculator with a priority byte from `FNPRIORT` |
| &5D and above | Rejected — *Not understood* |

Which leaves:

| Stored code | Internal | Verdict |
|---|---|---|
| &49, &4E, &51, &52 | &2F, &34, &37, &38 | Immediate slots whose table entries are *Not understood*. The table is in ROM and the evaluator's continuation points are not published, so **treat these as unusable** |
| **&68** | &4E | **Free.** Priority 15, numeric argument, numeric result. Calculator opcode &4E is unused |
| **&6A** | &50 | **Free.** Priority 15, **string** argument, numeric result. Calculator opcode &50 is unused |
| &75 | &5B | **Taken** — opcode &5B is `INKEY$ #n`, which the evaluator queues for the stream form of `INKEY$` |
| &77–&79 | &5D–&5F | **Unusable** — the evaluator rejects internal codes of &5D and above |

So there are exactly **two** free function slots, and their argument and
result types are fixed by the ROM's priority tables. You cannot choose them,
and you cannot write a function that takes no argument or more than one —
for those, use a command, or a bracketed syntax parsed by a `CMDV` hook.

### Operator codes

| Stored code | Internal operation | Verdict |
|---|---|---|
| **&7D** | &0B | **Free.** The slot the never-implemented `BXOR` was allocated. Priority 2, numeric operands, numeric result; `FPATAB` entry &0B is *Not understood* |

Because &0B is below the `AND` code (&0E), the evaluator rejects `$ op $`
for it at syntax-check time, which is the correct behaviour for a bitwise
operator.

---

## 5. Services your hook may call

The public jump table at &0100 handles its own paging, so these are safe to
call from anywhere — including from a `RST28V` hook with ROM 1 paged in.

| Address | Name | Contract |
|---|---|---|
| &0010 | `RST &10` | Print the character in `A` |
| &0013 | `PRINTSTR` | Print `BC` bytes from `(DE)` |
| &0018 | `RST &18` | `A` = the significant character at `CHAD`; `HL` = `CHAD` |
| &0020 | `RST &20` | Advance `CHAD`, then as `RST &18` |
| &0118 | `EXPT1NUM` | Evaluate a numeric expression at `CHAD`. `CY` if running; `A` = the terminating character |
| &011B | `EXPTSTR` | The same for a string expression |
| &011E | `EXPTEXPR` | Either kind; `Z` = string, `NZ` = numeric, `CY` = running |
| &0121 | `GETINT` | Pop the calculator-stack top as an integer into `BC` (and `HL`, `A` = `C`). Raises error 30 if negative or ≥ 65536 |
| &0124 | `STKFETCH` | Pop five raw bytes into `A, E, D, C, B` |
| &0127 | `STKSTORE` | Push `A, E, D, C, B`. For an integer: `A` = 0, `E` = sign, `D` = low, `C` = high, `B` = 0. Returns `HL` = the new `STKEND` |
| &012A | `SBUFFET` | Pop a string descriptor and copy the text to `INSTBUF` (&4F00). Exit `DE` = &4F00, `BC` = `A` = length. Raises error 27 if the string is empty or longer than 255. **Restores paging** |
| &0109 | `WKROOM` | Open `BC` bytes of workspace; `DE` = start |
| &012D / &0130 | `FARLDIR` / `FARLDDR` | Cross-page block copy |
| &0166 | `KBFLUSH` | Empty the keyboard queue |
| &0169 | `READKEY` | Read the keyboard |

### Raising an error

```z80
        RST &08
        DB  29                  ; Not understood
```

This never returns: the handler resets the stack pointer from `ERRSP`. The
full list of codes is in
[user-manual/appendix-b-error-messages.md](user-manual/appendix-b-error-messages.md).

### Telling the syntax pass from execution

`FLAGS` bit 7 (`FLAGS` is 23611) is set while running and clear while
checking:

```z80
        LD A,(&5C3B)
        RLA                     ; bit 7 -> CY
        RET NC                  ; syntax pass
```

`EXPT1NUM`, `EXPTSTR` and `EXPTEXPR` return the same information in the carry
flag, so in practice you write:

```z80
        CALL &0118              ; EXPT1NUM
        RET NC                  ; checking: the argument has been validated, nothing else to do
```

At check time the expression routines validate types and shapes and insert
the invisible five-byte constants into the line, but stack nothing. A hook
that returns at that point leaves the interpreter to move on to the next
statement.

---

## 6. Worked example 1 — claiming a reserved command token

`MOVE x, y` moves the graphics position without plotting anything — something
SAM BASIC genuinely lacks. `MOVE` is token &93, already in the keyword table
and already listed correctly, so **only `CMDV` is needed**.

The graphics position lives in `XCOORD` (23106, two bytes) and `YCOORD`
(23105, one byte), and `YCOORD` is stored inverted: scan 0 is the top of the
screen. The conversion from BASIC's convention is
scan = 191 − (*y* + `ORGOFF`), where `ORGOFF` (23132) is twice the character
height.

```z80
; MOVE x,y  -- claim the DOS-reserved token &93 through CMDV
CHAD:       EQU &5A97
YCOORD:     EQU &5A41
XCOORD:     EQU &5A42
ORGOFF:     EQU &5A5C
EXPT1NUM:   EQU &0118
GETINT:     EQU &0121

            ORG &5881               ; the 95-byte hole in the system page

MOVEHK:     CP &93                  ; the MOVE token?
            RET NZ                  ; no: let the ROM dispatch as usual

            POP HL                  ; discard the return into the dispatcher
            RST &20                 ; step CHAD past the token
            CALL EXPT1NUM           ; x
            CP ","
            JR NZ,MVNON
            RST &20
            CALL EXPT1NUM           ; y; CY if running
            RET NC                  ; syntax pass: arguments check out, so stop here

            CALL GETINT             ; y comes off first
            LD A,C
            PUSH AF
            CALL GETINT             ; then x
            LD A,B
            AND A
            JR NZ,MVOFF             ; x above 255
            LD (XCOORD),BC
            POP AF
            LD B,A
            LD A,(ORGOFF)
            ADD A,B
            LD B,A                  ; y + ORGOFF
            LD A,191
            SUB B                   ; scan = 191 - (y + ORGOFF)
            JR C,MVOFF
            LD (YCOORD),A
            RET                     ; -> NEXTSTAT

MVOFF:      RST &08
            DB 32                   ; Off screen

MVNON:      RST &08
            DB 29                   ; Not understood
```

53 bytes, so it fits the stock hole with room to spare.

### Loader

```basic
   10 REM install MOVE
   20 RESTORE 1000
   30 FOR i = 22657 TO 22657+52: READ b: POKE i,b: NEXT i
   40 DPOKE 23284, 22657              : REM CMDV
   50 PRINT "MOVE installed"
   60 STOP
 1000 DATA 254,147,192,225,231,205,24,1,254,44,32,39,231,205,24,1
 1010 DATA 208,205,33,1,121,245,205,33,1,120,167,32,20,237,67,66
 1020 DATA 90,241,71,58,92,90,128,71,62,191,144,56,4,50,65,90
 1030 DATA 201,207,32,207,29
```

### Trying it

```basic
MODE 4: CLS
MOVE 20,20
DRAW 100,0
MOVE 20,120: DRAW 100,0
```

Because `MOVE` was already a keyword, `LIST` shows it correctly and `RENUM`,
`EDIT` and everything else work with no further effort. **This is by far the
cheapest way to add a command**, and worth taking whenever one of the eight
reserved DOS spellings suits your purpose.

> Do not install this alongside a DOS, which will want `MOVE` for itself.

---

## 7. Worked example 2 — a new command with a new spelling

`CENTRE a$` prints a string centred in the current window. There is no
reserved spelling for it, so all three of `MTOKV`, `CMDV` and `PRTOKV` are
needed, and it takes token &D0.

This example is combined with example 3 into a single resident block, since
in practice one extension installs all its hooks together. The full listing
is in §8; the parts belonging to `CENTRE` are:

```z80
TCENTRE:    EQU &D0                 ; free command token

; --- the keyword table entry: index, length, text ---
            DB TCENTRE-&3B, 6       ; index &95 -> command token &D0
            DM "CENTRE"

; --- CMDV ---
CMDHK:      CP TCENTRE
            RET NZ                  ; not ours: let the ROM dispatch normally

            POP HL                  ; discard the dispatcher's return, so our RET goes to NEXTSTAT
            RST &20                 ; step CHAD past the token
            CALL EXPTSTR            ; CY if running
            RET NC                  ; the syntax pass has nothing more to do

            CALL SBUFFET            ; DE -> the text, BC = A = its length
            PUSH DE
            PUSH BC
            LD A,(WINDRHS)
            LD H,A
            LD A,(WINDLHS)
            NEG
            ADD A,H
            INC A                   ; the window width in columns
            SUB C                   ; less the length of the string
            JR NC,CEHALF

            XOR A                   ; longer than the window: no indent

CEHALF:     RRA                     ; half of it; carry is clear either way
            LD B,A
            INC B
            JR CESKP

CESPL:      LD A," "
            RST &10

CESKP:      DJNZ CESPL

            POP BC
            POP DE
            CALL PRINTSTR
            LD A,13
            RST &10                 ; end the line
            RET
```

Points worth noticing:

* **`POP HL` first.** Everything after it returns to `NEXTSTAT` rather than
  back into the dispatcher.
* **`RST &20` before parsing.** `CHAD` still points at the command token when
  `CMDV` is called.
* **`RET NC` after `EXPTSTR`.** On the syntax pass the argument has been
  type-checked, which is all that pass needs; returning here is exactly what
  the ROM's own `SYNTAXA` helper does.
* **`SBUFFET` does the paging.** The string may be anywhere in memory; the
  jump-table routine copies it to a fixed buffer and restores the paging.
* The indent is measured from the current print position, so `CENTRE` is
  meant to be used at the start of a line.

Because token &D0 has only a `-` placeholder in the keyword table, `LIST`
would show `-` without the `PRTOKV` hook. §8 supplies one.

---

## 8. Worked example 3 — a new function and a new operator

Two more keywords, in the same resident block:

* **`HASH a$`** — a function taking a string and returning a number, on the
  free function code &6A.
* **`BXOR`** — the bitwise exclusive-or the ROM was designed for and never
  got, on the free operator code &7D.

Neither needs `EVALUV`. The evaluator already knows how to parse a
one-argument function and a binary operator; all it needs is a token, and all
the calculator needs is an implementation for the opcode the evaluator
queues.

| Keyword | Stored code | Internal | Priority byte | Signature | Calculator opcode |
|---|---|---|---|---|---|
| `HASH` | &6A | &50 | &8F (from `FNPRIORT`) | string → number | &50 |
| `BXOR` | &7D | operator | &C2 (from `OPPRIORT`) | number, number → number | &0B |

### The complete resident block

```z80
; A resident extension adding CENTRE (command), HASH (function) and BXOR (operator)
CHAD:       EQU &5A97
WINDRHS:    EQU &5A56
WINDLHS:    EQU &5A57
FLAGS:      EQU &5C3B
CURCHL:     EQU &5C51
STKEND:     EQU &5C65

PRINTSTR:   EQU &0013
EXPTSTR:    EQU &011B
GETINT:     EQU &0121
STKSTORE:   EQU &0127
SBUFFET:    EQU &012A

TCENTRE:    EQU &D0                 ; free command token
FHASH:      EQU &6A                 ; free function code: string in, numeric out
FBXOR:      EQU &7D                 ; free operator code
OPHASH:     EQU FHASH-&1A           ; &50 -- the calculator opcode the evaluator queues
OPBXOR:     EQU &0B                 ; BXOR's internal operation code

            ORG &5CD5               ; the hole carved by raising PROG

; =====================================================================================================================
; MTOKV -- give the three words their tokens
;
; Entry:  DE -> a 15-byte copy of the candidate word
; Exit:   NZ, A = keyword index, HL -> the word, DE -> just past it;  or Z if we do not know the word
; =====================================================================================================================

TOKHK:      LD (CAND),DE
            LD HL,KWTAB

TKENT:      LD A,(HL)               ; the index this entry produces, or 0 to end the table
            AND A
            JR Z,TKNO

            LD C,A
            INC HL
            LD B,(HL)               ; name length
            INC HL
            LD DE,(CAND)

TKCMP:      LD A,(DE)
            XOR (HL)
            AND &DF                 ; compare without regard to case
            JR NZ,TKMIS

            INC HL
            INC DE
            DJNZ TKCMP

            LD A,(DE)               ; the character after the word
            CALL ISNAME
            JR C,TKENT              ; a name character follows, so this was not the word after all

            LD HL,(CAND)
            LD A,C                  ; the index; always non-zero, so NZ
            AND A
            RET

TKMIS:      LD C,B                  ; skip the rest of this entry's name
            LD B,0
            ADD HL,BC
            JR TKENT

TKNO:       LD DE,(CAND)
            XOR A                   ; Z: we do not know this word
            RET

; --- ISNAME: CY if A is a letter, '$' or '_' -- the ROM's own rule for what may follow a keyword ---

ISNAME:     CALL ALPHA
            RET C

            CP "$"
            SCF
            RET Z

            CP "_"
            SCF
            RET Z

            AND A
            RET

ALPHA:      CP "A"
            CCF
            RET NC

            CP "z"+1
            RET NC

            CP "Z"+1
            RET C

            CP "a"
            CCF
            RET


; =====================================================================================================================
; CMDV -- execute CENTRE
; =====================================================================================================================

CMDHK:      CP TCENTRE
            RET NZ

            POP HL
            RST &20
            CALL EXPTSTR
            RET NC

            CALL SBUFFET
            PUSH DE
            PUSH BC
            LD A,(WINDRHS)
            LD H,A
            LD A,(WINDLHS)
            NEG
            ADD A,H
            INC A
            SUB C
            JR NC,CEHALF

            XOR A

CEHALF:     RRA
            LD B,A
            INC B
            JR CESKP

CESPL:      LD A," "
            RST &10

CESKP:      DJNZ CESPL

            POP BC
            POP DE
            CALL PRINTSTR
            LD A,13
            RST &10
            RET


; =====================================================================================================================
; RST28V -- perform HASH and BXOR
;
; Entry:  A = the calculator opcode, DE = STKEND, IX past the opcode
; =====================================================================================================================

FPHK:       CP OPHASH
            JR Z,DOHASH

            CP OPBXOR
            RET NZ                  ; not ours: let the calculator dispatch it

; --- BXOR: two numbers in, one out. The ROM's own FPBOR/FPBAND work exactly this way. ---

            POP HL                  ; discard the return into the calculator, so our RET goes to its main loop
            CALL GETINT             ; the right-hand operand
            PUSH BC
            CALL GETINT             ; the left-hand one
            POP HL
            LD A,B
            XOR H
            LD B,A
            LD A,C
            XOR L
            LD C,A
            JR STKBC

; --- HASH: a string in, a number out ---

DOHASH:     POP HL
            CALL SBUFFET            ; pops the string; DE -> the text, A = BC = its length
            LD B,A
            LD HL,0

HSHLP:      LD A,(DE)
            INC DE
            XOR H
            LD H,A
            ADD HL,HL               ; rotate the accumulator left one place
            JR NC,HSHNC

            INC L

HSHNC:      DJNZ HSHLP

            LD B,H
            LD C,L

; --- STKBC: stack BC as a small integer and return to the calculator's main loop ---

STKBC:      LD D,C                  ; value, low byte
            LD C,B                  ; value, high byte
            XOR A
            LD E,A                  ; positive
            LD B,A
            CALL STKSTORE           ; pushes A, E, D, C, B
            LD DE,(STKEND)
            RET


; =====================================================================================================================
; PRTOKV -- list the three words back
;
; A function token is two bytes, &FF then the code, and the ROM only offers us the first. We therefore divert the
; channel's own output routine for exactly one character -- the same trick the ROM uses for its own two-byte
; tokens -- and put it back before doing anything else.
; =====================================================================================================================

PRTHK:      CP TCENTRE
            JR Z,PRTOWN

            CP &FF                  ; the function prefix?
            RET NZ

            LD A,(PASS)
            AND A
            LD A,&FF                ; restore the byte the ROM is expecting
            JR Z,PRTDIV

            PUSH AF                 ; our own re-issued prefix: stand aside for it
            XOR A
            LD (PASS),A
            POP AF
            RET

PRTDIV:     LD HL,(CURCHL)          ; divert the channel to PRTFN for one character
            LD E,(HL)
            INC HL
            LD D,(HL)
            LD (SAVOP),DE
            LD DE,PRTFN
            LD (HL),D
            DEC HL
            LD (HL),E
            POP HL                  ; the prefix has been dealt with
            RET

; --- PRTFN: the diverted output routine, called with the byte that followed the prefix ---

PRTFN:      PUSH AF
            LD HL,(CURCHL)          ; put the channel back first, whatever happens next
            LD DE,(SAVOP)
            LD (HL),E
            INC HL
            LD (HL),D
            POP AF

            CP FHASH
            JR Z,PRTOWN2

            CP FBXOR
            JR Z,PRTOWN2

; Not one of ours, so re-issue the two bytes and let the ROM expand them. PASS makes our hook stand aside for the
; prefix; the ROM's own diversion then collects the code byte.

            PUSH AF
            LD A,1
            LD (PASS),A
            LD A,&FF
            RST &10
            POP AF
            RST &10
            RET

; --- PRTOWN: print our own spelling of the token in A, with the ROM's spacing rule ---

PRTOWN:     POP HL                  ; discard the return into the lister

PRTOWN2:    LD E,A                  ; the token or function code we are looking for
            LD HL,KWTAB

PRTLP:      LD A,(HL)               ; index
            AND A
            RET Z                   ; not in the table after all

            LD C,A
            INC HL
            LD B,(HL)               ; name length
            INC HL
            LD A,C
            ADD A,&3B               ; a command index becomes its token ...
            CP E
            JR Z,PRTGO

            DEC A                   ; ... and a function index its code
            CP E
            JR Z,PRTGO

            LD C,B                  ; no: step over this entry's name
            LD B,0
            ADD HL,BC
            JR PRTLP

PRTGO:      LD C,B                  ; BC = the name length
            LD B,0
            PUSH HL
            PUSH BC
            LD A,(FLAGS)
            RRA                     ; bit 0 set means a space has just been printed
            LD A," "
            CALL NC,&0010           ; the leading space
            POP BC
            POP DE
            CALL PRINTSTR           ; the word itself
            LD A," "
            RST &10                 ; and the trailing space
            RET


; =====================================================================================================================
; The keyword table: index byte, name length, name. A zero index ends it.
;
;   index + &3B = the command token       (indexes &4A and up)
;   index + &3A = the function code       (indexes below &4A)
; =====================================================================================================================

KWTAB:      DB TCENTRE-&3B, 6
            DM "CENTRE"
            DB FHASH-&3A, 4
            DM "HASH"
            DB FBXOR-&3A, 4
            DM "BXOR"
            DB 0

CAND:       DW 0                    ; the candidate word being matched
SAVOP:      DW 0                    ; the channel output address we diverted
PASS:       DB 0                    ; non-zero while a prefix is being re-issued
```

335 bytes, at 23765–24099. Entry points:

| Vector | System variable | Value |
|---|---|---|
| `MTOKV` | 23290 | `TOKHK` = 23765 |
| `CMDV` | 23284 | `CMDHK` = 23846 |
| `RST28V` | 23280 | `FPHK` = 23894 |
| `PRTOKV` | 23262 | `PRTHK` = 23951 |

### Loader

Because the block lives in the hole below `PROG`, installing it takes **two
programs**: a configurator that raises `PROG` and chains to the real one, and
the real one that pokes the code. They cannot be combined, because raising
`PROG` leaves the running program's own text sitting in the hole — only a
`LOAD` rebuilds the area from the new `PROG`. See §2 and
[hudg.md](hudg.md#automating-the-change).

Save this one as `"ext"` first:

```basic
   10 REM ---- ext: poke the code and install the vectors
   20 RESTORE 1000
   30 FOR i = 23765 TO 23765+334: READ b: POKE i,b: NEXT i
   40 DPOKE 23290, 23765                        : REM MTOKV
   50 DPOKE 23284, 23846                        : REM CMDV
   60 DPOKE 23280, 23894                        : REM RST28V
   70 DPOKE 23262, 23951                        : REM PRTOKV
   80 PRINT "CENTRE, HASH and BXOR installed"
   90 STOP
 1000 DATA 237,83,31,94,33,10,94,126,167,40,36,79,35,70,35,237
 1010 DATA 91,31,94,26,174,230,223,32,16,35,19,16,246,26,205,10
 1020 DATA 93,56,228,42,31,94,121,167,201,72,6,0,9,24,216,237
 1030 DATA 91,31,94,175,201,205,24,93,216,254,36,55,200,254,95,55
 1040 DATA 200,167,201,254,65,63,208,254,123,208,254,91,216,254,97,63
 1050 DATA 201,254,208,192,225,231,205,27,1,208,205,42,1,213,197,58
 1060 DATA 86,90,103,58,87,90,237,68,132,60,145,48,1,175,31,71
 1070 DATA 4,24,3,62,32,215,16,251,193,209,205,19,0,62,13,215
 1080 DATA 201,254,80,40,20,254,11,192,225,205,33,1,197,205,33,1
 1090 DATA 225,120,172,71,121,173,79,24,20,225,205,42,1,71,33,0
 1100 DATA 0,26,19,172,103,41,48,1,44,16,246,68,77,81,72,175
 1110 DATA 95,71,205,39,1,237,91,101,92,201,254,208,40,68,254,255
 1120 DATA 192,58,35,94,167,62,255,40,7,245,175,50,35,94,241,201
 1130 DATA 42,81,92,94,35,86,237,83,33,94,17,183,93,114,43,115
 1140 DATA 225,201,245,42,81,92,237,91,33,94,115,35,114,241,254,106
 1150 DATA 40,17,254,125,40,13,245,62,1,50,35,94,62,255,215,241
 1160 DATA 215,201,225,95,33,10,94,126,167,200,79,35,70,35,121,198
 1170 DATA 59,187,40,10,61,187,40,6,72,6,0,9,24,233,72,6
 1180 DATA 0,229,197,58,59,92,31,62,32,212,16,0,193,209,205,19
 1190 DATA 0,62,32,215,201,149,6,67,69,78,84,82,69,48,4,72
 1200 DATA 65,83,72,67,4,66,88,79,82,0,0,0,0,0,0
```

Then this configurator, saved as `"setup"` with `SAVE "setup" LINE 10`:

```basic
   10 REM ---- setup: carve the hole, then chain to "ext"
   20 IF DPEEK 23200 <> 40149 THEN GOTO 50      : REM &9CD5 = not carved yet
   30 DPOKE 23200, DPEEK 23200 + 352
   50 LOAD "ext" LINE 10                        : REM must be the last statement executed
```

`LOAD` rebuilds the whole program area from the *current* `PROG`, so the 352
bytes vacated at 23765 survive it untouched — and the configurator's own text,
which is now sitting in that hole, is discarded. Running `setup` twice is
harmless: the test on line 20 stops the hole being carved a second time.

Boot time is the cleanest moment to do this, since a disc's auto-load program
can be exactly this configurator.

### Trying it

```basic
MODE 4: CLS
CENTRE "SAM COUPE"
CENTRE "an extended BASIC"
PRINT HASH "hello"
PRINT HASH "hellp"
PRINT BIN$ (BIN 1100 BXOR BIN 1010)      : REM 110
LET a = 5 BXOR 3
```

and then `LIST` — every one of the three lists back in its own spelling.

### Why this works

The evaluator needs no help beyond the token. Meeting `&FF &6A` it computes
the internal code &50, looks its priority byte up in `FNPRIORT`, finds
"string argument, numeric result, priority 15", parses one string operand,
and queues operation &50 for the calculator. Meeting `&FF &7D` in operator
position it computes internal operation &0B, finds priority 2 in `OPPRIORT`,
and queues that. All the type checking, the operand order and the precedence
come free.

The calculator then reaches `BREGEN` with the opcode in `A`, calls our
`RST28V` hook, and we do the work and return to its main loop.

Note what the tables give you and what they cost you:

* `HASH` **must** take a string and return a number, because &8F is what
  `FNPRIORT` holds for that slot.
* `BXOR` **must** bind at priority 2 — the same as `OR` and `BOR` — because
  that is what `OPPRIORT` holds for operation &0B.
* `$ BXOR $` is rejected at typing time, because the evaluator only remaps
  operations of code &0E and above into their string variants.

---

## 9. External commands

### 9.1 What the ROM's authors intended

Although the ROM implements nothing, it is unusually clear about what was
*planned*. Four comments in the original source, quoted verbatim, reconstruct
the whole design between them.

**1. The dot was to mark an external command.** In the block of design notes
above the keyword table in [text.asm](../text.asm):

```text
;ALLOW 80-95 IN PROC NAMES SO A FACE SYMBOL CAN BE A COMMAND?
;USE "." FOR EXTERNAL COMMAND
```

Note the question mark on the first line: these are notes to self, and
neither was carried out. `GETALPH` accepts only `A`–`Z` and `a`–`z`, so
neither a symbol character nor a `.` can begin a procedure name.

**2. The calling buffer was to hold machine code addresses.** In `PROCS`
([fn.asm](../fn.asm)), where a `PROC` call reads its buffer:

```text
           LD B,(HL)         ;PAGE
           BIT 5,B
           JR NZ,MDPERR      ;(BIT 7 IS ALWAYS SET, BIT 6=EXTERNAL CMD, BIT 5
                             ;IS SET IF 'NO DEF PROC')
           INC HL
           LD E,(HL)
           INC HL
           LD D,(HL)         ;ADDR OF DEF PROC LINE OR EXEC CODE
           …
           CALL TSURPG       ;SELECT DEF PROC OR EXEC CODE PAGE
```

So the six-byte buffer that follows every `PROC` call was designed to hold
**either** the address of a `DEF PROC` line **or** the entry point of machine
code, with bit 6 of the page byte saying which — and `TSURPG` already pages
that code in.

**3. `XCMDP` was to head a chain of command lists.** From
[vars.asm](../vars.asm):

```text
XCMDP:     EQU VAR2+&0B ;(3) PAGE/ADDR OF FIRST EXTERNAL CMD LIST, OR FFXXXX
```

"**FIRST** external cmd list" — so more than one was expected, which means a
linked chain and a documented way for utilities to add to it.

**4. And it is initialised to "none".** From the cold-start table in
[text.asm](../text.asm):

```text
           DB &FF,0,0    ;XCMDP SHOWS "NO EXTERNAL CMDS"
```

### The one step that was never finished

Everything above exists except the part that would join it up. Nothing sets
bit 6, nothing reads `XCMDP`, and — crucially — **`PROCS` never tests bit 6**.
It checks bit 5 for "no definition" and then treats the address as a
`DEF PROC` line regardless:

```z80
            LD HL,5
            ADD HL,DE         ;SKIP TO FIRST POSSIBLE DEF PROC NAME START POSN
```

So a buffer with bit 6 set would be paged in correctly and then parsed as a
program line. The missing piece is an interception *before* `PROCS` gets
that far — which is exactly what `CMDV` is for, and why a DOS is the natural
place for it to live.

Read that way, the design is coherent and the ROM holds up its end: it
supplies the buffer, the bit, the page-in, the error when resolution fails,
and the two vectors (`CMDV`, `RST8V`) a utility needs to close the loop.
§9.4 closes it.

> Everything in this subsection is quotation plus inference. The quotations
> are exact; the reconstruction is a reading, and the authors are not here to
> confirm it.

### 9.2 Three routes, compared

| | Route A — dot form | Route B — buffered | Route C — a resident DOS |
|---|---|---|---|
| Syntax | `.name args` | `name args` | either |
| Hooks needed | `CMDV` | `CMDV` + `RST8V` | the DOS's own `&4200`/`&4203` entries |
| Name lookup | on every call | once per call site, per compile | DOS's choice |
| Clashes with `DEF PROC` | never | a real `DEF PROC` wins | — |
| Listing | plain text, no work | plain text, no work | — |
| Complexity | ~130 bytes | ~380 bytes | n/a |

Both A and B leave the name in the program as ordinary characters, so
`MTOKV` and `PRTOKV` have nothing to do — which is why external commands are
much the cheapest way to add *many* commands. Only the token routes of §6–8
need tokeniser and lister work.

### 9.3 Route A — the dot form, resolved at run time

The simplest thing that works: recognise `.` in `CMDV`, match the name
against a table, and jump. The cost is a short table search on every
execution.

```z80
; External commands: ".name arguments", dispatched from CMDV
CHAD:       EQU &5A97
FLAGS:      EQU &5C3B
FRAMES:     EQU &5C78
EXPT1NUM:   EQU &0118
GETINT:     EQU &0121
KBFLUSH:    EQU &0166

            ORG &5CD5

; =====================================================================================================================
; CMDV -- a statement beginning with '.' is one of ours
; =====================================================================================================================

XCMD:       CP "."
            RET NZ                  ; not ours: let the ROM dispatch normally

            POP HL                  ; discard the return into the dispatcher
            LD HL,XTAB

XENT:       LD A,(HL)               ; name length; 0 ends the table
            AND A
            JR Z,XNONE

            LD B,A
            PUSH HL
            INC HL                  ; -> the name text
            LD DE,(CHAD)
            INC DE                  ; -> the first character after the '.'

XCLP:       LD A,(DE)
            XOR (HL)
            AND &DF                 ; compare without regard to case
            JR NZ,XMISS

            INC HL
            INC DE
            DJNZ XCLP

            LD A,(DE)               ; the character after the name
            CALL ISNAME
            JR C,XMISS              ; the name goes on, so this was not it

            LD (CHAD),DE            ; step CHAD past the name; the arguments follow
            LD E,(HL)
            INC HL
            LD D,(HL)               ; the routine's address
            POP HL                  ; discard the saved entry pointer
            EX DE,HL
            JP (HL)                 ; enter it; it returns to NEXTSTAT

XMISS:      POP HL                  ; step over this entry: length byte + name + address
            LD C,(HL)
            LD B,0
            INC BC
            INC BC
            INC BC
            ADD HL,BC
            JR XENT

XNONE:      RST &08
            DB 29                   ; Not understood

; --- ISNAME: CY if A is a letter, '$' or '_' ---

ISNAME:     CALL ALPHA
            RET C

            CP "$"
            SCF
            RET Z

            CP "_"
            SCF
            RET Z

            AND A
            RET

ALPHA:      CP "A"
            CCF
            RET NC

            CP "z"+1
            RET NC

            CP "Z"+1
            RET C

            CP "a"
            CCF
            RET


; =====================================================================================================================
; The commands themselves. Each is entered with CHAD at its arguments and returns to the next statement.
; Each must cope with the syntax pass as well as with execution.
; =====================================================================================================================

; --- .FLUSH -- empty the keyboard queue. No arguments. ---

XFLUSH:     LD A,(FLAGS)
            RLA                     ; bit 7 -> CY: running
            RET NC                  ; the syntax pass has nothing to check

            JP KBFLUSH

; --- .WAIT n -- wait n frames, ignoring the keyboard ---

XWAIT:      CALL EXPT1NUM           ; CY if running
            RET NC

            CALL GETINT             ; BC = the frame count

XWOUT:      LD A,B
            OR C
            RET Z

            LD A,(FRAMES)           ; the low byte of the frame counter

XWIN:       LD HL,FRAMES
            CP (HL)
            JR Z,XWIN               ; wait for the interrupt to move it on

            DEC BC
            JR XWOUT


; =====================================================================================================================
; The command table: name length, name, routine address. A zero length ends it.
; =====================================================================================================================

XTAB:       DB 5
            DM "FLUSH"
            DW XFLUSH
            DB 4
            DM "WAIT"
            DW XWAIT
            DB 0
```

131 bytes, at 23765–23895, with `XCMD` at 23765.

```basic
   10 RESTORE 1000
   20 FOR i = 23765 TO 23765+130: READ b: POKE i,b: NEXT i
   30 DPOKE 23284, 23765               : REM CMDV
   40 STOP
 1000 DATA 254,46,192,225,33,72,93,126,167,40,44,71,229,35,237,91
 1010 DATA 151,90,19,26,174,230,223,32,20,35,19,16,246,26,205,14
 1020 DATA 93,56,10,237,83,151,90,94,35,86,225,235,233,225,78,6
 1030 DATA 0,3,3,3,9,24,208,207,29,205,28,93,216,254,36,55
 1040 DATA 200,254,95,55,200,167,201,254,65,63,208,254,123,208,254,91
 1050 DATA 216,254,97,63,201,58,59,92,23,208,195,102,1,205,24,1
 1060 DATA 208,205,33,1,120,177,200,58,120,92,33,120,92,190,40,250
 1070 DATA 11,24,241,5,70,76,85,83,72,42,93,4,87,65,73,84
 1080 DATA 50,93,0
```

```basic
.flush
.wait 100
FOR i = 1 TO 5: PRINT i: .wait 25: NEXT i
```

#### Notes

* `CHAD` still points at the `.` when `CMDV` fires, so the name starts one
  byte later. Reading it directly through `(DE)` is safe because the
  program's page is already in section C.
* Setting `CHAD` past the name is all the argument routines need; `RST &18`
  skips any spaces for them.
* Rejecting a match that is followed by a letter, `$` or `_` is what stops
  `.waiting` matching `.wait`.
* The table search happens on **every** execution. For a command inside a
  loop that is a real cost, and route B removes it.

### 9.4 Route B — `DEF PROC`-style calling buffers

This is the design of §9.1, finished. External commands are written without
a dot, exactly like procedure calls, and the ROM's own calling-buffer
machinery carries the resolved address.

#### How it works

| Stage | What happens |
|---|---|
| Syntax pass | The ROM sees a letter-initial statement, runs `PROCSY`, and opens a six-byte buffer after the name: `0E FD FD ?? ?? ??` |
| Compile pass | `LOOKDP` searches the program for a matching `DEF PROC`. Finding none, it writes a page byte of `&FF` — bits 7, 6 **and 5** set |
| First execution | `PROCS` sees bit 5 and raises error 12. Our **`RST8V`** hook traps it, searches the `XCMDP` chain, and patches the buffer: page byte = `page \| &C0` (resolved, external) and the entry address. It then dispatches the call |
| Later executions | Our **`CMDV`** hook spots bit 6 set and bit 5 clear, reads the address straight out of the buffer, and jumps — no search at all |

The division of labour is the point: `RST8V` is the *compiler*, run once per
call site; `CMDV` is the *fast path*, run every time.

Three properties fall out of using the ROM's own buffer:

* **A real `DEF PROC` always wins.** The compile pass resolves genuine
  procedures first and our hook never sees them, so a program can override an
  external command simply by defining a procedure of that name.
* **Arguments work identically.** The buffer occupies the six bytes between
  the name and the argument list, so setting `CHAD` past it puts the
  arguments exactly where a `PROC` call would find them.
* **Nothing is stored that can go stale.** The address points into the
  extension, not into the program, and the compile pass rebuilds the buffer
  from scratch whenever the program changes.

#### How long the patch lasts

`COMPILE` runs before every execution, but the *whole-program* pass only runs
when `COMPFLG` is non-zero. `SCOMP` sets it, and is called by `LOAD`,
`DELETE`, `KEYIN`, `RENUM` and line insertion — and `CLEAR` calls `DOCOMP`,
which sets it unconditionally. Since `RUN` is `CLEAR` plus a jump, that means:

* **`RUN` clears every patch**, so the first call to each external command in
  a run costs one chain search.
* Within a run, and across direct commands, patches persist.
* Editing any line, or `LOAD`/`RENUM`/`KEYIN`, also clears them — which is
  what you want, since the buffer's position in the line has moved.

If you want the patch to survive `RUN`, rewrite the two `&FD` filler bytes to
something else — say `&FC` — as you patch. `LKCALL` only recognises `&FD` and
`&FE`, so the compile pass will then leave the buffer alone forever. **This
is a trap, not a tip:** the buffer now looks resolved to `PROCS`, so if the
extension is ever absent — the program saved and reloaded on a bare machine —
`PROCS` will page in a stale page and parse machine code as a `DEF PROC`
line. Leaving the fillers as `&FD` degrades safely to *Missing DEF PROC*.

#### The code

```z80
; External commands with DEF PROC-style calling buffers, registered through XCMDP
XCMDP:      EQU &5A0B
CHAD:       EQU &5A97
FLAGS:      EQU &5C3B
FRAMES:     EQU &5C78
HMPR:       EQU 251
NUMMARKER:  EQU &0E
EXPT1NUM:   EQU &0118
GETINT:     EQU &0121
KBFLUSH:    EQU &0166

            ORG &5CD5

; =====================================================================================================================
; CMDV -- the fast path: a call buffer that has already been resolved to an external command
;
; Entry:  A = the first significant byte of the statement, CHAD -> it
; =====================================================================================================================

CMDHK:      LD C,A                  ; keep the byte, since declining must leave it untouched
            CALL ALPHA
            LD A,C
            RET NC                  ; not a letter, so not a PROC-style call

            LD A,(FLAGS)
            RLA                     ; bit 7 -> CY: running
            LD A,C
            RET NC                  ; syntax pass: let the ROM build the call buffer

            CALL FINDBUF            ; HL -> the buffer's page byte
            LD A,C
            RET NC                  ; no buffer within reach: leave it to the ROM

            LD A,(HL)
            AND &60
            CP &40                  ; bit 6 set and bit 5 clear: resolved, and external
            LD A,C
            RET NZ                  ; a DEF PROC or an unresolved buffer: leave it to the ROM

            POP DE                  ; discard the dispatcher's return; NEXTSTAT is now on top
            JR CALLEXT


; =====================================================================================================================
; RST8V -- trap "Missing DEF PROC" and resolve the name against the external command lists
;
; Entry:  A = the error code, DE -> the code byte, and the stack holds
;         [return into the error handler] [address past the DB] [NEXTSTAT]
;
; The third of those is only there because PROCS pushes nothing between the dispatcher's PUSH and its RST &08.
; =====================================================================================================================

ERRHK:      CP 12                   ; Missing DEF PROC?
            RET NZ                  ; any other error is not ours

            LD HL,(CHAD)            ; -> the first character of the name
            CALL XLOOK              ; CY with A = page byte and DE = entry address
            RET NC                  ; not one of ours: let the ROM report the error

            POP HL                  ; discard the return into the error handler
            POP HL                  ; discard the address past the DB; NEXTSTAT is now on top

            PUSH AF
            PUSH DE
            CALL FINDBUF            ; HL -> the buffer's page byte
            POP DE
            POP AF
            JR NC,ENTER             ; no buffer: dispatch this once without patching

            OR &C0                  ; bit 7 resolved, bit 6 external
            LD (HL),A
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D               ; the buffer now takes the fast path above
            INC HL
            LD (CHAD),HL            ; the arguments follow the buffer
            JR ENTER


; --- CALLEXT: read a resolved buffer at (HL) and enter the routine ---

CALLEXT:    LD A,(HL)               ; page byte
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)               ; entry address
            INC HL
            LD (CHAD),HL            ; the arguments follow the buffer

; --- ENTER: A = page byte, DE = entry address. Page it in only if it is not already addressable. ---

ENTER:      BIT 7,D
            JR Z,ENTGO              ; below &8000: in the system page or ROM, so no paging needed

            AND &1F
            LD H,A
            IN A,(HMPR)
            XOR H
            AND &E0
            XOR H
            OUT (HMPR),A

ENTGO:      EX DE,HL
            JP (HL)                 ; the routine returns to NEXTSTAT


; ---------------------------------------------------------------------------------------------------------------------
; FINDBUF -- locate the call buffer that follows the name at CHAD
;
; Exit:   CY with HL -> the buffer's page byte; NC if there is none within a sensible distance
; ---------------------------------------------------------------------------------------------------------------------

FINDBUF:    LD HL,(CHAD)
            LD B,40
            LD A,NUMMARKER

FBLP:       CP (HL)
            INC HL
            JR Z,FBOK

            DJNZ FBLP

            AND A                   ; NC
            RET

FBOK:       INC HL                  ; step over the two filler bytes
            INC HL
            SCF
            RET


; =====================================================================================================================
; XLOOK -- search the XCMDP chain for the name at (HL)
;
; Exit:   CY with A = the routine's page byte and DE = its address; NC if the name is not registered
;
; The name is copied into the system page first, because a command list may live in a page that has to be mapped
; over section C -- which is where the program, and therefore the name, currently is.
; =====================================================================================================================

XLOOK:      LD DE,NMBUF
            LD B,0

XNLP:       LD A,(HL)
            CALL ALNUMUND
            JR NC,XNEND

            LD (DE),A
            INC DE
            INC HL
            INC B
            LD A,B
            CP 33
            JR C,XNLP

XNEND:      LD A,B
            LD (NMLEN),A
            AND A
            RET Z                   ; an empty name matches nothing

            IN A,(HMPR)
            LD (SAVHMP),A
            LD HL,(XCMDP+1)
            LD A,(XCMDP)

XLIST:      INC A
            JR Z,XNOTF              ; a page byte of &FF ends the chain

            DEC A
            CALL XPAGE              ; map this list if it is not already addressable
            LD C,(HL)               ; the next list's page ...
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)               ; ... and address
            INC HL                  ; -> the first entry
            PUSH DE
            PUSH BC
            CALL XENTS
            POP BC
            POP DE
            JR C,XFOUND

            LD A,C
            EX DE,HL
            JR XLIST

XFOUND:     LD (XPG),A
            LD (XAD),DE
            LD A,1
            JR XDONE

XNOTF:      XOR A

XDONE:      LD (XHIT),A
            LD A,(SAVHMP)
            OUT (HMPR),A            ; put the paging back before returning
            LD DE,(XAD)
            LD A,(XHIT)
            RRA                     ; bit 0 -> CY
            LD A,(XPG)              ; does not disturb the flags
            RET


; --- XENTS: search one list, whose first entry is at (HL) ---

XENTS:      LD A,(HL)               ; the entry's name length; 0 ends the list
            AND A
            RET Z                   ; NC

            PUSH HL
            LD B,A
            LD A,(NMLEN)
            CP B
            JR NZ,XEN2              ; a different length cannot match

            INC HL
            LD DE,NMBUF

XECMP:      LD A,(DE)
            XOR (HL)
            AND &DF                 ; compare without regard to case
            JR NZ,XEN2

            INC HL
            INC DE
            DJNZ XECMP

            LD A,(HL)               ; the routine's page ...
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)               ; ... and address
            POP HL
            SCF
            RET

XEN2:       POP HL                  ; step over this entry: length byte, name, page, address
            LD C,(HL)
            LD B,0
            INC BC
            INC BC
            INC BC
            INC BC
            ADD HL,BC
            JR XENTS


; --- XPAGE: map page A into section C, but only if HL is not already addressable ---

XPAGE:      BIT 7,H
            RET Z

            PUSH HL
            AND &1F
            LD H,A
            IN A,(HMPR)
            XOR H
            AND &E0
            XOR H
            OUT (HMPR),A
            POP HL
            RET


; --- Character classes, as the ROM defines them ---

ALNUMUND:   CALL ALPHA
            RET C

            CP "9"+1
            JR NC,ANUND

            CP "0"
            CCF
            RET C

ANUND:      CP "_"
            SCF
            RET Z

            AND A
            RET

ALPHA:      CP "A"
            CCF
            RET NC

            CP "z"+1
            RET NC

            CP "Z"+1
            RET C

            CP "a"
            CCF
            RET


; =====================================================================================================================
; The commands themselves. Entered with CHAD at the arguments; each returns to NEXTSTAT.
; =====================================================================================================================

XFLUSH:     LD A,(FLAGS)
            RLA
            RET NC                  ; syntax pass

            JP KBFLUSH

XWAIT:      CALL EXPT1NUM           ; CY if running
            RET NC

            CALL GETINT             ; BC = the frame count

XWOUT:      LD A,B
            OR C
            RET Z

            LD A,(FRAMES)

XWIN:       LD HL,FRAMES
            CP (HL)
            JR Z,XWIN

            DEC BC
            JR XWOUT


; =====================================================================================================================
; Our command list. The first three bytes are the chain link, filled in at install time with the old XCMDP.
;
;   list:   page of the next list (&FF = none), address of the next list (2)
;   entry:  name length, name, routine page, routine address (2)     -- a length of 0 ends the list
; =====================================================================================================================

MYLIST:     DB &FF                  ; no next list until the installer says otherwise
            DW 0

            DB 5
            DM "FLUSH"
            DB 0
            DW XFLUSH

            DB 4
            DM "WAIT"
            DB 0
            DW XWAIT

            DB 0                    ; end of this list

NMLEN:      DB 0
NMBUF:      DS 33
SAVHMP:     DB 0
XPG:        DB 0
XAD:        DW 0
XHIT:       DB 0
```

384 bytes, at 23765–24148:

| Symbol | Address | Purpose |
|---|---|---|
| `CMDHK` | 23765 | → `CMDV` (23284) |
| `ERRHK` | 23792 | → `RST8V` (23278) |
| `MYLIST` | 24089 | The command list, to be registered in `XCMDP` |

#### Loader

Use the configurator of §8 to carve the space — with `+ 352` changed to
`+ 400`, since this block is larger — and then:

```basic
   10 REM ---- external commands with calling buffers
   20 RESTORE 1000
   30 FOR i = 23765 TO 23765+383: READ b: POKE i,b: NEXT i
   40 REM chain our list on to whatever was already registered
   50 POKE  24089, PEEK 23051
   60 DPOKE 24090, DPEEK 23052
   70 POKE  23051, 0                          : REM our list is directly addressable
   80 DPOKE 23052, 24089
   90 REM install the hooks
  100 DPOKE 23284, 23765                      : REM CMDV
  110 DPOKE 23278, 23792                      : REM RST8V
  120 PRINT "external commands installed"
  130 STOP
 1000 DATA 79,205,237,93,121,208,58,59,92,23,121,208,205,44,93,121
 1010 DATA 208,126,230,96,254,64,121,192,209,24,34,254,12,192,42,151
 1020 DATA 90,205,63,93,208,225,225,245,213,205,44,93,209,241,48,22
 1030 DATA 246,192,119,35,115,35,114,35,34,151,90,24,9,126,35,94
 1040 DATA 35,86,35,34,151,90,203,122,40,11,230,31,103,219,251,172
 1050 DATA 230,224,172,211,251,235,233,42,151,90,6,40,62,14,190,35
 1060 DATA 40,4,16,250,167,201,35,35,55,201,17,47,94,6,0,126
 1070 DATA 205,219,93,48,9,18,19,35,4,120,254,33,56,241,120,50
 1080 DATA 46,94,167,200,219,251,50,80,94,42,12,90,58,11,90,60
 1090 DATA 40,34,61,205,202,93,78,35,94,35,86,35,213,197,205,158
 1100 DATA 93,193,209,56,4,121,235,24,230,50,81,94,237,83,82,94
 1110 DATA 62,1,24,1,175,50,84,94,58,80,94,211,251,237,91,82
 1120 DATA 94,58,84,94,31,58,81,94,201,126,167,200,229,71,58,46
 1130 DATA 94,184,32,22,35,17,47,94,26,174,230,223,32,12,35,19
 1140 DATA 16,246,126,35,94,35,86,225,55,201,225,78,6,0,3,3
 1150 DATA 3,3,9,24,212,203,124,200,229,230,31,103,219,251,172,230
 1160 DATA 224,172,211,251,225,201,205,237,93,216,254,58,48,4,254,48
 1170 DATA 63,216,254,95,55,200,167,201,254,65,63,208,254,123,208,254
 1180 DATA 91,216,254,97,63,201,58,59,92,23,208,195,102,1,205,24
 1190 DATA 1,208,205,33,1,120,177,200,58,120,92,33,120,92,190,40
 1200 DATA 250,11,24,241,255,0,0,5,70,76,85,83,72,0,251,93
 1210 DATA 4,87,65,73,84,0,3,94,0,0,0,0,0,0,0,0
 1220 DATA 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
 1230 DATA 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
```

#### Trying it

```basic
   10 flush
   20 FOR i = 1 TO 5
   30   PRINT i
   40   wait 25
   50 NEXT i
```

and then, to see a real `DEF PROC` take precedence:

```basic
   10 wait 25
   20 STOP
 1000 DEF PROC wait n
 1010   PRINT "my own wait, "; n
 1020 END PROC
```

### 9.5 `XCMDP` — a chainable registry

`XCMDP` is three bytes at 23051 in the ROM's standard page-form: a page byte
followed by a 16-bit address, with a page byte of `&FF` meaning "none". That
much is the ROM's, and "**first** external cmd list" tells us a chain was
intended. Everything below is a proposal that fits those constraints — there
is no ROM code to be compatible with, so the only thing that matters is that
implementations agree with each other.

#### Format

```text
list:   +0      page of the next list, or &FF to end the chain
        +1..2   address of the next list
        +3..    entries

entry:  +0      name length in characters, or 0 to end this list
        +1..    the name, upper case, no terminator
        +n+1    page byte of the routine
        +n+2..3 address of the routine
```

Two conventions make it usable:

* **A routine or list whose address is below &8000 is directly addressable**
  — it is in the system page or in ROM — and its page byte is ignored. This
  is what lets a small utility register a list without owning a page.
* **Otherwise the page byte is a physical page number** in bits 4–0, to be
  mapped into section C, and the address lies in &8000–&BFFF. The remaining
  bits follow the calling-buffer convention (bit 7 resolved, bit 6 external),
  so an entry can be copied straight into a call buffer.

A routine that needs to read `CHAD` — which is to say, one that takes
arguments — must be directly addressable, because paging section C displaces
the program. A routine in its own page must either take no arguments or be
reached through a trampoline in the system page.

#### Registering a list

Chain insertion at the head, which is the only operation that needs no
locking and cannot disturb a search in progress:

```z80
INSTALL:    LD HL,(XCMDP+1)         ; the current head
            LD (MYLIST+1),HL
            LD A,(XCMDP)
            LD (MYLIST),A           ; our list now points at it
            LD HL,MYLIST
            LD (XCMDP+1),HL
            XOR A                   ; page 0: directly addressable
            LD (XCMDP),A            ; ... and we are the new head
            RET
```

or from BASIC, as in the loader above:

```basic
POKE  24089, PEEK 23051
DPOKE 24090, DPEEK 23052
POKE  23051, 0
DPOKE 23052, 24089
```

#### Rules for playing well with others

* **Insert at the head, and always preserve the old value.** Overwriting
  `XCMDP` without chaining silently unregisters every other extension.
* **Search the whole chain.** Stop at the first match, so the most recently
  installed list wins — the same precedence rule as vector chaining.
* **Restore `HMPR` before returning** if you paged a list in.
* **Do not remove your list from the middle of the chain** unless you can be
  sure nothing else has since chained on to it. Zeroing your own hook vectors
  is the safe way to disable an extension; see §10.
* **Copy the candidate name out of the program first.** A search that pages
  a list into section C destroys its own input otherwise. `XLOOK` above does
  this.

### 9.6 How a resident DOS does it differently

A DOS does not need `RST8V` at all, because the ROM already routes every
error to it. `ERROR2` offers the code to `RST8V` first, then:

```z80
            LD A,(DOSFLG)
            AND A
            LD A,(DE)
            JR NZ,PTDOS                 ; A DOS is resident, so it sees everything
```

`PTDOS` pages the DOS into section B, switches to a private stack inside the
DOS page, and calls **&4203** for an error or **&4200** for a hook code. So a
DOS gets error 12 handed to it on a plate, with its own code and workspace
mapped — a far better position than a system-page hook occupies.

On return the ROM inspects three things:

| | |
|---|---|
| `DOSER` (23488) | If non-zero, the ROM jumps there instead of continuing — "re-enter me at this address" |
| `A` | Non-zero means "still an error, report it"; zero means handled |
| `DOSCNT` (23491) | Bit 0 is set while the DOS is in control, so an error raised *inside* the DOS is not handed back to it |

The handled path resets `SP` from `ERRSP` before returning, which means the
DOS is expected to have arranged its own resume address there. That last part
is a DOS-side convention, and the ROM alone does not determine it.

The practical consequence for a utility author: **if a DOS is present, it
sees the error before you get to act on the consequences, and it may consume
it.** An `RST8V` hook still runs first, so trapping error 12 works either
way — but a hook that declines will find the DOS may handle the error
differently from the bare ROM.

### 9.7 B-DOS and dot commands

**I have not been able to verify how B-DOS implements dot commands.** This
repository contains the ROM sources and a set of ROM images only — no DOS
source, and no DOS binary to disassemble. Everything in §9.1–9.6 is derived
from the ROM side of the interface, which constrains what any DOS can do but
does not tell us what a particular one chose.

What the ROM side does establish, and which any DOS's implementation must fit:

* A DOS is entered at **&4200** (hook codes ≥ 128) and **&4203** (errors),
  with its own page in section B and its own stack. Both are reached only
  through `RST &08`.
* It therefore sees **error 12** without needing `RST8V`, which makes the
  route-B design of §9.4 the natural one for a DOS: no dot required, and
  the ROM's own calling buffers carry the resolved address.
* Equally it can claim `CMDV` and recognise `.` directly, as in §9.3. Nothing
  stops a DOS doing both.
* Whichever it chooses, the three facilities the ROM built for this —
  bit 6 of the call buffer page byte, `TSURPG` paging the code in, and
  `XCMDP` — are available and cost nothing to use.

The open questions that only the source can answer are:

1. Does B-DOS recognise `.` in `CMDV`, or does it trap error 12, or both?
2. Does it use the ROM's calling buffers and bit 6, or its own lookup?
3. Does it populate `XCMDP`, and if so in what format? If a real format
   exists, §9.5's proposal should be replaced by it rather than competing
   with it.
4. How does a dot command loaded from disc get into memory and stay there —
   its own page, or the DOS's?

> **Yes please — if you can get hold of the B-DOS source, I would like to see
> it.** Those four questions are answerable in an afternoon with it, and the
> answers would turn §9.5 from a proposal into documentation of an existing
> convention. The same applies to MasterDOS and SAMDOS if they are to hand:
> comparing two implementations would show which parts are convention and
> which are accident.

---

## 10. Chaining, uninstalling and surviving `NEW`

### Only one owner per vector

Each vector holds one address. If two extensions both want `CMDV`, the
second must chain to the first:

```z80
        ; at install time, save whatever was there
OLDCMD: DW 0

MYHOOK: CP MYTOKEN
        JR Z,MINE
        LD HL,(OLDCMD)          ; not mine: pass it on
        LD A,H
        OR L
        RET Z                   ; nothing was there
        LD A,C                  ; restore the byte the next hook expects
        JP (HL)
```

Note the `JP (HL)`, not `CALL`: the next hook in the chain expects the same
stack layout you were given, including the dispatcher's return address, so
that it too can `POP` it if it decides to handle the statement.

Keep the byte in a register the chain preserves (or reload it) before
jumping — the flag-and-register conventions in §3 apply to every link.

### `NEW` does not clear the vectors

`NEW` enters at `NEW2`, which resets the screen list, the page allocation
table, the streams, the variable areas and the palette. It does **not**
re-copy the `CHIT`/`MAIT` initialisation tables, so the whole vector block,
`CMDADDRT`, `PATOUT`, `ERRMSGS`, `KBTAB`, `DKLIM`, `PSLD` and `XCMDP` all
survive it. Only a cold start clears them.

That is convenient — your extension survives `NEW` — and dangerous: a
vector pointing at code that has been overwritten will crash the machine at
the next statement. Two consequences:

* **Uninstall by zeroing the vector**, not by overwriting the code.
  `DPOKE 23284,0` disables a `CMDV` hook completely.
* **Do not leave a vector pointing into the hole below `PROG` if you then
  lower `PROG` back**, and do not point one at a reserved page you later
  release with `CLOSE`.

A defensive installer zeroes every vector it is about to claim before poking
the code, so a half-installed extension cannot fire.

### Tokens outlive the extension

A program that has been tokenised with your keywords contains your token
bytes. Load it with the extension absent and &D0 lists as `-` and gives
*Not understood*; `&FF &6A` lists as `-` and gives *Not understood* too.
There is no version marking, so a program that depends on an extension should
check for it and refuse to run otherwise:

```basic
10 IF DPEEK 23284 = 0 THEN PRINT "extension not installed": STOP
```

---

## 11. Checklist and pitfalls

Before you install a hook, check every one of these.

**Register and flag discipline**

- [ ] Every hook returns with `A` unchanged when it declines. `CMDV`,
      `EVALUV`, `RST28V` and `PRTOKV` all use `A` after the call.
- [ ] `MTOKV` returns `Z` to decline and `NZ` with `A`, `HL` and `DE` set to
      accept.
- [ ] `PRTOKV` must not use `INC A` to test for &FF — it destroys the value
      the ROM is about to test.

**Stack discipline**

- [ ] `POP` exactly one return address when you take over from `CMDV`,
      `RST28V` or `PRTOKV`, and none when you decline.
- [ ] A routine reached through the channel-output diversion (§8) has a
      *different* stack layout — do not `POP` there.
- [ ] An `RST8V` hook that takes over pops **two** — and only because the
      error site was checked. Confirm what the erroring routine had pushed
      before assuming the same layout for another error code.
- [ ] An `RST8V` hook cannot change the error by changing `A`; the ROM
      re-reads the code from `(DE)`.

**The two passes**

- [ ] Every command hook works on the syntax pass as well as at run time.
      Validate the arguments and return; do not act.
- [ ] Nothing is on the calculator stack during the syntax pass. `GETINT`
      after a `RET NC` you forgot to write will read rubbish.

**Paging**

- [ ] The hook body is in the system page, &4000–&7FFF.
- [ ] `RST28V` and `PRTOKV` hooks run with ROM 1 in section D; do not touch
      `LMPR`.
- [ ] If you page section C, restore `HMPR` before returning.
- [ ] Use the jump table for anything that touches BASIC's data; those
      routines handle and restore paging themselves.

**Tokens**

- [ ] The command token is &D0, &F7–&FE, or one of the eight reserved DOS
      spellings — and &F7–&FE only work through `CMDV`.
- [ ] The function code is &68 or &6A, and your argument and result types
      match the priority byte the ROM has already fixed for it.
- [ ] The operator code is &7D, and priority 2 is acceptable.
- [ ] Your `MTOKV` match is rejected when followed by a letter, `$` or `_`.
- [ ] The word is not already in the ROM's keyword table — `MTOKV` is only
      consulted after the ROM's own table misses.

**Listing**

- [ ] A `PRTOKV` hook exists for every token that has no real spelling in
      `KEYWTAB`, or `LIST` will show `-`.
- [ ] Leading and trailing spaces follow the ROM's rule, or listings will run
      words together.

**Errors**

- [ ] Errors are raised with `RST &08` and a code byte, and never return.
- [ ] A ROM routine that raises an error does not return to you either —
      validate ranges before calling `GETINT`, `SBUFFET` and friends if you
      need to stay in control.

---

## Related documents

| Document | For |
|---|---|
| [machine-code-interface.md](machine-code-interface.md) | The full jump table, the restarts, the calculator's instruction set, and the `CALL`/`USR` protocol |
| [tokenized-program-format.md](tokenized-program-format.md) | The exact stored form of a line, the invisible five-byte forms, and the compile pass |
| [memory-map.md](memory-map.md) | Every region of the system page, with sizes — the definitive account of what is free |
| [hudg.md](hudg.md) | Raising `PROG` to carve always-addressable RAM, and why `NEW` cannot be automated |
| [constants.md](constants.md) | Every named constant, including the full token and error lists |
| [source-files.md](source-files.md) | Routine-by-routine reference, including all the call sites quoted here |
| [user-manual/](user-manual/README.md) | The language itself |

---

> [!WARNING]
> **AI-generated documentation.** The contracts above were read from the ROM
> source and the example code assembles cleanly with pyz80, but none of it has
> been run on real hardware or in an emulator. Treat the listings as
> well-evidenced starting points, not as tested software — and test any hook
> on a machine you are willing to reset.
