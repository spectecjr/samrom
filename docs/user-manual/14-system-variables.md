# 14. System Variables

← [Memory and machine code](13-memory-and-machine-code.md) · [Contents](README.md) · [Next: Expert techniques →](15-expert-techniques.md)

---

The interpreter's working storage is a block of memory you can read and write
like any other. Changing the right byte lets you alter behaviour that has no
command of its own — the cursor character, the printer margin, the wildcard
`INSTR` matches, whether BREAK works, where the character set lives.

## 14.1 `SVAR`

```
SVAR n
```

`SVAR` returns the **address** of system variable *n* — it does not read it.
The base is 23040, so `SVAR n` is simply 23040 + *n*, and you almost always
write:

```basic
PRINT PEEK SVAR 47                : REM read the comma-tab setting
POKE  SVAR 47, 1                  : REM write it
PRINT DPEEK SVAR &36              : REM read a two-byte variable
DPOKE SVAR &36, &0808             : REM write one
```

Using `SVAR` rather than a literal address documents your intent and survives
any future change of base.

The main system variable block runs from offset 0 to offset 511. The
ZX-Spectrum-compatible block begins at offset 512 (absolute address 23552),
so `SVAR 512` and 23552 are the same place. By convention the second block is
referred to by absolute address, and this chapter follows that.

## 14.2 A caution

Some of these are safe to change, some are read-only in practice, and some
will crash the machine instantly. Each table below marks the useful ones.

| Marking | Meaning |
|---|---|
| ✔ | Safe and useful to change |
| ○ | Useful to read; changing it is for experts |
| ✘ | Interpreter state — do not write |

Two-byte variables are shown as (2), longer ones with their length.

---

## 14.3 Editor and device configuration

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &00 | 23040 | `LNCUR` | ✔ | Character used for the current-line cursor in listings (normally `>`) |
| &01 | 23041 | `KURCHAR` (2) | ✔ | Edit cursor characters: lower case, then upper case |
| &03 | 23043 | `BIN1DIG` | ✔ | Character `BIN$` emits for a 1 bit (normally `1`) |
| &04 | 23044 | `BIN0DIG` | ✔ | Character `BIN$` emits for a 0 bit (normally `0`) |
| &05 | 23045 | `INSTHASH` | ✔ | `INSTR` wildcard character, matching anything (normally `#`) |
| &06 | 23046 | `PSLD` (2) | ✔ | Permanent save/load device: letter, then number (`DEVICE` sets it) |
| &08 | 23048 | `SPEEDINK` | ✔ | Frames between `FLASH` palette swaps |
| &09 | 23049 | `LINIPTR` (2) | ✘ | Next entry in the line-interrupt colour table |
| &0B | 23051 | `XCMDP` (3) | ○ | Page/address of the first external command list, or &FF for none. Reserved by convention — **no ROM code reads it** |
| &0E | 23054 | `PRRHS` | ✔ | Printer right margin (normally 79) |
| &0F | 23055 | `AFTERCR` | ✔ | Byte sent after a printer CR: 10 for auto line feed, 0 for none |
| &10 | 23056 | `LPTPRT1` (2) | ✔ | Printer control port, then the strobe value |
| &12–&2E | 23058 | *(reserved)* | ○ | Free for a `DUMP` driver's own use |
| &2F | 23087 | `TABVAR` | ✔ | `PRINT` comma tab width: 0 = 16 columns, non-zero = 8 |
| &30 | 23088 | `M23LSC` (2) | ○ | Lower-screen paper/ink bytes for `MODE 3` and `MODE 4` |
| &32 | 23090 | `SOFE` | ✔ | Screen blanking: 0 permits the automatic blank timer, non-zero prevents it |
| &33 | 23091 | `TPROMPTS` | ✔ | Bit 0 suppresses file names during `LOAD`, bit 1 prompts during `SAVE` |

## 14.4 Screen and print state

