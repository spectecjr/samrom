# 10. Sound

← [Graphics](09-graphics.md) · [Contents](README.md) · [Next: Data, files and devices →](11-data-files-and-devices.md)

---

SAM has two ways of making a noise: the one-bit speaker driven by `BEEP`, and
the Philips SAA1099 six-channel sound chip driven by `SOUND`.

## 10.1 `BEEP`

```
BEEP duration, pitch
```

* **duration** is in seconds, and may be up to 16.
* **pitch** is a semitone offset from middle C. `BEEP 1,0` is middle C,
  `BEEP 1,12` is the octave above, `BEEP 1,-12` the octave below.

The frequency produced is

$$ f = 55 \times 2^{(n+27)/12} \text{ Hz} $$

— 27 semitones below middle C is the A at 55 Hz that anchors the scale.

The resulting frequency must lie between about **8 Hz and 16 kHz**, which
puts the usable pitch range at roughly −60 to +71. Outside it you get
error 49, *Invalid Note*; a duration over 16 seconds gives error 50,
*Note too long*.

```basic
10 REM a scale
20 FOR n = 0 TO 12
30   BEEP 0.2, n
40 NEXT n
```

```basic
10 REM a tune, as pairs of pitch and length
20 DATA 0,2, 2,2, 4,2, 0,2, 0,2, 2,2, 4,2, 0,2
30 DATA 4,2, 5,2, 7,4, 4,2, 5,2, 7,4
40 FOR i = 1 TO 14
50   READ p, l
60   BEEP l/8, p
70 NEXT i
```

`BEEP` runs with interrupts disabled and drives the speaker bit of the
keyboard port directly, so the timing is exact but nothing else happens while
it plays. There is no way to play a `BEEP` in the background.

## 10.2 `SOUND` — the sound chip

```
SOUND register, value [; register, value …]
```

Writes values into the SAA1099's registers. Registers are 0 to 31; values are
bytes. Up to **127** pairs may be given in one statement, and they are all
written in one burst after the whole list has been evaluated — which matters
when you are setting several registers that must change together.

An out-of-range register gives error 30; too many pairs gives error 33.

### The register map

These are the chip's own registers, not the ROM's — the ROM simply passes
values through. They are given here for convenience.

| Register | Purpose |
|---|---|
| 0–5 | Amplitude of channels 0–5. Low nibble = left, high nibble = right, 0–15 each |
| 8–13 | Frequency of channels 0–5, 0–255 within the octave |
| 16 | Octave: channel 0 in bits 0–2, channel 1 in bits 4–6 |
| 17 | Octave: channels 2 and 3 |
| 18 | Octave: channels 4 and 5 |
| 20 | Frequency enable, one bit per channel (bit 0 = channel 0) |
| 21 | Noise enable, one bit per channel |
| 22 | Noise generator control: two 2-bit fields for generators 0 and 1 |
| 24 | Envelope control for channel 2 |
| 25 | Envelope control for channel 5 |
| 28 | Bit 0 = sound enable, bit 1 = reset |

The frequency of a channel is set by an octave (0–7) and a frequency value
(0–255) together; higher values within an octave give higher pitches.

### A worked example

```basic
  10 REM one channel, one note
  20 SOUND 28, 2                : REM reset
  30 SOUND 28, 1                : REM enable
  40 SOUND 16, 4                : REM channel 0, octave 4
  50 SOUND 8, 128               : REM channel 0 frequency
  60 SOUND 20, 1                : REM enable channel 0 as a tone
  70 SOUND 0, &FF               : REM channel 0 full volume both sides
  80 PAUSE 100
  90 SOUND 0, 0                 : REM silence it
```

Because all the pairs of one statement are written together, the same thing
is more conveniently written:

```basic
20 SOUND 28,2; 28,1; 16,4; 8,128; 20,1; 0,&FF
```

### A simple three-channel chord

```basic
10 SOUND 28,2; 28,1
20 SOUND 16,&44; 17,&04        : REM octave 4 for channels 0,1,2
30 SOUND 8,101; 9,145; 10,179  : REM three pitches
40 SOUND 20,7                  : REM channels 0,1,2 as tones
50 SOUND 0,&FF; 1,&FF; 2,&FF   : REM full volume
60 PAUSE 150
70 SOUND 0,0; 1,0; 2,0
```

Unlike `BEEP`, `SOUND` returns immediately: the chip keeps playing while your
program carries on. That makes it the right choice for background music and
for effects during animation.

### Silence

Setting every amplitude register to 0 silences the chip. `NEW`, `RUN` and
`CLEAR` all do this for you.

## 10.3 The canned effects

```
ZAP
POW
BOOM
ZOOM
```

Four ready-made sound effects, all built from rapid sweeps of the speaker
period:

| Effect | Sound |
|---|---|
| `ZAP` | Six short bursts at a fixed period |
| `POW` | A percussive hit, from a table of periods |
| `BOOM` | A sweep upward |
| `ZOOM` | A sweep downward |

They take no parameters:

```basic
10 FOR i = 1 TO 3: ZAP: PAUSE 10: NEXT i
20 BOOM
30 ZOOM
40 POW
```

Like `BEEP`, they use the speaker and block until finished.

## 10.4 Turning sound off in hardware

The border port carries two bits that are not colour: bit 7 is a MIDI-through
flag and bit 6 turns the internal speaker off. `BORDCOL` (23627) keeps a copy
of the whole byte so that `SAVE`, `LOAD` and `BEEP` can restore it, preserving
those two bits.

If you need to mute the speaker without changing anything else, modify
`BORDCOL` and re-issue the `BORDER` colour it holds.

## 10.5 MIDI

The MIDI ports are at hardware address &FD, shared with the network. The ROM
provides two interrupt vectors for MIDI use:

| Vector | Offset | Purpose |
|---|---|---|
| `MIPV` | &E8 | MIDI input interrupt |
| `MOPV` | &EA | MIDI output interrupt |

There is no MIDI support in BASIC itself; using it means installing your own
handlers through those vectors (see chapter 15) and driving the port with
`IN` and `OUT`.

---

## Summary

* `BEEP length, pitch` — pitch is semitones from middle C, length in seconds
  up to 16. It blocks.
* `SOUND reg, val; reg, val; …` writes the SAA1099's registers, up to 127
  pairs at once, and returns immediately.
* `ZAP`, `POW`, `BOOM` and `ZOOM` are ready-made effects.
* Sound can be muted in hardware via bit 6 of the border port.

---

← [Graphics](09-graphics.md) · [Contents](README.md) · [Next: Data, files and devices →](11-data-files-and-devices.md)
