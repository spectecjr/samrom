# Keyboard Scanning, Debouncing and Auto-Repeat

How the ROM gets from a key matrix reading to a character in `LASTK`: the
nine-row scan, the edge detection that makes rollover work, the two-deep
history that debounces a press, the auto-repeat interlocks, and the
type-ahead queue that everything downstream reads from — plus why the mouse
has to be dealt with first, since it shares a port with the ninth row.

Sources: [scrsel1.asm](../scrsel1.asm) (`FRAMINT`, `KEYRD2`, `KINTER`,
`KYVL`, `TWOKSC`, `KEYSCAN`), [tadjm.asm](../tadjm.asm) (`GETKEY`,
`READKEY`, `KBFLUSH`, `KEYRD`), [editor.asm](../editor.asm) (`KYIP`,
`KYIP2`, `KYPM`, `GTKBK`, `WKBR`, `WAITKEY`),
[mainlp.asm](../mainlp.asm) (`BRKTST`), [misc31.asm](../misc31.asm)
(cold-start table copy).

## The pipeline

Everything is driven from the 50 Hz frame interrupt. Nothing polls the
hardware in the foreground except `INKEY$` and the BREAK test.

```text
FRAMINT (50Hz)
 ├─ INTS3/INTS4       mouse first: the driver, or nine reads of the shared port
 └─ KEYRD2
     ├─ KINTER
     │   ├─ KEYSCAN   read 9 rows; keep only 1->0 changes; (row,bit) -> scan code
     │   ├─ NLASTH    3-deep code history: new press, or the same key still held?
     │   ├─ REPCT     REPDEL / REPPER countdown, plus the repeat interlocks
     │   ├─ KYVL      scan code + shift state -> character, via KTAB
     │   └─ KBQB      append to the 8-byte type-ahead queue
     └─ LASTK         one character per frame, gated by FLAGS bit 5

GETKEY / KYIP / WAITKEY  read LASTK        (queued, type-ahead honoured)
READKEY (INKEY$)         calls TWOKSC      (live hardware, queue bypassed)
BRKTST  (ESC/BREAK)      reads port &F7FE  (live hardware, queue bypassed)
```

## The matrix