Everything from `BGFLG` to `SPOSNL` travels with the screen: switching
screens saves this block into the outgoing screen's own page and reloads it
from the incoming one. That is why each screen keeps its own windows, cursor
position, colours and mode.

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &34 | 23092 | `BGFLG` | ✔ | Block graphics: 0 synthesises block shapes for codes 128–143, non-zero uses UDGs (`BLOCKS`) |
| &35 | 23093 | `FL6OR8` | ○ | Character width in `MODE 3`: 0 = 6-pixel cells, non-zero = 8 |
| &36 | 23094 | `CSIZE` (2) | ○ | Cell height (low byte, 6–32) then width (high byte, 6 or 8) |
| &38 | 23096 | `UWRHS` | ○ | Upper window right column |
| &39 | 23097 | `UWLHS` | ○ | Upper window left column |
| &3A | 23098 | `UWTOP` | ○ | Upper window top row |
| &3B | 23099 | `UWBOT` | ○ | Upper window bottom row |
| &3C | 23100 | `LWRHS` | ○ | Lower window right column |
| &3D | 23101 | `LWLHS` | ○ | Lower window left column |
| &3E | 23102 | `LWTOP` | ○ | Lower window top row (rises as `INPUT` prompts grow) |
| &3F | 23103 | `LWBOT` | ○ | Lower window bottom row |
| &40 | 23104 | `MODE` | ○ | Current **internal** mode 0–3 (user `MODE` 1–4) |
| &41 | 23105 | `YCOORD` | ○ | Graphics Y position, 0–191, **0 at the top** |
| &42 | 23106 | `XCOORD` (2) | ○ | Graphics X position, 0–255 or 0–511 |
| &44 | 23108 | `THFATP` | ○ | Permanent `FATPIX`: 0 = thin, non-zero = fat |
| &45 | 23109 | `ATTRP` | ✔ | Permanent attribute byte for modes 1 and 2 |
| &46 | 23110 | `MASKP` | ✔ | Permanent attribute mask (set bits come from the existing screen) |
| &47 | 23111 | `PFLAGP` | ✔ | Permanent print flags: bit 4 = `PAPER 17`, bit 6 = `INK 17` |
| &48 | 23112 | `M23PAPP` | ✔ | Permanent paper byte for modes 3 and 4 |
| &49 | 23113 | `M23INKP` | ✔ | Permanent ink byte for modes 3 and 4 |
| &4A | 23114 | `OVERP` | ✔ | Permanent text `OVER`, 0 or 1 |
| &4B | 23115 | `INVERP` | ✔ | Permanent `INVERSE` as a mask: 0 normal, 255 inverse |
| &4C | 23116 | `GOVERP` | ✔ | Permanent graphics `OVER` 0–3 |
| &4D | 23117 | `THFATT` | ○ | Working copy of `THFATP` |
| &4E | 23118 | `ATTRT` | ○ | Working attribute |
| &4F | 23119 | `MASKT` | ○ | Working attribute mask |
| &50 | 23120 | `PFLAGT` | ○ | Working print flags |
| &51 | 23121 | `M23PAPT` | ○ | Working mode 3/4 paper |
| &52 | 23122 | `M23INKT` | ○ | Working mode 3/4 ink |
| &53 | 23123 | `OVERT` | ○ | Working `OVER` |
| &54 | 23124 | `INVERT` | ○ | Working `INVERSE` mask |
| &55 | 23125 | `GOVERT` | ○ | Working graphics `OVER` |
| &56 | 23126 | `WINDRHS` | ○ | Current window right column |
| &57 | 23127 | `WINDLHS` | ○ | Current window left column |
| &58 | 23128 | `WINDTOP` | ○ | Current window top row |
| &59 | 23129 | `WINDBOT` | ○ | Current window bottom row |
| &5A | 23130 | `WINDMAX` (2) | ○ | Limits `WINDOW` validates against: lowest row, then rightmost column |
| &5C | 23132 | `ORGOFF` | ○ | Distance of the graphics origin above the screen bottom, in scan lines |
| &5D | 23133 | `LSOFF` | ○ | Spare scan lines between the upper and lower screens |
| &6C | 23148 | `SPOSNU` (2) | ○ | Upper screen print position: column, then row |
| &6E | 23150 | `SPOSNL` (2) | ○ | Lower screen print position |

