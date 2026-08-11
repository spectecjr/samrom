# SAM Coupé ROM 3.0 — Source File and Routine Reference

The ROM is built by [samrom.asm](../samrom.asm), which `include`s the modules
below in order. The first group assembles into **ROM0** (&0000–&3FFF, always
visible at address 0); the second into **ROM1** (assembled at &C000, paged into
the top 16K). ROM0 holds the restarts, editor, main interpreter loop,
expression evaluator front-end, variable handling and graphics primitives;
ROM1 holds the floating-point calculator, arithmetic, printing, tape/net I/O,
and the keyword/message tables. Code in ROM1 that must run while the BASIC
program is paged into the same address range is copied into RAM buffers
(`INSTBUF`/`CDBUFF`) before execution.

Companion documents:

- [constants.md](constants.md) — every `EQU` constant, by file.
- [tokenized-program-format.md](tokenized-program-format.md) — the tokenizer,
  the compile pass, and the exact in-memory form of a tokenized program.
- [memory-map.md](memory-map.md) — the system-page and BASIC-area memory map.
- [machine-code-interface.md](machine-code-interface.md) — the jump table,
  restarts, calling the FP calculator, and CALL/USR parameter passing.
- [extending-basic.md](extending-basic.md) — the `MTOKV`/`CMDV`/`RST28V`/
  `PRTOKV` hooks, the free token budget, and worked examples of new commands,
  functions, operators and external commands.
- [dos-and-extensions.md](dos-and-extensions.md) — what SAMDOS 2, MasterDOS
  and MasterBASIC add, how each attaches itself to the ROM, and the extended
  token map.
- [file-formats.md](file-formats.md) — the saved-file header and how a BASIC
  program is encoded on tape/disc.
- [font-rendering.md](font-rendering.md) — character cell geometry, and which
  bits and scans of a bitmap reach the screen at each `CSIZE`.
- [hudg.md](hudg.md) — the `CHARS`/`UDG`/`HUDG` font pointers and the dormant
  high-UDG range.

## File index

