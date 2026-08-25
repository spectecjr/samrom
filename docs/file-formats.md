# SAM Coupé ROM 3.0 — Saved BASIC Program File Format

How `SAVE`/`LOAD` encode a BASIC program on tape, net or disc, from
[tapemn.asm](../tapemn.asm) (header construction `SLMVC`/`HDRLNOK`, save
execution `SAMAIN`/`SVFL`, load execution `LDPRDT`/`LDPROG`) and
[tapex.asm](../tapex.asm) (block encoding `SABLK`/`LDBLK`).

## Overall file structure

Every SAM file is two blocks:

| Block | Type byte | Length | Contents |
|---|---|---|---|
| Header | &01 | 80 bytes | The `HDR` buffer described below |
| Data | &FF | As given at header offset 34–36 | The file body |

On **tape/net** the ROM writes the two blocks itself (each with its own
leader/sync/parity — see [Tape block encoding](#tape-block-encoding)). On a
**DOS device** the ROM builds the same 80-byte header at `HDR` (&4B00),
points IX at it, and issues hook &84 (`SVHK`) / &81 (`FOPHK`) — the DOS
stores header and data however it likes but must present the same header
back on load (the DOS re-enters the ROM's common code at `LDFL`/`LKTH`/
`SVFL` with E = 1/3/2).

## The 80-byte header

Multi-byte *lengths and addresses* use the ROM's **page form**: three bytes
`pages, lo, hi` meaning $`\text{pages} \times 16384 + (\text{hi:lo} \bmod 16384)`$
— the hi byte usually has bit 7 set (&8000-based section-C
address); loaders must mask bits 6–7 of the hi byte when forming the 14-bit
remainder, and treat the whole triple as invalid ("none") when the first
byte is &FF.

| Offset | Size | Field | Contents |
|---|---|---|---|
| 0 | 1 | Type | 16 = BASIC program, 17 = numeric array, 18 = string array, 19 = CODE, 20 = SCREEN$ |
| 1–10 | 10 | Name | File name, space-padded (first byte &FF = null name = "match anything" on load) |
| 11–14 | 4 | Name extension | Extra name characters allowed when the device is not tape |
| 15 | 1 | Flags (`HFG`) | Bit 0 = invisible (name not printed while searching), bit 1 = protected |
| 16–26 | 11 | Type-specific | See below |
| 27 | 1 | `DIRE` | Directory entry number (request header only; unused by tape) |
| 28–30 | 3 | — | Spare |
| 31–33 | 3 | Start (`HDN`) | Data start, page form. BASIC: PROG's page and address (typically `00 D5 9C`). CODE: relative page form (relative to the calling context's base page; SAVE adds the current LRPORT so the stored value is absolute-ish). Arrays: address of the variable record, or &FFxxxx if it doesn't exist |
| 34–36 | 3 | Length | Data block length, page form (&FFxxxx in a *request* header means "whatever the file says", e.g. `LOAD "" CODE`) |
| 37–39 | 3 | Execute / auto-run | CODE: execution address (relative page form) or &FFxxxx = none. BASIC: byte 37 = 0 if there is an auto-run line, then bytes 38–39 = line number (lo,hi); byte 37 = &FF = no auto-run |
| 40–79 | 40 | Comment | Not initialised or interpreted by the ROM — free for tools to use |

### Type-specific area (offsets 16–26)

| Type | Offsets 16–26 |
|---|---|
| 16 BASIC | Three page-form lengths (see next section): 16–18 program alone, 19–21 program + numeric variables, 22–24 program + numeric variables + gap; 25–26 unused |
| 17 / 18 array | The variable's type/length byte (offset 16) followed by its 10-character name — exactly the 11 bytes of the variables-area record header |
| 19 CODE | Unused |
| 20 SCREEN$ | Offset 16 = screen MODE (0–3); rest unused |

## What the data block contains for a BASIC program (type 16)

SAVE writes **one contiguous block** starting at `PROG` with length
$`(\text{ELINE} - 1) - \text{PROG}`$ — that is, everything from the first
program line up to *but excluding* the &FF terminator that ends the
string/array area (the terminator is deliberately not saved; LOAD re-plants
one). The block therefore contains, in order:

```text
PROG   → program lines (tokenized, with &0E number forms and FN/PROC
         calling buffers exactly as stored — see
         tokenized-program-format.md), ending with the &FF program
         terminator
NVARS  → numeric variables: 26 letter-chain root pointers (52 bytes)
         followed by the numeric variable records
NUMEND → the numbers-to-strings gap (saved as-is; usually a few hundred
         slack bytes)
SAVARS → string and array records
       → (the final &FF stopper is NOT in the file)
```

So a saved program carries its variables with it — `SAVE` after `RUN`
preserves state, and the pseudo-variables (XOS/YOS/XRG/YRG etc., which live
in the numeric variables area) travel too.

These four regions are the first four of BASIC's moving area;
[memory-map.md](memory-map.md#what-save-stores-and-what-load-rebuilds) sets
them out alongside the ones that are *not* saved (edit line, workspace) and
the state that is discarded rather than restored (the BASIC stack, the `DATA`
pointer, the FN/PROC calling buffers).

The three lengths at header offsets 16/19/22 are the distances from PROG to
NVARS, NUMEND and SAVARS respectively, computed at save time
(`SUBAHLCDE` page-form subtraction of each pointer from PROG).

### How LOAD reconstructs the program (`LDPRDT`/`LDPROG`)

1. Check the file fits: compare the header length against free memory
   (error 1 "Out of memory" if not).
2. Delete the current program *and* numeric variables in one reclaim
   (NVARS is zeroed first so pointer auto-adjustment doesn't misfire), and
   clear the BASIC stack (its return addresses are obsolete).
3. Open a block of exactly the file length at PROG (`MKRBIG`), plant a
   provisional &FF at the start (so a failed load leaves an empty,
   consistent program), and load the data block into it.
4. Rebuild the three region pointers by page-form addition:
   NVARS = PROG + (hdr+16), NUMEND = PROG + (hdr+19),
   SAVARS = PROG + (hdr+22). Everything above SAVARS (edit line onward) was
   already in place around the opened block.
5. `RESTORE 0`, then set `COMPFLG` and run the compile pass (DOCOMP) — the
   FN/PROC **calling-buffer addresses inside the loaded program are stale**
   (they refer to wherever the program sat when it was saved) and are fully
   recomputed here; a file written by an external tool may safely store its
   buffers unresolved (`0E FE FE FF 00 00` form) for the same reason.
6. Auto-run: `LOAD "name" LINE n` overrides the header; otherwise if header
   byte 37 = 0, GOTO the line at bytes 38–39.

`MERGE` loads the same file into workspace instead, then splices: lines
replace same-numbered lines, numeric variables are re-created one by one,
strings/arrays replace same-named victims — using header lengths 16 and 22
to find the section boundaries inside the loaded image.

### Verification notes for tools

* The data block must exactly match the pointers: program terminator &FF
  present at PROG+(hdr16)−1… strictly, the &FF program stopper is the last
  byte before NVARS; the 26 chain roots follow immediately.
* All numeric-chain pointers and calling buffers are position-independent
  (relative links / recompiled), so a program image can be relocated freely
  — only the header's three lengths and the total length must be
  consistent.
* Line format inside the program section:
  [tokenized-program-format.md §7](tokenized-program-format.md#7-the-final-in-memory-format-detokenizer-specification).

## Other file types, briefly

| Type | Data block |
|---|---|
| 17/18 array | The complete variables-area record **from its type/length byte**: 11-byte name header + 3-byte length + dimension data + elements (`ADD14` accounts for the 14 header bytes). LOAD deletes any same-named variable and splices the record into SAVARS, then overwrites the stored name with the requested one |
| 19 CODE | Raw bytes. Start/length/execute from the header; on load the start address is interpreted through the 0–512K `PDPSR2` mapping and the code optionally executed |
| 20 SCREEN$ | The screen bitmap for the saved MODE, followed immediately by the 40-byte palette table (`PALTAB`) and the line-interrupt colour table — see [SCREEN$ files in detail](#screen-files-type-20-in-detail) |

## SCREEN$ files (type 20) in detail

A screen file is a picture *plus the colours it was drawn with*: the bitmap,
then the whole 40-byte working palette, then the line-interrupt colour list.
`SAVE SCREEN$` builds the trailer in `HDR5` and `LOAD`/`VERIFY` take it apart
in `LDSCRN` (both [tapemn.asm](../tapemn.asm)); the two tables themselves are
maintained by `PALETTE` in [misc31.asm](../misc31.asm) and consumed by the
frame and line interrupts in [scrsel1.asm](../scrsel1.asm).

| Data offset | Size | Contents |
|---|---|---|
| 0 | *bitmap* | Screen memory, verbatim, from &8000 in the screen's page |
| *bitmap* | 40 | `PALTAB` — the working palette |
| *bitmap*+40 | 4·*n*+1 | `LINICOLS` — *n* line-interrupt entries then an &FF terminator |

The mode is header offset 16 and is the **internal** mode 0–3, one less than
the number BASIC's `MODE` command takes:

| Header byte 16 | BASIC `MODE` | Bitmap | Smallest whole file |
|---|---|---|---|
| 0 | `MODE 1` | &1B00 (6912) | 6953 |
| 1 | `MODE 2` | &3800 (14336) | 14377 |
| 2 | `MODE 3` (four colours) | &6000 (24576) | 24617 |
| 3 | `MODE 4` | &6000 (24576) | 24617 |

The header's start address is always `00 00 80` — &8000 in the page recorded
by `CUSCRNP` — and the length covers bitmap and trailer together. &20 in the
mode byte means "a CODE file being loaded as SCREEN$": `LDSCRN` substitutes
the current mode and skips the mode change.

### The palette table (`PALTAB`, 40 bytes)

`PALTAB` is 40 bytes at &55D8 (`PALTABLEN` = &28), copied to and from the file
as one lump. It is four groups:

| Offset in the 40 bytes | Bytes | Contents |
|---|---|---|
| 0–15 | 16 | **Main palette**, entries 0–15 — the colours in force in the file's mode |
| 16–19 | 4 | Parked main colours for entries 0–3 of the *other* mode group |
| 20–35 | 16 | **Alternate palette**, entries 0–15 — the flash partner of 0–15 |
| 36–39 | 4 | Parked alternate colours for entries 0–3 of the other mode group |

Each byte is one SAM colour, 0–127, laid out `G1 R1 B1 BRIGHT G0 R0 B0` in
bits 6–0; bit 7 is unused. To render a file you need offsets 0–15 only.

**The flash pair.** The frame interrupt reloads the whole CLUT every 50th of
a second with `OTDR` of sixteen bytes counting down from offset 15 or from
offset 35, chosen by bit 0 of `PALFLAG`, which is flipped every `SPEEDINK`
frames. An entry whose two colours are equal is steady; an entry whose two
differ flashes between them. `PALETTE i,c` writes *c* to both halves;
`PALETTE i,b,c` writes the two separately.

**The parked entries.** BASIC `MODE 3` (internal mode 2) has only four inks,
and it uses a different set of colours for entries 0–3 than the sixteen-colour
modes do. Rather than keep two palettes the ROM parks the inactive four:
`PALSW` swaps offsets 0–3 with 16–19 and 20–23 with 36–39 whenever the machine
enters or leaves that mode. So offsets 0–15 are *always* the live palette for
the mode in header byte 16, and 16–19/36–39 are the four colours that would
come back if the mode were switched. A tool that only draws the picture can
ignore them, but should carry them through unchanged when rewriting a file.

`NEW` reinitialises the table from `INITCOLS` ([text.asm](../text.asm)):
entries 0–7 black, blue, red, magenta, green, cyan, yellow, white at half
brightness, 8–15 the same eight with the bright bit (except black), and the
four parked mode-3 colours black, blue, red, white. Both halves get the same
values, so nothing flashes on a fresh machine.

Screens that are open but not being displayed keep their own copy of these 40
bytes in the last 40 bytes of their 32K block (`PALBUF`, offset &7FD8 of the
pair of pages); `SDISR` in [misc2.asm](../misc2.asm) copies it in and out of
`PALTAB` as `DISPLAY` changes which screen is shown.

### The line-interrupt table (`LINICOLS`)

`LINICOLS` (&5600, 512 bytes) is how `PALETTE ... LINE` changes a colour
part-way down the frame. It is a list of four-byte entries **sorted by scan
line ascending**, ending in a single &FF:

| Byte | Contents |
|---|---|
| 0 | Scan line, 0–190 — the last line drawn with the old colour |
| 1 | Palette entry to change, 0–15 |
| 2 | Colour |
| 3 | Alternate colour (the flash partner) |

* The terminator is an &FF **in the scan-line position**. An empty list is one
  byte, so a screen file's trailer is never shorter than 41 bytes.
* At most 127 entries. `PALETTE` refuses to insert past a total of &1FF bytes
  ("Palette table full"), and `LOAD` discards any list of &200 bytes or more.
* Several entries may share a scan line: the handler applies them in one go
  and the sort keeps them adjacent.
* The two colours flash exactly as `PALTAB`'s do — every `SPEEDINK` frames the
  frame interrupt walks the whole list swapping bytes 2 and 3 of every entry.
  **In a saved file the pair may therefore be in either order**, depending on
  which way round the flash happened to be at the moment of the `SAVE`.

**Scan numbering.** `PALETTE i,c LINE y` stores 174 − *y*, so the entry's scan
byte is one *less* than the display line the new colour first appears on
(`COLATSR`, [misc31.asm](../misc31.asm), converts BASIC's *y* = 175 at the top
down to −16 at the bottom into a 0–191 top-down scan and then subtracts one).
`LINE 175` is rejected with "Integer out of range" because it would need an
interrupt at the end of a line that does not exist, and 174 − (−16) = 190 is
the largest value that can appear.

**What the hardware does with it.** Each frame interrupt resets `LINIPTR` to
the start of the list and writes the first scan byte to `STATPORT`, arming the
line interrupt (&FF = never). When that interrupt fires, `LINEINT` waits on the
pen-Y register at port &01F8 until the raster leaves that line, writes the new
colour to `CLUTPORT` with the palette entry number in B, then walks on to the
next entry and arms the next scan. The changes have to fit in the border
period: the ROM's own measurements are about 32 T-states for the first colour
and 80 for each further one, giving about two changes in the border and three
in the visible part of a line. Overrunning loses not just the late change but
every later change in the frame, because `STATPORT` never gets re-armed.

A cold-started machine builds a 16-entry default rainbow — palette entry 0
changed every eleven scans, at lines 0, 11, 22 … 165, taking its colours from
`PALTAB`+1 upwards — which is what the boot screen's striped border is. `NEW`
empties the list, so most saved screens carry the one-byte empty form unless
the program deliberately built a list.

### How `SAVE` assembles the trailer

`HDR5` measures the list with `FLITE`, adds 40, adds the bitmap length for the
mode, and records the total as the file length. It then pages the screen in
and `LDIR`s `PALTAB` (and, contiguously in memory, `LINICOLS`) into the screen
block **just past the end of the bitmap** — &9B00 in mode 0, &B800 in mode 1,
offset &6000 with the screen's second page mapped at &8000 in modes 2 and 3 —
so that the whole file is one contiguous block starting at &8000.

Two consequences:

* Saving a screen scribbles 41 or more bytes over the spare RAM in that
  screen's 32K block. It is spare in every mode, but it is not preserved.
* `HDR5` is the common parameter routine for `SAVE`, `LOAD` **and** `VERIFY`,
  so it runs — and does that copy — for all three. `VERIFY SCREEN$` therefore
  compares the file's trailer against the palette and line list that are
  current *now*, not against whatever was in force when the file was written.

### How `LOAD` takes it apart

`LDSCRN` changes mode if the file's differs, loads the whole block to &8000,
and then works out what came after the picture:

1. `extra` = file length − bitmap length for the mode. Zero or negative means
   there is no trailer (a plain CODE file loaded as SCREEN$); it returns.
2. 40 bytes are copied from the end of the bitmap to `PALTAB` if the screen
   being loaded is the one on display, or to that screen's `PALBUF` if not.
3. The next byte is examined. **195 (&C3) or more means "no list"** — scan
   lines only run to 190, so &FF terminator lands here for an empty one. The
   byte is still stored, which is what leaves `LINICOLS` correctly terminated.
4. Otherwise `extra` − 40 bytes are copied on to `LINICOLS`, with interrupts
   disabled, and `STATPORT` is set to &FF so no line interrupt can fire against
   a half-written list until the next frame interrupt re-arms it.
5. A list of &200 bytes or more is rejected at step 4 (the palette has already
   been taken).

### Notes for tools

* Write the trailer as exactly 40 + 4·*n* + 1 bytes. The 40-byte palette copy
  is unconditional once `extra` is positive, so a trailer of, say, 20 bytes
  loads 20 bytes of palette and 20 bytes of whatever followed the file in
  memory.
* Keep the list sorted ascending by scan line. Neither `LOAD` nor the interrupt
  handler sorts or validates it, and an out-of-order entry simply stops the
  walk making sense for the rest of the frame.
* Terminate with &FF specifically. `FLITE` tests for &FF exactly when measuring
  the list for a later `SAVE`, even though `LOAD` accepts anything from 195 up
  as "empty".
* Loading a **mode 0 or 1** file into a screen that is not currently displayed
  does not restore its palette. The ROM writes to `PALBUF`−&4000 = &BFD8,
  which is only the real per-screen palette store when the screen's second page
  is mapped at &8000 — true after loading a mode 2/3 bitmap, because the loader
  steps the page as the address crosses &C000, but not after the shorter mode
  0/1 ones, where &BFD8 is unused RAM at the end of the first page. This looks
  like a ROM bug rather than intent; `SAVE` has no matching problem.

## Tape block encoding

`SABLK`/`LDBLK` ([tapex.asm](../tapex.asm)) implement a ZX-Spectrum-style
but **speed-programmable** format (`DEVICE Tn` sets the speed; default
`TSPEED` = 112; the half-cycle period scales from it, and the leader cycle
count is scaled inversely so leaders last roughly constant wall-clock
time):

| Element | Encoding |
|---|---|
| Leader | A long run of uniform cycles (count scaled by speed) letting the loader measure the recording speed — the loader self-calibrates its bit threshold from it, so tapes recorded at any speed (including ZX speed) load |
| Sync | A distinctive short pulse pair marking the start of data |
| Type byte | First data byte: &01 = header block, &FF = data block (compared against the expected type; ZX 17-byte headers are recognised and translated — a ZX CODE header becomes a SAM type-19 header) |
| Data | Bytes MSB-first; each bit is one cycle, 0 short / 1 long relative to the measured threshold; the border stripes while saving/loading |
| Parity | Final byte: XOR of type byte and all data bytes; mismatch = "Loading error" (19) |

`VERIFY` runs the same reception comparing against memory instead of
storing. Net transfers (`DEVICE N`) use the same two-block structure with
their own byte-level protocol (station addressing via `OTHER`, per-byte
parity).

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