Offsets &5E–&6B (23134–23147) are spare.

## 14.5 Interpreter state

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &70 | 23152 | `PRPOSN` (2) | ○ | Printer column |
| &72 | 23154 | `OPCHAR` | ✘ | Character currently being output |
| &73 | 23155 | `DEVICE` | ○ | Output device: 0 upper screen, 1 lower screen, 2 printer |
| &74 | 23156 | `CLET` | ○ | Letter of the current channel |
| &75 | 23157 | `IFTYPE` | ✘ | Whether the last `IF` on this line was long or short |
| &76 | 23158 | `REFFLG` | ✘ | `REF` binding state; also flags that a line uses `FN` |
| &77 | 23159 | `CURDISP` | ○ | Screen selected by `DISPLAY`, or 0 to follow the current screen |
| &78 | 23160 | `CUSCRNP` | ○ | Page and mode bits of the screen being drawn on |
| &79 | 23161 | `CURP` | ✘ | Saved `HMPR` value |
| &7A | 23162 | `CLRP` | ✘ | Saved `LMPR` value |
| &7B | 23163 | `CSA` (2) | ✘ | Address of the statement currently executing |
| &7D | 23165 | `FIRST` (2) | ✘ | Low end of a line range (`LIST`/`DELETE`) |
| &7F | 23167 | `LAST` (2) | ✘ | High end of a line range |

## 14.6 Memory area pointers

These fourteen three-byte pointers delimit the movable BASIC area. Each is a
page byte followed by a 16-bit address normalised into the 32768–49151
window. **Never write to them** — but reading them tells you exactly how
memory is laid out.

Regions run, low to high: program → numeric variables → gap → strings and
arrays → edit line → workspace → free → `RAMTOP`.

| Offset | Address | Name | Points at |
|---|---|---|---|
| &81 | 23169 | `SAVARSP` / `SAVARS` | Start of the string and array area |
| &84 | 23172 | `NUMENDP` / `NUMEND` | End of the numeric variables |
| &87 | 23175 | `NVARSP` / `NVARS` | Start of the numeric variables (= end of the program) |
| &8A | 23178 | `DATADDP` / `DATADD` | The `READ` position within the current `DATA` statement |
| &8D | 23181 | `WKENDP` / `WKEND` | End of workspace — the top of everything allocated |
| &90 | 23184 | `WORKSPP` / `WORKSP` | Start of workspace |
| &93 | 23187 | `ELINEP` / `ELINE` | Start of the line being typed or edited |
| &96 | 23190 | `CHADP` / `CHAD` | Next character to be interpreted |
| &99 | 23193 | `KCURP` / `KCUR` | Position of the edit cursor |
| &9C | 23196 | `NXTLINEP` / `NXTLINE` | The line following the one being executed |
| &9F | 23199 | `PROGP` / `PROG` | Start of the BASIC program |
| &A2 | 23202 | `XPTRP` / `XPTR` | Where the flashing `?` goes after a syntax error |
| &A5 | 23205 | `DESTP` / `DEST` | Where the value being assigned should be stored |
| &A8 | 23208 | `PRPTRP` / `PRPTR` | Position in a `PROC` call's argument list |
| &AB | 23211 | `DPPTRP` / `DPPTR` | Position in a `DEF PROC` parameter list |
| &AE | 23214 | `CLAPG` / `CLA` | Start of the line being executed |

In each pair, the first byte is the page and the following two are the
address, so `PEEK SVAR &9F` gives the program's page and `DPEEK SVAR &A0`
its address.

