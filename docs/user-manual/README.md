# The SAM BASIC User Manual

A complete guide to SAM BASIC, the language built into ROM 3.0 of the SAM
Coupé — from your first `PRINT` to writing procedures, driving the graphics
hardware, and reaching into the machine's system variables.

Everything here is derived from the ROM source itself (the annotated tree in
[`../../annotated/`](../../annotated/)) rather than from the original printed
manual, so where the two disagree, this describes what the machine actually
does.

---

## How to use this manual

The chapters build on one another. If you are new to programming, read
1–7 in order; everything after that can be dipped into as you need it. If you
already know another BASIC, skim chapters 3–5 for the differences (SAM BASIC
has long variable names, block `IF`, `DO`/`LOOP`, and no line numbers in
control flow) and then go straight to what interests you.

The **appendices** are reference, not tutorial. Appendix A lists every
keyword alphabetically with its full syntax; keep it open while you program.

## Part I — The basics

| | Chapter | What it covers |
|---|---|---|
| 1 | [First steps](01-first-steps.md) | The screen, direct commands, `PRINT`, your first program, `RUN`, `LIST`, `NEW` |
| 2 | [The editor and your environment](02-the-editor.md) | Typing and editing lines, cursor keys, `EDIT`, `AUTO`, `DELETE`, `RENUM`, `LIST FORMAT`, function keys, `DEF KEYCODE`, `KEY` |
| 3 | [Numbers, strings and variables](03-numbers-strings-and-variables.md) | Number format and precision, string literals, variable names, `LET`, `DEFAULT`, slicing, `DIM`, arrays, `LENGTH` |
| 4 | [Expressions and operators](04-expressions-and-operators.md) | Every operator, its priority and type rules; how the evaluator works; the complete function list |

## Part II — Writing programs

| | Chapter | What it covers |
|---|---|---|
| 5 | [Decisions and loops](05-decisions-and-loops.md) | `IF`/`THEN`/`ELSE`/`END IF`, `DO`/`LOOP`, `WHILE`, `UNTIL`, `EXIT IF`, `LOOP IF`, `FOR`/`NEXT`, `GOTO`, `GOSUB`, `ON`, `POP`, `LABEL`, `STOP`, `CONTINUE`, `PAUSE` |
| 6 | [Procedures and functions](06-procedures-and-functions.md) | `DEF PROC`, calling by name, parameters, `REF`, `LOCAL`, `DEF PROC … DATA`, `END PROC`, `DEF FN`, `FN`, recursion, `KEYIN` |
| 7 | [Input and output](07-input-and-output.md) | `PRINT` items and separators, `AT`, `TAB`, `INPUT`, `INPUT LINE`, `GET`, streams and channels, `OPEN #`, `CLOSE #`, `LPRINT`, `LLIST`, `DUMP`, stream 16 and `RECORD` |

## Part III — The machine

| | Chapter | What it covers |
|---|---|---|
| 8 | [The screen and colour](08-the-screen-and-colour.md) | `MODE`, `CSIZE`, `FATPIX`, `BLOCKS`, `WINDOW`, the colour commands, `PALETTE`, `BORDER`, `CLS`, `ROLL`, `SCROLL`, multiple screens |
| 9 | [Graphics](09-graphics.md) | The coordinate system, `xos`/`yos`/`xrg`/`yrg`, `PLOT`, `DRAW`, `CIRCLE`, `FILL`, `POINT`, `ATTR`, `SCREEN$`, `GRAB`, `PUT`, `BLITZ`, `RECORD` |
| 10 | [Sound](10-sound.md) | `BEEP`, `SOUND` and the SAA1099, `ZAP`, `POW`, `BOOM`, `ZOOM` |
| 11 | [Data, files and devices](11-data-files-and-devices.md) | `DATA`/`READ`/`RESTORE`/`ITEM`, `SAVE`, `LOAD`, `VERIFY`, `MERGE`, file types, `DEVICE`, `BOOT`, the DOS functions |

## Part IV — Mastery

| | Chapter | What it covers |
|---|---|---|
| 12 | [Errors and debugging](12-errors-and-debugging.md) | How errors are reported, `ON ERROR`, recovering, and debugging technique |
| 13 | [Memory and machine code](13-memory-and-machine-code.md) | The 0–524287 address model, `PEEK`/`POKE`/`DPEEK`/`DPOKE`, `CALL`, `USR`, `USR$`, `IN`/`OUT`, `FREE`, `RAMTOP`, `CLEAR`, page reservation |
| 14 | [System variables](14-system-variables.md) | `SVAR`, and the complete annotated table of every system variable you can read or write |
| 15 | [Expert techniques](15-expert-techniques.md) | Speed, the tokenised program format, style, extending BASIC through the ROM vectors, external commands |

## Appendices

| | Appendix | Contents |
|---|---|---|
| A | [Keyword reference A–L](appendix-a-keywords-a-l.md) · [M–Z](appendix-a-keywords-m-z.md) | Every keyword and function, alphabetically, with syntax, semantics, errors and an example |
| B | [Error messages](appendix-b-error-messages.md) | All 56 reports, what causes each, and what to do |
| C | [Character codes](appendix-c-character-codes.md) | The character set, control codes, block graphics, UDGs |
| D | [Tokens and operator priorities](appendix-d-tokens-and-priorities.md) | Token values, function codes, the priority table |

## Companion documents

These describe the ROM rather than the language, and are worth reading once
you start writing machine code or picking the ROM apart:

* [dos-and-extensions.md](../dos-and-extensions.md) — what SAMDOS 2, MasterDOS and MasterBASIC add on top of the ROM
* [extending-basic.md](../extending-basic.md) — adding your own commands, functions, operators and external commands
* [memory-map.md](../memory-map.md) — the system page and BASIC area layout
* [machine-code-interface.md](../machine-code-interface.md) — jump table, restarts, the FP calculator, `CALL`/`USR` protocol
* [tokenized-program-format.md](../tokenized-program-format.md) — the tokeniser and the exact stored form of a program
* [file-formats.md](../file-formats.md) — saved-file headers
* [font-rendering.md](../font-rendering.md) — character cell geometry
* [hudg.md](../hudg.md) — the font pointers and the dormant high-UDG range
* [constants.md](../constants.md) — every constant in the ROM source
* [source-files.md](../source-files.md) — per-file, per-routine reference

---

## Conventions used in this manual

| Notation | Meaning |
|---|---|
| `WORD` | Type it exactly (case does not matter — the tokeniser folds case) |
| *italic* | Something you supply |
| `[ ]` | Optional |
| `{a \| b}` | Choose one |
| `…` | The preceding item may repeat |

Examples are shown as you would type them. A `>` prompt is never shown —
SAM has no prompt character; you simply type onto the lower part of the
screen.

---

> [!WARNING]
> **AI-generated documentation.** This manual was written from the annotated
> ROM source with AI assistance and has not been checked against real
> hardware. It is a well-evidenced reading of the code, not the original
> author's own documentation. Where behaviour matters, verify it.
