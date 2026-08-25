# SAM BASIC — Tokenization, Compilation, and the In-Memory Program Format

This document describes, from the ROM 3.0 source, how SAM BASIC turns a typed
line into its stored form, how that form is "compiled" (call-site address
caching) before execution, and — in enough detail to write a converter that
turns the stored bytes back into text — exactly what the final in-memory
token stream looks like.

Source references: the tokenizer is `TOKPT2` in
[miscx2.asm](../miscx2.asm) (run from RAM via `TOKMAIN` in
[misc2.asm](../misc2.asm)); keyword matching is `GETTOKEN` in
[scrsel2.asm](../scrsel2.asm); the keyword table is `KEYWTAB` in
[text.asm](../text.asm); number embedding is `INSERT5B`/`CALC5BY` in
[eval.asm](../eval.asm); calling buffers are created by `MKCLBF`/`MAKESIX`
and resolved by `COMPILE`/`LKCALL`/`LOOKDF`/`LOOKDP` in [fn.asm](../fn.asm);
the reference detokenizer is `OUTLINE` in [scrfn.asm](../scrfn.asm) plus the
token printer in [tprint.asm](../tprint.asm).

## Contents

1. [Life cycle of a line](#1-life-cycle-of-a-line)
2. [The tokenizer](#2-the-tokenizer)
3. [Syntax check and the invisible 5-byte number forms](#3-syntax-check-and-the-invisible-5-byte-number-forms)
4. [String literals](#4-string-literals)
5. [FN and PROC calling buffers, and the COMPILE pass](#5-fn-and-proc-calling-buffers-and-the-compile-pass)
6. [Token rewriting: the two IFs and two ELSEs](#6-token-rewriting-the-two-ifs-and-two-elses)
7. [The final in-memory format (detokenizer specification)](#7-the-final-in-memory-format-detokenizer-specification)
8. [The complete token tables](#8-the-complete-token-tables)
9. [The 5-byte number format](#9-the-5-byte-number-format)
10. [Execution: how the stored form is consumed](#10-execution-how-the-stored-form-is-consumed)

---

## 1. Life cycle of a line

When ENTER is pressed in the editor, the main loop (`MAINELP`,
[mainlp.asm](../mainlp.asm)) processes the edit line (ELINE) in this order:

```text
EDITOR      collect keystrokes into ELINE (plain ASCII + any tokens that
            arrived via EDIT/DEF KEY, which insert already-tokenized text)
TOKMAIN     tokenize: replace spelled-out keywords with token bytes
LINESCAN    syntax-check every statement; as a side effect the expression
            evaluator INSERTS the invisible 5-byte forms after every numeric
            literal, and FN/PROC references get 6-byte calling buffers
then either:
INSERTLN    (line starts with a number) copy the line — tokens, 5-byte
            forms, calling buffers and all — into the program area
or:
COMPILE + LINERUN   (no line number) resolve calling buffers and execute
```

Two consequences worth stating up front:

* **A stored program line is byte-for-byte what the syntax checker left in
  ELINE.** Numbers carry both their ASCII text *and* a pre-converted 5-byte
  binary value; FN/PROC calls carry both the name text *and* a 6-byte address
  buffer. Nothing is recomputed from text at run time.
* Editing a line reverses the process: `EDIT` lists the line back into ELINE
  through channel "R", which expands tokens to text, while the &0E forms are
  simply *not printed* — they are recreated by the next LINESCAN.

`VAL`/`VAL$` ([rom1fns.asm](../rom1fns.asm) `FPVAL`) run the identical
pipeline — `TOKDE` then a checking `SCANSR` pass (which inserts 5-byte forms
into the workspace copy) then an executing pass — which is why VAL accepts
full expressions including spelled-out keywords.

`KEYIN` and `INPUT` also funnel their text through `TOKMAIN`+`LINESCAN`
(INPUT strips the inserted forms again with `REMOVEFP` before treating the
text as data).

---

## 2. The tokenizer

`TOKMAIN` copies the tokenizer body from ROM1 to `CDBUFF+&80` in the system
page and executes it there (ROM1 occupies the same addresses as the text
being tokenized, so it cannot run in place). The algorithm (`TOKPT2`):

1. **Scan** the line from the start. Stop at CR (&0D).
2. Bytes that cannot start a keyword are skipped, with three special cases:
   * `"` — skip to the closing quote (or CR). **Nothing inside string
     literals is ever tokenized.**
   * &FF — an already-present function token; skip the prefix *and* its code
     byte (so re-tokenizing an edited line is safe).
   * `<` and `>` are treated as possible word starts (for `<>`, `<=`, `>=`).
3. At a candidate word start (letter, `<`, `>`): copy up to **15 characters**
   to a scratch buffer, then call **`GETTOKEN`** with the keyword table
   (`KEYWTAB`, `KEYWNO` = 196 words). If GETTOKEN fails, the `MTOKV` vector
   is offered the word (user-extensible tokenizers); if that also fails, the
   scan resumes after the *whole* run of letters/underscores/`$` — so the
   tail of `printer` is not matched as a keyword.
4. `GETTOKEN` (scrsel2.asm) matches case-insensitively against the list
   (each list word's last letter has bit 7 set). Embedded spaces in list
   words (`GO TO`, `DEF FN`, `END PROC`, `LOOP IF`, `ON ERROR`, …) are
   *optional* in the input. After a complete match, the next input character
   must fail `ALDU` (letter, `_`, or `$`) unless the list word ends in `=`,
   `>` or `$` — this is the rule that leaves `printer`, `print_out` and
   `print$` alone while tokenizing `print1` and `print:`.
5. The 1-based match index A becomes the stored form:
   * **A < &4A** (the function section of the table): code = A + &3A,
     giving &3B–&83. The **first letter of the word is overwritten with the
     prefix &FF** and the code follows: functions and the alphabetic binary
     operators are stored as the two bytes `FF cc`.
   * **A ≥ &4A**: token = A + &3B, giving a **single byte &85–&FE**.
     Special case: the final list entry `INK` would yield &FF; the tokenizer
     substitutes **&A1 (PEN)** so INK may be typed as a synonym for PEN.
6. **Space absorption**: if the character before the word is a space, the
   token overwrites that space (one leading space is absorbed); if the
   character after the matched word is a space, it is included in the region
   that is closed up (one trailing space absorbed). The remaining spelled-out
   letters are removed with `RECLAIM1`. The lister re-synthesises these
   spaces on output, so listings look unchanged.
7. If the token just placed was **REM (&B7)**, tokenization stops for the
   rest of the line (REM text is preserved verbatim). Otherwise the scan
   continues after the token.

Note what the tokenizer does **not** do: it does not touch numbers, does not
create the &0E forms, and does not validate anything. All of that happens in
the syntax-check pass.

---

## 3. Syntax check and the invisible 5-byte number forms

`LINESCAN` runs the normal statement interpreter with FLAGS bit 7 = 0
("checking"). Command routines validate argument shapes and abort before
doing work (`ABORTER`). Expressions go through the same evaluator as at run
time (`SCANSR`, eval.asm), and this is where literal optimization happens.

**At check time**, when the evaluator meets a numeric literal (digits, `.`,
`&` hex, or the BIN token) — `INSERT5B`:

1. `CALC5BY` parses the text and leaves the value on the calculator stack
   (decimal with optional fraction and `E±nn`, `&`/`…H` hex via
   `AMPERSAND`, or binary after BIN).
2. `MAKESIX` opens **6 bytes in the line immediately after the literal
   text** and writes the marker **&0E**.
3. The value is popped off the calculator stack and its 5 bytes are copied
   after the marker.

So the stored form of `100` in a line is:

```text
31 30 30 0E 00 00 64 00 00
'1''0''0' ^  [ 5-byte value ]
          number marker
```

**At run time** the evaluator does the reverse: on seeing a digit it scans
forward to the next &0E (`LK0ELP`) and LDIRs the 5 bytes straight onto the
calculator stack — the ASCII is never re-parsed.

Everything else in the ROM knows the convention:

* The `NUMBER`/`RDCN` routine in the RST area of main.asm adds 6 to the
  pointer whenever it reads &0E — the canonical "skip invisible form"
  primitive used by the searcher, the statement skipper, and the lister.
* `SKIPSTATS`, `FINDERS` (program search) and `READ LINE` all call `NUMBER`
  so quoted colons, THEN, and number bytes that happen to look like &22 or
  &0D never confuse them.
* `REMOVEFP` strips every `&0E+5` group from a region (INPUT lines, DEF
  KEYCODE bodies) before the text is reused as text.
* **RENUM** (`CHGREF`, miscx1.asm) maintains the invariant: after renumbering
  it writes the new value into the 5-byte form *and* re-prints the digits,
  resizing the line if the digit count changed.

Limits enforced here: statements per line ≤ 127, line text ≤ &3EFF bytes,
line numbers 1–65279 (&FEFF).

---

## 4. String literals

String literals are **stored as typed and used in place**. At run time
(`SQUOTE`, eval.asm) a quoted string with no embedded `""` pairs is *not
copied anywhere*: the evaluator stacks a 5-byte string descriptor
(page, start, length) pointing **into the BASIC line itself**. Only strings
containing doubled quotes are copied (with the escapes collapsed) into the
workspace at run time.

So there is no separate stored form for strings — the "optimization" is the
absence of one, and any detokenizer simply copies the bytes between the
quotes verbatim (bytes ≥ &80 inside quotes are UDG/graphic characters, never
tokens; the tokenizer guaranteed that by skipping quoted text).

---

## 5. FN and PROC calling buffers, and the COMPILE pass

### Creation (syntax-check time)

When the checker meets `FN name…` (`FNSYN`) or a statement beginning with a
letter — a procedure call (`PROCSY`) — it validates the name and argument
list, then `MKCLBF` opens **6 bytes immediately after the name**:

```text
FN  call:   0E FE FE FE ?? ??
PROC call:  0E FD FD FD ?? ??
```

The &0E leader makes every generic routine treat the buffer exactly like a
number form (skip 6). The FD/FE filler marks it as an *unresolved* FN/PROC
buffer.

`DEF FN` itself (`DFNP2`, miscx2.asm) gets the same treatment for each
**parameter**: after each `letter` or `letter$` in its parameter list a
plain `0E xx xx xx xx xx` buffer is opened — at call time the argument
values are copied into these slots and `LKFNVAR` resolves single-letter
variables from them while the FN expression is evaluated.

### Resolution — `COMPILE` (fn.asm)

`COMPILE` runs before every execution: at `RUN`/`CLEAR`, and for the edit
line before every direct command. `COMPFLG` bit 7 (set by INSERTLN, LOAD,
DELETE, RENUM, KEYIN) requests a whole-program pass; the edit line is always
processed (FNs only when `REFFLG` recorded an FN in the line).

The pass does three things:

1. **Labels**: every `LABEL name` line assigns its own line number to the
   numeric variable `name` (so `GOTO name` works via a variable).
2. **DEF FN table**: one scan collects page/address of every `DEF FN` into
   INSTBUF (≤ 170 definitions, else error 52).
3. **Buffer patching**: `LKCALL` finds every calling buffer by searching for
   the byte pattern

   ```text
   (not &0E) &0E  FDFD|FEFE  (byte with bit 7 set)
   ```

   — a lone preceding &0E distinguishes a buffer from a numeric literal
   whose 5 bytes happen to contain FD/FE pairs, and `0E FE FE 80…` can never
   be a line header because it would imply a line length > 32768. The
   call-site name is read *backwards* from the buffer (letters, digits,
   `_`, `$`; a preceding `FF 42` "FN" token is skipped), then matched
   (case-insensitively, spaces ignored) against the DEF FN table or against
   `DEF PROC` statements found at line starts (`LKFC`). The buffer's last
   three bytes are patched:

   ```text
   resolved:    0E FE FE pp aa aa     pp = page OR &80, aaaa = address
   unresolved:  0E FE FE FF ?? ??     (bit 5 set = "no DEF FN/PROC")
   ```

   For FNs the address points just past the DEF FN name (at its `(` or
   `=`); for PROCs it points at the DEF PROC line so parameters and the
   body can be located. Page byte flags: bit 7 always set, bit 6 = external
   command (XCMDP mechanism), bit 5 = missing (checked at call time: errors
   7 "FN without DEF FN" / 12 "Missing DEF PROC").

### Use (run time)

`IMFN`/`PROCS` scan forward from the current position to the first &0E,
skip the two FD/FE bytes, page in `pp AND &1F`, and jump — no name search
ever happens during execution. Since programs move (edits, MAKEROOM) and
saved files are reloaded at different addresses, the addresses are simply
recomputed by the next COMPILE; the FD/FE signature bytes are what make the
buffers findable again.

---

## 6. Token rewriting: the two IFs and two ELSEs

The keyword list contains IF twice (&D7 "long IF", &D8 "short IF") and ELSE
twice (&D9 "long ELSE", &DA "short ELSE"); the tokenizer always produces the
*first* occurrence (&D7 / &D9). The **syntax checker rewrites the byte in
the stored line**:

* `LIF` (&D7) becomes `SIF` (&D8) when the condition is followed by THEN
  (`LIF`/`SIF` in do.asm write `LD (HL),&D8` into the line).
* `LELSE` (&D9) becomes `ELSE` (&DA) when the preceding IF on the line was
  short; `LELSE LIF cond` becomes `LELSE SIF cond` (the ELSE IF chain form).

Both pairs list identically ("IF", "ELSE"), so the distinction is invisible
in listings but present in the stored bytes — a detokenizer must map both
codes of each pair to the same word.

---

## 7. The final in-memory format (detokenizer specification)

### Program area

The program starts at (PROGP)/(PROG) and is a sequence of lines in ascending
line-number order, terminated by a byte **&FF** where the next line-number
MSB would be. (The edit line, at (ELINE), has the same *text* format but no
4-byte header — it is `[optional digits][text] 0D FF`.)

### Line layout

```text
offset 0   line number, MSB FIRST     (1–&FEFF; &FF here = end of program)
offset 1   line number, LSB
offset 2   text length, LSB           (length of text INCLUDING the final 0D)
offset 3   text length, MSB
offset 4   text bytes …
last       0D
```

Note the mixed endianness: line number big-endian (so lines compare
MSB-first during search), length little-endian.

### Text bytes

Process the text sequentially with an *in-quotes* flag (initially clear):

| Byte(s) | Meaning / action for a converter |
|---|---|
| &0D | End of line. |
| &0E | Invisible form — **emit nothing, skip 6 bytes total** (the marker + 5). This covers numeric literals (whose ASCII text precedes them), FN/PROC calling buffers (`0E FE FE …`/`0E FD FD …`, whose name precedes them), and DEF FN parameter buffers. Never toggles the quote flag, never counts as a statement boundary. |
| &22 `"` | Emit, and toggle the in-quotes flag. (A doubled `""` inside a string is simply two quote bytes: the flag toggles twice.) |
| &20–&7F | Plain ASCII — emit as-is. |
| &00–&1F (except &0D, &0E) | Literal control codes (colour controls &10–&15 with a parameter byte, AT &16 / TAB &17 with parameters, etc., typically inside strings or PRINT items). The interpreter skips them when scanning (RST &18 passes over bytes < &21); the lister sends them to the print routine, where they act. A text converter should pass them through (or escape them). |
| &80–&84 | Always UDG/block-graphic characters — emit as character codes, never keywords. |
| &85–&FE, in quotes | UDG/graphic characters — emit as character codes. |
| &85–&FE, not in quotes | **Keyword token** — emit the keyword text from [the table below](#8-the-complete-token-tables), with the spacing rules given there. |
| &FF, in quotes | UDG/graphic character &FF. |
| &FF, not in quotes | **Function prefix**: the next byte (&3B–&83) selects a function or alphabetic operator from the second table; emit its text with its spacing rules. (Codes outside &3B–&83 after &FF do not occur in checked lines.) |

Statement separators are the literal `:` byte (outside quotes) and the THEN
token (&8D); a converter need not treat them specially beyond normal token
expansion, except to reproduce SAM's pretty-listing (LIST FORMAT) behaviour,
which turns statement-separating `:` into newline + 6-space indent and
applies block indenting driven by the structural tokens (see `SPACES`,
scrfn.asm).

### Spacing on output

The tokenizer absorbed up to one space on each side of every keyword, so a
faithful lister re-inserts them (`POFN`/`POBTL`/`POMSG3` in tprint.asm):

* Single-byte tokens (&85–&FE): print a **leading space** unless the
  previously emitted character was already a space, and a **trailing
  space** if the keyword ends in a letter or `$`.
* &FF-pair operators MOD, DIV, BOR, BAND, OR, AND (&7A–&80): leading and
  trailing space.
* &FF-pair `<>`, `<=`, `>=` (&81–&83): no spaces.
* &FF-pair FN (&42) and BIN (&43): trailing space only.
* All other &FF-pair functions: no leading space; trailing space if the
  name ends in a letter or `$` (i.e. all of them — so `SIN x`, `CHR$ a`).

A converter that only needs *re-tokenizable* text (rather than
column-identical listings) can simply emit one space either side of every
keyword.

### Worked example

`10 IF a>1 THEN PRINT "ok": GO TO 100` is stored as (hex):

```text
00 0A                      line number 10 (MSB first)
1C 00                      text length 28 (includes the 0D)
D8                         SIF   ("IF" rewritten because THEN follows)
61                         'a'
3E                         '>'   (single-char operators stay plain ASCII)
31 0E 00 00 01 00 00       '1' + invisible form (value 1)
8D                         THEN
BB                         PRINT
22 6F 6B 22                '"' 'o' 'k' '"'
3A                         ':'
B4                         GO TO
31 30 30 0E 00 00 64 00 00 '1''0''0' + invisible form (value 100)
0D
```

(The `>` comparison is a plain ASCII byte; only the two-character
comparisons and the alphabetic operators are FF-pairs.)

---

## 8. The complete token tables

### Single-byte tokens &85–&FE (and the &FF prefix)

Derived from `KEYWTAB` order and the `CMDADT` comments in
[text.asm](../text.asm). "—" entries are unused codes (never produced by the
tokenizer; if encountered, treat as UDG characters).

| Code | Keyword | Code | Keyword | Code | Keyword | Code | Keyword |
|---|---|---|---|---|---|---|---|
| &85 | USING | &A4 | BRIGHT | &C3 | DRAW | &E2 | DPOKE |
| &86 | WRITE | &A5 | INVERSE | &C4 | DEFAULT | &E3 | RENAME |
| &87 | AT | &A6 | OVER | &C5 | DIM | &E4 | CALL |
| &88 | TAB | &A7 | FATPIX | &C6 | INPUT | &E5 | ROLL |
| &89 | OFF | &A8 | CSIZE | &C7 | RANDOMIZE | &E6 | SCROLL |
| &8A | WHILE | &A9 | BLOCKS | &C8 | DEF FN | &E7 | SCREEN |
| &8B | UNTIL | &AA | MODE | &C9 | DEF KEYCODE | &E8 | DISPLAY |
| &8C | LINE | &AB | GRAB | &CA | DEF PROC | &E9 | BOOT |
| &8D | THEN | &AC | PUT | &CB | END PROC | &EA | LABEL |
| &8E | TO | &AD | BEEP | &CC | RENUM | &EB | FILL |
| &8F | STEP | &AE | SOUND | &CD | DELETE | &EC | WINDOW |
| &90 | DIR | &AF | NEW | &CE | REF | &ED | AUTO |
| &91 | FORMAT | &B0 | RUN | &CF | COPY | &EE | POP |
| &92 | ERASE | &B1 | STOP | &D0 | — | &EF | RECORD |
| &93 | MOVE | &B2 | CONTINUE | &D1 | KEYIN | &F0 | DEVICE |
| &94 | SAVE | &B3 | CLEAR | &D2 | LOCAL | &F1 | PROTECT |
| &95 | LOAD | &B4 | GO TO | &D3 | LOOP IF | &F2 | HIDE |
| &96 | MERGE | &B5 | GO SUB | &D4 | DO | &F3 | ZAP |
| &97 | VERIFY | &B6 | RETURN | &D5 | LOOP | &F4 | POW |
| &98 | OPEN | &B7 | REM | &D6 | EXIT IF | &F5 | BOOM |
| &99 | CLOSE | &B8 | READ | &D7 | IF (long) | &F6 | ZOOM |
| &9A | CIRCLE | &B9 | DATA | &D8 | IF (short) | &F7–&FE | — |
| &9B | PLOT | &BA | RESTORE | &D9 | ELSE (long) | &FF | *function prefix* |
| &9C | LET | &BB | PRINT | &DA | ELSE (short) | | |
| &9D | BLITZ | &BC | LPRINT | &DB | END IF | | |
| &9E | BORDER | &BD | LIST | &DC | KEY | | |
| &9F | CLS | &BE | LLIST | &DD | ON ERROR | | |
| &A0 | PALETTE | &BF | DUMP | &DE | ON | | |
| &A1 | PEN | &C0 | FOR | &DF | GET | | |
| &A2 | PAPER | &C1 | NEXT | | | | |
| &A3 | FLASH | &C2 | PAUSE | | | | |

Notes: &D7/&D8 both list as `IF`; &D9/&DA both list as `ELSE`. Typing `INK`
tokenizes to &A1 (PEN). The tokenizer never emits &90–&93, &E3, &F1, &F2 as
*executable* commands' targets in this ROM (their CMDADT entries are
NONSENSE, reserved for DOS), but the tokens themselves are produced and
stored normally.

### &FF-prefixed function/operator codes &3B–&83

| Code | Name | Code | Name | Code | Name | Code | Name |
|---|---|---|---|---|---|---|---|
| &3B | PI | &4E | — (CHAR$) | &61 | PEEK | &74 | USR$ |
| &3C | RND | &4F | PATH$ | &62 | DPEEK | &75 | — (INKEY$ dup) |
| &3D | POINT | &50 | STRING$ | &63 | DVAR | &76 | NOT |
| &3E | FREE | &51 | — (USING$) | &64 | SVAR | &77–&79 | — |
| &3F | LENGTH | &52 | — (SHIFT$) | &65 | BUTTON | &7A | MOD |
| &40 | ITEM | &53 | SIN | &66 | EOF | &7B | DIV |
| &41 | ATTR | &54 | COS | &67 | PTR | &7C | BOR |
| &42 | FN | &55 | TAN | &68 | — | &7D | — (BXOR) |
| &43 | BIN | &56 | ASN | &69 | UDG | &7E | BAND |
| &44 | XMOUSE | &57 | ACS | &6A | — | &7F | OR |
| &45 | YMOUSE | &58 | ATN | &6B | LEN | &80 | AND |
| &46 | XPEN | &59 | LN | &6C | CODE | &81 | <> |
| &47 | YPEN | &5A | EXP | &6D | VAL$ | &82 | <= |
| &48 | RAMTOP | &5B | ABS | &6E | VAL | &83 | >= |
| &49 | — (INARRAY) | &5C | SGN | &6F | TRUNC$ | | |
| &4A | INSTR | &5D | SQR | &70 | CHR$ | | |
| &4B | INKEY$ | &5E | INT | &71 | STR$ | | |
| &4C | SCREEN$ | &5F | USR | &72 | BIN$ | | |
| &4D | MEM$ | &60 | IN | &73 | HEX$ | | |

Internally the evaluator subtracts &1A from these codes (giving &21–&69) to
index its dispatch tables — that offset appears throughout eval.asm and
fpcmain.asm but never in the stored program.

---

## 9. The 5-byte number format

The 5 bytes after an &0E marker (and every entry on the calculator stack)
use the same two-form representation as the ZX Spectrum:

**Small integer form** (any integer −65535…65535):

| Byte | Contents |
|---|---|
| 0 | &00 (marks integer form) |
| 1 | Sign — &00 positive, &FF negative |
| 2 | Value LSB (two's-complement 16-bit value; e.g. −5 is stored `00 FF FB FF 00`) |
| 3 | Value MSB |
| 4 | &00 |

**Floating-point form** — the magnitude is $`m \times 2^{e-128}`$ with the
mantissa normalised to $`0.5 \le m < 1`$:

| Byte | Contents |
|---|---|
| 0 | Exponent $`e`$ (&01–&FF, bias &80) |
| 1 | Mantissa byte 1 — bit 7 **replaced** by the sign (0 = +, 1 = −); the mantissa's own top bit is implicit (always 1) |
| 2–4 | Mantissa bytes 2–4, most significant first |

Byte 0 = 0 always means integer form; a zero *value* is
`00 00 00 00 00`. Examples: `1.0` FP form = `81 00 00 00 00`
(usually stored as integer `00 00 01 00 00`); `0.5` = `80 00 00 00 00`;
`π/2` = `81 49 0F DA A2`.

A detokenizer normally ignores these bytes (the ASCII text precedes them),
but a *verifier* can decode and compare; conversely a program **generator**
must supply them, since the run-time evaluator reads only the 5-byte form.
Conversion between forms is `RESTACK`/`FPFORM` (mult.asm) and
`INT`/`FPTOBC` (tadjm.asm).

---

## 10. Execution: how the stored form is consumed

For completeness, the run-time reading conventions a converter should be
aware of:

* **Character fetch** (`RST &18`/`RST &20`): skips every byte &00–&20 except
  CR. Spaces and stray control bytes are therefore insignificant outside
  strings — but note the tokenizer already removed at most one space around
  keywords; others remain stored.
* **Command dispatch** (`STMTLP`): the first significant byte of a statement
  must be ≥ &90 (a command token) or a letter (implicit PROC call — also
  LET-less assignment is *not* supported; `LET` has its own token). The
  token −&90, doubled, indexes the CMDADDRT word table.
* **Numbers**: first digit/`.`/`&`/BIN encountered in an expression triggers
  the scan-to-&0E described in §3.
* **FN/PROC**: scan-to-&0E from the name, then use the patched page/address
  (§5).
* **Statement/line addressing**: GOTO/GOSUB/RETURN/NEXT/LOOP store and use
  (page, line-start address, statement-number) triples — statement numbers
  count `:`/THEN boundaries from 1, so a converter that renumbers or edits
  statements changes program meaning for CONTINUE/POP but not for stored
  programs (those triples exist only on the run-time BASIC stack, never in
  the program area).
* The only bytes in the *program area* that encode addresses are the
  calling buffers — and they are recomputed by COMPILE before every run, so
  a converter may safely emit them unresolved (`0E FE FE FE 00 00` /
  `0E FD FD FD 00 00`) as the syntax checker does.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
