# Appendix D — Tokens and Operator Priorities

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · [Appendix B](appendix-b-error-messages.md) · [Appendix C](appendix-c-character-codes.md) · **Appendix D**

---

## D.1 How keywords are stored

When you press ENTER, the tokeniser replaces each spelled-out keyword with
one or two bytes:

* **Commands and qualifiers** become a single byte in the range &85–&FE.
* **Functions and word-spelled operators** become **two** bytes: the prefix
  `&FF` followed by a code in the range &3B–&83.

The keyword table holds 196 entries. Matching is case-insensitive, and a
space in a table entry is optional — so `GOTO` and `GO TO`, `ENDIF` and
`END IF`, `DEFPROC` and `DEF PROC` all match. A keyword may not be
immediately followed by a letter (except for entries ending in `=`, `>` or
`$`), so `PRINTX` is not `PRINT X`.

After `REM`, tokenising stops for the rest of the line. Inside a string
literal nothing is tokenised.

Because tokens overlap the UDG character codes, the print routines resolve
the ambiguity from an in-quotes flag: `PRINT CHR$ 160` gives a UDG, listing
gives the keyword.

See [tokenized-program-format.md](../tokenized-program-format.md) for the
complete stored form of a program.

### Tags

Everything in sections D.2 to D.4 is ROM 3.0 unless tagged. The tags mark
keywords that only exist when an extension is loaded:

| Tag | Meaning |
|---|---|
| **`[DOS]`** | Any disk operating system |
| **`[SD2]`** | SAMDOS 2 |
| **`[MD]`** | MasterDOS |
| **`[MB]`** | MasterBASIC |

[dos-and-extensions.md](../dos-and-extensions.md) covers all three in
detail, including how each attaches itself to the ROM.

## D.2 Function and operator codes (`&FF` + code)

| Code | Keyword | | Code | Keyword |
|---|---|---|---|---|
| &3B | `PI` | | &60 | `IN` |
| &3C | `RND` | | &61 | `PEEK` |
| &3D | `POINT` | | &62 | `DPEEK` |
| &3E | `FREE` | | &63 | `DVAR` |
| &3F | `LENGTH` | | &64 | `SVAR` |
| &40 | `ITEM` | | &65 | `BUTTON` |
| &41 | `ATTR` | | &66 | `EOF` |
| &42 | `FN` | | &67 | `PTR` |
| &43 | `BIN` | | &68 | *(unused — see below)* |
| &44 | `XMOUSE` | | &69 | `UDG` |
| &45 | `YMOUSE` | | &6A | *(unused — see below)* |
| &46 | `XPEN` | | &6B | `LEN` |
| &47 | `YPEN` | | &6C | `CODE` |
| &48 | `RAMTOP` | | &6D | `VAL$` |
| &49 | *(unused)* | | &6E | `VAL` |
| &4A | `INSTR` | | &6F | `TRUNC$` |
| &4B | `INKEY$` | | &70 | `CHR$` |
| &4C | `SCREEN$` | | &71 | `STR$` |
| &4D | `MEM$` | | &72 | `BIN$` |
| &4E | *(unused)* | | &73 | `HEX$` |
| &4F | `PATH$` | | &74 | `USR$` |
| &50 | `STRING$` | | &75 | *(unused)* |
| &51 | *(unused)* | | &76 | `NOT` |
| &52 | *(unused)* | | &77–&79 | *(unused)* |
| &53 | `SIN` | | &7A | `MOD` |
| &54 | `COS` | | &7B | `DIV` |
| &55 | `TAN` | | &7C | `BOR` |
| &56 | `ASN` | | &7D | *(unused)* |
| &57 | `ACS` | | &7E | `BAND` |
| &58 | `ATN` | | &7F | `OR` |
| &59 | `LN` | | &80 | `AND` |
| &5A | `EXP` | | &81 | `<>` |
| &5B | `ABS` | | &82 | `<=` |
| &5C | `SGN` | | &83 | `>=` |
| &5D | `SQR` | | | |
| &5E | `INT` | | | |
| &5F | `USR` | | | |

Three boundaries in this table are structural:

