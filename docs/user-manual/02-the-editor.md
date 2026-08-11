# 2. The Editor and Your Environment

← [First steps](01-first-steps.md) · [Contents](README.md) · [Next: Numbers, strings and variables →](03-numbers-strings-and-variables.md)

---

Everything you type goes through the same line editor, whether you are
entering a program line, a direct command, or answering an `INPUT`. This
chapter covers the editor itself and the commands that manage your program
as a whole.

## 2.1 The editing keys

The editor reads one key at a time. Codes 7 to 15 are *editing* keys and are
acted on rather than inserted:

| Code | Key | Action |
|---|---|---|
| 7 | EDIT | Copy the current listing line into the edit buffer for editing |
| 8 | ← | Move the cursor one character left |
| 9 | → | Move the cursor one character right |
| 10 | ↓ | Move the listing cursor `>` down a line |
| 11 | ↑ | Move the listing cursor `>` up a line |
| 12 | DELETE | Delete the character to the left of the cursor |
| 13 | ENTER | Finish the line |
| 14 | (shifted DELETE) | Delete the character to the right of the cursor |
| 15 | (keypad) | Toggle the numeric keypad between function keys and digits |

Codes 16 to 21 are the colour control codes (`INK`, `PAPER`, `FLASH`,
`BRIGHT`, `INVERSE`, `OVER`). When you type one, the editor waits for the
following keystroke and stores it as the code's parameter, so an embedded
colour change is always two bytes.

The cursor sits *before* the character it is on. Because a function keyword
is stored as two bytes (`&FF` plus a code), cursor movement and deletion
treat such a pair as one character — you never end up half-way inside a
token.

The cursor character itself is taken from the system variable `KURCHAR`, and
there are two of them: one for lower case and one for upper case, so the
cursor tells you the state of CAPS LOCK.

## 2.2 Editing an existing line

The `>` marker in the listing shows the **current line**. Move it with the
up and down cursor keys, then press **EDIT**. The whole line is listed into
the edit buffer, where you can change it; press ENTER to store the modified
version.

Pretty-list indentation is turned off while a line is being edited, so what
you see is exactly what is stored.

Internally this works by printing the line through **channel R**, a
pseudo-device whose "screen" is the edit line. That is also how `AUTO`
pre-types the next line number.

## 2.3 Automatic line numbering — `AUTO`

```
AUTO [line [, step]]
```

Turns on automatic numbering. After each line you enter, the next number is
typed in for you.

```basic
AUTO 100,10
```

With no parameters, `AUTO` continues from the current line plus ten.

The step must not be greater than the starting line (the ROM sets the current
line to *line* − *step* and would otherwise underflow).

`AUTO` does not return to the caller — it re-enters the main loop directly —
so it cannot usefully be followed by another statement on the same line.
Press ENTER on an empty line to stop.

## 2.4 Deleting and renumbering

```
DELETE [first] [TO [last]]
RENUM  [first] [TO [last]] [LINE n] [STEP m]
```

`DELETE 100 TO 200` removes a range of lines in a single operation. Both ends
are optional: `DELETE TO 50` deletes everything up to line 50, `DELETE 900 TO`
deletes from 900 to the end. `DELETE 100` on its own deletes just line 100.
An inverted range such as `DELETE 20 TO 10` does nothing.

`RENUM` renumbers the program. `LINE` gives the new starting number and
`STEP` the increment; both default to 10.

```basic
RENUM
RENUM 500 TO 900 LINE 1000 STEP 5
```

`RENUM` also rewrites every **reference** to a line number — in `GOTO`,
`GOSUB`, `RESTORE`, `RUN`, `LIST`, `DELETE`, `SAVE … LINE` and so on. It
needs about 6K of free memory to build its translation table and will refuse
if there is less.

> `RENUM` handles `LINE` carefully: `LINE` only counts as introducing a line
> number when it follows a closing quote or a `$`, as in `SAVE "x" LINE 10`.
> `INPUT LINE a$` and `PALETTE 1,7 LINE 100` are left alone.

## 2.5 Listing

```
LIST [#stream] [,|;] [first] [TO [last]]
LIST FORMAT n
LLIST …
```

`LIST` sends to the screen (stream 2), `LLIST` to the printer (stream 3), and
`LIST #4;100 TO 200` to whatever stream 4 is attached to.

The first line listed becomes the current line, so `LIST 500` followed by
EDIT is a quick way to reach a distant line.

**`LIST FORMAT n`** (*n* = 0, 1 or 2) controls the pretty-lister. It adds *n*
columns of indent for each level of nesting — `FOR`/`NEXT`, `DO`/`LOOP`,
`IF`/`END IF`, `DEF PROC`/`END PROC` — and puts each statement of a
multi-statement line on its own screen line. `LIST FORMAT 0` restores plain
listing. Anything other than 0–2 gives error 30.

