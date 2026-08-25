# Annotated SAM Coupé ROM 3.0 source

A parallel copy of the ROM source, documented as a modern codebase would be: file-level overviews, per-routine
contracts (entry, exit, registers used, notes), inline explanation of non-obvious code, and named constants in place
of magic numbers.

**The annotated source is intended to assemble to a byte-identical ROM image.** Nothing here changes behaviour.

> [!WARNING]
> This annotation was produced with AI assistance and has not been assembled on real hardware (see
> [Verification](#verification) for what *has* been checked). Treat the commentary as a well-evidenced reading of the
> code, not as the author's own documentation.

## Status

**Complete.** All 39 source files have been converted, plus the new `equates.asm`. The annotated tree assembles to
an image byte-identical to the one built from the original source.

| File | Lines (orig → annotated) | Contents |
|---|---|---|
| `samrom.asm` | 49 → 73 | Build glue; include order changed (see below) |
| `equates.asm` | — → 670 | **New file**: named constants |
| `vars.asm` | 527 → 655 | System variable map; adds legacy token aliases |
| `main.asm` | 552 → 872 | Restarts, interrupt entries, public jump table, inter-ROM linkage |
| `lookvar.asm` | 328 → 372 | Variable lookup; documents both variable storage layouts |
| `misc1.asm` | 507 → 623 | Streams and channels, colour state, READ, POKE, the 0-512K address model |
| `editor.asm` | 648 → 786 | The line editor, channel R, DEF KEY expansion |
| `list.asm` | 657 → 800 | AUTOLIST, LIST, CLS, PRINT, listing cursor movement |
| `mainlp.asm` | 775 → 862 | Interpreter main loop, syntax pass, line insertion, error handling |
| `eval.asm` | 894 → 1004 | Expression evaluator, operator priorities, literal conversion |
| `do.asm` | 823 → 967 | DO/LOOP, IF/ELSE, FOR/NEXT, BASIC stack, line finder |
| `grabput.asm` | 472 → 543 | GRAB and PUT block graphics, FARLDIR cross-page block move |
| `tadjm.asm` | 907 → 1114 | Calculator stack, program searcher, MAKEROOM/RECLAIM, page arithmetic, tape edges |
| `assign.asm` | 1004 → 1156 | Assignment, array indexing, string slicing, DIM |
| `fn.asm` | 995 → 1097 | DEF FN/FN, DEF PROC/PROC, LOCAL, the call-buffer compile pass |
| `nparpro.asm` | 772 → 872 | PROC parameter binding by value and by REF, RESTORE, local teardown |
| `misc2.asm` | 997 → 1137 | RST 8 dispatch and DOS hand-off, ROM1-to-RAM stubs, LET, RUN/CLEAR, syntax helpers |
| `endprint.asm` | 988 → 1160 | Per-mode character rendering, screen and pixel addressing, the fixed routines |
| `graph0.asm` | 529 → 642 | CIRCLE and DRAW: midpoint circle, Bresenham line, off-screen checking |
| `graph1.asm` | 313 → 380 | PLOT and the per-mode, per-`OVER` pixel plot routines dispatched through IY |
| `graph2.asm` | 1093 → 1333 | BLITZ, flood FILL and its check screen, coordinate ranges and offsets, the graphics recorder |
| `roll.asm` | 847 → 1140 | ROLL and SCROLL, the editor's window scroller, mode 0 scan stepping |
| `fpcmain.asm` | 766 → 844 | Floating-point calculator: opcode table, fetch-execute loop, stack primitives |
| `mult.asm` | 827 → 987 | Multiply, divide, add, subtract; integer fast paths and the 32-bit mantissa loops |
| `transend.asm` | 407 → 521 | SIN, COS, TAN, EXP, LN, ATN, ASN, ACS and `^`, as calculator bytecode |
| `printfp.asm` | 564 → 682 | Number to decimal string: shift-and-DAA integer conversion, ×10 fraction conversion |
| `miscx2.asm` | 517 → 589 | DEF KEYCODE, DEF FN, **the tokeniser**, MERGE |
| `miscx1.asm` | 782 → 923 | The RAM-executed routines: RENUMBER, GET, DELETE, KEYIN, POP, INPUT |
| `misc31.asm` | 695 → 812 | CALL, cold-start RAM sizing and initialisation, NEW, font unpacking, PALETTE |
| `misc32.asm` | 653 → 811 | BEEP and the sound effects, colour items, BORDER, WINDOW, RANDOMIZE |
| `scrsel2.asm` | 663 → 815 | GOTO/GOSUB, the keyword matcher, MODE and CSIZE, AUTO, SOUND, the disk boot loader |
| `scrfn.asm` | 774 → 918 | COPY, `SCREEN$`, listing output, the pretty-listing indent machinery |
| `tapex.asm` | 567 → 720 | Tape and network block transfer: pulse encoding, leader detection, bit timing |
| `using.asm` | 842 → 997 | Pointer adjustment after memory moves, printer output, heap, INSTR, LENGTH, `STRING$`, curved DRAW |
| `tprint.asm` | 832 → 1000 | The print path: ASCII, tokens, UDGs, control codes, scrolling |
| `rom1fns.asm` | 877 → 1193 | VAL, RND, ATTR, POINT, the string producers, SQR/ABS/SGN/INT/TRUNCATE, UDG |
| `scrsel1.asm` | 878 → 1125 | Screens and streams, page allocation, the interrupt handler, the keyboard scanner |
| `tapemn.asm` | 929 → 1134 | SAVE/LOAD/VERIFY/MERGE: header building, matching and reconciliation |
| `text.asm` | 1406 → 1589 | Messages and their compression, the keyword table, dispatch tables, key map, character set |
| `romtest.asm` | 110 → 170 | Standalone: compare the assembled image against the live ROM |

`annotated/samrom.asm` includes every file in the directory, so the tree builds on its own; the check script still
overlays it onto the originals so the two images can be compared side by side.

## Conventions

### File header

Each file opens with a banner giving its purpose, the routines it contains grouped by theme, and any structural
constraint a reader needs up front (paging assumptions, why a body is copied to RAM before execution, and so on).

### Routine header

```asm
; ---------------------------------------------------------------------------------------------------------------------
; NAME -- one-line summary
;
; Longer explanation of the algorithm and why it is written this way.
;
; Entry:  A  = ...
;         HL = ...
; Exit:   BC = ...
;         CY set if ...
; Notes:  ...
; ---------------------------------------------------------------------------------------------------------------------
```

Entry/Exit are stated wherever the original comments or the call sites make the contract determinable. Where a routine
has several entry points, each is documented at its label.

### Layout

* Labels in column 0, mnemonics in column 13, comments aligned at column 41 where practical.
* Maximum line length 120 characters.
* Section banners use `=` rules, routine headers `-` rules.

### Naming

New constants are prefixed so they can never collide with the original symbols, none of which contain an underscore:

| Prefix | Meaning | Example |
|---|---|---|
| `ERR_` | Error/report code passed after `RST &08` | `ERR_NONSENSE` (29) |
| `HOOK_` | DOS hook code | `HOOK_AUTOLOAD` (136) |
| `TOK_` | Single-byte BASIC keyword token | `TOK_REM` (&B7) |
| `FN_` | Function code following the `&FF` prefix | `FN_SIN` (&53) |
| `F...` | Bit mask within a named flag byte | `FFLAGRUN`, `FTVAUTOLIST` |
| `LMPR`/`VID` | Paging and video port bit values | `LMPRROM1`, `VIDMODE` |
| `CC_` | Print control code | `CC_AT` (22) |
| `FT_` | Save/load file type | `FT_BASIC` (16) |
| `RDIR`/`RS` | ROLL/SCROLL direction and mode | `RDIRDOWN` (4), `RSROLL` (&FF) |
| `SCLIST` | Field within a screen list entry | `SCLISTPAGE` (%00011111) |
| `KB` | Keyboard queue and matrix geometry | `KBQMASK` (7), `KBSHCTRL` (3) |
| `BLZ` | BLITZ command code | `BLZCIRCLE` (3) |
| `SKIP...` | Opcode literal used as a "jump over the next instruction" | `SKIP1CP` (&FE) |

The handful of constants the original source already named (`SAVETOK`, `THENTOK`, `LRPORT`, …) keep those names.
Token names are retained in `vars.asm` as aliases of the systematic `TOK_`/`FN_` definitions, so both spellings
resolve to the same value and older listings stay readable.

### Include order

`annotated/samrom.asm` pulls `equates.asm` and `vars.asm` in **before** `main.asm`, where the original included
`vars.asm` second. Both files contain nothing but `EQU` definitions and emit no bytes, so the image is unaffected —
and every module can now refer to ports, tokens and system variables by name rather than by literal.

## Verification

### Confirmed by assembly

pyz80 1.3.0 builds the annotated tree to an image **byte-identical** to the original. `check.sh` performs the whole
comparison:

```sh
python -m pip install pyz80
annotated/check.sh
```

```text
samrom.asm  (40 annotated files): BYTE-IDENTICAL
romtest.asm: BYTE-IDENTICAL

verify_annotated.py: FAILURES: 0
```

It builds `samrom.asm` from the repository root and from `annotated/`, compares the binaries, does the same for
`romtest.asm` — which `samrom.asm` does not include — and then runs the static checker, which reports *which line*
differs when something does. Exit status is 0 only if every comparison matched, so it drops straight into a hook or
a CI step. Run it after every edit.

Options: `--overlay` copies `annotated/*.asm` over a copy of the originals and builds that instead, which is what
made it possible to verify one file at a time during the conversion and is still the right mode for a partial
tree; `--no-verify` skips the static checker; `--keep` leaves the build directory behind.

The script finds pyz80 itself, including in the per-user scripts directory Windows installs it into. Note that the
pip package provides a console script called `pyz80`, **not** `pyz80.py`; the repository's `Makefile` and
`make.bat` still invoke the older script name.

The annotated tree is self-contained, so the default mode is a genuine standalone build. Both the reordered
includes and the forward-referenced constants assemble cleanly, so the two open questions noted below are now
closed.

Note that the pip package installs a `pyz80` console script, **not** `pyz80.py`; the repository's `Makefile` and
`make.bat` still invoke the older script name.

`romtest.asm` is not reachable from `samrom.asm`, so it is checked by building it separately in both trees and
comparing the two images the same way.

### Pre-existing source/image discrepancy

The assembled original differs from `roms/ROM30` in exactly three bytes, at ROM1 &F5F8-&F5FA (file offset 30200, in
the copyright banner at `UMVAL` = &F5DD): the source spells the
copyright banner `MILES GORDON TECHNOLOGY PLC` where the shipped image has `plc`. This predates the annotation and
is unaffected by it — but it does mean the source is not quite a byte-exact reconstruction of the official image,
despite what `ReadMe.txt` implies.

### Static equivalence check

`verify_annotated.py` checks equivalence directly from the text, which is useful for spotting mistakes without a
full build and for pinpointing *which line* differs when a build does fail:

1. Strip comments and blank lines.
2. Build a symbol table from every `EQU` in both trees and resolve each to an integer.
3. Normalise each code line: canonicalise numeric literals (`&FF`, `%11111111`, `255`, `"A"`) to decimal, substitute
   resolved symbols for their values, constant-fold arithmetic operands, and standardise whitespace and case.
4. Compare the resulting instruction streams line for line.

If the streams match, the two files must assemble identically — no annotation or renaming can have altered the
emitted bytes. Memory indirection is distinguished from arithmetic so `LD HL,(CHAD)` is never confused with a folded
constant; folded values are compared modulo 65536 so `-SCANBYTESM23` and `&FF80` are recognised as the same word;
and includes of files that emit nothing are ignored so the reordering above is not flagged.

```sh
python annotated/verify_annotated.py . annotated
```

```text
  --  equates.asm: no original (new file, skipped)
  OK  main.asm  (386 code lines)
  OK  roll.asm  (623 code lines)
  ...
  OK  vars.asm  (0 code lines)

FAILURES: 0
```

Two parsing bugs in the checker had to be fixed before it agreed with the assembler: an apostrophe was treated as a
string quote even in `EX AF,AF'`, which swallowed the following comment, and the numeric-literal pattern matched
*inside* identifiers, so `SKIP1LDH` was read as `SKIP1L` plus the suffix-hex literal `DH`. Both produced false
mismatches on files the assembler had already confirmed byte-identical.

The same script is used by the annotated [SAMDOS 2](https://github.com/stefandrissen/samdos) source, which selects
its own extension with `--ext=.s`. Annotating that tree turned up four further parsing bugs, all fixed here too:
dotted identifiers were not recognised as symbols; `<<`, `>>` and `|` were not folded; and expressions inside an
indirection, or led by a label whose value is unknowable without assembling, were not folded at all.

The check has teeth: it was validated by seeding a one-byte change (`LD A,&FE` → `LD A,&FD`), which it located
immediately, and it caught a genuine error during the conversion of `main.asm`, where the `MODE` range check's
`LD DE,&0400+34` had been rewritten with the wrong error constant (34 is `ERR_BADMODE`, not `ERR_IOOR`).

A separate cross-check confirms all 508 symbols defined in the original tree resolve to identical values in the
annotated tree.

### What it does not prove

* That the ROM behaves correctly on hardware. A byte-identical image cannot behave differently, but neither the
  original nor the annotated build has been run on a real machine as part of this work. `romtest.asm` is the tool
  for that check: it compares the assembled image against the live ROM from within a running machine.
* That the commentary is correct. The build proves the *code* is unchanged, not that the explanations of it are
  right — see the warning at the top.

## Related documentation

Prose documentation of the same material lives in [`../docs`](../docs):

* [source-files.md](../docs/source-files.md) — per-file routine reference
* [constants.md](../docs/constants.md) — every `EQU` in the original source
* [memory-map.md](../docs/memory-map.md) — system page and BASIC area layout
* [machine-code-interface.md](../docs/machine-code-interface.md) — jump table, calculator, `CALL`/`USR`
* [extending-basic.md](../docs/extending-basic.md) — the interpreter's extension hooks, with worked examples
* [dos-and-extensions.md](../docs/dos-and-extensions.md) — what SAMDOS 2, MasterDOS and MasterBASIC add on top
* [tokenized-program-format.md](../docs/tokenized-program-format.md) — tokeniser and stored program format
* [file-formats.md](../docs/file-formats.md) — saved file header and layout
* [font-rendering.md](../docs/font-rendering.md) — character cell geometry
* [hudg.md](../docs/hudg.md) — character set pointers
* [keyboard.md](../docs/keyboard.md) — matrix scan, debouncing, auto-repeat, type-ahead queue
