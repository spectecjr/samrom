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
`pages, lo, hi` meaning \(\text{pages} \times 16384 + (\text{hi:lo} \bmod
16384)\) — the hi byte usually has bit 7 set (&8000-based section-C
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
\((\text{ELINE} - 1) - \text{PROG}\) — that is, everything from the first
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
| 20 SCREEN$ | The screen bitmap for the saved MODE (&1B00 bytes mode 0, &3800 mode 1, &6000 modes 2/3) followed immediately by the 40-byte palette table (`PALTAB`) and, if present, the line-interrupt colour table (first byte &C3-terminated check) |

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
