# SAMDOS 2, MasterDOS and MasterBASIC

What the three common extensions add to SAM BASIC, how each attaches itself
to the ROM, and the complete extended token map.

The ROM alone gives you the language documented in
[user-manual/](user-manual/README.md). Almost every real SAM had at least a
DOS loaded, and much published software assumes MasterDOS or MasterBASIC —
so a great deal of "SAM BASIC" as people remember it is not in the ROM at
all. This document draws the line.

Sources:

| | |
|---|---|
| SAMDOS 2 | Source, `samdos/src/*.s` — Bruce B Gordon / SAM Computers Ltd, 1990 |
| MasterDOS 2.3 | Source, `masterdos/src/masterdos23.asm` — Andrew J A Wright, 1990 |
| MasterBASIC | *SAM Coupé MasterBASIC Documentation V2*, Format Publications — manual only, no source |

Where a statement below comes from a manual rather than from source it says
so. Where it comes from source it can be checked line by line.

---

## Tags used throughout the documentation

These appear in the user manual and the other reference documents wherever a
feature is not part of the ROM:

| Tag | Meaning |
|---|---|
| **`[DOS]`** | Needs *some* disk operating system. Without one the ROM raises error 53, *No DOS*, or 29, *Not understood* |
| **`[SD2]`** | SAMDOS 2 |
| **`[MD]`** | MasterDOS |
| **`[MB]`** | MasterBASIC |

A feature tagged **`[MD]`** **`[MB]`** needs both. Untagged material is pure
ROM 3.0 and works on a bare machine.

---

## Contents