| File | Contents |
|---|---|
| [main.asm](#mainasm) | ROM0 restarts (RST 0–&38), NMI handler, public jump table at &0100, ROM0↔ROM1 paging call helpers |
| [vars.asm](#varsasm) | System variable definitions only (no code) — see [constants.md](constants.md#varsasm) |
| [editor.asm](#editorasm) | Line editor: key dispatch, cursor movement, insert/delete, DEF KEY expansion |
| [list.asm](#listasm) | AUTOLIST, LIST/LLIST, CLS family, PRINT command, cursor up/down through the program |
| [roll.asm](#rollasm) | ROLL and SCROLL commands, window clear, editor scroll, pixel-row address stepping |
| [mainlp.asm](#mainlpasm) | The interpreter main loop: LINESCAN syntax pass, statement dispatch, line insertion, error handling |
| [misc1.asm](#misc1asm) | Streams/channels (SETSTRM), temporary colour vars (TEMPS), READ, POKE/DPOKE, colour items |
| [lookvar.asm](#lookvarasm) | Variable lookup: name parsing, numeric variable chains, string/array search |
| [eval.asm](#evalasm) | Expression evaluator (SCANNING/SCANSR), operator priorities, literal number conversion (CALC5BY) |
| [do.asm](#doasm) | DO/LOOP, IF/ELSE/END IF, FOR/NEXT, GOTO/GOSUB/RETURN plumbing, BASIC stack, FNDLINE, ON ERROR |
| [tadjm.asm](#tadjmasm) | FP-stack helpers (stack/fetch/GETINT), program search (SEARCHALL), MAKEROOM/RECLAIM, page-form arithmetic |
| [graph0.asm](#graph0asm) | CIRCLE and DRAW (line drawing, thin-pixel draw) |
| [graph1.asm](#graph1asm) | PLOT and the per-mode pixel plotting subroutines; SETIY plot dispatcher |
| [graph2.asm](#graph2asm) | BLITZ (graphics string interpreter), FILL, screen→check-screen transfer, coordinate fiddling |
| [grabput.asm](#grabputasm) | GRAB and PUT block graphics; FARLDIR/FARLDDR cross-page block moves |
| [assign.asm](#assignasm) | Assignment (ASSIGN/STKVAR), DIM, string slicing, variable creation |
| [fn.asm](#fnasm) | DEF FN/FN evaluation, DEF PROC/PROC call, LOCAL, the COMPILE pass that patches call buffers |
| [nparpro.asm](#nparproasm) | PROC parameter processing (by value and by REF), RESTORE, local-variable teardown |
| [misc2.asm](#misc2asm) | RST 8 error entry and DOS hand-off, ROM1→RAM stub loaders (incl. TOKMAIN), LET/DEFAULT, RUN/CLEAR, syntax helpers, class checks |
| [endprint.asm](#endprintasm) | Final per-mode character rendering (see [font-rendering.md](font-rendering.md)), screen address calculation, string compare, buffer fetch, memory-room tests |
| [miscx1.asm](#miscx1asm) | ROM1 bodies copied to RAM: RENUM, GET, DELETE, KEYIN, POP, INPUT |
| [miscx2.asm](#miscx2asm) | More copied bodies: DEF KEYCODE, DEF FN statement, **the tokenizer (TOKPT2)**, MERGE |
| [fpcmain.asm](#fpcmainasm) | Floating-point calculator: opcode dispatch table, control loop, literals, jumps, comparisons |
| [transend.asm](#transendasm) | Transcendental functions: SIN/COS/TAN/ASN/ACS/ATN/LN/EXP/POWER, Chebyshev SERIES generator |
| [mult.asm](#multasm) | FP multiply/divide/add/subtract, integer fast paths, number form conversion |
| [rom1fns.asm](#rom1fnsasm) | VAL/VAL$, RND, ATTR, POINT, INKEY$, CHR$, BIN$/HEX$, MEM$, CONCAT, &-hex literals, PEEK/DPEEK, STR$, CODE |
| [scrsel1.asm](#scrsel1asm) | OPEN/CLOSE SCREEN and streams, page allocation, all interrupt service (frame/line/MIDI/mouse), keyboard scan buffering |
| [scrsel2.asm](#scrsel2asm) | GOTO/GOSUB (+ ON), **GETTOKEN keyword matcher**, MODE, FATPIX, CSIZE, AUTO, SOUND, BOOT |
| [printfp.asm](#printfpasm) | Number-to-text conversion (STR$/PRINT of numbers), power-of-ten scaling |
| [tprint.asm](#tprintasm) | Character/token output: ASCII, UDGs, keyword expansion, control codes, scroll prompts, number printing |
| [tapemn.asm](#tapemnasm) | SAVE/LOAD/MERGE/VERIFY command parsing and execution, header handling |
| [tapex.asm](#tapexasm) | Tape/net low-level block save/load, edge timing, net/MIDI byte I/O |
| [using.asm](#usingasm) | XOINTERS pointer adjustment after MAKEROOM/RECLAIM, heap, INSTR, LENGTH, STRING$, code-buffer builders (CRTBF), DRAW curve |
| [misc31.asm](#misc31asm) | CALL, machine init (MNINIT), NEW, charset unpacker, PALETTE command and line-interrupt colour table |
| [misc32.asm](#misc32asm) | BEEP and sound effects (ZAP/POW/BOOM/ZOOM), KEY, DEVICE, PAUSE, colour-item execution, BORDER, WINDOW, OUT, STOP, RANDOMIZE |
| [scrfn.asm](#scrfnasm) | COPY, SCREEN$ recognition, **OUTLINE — the listing/detokenizing routine**, pretty-list indenting, cursor output, number printing |
| [text.asm](#textasm) | Data: error messages (compressed), keyword table, key maps, command address table, initial palette, compressed charset |
| [romtest.asm](#romtestasm) | Stand-alone test program comparing the assembled image against the live ROM (not part of the ROM build) |

---

## main.asm

The very bottom of ROM0: the Z80 restart vectors, interrupt entries, and the
public jump table at &0100 that gives external code stable entry points into
both ROMs. Also contains the RST &30 mechanism used throughout the ROM to call
routines in the *other* ROM with automatic paging.

| Entry point | Description |
|---|---|
| [L0000](#l0000) | Reset: DI and jump to `MINITH` (delay, enable ROM1, jump to `MNINIT`) |
| `HLJUMP`/`IYJUMP`/`IXJUMP`/`BCJUMP` | Tiny `JP (rr)` helpers used as computed-jump primitives |
| [NRWRITE](#nrwrite) | `LD (HL),A : RET` — write helper callable with ROM paged appropriately |
| RST &08 | Error restart: byte after the RST is the error code; jumps to `ERROR2` in misc2.asm |
| RST &10 ([RST102](#rst102)) | Print character in A through the current channel |
| [PRINTSTR](#printstr) (&0013) | Print BC bytes from (DE) via the channel's string output (`SOP2`) |
| RST &18 ([GETCHAR](#getchar)) | Get the character at CHAD, skipping spaces and control codes (not CR), with ROM1 paged out |
| RST &20 ([NEXTCHAR](#getchar)) | Advance CHAD then behave as RST &18 |
| RST &28 ([FPCP2](#fpcp2)) | Floating-point calculator entry — pages in ROM1 and runs `FPCMAIN` over the inline code bytes |
| RST &30 ([RST30L2](#rst30l2)) | Call/jump into ROM1: the word after the RST is the target −&8000; bit 15 clear means "jump" instead of "call" |
| RST &38 | Maskable interrupt: reads STATPORT, pages system page in, dispatches via `ANYIV` (normally [ANYI](#anyi)) |
| NMI (&0066) | Pages to a safe state, calls the `NMIV` vector (normally super-break), restores paging |
| [RDCN](#rdcn)/[NUMBER](#rdcn) | Read char at (HL) / skip an invisible &0E+5-byte number form (adds 6 to L) |
| `NRREAD`/`RDDE` | `LD A,(HL)` / `LD A,(DE)` with RET — read helpers for cross-ROM peeking |
| [NXCHAR](#nxchar) (&0074) | Advance CHAD and read the next char with *no* skipping (used inside number parsing) |
| [Jump table &0100](#jump-table) | Public vectors: JSCRN, HEAPROOM, WKROOM, MKRBIG, CALBAS, SETSTRM, POMSG, EXPT1NUM…, GETINT, STKFETCH/STKSTORE, SBUFFET, FARLDIR/FARLDDR, JPUT/JGRAB/JPLOT/JDRAW/JDRAWTO/JCIRCLE/JFILL/JBLITZ/JROLL, CLSBL/CLSLOWER, palette/screen/copy hooks, RECLAIM2, KBFLUSH, READKEY, KYIP2, BEEP, SABYTES/LDBYTES/LDVD2, EDGE2, PFSTRS, SENDA, IMSCSR, GRCOMP, GETTOKEN, JCLSCR |
| [MODECMD](#modecmd) | The MODE command: insist on a number 1–4, then jump to `MODPT2` in ROM1 |
| [S16OP](#s16op) | Channel `$` output stub — calls `S16OSR` (append char to a string variable) with ROM1 off |
| [R1OFFCL / R1OFFJP / R1OFFCLBC](#r1offcl) | Call (or jump to) the address in the following word/BC with ROM1 paged out, restoring paging afterwards |
| [R1XJP](#r1xjp) | Turn ROM1 off permanently and jump to (BC) |
| [SOP2](#sop2) | String output: uses the channel's block-output entry if it has one, else repeated RST &10 |
| [JSVIN](#jsvin) | "Jump with system variables in": pages the system page in at &4000 with a private stack, calls the parameter address, restores everything |
| `STRMTAB` | Initial stream displacement table for streams −5…3 |

### Details

#### L0000
Reset entry. Interrupts are disabled and control passes to `MINITH`, which
runs a ~300 ms delay loop (waiting for the ASIC to become ready — this delay
is what the pre-production ROMs lacked), switches ROM1 on via port 250, and
jumps to `MNINIT` in misc31.asm for the full machine initialisation.

#### RST102
The RST &10 print restart. Saves IX/HL/DE/BC, fetches the output-routine
address from the current channel (`CURCHL`) and calls it. Every character
printed by the ROM funnels through here; the channel address is temporarily
redirected to implement control-code parameter collection.

#### PRINTSTR
Address &0013. Prints BC characters starting at (DE). `SOP2` implements it:
if the current channel provides a special string-output entry (flagged by a
&40 byte in the channel record), the whole block is handed over in one call;
otherwise it loops on RST &10. DE ends just past the string, BC ends 0.

#### GETCHAR
RST &18 / RST &20 — the interpreter's character fetch. RST &18 loads HL from
CHAD, RST &20 pre-increments CHAD. Both then page ROM1 *out* (so the program
area at &C000 is visible), skip every byte below &21 except CR (updating CHAD
past skipped spaces/control bytes), restore the previous paging and return the
significant character in A. This is why spaces are insignificant almost
everywhere in SAM BASIC source lines.

#### FPCP2
RST &28. Saves the caller's IX and makes IX point at the byte after the RST —
the calculator's instruction pointer. Saves BC in `BCREG`, forces ROM1 on,
and calls `FPCMAIN`. The calculator executes the byte codes following the RST
until an `EXIT`/`EXIT2` code, then execution resumes after them with paging
restored. See [fpcmain.asm](#fpcmainasm).

#### RST30L2
RST &30 — the inter-ROM linkage. When executed from within ROM0, the word
following the RST is a ROM1 address minus &8000: bit 15 set means CALL, clear
means JUMP (bit 7 of the stored high byte is used as the flag and set before
use). ROM1 is paged in around the call and the original paging restored.
When RST &30 is executed from RAM (address ≥ &4000) it re-dispatches through
the `RST30V` vector instead, so user code can use its own convention.

#### ANYI
The default RST &38 handler body (via `ANYIV`). The interrupt stub reads
STATPORT and LRPORT, forces both ROMs on with page 0 in section B, then `ANYI`
switches to the dedicated `INTSTK` stack and calls `INTS` (scrsel1.asm) which
demultiplexes frame/line/MIDI/mouse interrupt sources.

#### RDCN
`RDCN` = `LD A,(HL)` then fall into `NUMBER`: if A is the &0E number marker,
add 6 to the pointer (skipping the marker and the 5-byte numeric form) and
return the following character. This is the canonical "skip invisible number"
primitive used by the lister, searchers and skippers.

#### NXCHAR
&0074. Increment CHAD and return the byte there with **no** skipping — used
by the number parser, which must see every digit and cannot have spaces
skipped for it.

#### Jump table
At &0100 sits a table of `JP`/`RST &30` entries providing a stable public API
(addresses &0100, &0103, &0106 … &018D). Comments in the source give each
vector's contract; notable ones: &010F `CALBAS` (call a BASIC line from
machine code), &0112 `SETSTRM`, &0118/&011B/&011E expression evaluation,
&0121 `GETINT`, &0124/&0127 string stack fetch/store, &012D/&0130
`FARLDIR`/`FARLDDR` (cross-page block copy), the graphics entries
(&0133–&014B), &0163 `RECLAIM2`, &0169 `READKEY`, &018A `GETTOKEN`.

#### NRWRITE
One-instruction write-and-return, used via computed calls when a single byte
must be written while a particular page is switched in.

#### MODECMD
Implements `MODE n`. Uses `SYNTAX6` to demand a numeric argument, `LIMDB` to
range-check 1–4 (decrementing to 0–3), then dispatches to `MODPT2` in ROM1
which reprograms the video mode, windows and expansion tables.

#### S16OP
Output routine for the `$` channel (stream 16 / RECORD TO): preserves AF' and
calls `S16OSR` (misc2.asm) with ROM1 off to append the character to the string
variable named in `STRM16NM`.

#### R1OFFCL
Family of helpers to execute ROM0-resident code that needs ROM1 paged out
(e.g. to see the BASIC program): `R1OFFCL` calls the address in the inline
word; `R1OFFJP` does the same but discards the return address (a "jump" that
still restores paging); `R1OFFCLBC` calls BC. `R1ONCLBC` is the complement
that forces ROM1 *on*. All preserve every register except AF'.

#### R1XJP
Pages ROM1 out and jumps to BC without any restore — used when control is
permanently transferring back into ROM0 (e.g. at the end of AUTOLIST).

#### SOP2
See PRINTSTR above.

#### JSVIN
Vector &0103. For external code: switches the system page into section A
(&4000) with ROM0 on/ROM1 off, moves the stack to a safe internal area, calls
the routine whose address follows the call, then restores stack and paging.

---

## vars.asm

No code — the complete system-variable map, fixed buffers, token codes, DOS
hooks and port numbers. Fully catalogued in
[constants.md](constants.md#varsasm).

---

## editor.asm

The interactive line editor. It runs as a loop fed by `WAITKEY`, inserting
printable characters at the cursor (`KCUR`) in the edit line (ELINE) or INPUT
workspace, and dispatching editing keys 7–&0F through a pointer table.

| Entry point | Description |
|---|---|
| [EDITOR](#editor) | Main editor entry: hooks `EDITV`, saves ERRSP, applies AUTO line numbering, then loops on `EDFK`/key dispatch until ENTER |
| [ADDCHAR](#addchar) | Channel "R" output routine: insert a character at KCUR, expanding token bytes ≥&85 to their keyword text (used when a line is listed into the edit buffer) |
| `ADCH1` | Raw insertion of one byte at KCUR (opens 1 byte with MKRMCH) |
| [EDFK](#edfk) | Get a key; if it is a user-defined key (192–254), insert its definition text (auto-ENTER unless it ends in ":") |
| `EKPT` | Editing-key pointer table: EDIT, left, right, down, up, delete-left, ENTER, delete-right, keypad toggle |
| [EDKY](#edky) | EDIT key: list line EPPC into ELINE through channel "R" with pretty-listing off |
| [EDLT / EDRT](#edlt) | Cursor left/right, treating an &FF+code function token as one character |
| `EDDN`/`EDUP` | Cursor down/up: within a line uses the special `CUOP` output to find the matching KCUR; on an empty ELINE moves the `>` program cursor instead (`FUPDN`) |
| `EDKPX` | Toggle the numeric-keypad flag (KPFLG) |
| [EDDLL / EDDLR / EDDLC](#eddll) | Delete left/right; deletes both bytes of FF-prefixed tokens and pulls colour-control parameters correctly |
| `CARET` | Delete one byte at (HL) — also used by LOCAL |
| [EDENT](#edent) | ENTER: unwind to the editor's caller; `ERRCHK`/`RESESP` re-raise any pending error |
| `RESTOP`/`POCHNG`/`DETOHL`/`PRERESTOP` | Channel output-address patching used for control-code parameter collection |
| `CUOP` | Special output routine (via ROM1 `CUOPP`) that watches for the screen position matching the cursor during EDUP/EDDN |
| [WARNBZ / RSPNS / NOISE / BEEPER](#warnbz) | Editor error buzz (RASP) and key-click (PIP) |
| [CLEARSP](#clearsp) | Reclaim the edit line (or INPUT workspace region); `SETKC`/`SETKC2` reset KCUR/KCURP |
| `SETDE` | DE := start of ELINE (edit mode, Z) or of the INPUT line in workspace (NZ) |
| [LNNM](#lnnm) | Read a line number at (HL), falling back to the previous line at program end (DE=0 if no program) |
| `GTKBK`/`WKBR` | Flush keyboard and wait for a key with BREAK checking |
| [WAITKEY](#waitkey) | Wait for a key via the current channel's input routine; "End of file" error if input is exhausted |
| [KYIP / KYIP2](#kyip) | The keyboard channel input routine: returns queued key, handles CAPS lock, and the two-key colour-control sequences (`KYPM`) |
| `EDPRT`/`FONOP` | Print the edit/INPUT line to the lower screen (ROM1 `EDPTR2`); force normal output |
| [AULN](#auln) | AUTO mode: if the edit line is empty, print EPPC+step into it as the new line number |
| [FNDKYD / DKTR](#fndkyd) | Find a DEF KEY definition for key code A (or the list terminator) in the DKDEF buffer |
| `KSCHK` | Z if the current channel letter is K or S |

### Details

#### EDITOR
Entered with the edit line (or INPUT buffer) already set up. Pushes an error
frame (`EDER`) so that syntax errors during editing buzz and re-enter the
editor rather than aborting, records the screen position, applies `AULN`, and
then loops: `EDFK` fetches a key, `NOISE` clicks, and the key is either
inserted (`ADCH1`), treated as a two-byte colour control (`TWOKYS`), or
dispatched through `EKPT` to an editing routine. The loop address `EDLP` is
kept on the stack so editing routines simply RET to continue.

#### ADDCHAR
The output side of channel "R" (the editor channel used by EDIT and AUTO):
characters "printed" to it are inserted into the line at KCUR. Bytes ≥&85 are
expanded back to keyword text via ROM1 `PRGR802` unless the in-quotes flag is
set, so listing a tokenized line into the buffer yields editable text. It also
maintains FLAGS bit 0 (leading-space suppression) so that re-tokenizing the
edited line produces identical spacing.

#### EDFK
Fetches a key with `WAITKEY`. Codes 192–201 are the function keys/keypad
(returned as digits if KPFLG says numeric). Other codes ≥192 are looked up
with `FNDKYD`; if defined, the definition text is block-inserted at KCUR and,
unless the definition ends with ":", ENTER is simulated (`EDENT`).

#### EDKY
The EDIT key. In INPUT mode it just clears the input line. Otherwise it takes
the line number from the edit line (or EPPC), finds the line, and lists it
into ELINE by printing it through channel "R" with `OUTLINE` — i.e. the line
is *detokenized* into the edit buffer. KCUR is left just after the 5-digit
line number.

#### EDLT
Cursor movement treats the two-byte &FF-prefix function tokens as a unit:
moving left over the code byte of an FF-pair steps back an extra byte; EDRT
skips forward over an &FF before landing. Movement stops at the line start
(the byte before is the SAVARS &FF terminator) and at the CR at line end.

#### EDDLL
Delete-left calls EDLT then deletes at the new position; delete-right deletes
at KCUR unless it is the CR. `EDDLC` deletes 2 bytes for an FF-prefixed token,
and when the byte before the deletion point is a colour control code &10–&15
it deletes the control byte first and re-points KCUR so the orphaned parameter
is deleted by the next keystroke.

#### EDENT
ENTER. Discards the editor-loop and warn-buzz frames from the stack and
returns to the editor's caller (the main loop), after `RESESP` restores ERRSP
and re-raises any recorded error.

#### WARNBZ
On editor-detected errors with the lower screen in use: zeroes ERRNR, emits
the RASP buzz and re-presents the line, rather than aborting to a report.

#### CLEARSP
Reclaims everything between ELINE and WORKSP−1 (edit mode) or WORKSP and
WKEND−1 (INPUT mode), then resets KCUR (and KCURP from the current paging).

#### LNNM
Given HL at a line-number MSB, returns DE = that line number; if HL sits on
the &FF program terminator it returns the previous line's number (DE via the
passed-in DE pointer), or 0 for an empty program.

#### WAITKEY
Sets TVFLAG bit 3 ("edit line needs printing to lower screen") on first call,
then repeatedly calls the current channel's input routine until it returns a
key (CY) — a Z,NC return loops, NZ,NC raises "End of file".

#### KYIP
The standard keyboard input routine installed in channels K and S. Returns
the queued key from LASTK with CY. CHR$ 6 toggles caps lock; codes &10–&15
(PEN…OVER controls) switch the channel input to `KYPM`, which validates and
returns the following parameter digit, restoring normal input afterwards.

#### AULN
If AUTO is on and the edit line is empty, computes EPPC+AUTOSTEP and prints
it into the edit line through channel "R" (refusing numbers ≥ &FF00).

#### FNDKYD
Scans the DEF KEY buffer at (DKDEF): each definition is `code, len16, text…`,
terminated by an &FF code byte. Returns HL=text, BC=len, CY if absent. `DKTR`
finds the terminator (used to compute free space).

---

## list.asm

Listing and screen-clear commands, plus the PRINT command itself and the
logic that moves the `>` program cursor up/down the listing.

| Entry point | Description |
|---|---|
| [AUTOLIST](#autolist) | List the program around EPPC in the upper screen, adjusting SDTOP so the current line is visible without scrolling |
| [LIST / LLIST](#list) | The LIST command: optional FORMAT n, optional #stream, line range via the bracketless slicer; sets EPPC |
| `LIST5`/`LSTLNS` | List from line HL onwards with indenting on (calls ROM1 `LSTR1`) |
| `SPACAN` | Cancel pending pretty-listing indent counts |
| [CLS / CLSBL / MCLS](#cls) | CLS command (and BLITZ entry): clear whole screen or window, reset scroll counts, LPT table and graphics origin |
| [CLSLOWER](#clslower) | Clear (and shrink) the lower screen window, resetting channel K |
| `CLSE`/`CLSG` | Fast full-screen clear using stacked PUSHes (~7 T-states/byte) |
| `CLWC`/`CLWC2` | Clear window and refresh the channel's I/O addresses |
| [PRINT / LPRINT](#print) | The PRINT command: separators, TAB/AT items, colour items, expression printing via STR$ |
| `PRSEPR`/`PRTERM`/`PRITEM` | Print separator/terminator classification and single print-item evaluation |
| `RUNCR`/`PRCIFRN` | Print CR (or char C) only when running |
| [FUPDN / LPD / MWDN / MWUP](#fupdn) | Move the `>` cursor a line up/down the on-screen listing, scrolling the window when leaving it |
| `IOUTLN`/`IOUTLNC`/`IOPCL`/`IOPOF` | Print one program line with indented-output mode switched on/off around it |
| [REALN / ADVEPPC / ADVSTOP / ADVAC](#realn) | Snap a line-number system variable to a real line / advance it to the next line |

### Details

#### AUTOLIST
Called after every command execution in the edit loop. Ensures EPPC and SDTOP
name real lines, computes a suitable SDTOP at most ~&200 bytes above EPPC's
address (so the current line appears without scrolling), sets LISTSP so a
"scroll?" refusal aborts cleanly, then lists from SDTOP with indenting on.
TVFLAG bit 4 marks the autolist while it runs.

#### LIST
`LLIST` presets stream 3, `LIST` stream 2. `LIST FORMAT n` (0–2) just stores
LISTFLG (the pretty-listing indent step). Otherwise an optional `#s`, an
optional `,`/`;`, then a bracketless range (`10 TO 200`, `TO`, `50`…) parsed
by `BRKLSSL` into FIRST/LAST. A single number means "from here to the end"
for LIST. FIRST becomes the new EPPC and `LIST5` prints from there.

#### CLS
`CLS` alone clears the whole screen (also resetting the graphics origin to
0,0 via a small calculator program), `CLS 1` only the window, `CLS #`
resets windows/streams fully (ROM1 `CLSHS`). `CLSBL` is the BLITZ entry with
A holding the parameter. On a full clear the 30-byte LPT (line pointer table)
is zeroed and LNPTR set to &FF (no cursor line on screen).

#### CLSLOWER
If the lower window has grown beyond its normal 2 lines (INPUT prompts), the
overlap area is cleared as a temporary window with upper-screen colours
first; then the lower window proper is cleared, channel K selected, and
SPOSNL reset.

#### PRINT
`PRINT`/`LPRINT` select stream 2/3 when running, set the in-quotes flag (so
tokens print as UDGs, not keywords), copy permanent colour vars to temps, and
loop: separators (`;` nothing, `,` CHR$ 6 column tab, `'` CR) alternate with
items. Items are TAB n, AT r,c, `#s` redirection, colour items, or an
expression: numeric results go through `JPFSTRS` (STR$ to buffer) and strings
print directly from their pages.

#### FUPDN
Handles cursor-up (&0B)/down (&09) over the listing when the edit line is
empty. Uses the LPT table (one byte per screen row, &FF where a program line
starts) to find the previous/next row bearing a line number; if the cursor
would leave the window, the window is scrolled (`MWDN` measures the incoming
line's height with a dummy "dumped" print first; `MWUP` advances SDTOP and
reprints the boundary lines) and EPPC follows.

#### REALN
`REALN` replaces the line number in a system variable with the first real
line ≥ it. `ADVEPPC`/`ADVSTOP` advance EPPC/SDTOP one line (used by
cursor-down and scrolling), all through `ADVAC` which combines `FNDLINE` and
`LNNM`.

---

## roll.asm

ROLL and SCROLL (wrap-around vs. blanking) of arbitrary screen areas, plus the
window-clear and editor-scroll primitives built on the same machinery. The
inner loops execute a run of `LDI`/`RLD`-style opcodes generated into the RAM
code buffer `CDBUFF` (built by `CRTBF`/`CRTBFI` in using.asm).

| Entry point | Description |
|---|---|
| [ROLL / SCROLL](#roll) | The commands: `dir[,pixels[,x,y,w,len]]`; SCROLL CLEAR/RESTORE toggle the "scroll?" prompt |
| `JROLL` | Jump-table entry with registers pre-loaded (B=pix, C=dir, HL=coords, D=len, E=width, A=roll/scroll) |
| `RLBYTE`/`RUPDN` | Byte-granular left/right movement; up/down movement (also the editor's engine) |
| [RSSTBLK](#rsstblk) | Save the strip that will wrap into RSBUFF (shared with GRAB); errors if > ~8K |
| [CLSWIND](#clswind) | Clear the current character window (scroll up by its own height) |
| [EDRS / EDRS1UP / EDRSADN](#edrs) | Editor scroll of the window by A rows up/down, scrolling the LPT line table alongside |
| `RSMOVSR` | Copy B' scans between screen rows via CDBUFF (main block mover) |
| [CALCPIX / CALCPIXD](#calcpix) | Convert character rows to scan lines using CSIZE (plus double-height adjust) |
| [NEXTUP / NXTDOWN / NEXTDOWN](#nextup) | Step a screen address one scan up/down in modes 0/1 (mode 0's thirds layout handled) |
| `CTAA` | Convert a mode 0 pattern address to its attribute address |

### Details

#### ROLL
Parses direction (1=left, 2=up, 3=right, 4=down), optional pixel count, and
an optional x,y,w,len area (widths forced even, coordinates forced to fat).
Requires MODE 2/3 for arbitrary areas. Single-pixel horizontal movement uses
`RLD`/`RRD` runs; multi-pixel horizontal movement moves whole bytes with a
generated LDIR/LDDR run, wrapping the displaced bytes through RSBUFF (ROLL)
or blanking with the paper byte (SCROLL). Vertical movement copies scans with
`RSMOVSR` then wraps or blanks the freed strip.

#### RSSTBLK
Copies the `pix` scans that are about to be pushed off the area into RSBUFF
(&E003 in the second screen page), recording the byte count in TEMPW2. "Stored
area too big" if the strip exceeds ~8K−19 bytes. GRAB uses the same routine to
capture its block.

#### CLSWIND
Expresses "clear window" as "scroll up by the whole window height": the same
code path blanks every scan, including the leftover scans between upper and
lower screen when clearing the upper window.

#### EDRS
The editor/lister scroll. Computes the window geometry (width in bytes per
mode — 1, 1, 1.5/2 or 4 bytes per column), then uses `RUPDN2`. Mode 1 scrolls
pattern data then attributes; mode 0 has its own scan-stepping loop
(`EDRSM0`) using NEXTUP/NEXTDOWN and scrolls the attribute block separately.
`EDRS1UP` also scrolls the LPT table (`STENTS`) so line-number tracking
follows the text.

#### CALCPIX
$ \text{scans} = \text{rows} \times \text{height} $ where the height comes
from CSIZE (6–32), plus DHADJ (8) when the bottom half of a double-height
character is being placed.

#### NEXTUP
Address steppers for the interleaved mode 0 layout (character cell thirds)
and linear 32-byte rows of mode 1. Used by scroll, SCREEN$ and the mode 0
plot routines.

---

## mainlp.asm

The heart of the interpreter: the syntax-check pass over a line, the
statement dispatch loop used both for checking and running, the main
edit-execute loop, error handling, and line insertion.

| Entry point | Description |
|---|---|
| [LINESCAN](#linescan) | Syntax-check the edit line: FLAGS bit 7 cleared ("checking"), statements run in check mode, 5-byte forms get inserted |
| [LINERUN / LOOPEL](#linerun) | Run (or continue at statement C in) the edit line; PPC=&FFFF marks "in ELINE" |
| [SEARCH](#search) | DO/DEF PROC helper: find token E (with D intervening) from CHAD or die with the error byte after the call |
| [STMTLP…NEXTSTAT](#stmtlp) | The statement loop: fetch command byte, dispatch via CMDADDRT (ROM1 paged as needed), return to NEXTSTAT |
| [NEXTSTAT / STMTNEXT / LINEEND / LINEUSE / NEXTLINE](#nextstat) | Between-statement logic: BREAK check, pending jumps (NSPPC/NEWPPC), line advance, statement skipping |
| `REMARK` | REM: discard the rest of the line |
| `BRKCR`/`BRKSTOP`/`BRKTST` | BREAK (ESC) tests: error 14 ("BREAK - CONTINUE to repeat"), error 15 ("BREAK into program") |
| [MAINEXEC / MAINELP](#mainexec) | The main edit loop: AUTOLIST, EDITOR, TOKMAIN, LINESCAN, then insert the line or run it |
| [MAINER](#mainer) | Post-execution/error return: ON ERROR dispatch, CONTINUE bookkeeping, report printing |
| [ERRHAND1 / ERRHAND2](#errhand1) | Print the error report (with variable name for error 2), set OLDPPC/OSPPC for CONTINUE |
| `DFKNL` | DEF KEYCODE tail: syntax-check the rest of the line then strip its 5-byte forms |
| [REMOVEFP](#removefp) | Remove all invisible &0E+5-byte forms from (HL) to the CR |
| [EVALLINO](#evallino) | Parse the line number at the start of ELINE into BC (Z if none, CY if >65279) |
| `AELP`/`STPGS` | Address ELINE / set CLAPG=CHADP=NXTLINEP from A |
| [INSERTLN](#insertln) | Insert the tokenized, checked edit line into the program (replacing any existing line) |
| [SKIPSTATS / SKIPCSTAT / SKIPS0](#skipstats) | Skip D statements (or the current one) respecting quotes and number forms |
| `DATA`/`DATA1` | DATA: skip the statement when running; syntax-check items when checking |

### Details

#### LINESCAN
Resets FLAGS bit 7 (syntax-check mode), IFTYPE, SUBPPC and ERRNR, evaluates
the line number, then falls into the statement loop. In check mode every
command routine validates its arguments — and the expression evaluator's
literal handler *writes the 5-byte forms into the line* (see
[tokenized-program-format.md](tokenized-program-format.md)). `ABORTER` makes
command routines return early instead of executing.

#### LINERUN
Runs the edit line: CLA's page byte is zeroed (an ELINE marker that RETURN
and NEXT recognise), PPC=&FFFF (prints as line 0), CHAD points at the line
and NXTLINE at its end; then the shared NEXTLINE path starts statement 1.

#### SEARCH
Wrapper over `SEARCHALL` (tadjm.asm) used by DO (find LOOP), DEF PROC (find
END PROC) and long IF. On failure it jumps to &0008 so the byte following the
CALL becomes the error code; on success it discards its return address and
resumes execution at the found position (`EXCHAD2` re-establishes PPC and
NXTLINE from CLA, and skips a WHILE/UNTIL condition after LOOP).

#### STMTLP
For each statement: skip spaces, handle ":" and CR, store CSA, offer the
command byte to the `CMDV` hook, then require a byte ≥ &90 (below &90 with a
letter means a PROC call — `PROCS`). The byte indexes CMDADDRT (a word table
in ROM1, base held in the CMDADDRT sysvar); bit 15 of the entry selects
whether the routine lives in ROM1 (leave it paged) or ROM0 (page it out).
The command routine is jumped to with `NEXTSTAT` pushed as its return.

#### NEXTSTAT
After each statement: BREAK check, page CHADP back in. If NSPPC ≠ &FF a jump
is pending: NEWPPC=&FFxx means the edit line, otherwise `FNDLNHL` locates the
line (GOTO tolerates a missing line by landing on the next one; RETURN etc.
insist via `STATLOST`). `LINEUSE`/`NEXTLINE` update CLA/PPC/NXTLINE and
either enter the first statement or `SKIPSTATS` to the requested one.

#### MAINEXEC
The outer loop of the whole machine: AUTOLIST; `SETMIN` (empty edit line);
EDITOR (returns on ENTER); **TOKMAIN** (tokenize the typed line); **LINESCAN**
(syntax-check, embedding number forms); then if the line starts with a number
→ `MAINEADD`/`INSERTLN`, else set FLAGS bit 7 ("running"), NSPPC=1, run
COMPILE (labels/FN/PROC address caching) and LINERUN it.

#### MAINER
Where every run ends (normally or via RST 8, since ERRSP points here). Fixes
SUBPPC after ON, cancels DEFADD/XPTR/AUTO, restores display 0 and the edit
line. If ON ERROR's temporary flag was armed and the error isn't OK/STOP,
control transfers to the statement after the recorded `ON ERROR` instead of
printing a report. Otherwise `ERRHAND1` prints `nn message, line:stat` (error
&50 prints the MGT banner; DOS errors ≥&51 fetch messages from the DOS page)
and `ERRHAND2` records CONTINUE information.

#### ERRHAND1
See MAINER. Error 2 ("… not found") prints the offending variable name from
TLBYTE/NMBUFF, appending `$` or `()` by type.

#### REMOVEFP
Walks a statement byte-by-byte; wherever it finds &0E it reclaims 6 bytes.
Used before re-editing text that was syntax-checked (INPUT lines, DEF
KEYCODE) so the invisible forms never reach the user.

#### EVALLINO
Addresses ELINE, calls `SMBW` (set MEM to a scratch area), converts leading
digits via INTTOFP/FPTOBC. Returns BC=number, Z if zero/absent, CY if >65279
(&FEFF is the highest legal line).

#### INSERTLN
Sets COMPFLG (whole program needs recompiling), trims a single leading space
after the line number, limits the text to &3EFF bytes, finds/reclaims any
existing line with `FNORECL`, then opens `len+4` bytes and writes: line
number **MSB first**, then length (LSB first), then copies the text (including
its embedded 5-byte forms and calling buffers) from ELINE with FARLDIR. A
bare line number (text = just CR) deletes the line.

#### SKIPSTATS
The statement skipper: counts ":" and THEN as statement boundaries, ignores
them inside quotes, skips &0E forms via `NUMBER`, stops at CR. Exits with
CHAD on the boundary character. Used by ON, error recovery, DATA, statement
addressing after jumps.

---

## misc1.asm

| Entry point | Description |
|---|---|
| [PRHSH1 / PRHSH2](#prhsh1) | Parse `#stream` in LIST/PRINT and select it |
| [STRMINFO / SETSTRM](#strminfo) | Map stream number (−5…16; 16→−4) to its STREAMS entry; select channel, set DEVICE and CLET |
| `STREAMFE`/`STREAMFD` | Select stream −2 ("S", main screen) / −3 ("K", lower screen) |
| `CHANFLAG` | Make (CURCHL) current: record channel letter, DEVICE for K/S/P, fall into TEMPS |
| [TEMPS / GTEMPS / GRATEMPS](#temps) | Copy permanent colour/graphics variables to the temporary set; select window; build the colour expansion table |
| `COLEX` | (Re)colour the mode 2/3 expansion table from M23PAPT/M23INKT |
| [POKE / DPOKE / PDPSUBR](#poke) | POKE n,list / POKE n,a$ / DPOKE; the shared 0–512K address-to-paging resolver |
| `CHKMD23` | Error 34 unless MODE ≥ 2 |
| [READ](#read) | READ [LINE] var…: find next DATA item (searching from CLA when exhausted), assign via VALFET1 or as a raw LINE string |
| `SYNT9SR`/`CITEM`/`CITEMSR` | Colour-item parsing for PLOT/CIRCLE/FILL/PRINT (`INK n;` etc.) |
| [PERMS](#perms) | The INK/PAPER/FLASH/BRIGHT/INVERSE/OVER commands: run the item then copy temps to permanents |
| `LDIR8` | Copy the 8 temp colour bytes to the permanent set |

### Details

#### PRHSH1
`PRHSH1` (from LIST) checks for `#`; `PRHSH2` (from PRINT) evaluates the
stream number and selects it via `STRMINF2`+`STSM2` (error 47 if unopen).

#### STRMINFO
Streams live at &5C0C–&5C35 as 16-bit displacements into the CHANS area
(0 = closed). Stream 16 is transformed to internal stream −4 (output into a
string — RECORD). `SETSTRM` stores STRNO, resolves the pointer and falls into
`CHANFLAG`, which also sets DEVICE (S=0, K=1, P=2) and runs TEMPS for K/S/P.

#### TEMPS
Copies THFATP…GOVERP (9 bytes) to the temporary set; for the lower screen
forces OVER/INVERSE 0 and BORDCR/M23LSC colours. Selects the window
rectangle for the device. `COLEX` then builds CEXTAB: the 16 (mode 2) or 32
(mode 3) expansion-table bytes masked into ink/paper colour bytes so the
per-mode print routines can emit coloured pixels straight from a table.
`GRATEMPS` is the graphics variant (always upper screen, skips COLEX).

#### POKE
POKE accepts an address then either a string (block-copied with FARLDIR) or up
to 32 numbers (stored ascending from the address). Addresses are 0–&1FFFF
relative to the context base page: `PDPSUBR` unstacks the address, and for
0–&FFFF maps 0–&3FFF→ROM0, &4000–&7FFF→base page, &8000–&FFFF→base+1/2, while
≥&10000 pages the target into &8000–&BFFF directly. DPOKE/PEEK/DPEEK/CALL/USR
share it.

#### READ
For each variable: if DATADD points mid-list (space or comma) continue there,
else `SRCHPROG` for the next DATA statement (error 3 when none). Normal READ
assigns with `VALFET1` (full expression evaluation against the DATA text);
READ LINE copies the raw text (quotes stripped of FP forms via a workspace
copy and `REMOVEFP`) and assigns it as a string. CHAD is preserved in the
auto-adjusting PRPTR while the data pointer is walked.

#### PERMS
Executes the colour item for the current command token (via `COTEMP4` →
`PRCOITEM` in ROM1, which edits the temporary variables), then copies
ATTRT…GOVERT over ATTRP…GOVERP, making the change permanent.

---

## lookvar.asm

Variable lookup. Also the definitive record of how variables are stored — see
the detail sections.

| Entry point | Description |
|---|---|
| [LOOKVARS / LKVARS2](#lookvars) | Parse the name at CHAD, copy it to NMBUFF, and search the numeric chains or the string/array area; NZ=found with HL at the value |
| [NUMLOOK](#numlook) | Search the per-letter linked lists of numeric variables for the name in FIRLET |
| `LKBSV` | Look up a name stored on the BASIC stack (PROC teardown helper) |
| [STARYLK / STARYLK2](#starylk) | Search the string/array area for the name in FIRLET (type/length byte in C) |
| [NAMTOBUF](#namtobuf) | Copy a variable name to FIRLET (lower-cased, spaces stripped), classifying it ($, (, array bits) |
| `LVFLAGS` | LOOKVARS then return FLAGS×2: M=numeric, P=string, CY=running, Z' = not found |

### Details

#### LOOKVARS
Front end: `NAMTOBUF` scans the name, sets FLAGS bit 6 (numeric/string) and C
(bits 4–0 name length−1; bit 6 string array; bit 5 numeric array), and CHAD
is moved past the name and any `$`/`(`. Simple numerics go to NUMLOOK (in run
time), everything else to STARYLK. On exit: NZ=found, HL→value (numbers: 5
bytes; strings: length-in-pages byte), C=type/length byte from the variables
area; Z=not found with HL at the chain terminator (numbers) or the SAVARS
&FF stopper (strings).

#### NUMLOOK
Numeric variables are stored as 26 per-letter chains. NVARS points at 26
16-bit *relative* pointers (one per letter a–z, MSB &FF = empty). Each
variable record:

| Field | Size | Contents |
|---|---|---|
| Type/len byte | 1 | See bit table below |
| Pointer | 2 | Relative offset from its own location to the next variable of this letter (&FFFF ends the chain) |
| Name tail | 0–31 | 2nd…nth name letters (first letter implied by the chain) |
| Value | 5 | The number (integer or FP form) |
| FOR extension | 19 | Only if bit 6 set: limit (5), step (5), looping page (1), address (2), statement (1) |

Type/len byte bits:

| Bit | Meaning |
|---|---|
| 7 | Hidden (PROC-local shadowing) |
| 6 | FOR-NEXT variable (record extended as above) |
| 5 | Unused slot (re-usable by PROC locals) |
| 4–0 | Name length − 1 (0–31) |

The search compares the type/length byte (ignoring the FOR bit) then the
name tail; page overflow is handled so chains can span 16K boundaries.

#### STARYLK
Strings and arrays live in a separate area (SAVARS→ELINE), terminated by an
&FF byte. Each record:

| Field | Size | Contents |
|---|---|---|
| Type/len byte | 1 | Bit 7 = hidden; bit 6 = string array; bit 5 = numeric array (bits 6 and 5 both clear = simple string); bits 4–0 = true name length (max 10) |
| Name | 10 | Name, padded to 10 characters |
| Length (pages) | 1 | Data length ÷ 16K |
| Length (mod 16K) | 2 | Data length remainder |
| Data | … | String text; or dimension count, dimension sizes (words) and elements for arrays (5 bytes per numeric element; fixed-width rows for string arrays — see DIM in assign.asm) |

Search compares type (ignoring bit 6 mismatch so `a$` finds a 1-D string
array) and name; STRLOCN tracks the current record.

#### NAMTOBUF
Names may contain letters, digits, `_` and embedded spaces (removed); up to
32 characters for numerics, but string/array names are limited to 10 (error
40 otherwise, at STARYLK). The first character is stored lower-cased at
FIRLET; matching elsewhere is case-insensitive (`AND &DF`).

---

## eval.asm

The expression evaluator — an operator-precedence scanner driven from
`SCANSR`, with function/operator priorities in tables, plus the routines that
convert literal text numbers to 5-byte forms.

| Entry point | Description |
|---|---|
| [SCANNING / SCANSR](#scanning) | Evaluate the expression at CHAD. Running: result on the FP stack. Checking: syntax verified and 5-byte forms inserted. FLAGS bit 6 = result type |
| `SLETTER` | Variable reference (checks DEF FN parameter buffers first via LKFNVAR) |
| [ABOVLETS / IMMEDCODES](#abovlets) | Handle an &FF-prefixed function token: immediate functions dispatch through IMFNATAB, FPC functions get queued with priority &CF |
| [SDECIMAL / INSERT5B / LK0ELP](#sdecimal) | Literal number: at check time compute and insert `0E xx xx xx xx xx`; at run time skip the digits and copy the 5 bytes to the FP stack |
| [OPERATOR / SLOOP / PRIGRTR](#operator) | Binary-operator recognition (+−*/^=<>… and FF-prefixed MOD…>=), priority comparison and deferred execution |
| `OPPRIORT` / `FNPRIORT` | Priority tables for binary operators and odd-priority unary functions (bit 7 = numeric result, bit 6 = numeric argument) |
| `IMFNATAB` | Address table for "immediate" functions (PI, RND, POINT, FN, BIN, INSTR, INKEY$, SCREEN$, MEM$ …) |
| [SQUOTE / SQUOTE2](#squote) | String literals: simple strings are stacked in place; embedded `""` pairs force a copy to a buffer/workspace |
| [CALC5BY](#calc5by) | Convert decimal / `&hex` / BIN binary literal text to a value on the FP stack |
| [INTTOFP](#inttofp) | Accumulate ASCII digits at CHAD into a number on the FP stack |
| `R0USR`/`R0USRS`/`CALLX` | USR/USR$ and the CALL trampoline (paged call to machine code) |
| `IMMEMRYS`/`IMHIMEM`/`IMMEM`/`IMMOUSEX`… | Immediate functions: MEM$(a TO b), RAMTOP, FREE, XMOUSE/YMOUSE, XPEN/YPEN, IN, PI, ITEM |
| [FPSWOP13 / FPSWOP23 / SWOP12 / FPSWOP](#fpswop13) | FP-stack entry swaps (also FPC operations &06/&1C/&1D) |
| `STKPGFORM`/`STK19BIT` | Stack a page-form (page,addr) or 19-bit address as a number |

### Details

#### SCANNING
`SCANNING` wraps `SCANSR` in an ROM1-off call and returns C=current char,
A=FLAGS. `SCANSR` pushes a priority-0 stopper, then loops: each token is
classified (letter → variable; FF → function/alphabetic operator; digit/./& →
literal; quote → string; bracket, unary ± …). Functions and operators are
pushed as (priority, code) pairs; whenever the incoming priority does not
exceed the top of the stack, the stacked operation is executed (running) or
type-checked (checking) via the calculator's `USEB`. String operands remap
operator codes (+7 for comparisons, CONCAT for `+`), enforcing type rules at
check time (bit 6 of the priority byte vs FLAGS bit 6). The scan ends when
both priorities are 0; exit is through RST &18 so A=terminating char.

#### ABOVLETS
On &FF: the next byte −&1A gives the internal code (&21–&69). Codes below SIN
are "immediate" — evaluated at once because they take no argument or
bracketed arguments (dispatch through IMFNATAB, with NUMCONT/STRCONT setting
the result type). SIN…EOF-range codes and NOT/NEGATE/VAL-class codes are
queued like operators with their priority from FNPRIORT (default &CF:
priority 15, numeric in/out).

#### SDECIMAL
The heart of literal optimization. **Check time** (`INSERT5B`): CALC5BY
computes the value; `MAKESIX` opens 6 bytes at CHAD — i.e. *after the ASCII
digits* — writes &0E, and the value is popped off the FP stack into the 5
bytes. **Run time** (`LK0ELP`): the digits are skipped by scanning forward to
the next &0E and the following 5 bytes are LDIR'd straight onto the FP stack
— no text conversion ever happens while running.

#### OPERATOR
Recognises single-character operators by code arithmetic (`SUB "*"+1` maps
the ASCII character to an internal operation code; `^` is special-cased) and
the FF-prefixed alphabetic operators and two-character comparisons (stored
token codes &7A–&83 map to internal codes &08–&11). The internal code
indexes OPPRIORT for the priority byte, whose low nibble is the binding
priority:

| Operator | Stored form in the line | Internal code | Priority |
|---|---|---|---|
| `*` | ASCII &2A | &00 | 8 |
| `+` | ASCII &2B | &01 | 6 |
| `-` (binary) | ASCII &2D | &03 | 6 |
| `^` | ASCII &5E | &04 | 15 |
| `/` | ASCII &2F | &05 | 8 |
| MOD | `FF 7A` | &08 | 14 |
| DIV | `FF 7B` | &09 | 14 |
| BOR | `FF 7C` | &0A | 2 |
| BXOR | (`FF 7D` — unused slot) | &0B | 2 |
| BAND | `FF 7E` | &0C | 3 |
| OR | `FF 7F` | &0D | 2 |
| AND | `FF 80` | &0E | 3 |
| `<>` | `FF 81` | &0F | 5 |
| `<=` | `FF 82` | &10 | 5 |
| `>=` | `FF 83` | &11 | 5 |
| `<` | ASCII &3C | &12 | 5 |
| `=` | ASCII &3D | &13 | 5 |
| `>` | ASCII &3E | &14 | 5 |
| NOT (unary) | `FF 76` | — | 4 |
| Unary minus (NEGATE) | ASCII &2D | — | 9 |

(Unary functions default to priority 15 via FNPRIORT.) Bits 7/6 of each
priority byte declare the result/argument types for the check-time type
rules. When the left operand is a string, `+` is remapped to CONCAT (code
&02) and each comparison/AND to its string variant (numeric code + 7,
giving calculator ops &15–&1B); `$ MOD $` and the like are rejected as
nonsense.

#### SQUOTE
A quoted string with no doubled quotes is *not copied anywhere*: its start
address/page/length in the BASIC line itself are stacked (STKSTOREP). Only
strings containing `""` escapes are copied (de-escaped) into INSTBUF and then
workspace. This is the ROM's "string literal optimization": literals live in
the program and are referenced in place.

#### CALC5BY
Dispatch on first char: `&` → ROM1 `AMPERSAND` (hex, up to 6 digits);
BIN token (&FF &43 already tokenized — the &43 code is seen here) → binary
digits accumulated into BC (error 28 past 16 bits); otherwise DECIMAL:
integer part via INTTOFP, optional fraction accumulated with a ×0.1
multiplier loop, optional `E±nn` applied via ROM1 `POFTEN`.

#### INTTOFP
Total = total×10 + digit, on the FP stack, using calculator code with the
digit in BREG. Stops at the first non-digit (fetched with NXCHAR so spaces
terminate a number).

#### FPSWOP13
Register-level swap of FP-stack entries used by FOR (ordering value/limit/
step) and OPEN; the same code implements calculator ops SWOP, SWOP13, SWOP23.

---

## do.asm

Control flow: DO/LOOP, IF in both forms, FOR/NEXT, GOTO/GOSUB/RETURN
support, the BASIC stack, and the line finder.

| Entry point | Description |
|---|---|
| [DO / LOOP / LOOPIF / EXITIF](#do) | DO [WHILE/UNTIL cond] … LOOP [WHILE/UNTIL cond]; LOOP IF / EXIT IF |
| [BSTKE](#bstke) | Push a return frame (type/page, line addr, statement) on the BASIC stack; types &80=DO, &40=PROC, 0=GOSUB |
| [RLEPCOM / RLEPC2](#rlepcom) | "Goto statement C in line at page A, addr HL" — shared resume path for RETURN/END PROC/LOOP/NEXT |
| [ON](#on) | ON n: skip to the n'th following statement; PROC/GOSUB targets fake statement 0 of the next line so they return correctly |
| `GOTO2`/`GOTO3`/`GOTO4` | Set NEWPPC/NSPPC for a jump (range check 0–65279) |
| `CONTINUE` | Jump to OLDPPC/OSPPC |
| [CALBAS](#calbas) | Call a BASIC line from machine code; errors return here with A=code |
| `RETURN` / [ENDPROC](#endproc) | Pop a GOSUB/PROC frame and resume at the next statement (END PROC also tears down LOCALs and re-arms ON ERROR) |
| `WHUNT` | Evaluate an optional WHILE/UNTIL condition into a loop/no-loop carry flag |
| [RETLOOP / RETLOOP2](#retloop) | Pop a BASIC-stack frame of the required type (NZ if wrong type/empty) |
| [FNDLNHL / FNDLNBC / FNDLINE](#fndlnhl) | Find line number HL/BC: from PROG, or from the current line when running and the target is ahead |
| [LIF / SIF / LELSE / ELSE / ENDIF](#lif) | Long and short IF; note the token rewriting between LIF/SIF and LELSE/ELSE forms |
| `TRUETST` | Drop the top FP value and set NZ if it was non-zero |
| [FOR](#for) | FOR v=a TO b [STEP c]: build the 20-byte FOR record, or skip to the matching NEXT if no iteration possible |
| [NEXT / NEXTSR / NEXTTEST](#next) | NEXT v: integer fast path, FP fall-back, loop-back via the stored line/statement |
| [ONERROR](#onerror) | ON ERROR: record ERRLN/ERRSTAT and arm ONERRFLG (or STOP to disarm) |

### Details

#### DO
DO with a false WHILE/UNTIL (or EXIT IF true) searches forward for the
matching LOOP (`SEARCH` with intervening-token DO, so nesting is respected)
and continues after it; otherwise `BSTKE` pushes a DO frame (type &80) and
execution proceeds. LOOP pops the frame and loops back (re-pushing happens on
the next DO execution — the frame stores the *DO line* start and statement).
LOOP IF condition pops-and-loops only when true; EXIT IF pops and skips to
LOOP when true.

#### BSTKE
The BASIC stack grows *down* from BSTACK (&4AFF) toward HEAPEND; each frame
is 4 bytes: type|page, line-address (word), statement. "BASIC stack full"
(41) when it would meet the heap. The frame's address is CLA (line start) —
so RETURN/LOOP resume by line+statement, not by CHAD.

#### RLEPCOM
Common resume: if the stored address MSB is 0 the frame refers to the edit
line (resume via LOOPEL / NSPPC); otherwise page in the stored page and enter
`RLEPI` in mainlp.asm with the line start and statement number.

#### ON
`ON n` adds n to SUBPPC and skips n statements. If the target statement is a
PROC call or GOSUB, CHAD is left at the ":" and CLA is temporarily set to
NXTLINE with SUBPPC=255, so the called routine's return lands at statement 1
of the *next line* (ONSTORE preserves the real statement for error reports).
GOTO executes normally; any other statement executes with a forced line-end
return so exactly one statement runs.

#### CALBAS
Public vector &010F. Pushes a GOSUB frame whose statement byte is &FF; when
the called line RETURNs, the &FF statement makes RETURN pop back into
CALBAS's error frame instead of BASIC. Exit Z if OK else A=error number.

#### ENDPROC
Pops a PROC frame (`DPRA`, error 12 if none), calls `DELOCAL` (nparpro.asm)
to unwind local/REF variables, restores ON ERROR's temporary bit if the
permanent bit is set, and resumes at the frame's statement+1.

#### RETLOOP
Reads the frame at BSTKEND without popping unless the type bits (&E0 mask)
match B; returns A=type/page, HL=line address, C=statement, and advances
BSTKEND on success.

#### FNDLNHL
Finds a line by number. When running and the target ≥ PPC, the search starts
at CLA (current line) instead of PROG — a big win for forward GOTOs. Walks
line headers (number MSB-first compare, then length) handling 16K page
crossings. Exit: HL→line-number MSB of the found-or-next line, DE→previous
line, Z if exact match.

#### LIF
The tokenizer always produces the LIF token (&D7) for "IF" (it is first in
the keyword list). At *syntax-check* time the IF routine inspects its own
statement: if a THEN follows the condition, the command byte in the line is
**rewritten** to SIF (&D8) — so the stored program distinguishes long IF
(block form, terminated by END IF) from short IF (one-line THEN form).
Similarly ELSE tokenizes as LELSE (&D9) and is rewritten to ELSE (&DA) when
the preceding IF on the line was short; `LELSE LIF cond` becomes
`LELSE SIF cond` (ELSE IF chains). At run time a false long IF searches for
LELSE/END IF with nested LIFs counted (`SRCHALL3`); a false short IF searches
the line for ELSE.

#### FOR
Assesses the control variable with SYNTAX4 (marks the type/len byte bit 6),
evaluates value/limit/step, then `ASSISR` assigns the value — creating or
reusing a FOR-type record which extends the normal 5-byte value with limit
(5), step (5), looping page (1), looping address (2), looping statement (1).
The looping point is the next statement (or statement 1 of the next line).
If `NEXTTEST` says no iteration is possible, the interpreter searches forward
for `NEXT v` (matching the variable name) and continues after it (error 6 if
absent).

#### NEXT
Looks up the variable (STRLEN's bit 6 confirms FOR type, else error 5
NEXT-without-FOR at NWFERR... error 0/5 accordingly). `NEXTSR` attempts pure
16-bit integer add of step to value with overflow detection; on overflow or
FP forms, value/limit/step are copied to calculator memories and
`V=V+S` / `NEXTTEST` run in FP. If the limit test passes, RLEPCOM resumes at
the stored looping line/statement.

#### ONERROR
`ON ERROR STOP` clears ONERRFLG. Otherwise records the current line/statement
in ERRLN/ERRSTAT and sets ONERRFLG=&81 (temporary+permanent armed) — except
in the edit line, where it is disabled. MAINER consumes the temporary bit on
the next error and re-enters the program at the statement after ON ERROR.

---

## tadjm.asm

A grab-bag of core services: keyboard fetch, FP-stack access, program search,
memory open/close, page-form (19-bit address) arithmetic.

| Entry point | Description |
|---|---|
| `NMISTOP` | NMI "super-break": force error 15 with a fresh stack |
| [GETKEY / READKEY / KBFLUSH / KEYRD](#getkey) | Keyboard fetch primitives (READKEY rescans two-key rollover; used by INKEY$) |
| [STACKA / STACKBC / STACKHL / STKSTORE / STKFETCH](#stacka) | Push/pop 5-byte entries on the FP calculator stack (numbers or string descriptors) |
| `STKSTOREP`/`STKST0`/`STKSTOS` | Stack a string descriptor with the current/masked page |
| [FDELETE / HLTOFPCS](#fdelete) | Fast drop of the top FP entry / push 5 bytes from (HL) |
| [GETINT / GETBYTE / FPTOBC / FPTOA](#getint) | Unstack the top value as an integer (error 30 if negative or out of range) |
| [SETMIN / SETWORK / SETSTK](#setmin) | Reset edit line / workspace / FP stack to empty |
| [SRCHPROG / SEARCHALL / FINDERS](#srchprog) | The program searcher: find token E, with token D counted as "intervening" (nesting), optional second target C, one line or whole program |
| [MKRMCH / MKRM1 / MAKEROOM / MKRBIG](#makeroom) | Open 1/BC/ABC bytes at (HL), moving everything above and adjusting the 14 memory pointers |
| `FNORECL`/`NORECL` | Find and delete a program line |
| [RECLAIM1 / RECLAIM2 / RECL2BIG](#reclaim2) | Close up DE→HL / BC bytes / ABC bytes at (HL) |
| [WKROOM](#wkroom) | Extend the workspace end by BC bytes; DE=room start |
| `ASSV`/`AFLPS` | Adjust a stored page/addr triple (FOR records, BASIC-stack frames) after a move |
| [ADDRSV family](#addrsv) | ADDRELN/ADDRPROG/ADDRCHAD/ADDRWK/ADDRNV/ADDRSAV/…: page in and load HL from a (page,addr) system variable |
| `NEXTONE`/`DIFFER` | Get the extent of a program line / BC = HL−DE |
| `LIMBYTE`/`LIMDB` | Range-check the FP top against limit D, raising error E |
| `SPLITBC` | Split BC into PAGCOUNT/MODCOUNT for FARLDIR |
| `GETROOM` | Free memory (RAMTOP − workspace end) as a 19-bit value |
| [PGOVERF / DECPTR / CHKPTR](#pgoverf) | Correct an address that stepped over/under the &8000–&BFFF window, adjusting the page |
| [ADDAHLBC / SUBAHLBC / ADDAHLCDE / SUBAHLCDE / PAGEFORM / AHLNORM](#addahlbc) | Page-form ↔ 19-bit address arithmetic |
| `SETESP` | Push an error-return frame (old ERRSP saved on stack) |
| `RDRLEN`/`RDLLEN`/`RDTHREE` | Read 3-byte lengths from the tape header buffers |
| [EDGE2 / EDGSENS](#edge2) | Tape-edge timing loop (returns pulse length in C; NC on BREAK/timeout) |

### Details

#### GETKEY
`KEYRD` calls the ROM1 scanner then reports the buffered key; `READKEY` (the
INKEY$ back-end) does a fresh two-key scan (`TWOKSC`) and translates through
the key map; `KBFLUSH` empties the queue and clears the new-key flag.

#### STACKA
All values on the calculator stack are 5 bytes. `STKSTORE` writes A,E,D,C,B
in order — for a string that is page/flags, start-lo, start-hi, len-lo,
len-hi; for a small integer 0, sign, lo, hi, 0. `STKFETCH` is the exact
inverse. STKSTOREP variants insert the current URPORT page with bit 7
signalling "delete old copy after assignment" (set for simple unsliced
strings).

#### FDELETE
STKEND −= 5 without copying; returns HL pointing at the dropped value so
callers can read or move it (this is how values are copied out).

#### GETINT
FPTOBC forces the top value to small-integer form (adding 0.5 and INT if it
is in FP form), then returns BC/HL/A with CY if |value| ≥ 65536, NZ if
negative; GETINT/GETBYTE raise error 30 on CY/NZ (GETBYTE also for >255).

#### SETMIN
Writes CR,&FF at ELINE (empty edit line + program-area terminator), points
WORKSP after it, and falls into SETWORK (WKEND=WORKSP) and SETSTK
(STKEND=FPSBOT).

#### SRCHPROG
The generalised finder used by DO/LOOP, IF/ELSE, DEF FN/DATA searches, RENUM
and FOR. Inputs: E=target token, D=intervening token (nesting counter;
THENTOK means none), C=secondary target armed when nesting depth returns to
zero (LELSE handling), B'=&FF for whole program or 0 for one line, all
scanned from CHAD. Skips &0E forms, quoted strings and REM statements;
tracks statement numbers in A'. Returns CY=found with CHAD just past the
target and A=statement number.

#### MAKEROOM
Opens space at (HL): checks room (insisting on a 150-byte reserve except for
`MKRMCH`), then calls ROM1 `XOINTERS` (using.asm) which adjusts the 14
pointer system variables (SAVARS…PRPTR) and computes the block to shift, and
FARLDDR moves it up. `MKRBIG` takes a page-form length (A pages + BC).
Everything from the insertion point to WKEND moves; auto-adjusted pointers
(including KCUR, CHAD, XPTR, PRPTR when temporarily holding user pointers)
follow automatically.

#### RECLAIM2
The inverse: XOINTERS with CY adjusts pointers down and FARLDIR closes the
gap. RECLAIM1 takes start (DE) and end (HL); RECL2BIG a page-form size.

#### WKROOM
Grows the workspace at WKEND by BC bytes (no shifting — workspace is the top
of the moving region). Returns DE=start of the new room, HL=end.

#### ADDRSV
Each of these loads A=page byte, pages it in (section C), and returns HL =
the stored address, exploiting the fixed layout `page, addr-lo, addr-hi` of
the pointer system variables.

#### PGOVERF
When pointer arithmetic overflows &BFFF (or underflows &8000), these fix the
address back into the &8000–&BFFF window and step URPORT accordingly.

#### ADDAHLBC
The page-form address kit: AHL (A=page 0–31, HL=&8000–&BFFF) ⇄ 19-bit linear
via AHLNORM/PAGEFORM; add/subtract BC or another page-form CDE. All memory
sizing in the ROM uses these.

#### EDGE2
The tape input timer: alternates border colour, watches the EAR bit with a
47-T loop counting in C, returns CY=edge found, NC,Z=timeout, NC=BREAK.

---

## graph0.asm

| Entry point | Description |
|---|---|
| [CIRCLE / JCIRCLE](#circle) | CIRCLE x,y,r — 8-way symmetric point-plotting circle with thin-pixel support |
| [DRAW / JDRAW / JDRAWTO / DRAWLINE](#draw) | DRAW dx,dy / DRAW TO x,y (+ optional curve angle) — Bresenham-style line with off-screen run-off handling |
| `THINDRAW` | The 512-pixel-wide (mode 2 thin) line variant |

### Details

#### CIRCLE
After SYNTAX9 (colour items + coords) and radius, plots the four axis points
then walks one octant, mirroring each point 8 ways (`CIRCEX`→`CIRC3/4/5`).
The per-point plot goes through the IY vector chosen by SETIY (or the
thin-pixel `THCIRCSR`). Radius 0 degenerates to PLOT. BLITZ recording code 3.

#### DRAW
`DRAW TO` converts absolutes to displacements from the current position;
plain DRAW takes signed displacements (through XRG/YRG scaling). An optional
third argument makes a curve (DRCURVE in using.asm approximates it with
chords). The line loop tracks error in C, taking straight or diagonal steps
via pre-computed step routines, plotting through IY; if the line would leave
the screen, `PLOTCHK`/`RUNOFF` clips it and "Off screen" (32) is raised at
the end unless it started off-screen. Updates XCOORD/YCOORD to the endpoint.

---

## graph1.asm

| Entry point | Description |
|---|---|
| [PLOT / JPLOT / PLOTFD / THINPLOT / TDPLOT](#plot) | PLOT x,y in all modes, fat and thin pixels; records to BLITZ string (code 1) |
| `M0DPLOT`/`M1DPLOT` | Mode 0/1 plot used by DRAW (pattern bit + attribute) |
| `M3DPOV0…M3DPOV3` | Mode 2/3 nibble plots for OVER 0/1/2/3 (force, XOR, OR, AND), each with inverse variants |
| [SETIY](#setiy) | Choose the plot routine for the current mode/OVER/INVERSE into IY; A=ink nibble for modes 2/3; hookable via SETIYV |

### Details

#### PLOT
`PLOTFD` fiddles coordinates through XOS/YOS/XRG/YRG (Y ends 0 at top),
updates YCOORD/XCOORD, selects the screen page, and jumps through IY. Thin
plot computes
$ \text{addr} = \&8000 + Y \times 128 + \lfloor X/4 \rfloor$
and rotates a 2-bit mask into place, honouring OVER and INVERSE against
M23INKT/M23PAPT.

#### SETIY
Dispatch matrix: mode 0/1 → M0DPLOT/M1DPLOT; modes 2/3 → one of the four
OVER routines, pre-loading D' with the ink nibble (doubled for even/odd
pixels). GOVERT (graphics OVER 0–3) selects XOR/OR/AND variants; INVERT
flips to the paper colour.

---

## graph2.asm

| Entry point | Description |
|---|---|
| [BLITZ / JBLITZ / FDMAINLP](#blitz) | Interpret a graphics-command string: coded PLOT/DRAW/CIRCLE/OVER/INK/CLS/PAUSE records |
| [FILL / JFILL](#fill) | Textured flood fill (optionally `USING a$` 16×8 pattern), using a check screen and a coordinate stack |
| [TRANSCR / TRANSODD](#transcr) | Copy the mode 2/3 screen into the &E000 "check screen" as a 1-bit-per-pixel blocked/free map |
| [CHARCOMP / GRCOMP](#charcomp) | Compress a mode 2/3 character cell to 1-bit form (SCREEN$, graphics COPY) |
| [GTFCOORDS / GTFIDFCDS / USCOORDS](#gtfcoords) | Unstack and range-check coordinates, applying XOS/YOS/XRG/YRG fiddling; force fat pixels for GET/ROLL |

### Details

#### BLITZ
`BLITZ a$` executes a string of records (the same format `GRAREC` appends
when RECORD is active):

| Record bytes | Action |
|---|---|
| `sgnX, X, sgnY, Y` | Relative draw (sign bytes &00/&FF) |
| `01, x, y` | PLOT |
| `02, x, y` | DRAW TO |
| `03, x, y, r` | CIRCLE |
| `04, o` | OVER o |
| `05, i` | INK i |
| `06, c` | CLS c (0 = whole screen, 1 = window) |
| `07, n` | PAUSE n |

Coordinates pass through the same fiddling as the typed commands.

#### FILL
Requires MODE 2/3. Builds a 128-byte pattern buffer (solid = current ink;
`USING a$` = a 16-row pattern; string must be 128 bytes when patterned),
calls TRANSCR to build the check screen, then seed-fills line by line: for
each horizontal run bounded by set bits it marks the run, pushes candidate
runs above/below on FILLSTK, and paints the real screen through the pattern.
"Stored area too big"/stack overflow are guarded.

#### TRANSCR
Copies the display (mode 3: whole screen; mode 2: the relevant part) to
&E000+ as one bit per pixel where 1 = colour differs from the fill origin's
colour — the fill's blocking map.

#### CHARCOMP
Reduces an 8-scan character cell (2 or 4 bytes per scan) to 8 single bytes in
SCRNBUF by comparing against the top-left pixel colour — shared by SCREEN$
matching and graphics COPY.

#### GTFCOORDS
Unstacks Y then X, converts BASIC's −16…175 Y range to physical 0–191
top-down, checks X against 255 (fat) or 511 (thin, CY returned), applying
the XOS/XRG/YOS/YRG pseudo-variables (which live at fixed displacements in
the numeric variables area). `GTFIDFCDS` halves thin X so ROLL/GRAB always
work in fat coordinates.

---

## grabput.asm

| Entry point | Description |
|---|---|
| [GRAB / JGRAB](#grab) | GRAB a$,x,y,w,len — capture a screen block into a string: `00,widthBytes,len` header + raw scans |
| [PUT / JPUT](#put) | PUT x,y,a$[,mask$] — write a grabbed block back with OVER 0–3/INVERSE, optionally masked |
| `GPTRUNC`/`GPVARS` | Clip block length at the screen bottom; compute screen address and counters |
| `PUTSRTAB` | The four 10-byte inner loops (LD/XOR/OR/AND) + fast LDIR path + masked path |
| `PSCHKMHL`/`SCRMOV` | Validate a PUT string (must start CHR$ 0, non-empty) and copy it into spare screen memory |
| [FARLDIR / FARLDDR / STRMOV](#farldir) | The universal cross-page block move: PAGCOUNT×16K + MODCOUNT bytes from page A,HL to page C,DE via a 256-byte bounce buffer |

### Details

#### GRAB
Captures via the ROLL/SCROLL store-block routine into RSBUFF, prefixing
control code 0, width (bytes) and length (scans), then assigns the whole
thing as a string (so it can be saved, copied, PUT elsewhere). Width is
rounded up to whole bytes; requires MODE 2/3.

#### PUT
Validates the string(s); a mask string must match width/length ("PUT mask
mismatch"). Chooses the inner loop: OVER0+INVERSE0 uses plain LDIR; OVER 0–3
apply INVERSE as an XOR mask then LD/XOR/OR/AND to the screen; the masked
variant ANDs through the mask string so only 1-bits of the mask are altered.
Blocks hanging off the bottom are truncated.

#### FARLDIR
The ROM's memcpy. Source page/addr in A/HL, destination in C/DE, size in
PAGCOUNT (16K units) + MODCOUNT. Copies via BUFF256 in the system page in
256-byte chunks, re-paging source and destination alternately, in either
direction (FARLDDR for overlapping upward moves). Exit leaves TEMPW1/TEMPB2
past the destination. INSLV offers a vector hook.

---

## assign.asm

| Entry point | Description |
|---|---|
| [VALFET1 / VALFET2](#valfet1) | Evaluate the right-hand side, insist its type matches FLAGS, then ASSIGN if running |
| [ASSIGN / ASSISR](#assign) | Store the FP-stack top into the variable described by DEST/DESTP/FLAGX/STRLEN |
| `ASENV`/`ASNN` | Overwrite an existing numeric / create a new numeric at NUMEND (linking it into its letter chain, opening 512 bytes if the gap is tight) |
| [ASSTR / ASDEL / ASNST](#asstr) | Assign to an existing string (copy + space-pad into the fixed-length slot, or delete-and-recreate for simple strings) / create a new string at the end of SAVARS |
| `ASDEL2`/`ASDEL3`/`ADD14` | Delete a string/array record (data + 14-byte header) |
| [RECORD](#record) | RECORD TO a$ (arm stream-16 output into a string) / RECORD STOP |
| [SYNTAX1 / SYNTAX4 / SYN14C](#syntax1) | Assess a variable for assignment (SYNTAX4: FOR variables), setting DEST/DESTP/STRLEN/FLAGX/DFTFB |
| [STKVAR / STKVAR2 / SVARRAYS / SLICING](#stkvar) | Index arrays and slice strings: subscript evaluation, element address computation, slicer defaults |
| [DIM](#dim) | DIM name(d1,…,dn): delete any old version, build header (total len, len, dim count, dim sizes) and clear the data |
| `GETSUBS` | Evaluate a subscript, check 1…limit, return it decremented |
| `SAROOM` | Open room at the end of SAVARS and copy in the type/name header |

### Details

#### VALFET1
Used by LET/READ/INPUT: SCANNING evaluates, the result type is compared with
the target's (error 29 on mismatch), and in run time ASSIGN stores it.

#### ASSIGN
Branches on type and FLAGX bit 0 ("new"): existing number → 5-byte copy over
the old value; new number → `ASNN` links a fresh record at NUMEND (relative
pointer from the previous chain tail) after ensuring ≥60 free bytes (else
opening 512 before SAVARS); strings → ASSTR. `CGXRG` is a related special:
halve/double XRG when FATPIX/MODE changes pixel width.

#### ASSTR
Slices and array elements are fixed-size: the source is FARLDIR'd in,
truncated or space-padded to the destination length. Simple strings (DESTP
bit 7 set) are variable-size: the new value is first *created* as a fresh
record at the SAVARS end (`ASNST` — so `LET a$=a$+"x"` works), then the old
record is deleted (`ASDEL`). ASNST protects sources above WKEND from
pointer auto-adjustment during MAKEROOM.

#### RECORD
`RECORD TO a$` deletes any existing a$, stores its name in STRM16NM, sets
GRARF (graphics commands also append their BLITZ records), and creates a$ as
a null string; stream 16 output (`S16OSR`) then appends bytes to it.
`RECORD STOP` clears GRARF.

#### SYNTAX1
LOOKVARS then `SYN14C`: records DEST (value address, or chain-tail/stopper
address for new variables), DESTP (page; bit 7 = "delete old copy"), STRLEN
(length or type byte), FLAGX bit 0 ("new"), and DFTFB (zero iff an existing
number is "minus zero", which DEFAULT treats as non-existent). Undimensioned
arrays and slices of new strings raise error 2 here.

#### STKVAR
At check time just validates subscript/slicer syntax. At run time: simple
strings convert the pages+mod-16K length to a 16-bit length and stack a
descriptor (bit 7 of page set = replace-on-assign); arrays walk the dimension
list computing
$ \text{total} = (\dots(s_1 \times d_2 + s_2) \times d_3 + \dots) + s_n $,
finally multiplied by 5 (numeric) or by the last dimension (string) and
added to the data start. String results may then be sliced:
`SLICING` handles `(a TO b)` with defaults, empty result for reversed
ranges, and error 4 for out-of-range values.

#### DIM
Deletes any existing variable of the same name, evaluates the dimension
sizes (pushing them on the machine stack and multiplying on the FP stack),
computes text size + dim-info size + 14-byte header, opens the room at the
SAVARS end via SAROOM, then writes: pages, len-mod-16K (of data after
header), dim count, dim sizes (words), and clears the data to 0 (numeric) or
spaces (string). Note the stored "length" covers everything after the
3-byte length field itself, i.e. dim data + elements.

---

## fn.asm

DEF FN / FN, DEF PROC / PROC / LOCAL, and the COMPILE pass. See
[tokenized-program-format.md](tokenized-program-format.md) for the calling
buffer byte format this file creates and patches.

| Entry point | Description |
|---|---|
| [COMPILE / DOCOMP / SCOMP](#compile) | The compile pass: assign LABEL line numbers to variables, then patch every FN/PROC calling buffer with the target's page/address |
| `COMDF`/`COMDP` | Build a table of all DEF FNs (page/addr) in INSTBUF (≤170, error 52); scan for FE/FD calling buffers and resolve them |
| [LKCALL](#lkcall) | Find the next calling buffer: pattern `not-0E, 0E, FD/FD or FE/FE, byte≥&80`; extracts the call-site name into NMBUFF |
| [LOOKDF / LOOKDP](#lookdf) | Match the name against DEF FNs (table) / DEF PROC lines (LKFC scan); patch the buffer with page OR &80 + address, or &FF if unresolved |
| `MATCHER`/`MATCHFN`/`MATCHERF` | Case-insensitive name comparison (spaces skipped in the candidate) |
| [IMFN](#imfn) | Run-time FN evaluation: use the patched buffer to jump to the DEF FN, copy argument values into its parameter buffers, evaluate its expression with DEFADD set |
| [FNSYN / PROCSY / MKCLBF](#fnsyn) | Syntax-time: create the 6-byte calling buffer `0E FE FE FE ? ?` (FN) or `0E FD FD FD ? ?` (PROC) after the name |
| [MAKESIX](#makesix) | Open 6 bytes at (HL) and write the &0E marker — the primitive behind all invisible forms |
| [DEFPROC / PROCS](#defproc) | DEF PROC (run time: skip to END PROC) and the PROC-call dispatcher (reached for any statement starting with a letter) |
| [LOCAL](#local) | LOCAL v-list: process like PROC parameters with an empty call list, so variables become local |
| [LKFNVAR](#lkfnvar) | During FN evaluation, resolve single-letter variables from the DEF FN parameter buffers (searched via DEFADD) |
| `FORESP`/`FORESP1` | Advance HL to the next significant (≥ &21) character |
| [LKFC](#lkfc) | Find a token at the start of a program line (skipping leading spaces/CCs) — used for DEF PROC and LABEL scans |
| `FNNAME`/`VARNAME`/`VARAR` | Name syntax checks (FN names, PROC parameter names, `name()` forms) |

### Details

#### COMPILE
Runs before any program execution (RUN/CLEAR/GOTO of the edit line). If
COMPFLG bit 7 is set (program changed), it first executes every `LABEL name`
by assigning the line number to the named numeric variable, then resolves
calling buffers in the whole program; the edit line is always resolved (FNs
only if REFFLG says any FN appears). CHAD/KCUR juggling keeps pointers valid
while variable creation moves memory.

#### LKCALL
Scans up to B' 8K blocks for &FD/&FE with CPIR, then verifies the full
signature: preceded by exactly one &0E (two would be a numeric literal
coincidence), followed by a byte with bit 7 set (fresh buffers hold FD/FE
&FD/&FE ≥ &80; patched ones hold page|&80). It then walks *backwards* over
the name (letters/digits/underscore/$, skipping a preceding &FF &42 'FN'
token pair) and copies length+name into NMBUFF.

#### LOOKDF
FNs: compare NMBUFF against each table entry (the byte after 'DEF FN').
PROCs: `LKFC` scans line starts for the DEF PROC token, then matches the
name. On success the buffer bytes 3–5 become page|&80 and the address just
past the DEF PROC/FN name; on failure page byte &FF (bit 5 set = "missing",
tested at call time).

#### IMFN
Scans forward from CHAD to the &0E of the calling buffer, errors if bit 5 of
the page byte is set (7, "FN without DEF FN"), then for each parameter in
the DEF FN header: evaluates the corresponding FN argument (type-checked
$ vs numeric) and copies the 5-byte result into the parameter's own &0E
buffer inside the DEF FN line. Finally evaluates the expression after "=" with
DEFADD pointing at the DEF FN's parameter list (so LKFNVAR resolves
parameters) and CHAD/DEFADD restored afterwards — recursion-safe because the
previous DEFADD is stacked.

#### FNSYN
At syntax-check time `FN name(args)` and `procname args` get `MKCLBF`: six
bytes are opened after the name — &0E then five filler bytes (&FE×3 for FN,
&FD×3 for PROC, last two undefined) — and the argument list is checked.
Because the buffer starts with &0E, every other part of the ROM (listing,
searching, skipping) treats it as an invisible number form.

#### MAKESIX
`LD BC,6 : CALL MAKEROOM : LD (HL),&0E : INC HL : RET` — also used by DEF FN
parameter buffers and (in miscx2) DEF KEYCODE.

#### DEFPROC
Running into a DEF PROC statement means falling through sequential execution:
it searches for END PROC (error 13 if missing) and continues after it. The
statement's syntax pass checks the parameter list (REF allowed) and an
optional trailing DATA. `PROCS` is the run-time call: finds the buffer,
errors 12 if unresolved, sets PRPTR (call-site parameter pointer) and
DPPTR (definition parameter pointer), pushes a PROC frame (&40) returning to
the *next* statement, then jumps to statement 2 of the DEF PROC line after
PROPAR has bound the parameters.

#### LOCAL
Sets up PRPTR to point at a CR in ROM (empty call list) and DPPTR at its own
argument list, then runs the same parameter processing (PROP2), so each
listed variable is given a local (hidden-global) copy initialised from the
PROC machinery with no value. The current statement position is pushed as a
pseudo-PROC frame so END PROC unwinds it.

#### LKFNVAR
Only single-letter names participate (longer names always use global
variables). Searches from DEFADD for parameter buffers: a numeric parameter
is `letter 0E …5 bytes…`, a string parameter `letter $ 0E …`; on a match the
5 bytes are stacked directly (for strings they are a string descriptor
copied from the argument).

#### LKFC
Line-start scanner: for each line, skip leading spaces/control bytes; if the
first significant byte equals C, return NC with CHAD on it. Used by the
LABEL and DEF PROC passes and by RESTORE's DATA search variant.

---

## nparpro.asm

PROC parameter processing — the most intricate part of the interpreter. The
long comment at the top of the file is the specification; the summary:

| Entry point | Description |
|---|---|
| [PROPAR / PROP2](#propar) | Bind PROC-call arguments to DEF PROC parameters, stacking undo records on the BASIC stack |
| [RESTORE / RESTOREZ](#restore) | The RESTORE command (placed here to share a JR); set DATADD to line n (or 0) |
| `UNVLK` | Find an "unused" numeric variable slot of matching name/type to re-use for a local |
| `RUAHL` | Record on the BASIC stack the displacement (from NVARS) of a variable to reveal/mark-unused at END PROC |
| `PPSUB` | Record a type/name string on the BASIC stack (with flag bits in the stored type byte) |
| `NEGVTR` | Cancel a "reveal" record when a REF variable turns out to be the same as a hidden global |
| [DELOCAL](#delocal) | END PROC/POP teardown: walk the BASIC-stack records — copy REF values back, mark locals unused, reveal hidden globals, delete local strings/arrays, rename REF strings back |
| `PTTODP`/`PTTOPR` | Point CHAD at the DEF PROC / PROC parameter list (Z at list end) |

### Details

#### PROPAR
For each DEF PROC parameter: numeric by value — any existing global of the
same name is hidden (bit 7 of its type byte; a second copy is neutralised as
"minus zero"), a local is created (re-using an "unused" slot when possible)
and the call argument assigned to it. REF numeric — the argument must be a
variable; the local is aliased both ways with records so END PROC copies the
final value back. Strings/arrays by value — the global is hidden and a new
local string created at the SAVARS end; REF strings/arrays are *renamed* to
the DEF PROC name via the rename stack at HDR, and renamed back at END PROC.
Every action pushes a typed undo record; "BASIC stack full" (41) and
"Parameter error" (26) guard the process.

#### RESTORE
`RESTORE [n]` finds line n (default 0) and points DATADD/DATADDP just before
it so READ's scanner takes over from there.

#### DELOCAL
Interprets the undo records (format documented in the source at DELOCAL):
terminator 00 00; &FF-prefixed = REF string rename record; bit 4 set =
string/array name (bit 7: also reveal a hidden global); bit 4 clear =
displacement of a numeric (bit 7: reveal; bits 7/5: REF value copy-back via
a temporary buffer). Runs until the terminator, restoring BSTKEND.

---

## misc2.asm

| Entry point | Description |
|---|---|
| [ERROR2](#error2) | The RST 8 back-end: record XPTR, consult RST8V, pass hook/error codes to DOS if booted, else set ERRNR and long-jump to ERRSP |
| `PTDOS`/`DOSC` | Page the DOS in at &4000 and call its error (&4203) / hook (&4200) entries |
| [TOKMAIN / TOKDE / BUFMV](#tokmain) | Copy the tokenizer body from ROM1 into CDBUFF+&80 and run it over the edit line (or arbitrary text for VAL) |
| `MEPROG`/`INPUT`/`RENUM`/`KEYIN`/`GET`/`DELETE`/`POP`/`DEFKEY`/`DEFFN` | Stubs that copy the corresponding ROM1 body (see miscx1/miscx2) into INSTBUF/HDR and jump to it |
| [LET / DEFAULT](#let) | LET a=…,b=… and DEFAULT (assign only if the variable doesn't exist / is "minus zero") |
| `LABEL`/`SVNUMV`/`VNUMV` | LABEL name: (run time: skip; compile does the work); numeric-variable validators |
| [RUN / CLEAR](#run) | RUN [n] = GOTO n + RESTORE 0 + CLEAR 0; CLEAR [addr] resets variables, stacks, RAMTOP |
| `CLRSR`/`SETSYS`/`SETNE`/`SETSAV` | Clear FPCS/BASIC stack/variables (26 chain pointers to FFFF, XYZ pseudo-vars re-seeded); set (page,addr) sysvars |
| `CLSND` | Zero all 32 sound-chip registers |
| [S16OSR](#s16osr) | Stream-16 output: append the character to the string variable named in STRM16NM |
| [SYNTAX3 / SYNTAX6 / SYNTAX8 / SYNTAXA and friends](#syntax3) | Argument-shape helpers: expect number/0, number, number-pair, string; bracket/comma insisters; expression classifiers |
| `RUNFLG`/`ABORTER`/`CHKEND` | CY if running; abort a command routine at check time; insist on end-of-statement |
| [ALPHA / NUMERIC / ALPHANUM / ALDU / ALNUMUND](#alpha) | Character classes (ALDU defines which trailing chars block tokenization) |
| [BRKLSSL / GIR / GIR2](#brklssl) | Bracketless slicer `a TO b` for LIST/DELETE/AUTO ranges into FIRST/LAST |
| `DISPLAY`/`SETDISP`/`VIDSEL`/`SDISR` | DISPLAY n: switch the displayed screen, swapping palettes between screen pages |
| `PRSVARS`/`RSVARS`/`SSVARS` | Save/restore the print variables block to/from the non-displayed screen's page |
| [R0INST](#r0inst) | The INSTR inner search (CPIR-based, `#` wildcard) |

### Details

#### ERROR2
Records CHAD in XPTR (the `?` marker for listings), fetches the code byte
following the RST 8, and: if DOS is booted and not already in control, passes
hook codes (≥128) and errors to the DOS page (special returns 1/2/3 continue
LOAD/SAVE flows); codes ≥128 without DOS give "No DOS" (53). Otherwise ERRNR
is set and SP reset from ERRSP — landing in MAINER, an editor error frame, or
a SETESP frame.

#### TOKMAIN
The tokenizer must run with ROM1 paged out (the text lives up there in the
same range), so its body (`TOKPT2`, miscx2.asm) is LDIR'd from its assembled
position in ROM1 to CDBUFF+&80 and entered there. `TOKDE` is the entry used
by VAL/VAL$, tokenizing arbitrary text at DE. All the sibling stubs compute
their body's ROM1 address as &C000 plus the summed lengths of the bodies
before it.

#### LET
LET assigns each `var=expr` via SYNTAX1+VALFET1. DEFAULT does the same but,
when running and the variable exists (DFTFB≠0, i.e. not "minus zero"), the
expression is evaluated and discarded instead of stored.

#### RUN
RUN = GOTO n (default 0), RESTORE 0, then CLEAR's core: reclaim the
NVARS→ELINE gap to 605 bytes, clear variables/stacks (CLRSR), re-run COMPILE,
CLS, and validate/set RAMTOP (error 48). CLEAR addr moves RAMTOP (checked
against WKEND+180 and LASTPAGE).

#### S16OSR
Looks up the recorded string variable, extends it by one byte at its end
(MKRM1) and stores the output character — making `PRINT #16` (and RECORDed
graphics) append to the string. Error 42 past &FEFF bytes.

#### SYNTAX3
The syntax helper family: each expects a particular argument shape and, at
check time, *discards its caller's return address* so the command routine is
skipped (the standard early-out idiom). EXPTEXPR returns Z for a string
expression; EXPT1NUM/EXPT2NUMS/EXPT4NUMS chain commas; SYNTAX9 handles
embedded colour items before coordinates.

#### ALPHA
CY for A–Z/a–z. ALDU (letter, `_` or `$`) is what the tokenizer checks after
a matched word — so `printer`, `print_out`, `print$` stay untokenized while
`print1`/`print:` tokenize.

#### BRKLSSL
Parses `n`, `n TO`, `TO m`, `n TO m`, or nothing into FIRST/LAST (defaults
1/&FEFF), returning A=0 when a single number was given (LIST turns that into
"n TO end"; DELETE keeps it as one line).

#### R0INST
The INSTR core: CPIR for the first target character, then byte compare with
the INSTHASH wildcard honoured; returns BC=1-based position or 0/CY.

---

## endprint.asm

| Entry point | Description |
|---|---|
| [EPSUB / M0PRINT / M1PRINT / M2PRINT / M3PRINT](#epsub) | Render one character cell in each mode from the pattern at HL, honouring OVER (B) and INVERSE (C) masks and CSIZE |
| `POPOUT`/`R1OSR` | Paging bracket used around ROM0 helpers called from ROM1 |
| `GTRLNN` | RENUM helper: read the line number a header points at |
| [CWKSTK](#cwkstk) | Copy BC bytes from common memory to the workspace and stack the string parameters |
| [POFETCH](#pofetch) | Fetch the current print position (upper/lower screen or printer) and RHS limit |
| `UTMSG`/`POMSG` | Print utility message A / message A from list DE |
| [ANYDEADDR / M0DEADDR…M3DEADDR / CLCPO](#anydeaddr) | Row/column → screen address for each mode (mode 2 returns 6-pixel odd/even info) |
| [ANYPIXAD / M0PIXAD / M1PIXAD](#anypixad) | Pixel coordinate → address + bit/nibble offset for each mode |
| [POATTR01 / SETATTR](#poattr01) | Write the attribute for a mode 0/1 cell from ATTRT/MASKT/PFLAGT (INK 9/PAPER 9 contrast logic) |
| [STRCOMP](#strcomp) | Compare the two strings on the FP stack (Z equal, CY S1<S2) — the FPC string comparison back-end |
| [SBUFFET / SBFSR](#sbuffet) | Copy the string on the FP stack into INSTBUF (≤255 or ≤511 bytes) |
| `UNSTKPRT` | Unstack a string descriptor and compute the port value to page it in |
| `IDERR` | "Invalid device" — the input routine for output-only channels |
| [TSTRMBIG / TESTROOM](#tstrmbig) | Room checks: error 1 (Out of memory) if ABC/BC bytes won't fit below RAMTOP |

### Details

#### EPSUB
Entered from ROM1's PROM1 with DE=row/col, HL=character pattern, B=OVER mask
(&FF for OVER 1–3), C=INVERSE mask. Each mode routine computes the screen
address and merges `(pattern XOR C)` scans with optional XOR of the existing
byte; modes 2/3 expand bits through CEXTAB into coloured bytes/nibbles
(mode 2 also has the 85-column 6-pixel path with odd/even column phases);
mode 0/1 write pattern then attribute. Double-height (CSIZE ≥16) prints the
doubled matrix in two passes via DHADJ.

#### CWKSTK
Used by CHR$, STR$, BIN$ etc.: opens BC bytes of workspace, copies the text
in, and stacks page/start/len — making a temporary string result.

#### POFETCH
DEVICE selects SPOSNU/SPOSNL/PRPOSN; returns D=row, E=col, A=RHS limit
(WINDRHS or PRRHS), CY for printer.

#### ANYDEADDR
$ \text{addr} = \&8000 + \text{scans} \times w + \text{col} \times b $,
with the per-mode scan width $ w $ and bytes-per-column $ b $:

| Mode | $ w $ (bytes/scan) | $ b $ (bytes/column) |
|---|---|---|
| 0 | 32 (interleaved thirds layout) | 1 |
| 1 | 32 | 1 |
| 2 | 128 | 2 (8-pixel cells) or 1.5 (6-pixel, 85-column — odd/even phase returned) |
| 3 | 128 | 4 |

CLCPO converts character rows to scans (CALCPIXD) and adds LSOFF for the
lower screen.

#### ANYPIXAD
For POINT/plot: mode 0 interleaved thirds, mode 1 linear, modes 2/3 nibble
addressing (CY = odd pixel in mode 3).

#### POATTR01
Computes the attribute byte for a printed cell: MASKT bits pass through the
old attribute, PFLAGT bits 4/6 implement PAPER 9/INK 9 (choose contrasting
colour), and mode 0's attribute layout (thirds) is handled via CTAA.

#### STRCOMP
Fetches both descriptors (pages in each side as needed), compares byte-wise
across page boundaries; shorter string that matches is "less".

#### SBUFFET
For commands needing a filename or small string in common memory: fetch the
descriptor, error 27 ("Invalid argument") if len 0 or >255 (SBFSR2 variant
allows 511), copy to INSTBUF.

#### TSTRMBIG
All allocation funnels here: computes new WKEND, compares against RAMTOP,
raising "Out of memory" (1) if it doesn't fit; TESTROOM is the BC-byte
convenience wrapper.

---

## miscx1.asm

Start of ROM1. The first several bodies are `ORG`'d at their RAM execution
addresses (INSTBUF or HDR) and copied there by the misc2.asm stubs before
running, because they must read/write the program area that occupies the same
addresses as ROM1.

| Entry point | Description |
|---|---|
| [RNMP2 (RENUM)](#rnmp2-renum) | RENUM [first TO last] [LINE l] [STEP s]: build an old→new line-number table in screen memory, rewrite line numbers and every reference |
| `CHGREF`/`RENTAB` | Rewrite line-number references after tokens in RENTAB (DELETE, ON ERROR, LINE, LLIST, LIST, RESTORE, GOTO, GOSUB, RUN), re-sizing each line via ADJLINE |
| `ADJLINE` | Open/close space inside a program line and fix its length field |
| `TRANSFORM`/`TRANSHL` | Map an old line number through the SBO/SBN tables to its new value |
| [GETP2 (GET)](#getp2-get) | GET var: wait for a key and assign it (digit/letter value for numerics, CHR$ for strings) |
| [DELPT2 (DELETE)](#delpt2-delete) | DELETE [n] TO [m]: reclaim the block of lines |
| [KEYP2 (KEYIN)](#keyp2-keyin) | KEYIN a$: place a string in the edit line, tokenize, syntax-check, then insert or execute it |
| [POPP2 (POP)](#popp2-pop) | POP [var]: pop any BASIC-stack frame, optionally assigning the return line number; PROC frames also run DELOCAL |
| [INPP2 (INPUT)](#inpp2-input) | INPUT [LINE] items: print prompts, edit the reply in workspace, validate/assign; INPUT LINE takes raw text |

### Details

#### RNMP2 (RENUM)
Defaults LINE 10 STEP 10 over the whole program. Uses the two screen-page
halves SBO/SBN as parallel arrays of old and new numbers (needs 6K free and
the screen paged in), refusing if lines would collide with un-renumbered
neighbours or exceed &FEFF. Reference rewriting evaluates the &0E form after
each reference keyword, transforms it, writes the new 5-byte form and
re-prints the digits (via `JPFSTRS`), adjusting the line length either way —
so both the visible text and the invisible form stay consistent.

#### GETP2 (GET)
Waits for a key (BREAK allowed). String targets get CHR$(key); numeric
targets get 0–9 for digits or 10+ for letters (hex-style).

#### DELPT2 (DELETE)
Range via GIR2/`TO`; unlike LIST, a single number deletes one line. Computes
the page-form length between the first and past-the-last line and RECL2BIGs
it, then re-enters execution via GT4R (a GOTO to the current position, since
NXTLINE etc. are stale).

#### KEYP2 (KEYIN)
The programmatic line-entry command: the string is copied into ELINE,
TOKMAIN+LINESCAN run over it, and it is inserted (line number present) or
executed as a direct command (no line number) — all under a private error
frame so failures return to the caller.

#### POPP2 (POP)
`POP` discards the top BASIC-stack frame of *any* type; `POP v` also assigns
the frame's return line number (0 for the edit line) to v. PROC frames get
their locals unwound.

#### INPP2 (INPUT)
Clears the lower screen and workspace, then walks the item list: embedded
`(print items)`, prompts, separators, and variables. Each numeric/string
variable presents an editing buffer (quotes pre-inserted for plain string
INPUT), runs the EDITOR on it, tokenizes, and validates with a syntax pass
before assigning; INPUT LINE skips validation and assigns the raw text.
`STOP` typed as input raises error 17. Errors in K/S channels loop back to
re-edit rather than aborting.

---

## miscx2.asm

| Entry point | Description |
|---|---|
| [DKP2 (DEF KEYCODE)](#dkp2-def-keycode) | DEF KEYCODE n,a$ or DEF KEYCODE n:statements — store a definition in the DEF KEY buffer |
| [DFNP2 (DEF FN)](#dfnp2-def-fn) | The DEF FN statement's syntax pass: create the &0E parameter buffers after each parameter name |
| [TOKPT2 (the tokenizer)](#tokpt2-the-tokenizer) | Convert spelled-out keywords in a line to token bytes (runs at CDBUFF+&80) |
| [MEPRO2 (MERGE)](#mepro2-merge) | MERGE: load a program file into workspace and merge lines/variables into the current program |

### Details

#### DKP2 (DEF KEYCODE)
Key codes 192–254 are definable. The definition is either a string or the
raw rest of the line (statements form). Any existing definition is closed
up; the new one is appended before the &FF terminator as `code, len16, text`
(error 52 if DKLIM would be passed).

#### DFNP2 (DEF FN)
Runs only at syntax time (running skips the statement). For each parameter
`letter[$]`, `MAKESIX` opens `0E xx xx xx xx xx` right after the name —
the buffer that IMFN will fill with the argument value at call time. Then
the result expression after `=` is type-checked against the FN name's type.

#### TOKPT2 (the tokenizer)
The full algorithm is documented in
[tokenized-program-format.md](tokenized-program-format.md#2-the-tokenizer).
In brief: scan the line; at each candidate word start (letter, `<`, `>`)
copy up to 15 characters to a scratch buffer and match against the keyword
table with GETTOKEN (plus the MTOKV user hook); on a match write either a
single token byte (&85–&FE, entries ≥ &4A) or an &FF prefix + function code
(&3B–&83), absorb one leading and one trailing space, close up the freed
text, and continue — stopping at CR and after REM, and skipping quoted
strings and `FF`-prefixed codes already present.

#### MEPRO2 (MERGE)
Loads the file into an opened workspace block, then: merges BASIC lines one
by one (replacing same-numbered lines via MAKEROOM/FARLDIR), merges numeric
variables (re-creating each via the FP stack), and merges strings/arrays
(deleting same-named victims first). Uses the saved header's three length
fields to separate program, numeric variables and string area.

---

## fpcmain.asm

The floating-point calculator: a byte-coded stack machine entered by RST &28.
The opcode values are listed in [constants.md](constants.md#fpcmainasm).

| Entry point | Description |
|---|---|
| `FPATAB` | Dispatch table: operation code ×2 indexes the handler address |
| [FPCMAIN / FPCLP / BREGEN](#fpcmain) | The fetch-execute loop: IX is the instruction pointer, DE tracks STKEND; RST28V hook first |
| `FPUSEB` | Execute the operation code held in BREG (how the expression evaluator runs queued operators) |
| `FPSTO`/`FPSTOD`/`FPRCL` | Store (keep/delete) and recall calculator memories 0–5 at (MEM) |
| [FPCONST / FPCTAB](#fpconst) | Stack a constant (0.5, 0, 16384, 1.0, 1, 10, π/2) |
| `FPEXIT`/`FPEXIT2` | Leave the calculator (EXIT2 also unwinds the RST 28 frame — used at the end of `DB CALC` sequences inside FPC routines) |
| `FPDUP`/`FPDROP` | Duplicate / drop the top entry |
| [FPJUMP / FPJPTR / FPJPFL / FPLDBREG / FPDECB](#fpjump) | Signed relative jumps in the code stream, conditional on true/false; BREG load/decrement-and-branch |
| `FPSOMELIT`/`FP5LIT`/`FP1LIT` | Stack inline literals (n bytes / 5 bytes / 1 byte as a small integer) |
| `FPLKADDRB`/`FPLKADDRW` | PEEK/DPEEK an inline address onto the stack |
| [FPGRTE0 / FPGRTR0 / FPNOT / FPLESE0 / FPLESS0 / SETTRUE / SETFALSE](#fpgrte0) | Sign/zero tests producing 1/0 |
| `FPAND`/`FPOR`/`FPSAND` | Logical AND/OR (N2 zero-test semantics); `a$ AND n` |
| [FPSEQUAL…FPSNOTE](#fpsequal) | The six string comparisons via STRCOMP |
| [FPNEQUAL…FPNNOTE](#fpnequal) | The six numeric comparisons as subtract + sign-test calculator programs |
| `FPMOD`/`FPIDIV` | MOD and DIV as composite calculator programs |
| `FPBOR`/`FPBAND` | Bit-wise OR/AND on 16-bit integers |
| `TSTZERO` | Z if the 5-byte value at (DE) is zero |

### Details

#### FPCMAIN
Each iteration pushes FPCLP as the handler's return, refreshes STKEND from
DE, fetches the code byte at (IX+0). Codes &00–&1F are binary (DE backed up
5 so HL/DE point at N1/N2 and the result overwrites N1), &20–&5F unary,
&C8–&CF/&D0–&D7/&D8–&DF store/store-keep/recall memories, &E0–&FF constants.
Anything else: error 51 "FPC error". The RST28V vector sees every code
first, allowing full replacement/extension.

#### FPCONST
FPCTAB packs the constants: small-integer forms for 0, 16384, 1, 10 and FP
forms for 0.5 (&80 00 00 00 00 → exponent-only), 1.0, π/2
(&81 49 0F DA A2).

#### FPJUMP
The displacement byte at (IX) is signed. JPTRUE/JPFALSE are *binary*
operations: they drop the tested value as they branch.

#### FPGRTE0
The comparison-with-zero family reads the sign byte and/or zero-tests the
value in place, then overwrites it with small-integer 1 or 0 (`SETTRUE`/
`SETFALSE` → `STACKC` writes 00 sign C 00 x).

#### FPSEQUAL
All six call `STRCOMP` (endprint.asm) then map Z/CY onto true/false.

#### FPNEQUAL
Each numeric comparison is literally `SUBN` followed by the appropriate
sign/zero test — three-byte calculator programs.

---

## transend.asm

Chebyshev-based transcendental functions, all written as calculator code.

| Entry point | Description |
|---|---|
| `FPSIN`/`FPCOS`/`FPTAN` | Sine (W.E. Thomson's faster series), cosine = sin(x+π/2), tan = sin/cos |
| `FPREDARG` | Reduce an angle to the −π…π range (V = x/2π fractional part scaled) |
| `FPEXP`/`FPPOWR2` | $ e^x = 2^{x \log_2 e} $; $ 2^y $ with integer/fraction split (error 28 on overflow, 0 on deep underflow) |
| `FPPOWER` | $ N_1^{N_2} $: special-cases $ N_1 = 0 $ and integer powers 0–&3F (by repeated multiplication), else $ e^{N_2 \ln N_1} $ |
| `FPLOGN` | Natural log: exponent extraction + series on the mantissa |
| `FPARCTAN`/`FPARCSIN`/`FPARCCOS` | ATN (range-folded series); $ \operatorname{ASN} x = \operatorname{ATN}\dfrac{x}{\sqrt{1-x^2}} $; $ \operatorname{ACS} x = \pi/2 - \operatorname{ASN} x $ |
| [SERIES](#series) | The Chebyshev series engine: 12-coefficient loop driven by DECB with inline literals |
| `FPSQR` | (in rom1fns/transend flow) $ \sqrt{x} = x^{0.5} $ via the POWER path with a fast exponent halving |

### Details

#### SERIES
Generator for all the above: BREG counts 12 terms; each loop iteration
stacks a coefficient literal (variable-length via SOMELIT) and performs the
Chebyshev recurrence in memories 0–2. The polynomial argument must be
pre-scaled by the caller.

---

## mult.asm

The binary arithmetic core.

| Entry point | Description |
|---|---|
| [QMULT](#qmult) | Fast 16-bit HL×DE (used by array indexing etc.), CY on overflow |
| `STORADE`/`STOREI`/`FETCHI` | Small-integer store/fetch between (HL) and DE/C(sign) |
| [FPMULT / FPMULT2](#fpmult) | Multiply: integer×integer fast path (falling back on overflow), power-of-two shortcut, else 32×32-bit mantissa multiply with rounding |
| [FPDIVN](#fpdivn) | Divide: power-of-two shortcut, else 34-bit restoring division |
| [FPADDN / FPSUBN](#fpaddn) | Add/subtract: integer fast path, else align exponents (ADDALIGN), add/sub mantissas, normalise (MULNORM) and round |
| `MUDIADSR` | Unpack two FP numbers into registers for multiply/divide (restores implicit leading 1 bits) |
| [DFPFORM / FPFORM](#dfpform) | Convert one/both stack entries from small-integer to full FP form (RESTACK) |

### Details

#### QMULT
Chooses the smaller operand as the bit counter; ~8 shifts for byte operands.

#### FPMULT
Both-integer inputs try QMULT with sign handling; overflow re-enters the FP
path. In FP: sign = XOR of signs, exponents add (−&80 bias), mantissas
multiply 8 bits at a time into HL'HL, then MULNORM normalises (shifting up
to 32 bits for cancellations), rounds on the 33rd bit, and stores exponent +
31-bit mantissa with the sign in bit 7 of the first mantissa byte. Overflow
→ error 28; underflow → zero.

#### FPDIVN
Division by zero → error 28 (via the subtract in the exponent path checking
N2=0 first — "Number too large"). Restoring division produces 34 bits so
the 0.25–0.999 raw quotient can be normalised and rounded.

#### FPADDN
If both are small integers, a 16-bit add with sign logic handles it unless
it overflows. FP path: the smaller exponent's mantissa is shifted right by
the exponent difference (>32 → result is the larger), mantissas add (same
sign) or subtract (different), the result renormalises — including the full
cancellation case giving zero.

#### DFPFORM
`FPFORM` (= calculator op RESTACK) rewrites a small-integer entry
`00 sign lo hi 00` as exponent/mantissa form (exponent = $ \&90 - s $ where
$ s $ is the normalising shift; mantissa = the value shifted so bit 30 is
the top set bit; sign in mantissa bit 7).
`DFPFORM` does both operands for the multiply/divide/power paths.

---

## rom1fns.asm

| Entry point | Description |
|---|---|
| [FPVAL / FPVALS](#fpval) | VAL/VAL$: tokenize the argument text in workspace, syntax-check it as an expression, then evaluate it (with FLAGS run bit borrowed) |
| `IMRND` | RND [(n)]: congruential seed update $ \text{seed} \leftarrow ((\text{seed}+1) \times 75 \bmod 65537) - 1 $; returns a fraction, or an integer in $ 0 \dots n-1 $ |
| `IMATTR`/`IMPOINT` | ATTR(l,c) and POINT(x,y) — read attribute byte / pixel ink number in any mode |
| `GETCP` | Validate a line/col pair against limits |
| `FPINKEY`/`FPINKEN` | INKEY$ [#n]: stream version reads the channel; builds a 1-char string |
| `FPBUTTON` | BUTTON n — mouse button status bit |
| `FPSVAR` | SVAR n = &5A00+n (address of a system variable) |
| `FPCHRS` | CHR$ n — 1-byte string in workspace |
| `FPBINS`/`FPHEXS` | BIN$ (8/16 digits, using BIN1DIG/BIN0DIG chars), HEX$ (2/4/6 digits by magnitude) |
| `MEMRYSP2` | MEM$(a TO b) part 2: copy the memory range to workspace as a string |
| [FPCONCAT](#fpconcat) | String + string: copy both into fresh workspace (error 42 past 64K−1) |
| [AMPERSAND](#ampersand) | `&hex` literal parser (up to 6 digits, 19-bit + sign forms) — evaluated at syntax time into the 5-byte form |
| `FPUSRS`/`FPUSR` | USR$/USR — trampoline to ROM0's CALLX |
| `FPPEEK`/`FPDPEEK` | PEEK/DPEEK through PDPSUBR's 0–512K addressing |
| `FPTRUSTR` | TRUNC$ — strip trailing spaces |
| `FPSTRS`/`FPCODE`/`FPLEN`/`FPUDG` | STR$ (via PFSTRS), CODE, LEN, UDG address |

### Details

#### FPVAL
The remarkable one: VAL copies its string to workspace with a CR appended,
runs **TOKDE** (the tokenizer) over it, then SCANSR twice — once with the run
bit forced off (a genuine syntax check, which also inserts 5-byte forms into
the workspace copy), once running to get the value. So VAL accepts anything
an expression can be, including keywords in text form. VAL$ is the string
flavour.

#### FPCONCAT
Fetches S2's descriptor, opens len1+len2 workspace bytes, FARLDIRs both
halves in, stacks the result descriptor.

#### AMPERSAND
Called from CALC5BY during syntax checking: accepts 1–6 hex digits
(letters case-insensitive), building a 19-bit-plus value; results ≤ &FFFF
become small integers, larger values full FP. Also accepts the `nnnnH`
suffix form.

---

## scrsel1.asm

| Entry point | Description |
|---|---|
| [SCREEN / JSCRN](#screen) | SCREEN n: make screen n current for output (display too if DISPLAY 0) |
| `SCRNTLK2` | Look up screen 1–16 in SCLIST → mode/page (Z if closed) |
| [OPSCRN / CLSCRN](#opscrn) | OPEN SCREEN n,m / OPEN #s,"letter" / OPEN n pages; CLOSE SCREEN n / CLOSE #s / CLOSE n pages — page allocation in ALLOCT |
| `CHLTCHK` | Map a channel displacement to its letter and class |
| [INTS](#ints) | The interrupt demultiplexer: line, frame, MIDI in/out, mouse/COMs — each via its vector |
| [FRAMINT](#framint) | Frame interrupt: palette flash (two palette tables swapped every SPEEDINK frames), line-interrupt table reload, FRAMES counter, keyboard scan, screen-off counter |
| [LINEINT](#lineint) | Line interrupt: walk LINICOLS entries `scan,palette-entry,colour1,colour2`, reprogramming the CLUT at exact scans |
| [KEYRD2 / KINTER / KEYSCAN…](#keyrd2) | Keyboard scanning into the 8-byte queue with rollover, repeat (REPDEL/REPPER), shift/symbol/control translation through KTAB |

### Details

#### SCREEN
Selects the mode/page pair from SCLIST into CUSCRNP (print/plot target) and,
if no explicit DISPLAY is active, also shows it. Print variables of the old
screen are saved into its second page (PVBUFF) and the new screen's set
loaded — each open screen keeps its own windows, positions and colours.

#### OPSCRN
`OPEN SCREEN n,m[,c]` allocates 2 pages (marked &40 in ALLOCT) and enters
mode/page into SCLIST — error 44 if the screen exists, 1 if no pages.
`OPEN #s;"x"` binds stream 4–15 to a channel letter via CLTAB. `OPEN n` / 
`OPEN TO n` reserve raw pages for the user (adjusting LASTPAGE). CLOSE
reverses each form; closing the displayed screen falls back to screen 1.

#### INTS
Reads the pending-interrupt bits saved by the RST &38 stub and dispatches in
priority order line → frame → MIDI-out → COMs → MIDI-in, each first offering
its vector (LINIV/FRAMIV/MOPV/COMSV/MIPV).

#### FRAMINT
Every 20 ms: reload the line-interrupt pointer to the LINICOLS table start
and program the first entry; every SPEEDINK frames swap PALFLAG and load the
other palette table (this is how FLASH colours work — the two 16-entry
tables at PALTAB differ only in flashing inks); increment FRAMES (3+2
bytes); call the mouse vector; scan the keyboard (KEYRD2); count down
SOFFCT for automatic screen-off.

#### LINEINT
LINICOLS entries are 4 bytes: scan line, palette index, colour A, colour B
(A/B by PALFLAG). The handler spins on STATPORT to hit the exact scan,
reprograms the CLUT entry, loads the next entry's scan into the line
interrupt register, and returns — up to 127 changes per frame.

#### KEYRD2
Full-travel scan of the 9 half-rows into a 72-bit map; two-key rollover with
the shift keys read separately; new keys translate through the three 69-byte
KTAB planes (plus the control-key table) and are queued in KBQB (8 deep,
head/tail in KBQP); repeats after REPDEL then every REPPER frames. LASTK and
FLAGS bit 5 present the queue head to the interpreter.

---

## scrsel2.asm

| Entry point | Description |
|---|---|
| [GOTO / GOSUB / GOTON](#goto) | GOTO/GOSUB n, and the `GOTO ON x;l1,l2,…` selector form |
| [GETTOKEN](#gettoken) | The keyword matcher used by the tokenizer (public vector &018A) |
| [MODPT2](#modpt2) | The MODE switch: set MODE/CUSCRNP/hardware, window geometry (MDSR), expansion tables, mode 2↔3 colour juggling, then CLS |
| `FATPIX` | FATPIX 0/1 — switch mode 2 pixel width, rescaling XCOORD and XRG |
| `WIDTH` (CSIZE) | CSIZE w,h — character cell size (6/8 wide, 6–32 high; ≥16 = double height) |
| `SUET`/`QUADBITS`/`DBBITS` | Build EXTAB: each 4-bit pattern doubled (mode 2) or quadrupled (mode 3) |
| [AUTO](#auto) | AUTO line,step (both optional): arm AUTOFLG/AUTOSTEP and re-enter the main loop via AULL |
| [SOUND](#sound) | SOUND reg,val;reg,val;… — batch writes to the sound chip (≤127 pairs) |
| [BOOT / BOOTEX](#boot) | BOOT: find/reuse a DOS page, read track 4 sector 1, verify the "BOOT" signature, jump to &8009 |

### Details

#### GOTO
GOSUB stacks a GOSUB frame (line number range-checked) before the shared
GOTO3 which sets NEWPPC/NSPPC=0. `ON x;` picks the x'th number from the
list (out-of-range falls through to the next statement).

#### GETTOKEN
Inputs: HL = keyword list −1, A = word count +1, DE = the candidate text
(copy). Scans the list (last letter of each word has bit 7 set), matching
case-insensitively; embedded spaces in list words ("GO TO", "DEF FN",
"END PROC", "LOOP IF"…) are optional in the input. After a full match the
next input character must not be a letter/underscore/`$` (via ALDU) unless
the word ends in `=`, `>` or `$` (so `<>`, `<=`, `>=`, `CHR$a` work).
Returns A = 1-based index of the matched word, Z if none.

#### MODPT2
Mode 0 gets 8-pixel-high cells (attribute alignment), modes 1–3 get 9. Mode
2 selects 64 or 85 columns by FL6OR8. Switching to/from mode 2 saves and
restores the mode 3 paper/lower-screen colours and converts between striped
and solid formats, doubling/halving X coordinates when the thin-pixel flag
changes.

#### AUTO
Defaults: line = EPPC+10, step 10. Stores step and EPPC=line−step, then each
pass of the main loop calls AULN (editor.asm) to pre-type the next number.

#### SOUND
Collects register/value pairs (registers 0–31) into INSTBUF, terminates with
&FF, then squirts them to ports &1FF/&FF.

#### BOOT
`BOOT 1` forces a re-boot; plain BOOT with DOS resident just issues the
auto-load hook. Otherwise: find a free (or previous DOS) page, spin up the
drive checking the index hole ("Missing disc"), step to track 4, read sector
1 to &8000 with retries, check bytes &8100+ spell "BOOT" ("No DOS"
otherwise), and jump to the DOS init at &8009.

---

## printfp.asm

| Entry point | Description |
|---|---|
| [PFSTRS](#pfstrs) | STR$/PRINT of the number on the FP stack: BC digits at (DE) in PRNBUFF, rounded to 8 significant digits, E-form when needed |
| [PRFPBUF](#prfpbuf) | Raw conversion: integer part by repeated decimal subtraction/BCD, fraction by repeated ×10 of the binary fraction |
| `DECDIGP`/`DECDIGN` | log10 bounds for a power of two (digits before point / zeros after) |
| `DECIMIZE`/`PRBCD` | Binary→BCD conversion of the integer part and BCD→ASCII output |
| [POFTEN](#poften) | Multiply the FP top by $ 10^{A} $ (A signed) — used by E-format input and output |

### Details

#### PFSTRS
Drives PRFPBUF then post-processes: round the 9th digit up (with carry
rippling and possible re-lengthening), decide E-format (magnitude ≥ 1E8 or
leading zeros beyond FRACLIM), place the decimal point, strip trailing
zeros, and emit `mantissa E±nn` when in E-form. FRACLIM (normally 6) allows
up to 4 leading fraction zeros before switching to E-form.

#### PRFPBUF
Splits the number at the binary point using the exponent; the integer part
is converted through a 5-byte BCD buffer (up to 10 digits), the fraction by
multiplying the remaining bits by 10 repeatedly, taking the carry-out digit
each time until 9 digits exist. Numbers ≥ 2^32 are pre-scaled by negative
powers of ten (recording EPOWER).

#### POFTEN
Squares 10 progressively (binary exponentiation over the bits of |A|),
multiplying or dividing the target as bits demand — also the engine behind
`1.23E-4` input scaling.

---

## tprint.asm

The output side of the token system, plus control codes. `PROM1` is where
channel K/S output lands (via PRMAIN in ROM0).

| Entry point | Description |
|---|---|
| [PROM1 / PRASCII](#prom1) | Main print: <&20 control codes, &20–&7F ASCII through CHARS, ≥&80 tokens/UDGs |
| `NLENTRY`/`PRNONWLN` | Position bookkeeping: line-full → recursive CR (with listing indent), then render via PATOUT |
| [PRGR80 / PRGR802](#prgr80) | Codes ≥&80: UDGs when in quotes/INPUT (or &80–&84 always); otherwise keyword expansion via the four sub-lists |
| [POFN / PSTFF2](#pofn) | &FF prefix: capture the next byte, then print the named function with correct spacing rules |
| [POMSR / POMSR3 / MVWORDLP](#pomsr) | Message/keyword extraction into MSGBUFF: walks bit-7-terminated lists, expanding compression codes 0–31 recursively |
| [POUDG / PUDGS](#poudg) | Block graphics (&80–&8F computed from the code's nibbles) and UDG/foreign characters via UDG/HUDG pointers |
| [PRCRLCDS / CCPTB](#prcrlcds) | Control codes 6–23: comma-tab, cursor moves, delete, ENTER, colour codes (collect parameters by channel redirection), AT/TAB |
| `PRENTER`/`LPRENT` | CR handling with window scroll; printer CR+optional LF |
| [SCRLSCR / SCRLS](#scrlscr) | "scroll?" prompting, autolist abort, lower-screen scroll stealing rows from the upper screen |
| `DBCHAR` | Double each scan of a character matrix for double-height printing |
| `EROC2` | Erase the old `>` cursor (listing support) |
| `WTBRK` | Prompt via a utility message and wait for a key |

### Details

#### PROM1
ASCII: pattern address = (CHARS)+8×code; FLAGS bit 0 tracks "last char was a
space" for keyword spacing. All rendering funnels through NLENTRY (position/
line-full logic) then the PATOUT vector (normally ENDOUTP → per-mode
renderer in endprint.asm; DMPFG discards output for measuring).

#### PRGR80
The INQUFG (in-quotes) and FLAGX (INPUT) flags force UDG printing so program
*strings* list as characters while program *code* lists as keywords —
resolving the &85–&FE overlap between tokens and UDGs by context. PRGR802 is
also called by the editor's channel R to expand tokens into the edit buffer.

#### POFN
Printing an &FF redirects the channel to capture the following code byte,
then selects the token sub-list (immediate/FPC/binary) and spacing: MOD–AND
get spaces both sides; FN and BIN a trailing space only; `<>`, `<=`, `>=`
none; keywords ending in a letter or `$` get a trailing space; a leading
space is added unless the previous character was one.

#### POMSR
The list walker shared by keywords, error messages and utility messages:
entry N is found by counting bit-7 bytes; bytes &00–&1F recurse into
COMPLIST (the compression fragments); the expansion accumulates in MSGBUFF
with BC=length.

#### POUDG
Codes &80–&8F with BGFLG=0 are synthesized block graphics (each nibble
quadrupled into the cell); otherwise codes &80–&A8 index from (UDG) and
higher codes from (HUDG).

#### PRCRLCDS
Control codes with operands (16–23) redirect the channel output address so
the next 1–2 "printed" bytes are collected as parameters (TVDATA), then
CCRP2 applies them: INK…OVER via PRCOITEM, AT with lower-screen growth
(scrolling the upper screen when they collide), TAB modulo the window width.

#### SCRLSCR
On window-bottom CR: during AUTOLIST, hitting the bottom aborts the listing
via LISTSP. Otherwise, when SCRCT expires, "scroll?" is prompted on the
lower screen; N/space/BREAK raises error 14, anything else resets the count
and scrolls. Lower-screen scrolls that would collide with the upper print
position scroll the upper window too.

---

## tapemn.asm

| Entry point | Description |
|---|---|
| [SLMVC](#slmvc) | Common parser for SAVE/LOAD/MERGE/VERIFY: OVER flag, device letter override, filename, then the type qualifiers |
| `HDR5`/`HDR6`/`SVDS1` | Type qualifiers: SCREEN$ (mode+palette+line table), DATA a()/a$() (arrays), CODE start,len,exec / LINE n (auto-run) |
| [LVMMAIN / LKTH / LDFL](#lvmmain) | LOAD/VERIFY/MERGE execution: fetch headers until the name matches, then dispatch by type |
| `CDSCVE` | Verify any file / load CODE (with relative-page address fix-up and optional execute) |
| [LDPRDT / LDPROG](#ldprdt) | Load a program or array file: open room, load, then rebuild NVARS/NUMEND/SAVARS pointers from the header's three lengths, run auto-run line if present |
| `LDSCRN` | Load/verify SCREEN$ into an open (or newly opened) screen, restoring palette and line-interrupt table |
| `LDVDBLK`/`LDDBLK`/`LDVD2` | Load or verify one data block (tape via LDBLK, net, or DOS hook by device) |
| `SLVMC` | SAVE execution: write header then data block(s) |

### Details

#### SLMVC
Builds the 80-byte request header at HDR (layout documented at the top of
the file: type 16–20, 10-char name, flags, per-type info at offset 16,
start/length/execute triples at offset 31). `SAVE OVER` sets OVERF; a
leading device string ("T"/"D1:"/"N2:" style via PSLD/SLDEV) selects
tape/disc/net; DOS devices divert through hook codes.

#### LVMMAIN
For tape: LDBLK reads each header, the name is compared (null name matches
anything, and names are echoed unless suppressed), then the type routines
check/allocate memory. Program loads wipe the current program first
(including CLEAR-like variable reset); "Loading error" (19) and type
mismatches guard each stage. DOS entry points LKTH/LDFL let the DOS reuse
the tail of the flow after loading headers/files itself.

#### LDPRDT
Programs: room is checked against the header length, the block loaded over
the program area, then NVARS/NUMEND/SAVARS are reconstructed by adding the
three stored lengths to PROG, remaining pointers reset, RESTORE 0 done, and
the auto-run line (header offset 37: 0,lo,hi) GOTOs if present. Arrays:
any existing array of the stored name is deleted and the new record spliced
into SAVARS.

---

## tapex.asm

| Entry point | Description |
|---|---|
| [SABLK / SABYTES](#sablk) | Save a block of CDE bytes from HL to tape: leader (speed-compensated cycle count), sync, type byte, data with border stripes, parity |
| [LDBLK / LDBYTES](#ldblk) | Load/verify a tape block: leader detection, sync hunt, speed measurement (self-adjusting to the recorded TSPEED), bit slicing, parity check |
| [EDGEC](#edge2) | (tadjm.asm's EDGE2 partner) — double-edge timing used by LDBLK |
| `WNF`/`WNH`/`NIXJ` | Net save/load of a block with parity (station addressing via OTHER) |
| `NMOUT`/`NMIN` | Single byte out/in on the net/MIDI port with timing |
| `CKNET` | Wait for the net to fall quiet before transmitting |

### Details

#### SABLK
The SAM format is ZX-like but speed-programmable: PSLD's number sets the
half-cycle period; the leader cycle count is scaled so leaders last roughly
constant time at any speed. Data bytes stream from paged memory via the
same page-stepping used by FARLDIR. Type byte 01=header, FF=data.

#### LDBLK
Measures the leader to calibrate thresholds (accepting a wide speed range,
including ZX-recorded 17-byte headers for LOAD compatibility), hunts the
sync pulse pair, then slices bits by comparing pulse lengths against the
measured midpoint. CY on success; BREAK and mis-timing abort with NC
("Loading error" upstream).

---

## using.asm

Despite the name, mostly memory-management and search plumbing (the USING$
function itself was dropped — its token slot is unused).

| Entry point | Description |
|---|---|
| [XOINTERS](#xointers) | The pointer-adjustment engine behind MAKEROOM/RECLAIM: shift the 14 (page,addr) system variables at/above the change point, plus FOR records and BASIC-stack frames |
| `SMBW`/`SMBS` | Point MEM at scratch (workspace-based) calculator memories |
| `SADJ` | Adjust BASIC-stack frame addresses after a move |
| `SNDA2` | Send a byte to the printer port (with BREAK polling and busy wait) |
| [HEAPROOM](#heaproom) | Reserve/release BC bytes of heap between HPST and the BASIC stack (public vector &0106) |
| [IMINSTR / INARRAYEN / MINSR](#iminstr) | INSTR([start,]s$,t$) — the search driver over paged strings using R0INST |
| [IMLENGTH](#imlength) | LENGTH(n,name) — element length/count/dims of a variable without evaluating it |
| [IMSTRINGS](#imstrings) | STRING$(n,a$) — n repetitions of a$ built in workspace |
| `CIFILSR` | CIRCLE/FILL coordinate unstacker (thin-pixel offset handling into TEMPW1) |
| `CRBBFN`/[CRTBF / CRTBFI](#crtbf) | Build runs of RLD/RRD (pixel roll) or LDI/LDD (byte move) opcodes in CDBUFF for the roll/scroll/GRAB engines |
| [DRTCRV / DRCURVE](#drtcrv) | DRAW x,y,angle — approximate the arc with chord segments computed on the FP stack |

### Details

#### XOINTERS
Called with the change location and size: every pointer sysvar from SAVARS
to PRPTR that points at or above the location is adjusted by the size (up
for MAKEROOM, down for RECLAIM), page bytes rippling as addresses cross 16K
boundaries; then every FOR-variable's looping address and every BASIC-stack
frame gets the same treatment (AFLPS/SADJ/ASSV in tadjm.asm do the walking).
It also computes PAGCOUNT/MODCOUNT — the number of bytes between the change
point and WKEND — for the FARLDIR/FARLDDR that follows.

#### HEAPROOM
The heap grows up from HPST toward the down-growing BASIC stack; +BC
reserves, −BC releases (over-release just empties it). NC = insufficient
room with HL = shortfall.

#### IMINSTR
Optional start position (clamped), target copied to INSTBUF (1–255 bytes),
then R0INST (misc2.asm) scans the search string across page boundaries in
16K chunks. Returns position or 0.

#### IMLENGTH
LENGTH(0,a) = bytes per element, LENGTH(1,a()) = elements/dims etc.: looks
up the variable, then indexes its header without touching data — also
handles simple strings (length) and numbers (5).

#### IMSTRINGS
Multiplies out n×len (error 42 past 65535), opens workspace, and LDIRs the
source repeatedly.

#### CRTBF
Writes A copies of a 2-byte opcode (`ED A0` LDI etc., or RLD/RRD for pixel
shifts) into CDBUFF followed by RET — the ROM generates straight-line code
because a run of LDIs beats LDIR ~16%, and RLD runs have no loop form at
all. CDBUFF is called with (HL/DE/BC) set by the roll/scroll/GRAB/PUT/CLS
engines.

#### DRTCRV
For DRAW x,y,a: computes the chord count and per-segment displacement from
the turn angle (in calculator code, memories 0–5), then issues that many
short DRAWs, accumulating rounding so the curve closes on the endpoint.

---

## misc31.asm

| Entry point | Description |
|---|---|
| [CALLER / CALLX path](#caller) | CALL addr[,params]: evaluate up to 15 parameters (numbers → FP stack order, strings → descriptors), then far-call the address |
| [SETUPVARS](#setupvars) | Create/refresh the ERROR, STAT and LINO variables before an ON ERROR handler runs |
| [MNINIT](#mninit) | Cold start: RAM sizing (256/512K detection into PRAMTP), ALLOCT init, system variables from CHIT/MAIT, screen 1 open, charset unpack, DEF KEY defaults, copyright banner via error &50 |
| [NEW / NEW2](#new) | NEW: close all screens except 1, free pages, reset RAMTOP and re-init (keeping FISCRNP…PRAMTP) |
| `RBOW…` | The power-on "rainbow" line-interrupt colour table |
| [UPACK](#upack) | Unpack the 5-bit-compressed character set to 8-byte matrices at CHARSVAL (plus the 13 descender patches) |
| `CLSHS`/`CLSHS2` | CLS # — full window/stream/colour reset |
| [COLOUR (PALETTE)](#colour-palette) | PALETTE i,c or i,b,c, optionally LINE l — set palette memories, flashing pairs, and the per-scan LINICOLS table |
| `FLITE`/`FLITD` | Find the line-interrupt table end/entry |
| `PALSW` | Save/restore palette entries 0–3 across mode 2 switches |

### Details

#### CALLER
Parameters after the address: numbers are pushed on the FP stack (count in
TEMPB3, passed in A to the called code), strings passed as stacked
descriptors. The call itself goes through PDPSUBR paging (0–512K address)
with IX saved; the routine returns to NEXTSTAT.

#### SETUPVARS
Before entering an ON ERROR handler, three numeric variables are created or
updated: `error` (ERRNR), `stat` (SUBPPC), `lino` (PPC) — so handlers can
inspect the failure.

#### MNINIT
Sizes RAM by writing markers at each page (detecting 256K mirrors), builds
ALLOCT (pages marked free/used/non-existent), initialises the system page,
streams, channels (from CHANTAB), windows, palette (INITCOLS + rainbow
LINICOLS), unpacks the charset, installs default DEF KEYs (DKSRC: F0=LIST,
F4=RUN, F9=BOOT…), then reports via the MGT banner (error &50) into the
main loop.

#### NEW
Preserves only FISCRNP…PRAMTP (screen 1's page, allocation state, RAMTOP,
memory size), frees all other BASIC-owned pages and screens, and re-runs
most of MNINIT.

#### UPACK
Each character is 7 five-bit slices packed across bytes; unpacking centres
the 6 significant pixels with 2/1 blank columns and zeroes the 8th scan,
then a patch list (U8TAB) fixes the 13 characters that need the bottom scan
(descenders, comma, semicolon…).

#### COLOUR (PALETTE)
`PALETTE` alone clears LINICOLS and re-seeds both palette tables from
INITCOLS. With arguments it writes palette memory i (0–15) with colour c
(0–127) in *both* tables, or two colours b,c (one per table → flashing).
With `LINE l` the change goes into the LINICOLS table instead (4-byte
entries kept sorted by scan; up to 127; error 25 when full), taking effect
mid-frame via the line interrupt.

---

## misc32.asm

| Entry point | Description |
|---|---|
| [BEEP / BEEPP2](#beep) | BEEP duration,pitch: convert pitch (semitones, −60…69, fractions allowed) to period via octave halving, then the timed speaker loop |
| `ZAP`/`POW`/`BOOM`/`ZOOM` | Canned sound effects driving the sound chip / speaker |
| `BGRAPHICS` | BLOCKS n — block graphics on/off (BGFLG) |
| `KEY` | KEY position,code — repoke the 276-byte key map |
| `SLDEVICE` | DEVICE letter[speed/number] — set the default save/load device (PSLD) |
| [PAUSE](#pause) | PAUSE [n] — wait n frames (0 = forever) or until a key |
| [PRCOITEM2](#prcoitem2) | Execute a colour item: INK/PAPER/FLASH/BRIGHT/INVERSE/OVER parameter into the temporary variables, per-mode (attribute bits vs mode 2/3 bytes) |
| [BORDER / SETBORD](#border) | BORDER n: border port value, BORDCR, mode 2/3 lower-screen colours |
| `CVLSP`/`M3TO2` | Convert mode 3 colour bytes to non-striped mode 2 equivalents |
| [WINDOW](#window) | WINDOW [lhs,rhs,top,bot] — set (or reset) the upper window, clamped to WINDMAX |
| `OUT`/`STOP`/`RANDOMIZE` | OUT port,val; STOP (error 16); RANDOMIZE [n] (seed from FRAMES if 0) |

### Details

#### BEEP
Pitch $ p $: the octave $ \lfloor p/12 \rfloor $ offsets a base-frequency
table lookup; the fractional semitone interpolates. Produces DE=cycles−1, HL=half-period in
8T units for BEEPP2, which toggles bit 4 of the KEYPORT with interrupts off
(also the public vector &016F).

#### PAUSE
Flushes the keyboard, HALTs per frame decrementing the count, exits on
key/BREAK.

#### PRCOITEM2
The run-time half of INK/PAPER/…: validates ranges per mode (mode 3 inks
0–15 map into paper/ink nibble pairs; INK 8/9 and PAPER 9 set the PFLAGT
match/contrast bits; mode 2 uses solid bytes), updating ATTRT/MASKT/PFLAGT
or M23PAPT/M23INKT. OVER 0–3 also sets GOVERT for PUT/plot.

#### BORDER
Sets BORDCOL (hardware), BORDCR (modes 0/1 lower screen attribute) and
M23LSC (modes 2/3 lower screen colours), converting for mode 2 if active.

#### WINDOW
No arguments restores the full-screen window; otherwise validates the
rectangle against WINDMAX and stores UW*: subsequent PRINT/CLS/scroll are
confined to it.

---

## scrfn.asm

| Entry point | Description |
|---|---|
| [COPY / JTCOPY / JGCOPY](#copy) | COPY (text screen dump) and COPY CHR$ (graphics dump) — both via the DMPV vector (no printer driver in ROM) |
| [IMSCREENS / IMSCSR](#imscreens) | SCREEN$(l,c): capture the character cell, normalise it, and match against the character set and UDGs |
| `SCREENSR` | The matcher: quick scan on bytes 3/4, full 8-byte check on candidates |
| [LSTR1 / LSTLNL](#lstr1) | LIST part 2: OUTLINE each line until past LAST (or the autolist window fills) |
| [OUTLINE](#outline) | Print one program line: number (5-column), `>` cursor, indent, then detokenize the text — the reference "tokens back to text" routine |
| `STENTS` | Scroll the LPT line-number table with the window |
| [SPACES / INCSPCS / DECSPCS](#spaces) | Pretty-listing indent engine driven by the structural tokens (DO/FOR/IF/DEF PROC increase, LOOP/NEXT/END… decrease) |
| [EDPTR2](#edptr2) | Print the edit/INPUT line to the lower screen, cursor placement, blanking of leftovers |
| `CUOPP`/`OPCURSOR`/`OPCUR2` | Cursor rendering: match KCUR against the line pointer during output; inverse-video cursor glyph via KURCHAR |
| `PRLCU`/`PRFLQUERY`/`PRINVERT` | The `>` line cursor, the flashing `?` syntax-error marker, inverse printing |
| [PRAREG / PRNUMB1 / PRNUMB2](#prareg) | Print integers: 1–3 digits (A), plain (BC), or padded to 5 with leading spaces (line numbers) |

### Details

#### COPY
Both flavours only check syntax and jump through DMPV — printer dump code is
expected to be installed (e.g. by a DOS or utility) at that vector.

#### IMSCREENS
Reads the cell at (l,c) — via CHARCOMP for modes 2/3 (with 6-pixel column
rotation), direct copy for modes 0/1 (with inverse normalisation by the
top-left pixel) — then SCREENSR compares against the 96 ROM characters and
41 UDG codes, returning the character as a 1-byte string or "" if no match.

#### LSTR1
The listing loop: after each OUTLINE prints a CR, reads the next line number
(with ROM1 paged out) and stops past LAST; autolisting additionally stops
when the window is full.

#### OUTLINE
The detokenizer — a program converting the stored form back to text follows
exactly this: print the big-endian line number right-aligned to 5 columns;
mark the LPT row; print `>` for EPPC or a space; consult LISTFLG/SPACES for
indent; then loop over the text with `RDCN` (read char, *skip &0E+5 forms
invisibly*), tracking INQUFG across &22 quotes so ":" inside strings isn't
treated as a separator; ":" outside strings (pretty mode) becomes
CR+6-space indent; every other byte goes to RST &10 where tprint.asm
expands tokens (&85–&FE and &FF-pairs) to keywords and prints ASCII as-is.
The XPTR position prints a flashing `?`. Ends at the CR.

#### SPACES
Maintains NXTSPCS/CURSPCS (+THEN variants): DO, long IF, DEF PROC and FOR
add LISTFLG columns of indent from the next statement; LOOP, END PROC,
END IF and NEXT remove it from the current one; EXIT IF/LOOP IF/long ELSE
outdent just their own statement; short IF/ON indent only to end-of-line.

#### EDPTR2
The lower-screen editor display: prints the line via OUTLN25 (no line
number), tracks where the cursor lands (CUOPP swaps in when the screen
position matches KPOS), blanks any residue of the previous, longer
rendering, and preserves the "old position" so re-prints overlay exactly.

#### PRAREG
`PRNUMB2` (listings) pads to 5 with spaces then digits via repeated
subtraction of 10000/1000/100/10; `PRNUMB1` suppresses padding; numbers
≥ &FF00 print as 0 (the edit line's PPC).

---

## text.asm

Pure data:

| Region | Description |
|---|---|
| `UMVAL` | Utility messages 0–8 (banner, "scroll?", "Start tape…", "Basic:", array names) |
| `ERRMVAL` | Error messages 0–55, compressed with COMPLIST codes |
| `COMPLIST` | The 32 compression fragments (see [constants.md](constants.md#textasm)) |
| [KEYWTAB](#keywtab) | The keyword table: 196 words — immediate functions, FPC functions, binary operators, qualifiers &85–&8F, commands &90–&FE, and the trailing INK entry |
| `DKSRC` | Default DEF KEY definitions (F0=LIST, F1=RENUM:, F2=PRINT:, F3=MODE:, F4=RUN, F5=CONTINUE, F6=CLS #, F7/F8=LOAD ""/LOAD "" CODE, F9=BOOT) |
| `CHIT`/`MAIT` | System-variable initialisation blocks (18 + 26 bytes) |
| `CHANTAB` | Initial channel records: K, S, R (editor insert), P, $ (stream 16), B (printer byte) |
| `KSRC`/`CKTAB` | The 3-plane key map (normal/caps/symbol) and control-key table |
| `INITCOLS` | Initial palette (16 colours + 4-colour-mode set) |
| [CMDADT](#cmdadt) | The command address table: one word per token &90–&F6 (see [tokenized-program-format.md](tokenized-program-format.md)) |
| `U8TAB`/`SUBTAB` | Bottom-scan patch table for the charset; powers-of-ten for PRNUMB |
| `CHARSRC` | The 5-bit compressed character set (Simon N. Goodwin), ~600 bytes |

### Details

#### KEYWTAB
Words are stored with the last letter's bit 7 set; embedded spaces are
optional-match ("GO TO"). Order defines token values: match index 1–&49 →
function codes &3B–&83 (stored as &FF + code), &4A–&C4 → tokens &85–&FE
(index + &3B). The final entry "INK" maps to &FF and is transformed to the
PEN token (&A1) by the tokenizer. Unused slots hold "-".

#### CMDADT
Indexed by (token − &90)×2, base published in the CMDADDRT sysvar. Bit 15 of
each address doubles as "routine is in ROM1" (addresses ≥ &8000 assemble in
the &C000-based ROM1, so the paging decision falls out of the address
itself). Unimplemented commands (DIR, FORMAT, ERASE, MOVE, RENAME, PROTECT,
HIDE…) point at NONSENSE and are expected to be intercepted by a DOS via
the CMDV vector.

---

## romtest.asm

Not part of the ROM. A small utility assembled separately: copies the live
ROM0/ROM1 and the freshly assembled image into paged RAM, compares them
byte-for-byte (with the volatile areas patched out), and prints the first
mismatch address in hex — used to verify that this source assembles to the
official v3.0 image.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