## 14.7 Flags and scratch

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &B1 | 23217 | `DFTFB` | ✘ | Zero if the numeric just found held "minus zero" |
| &B2 | 23218 | `STRNO` | ○ | Number of the stream last selected |
| &B3 | 23219 | `LDCO` | ○ | Page offset applied when loading ZX-format code |
| &B5 | 23221 | `OPSTORE` (2) | ✘ | Saved channel output address |
| &B7 | 23223 | `DMPFG` | ✔ | Non-zero **discards all output** — used to measure a line's height |
| &B8 | 23224 | `LISTFLG` | ✔ | `LIST FORMAT` setting 0–2 |
| &B9 | 23225 | `LSTFT` | ✘ | Copy of `LISTFLG` for channel R during `EDIT` |
| &BA | 23226 | `INQUFG` | ○ | In-quotes flag: bit 0 makes token bytes print as UDGs |
| &BB | 23227 | `SPROMPT` | ✔ | Non-zero suppresses the `scroll?` prompt (`SCROLL CLEAR`) |
| &BC | 23228 | `OLDSPCS` | ✘ | Indent state of the previously listed line |
| &BD | 23229 | `INDOPFG` | ○ | Non-zero enables indented output |
| &BE | 23230 | `NXTSPCS` | ✘ | Indent columns for the next statement |
| &BF | 23231 | `CURSPCS` | ✘ | Indent columns for the current statement |
| &C0 | 23232 | `NXTHSPCS` | ✘ | Extra indent after `THEN`, next statement |
| &C1 | 23233 | `CURTHSPCS` | ✘ | Extra indent after `THEN`, current statement |
| &C2 | 23234 | `KPOS` (2) | ✘ | Where the edit cursor was last drawn |
| &C4 | 23236 | `SOFFCT` | ○ | Frames remaining before the screen blanks |
| &C5 | 23237 | `SOFLG` | ○ | Non-zero once the screen has blanked |
| &C6 | 23238 | `SPEEDIC` | ✘ | Frames until the next `FLASH` palette swap |
| &C7 | 23239 | `PALFLAG` | ✘ | Bit 0 selects which of the two palette tables is loaded |
| &C8 | 23240 | `TEMPW1` (2) | ✘ | Scratch |
| &CA | 23242 | `TEMPW2` (2) | ✘ | Scratch |
| &CC | 23244 | `TEMPW3` (2) | ✘ | Scratch |
| &CE | 23246 | `TEMPB1` | ✘ | Scratch |
| &CF | 23247 | `TEMPB2` | ✘ | Scratch |
| &D0 | 23248 | `TEMPB3` | ✘ | Scratch; carries the `CALL` parameter count and the `FILL` mode |
| &D1 | 23249 | `LASTSTAT` | ○ | The interrupt status latched by the last interrupt |
| &D2 | 23250 | `SPSTORE` (2) | ✘ | Stack pointer saved across an interrupt |
| &D5 | 23253 | `JVSP` (2) | ✘ | Stack pointer saved by `JSVIN` |
| &D7 | 23255 | `NMISP` (2) | ✘ | Stack pointer saved by the NMI handler |
| &D9 | 23257 | `NMILRP` | ✘ | `LMPR` value when the NMI fired |

`DMPFG` is worth knowing about: setting it non-zero makes every print
produce no output at all, while still updating the position. That is how the
ROM measures how tall a line will be, and you can use it the same way.

## 14.8 The vector table

Each entry is a 16-bit address. **A non-zero vector diverts the corresponding
ROM routine**, which is how a DOS or a utility extends the interpreter
without patching ROM. The ROM checks each for zero before calling it.

| Offset | Address | Name | Called |
|---|---|---|---|
| &DA | 23258 | `DMPV` | `DUMP`/`COPY` — nothing happens without a driver here |
| &DC | 23260 | `SETIYV` | When the plot routine is being selected |
| &DE | 23262 | `PRTOKV` | Before a keyword is expanded for printing |
| &E0 | 23264 | `NMIV` | Non-maskable interrupt (normally the super-break handler) |
| &E2 | 23266 | `FRAMIV` | Frame interrupt, 50 times a second |
| &E4 | 23268 | `LINIV` | Line interrupt |
| &E6 | 23270 | `COMSV` | Communications interrupt |
| &E8 | 23272 | `MIPV` | MIDI input interrupt |
| &EA | 23274 | `MOPV` | MIDI output interrupt |
| &EC | 23276 | `EDITV` | Editor entry |
| &EE | 23278 | `RST8V` | Error handling, before the code is acted on |
| &F0 | 23280 | `RST28V` | The FP calculator, with every opcode before dispatch |
| &F2 | 23282 | `RST30V` | `RST &30` issued from outside ROM 0 |
| &F4 | 23284 | `CMDV` | Command dispatch, with the command byte — **the hook for new keywords** |
| &F6 | 23286 | `EVALUV` | Function evaluation, with the function code — **the hook for new functions** |
| &F8 | 23288 | `LPRTV` | `LPRINT` output |
| &FA | 23290 | `MTOKV` | The tokeniser, when a word fails to match the keyword table |
| &FC | 23292 | `MOUSV` | Mouse reading, from the frame interrupt |
| &FE | 23294 | `KURV` | Cursor drawing |