| Boundary | Meaning |
|---|---|
| &4A (`INSTR`) | Below it, functions yield numbers; at and above, strings — until &53 |
| &53 (`SIN`) | The first function handled by the floating-point calculator rather than by the evaluator itself |
| &7A (`MOD`) | The first word-spelled binary operator |
| &80 (`AND`) | The last operator listed with spaces on both sides |

The ten unused codes — &49, &4E, &51, &52, &68, &6A, &75, &77–&79 and &7D —
have placeholder entries in the keyword table so the numbering stays right.
They are what a utility hooking `EVALUV` would claim.

Two of them are claimed in practice:

| Code | Keyword | | Note |
|---|---|---|---|
| &68 | `XVAR` | **`[MB]`** | Numeric argument, numeric result |
| &6A | `NVAL` | **`[MB]`** | String argument, numeric result |

The ROM's priority tables fix those two signatures, and MasterBASIC's
functions match them. &7D — the slot the unimplemented `BXOR` operator was
allocated — is still free.

### Function codes below &3B

The evaluator rejects any function code below `PI` (&3B), so this range is
invisible to the ROM and is where both extensions put their own functions.
None of these exist without the extension loaded.

| Code | Keyword | | Code | Keyword | |
|---|---|---|---|---|---|
| &26 | `EXIT PROC` | **`[MB]`** | &30 | `TIME$` | **`[MD]`** |
| &27 | `EXIT DO` | **`[MB]`** | &31 | `DATE$` | **`[MD]`** |
| &28 | `EXIT FOR` | **`[MB]`** | &32 | `INP$` | **`[MD]`** |
| &29 | `LOCN` | **`[MB]`** | &33 | `DIR$` | **`[MD]`** |
| &2A | `RESERVED` | **`[MB]`** | &34 | `FSTAT` | **`[MD]`** |
| &2B | `EQU` | **`[MB]`** | &35 | `DSTAT` | **`[MD]`** |
| &2C | `TICS` | **`[MB]`** **`[MD]`** | &36 | `FPAGES` | **`[MD]`** |
| &2D | `SHIFT$` | **`[MB]`** | &37 | `SCRAD` | **`[MB]`** |
| &2E | `SVAL$` | **`[MB]`** | &38 | `INARRAY` | **`[MB]`** |
| &2F | `USING$` | **`[MB]`** | &39–&3A | *free* | |

Note that the ROM reserves names for `INARRAY`, `USING$` and `SHIFT$` inside
its own range, at &49, &51 and &52, and never implements them. MasterBASIC
implements all three — but here, below &3B, ignoring the ROM's reserved slots.

## D.3 Qualifier tokens, &85–&8F

| Token | Keyword | Used by |
|---|---|---|
| &85 | `USING` | `FILL` |
| &86 | `WRITE` | *(unused by the ROM)* — **`[SD2]`** **`[MD]`** a record-file command |
| &87 | `AT` | Print items |
| &88 | `TAB` | Print items |
| &89 | `OFF` | *(unused by the ROM)* — **`[DOS]`** `PROTECT OFF`, `HIDE OFF` |
| &8A | `WHILE` | `DO`, `LOOP` |
| &8B | `UNTIL` | `DO`, `LOOP` |
| &8C | `LINE` | `SAVE`, `INPUT`, `READ`, `PALETTE` |
| &8D | `THEN` | `IF` |
| &8E | `TO` | Slicing, ranges, `FOR`, `OPEN` |
| &8F | `STEP` | `FOR`, `RENUM` |

## D.4 Command tokens, &90–&F6