The indentation is applied at listing time only; it is never stored.

## 2.6 The scroll prompt

When a listing (or any output) fills the screen, SAM stops and asks
`scroll?`. Press a key to continue, or `N`/ESCAPE to abandon.

```basic
SCROLL CLEAR      : REM suppress the prompt
SCROLL RESTORE    : REM re-enable it
```

These two forms of `SCROLL` do not touch the screen at all — they only set
the suppression flag. (The other forms of `SCROLL` scroll the display; see
chapter 8.)

## 2.7 The keyboard: keys, codes and definitions

Three separate mechanisms sit between a physical key and what your program
sees.

### The key map — `KEY`

```
KEY position, value
```

The keyboard is a matrix of 69 keys read in three shift states (CAPS SHIFT,
SYMBOL SHIFT, CONTROL), giving a translation table of 280 positions. `KEY`
rewrites one entry, so you can make any key produce any code.

Positions run 1 to 280 (position 0 exists but is unused).

### Key definitions — `DEF KEYCODE`

```
DEF KEYCODE n, a$
DEF KEYCODE n : rest-of-line
```

Any code from **192 upwards** may be given an expansion. When the editor
receives that code it inserts the definition instead. The definition may
contain tokens, so a single key can type a whole command.

The second form takes everything after the colon to the end of the line as
the definition, which is the convenient way to include keywords:

```basic
DEF KEYCODE 202: PRINT "Hello ";
```

The definitions live in a buffer at `DKBU` whose growth limit is `DKLIM`;
overflowing it gives error 52, *Too many definitions*.

The function keys F0–F9 produce codes 192–201 and are pre-defined at
switch-on:

| Key | Code | Definition |
|---|---|---|
| F0 | 192 | `LIST` |
| F1 | 193 | `RENUM :` |
| F2 | 194 | `PRINT :` |
| F3 | 195 | `MODE :` |
| F4 | 196 | `RUN` |
| F5 | 197 | `CONTINUE` |
| F6 | 198 | `CLS #` |
| F7 | 199 | `LOAD ""` |
| F8 | 200 | `LOAD "" CODE` |
| F9 | 201 | `BOOT` |

Three more definitions are installed for the TAB key (code 252 → comma tab)
and the shifted forms (253, 254 → `INVERSE 1` and `INVERSE 0`).

### Key repeat

Two system variables control auto-repeat, both in frames (fiftieths of a
second):

| Variable | Address | Default | Meaning |
|---|---|---|---|
| `REPDEL` | 23561 | 33 | Delay before a held key first repeats |
| `REPPER` | 23562 | 3 | Delay between subsequent repeats |

```basic
POKE 23561,10 : POKE 23562,1   : REM fast repeat
```

### The keypad

Code 15 toggles the numeric keypad between producing function-key codes and
producing digits. The current state is in `KPFLG` (23655): even selects
function keys, odd selects digits.

## 2.8 The type-ahead queue

Keys are buffered eight deep in `KBQB`. `INKEY$` reads the keyboard directly
(performing a fresh scan, so a key released before the call is *not*
reported), whereas `GET` and `INPUT` take keys from the queue. The jump-table
routine `KBFLUSH` empties it.

## 2.9 Managing the program itself

| Command | Effect |
|---|---|
| `NEW` | Erase program, variables, screens and definitions; reset everything |
| `CLEAR` | Erase variables and stacks, keep the program |
| `CLEAR n` | As above, and move `RAMTOP` to address *n* |
| `RUN` | `CLEAR` + `RESTORE` + start at the first line |
| `RUN n` | The same, starting at line *n* |
| `CONTINUE` | Resume from where the program last stopped |
| `KEYIN a$` | Execute the string *a$* as though it had been typed |

`KEYIN` is how a program modifies itself:

```basic
10 LET n = 500
20 KEYIN STR$ n + " PRINT ""generated line"""
```

The string is tokenised and syntax-checked exactly as typed input would be,
so it may create program lines as well as run commands.

## 2.10 Screen blanking

If nothing happens for a while the ROM blanks the screen to protect the
display. `SOFE` (system variable at offset &32) enables the timer: a value of
0 permits blanking, non-zero prevents it.

```basic
POKE SVAR &32, 1   : REM never blank the screen
```

---

## Summary

* The `>` cursor plus **EDIT** is how you change an existing line.
* `AUTO`, `DELETE` and `RENUM` manage line numbers.
* `LIST FORMAT 1` or `2` gives you indented, one-statement-per-line listings.
* `KEY` changes what a key produces; `DEF KEYCODE` changes what a code
  expands to; the function keys are just codes 192–201 with pre-set
  definitions.
* `KEYIN` lets a program write and run BASIC at run time.

---

← [First steps](01-first-steps.md) · [Contents](README.md) · [Next: Numbers, strings and variables →](03-numbers-strings-and-variables.md)