`FRAMIV` is the one most often used from BASIC-adjacent code: point it at a
routine and it runs fifty times a second, which is how you get background
music or a clock.

## 14.9 Compiler, error and listing state

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &0100 | 23296 | `CEXTAB` (32) | ✘ | Pixel expansion table with the current colours applied |
| &0120 | 23328 | `EXTAB` (32) | ✘ | Pixel expansion table, rebuilt when the mode changes |
| &0140 | 23360 | `COMPFLG` | ○ | Bit 7 set means the whole program needs recompiling |
| &0141 | 23361 | `BREAKDI` | ✔ | Non-zero **disables the BREAK test** between statements |
| &0142 | 23362 | `ERRSTAT` | ○ | Statement number of the active `ON ERROR` |
| &0143 | 23363 | `ERRLN` (2) | ○ | Line number of the active `ON ERROR` |
| &0145 | 23365 | `ONERRFLG` | ○ | `ON ERROR` arming: bit 7 temporary, bit 0 permanent |
| &0146 | 23366 | `ONSTORE` | ✘ | Real statement number saved by `ON` |
| &0147 | 23367 | `BCSTORE` (2) | ✘ | BC saved across an inter-ROM call |
| &0149 | 23369 | `M3PAPP` (2) | ✘ | `MODE 4` paper, preserved while `MODE 3` is selected |
| &014B | 23371 | `M3LSC` (2) | ✘ | `MODE 4` lower screen colours, likewise |
| &014D | 23373 | `TEMPW4` (2) | ✘ | Scratch |
| &014F | 23375 | `TEMPW5` (2) | ✘ | Scratch |
| &0152 | 23378 | `LPT` (30) | ✘ | Line pointer table: one byte per screen row, non-zero where a listed line begins |
| &0170 | 23408 | `ANYIV` (2) | ○ | The entry every maskable interrupt takes before demultiplexing |
| &0172 | 23410 | `RNSTKE` (2) | ✘ | Top of the rename stack used for `REF` string parameters |
| &0174 | 23412 | `CURCMD` | ○ | Token of the command currently executing |
| &0175 | 23413 | `LTDFF` | ✘ | Distinguishes `LET` from `DEFAULT` |
| &0176 | 23414 | `STRM16NM` (11) | ○ | Type/length byte and name of the string stream 16 appends to |
| &0181 | 23425 | `GRARF` | ○ | Graphics recording flag (`RECORD`) |
| &0182 | 23426 | `DHADJ` | ✘ | Scan offset while printing the lower half of a double-height character |
| &0183 | 23427 | `PAGCOUNT` | ✘ | Whole pages remaining in a block transfer |
| &0184 | 23428 | `MODCOUNT` (2) | ✘ | Bytes beyond those pages |
| &0186 | 23430 | `BCREG` (2) | ✘ | The FP calculator's B register |
| &0188 | 23432 | `AUTOFLG` | ○ | Non-zero while `AUTO` numbering is active |
| &0189 | 23433 | `AUTOSTEP` (2) | ○ | `AUTO` (and `RENUM`) increment |
| &018B | 23435 | `LSPTR` (2) | ✘ | Position within the line being listed |
| &018D | 23437 | `LNPTR` | ✘ | Screen row carrying the `>` cursor, or ≥ 64 if off screen |
| &018E | 23438 | `MSEDP` (8) | ○ | Mouse driver data |
| &018F | 23439 | `BUTSTAT` | ○ | Mouse button state, bits 2–0 for buttons 3–1 |
| &0196 | 23446 | `MXCRD` (2) | ○ | Mouse X coordinate (what `XMOUSE` returns) |
| &0198 | 23448 | `MYCRD` (2) | ○ | Mouse Y coordinate (what `YMOUSE` returns) |