1. [The three products](#1-the-three-products)
2. [How they attach to the ROM](#2-how-they-attach-to-the-rom)
3. [SAMDOS 2](#3-samdos-2)
4. [MasterDOS](#4-masterdos)
5. [MasterBASIC](#5-masterbasic)
6. [The extended token map](#6-the-extended-token-map)
7. [External commands: how it is really done](#7-external-commands-how-it-is-really-done)
8. [What this tells us about the ROM](#8-what-this-tells-us-about-the-rom)

---

## 1. The three products

**SAMDOS 2** is the standard disk operating system: the minimum needed to
make `DIR`, `FORMAT`, `ERASE`, `LOAD`, `SAVE` and friends work with a disk
drive. It adds no new keywords at all — it implements the ones the ROM
already tokenises but dispatches to *Not understood*.

**MasterDOS** is a much larger replacement DOS. It implements the same
commands, plus sub-directories, RAM disks, a clock, record files, and
**three new command tokens and seven new functions** of its own.

**MasterBASIC** is not a DOS. It is a language extension that loads *on top
of* a DOS and adds editing, sorting, string handling, sound and graphics
features — **four more command tokens and nineteen more functions**. Its
manual says it will combine itself with either DOS into one bootable file:

> The master disk supplied with this manual contains a program called
> "autoMBM" that will combine MasterBASIC with your DOS (preferably
> MasterDOS, but SAMDOS2 will do) to give a single convenient BOOTable file
> […] with the name "SD+MBASxx" or "MD+MBASxx".

A few MasterBASIC features are documented as needing MasterDOS specifically
— the timing functions need MasterDOS *and* the SAMBus clock, and there is a
section of the manual headed "With MasterDOS:" covering RAM-disk speed,
`ALTER DEVICE`, serial file buffers, and extensions to `FSTAT`, `DIR$` and
`INP$`.

---

## 2. How they attach to the ROM

Both DOSes use the same three mechanisms, and they are exactly the ones
[extending-basic.md](extending-basic.md) describes. Seeing them used in
anger is the best available check on that document.

### 2.1 The error-29 trap

Neither DOS hooks `CMDV` to catch its commands. Instead both let the ROM
fail and trap the error at their **`&4203` error entry**, which the ROM's
`PTDOS` calls for every error code.

SAMDOS 2 (`b.s`):

```z80
syntax:        ld (entsp),sp
               cp 29          ;notund
               jp nz,synt3
               …
               call gchr
               cp &90         ;dir
               jp z,dir
               cp &91         ;format
               jp z,wfod
               …
```

MasterDOS does the same but table-driven, and also traps error 53:

```z80
SYNTAX:        DI
               CP   53         ;NO DOS
               JR   Z,SYNT1
               CP   29         ;NOT UNDERSTOOD
               JR   NZ,ST3HP
```

Both then reset `CHAD` from `CSTAT` — the ROM system variable holding the
address of the statement currently executing — so they re-read the statement
from its first byte and dispatch on the command token.

MasterDOS guards against recursion with a flag, because the DOS itself calls
ROM routines that can raise error 29:

```z80
ST3HP:         JP   NZ,SYNT3   ;JP IF E.G. DOS CALLED EXPT1NUM
                               ; AND GOT VAL "#!"
                               ;GIVING NONSENSE ERROR - DO NOT
                               ; RECURSIVELY CALL DOS!
```

### 2.2 Hook codes

The ROM defines hook codes 128–142. Both DOSes extend the table far beyond
that and use the extra codes as their own internal call interface — a DOS
routine reaches another by `RST &08 : DEFB n` rather than by a direct call,
so the whole DOS is callable from anywhere without knowing where it is
paged. SAMDOS 2 goes to 168; MasterDOS to 174.

### 2.3 Vectors — MasterDOS only

MasterDOS additionally claims four ROM vectors. SAMDOS 2 claims none.

```z80
               LD   HL,SERDT+FS
               LD   DE,&4BA0
               LD   BC,DTEND-SERDT
               LDIR              ;COPY CODE TO SYS PAGE AT 4BA0H

               LD   HL,&4BB0
               LD   (&5ADE),HL     ;PRTOKV
               LD   HL,XTRA+MTV-PFV
               LD   (&5AFA),HL     ;MTOKV
               LD   HL,&4BB0+EVV-PVECT
               LD   (&5AF6),HL     ;EVALUV
               LD   HL,&4BB0+SLVP-PVECT
               LD   (CMDV),HL
```

Note **where** the stubs go: `&4BA0` in the system page, and a second block
at `XTRA` = `&5896`. Both are regions [memory-map.md](memory-map.md) lists as
spare — &4BA0–&4BFF is the gap below the interrupt stack, and &5896 is inside
the 95-byte hole at &5881–&58DF. So MasterDOS occupies **both** of the small
system-page holes an extension might otherwise want.

---

## 3. SAMDOS 2

### 3.1 Commands

SAMDOS 2 adds **no new tokens**. It implements ROM tokens that would
otherwise give *Not understood*:

| Token | Keyword | |
|---|---|---|
| &86 | `WRITE` | **`[SD2]`** The ROM tokenises this qualifier but never uses it |
| &90 | `DIR` | **`[DOS]`** |
| &91 | `FORMAT` | **`[DOS]`** |
| &92 | `ERASE` | **`[DOS]`** |
| &95 | `LOAD` | Extended for disk |
| &B8 | `READ` | **`[SD2]`** Record-file read |
| &CF | `COPY` | **`[DOS]`** |
| &E3 | `RENAME` | **`[DOS]`** |
| &E4 | `CALL` | Extended |
| &F1 | `PROTECT` | **`[DOS]`** |
| &F2 | `HIDE` | **`[DOS]`** |

`OPEN #` and `CLOSE #` need no interception: the ROM already hands an
unrecognised channel name to the DOS through hook codes 134 and 135.

Note that SAMDOS 2 does **not** claim `MOVE` (&93), which the ROM reserves —
MasterDOS does.

### 3.2 Hook codes

Codes 128–142 are the ROM's. SAMDOS 2 adds:

| Code | Purpose |
|---|---|
| 147 | `hofle` — open file |
| 148 | `sbyt` — save byte |
| 149 | `hwsad` — write sector |
| 150 | `hsvbk` — save block |
| 152 | `cfsm` |
| 154 | `pntp` |
| 155, 156 | `cops1`, `cops2` |
| 158 | `hgfle` — get file |
| 159 | `lbyt` — load byte |
| 160 | `hrsad` — read sector |
| 161 | `hldbk` — load block |
| 164 | `rest` |
| 165 | `pcat` |
| 166 | `heraz` — erase |

Codes in the range that are not implemented point at a common stub.

---

## 4. MasterDOS

### 4.1 Commands

MasterDOS's dispatch table `CTAB` is a list of (token, address) pairs:

| Token | Keyword | |
|---|---|---|
| &86 | `WRITE` | **`[MD]`** |
| &90 | `DIR` | **`[DOS]`** |
| &91 | `FORMAT` | **`[DOS]`** |
| &92 | `ERASE` | **`[DOS]`** |
| &93 | `MOVE` | **`[MD]`** — SAMDOS 2 does not implement this |
| &95 | `LOAD` | Extended |
| &98 | `OPEN` | Extended |
| &99 | `CLOSE` | Extended |
| &B3 | `CLEAR` | Patched |
| &B8 | `READ` | **`[MD]`** |
| &CF | `COPY` | **`[DOS]`** |
| &E3 | `RENAME` | **`[DOS]`** |
| &E4 | `CALL` | Extended |
| &F1 | `PROTECT` | **`[DOS]`** |
| &F2 | `HIDE` | **`[DOS]`** |
| **&F7** | **`BACKUP`** | **`[MD]`** — a new token |
| **&F8** | **`TIME`** | **`[MD]`** — a new token |
| **&F9** | **`DATE`** | **`[MD]`** — a new token |

`SAVE`, `LOAD`, `MERGE` and `VERIFY` (&94–&97) are additionally intercepted
through `CMDV`, as is `RUN`/`CLEAR`.

The source also carries two commented-out entries — `ALTER` at 250 and
`SORT` at 251 — reserved but not implemented. **MasterBASIC implements both,
at exactly those codes.**

### 4.2 Functions

MasterDOS's new functions are stored as `&FF` followed by a code in the range
**&30–&36**, which is *below* the ROM's own function range of &3B–&83 and so
cannot collide with it:

| Code | Function | Result |
|---|---|---|
| &30 | `TIME$` | string |
| &31 | `DATE$` | string |
| &32 | `INP$` | string |
| &33 | `DIR$` | string |
| &34 | `FSTAT` | numeric |
| &35 | `DSTAT` | numeric |
| &36 | `FPAGES` | numeric |

All are **`[MD]`**. A commented-out `SCRAD` at &37 is, again, implemented by
MasterBASIC.

MasterDOS also **extends `LENGTH`**, catching its internal code in the
`EVALUV` stub.

### 4.3 The vector stubs, in full

These are worth reading because they are a working example of every
technique [extending-basic.md](extending-basic.md) describes.

**`PRTOKV`** — list the new command tokens. Note the `POP HL` that discards
the lister's return, exactly as documented:

```z80
PVECT:         CP   247
               RET  C
               POP  HL
               LD   HL,(XPTR)
               RST  &08
               DEFB 169        ;HPTV - DOS PRINT TOKEN
               RET
```

**The two-byte function problem**, solved by diverting the channel's output
routine for one character — the same trick the ROM's own `POFN` uses:

```z80
;O/P ADDR USED WHEN CHAR AFTER FF IS PRINTED AT XTRA
PFV:           RST  &08
               DEFB 170      ;HPFF
               EXX
               PUSH BC
               POP  AF
PFTRG:         JP   C,0      ;JP POSTFF IF DOS DIDN'T HANDLE IT
               RET             ;JUST RET IF DONE IT
```

**`MTOKV`** — offer a failed word to the DOS, and for a function jump to a
patch in the buffer that writes the `&FF` prefix into the line by hand:

```z80
MTV:           RST  &08
               DEFB 171
               EXX
               PUSH BC
               POP  AF
               RET  Z
               RET  NC
               JP   &4F00      ;EXTENSION TO DEAL WITH FNS
```

**`CMDV`** — intercept `SAVE`/`LOAD`/`MERGE`/`VERIFY` and patch `RUN`/`CLEAR`:

```z80
SLVP:          LD   HL,SYSP
               LD   (DOSSTK),HL
               CP   &94        ;SAVE
               RET  C
               CP   &98
               JR   NC,RCP
               POP  HL
               RST  &08
               DEFB 173        ;HSLMV
```

### 4.4 `EVALUV`, and how MasterDOS rejoins the evaluator

This is the most interesting piece of the whole system, and it answers a
question [extending-basic.md §3.2](extending-basic.md#32-evaluv--the-expression-evaluator-23286)
had left open.

The stub catches its own codes — anything below `PI` — plus `LENGTH`:

```z80
EVV:           CP   &3F-&1A
               JR   Z,EVV2     ;RET UNLESS "LENGTH"
               CP   &3B-&1A
               RET  NC         ;DEAL WITH <3BH (PI)
EVV2:          POP  HL
               RST  &08
               DEFB 172        ;HKLEN - NO RETURN
```

It pops the evaluator's return address and never comes back — so it must
rejoin the scan somewhere. The ROM publishes no entry point for that. What
`HKLEN` does instead is **read the addresses out of the ROM at run time**,
navigating from the return address the vector was called with:

```z80
HKLEN:         EXX               ;HL=RET ADDR TO SCANNING
               INC  HL
               INC  HL
               INC  HL
               LD   C,(HL)     ;DISP TO "IMMED CODES"
               LD   B,0        ; (PART OF "JR")
               ADD  HL,BC
               PUSH HL         ;IMMED CODES
               LD   C,17
               ADD  HL,BC      ;PT TO NUMCONT
               LD   C,(HL)
               INC  HL
               LD   B,(HL)     ;BC=NUMCONT
               CP   &34-&1A
               JR   NC,HEVV2   ;JR IF NUMERIC RESULT
               LD   BC,6
               ADD  HL,BC
               LD   C,(HL)
               INC  HL
               LD   B,(HL)     ;BC=STRCONT
HEVV2:         PUSH AF
               CALL OWSTK   ;OVER-WRITE ADDR AFTER HOOK CODE ON
                            ;MAIN ROM STACK WITH NUMCONT OR
                            ;STRCONT ACCORDING TO TYPE OF RESULT
```

Step by step: it takes the return address into `SCANSR`, steps forward three
bytes to the `JR C,IMMEDCODES` displacement, adds it to find `IMMEDCODES`,
then reads the operands of the `LD HL,NUMCONT` and `LD HL,STRCONT`
instructions there. Having recovered both continuation addresses it
overwrites the return address on the ROM's stack with whichever suits the
result type, and dispatches its own function.

So a hook **can** implement a new immediate function and rejoin the
evaluator. The addresses are not published, but they are reachable by
walking the ROM relative to the vector's own return address — which survives
the ROM being at a different address, though not the instruction sequence
changing.

### 4.5 Hook codes

MasterDOS implements 128–174. Beyond the ROM's 128–142:

| Code | Purpose |
|---|---|
| 143 | `HLDPG` — as 130 but A = page |
| 144 | `HVEPG` — as 131 but A = page |
| 145 | `HSDIR` — set directory |
| 146 | `ROFSM` |
| 147 | `HOFLE` — open file |
| 148 | `SBYT` — save byte |
| 149 | `HWSAD` — write sector |
| 150 | `HKSB` — save ADE from HL |
| 151 | `HDBOP` — output BC from DE to file |
| 152 | `SCFSM` |
| 153 | `HORDER` — sort |
| 158 | `HGFLE` — get file |
| 159 | `LBYT` — load byte |
| 160 | `HRSAD` — read sector |
| 161 | `HLDBK` — load block |
| 162 | `HFRSAD` — far read sectors to a page |
| 163 | `HFWSAD` — far write sectors from a page |
| 164 | `REST` |
| 165 | `PCAT` |
| 166 | `HERAZ` — erase |
| 167, 168 | `MCHWR`, `MCHRD` — character write/read |
| 169 | `HPTV` — print token A |
| 170 | `HPFF` — the byte after `&FF` |
| 171 | `HGTTK` — match a word against the DOS keyword table |
| 172 | `HKLEN` — the evaluator patch |
| 173 | `HSLMV` — `SAVE`/`LOAD`/`MERGE`/`VERIFY` |
| 174 | `RCPTCH` — `RUN`/`CLEAR` |

Codes 137 and 138 differ from the ROM's meanings: MasterDOS uses 137 for
"seek track D" and 138 for "format track under head".

### 4.6 `DVAR`

`DVAR n` returns the **address** of the DOS's own variable *n*, so it is used
exactly like `SVAR`:

```basic
DPOKE DVAR 151, 0            : REM MasterBASIC: turn the warning BEEP off
POKE  DVAR 153, 1            : REM skip the format verify stage
```

MasterDOS's variable area begins at &4220 in the DOS page. A few of the
entries visible in the source:

| `DVAR` | Name | Meaning |
|---|---|---|
| 5 | `CHDIR` | Directory space character |
| 7 | `VERS` | Version: (`DVAR 7` − 20) / 10 — reads 43 for v2.3 |
| 9 | `SRTFG` | Sorted directory on/off |
| 11 | `FNSEP` | Separator character in file names |
| 15 | `ODEF` | Default drive |
| 16 | `DTKS` | Number of directory tracks |
| 22 | — | Address of the hook table |
| 26 | `NMIKP` | Page mapped at &8000 on NMI |
| 27 | `NMIKA` | Address called on NMI |
| **33** | **`ONERR`** | **The external syntax vector** — see §7 |
| **36** | **`EAPG`** | Page to use if `ONERR` is above &8000 |
| 37 | `MSINC` | Multi-sector increment |

MasterBASIC's manual documents four more that it adds: 151 `BEEPT`, 153
`FVFG`, 154 `CMPFG` (the `SAVE MODE` compression setting) and 155 `DBSTP`
(double stepping for 40-track disks).

---

## 5. MasterBASIC

No source was available, so this section is from the manual. Codes are from
its Appendix A, "ASCII and Keyword Codes".

### 5.1 New command tokens

| Token | Keyword | Purpose |
|---|---|---|
| &FA | `ALTER` | Search-and-replace through the program; also `ALTER DISPLAY`, `ALTER DEVICE` |
| &FB | `SORT` | Sort strings and string arrays |
| &FC | `JOIN` | Join program lines; `JOIN TO` appends strings |
| &FD | `EDIT` | `EDIT variable` — edit a variable's value |

These are the last four free command tokens. With MasterDOS's &F7–&F9, the
whole &F7–&FD range is taken, leaving only &FE and &D0.

### 5.2 New functions

Stored as `&FF` plus a code below the ROM's range:

| Code | Function | |
|---|---|---|
| &26 | `EXIT PROC` | **`[MB]`** |
| &27 | `EXIT DO` | **`[MB]`** |
| &28 | `EXIT FOR` | **`[MB]`** |
| &29 | `LOCN` | **`[MB]`** Search memory for a string |
| &2A | `RESERVED` | **`[MB]`** Reserve heap space |
| &2B | `EQU` | **`[MB]`** Case-insensitive string comparison |
| &2C | `TICS` | **`[MB]`** **`[MD]`** Elapsed time — needs a clock |
| &2D | `SHIFT$` | **`[MB]`** Case conversion |
| &2E | `SVAL$` | **`[MB]`** Number to compact string |
| &2F | `USING$` | **`[MB]`** Formatted number to string |
| &30–&36 | *MasterDOS functions* | **`[MD]`** |
| &37 | `SCRAD` | **`[MB]`** Screen address |
| &38 | `INARRAY` | **`[MB]`** Search a string array |
| &68 | `XVAR` | **`[MB]`** Extra system variables |
| &6A | `NVAL` | **`[MB]`** Inverse of `SVAL$` |

`EXIT PROC`, `EXIT DO` and `EXIT FOR` are *statements* despite living in the
function code range: a statement beginning with `&FF` fails the ROM's
dispatch and is picked up by the error-29 trap, which then looks at the
following code byte.

> **`XVAR` (&68) and `NVAL` (&6A) are the ROM's two free calculator function
> slots.** [extending-basic.md §4](extending-basic.md#4-the-token-budget)
> works out from the ROM's priority tables that &68 must be numeric→numeric
> and &6A string→numeric. `XVAR n` takes a number and returns one; `NVAL a$`
> takes a string and returns a number. MasterBASIC uses both, with exactly
> those signatures — which is a pleasing independent confirmation of the
> analysis, and means **those two slots are no longer free** on a machine
> with MasterBASIC loaded.

### 5.3 New control codes

| Code | Effect |
|---|---|
| 24 | Cursor left one word |
| 25 | Cursor right one word |

The ROM leaves 24–31 unused.

### 5.4 Feature summary

From the manual's contents, with the section headings it uses:

**Editing and debugging** — word left/right, last line recall, `JOIN` and
split program lines, `REF` program search, `PRINT REF`, `ALTER`
search-and-change, line number tracing, speed improvements.

**Data handling** — `EDIT variable`, `SORT` (with `ABS` and `INVERSE`
variants and sort-on-substring), deleting and joining strings and string
arrays.

**Data-handling functions** — `INARRAY`, `USING$`, `SVAL$`, `NVAL`,
`SHIFT$`, `EQU`.

**Sound** — `SOUND CLEAR`, `RECORD SOUND TO`, `RECORD SOUND OFF`,
`RECORD SOUND STOP`, `BLITZ SOUND`.

**Graphics** — an improved `PUT`, `COPY SCREEN n TO n`, faster animation via
`POKE`, `ALTER DISPLAY n TO n LINE n` for split-mode displays, `BLOCKS 2`
for extra UDGs, `CLS *`, `CSIZE` improvements, `SCRAD`.

**Printing** — interrupt-driven printing, serial input and output, screen
dumps, pound and hash characters.

**Timing** — **`[MD]`** `TIME +`, `TIME -`, `TICS`.

**Structured BASIC** — hiding procedures and functions, `EXIT PROC`,
`EXIT DO`, `EXIT FOR`.

**DOS enhancements** — `SAVE MODE` file compression, saving the
DOS/MasterBASIC boot file, `MERGE *`, protecting `CODE` files, `FORMAT`
enhancements, faster `DIR`.

**With MasterDOS** — RAM disk speed, `ALTER DEVICE drive TO drive`, serial
file buffers, alternative syntax for `COPY`/`RENAME`/`BACKUP`/`MOVE`, and
extensions to `FSTAT`, `DIR$` and `INP$`.

**Special purpose** — `LOCN`, `RESERVED`, an `INKEY$ #0` improvement,
`XVAR`, `DVAR` extensions.

---

## 6. The extended token map

Combining all three with the ROM. See
[user-manual/appendix-d-tokens-and-priorities.md](user-manual/appendix-d-tokens-and-priorities.md)
for the ROM's own map in full.

### 6.1 Function codes below the ROM's range

The ROM's evaluator rejects everything below `PI` (&3B), so this whole range
is available to an extension that hooks `EVALUV`:

| Code | Keyword | Tag |
|---|---|---|
| &26 | `EXIT PROC` | **`[MB]`** |
| &27 | `EXIT DO` | **`[MB]`** |
| &28 | `EXIT FOR` | **`[MB]`** |
| &29 | `LOCN` | **`[MB]`** |
| &2A | `RESERVED` | **`[MB]`** |
| &2B | `EQU` | **`[MB]`** |
| &2C | `TICS` | **`[MB]`** **`[MD]`** |
| &2D | `SHIFT$` | **`[MB]`** |
| &2E | `SVAL$` | **`[MB]`** |
| &2F | `USING$` | **`[MB]`** |
| &30 | `TIME$` | **`[MD]`** |
| &31 | `DATE$` | **`[MD]`** |
| &32 | `INP$` | **`[MD]`** |
| &33 | `DIR$` | **`[MD]`** |
| &34 | `FSTAT` | **`[MD]`** |
| &35 | `DSTAT` | **`[MD]`** |
| &36 | `FPAGES` | **`[MD]`** |
| &37 | `SCRAD` | **`[MB]`** |
| &38 | `INARRAY` | **`[MB]`** |
| &39, &3A | *free* | |

Note that the ROM reserves names for `INARRAY` (&49), `CHAR$` (&4E),
`USING$` (&51) and `SHIFT$` (&52) inside its own range and never implements
them. MasterBASIC implements three of those four — but at &38, &2F and &2D
instead, ignoring the ROM's reserved slots entirely. Presumably keeping all
its codes together below &3B was simpler than working within the ROM's
priority tables.

### 6.2 Function codes inside the ROM's range

| Code | Keyword | Tag | Note |
|---|---|---|---|
| &68 | `XVAR` | **`[MB]`** | One of the ROM's two free calculator slots |
| &6A | `NVAL` | **`[MB]`** | The other |
| &75 | — | | Not free: the calculator opcode is `INKEY$ #n` |
| &7D | — | | Still free — the unimplemented `BXOR` operator slot |

### 6.3 Command tokens

| Token | Keyword | Tag |
|---|---|---|
| &86 | `WRITE` | **`[SD2]`** **`[MD]`** |
| &90 | `DIR` | **`[DOS]`** |
| &91 | `FORMAT` | **`[DOS]`** |
| &92 | `ERASE` | **`[DOS]`** |
| &93 | `MOVE` | **`[MD]`** |
| &CF | `COPY` | **`[DOS]`** |
| &D0 | *free* | |
| &E3 | `RENAME` | **`[DOS]`** |
| &F1 | `PROTECT` | **`[DOS]`** |
| &F2 | `HIDE` | **`[DOS]`** |
| &F7 | `BACKUP` | **`[MD]`** |
| &F8 | `TIME` | **`[MD]`** |
| &F9 | `DATE` | **`[MD]`** |
| &FA | `ALTER` | **`[MB]`** |
| &FB | `SORT` | **`[MB]`** |
| &FC | `JOIN` | **`[MB]`** |
| &FD | `EDIT` | **`[MB]`** |
| &FE | *free* | |

**On a fully-loaded machine the only free command tokens are &D0 and &FE.**

---

## 7. External commands: how it is really done

[extending-basic.md §9](extending-basic.md#9-external-commands) reconstructs
the ROM authors' intended external-command design from their comments, and
notes that nothing reads `XCMDP`. Both DOSes confirm the second half of that:
**neither SAMDOS 2 nor MasterDOS uses `XCMDP`, and neither implements
dot-commands in the ROM's sense.** What they provide instead is a vector of
their own.

### `ONERR` — the external syntax vector

When the error-29 trap finds no command it recognises, it calls a vector
held in the DOS's own variable area:

```z80
;CHECK EXTERNAL SYNTAX VECTOR
               ld hl,(onerr)
               ld a,h
               or l
               ld a,(cstr1)
               call nz,extadd          ; SAMDOS 2
```

MasterDOS does the same and adds paging, so the handler may live in a page
of its own:

```z80
               LD   HL,(ONERR)
               LD   A,H
               OR   L
               LD   A,(SVCST)
               JR   Z,SYNT3
               BIT  7,H
               JP   Z,EXTADD           ; below &8000: call it directly
               IN   A,(251)
               LD   D,A
               LD   A,(EAPG)
               OUT  (251),A            ; else page EAPG in at &8000
               LD   A,(SVCST)
               JP   (HL)
```

`EXTADD` calls through the ROM's `JSVIN` jump-table entry (&0103), so the
handler runs with the system page mapped and on a private stack.

The handler is entered with **A = the error code** (29 or 53) and `CHAD`
pointing at the start of the failed statement. Returning normally lets the
error be reported as usual.

### Installing one

| | SAMDOS 2 | MasterDOS |
|---|---|---|
| `ONERR` | `DVAR 25` (2 bytes) | `DVAR 33` (2 bytes) |
| Page byte | none | `DVAR 36` (`EAPG`) |

So from BASIC, with MasterDOS:

```basic
DPOKE DVAR 33, myhandler        : REM below &8000, in the system page
POKE  DVAR 36, mypage           : REM only needed if the handler is at &8000+
```

This is the mechanism a `.command` implementation would actually be built on
today — not `XCMDP`, and not `RST8V`. It has three advantages over hooking
`CMDV` yourself: the DOS has already reset `CHAD` to the start of the
statement, it has already established a safe stack, and it will not call you
recursively.

> The two indices genuinely differ because the layouts diverge after
> `DVAR 7`. MasterDOS states its own index in a comment; the SAMDOS 2 figure
> was obtained by assembling the source, where `onerr − dvar` = 25.

---

## 8. What this tells us about the ROM

Four conclusions worth carrying back into the other documents:

1. **The error-trap route is the mainstream one.** Both DOSes catch error 29
   at their own error entry rather than hooking `CMDV`. The ROM's `PTDOS`
   path makes this far more comfortable than `RST8V`: the DOS is entered
   with its own page mapped and its own stack.

2. **`EVALUV` really can implement functions.** MasterDOS recovers
   `NUMCONT`/`STRCONT` by walking the ROM from the vector's return address.
   [extending-basic.md](extending-basic.md) previously said this could not be
   done without hard-coding unpublished addresses; it now documents the
   technique.

3. **The free-slot analysis holds.** MasterBASIC independently picked &68 and
   &6A — the two calculator slots the ROM's priority tables leave usable —
   and matched their fixed type signatures. It also left &7D (`BXOR`) alone,
   so that slot is still available.

4. **The system-page holes are contested.** MasterDOS puts stubs at both
   &4BA0 and &5896. An extension that wants to coexist with it cannot assume
   either region is free.

---

## Related documents

| Document | For |
|---|---|
| [user-manual/](user-manual/README.md) | The ROM language itself |
| [extending-basic.md](extending-basic.md) | Writing your own extension: hook contracts and worked examples |
| [user-manual/appendix-d-tokens-and-priorities.md](user-manual/appendix-d-tokens-and-priorities.md) | The ROM's own token map |
| [machine-code-interface.md](machine-code-interface.md) | The jump table and the calculator |
| [memory-map.md](memory-map.md) | What is free in the system page |

---

> [!WARNING]
> **AI-generated documentation.** The SAMDOS 2 and MasterDOS material is read
> from their published sources and can be checked line by line. The
> MasterBASIC material is from its manual only — no source was available —
> and has not been verified against the product. Nothing here has been run on
> hardware.