A tag marks a command the ROM tokenises but dispatches to *Not understood* —
it works only when the tagged product is loaded. The tags are the ones
defined in [D.1](#tags); the claimed tokens are collected in a table of their
own [below](#command-tokens-claimed-by-the-extensions).

| Token | Keyword | | Token | Keyword |
|---|---|---|---|---|
| &90 | `DIR` **`[DOS]`** | | &C4 | `DEFAULT` |
| &91 | `FORMAT` **`[DOS]`** | | &C5 | `DIM` |
| &92 | `ERASE` **`[DOS]`** | | &C6 | `INPUT` |
| &93 | `MOVE` **`[MD]`** | | &C7 | `RANDOMIZE` |
| &94 | `SAVE` | | &C8 | `DEF FN` |
| &95 | `LOAD` | | &C9 | `DEF KEYCODE` |
| &96 | `MERGE` | | &CA | `DEF PROC` |
| &97 | `VERIFY` | | &CB | `END PROC` |
| &98 | `OPEN` | | &CC | `RENUM` |
| &99 | `CLOSE` | | &CD | `DELETE` |
| &9A | `CIRCLE` | | &CE | `REF` † |
| &9B | `PLOT` | | &CF | `COPY` **`[DOS]`** |
| &9C | `LET` | | &D0 | *(unused)* |
| &9D | `BLITZ` | | &D1 | `KEYIN` |
| &9E | `BORDER` | | &D2 | `LOCAL` |
| &9F | `CLS` | | &D3 | `LOOP IF` |
| &A0 | `PALETTE` | | &D4 | `DO` |
| &A1 | `PEN` (also `INK`) | | &D5 | `LOOP` |
| &A2 | `PAPER` | | &D6 | `EXIT IF` |
| &A3 | `FLASH` | | &D7 | `IF` (block form) |
| &A4 | `BRIGHT` | | &D8 | `IF` (single-line form) |
| &A5 | `INVERSE` | | &D9 | `ELSE` (block form) |
| &A6 | `OVER` | | &DA | `ELSE` (single-line form) |
| &A7 | `FATPIX` | | &DB | `END IF` |
| &A8 | `CSIZE` | | &DC | `KEY` |
| &A9 | `BLOCKS` | | &DD | `ON ERROR` |
| &AA | `MODE` | | &DE | `ON` |
| &AB | `GRAB` | | &DF | `GET` |
| &AC | `PUT` | | &E0 | `OUT` |
| &AD | `BEEP` | | &E1 | `POKE` |
| &AE | `SOUND` | | &E2 | `DPOKE` |
| &AF | `NEW` | | &E3 | `RENAME` **`[DOS]`** |
| &B0 | `RUN` | | &E4 | `CALL` |
| &B1 | `STOP` | | &E5 | `ROLL` |
| &B2 | `CONTINUE` | | &E6 | `SCROLL` |
| &B3 | `CLEAR` | | &E7 | `SCREEN` |
| &B4 | `GO TO` | | &E8 | `DISPLAY` |
| &B5 | `GO SUB` | | &E9 | `BOOT` |
| &B6 | `RETURN` | | &EA | `LABEL` |
| &B7 | `REM` | | &EB | `FILL` |
| &B8 | `READ` | | &EC | `WINDOW` |
| &B9 | `DATA` | | &ED | `AUTO` |
| &BA | `RESTORE` | | &EE | `POP` |
| &BB | `PRINT` | | &EF | `RECORD` |
| &BC | `LPRINT` | | &F0 | `DEVICE` |
| &BD | `LIST` | | &F1 | `PROTECT` **`[DOS]`** |
| &BE | `LLIST` | | &F2 | `HIDE` **`[DOS]`** |
| &BF | `DUMP` | | &F3 | `ZAP` |
| &C0 | `FOR` | | &F4 | `POW` |
| &C1 | `NEXT` | | &F5 | `BOOM` |
| &C2 | `PAUSE` | | &F6 | `ZOOM` |
| &C3 | `DRAW` | | &F7–&FE | *(unused by the ROM — see below)* |

† `REF` is only valid inside a `DEF PROC` parameter list; used as a statement
it gives *Not understood*.

`&FF` is the function prefix and never a command.

### Command tokens claimed by the extensions

The eight DOS-reserved spellings are implemented by a DOS; the seven tokens
above &F6 are new spellings the extensions add through `MTOKV`.

| Token | Keyword | | Note |
|---|---|---|---|
| &90 | `DIR` | **`[DOS]`** | |
| &91 | `FORMAT` | **`[DOS]`** | The ROM does use the keyword itself, in `LIST FORMAT n` |
| &92 | `ERASE` | **`[DOS]`** | |
| &93 | `MOVE` | **`[MD]`** | SAMDOS 2 does not implement this one |
| &CF | `COPY` | **`[DOS]`** | The ROM's own screen dump is `DUMP` |
| &E3 | `RENAME` | **`[DOS]`** | |
| &F1 | `PROTECT` | **`[DOS]`** | |
| &F2 | `HIDE` | **`[DOS]`** | |
| &F7 | `BACKUP` | **`[MD]`** | |
| &F8 | `TIME` | **`[MD]`** | |
| &F9 | `DATE` | **`[MD]`** | |
| &FA | `ALTER` | **`[MB]`** | Reserved but commented out in the MasterDOS source |
| &FB | `SORT` | **`[MB]`** | Likewise |
| &FC | `JOIN` | **`[MB]`** | |
| &FD | `EDIT` | **`[MB]`** | |

`SAVE`, `LOAD`, `MERGE`, `VERIFY`, `OPEN`, `CLOSE`, `CLEAR`, `READ`, `CALL`
and `RUN` all keep their ROM meanings but are extended by a DOS.

**With everything loaded, the only free command tokens are &D0 and &FE.**

### Notes on particular tokens

* **`INK` and `PEN` share token &A1.** `INK` is the last entry in the keyword
  table, and matching it would produce &FF — the function prefix — so the
  tokeniser substitutes `PEN`. A program typed with `INK` lists back with
  `PEN`.
* **`IF` and `ELSE` each have two tokens.** The tokeniser always produces the
  block form (&D7, &D9) because it appears first in the table; the syntax
  checker rewrites the stored byte to the single-line form (&D8, &DA) when it
  finds a `THEN`. Both spellings list identically.
* **`COPY` (&CF) is not implemented by the ROM**; its screen dump is `DUMP`
  (&BF). Both DOSes implement `COPY` as a file copy.
* **`FORMAT` (&91)** is reserved for DOS as a command, but the ROM does use
  the keyword in `LIST FORMAT n`.
* **&D0 and &F7–&FE are free in the ROM**, and are what a utility hooking
  `CMDV` would claim. In practice MasterDOS takes &F7–&F9 and MasterBASIC
  &FA–&FD, leaving only &D0 and &FE.

## D.5 Operator priorities

The scanner stacks each operator as a (priority, operation) pair. When an
incoming operator does not bind more tightly than the one on the stack, the
stacked one is performed. The same byte also carries the type rules — one bit
for "wants a numeric argument", another for "yields a number" — which is how
`a$ MOD b$` is rejected at typing time.

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

Three consequences to remember:

```basic
PRINT 10 * 7 MOD 3      : REM 10  -- MOD binds tighter than *
PRINT SIN x^2           : REM (SIN x)^2 -- the function is applied first
PRINT -2^2              : REM -4  -- ^ binds tighter than unary minus
```

When the left operand of an operator turns out to be a string, the operation
is remapped: `+` becomes concatenation and each comparison becomes its string
variant. Everything else applied to two strings is rejected.

## D.6 Invisible bytes in a stored line

Three things appear in a stored program that you never typed and never see:

| Marker | Length | Purpose |
|---|---|---|
| `&0E` + 5 bytes | 6 | The binary value of a numeric literal, written after its digits |
| `&0E FE FE FE` + 2 | 6 | An `FN` calling buffer, filled in by the compile pass |
| `&0E FD FD FD` + 2 | 6 | A `PROC` calling buffer |

The `&0E` marker makes every part of the ROM — the lister, the searcher, the
statement skipper — step over all six bytes. It is why a stored program is
larger than the text you typed, why numeric constants cost nothing at run
time, and why `FN` and `PROC` calls are as fast as they are.

A `DEF FN` parameter list gets the same treatment: each parameter name is
followed by a plain six-byte slot that the call fills with the argument's
value.

---

[Contents](README.md) · [Appendix A](appendix-a-keywords-a-l.md) · [Appendix B](appendix-b-error-messages.md) · [Appendix C](appendix-c-character-codes.md) · **Appendix D**