## 14.10 Number formatting

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &019A | 23450 | `FRACLIM` | ✘ | Leading fraction zeros permitted before `E` notation. **Rewritten to 6 on every number conversion**, so poking it has no effect |
| &019B | 23451 | `NPRPOS` (2) | ✘ | Write position within the number buffer |
| &019D | 23453 | `DIGITS` | ✘ | Significant digits still to produce |
| &019E | 23454 | `EPOWER` | ✘ | Power of ten factored out for `E` notation |
| &019F | 23455 | `DECPNTED` | ✘ | Set once the decimal point has been emitted |
| &01A0 | 23456 | `PRNBUFF` (16) | ○ | The assembled number text |
| &01B0 | 23472 | `BCDBUFF` (5) | ✘ | Packed BCD digits during conversion |

`FRACLIM` looks like the one to reach for when small numbers print as `1E-7`
and you wanted `0.0000001` — but it is not usable from BASIC. `PFSTRS`, the
only entry point the jump table exposes, stores 6 into it before every
conversion. Only machine code calling the secondary entry `PFSTRSC` can
choose a different value.

## 14.11 Save, load and DOS state

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &01B5 | 23477 | `OTHER` | ✔ | Destination station number for network transfers |
| &01B6 | 23478 | `DCT` | ○ | Disk retry counter |
| &01B7 | 23479 | `SLDEV` (2) | ○ | Device letter and number for the transfer in progress |
| &01B9 | 23481 | `OVERF` | ○ | `SAVE OVER` flag: 0 means overwriting is permitted |
| &01BA | 23482 | `INSLV` (2) | ○ | Vector consulted by the block move routine (unused by the ROM) |
| &01BC | 23484 | `STRLOCN` (2) | ✘ | Address of the string/array record last found |
| &01BE | 23486 | `TVDATA` (2) | ✘ | Operands collected for a control code |
| &01C0 | 23488 | `DOSER` (2) | ○ | Where to jump after the DOS returns, or 0 for the normal path |
| &01C2 | 23490 | `DOSFLG` | ○ | Zero if no DOS is resident, otherwise the DOS page number |
| &01C3 | 23491 | `DOSCNT` | ✘ | Bit 0 set while the DOS is in control |
| &01C4 | 23492 | `BSTKEND` (2) | ○ | Lowest used address of the BASIC stack |

`PEEK SVAR &1C2` is the reliable test for "is there a DOS?".

## 14.12 Addresses initialised at cold start

These are all pointers the ROM sets up once and then uses. Redirecting them
is a legitimate — if advanced — way to change behaviour.

| Offset | Address | Name | | Description |
|---|---|---|---|---|
| &01C6 | 23494 | `BASSTK` (2) | ○ | Base of the BASIC stack; frames grow down from here |
| &01C8 | 23496 | `HEAPEND` (2) | ○ | Current top of the heap |
| &01CA | 23498 | `HPST` (2) | ○ | Base of the heap |
| &01CC | 23500 | `FPSBOT` (2) | ○ | Base of the floating-point calculator stack |
| &01CE | 23502 | `DKDEF` (2) | ○ | Start of the `DEF KEYCODE` buffer |
| &01D0 | 23504 | `DKLIM` (2) | ✔ | Address the `DEF KEYCODE` buffer may grow to |
| &01D2 | 23506 | `PATOUT` (2) | ✔ | Routine that renders a printable character |
| &01D4 | 23508 | `ERRMSGS` (2) | ✔ | Base of the error message table — point it at your own |
| &01D6 | 23510 | `UMSGS` (2) | ✔ | Base of the utility message table |
| &01D8 | 23512 | `KBTAB` (2) | ✔ | Base of the keyboard translation table |
| &01DA | 23514 | `CMDADDRT` (2) | ✔ | Base of the command address table |
| &01DC | 23516 | `MNOP` (2) | ○ | Main output routine, copied into channels when they are reset |
| &01DE | 23518 | `MNIP` (2) | ○ | Main input routine, likewise |
| &01E0 | 23520 | `PAGER` (14) | ○ | Reserved for a paging subroutine |
| &01EE | 23534 | `KBUFF` (18) | ✘ | Two keyboard state maps, for detecting newly pressed keys |

