# The Character Set, `UDG` and `HUDG`

How SAM BASIC locates a character's 8-byte bitmap, what the dormant `HUDG`
pointer does, and where a high-UDG font could actually live.

Sources: [vars.asm](../vars.asm) (`CHARS`, `UDG`, `HUDG`, `CHARSVAL`),
[misc31.asm](../misc31.asm) (`MNINIT`, `UPACK`),
[tprint.asm](../tprint.asm) (`PRGR80`, `POUDG`, `PUDGS`, `POFUDG`),
[rom1fns.asm](../rom1fns.asm) (`FPUDG`), and
[endprint.asm](../endprint.asm) (`EPSUB`, `SELSCRN`). Byte values verified
against `roms/ROM30`.

## The three font pointers

All three are 2-byte pointers in the ZX-style system-variable block:

| Sysvar | Address | Initial value | Points at | Set by |
|---|---|---|---|---|
| `CHARS` | &5C36 | &5090 (= `CHARSVAL` − 256) | Notional bitmap of CHR$ 0 | `MNINIT` |
| `UDG` | &5C7B | &5510 (= `CHARSVAL` + 896) | Bitmap of CHR$ 144 | `MNINIT` |
| `HUDG` | &5C7D | &0000 | Bitmap of CHR$ 169 | **Nothing — never written** |

`CHARSVAL` = &5190 holds the character set unpacked at boot by `UPACK` from
the 5-bit compressed `CHARSRC` table in [text.asm](../text.asm).

## Bitmap address arithmetic

