# SAM Coupé ROM 3.0 — Memory Map

Derived from the `EQU` values in [vars.asm](../vars.asm), the `MAIT`/`CHIT`
initialisation tables in [text.asm](../text.asm), and the initialisation code
in [misc31.asm](../misc31.asm) (`MNINIT`).

## Address spaces

The Z80's 64K space is four 16K sections, each independently pageable:

| Section | Address range | Normal contents while BASIC runs |
|---|---|---|
| A | &0000 – &3FFF | **ROM0** (paged out only for special cases) |
| B | &4000 – &7FFF | **The system page — physical RAM page 0** (LMPR low bits = &1F) |
| C | &8000 – &BFFF | Working page: BASIC program/variables page, screen, or whatever URPORT selects |
| D | &C000 – &FFFF | Page above section C's, or **ROM1** when its enable bit is set |

All system variables and fixed buffers below are in physical **page 0**,
addressed in section B. The BASIC program area *starts in the same page*
(immediately after the channels) but is addressed through section C — BASIC
addresses it as page 0 at &9CD5 and lets it grow across pages 1, 2, … up to
RAMTOP.

## System page (physical page 0)

Addresses are as seen in section B (&4000–&7FFF); the "offset" column is the
position within the 16K page. Length is in bytes.

| Start | End | Length | Offset | Region | Description |
|---|---|---|---|---|---|
| &4000 | &4AFF | 2816 | &0000–&0AFF | Heap + BASIC stack | Heap (`HPST`/`HEAPEND`) grows **up** from &4000 (initially empty); the DO/GOSUB/PROC "BASIC stack" (`BSTKEND`) grows **down** from `BSTACK` = &4AFF. The gap between `HEAPEND` and `BSTKEND` is **free** (error 41 when they meet) |
| &4B00 | &4B4F | 80 | &0B00 | `HDR` | Save/load header being requested/built; also the PROC rename stack (nparpro.asm) |
| &4B50 | &4B9F | 80 | &0B50 | `HDL` | Header loaded from tape/disc/net |
| &4BA0 | &4BFF | 96 | &0BA0 | *(spare)* | Unnamed; headroom for the interrupt stack (the source notes `INTSTK` "uses down to ~&49EE" in the deepest cases — tape I/O runs with interrupts off, so HDR/HDL are safe) |
| &4C00 | &4CFF | 256 | &0C00 | `BUFF256` / `INTSTK` | 256-byte bounce buffer for FARLDIR page-to-page copies; the interrupt stack also grows **down** from &4C00 |
| &4D00 | &4E80 | 385 | &0D00 | `FPSB` / `CDBUFF` | Bottom of the FP calculator stack (grows **up** from &4D00, top tracked by `STKEND`); overlaid by `CDBUFF`, the generated-code buffer (multi-LDI/RLD runs, max &181 bytes) — the RAM copy of the tokenizer runs at `CDBUFF+&80` (&4D80–&4E24) |
| &4E81 | &4EFF | 127 | &0E81 | Machine stack | Grows **down** from `ISPVAL` = &4F00 ("used down to ~&4E98 normally") |
| &4F00 | &50FF | 512 | &0F00 | `INSTBUF` | Execution buffer for command bodies copied from ROM1 (RENUM, GET, DELETE, POP, INPUT, DEF KEYCODE, DEF FN, MERGE), filename/SOUND/INSTR scratch. Overlaid sub-buffers: `FILBUFF` &5080 (128, FILL pattern) and `MSGBUFF` &50C0 (64, message assembly) |
| &5100 | &5120 | 33 | &1100 | `ALLOCT` | Page allocation table: 1 byte per RAM page (0=free, &40=reserved, &60=DOS, &C0=screen, &FF=absent/terminator) |
| &5121 | &513E | 30 | &1121 | `MEMVAL` | The six 5-byte calculator memories (default target of `MEM`) |
| &513F | &513F | 1 | &113F | `TLBYTE` | Type/length byte of the variable name being processed |
| &5140 | &5187 | 72 | &1140 | `NMBUFF` / `FIRLET` | Variable/FN/PROC name buffer (a second name copy lives at `TLBYTE+33` = &5160) |
| &5188 | &518F | 8 | &1188 | `SCRNBUF` / `NMISTK` | SCREEN$ compressed-character buffer; the NMI stack grows **down** from &5188 |
| &5190 | &55D7 | 1096 | &1190 | `CHARSVAL` | Unpacked character set, 8 bytes/char for codes 32–168 (`CHARS` = &5090 = CHARSVAL−256; `UDG` = &5510 = CHR$ 144). Codes &A9–&FF have no font in ROM — see [hudg.md](hudg.md) |
| &55D8 | &55FF | 40 | &15D8 | `PALTAB` | Working palette: 2 × 16 palette memories (flash pair) + mode-2 spare entries |
| &5600 | &57FF | 512 | &1600 | `LINICOLS` | Line-interrupt colour table (up to 127 × 4-byte entries + terminator) |
| &5800 | &5880 | 129 | &1800 | `DKBU` | DEF KEY definitions (`DKDEF`; growth limit `DKLIM` = &5880 by default) |
| &5881 | &58DF | 95 | &1881 | *(spare)* | Unused between the DEF KEY limit and the key map |
| &58E0 | &59FF | 288 | &18E0 | `KTAB` | Keyboard translation map: 3 × 70-entry planes (normal/caps/symbol) + control-key values |
| &5A00 | &5BFF | 512 | &1A00 | `VAR2` | Main system-variable block (see [constants.md](constants.md#varsasm); ends with the 18-byte `KBUFF` at &5BEE) |
| &5C00 | &5CB5 | 182 | &1C00 | ZX-style sysvars | `LHM1`…`PRAMTP`: keyboard state, `STREAMS`, `FLAGS`, `PPC`, `CHANS`, `STKEND`, `RAMTOP` etc. (small documented spare gaps inside) |
| &5CB6 | &5CD4 | 31 | &1CB6 | Channels | Six 5-byte channel records (output addr, input addr, letter: K, S, R, P, $, B) + &0D terminator; `CHANS` points here |
| &5CD5 | &7FFF | 9003 | &1CD5 | **Start of BASIC program area** | `PROG` = page 0, address &9CD5 (section C view). The program, then the numeric variables, gap, strings/arrays, edit line, and workspace continue from here across pages 1, 2, … |

Totals: &4000–&5CD4 (7381 bytes) of fixed system use; the rest of page 0
belongs to the moving BASIC area.

The only genuinely unused hole in the system page is &5881–&58DF (95 bytes).
[hudg.md](hudg.md) works through the consequences for anyone wanting to add
a high-UDG character set, including how to carve a larger hole by raising
`PROG`.

## The moving BASIC area (section C view, page 0 onward)

These regions are contiguous and slide as MAKEROOM/RECLAIM insert and delete
bytes; each boundary is a (page, address) system-variable pair. Order, low to
high:

| Pointer | Region that follows it | Contents |
|---|---|---|
| `PROG` (= 0:&9CD5) | Program | Tokenized program lines, terminated by &FF |
| `NVARS` | Numeric variables | 26 letter-chain root pointers (52 bytes) + variable records |
| `NUMEND` | Gap | Free slack between numbers and strings (new numeric variables grow into it; re-opened 512 bytes at a time) |
| `SAVARS` | Strings & arrays | String/array records, terminated by &FF |
| `ELINE` | Edit line | The line being typed/edited, ending &0D &FF |
| `WORKSP` | Workspace | INPUT data, temporary strings |
| `WKEND` | *(free)* | Free memory up to `RAMTOP` |
| `RAMTOP` | — | Default = &BFFF in page `LASTPAGE`; above it: user reserved pages and the screen pages at the top of RAM (2 pages per open screen) |

Not in this chain (fixed in the system page): the FP calculator stack
(&4D00, `STKEND`), the heap, the BASIC stack, and the machine stack.

## ROM layout

| Start | End | Length | Contents |
|---|---|---|---|
| &0000 | &3FFF | 16384 | ROM0 — restarts, [jump table at &0100](machine-code-interface.md#the-jump-table-at-0100), editor, interpreter loop, evaluator, variables, graphics (see [source-files.md](source-files.md)) |
| &C000 | &FFFF | 16384 | ROM1 — FP calculator/arithmetic, printing, tape/net, screens/interrupts, keyword & message tables (paged over section D on demand; the paging bit lives in LRPORT bit 6, toggled by the RST &30 mechanism) |

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