## 14.13 The ZX Spectrum compatible block

From 23552 upwards. Names and offsets follow the Spectrum where the meaning
is the same, which is why Spectrum tricks such as `POKE 23692,255` work
unchanged.

| Address | Name | | Description |
|---|---|---|---|
| 23552 | `LHM1` | ✘ | Scratch byte below `LASTH` |
| 23553 | `LASTH` | ○ | Last key hit, or 0 |
| 23554 | `KDATA` | ✘ | Control code being collected while its operand is typed |
| 23555 | `LKPB` (2) | ✘ | Previous keyboard scan result |
| 23557 | `REPCT` | ✘ | Frames until the held key repeats |
| 23558 | `LASTKV` (2) | ✘ | Raw port values of the last key read |
| 23560 | `LASTK` | ○ | Key taken from the head of the queue |
| 23561 | `REPDEL` | ✔ | Frames before a held key first repeats (33) |
| 23562 | `REPPER` | ✔ | Frames between subsequent repeats (3) |
| 23568 | `STREAMS` (42) | ○ | Stream table for streams −5 to 15; this address is stream 0 |
| 23606 | `CHARS` | ✔ | Character set base, stored 256 low |
| 23608 | `RASP` | ✔ | Length of the warning buzz |
| 23609 | `PIP` | ✔ | Length of the keyboard click |
| 23610 | `ERRNR` | ○ | Current error number; 0 means OK |
| 23611 | `FLAGS` | ○ | Principal interpreter flags |
| 23612 | `TVFLAG` | ○ | Screen output flags |
| 23613 | `ERRSP` (2) | ✘ | Stack pointer an error unwinds to |
| 23615 | `LISTSP` (2) | ✘ | Stack pointer an aborted `AUTOLIST` unwinds to |
| 23618 | `NEWPPC` (2) | ✘ | Line a pending jump will go to |
| 23620 | `NSPPC` | ✘ | Statement a pending jump will go to; 255 means none |
| 23621 | `PPC` (2) | ○ | Line number currently executing |
| 23623 | `SUBPPC` | ○ | Statement number currently executing, from 1 |
| 23624 | `BORDCR` | ✔ | Lower screen attribute in modes 1 and 2 |
| 23625 | `EPPC` (2) | ✔ | Line carrying the `>` cursor in listings |
| 23627 | `BORDCOL` | ○ | Value written to the border port; bit 6 mutes the speaker, bit 7 is MIDI through |
| 23631 | `CHANS` (2) | ○ | Base of the channel information area |
| 23633 | `CURCHL` (2) | ○ | Channel currently selected |
| 23635 | `DEFADDP` | ✘ | Page of the `DEF FN` parameter list |
| 23636 | `DEFADD` (2) | ✘ | `DEF FN` parameter list being evaluated, or 0 |
| 23638 | `NLASTH` (3) | ✘ | Raw port data for the most recent keypress |
| 23649 | `ZIPLIB` (2) | ✔ | Reserved for a third-party compiler — free otherwise |
| 23651 | `ZIPTEMP` (2) | ✔ | Likewise |
| 23653 | `STKEND` (2) | ○ | First free byte of the calculator stack |
| 23655 | `KPFLG` | ✔ | Keypad: even selects function keys, odd selects digits |
| 23656 | `MEM` (2) | ✔ | Base of the calculator's six numbered memories |
| 23658 | `FLAGS2` | ○ | Bit 3 = caps lock, bit 0 = the screen is not clear |
| 23660 | `SDTOP` (2) | ✔ | Line number at the top of an autolist |
| 23662 | `OLDPPC` (2) | ○ | Line `CONTINUE` will resume at |
| 23664 | `OSPPC` | ○ | Statement `CONTINUE` will resume at |
| 23665 | `FLAGX` | ✘ | Assignment and `INPUT` flags |
| 23666 | `STRLEN` (2) | ✘ | Length of the destination string |
| 23670 | `SEED` (2) | ✔ | `RND` seed (what `RANDOMIZE` sets) |
| 23672 | `FRAMES` (3) | ✔ | Frame counter, low three bytes — a 50 Hz clock |
| 23675 | `UDG` (2) | ✔ | Bitmap of `CHR$ 144`; codes 128–168 are relative to it |
| 23677 | `HUDG` (2) | ✔ | Bitmap of `CHR$ 169`, for codes 169–255. **The ROM never sets this** |
| 23679 | `FRAMES34` (2) | ✔ | Frame counter, high two bytes |
| 23682 | `OLDPOS` (2) | ✘ | Where the edit line last finished printing |
| 23692 | `SCRCT` | ✔ | Lines that may still scroll before the `scroll?` prompt |
| 23693 | `KBQB` (8) | ✘ | Keyboard queue |
| 23701 | `KBQP` (2) | ✘ | Queue pointers: tail low, head high |
| 23709 | `SCPTR` (2) | ○ | Entry in `SCLIST` for the current screen |
| 23711 | `FISCRNP` | ○ | Mode and page of screen 1 |
| 23712 | `SCLIST` (16) | ○ | Mode and page of screens 1–16, or 255 where closed |
| 23728 | `LASTPAGE` | ○ | Highest page reserved by BASIC |
| 23729 | `RAMTOPP` | ○ | Page of `RAMTOP` |
| 23730 | `RAMTOP` (2) | ○ | Highest address BASIC may use |
| 23732 | `PRAMTP` | ○ | Highest page fitted: 15 on a 256K machine, 31 on a 512K |