`KEYSCAN` reads **nine rows of eight bits** into `KBUFF`
([vars.asm:406](../vars.asm#L406), `VAR2+&01EE`, 18 bytes):

| Row (`B`) | Port | Bits 4-0 | Bits 7-5 |
|---|---|---|---|
| 1 | &FEFE | `KEYPORT` (&FE) | `STATPORT` (&F9) |
| 2-8 | &FDFE … &7FFE | `KEYPORT` | `STATPORT` |
| 9 | &FFFE | `KEYPORT` | — (forced high) |

SAM has eight keys per row where the Spectrum had five, so each row is
assembled from two ports read at the same address: bits 4-0 come from
`KEYPORT` and bits 7-5 from `STATPORT`, merged by the
`XOR E` / `AND D` / `XOR E` sequence at [KBSL](../scrsel1.asm). Row 9 is the
special port &FFFE, where only bits 4-0 are meaningful — `OR &E1` forces the
rest high.

`KBUFF` is two nine-byte halves: bytes 0-8 hold the current scan, bytes 9-17
the previous one.

### Bits that never reach the scanner

Four bits are forced high before change detection, so they can never be
reported as a key press:

| Key | Location | Read instead by |
|---|---|---|
| CAPS SHIFT | row 1, bit 0 | `KBSH`, port &FEFE |
| ESC | row 4, bit 5 | `BRKTST` ([mainlp.asm:353](../mainlp.asm#L353)), port &F7FE |
| SYMBOL SHIFT | row 8, bit 1 | `KBSH`, port &7FFE |
| CONTROL | row 9, bit 0 | `KBSH`, port &FFFE |

Pressing a shift key on its own therefore produces nothing. ESC is polled
directly by the BREAK test rather than queued, which is why BREAK works even
when the queue is full or a program is not reading keys.

## Sharing port &FFFE with the mouse

Row 9 is not only a keyboard row. The mouse interface answers at the same
address, and the ROM reads it with `IN A,(KEYPORT)` — the `IN A,(n)` form,
which puts **A** on the high address lines, so `A = &FF` selects &FFFE
exactly as `B = &FF` does in `KEYSCAN`.

The interface is sequential: each read returns the next item of a packet and
steps an internal pointer, so reading it has a side effect. That means
**every keyboard scan touches the mouse**, once per scan, as row 9.

### The frame interrupt orders them

[FRAMINT](../scrsel1.asm) deals with the mouse first and the keyboard last,
so a driver always gets its run of reads before `KEYSCAN` disturbs the port:

```asm
INTS3:  LD HL,(MOUSV)     ; is a mouse driver installed?
        DEC H
        LD A,H            ; if not, this leaves A = &FF, ready to address &FFFE
        INC H
        JR NZ,INTS4       ; H non-zero: hand the whole job to the driver

        IN A,(KEYPORT)    ; read 1 of 9, discarded
        LD HL,MSEDP
        LD B,8            ; READ MOUSE 9 TIMES TO CANCEL IT

MSDML:  LD A,&FF
        IN A,(KEYPORT)    ; reads 2-9, stored at MSEDP..MSEDP+7
        LD (HL),A
        INC HL
        DJNZ MSDML

INTS4:  CALL NZ,HLJUMP    ; ...or call the driver, which does its own reading
INTS5:  CALL KEYRD2       ; only now is the keyboard scanned
```

The `DEC H` / `LD A,H` / `INC H` dance does two jobs at once. `INC H` sets
the flags that both branches test — `Z` means `MOUSV` had a zero high byte,
so no driver — and on that path it leaves `A = &FF`, which is precisely the
value the first `IN A,(KEYPORT)` needs to address &FFFE. The same `NZ` then
survives to gate `CALL NZ,HLJUMP` at `INTS4`.

### Why the ROM reads a mouse it cannot use

The ROM has no mouse driver. `MOUSV` (23292) is a user vector, and
`MXCRD`, `MYCRD` and `BUTSTAT` — the variables behind `XMOUSE`, `YMOUSE` and
`BUTTON` — are **never written anywhere in the ROM**. Filling them is
entirely the driver's job.

So the nine reads on the driverless path exist only to undo the keyboard's
interference. Left alone, `KEYSCAN` would step the interface once per frame,
from an arbitrary starting phase, and the first driver to attach would find
it partway through a packet. Reading it nine times returns it to a known
state every frame, so a driver installed at any moment starts from a defined
position — hence the original comment, "READ MOUSE 9 TIMES TO CANCEL IT".

One side effect is worth knowing about: the loop stores reads 2-9 at
`MSEDP`…`MSEDP+7`, and `BUTSTAT` is `MSEDP+1`. On the driverless path
`BUTTON` therefore reports bits taken from the third raw read of the
interface rather than from anything that has been interpreted. `XMOUSE` and
`YMOUSE` return whatever `MXCRD`/`MYCRD` last held, which without a driver is
never updated at all.

### How the two avoid colliding

The scanner throws away most of row 9. `OR &E1` sets bits 7, 6, 5 and 0, so
only **bits 4-1** of &FFFE are read as keys, with CONTROL (bit 0) picked up
separately by `KBSH`.

That does not by itself resolve the overlap: `BUTSTAT` is documented as
carrying "bits 2-0 set for buttons 3-1", and bits 2 and 1 are two of the four
bits the scanner does keep. If the interface presented button data
continuously, a mouse click would read as a phantom keypress.

> **Inference, not documented in the source.** For the two to coexist, the
> interface has to return an idle value on the row-9 bits the scanner keeps,
> and only present packet data during a rapid burst of reads — resetting
> itself once reads stop for long enough. That is also the only reading under
> which "nine reads cancel it" makes sense as a way of restoring a known
> state. The ROM source neither states the timeout nor names which bits carry
> what; it only shows the ordering and the burst.

### Consequences for keyboard code

* **Foreground scans read the mouse port too.** `INKEY$` goes through
  `TWOKSC`, which calls `KEYSCAN` **twice** and so hits &FFFE twice more.
  Any machine-code routine calling `KEYSCAN` does the same.
* **A tight `INKEY$` loop is the pathological case.** It reads &FFFE
  continuously, outside the interrupt's ordering, in the gap the interface
  needs in order to resynchronise. A mouse driver polling from `MOUSV` shares
  the port with that traffic.
* **Scanning into private storage does not help.** Entering at `KEYSCAN+3`
  with `HL` pointing at your own 18-byte buffer changes where the results are
  written, not which ports are read.
* **The mouse has no interrupt of its own.** The interrupt formerly assigned
  to it is now the COMs interrupt — the source still labels it
  `COMS (EX MOUSE) INTERRUPT` — so mouse handling is polled from `FRAMINT`
  at 50 Hz and nothing else.

## Edge detection: the first debounce layer

The scanner reports **transitions, not levels**. For each row,
[KBCL](../scrsel1.asm) does:

```asm
LD A,(DE)   ; this scan
LD C,(HL)   ; last scan
LD (HL),A   ; last scan := this scan
XOR C       ; bits that changed
CPL         ; changes become 0s
OR (HL)     ; keep as 0 only where the change was 1->0 (pressed)
LD (DE),A   ; 'changed' data replaces the current scan
```

Per bit, writing 1 for "up" and 0 for "down" as the hardware does:

| Last | This | Result | Meaning |
|---|---|---|---|
| 1 | 1 | 1 | still up — ignored |
| 1 | **0** | **0** | newly pressed — reported |
| 0 | 1 | 1 | released — ignored |
| 0 | 0 | 1 | still held — ignored |

Two consequences fall straight out of this:

* A key held down produces **exactly one** event, however many frames it
  stays down. Auto-repeat is therefore entirely a software construct, not a
  by-product of the key still reading low.
* A second key pressed while the first is still held **is** noticed, because
  its bit changed even though the first key's did not. That is where
  two-key rollover comes from.

If no bit changed anywhere, [KBAKL](../scrsel1.asm) checks whether anything
is still down; if so it re-reports the previous code from `LASTKV`, and if
the whole matrix is clear it returns NZ (no key).

### Scan codes

[KBYK](../scrsel1.asm) converts the (row, bit) of the changed bit into a
scan code:

```text
code = bit * 9 - row        bit = 1 (bit 7) .. 8 (bit 0)
                            row = 1 (&FEFE) .. 9 (&FFFE)
```

giving 0-71 (&00-&47) — codes run down a *column* of the matrix, nine apart,
not along a row. The raw (row, bit) pair is also saved in `LKPB` (&5C03) for
the auto-repeat still-held check below. `KBENTERCODE` = 65 is ENTER, which
works out as bit 0 of port &BFFE — the same place the Spectrum put it.

A key press also zeroes `SOFFCT`, cancelling the 22-minute screen blanker and
turning the display back on if it had blanked.

### Shift state

[KBSH](../scrsel1.asm) then reads the three shift keys directly and reports
**one** of them, in strict precedence order:

| Order | Key | `D` | Equate |
|---|---|---|---|
| 1st | CAPS SHIFT | 1 | `KBSHCAPS` |
| 2nd | CONTROL | 3 | `KBSHCTRL` |
| 3rd | SYMBOL SHIFT | 2 | `KBSHSYM` |
| — | none | 0 | `KBSHNONE` |

CAPS SHIFT wins over everything, so CAPS+SYMBOL+key gives the caps-shifted
character. The pair is stored in `LASTKV` (&5C06) as E = scan code,
D = shift state.

## The debounce proper: `NLASTH`

`NLASTH` (&5C56, 3 bytes) is a shift register of the last three scan codes.
[KINTER](../scrsel1.asm) compares each new code against it:

| Comparison | Verdict |
|---|---|
| matches entry 1 | same key held → auto-repeat path |
| matches entry 2 | same key held → auto-repeat path |
| matches entry 3 — **ENTER only** | same key held → auto-repeat path |
| matches nothing | new press → queue it, reload `REPCT` from `REPDEL` |

[LDLH](../scrsel1.asm) pushes an entry only on two of those outcomes: a
frame with **no key at all** pushes zero, and a **newly queued press** pushes
its scan code. The auto-repeat path returns before reaching `LDLH`, so
holding a key freezes the history rather than filling it with copies of the
same code.

That is what makes the two-deep comparison a debounce. A contact that breaks
and re-makes re-arms the edge detector and produces a second "press" event a
frame or two later; because the intervening quiet frames each pushed a zero,
the bouncing code is still sitting in entry 1 or entry 2 and the event is
absorbed as "still held":

| Frame | Event | `NLASTH` after | Result |
|---|---|---|---|
| *n* | press, code X | `X 0 0` | queued |
| *n+1* | bounce, code X | `X 0 0` (unchanged) | matches entry 1 — suppressed |
| *n+2* | nothing | `0 X 0` | — |
| *n+3* | bounce, code X | `0 X 0` (unchanged) | matches entry 2 — suppressed |
| *n+4* | nothing | `0 0 X` | — |
| *n+5* | bounce, code X | `X 0 0` | **queued as a new press** (ENTER: still suppressed) |

So a key is protected against re-triggering for roughly **two idle scans**,
40 ms — and ENTER, checked against all three entries
([scrsel1.asm:836-840](../scrsel1.asm#L836-L840)), for three, 60 ms.

The original source justifies the extra check only with "PRONE TO STUTTER".
The reason is physical: ENTER is a large L-shaped keycap, so it can be
pressed well off-centre from its single switch, and the resulting rocking
makes its contact bounce longer and more erratically than the small square
keys. It is the one key whose mechanics warrant a wider window.

> The history holds *scan codes*, not (row, bit) pairs, and it advances on
> any new press. Pressing a different key in between therefore pushes the
> bouncing key's code along and can let it back through early.

## Auto-repeat

Once a code has matched the history, three interlocks stand between it and a
repeated character:

1. **`REPCT` (&5C05) must reach zero.** It counts down one per frame,
   loaded with `REPDEL` (&5C09) after the initial press and with `REPPER`
   (&5C0A) after each repeat. The cold start sets them to
   **33 and 3** frames ([misc31.asm:344](../misc31.asm#L344)) — about 0.66 s
   before the first repeat, then roughly 17 characters per second.
2. **The key must still physically be down.** The saved `LKPB` (row, bit) is
   used to index the raw current-scan half of `KBUFF` and rotate that bit into
   carry; carry set means up, and the repeat is abandoned. This catches the
   case where the history matches but the code in fact came from somewhere
   else.
3. **No character may already be waiting.** If `FLAGS` bit 5 (`FFLAGKEY`) is
   set, the program has not yet read the previous character and the repeat is
   dropped rather than queued.

Interlock 3 is what stops a held key from stuffing the ring buffer with a
burst that would keep arriving for seconds after you let go. `REPCT` is
*incremented* to 1 between interlocks 2 and 3, so a repeat blocked by an
unread character is retried on the very next frame rather than waiting
another full `REPPER`. A repeat blocked by interlock 2 leaves `REPCT` at
zero, but the key is by then released, so the history stops matching and the
next press reloads `REPDEL` anyway.

Both timings are ordinary system variables and can be poked:

```basic
POKE 23561,10: REM REPDEL - first repeat after 0.2s
POKE 23562,1:  REM REPPER - repeat every frame (50/sec)
```

## Translation to a character

[KYVL](../scrsel1.asm) turns (scan code, shift state) into a character.
`KBTAB` (`VAR2+&01D8`) points at the unshifted plane; the caps, symbol and
control planes follow at `KBSHIFTTAB` = 70-byte intervals, so the shift state
selects one by repeated addition of 70:

| Plane | Offset from `KBTAB` | Positions |
|---|---|---|
| Unshifted | +0 | 1-70 |
| CAPS SHIFT | +70 | 71-140 |
| SYMBOL SHIFT | +140 | 141-210 |
| CONTROL | +210 | 211-280 |

Position 0 exists but is unreachable — scan code 0 is bit 7 of row 9, one of
the bits forced high.

The planes live in RAM at `KTAB` (&58E0), set up by the cold start
([misc31.asm:224-231](../misc31.asm#L224-L231)): the first three are copied
from `KSRC` ([text.asm:1213](../text.asm#L1213)) with a single 210-byte
`LDIR`, and the CONTROL plane is left blank apart from a handful of values
scattered in from `CKTAB` by `PBSL`. Positions in `KSRC` that are not keys —
or that are one of the separately-scanned shifts — are marked `X` in the
source listing.

Because the table is in RAM, any key can be redefined from BASIC with
`KEY position, value` ([misc32.asm:281](../misc32.asm#L281)), which accepts
positions 1-280 and pokes the byte directly. Codes 192-201 and 252-254 in the
stock table are `DEF KEY` codes, expanded to strings by the editor rather
than printed.

**Caps lock is applied afterwards, not by table.** `FLAGS2` bit `FFL2CAPS`
causes `AND &DF` to be applied, but only to characters that pass the `ALPHA`
test — so caps lock affects letters only, and leaves digits and punctuation
alone.

## The type-ahead queue

| Variable | Address | Purpose |
|---|---|---|
| `KBQB` | &5C8D | 8-byte circular queue (`KBQSIZE` = 8) |
| `KBQP` | &5C95 | Displacements into it: low byte = tail (where the scanner writes), high byte = head (where the reader takes) |
| `LASTK` | &5C08 | The one character currently handed to the foreground |
| `FLAGS` bit 5 | &5C3B | `FFLAGKEY` — set when `LASTK` holds an unread character |

Head equal to tail means empty; the tail wraps through `KBQMASK` and the
queue is declared full when advancing the tail would make it equal the head,
so the usable depth is **seven** characters.

[KEYRD2](../scrsel1.asm) moves at most **one character per frame** out of the
queue into `LASTK`, and only if `FFLAGKEY` is clear. So the ceiling on
sustained input is 50 characters per second regardless of how fast the queue
was filled — the buffer absorbs bursts, it does not raise the rate.

## Who reads what

| Routine | Where | Reads | Notes |
|---|---|---|---|
| `KYIP` / `KYIP2` | [editor.asm:671](../editor.asm#L671) | `LASTK` | The keyboard channel input routine. Consumes `FFLAGKEY`; codes &10-&15 redirect the channel to `KYPM` to validate the following colour parameter |
| `WAITKEY` | [editor.asm:642](../editor.asm#L642) | via the channel | Loops on the channel's input routine until a key arrives |
| `GTKBK` / `WKBR` | [editor.asm:625](../editor.asm#L625) | via `KYIP2` | Wait for a key with BREAK checking. `GTKBK` flushes first, so a key pressed earlier cannot satisfy the wait |
| `GETKEY` / `KEYRD` | [tadjm.asm:50](../tadjm.asm#L50) | `LASTK` | Scan, then return the queue head or zero |
| `READKEY` | [tadjm.asm:65](../tadjm.asm#L65) | hardware | Jump table &0169; what `INKEY$` uses |
| `KBFLUSH` | [tadjm.asm:79](../tadjm.asm#L79) | — | Jump table &0166; zeroes `KBQP` and clears `FFLAGKEY` |
| `BRKTST` | [mainlp.asm:353](../mainlp.asm#L353) | hardware | Reads the ESC bit of port &F7FE directly |

### Why `INKEY$` behaves differently

`READKEY` calls `TWOKSC`, which performs a **fresh hardware scan** and
bypasses the queue entirely. Two consequences:

* A key that has already been released is not reported, so `INKEY$` misses
  keystrokes that a `GET`-style read would have caught from the queue.
* Pre-loading the queue cannot satisfy an `INKEY$`, which is why the usual
  trick of poking characters into `KBQB` to drive a program works for `INPUT`
  but not for `INKEY$`.

`TWOKSC` scans **twice** — the first scan may have had its change information
consumed by an interrupt that fired between the two, since the interrupt
handler is also running `KEYSCAN` against the same `KBUFF`. The second scan
sees the state the interrupt left behind.

> `KEYSCAN` can be entered at `KEYSCAN+3` with `HL` pointing at a different
> 18-byte buffer, to scan into private storage instead of the system `KBUFF`.
> That is the clean way for a machine-code program to read the matrix without
> fighting the interrupt handler.

## Related documents

* [constants.md](constants.md) — `KBQSIZE`, `KBROWS`, `KBSHIFTTAB`, `KBENTERCODE` and the shift-state equates.
* [memory-map.md](memory-map.md) — where `KTAB`, `KBUFF` and `KBQB` sit in the system page.
* [source-files.md](source-files.md) — `FRAMINT`, `KINTER` and `KEYSCAN` in the context of the rest of [scrsel1.asm](../scrsel1.asm).
* [user-manual/02-the-editor.md](user-manual/02-the-editor.md) — the editor's key handling and `DEF KEY` from the user's side.
* [user-manual/14-system-variables.md](user-manual/14-system-variables.md) — `REPDEL`, `REPPER`, `LASTK` and `FLAGS` as user-facing variables.
* [extending-basic.md](extending-basic.md#38-diverting-existing-behaviour) — `MOUSV` and the rest of the divertible vectors, and how to install one.

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