| Codes | Bitmap address | Code reference |
|---|---|---|
| &20–&7F (ASCII) | \((\text{CHARS}) + \text{code} \times 8\) | `PRASCII`/`PRINTMN1` |
| &80–&A8 (low UDGs) | \((\text{UDG}) - 1152 + \text{code} \times 8\), i.e. \((\text{UDG}) + (\text{code}-144) \times 8\) | [tprint.asm:329](../tprint.asm#L329) — the &FB80 added there is −144×8 |
| &A9–&FF (high UDGs) | \((\text{HUDG}) + (\text{code}-169) \times 8\) | [tprint.asm:324-326](../tprint.asm#L324-L326) |

The `UDG "x"` function (`FPUDG`, [rom1fns.asm:848](../rom1fns.asm#L848))
returns exactly these addresses, using the same three branches.

Each bitmap is 8 bytes, one per scan, bit 7 leftmost — but how many of those
bytes and bits actually reach the screen depends on `CSIZE`. See
[font-rendering.md](font-rendering.md).

Note that \((\text{UDG}) - 1152 = \&5510 - \&480 = \&5090 = (\text{CHARS})\).
The ROM font and the low UDGs are **one contiguous table**: `CHARSVAL`
&5190–&55D7 covers codes 32–168 (137 characters × 8 = 1096 bytes), and code
168's bitmap ends at &55D7 with `PALTAB` beginning at &55D8. The table hits
a wall exactly where the high UDGs would continue — which is presumably why
`HUDG` exists as a separate pointer rather than the table simply running on.

## Which codes reach `HUDG`

Character codes &80–&FF are ambiguous: they are both UDG/graphic characters
and BASIC tokens. `PRGR80` ([tprint.asm:118](../tprint.asm#L118)) resolves
the ambiguity by context:

| Condition | Codes treated as UDGs |
|---|---|
| `INQUFG` bit 0 set (in quotes) or `FLAGX` bit 7 set (INPUT line) | &80–&FF (all) |
| Otherwise (listing a program) | &80–&84 only; &85–&FE expand as keywords |

`PRINT` sets `INQUFG` bit 0 on entry ([list.asm](../list.asm), `PRINT`), so
**everything printed by a program takes the UDG path**. From there `PUDGS`
sends codes ≥ &90 (or any code when `BGFLG` is non-zero) to `POFUDG`, and
`POFUDG` uses `HUDG` for everything from &A9 up.

## `HUDG` is live but unpopulated

`HUDG` is read in exactly two places and written in none:

| Site | Purpose |
|---|---|
| [tprint.asm:324](../tprint.asm#L324) `POFUDG` | Printing character codes &A9–&FF |
| [rom1fns.asm:868](../rom1fns.asm#L868) `FPUDG` | `UDG "x"` for codes ≥ 169 |

`MNINIT` initialises `CHARS` and `UDG` and stops
([misc31.asm:211-214](../misc31.asm#L211-L214)); `NEW` enters at `NEW2` and
touches neither. The only thing that ever writes the location is the
power-on RAM test (`RMPS`), which fills every page with zeros.

So `HUDG` reads **&0000** on a freshly booted machine, and the consequence
is real rather than theoretical: `PRINT CHR$ 200` fetches its bitmap from
ROM0 &00F8, and the range &A9–&FF reads ROM0 &0000–&02B7. In the shipped
image that area is solid code — the source's `DS &0100-$` assembles to
nothing, `LRPOUT`'s final `C9` landing exactly at &00FF — so the result is
garbage pixels, not blanks. `HUDG` is a finished hook with no font behind
it; supply one and the whole &A9–&FF range becomes user-definable.

## Where a high-UDG font can live

### The constraint

At print time `EPSUB` ([endprint.asm:6-8](../endprint.asm#L6-L8)) executes
`R1OSR` (ROM1 off) and then `SELSCRN`, which pages the **screen** into
section C — and into section D as well for modes 2/3, whose 24K screens span
&8000–&DFFF. The bitmap is read through HL *after* that.

`HUDG` must therefore resolve in **&0000–&7FFF**: ROM0 or the system page.
It is a bare 16-bit address with no accompanying page byte, so nothing
outside that window is reachable.

### The budget

A full high-UDG set is 87 characters × 8 = **696 contiguous bytes**.
Free space in the system page (see [memory-map.md](memory-map.md)):

| Region | Size | Verdict |
|---|---|---|
| &5881–&58DF | 95 bytes | The only genuinely unused hole — 11 characters |
| &4BA0–&4BFF | 96 bytes | Nominally spare, but the interrupt stack descends through it (`INTSTK` &4C00 "uses down to &49EE") — unsafe |
| Gaps inside the &5C00 block | 1–8 bytes each | Too small to matter |

No 696-byte hole exists. Three ways round it follow, in order of
cleanliness. All are derived from the code rather than tested on hardware.

### (a) Raise `PROG` and carve space below the program

`MNINIT` sets `PROG` = &9CD5 (page 0, offset &1CD5), and nothing outside
`MNINIT` ever resets it — `NEW` enters at `NEW2`, which simply re-plants the
program terminator wherever `PROG` currently points
([misc31.asm:267-272](../misc31.asm#L267-L272)). Raising `PROG` therefore
carves a permanent hole below the program area.

The hole is stable because `MAKEROOM`/`RECLAIM` never disturb anything below
the change location: `ASSV` skips any pointer that is less than or equal to
it ([tadjm.asm:490-494](../tadjm.asm#L490-L494)), and the block move only
covers the change location up to `WKEND`. Page-0 offsets &1CD5–&1F8C are the
same bytes as section-B &5CD5–&5F8C, so the font is addressable at &5CD5
while printing. This costs no ROM feature.

```basic
10 DPOKE 23200,DPEEK(23200)+696 : REM PROG (&5AA0) up by 696 -> &9F8D
20 DPOKE 23677,23765            : REM HUDG (&5C7D) -> &5CD5, the freed hole
30 LOAD "nextprog" LINE 10
```

`PROG` is at `VAR2`+&A0 = &5AA0 = 23200 (its page byte `PROGP` is at &5A9F);
`HUDG` is at &5C7D = 23677; the hole starts at &5CD5 = 23765. All three are
in the 16384–32767 range that `POKE`/`DPOKE` map straight into the system
page, so no paging games are needed.

**Do not use `NEW` here** — see
[Automating the change](#automating-the-change) below. `LOAD` of a BASIC
program rebuilds the whole area from `PROG` on its own, so `NEW` is not
needed in the first place.

Write the font bitmaps *after* the load (the hole initially contains stale
program text), e.g. from the loaded program with
`POKE 23765+n, …` for \(n = 0 \dots 695\).

### (b) Steal &5600–&58DF (736 bytes)

`LINICOLS` (&5600–&57FF, 512 bytes) and the DEF KEY buffer (&5800–&58DF,
224 bytes including the unused tail) are contiguous, giving 736 bytes.
`HUDG` = &5600 then covers &A9–&FF in &5600–&58B7. The cost is
`PALETTE … LINE` colour changes and DEF KEY definitions.

Taking `LINICOLS` alone yields 512 bytes = 64 characters, codes &A9–&E8.
The ROM itself disables the boot rainbow by poking &FF into &5600
([mainlp.asm](../mainlp.asm), after the MGT banner), so treating that table
as expendable is a sanctioned move.

### (c) Sub-range trick for a small buffer

Because the address is \((\text{HUDG}) + (\text{code}-169) \times 8\),
`HUDG` may point *outside* the buffer so that only the codes you care about
land inside it:

\[ \text{HUDG} = \text{buffer} - (\text{first code} - 169) \times 8 \]

To serve codes &F5–&FF from the 95-byte hole at &5881:
\(\&5881 - (245-169) \times 8 = \&5881 - \&260 = \&5621\). Codes below &F5
would then read rubbish from wherever &5621 onward happens to be, which is
harmless provided the program never prints them.

## Automating the change

A natural instinct is to script the whole thing as
"poke `PROG`, poke `HUDG`, `NEW`, `LOAD`". That cannot be automated, because
of `NEW` — and it also isn't necessary.

### Why `NEW` blocks automation

`NEW` shares its tail with `MNINIT` and ends by executing
`RST &08 : DB &50` ([misc31.asm:323-324](../misc31.asm#L323-L324)), the
"report" that prints the MGT copyright banner. Two things follow:

* **It waits for a physical keypress.** `ERRHAND1` handles code &50 by
  printing the banner and then spinning in `WTFK`
  ([mainlp.asm:465-466](../mainlp.asm#L465-L466)) on `READKEY`. `READKEY`
  performs a fresh two-key *hardware* scan (`TWOKSC`,
  [tadjm.asm:21](../tadjm.asm#L21)) rather than reading the keyboard queue,
  so pre-loading `KBQB`/`KBQP`/`LASTK` will not satisfy it.
* **It never returns.** Before the banner, `NEW` does
  `LD SP,ISPVAL : LD HL,MAINER : PUSH HL : LD (ERRSP),SP`, so the machine
  stack is discarded and control lands in the main editor loop. No BASIC
  statement or machine-code routine after the `NEW` will ever run — and the
  program that issued it has been erased anyway.

### `NEW` isn't needed

`LOAD` of a BASIC program already does everything `NEW` would have done to
the program area, using the *current* value of `PROG`:

1. At parse time `HDRLNOK` builds the request header from `ADDRPROG` and
   `ADDRELN`, so the "existing area" it records is
   \([\text{PROG}, \text{ELINE}-1)\) — measured **after** your poke.
2. `LDPRDT` reclaims exactly that region, zeroing `NVARSP`/`NVARS+1` first
   so the pointer adjustment behaves, and clears the BASIC stack.
3. `MKRBIG` opens the file's length at `PROG`, the block is loaded, and
   `LDPROG` rebuilds `NVARS`, `NUMEND` and `SAVARS` from the header's three
   lengths, then does `RESTORE 0` and the compile pass.

Nothing in that sequence looks below `PROG`, so the 696 bytes you vacated
survive untouched. The three-line loader in
[(a) above](#a-raise-prog-and-carve-space-below-the-program) is the whole
recipe.

### Practical cautions

* **Use an auto-run line.** With no auto-run, `LDPROG` simply `RET`s and the
  interpreter resumes from the stale `CLA`/`NXTLINE` of the *old* program —
  whose text is now sitting in the hole. Either `LOAD "nextprog" LINE n` or
  save the target with `SAVE "nextprog" LINE n`.
* **Make the `LOAD` the last statement executed**, since the loading
  program's own text is discarded by it.
* **Boot-time is the cleanest moment.** `BOOT` issues DOS hook &88 (`ALHK`,
  "load auto-load file"), so a disc's auto-load program can be a two-line
  configurator that pokes `PROG`/`HUDG` and chains to the real program. The
  machine is already in a fresh state, so `NEW` never enters the picture.
* If you do want variables cleared without touching the program, `CLEAR`
  runs `CLRSR` plus the compile pass and a `CLS` with no banner and no
  keypress.

A machine-code alternative — replicating `NEW2`'s tail (plant the &FF
terminator, set `NVARS`/`NVARSP`/`ELINEP`, `CALL CLRSR`, set `ELINE`,
`CALL SETMIN`) while skipping the banner — is possible but calls ROM0
internals that have no jump-table entries, so it is version-fragile.

## Related documents

* [font-rendering.md](font-rendering.md) — cell geometry, which bits and scans
  of a bitmap are drawn at each `CSIZE`, and dual-width font design.
* [memory-map.md](memory-map.md) — the system-page layout these regions come from.
* [constants.md](constants.md) — the raw `EQU` values.
* [source-files.md](source-files.md) — `POFUDG`, `FPUDG`, `UPACK` and `EPSUB` in context.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