The last five are **not cleared by `NEW`**.

## 14.14 Reading the machine's shape

```basic
10 PRINT "RAM fitted:  "; (PEEK 23732 + 1) * 16; "K"
20 PRINT "DOS present: "; PEEK SVAR &1C2 <> 0
30 PRINT "Screen mode: "; PEEK SVAR &40 + 1
40 PRINT "Cell size:   "; PEEK SVAR &37; " x "; PEEK SVAR &36
50 PRINT "Free memory: "; FREE
60 PRINT "RAMTOP:      "; RAMTOP
70 PRINT "Uptime:      "; (DPEEK 23672 + 65536*PEEK 23674)/50; " s"
```

## 14.15 Some things worth doing

```basic
POKE SVAR &00, CODE "*"        : REM a different listing cursor
POKE SVAR &05, CODE "?"        : REM INSTR wildcard becomes '?'
POKE SVAR &2F, 1               : REM eight-column comma tabs
POKE SVAR &32, 1               : REM never blank the screen
POKE SVAR &33, 3               : REM silent tape operations
POKE SVAR &0E, 132             : REM 132-column printer
POKE SVAR &141, 1              : REM disable BREAK
POKE 23561, 8: POKE 23562, 1   : REM fast key repeat
POKE 23608, 0: POKE 23609, 0   : REM silence the buzz and the click
DPOKE 23672, 0                 : REM reset the frame clock
```

---

## Summary

* `SVAR n` gives the *address* of system variable *n*; the base is 23040 and
  the ZX-compatible block starts at offset 512 (address 23552).
* Colour, window and print state travel with the screen, and exist in
  permanent and temporary copies.
* The fourteen three-byte pointers from offset &81 describe the entire layout
  of the BASIC area.
* The nineteen vectors from offset &DA are the supported way to extend or
  divert the interpreter.
* A handful of bytes — `TABVAR`, `BREAKDI`, `SOFE`, `TPROMPTS`,
  `PRRHS`, `INSTHASH`, `REPDEL`/`REPPER` — give you behaviour with no command
  of its own. For what the keyboard group actually does, see
  [keyboard.md](../keyboard.md).

---

← [Memory and machine code](13-memory-and-machine-code.md) · [Contents](README.md) · [Next: Expert techniques →](15-expert-techniques.md)
