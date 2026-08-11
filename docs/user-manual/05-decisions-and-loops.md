# 5. Decisions and Loops

← [Expressions and operators](04-expressions-and-operators.md) · [Contents](README.md) · [Next: Procedures and functions →](06-procedures-and-functions.md)

---

SAM BASIC has a full set of structured control statements. You can write
substantial programs without a single line number in them — `GOTO` is
available, but you rarely need it.

## 5.1 `IF` — the short form

```
IF condition THEN statement [: ELSE statement]
```

Everything after `THEN` is on one line. If the condition is false, execution
skips to the `ELSE` on the same line, or to the next line if there is none.

```basic
10 IF x = 1 THEN PRINT "one"
20 IF x = 1 THEN PRINT "yes": ELSE PRINT "no"
30 IF a > b THEN LET big = a: ELSE LET big = b
```

Note the colon before `ELSE`: `ELSE` is a statement in its own right, so it
needs a statement separator in front of it.

`THEN` may be followed by several statements:

```basic
40 IF ready THEN PRINT "go": LET n = n+1: BEEP 1,0
```

All of them are part of the `THEN` branch, and all are skipped when the
condition is false.

## 5.2 `IF` — the block form

```
IF condition
  statements
[ELSE IF condition
  statements]
[ELSE
  statements]
END IF
```

Written on one line with colons, or across several lines. The distinguishing
feature is simply the **absence of `THEN`**:

```basic
100 IF score > 100
110   PRINT "Excellent"
120   LET level = level + 1
130 ELSE IF score > 50
140   PRINT "Not bad"
150 ELSE
160   PRINT "Try again"
170 END IF
```

`ELSE IF` chains as many times as you like. `END IF` is compulsory in the
block form; omitting it gives error 39, *Missing END IF*.

> **How SAM tells them apart.** The tokeniser cannot: both spellings are just
> `IF`. The syntax checker rewrites the stored token to the short form when it
> finds a `THEN` on the same statement, and rewrites `ELSE` to match. Both
> forms list identically, so the distinction is invisible.

Because `END IF` is found by searching forward at run time, a block `IF`
whose condition is false costs a program scan. In a hot loop, prefer the
short form or restructure.

## 5.3 `FOR` and `NEXT`

```
FOR variable = start TO limit [STEP step]
  …
NEXT variable
```

```basic
10 FOR i = 1 TO 10
20   PRINT i;" ";
30 NEXT i
40 FOR x = 10 TO 1 STEP -1: PRINT x: NEXT x
50 FOR t = 0 TO 1 STEP 0.1: PLOT t*100, 50: NEXT t
```

The control variable must be a **simple numeric variable** — not a string,
not an array element. `NEXT` requires the variable name; a bare `NEXT` is not
accepted.

The variable's record is extended to hold the limit, the step and the address
to loop back to, so a `FOR` variable takes 14 bytes more than an ordinary
numeric. You can read the control variable inside the loop, and after the
loop it holds the first value that failed the test.

If no iteration is possible at all — `FOR i = 5 TO 1` with a positive step —
the loop body is skipped entirely by searching forward for the matching
`NEXT`. If there is none you get error 6, *FOR without NEXT*. A `NEXT` whose
variable is not currently a `FOR` variable gives error 5, *NEXT without FOR*.

Whole-number loops take an integer fast path; a fractional `STEP` forces
floating-point arithmetic for every iteration. `FOR i = 0 TO 100` is
noticeably faster than `FOR i = 0 TO 10 STEP 0.1`.

## 5.4 `DO` and `LOOP`

This is SAM's general-purpose loop, and the one to reach for by default.

```
DO   [WHILE condition | UNTIL condition]
  …
LOOP [WHILE condition | UNTIL condition]
```

The condition may be at the top, at the bottom, both, or neither:

```basic
10 REM count to ten
20 LET n = 0
30 DO
40   LET n = n + 1
50   PRINT n
60 LOOP UNTIL n = 10

100 REM read until end of data
110 DO WHILE ITEM
120   READ a$
130   PRINT a$
140 LOOP

200 REM forever, exited from inside
210 DO
220   LET k$ = INKEY$
230   EXIT IF k$ = "q"
240 LOOP
```

### Leaving and repeating early

| Statement | Effect |
|---|---|
| `EXIT IF condition` | If true, leave the loop immediately (continue after the `LOOP`) |
| `LOOP IF condition` | If true, go back to the `DO` immediately |

Both discard the loop's stack frame correctly, so it is safe to use them
inside nested loops and procedures.

```basic
10 DO
20   INPUT "Number (0 to stop): "; n
30   EXIT IF n = 0
40   LOOP IF n < 0                 : REM ignore negatives, ask again
50   PRINT n; " squared is "; n*n
60 LOOP
```

A `LOOP` with no matching `DO` gives error 10; a `DO` whose `LOOP` cannot be
found gives error 9.

## 5.5 `GOTO`, `GOSUB` and `RETURN`

```
GOTO line
GOSUB line
RETURN
```

`GOSUB` remembers where it was and `RETURN` goes back to the statement after
the call. A `RETURN` with nothing stacked gives error 8.

Both accept an **expression**, not just a constant:

```basic
GOTO 100 + section*10
```

and both have a computed form:

```
GOTO ON expression ; line, line, line …
GOSUB ON expression ; line, line, line …
```

```basic
10 GOTO ON choice; 100, 200, 300, 400
```

The expression selects the first, second, third … line in the list. If it is
out of range, execution simply falls through to the next statement — no
error. That makes it easy to write a default case:

```basic
10 GOSUB ON choice; 1000, 2000, 3000
20 REM reached when choice was not 1, 2 or 3
30 PRINT "Unknown option"
```

The frame recorded by `GOSUB` holds the address of the line and the statement
number, not a raw pointer into the text, so returning still works if the
program has been edited in between.

## 5.6 `ON` — computed statements

```
ON expression : statement : statement : …
```

Selects the *n*'th of the statements that follow on the same line and runs
just that one; the rest of the line is then abandoned.

```basic
10 ON state: PRINT "idle": PRINT "running": PRINT "done"
```

A `GOTO` as the selected statement simply jumps. A `GOSUB` or a procedure
call returns to the statement *after* the whole `ON` — which is the useful
behaviour, and takes some care internally to arrange.

## 5.7 `LABEL` — naming a line

```
LABEL name
```

`LABEL` does nothing at run time. When the program is compiled — which
happens automatically before every `RUN` — each label's line number is
assigned to the named numeric variable. You then jump to the variable:

```basic
10 GOTO mainloop
20 REM ...
1000 LABEL mainloop
1010 PRINT "here"
1020 GOTO mainloop
```

Because the labels are re-resolved on every run, they survive `RENUM`,
insertion and deletion. Combined with `DEF PROC` (chapter 6), they let you
write programs in which no literal line number ever appears.

## 5.8 `POP` — discarding a stack frame

```
POP [numeric-variable]
```

Removes the top entry of the BASIC stack — whichever kind it is: `DO`,
`GOSUB` or `PROC`. If you give a variable, the line number the frame referred
to is assigned to it. For a `PROC` frame, that procedure's local variables are
discarded too.

This is the escape hatch for leaving a subroutine or a loop from somewhere
awkward:

```basic
1000 REM a subroutine that sometimes gives up
1010 IF error THEN POP: GOTO 9000
1020 RETURN
```

An empty stack gives error 11, *No POP data*.

## 5.9 Stopping, pausing and continuing

| Statement | Effect |
|---|---|
| `STOP` | Halt with report 16, *STOP statement* |
| `PAUSE n` | Wait *n* frames (fiftieths of a second), or until a key is pressed |
| `PAUSE 0` | Wait for a key, with no time limit |
| `CONTINUE` | Resume from where the program stopped |

`CONTINUE` uses `OLDPPC`/`OSPPC`, which record the line and statement of the
last stop. After a `BREAK` during I/O (report 14) the *same* statement is
re-run; after a stop between statements (report 15) execution resumes at the
next one.

Pressing **ESCAPE/BREAK** is checked between statements. To make a critical
section uninterruptible, set the `BREAKDI` system variable (offset &141)
non-zero:

```basic
POKE SVAR &141, 1     : REM BREAK disabled
POKE SVAR &141, 0     : REM BREAK enabled again
```

`PAUSE` counts only genuine frame interrupts — line interrupts and MIDI
interrupts also wake the processor but do not decrement the counter, so the
timing stays right even with a busy palette-change list.

## 5.10 The BASIC stack

`DO`, `GOSUB` and `PROC` all share one stack. It grows downwards from
`BASSTK` towards the heap; running the two together gives error 41, *BASIC
stack full*. Each frame is four bytes, so the limit is generous — but
unbounded recursion will find it.

Frames are typed, and each return statement will only unstack a frame of the
matching type. That is how the ROM tells `LOOP without DO` from `RETURN
without GOSUB`.

## 5.11 A worked example

```basic
  10 REM Guess the number
  20 RANDOMIZE
  30 LET secret = RND(99) + 1
  40 LET tries = 0
  50 DO
  60   INPUT "Guess (1-100): "; g
  70   LET tries = tries + 1
  80   IF g < 1 OR g > 100
  90     PRINT "Out of range"
 100     LOOP IF 1
 110   END IF
 120   IF g < secret
 130     PRINT "Too low"
 140   ELSE IF g > secret
 150     PRINT "Too high"
 160   ELSE
 170     PRINT "Got it in "; tries; " tries!"
 180     EXIT IF 1
 190   END IF
 200 LOOP
```

`EXIT IF 1` and `LOOP IF 1` are the idiomatic unconditional forms.

---

## Summary

* `IF … THEN` is the one-line form; `IF` with no `THEN` opens a block that
  `END IF` closes, with `ELSE` and `ELSE IF` in between.
* `DO`/`LOOP` takes `WHILE` or `UNTIL` at either end; `EXIT IF` and `LOOP IF`
  break out or repeat early.
* `FOR`/`NEXT` needs a simple numeric variable, named on the `NEXT`.
* `GOTO ON x; …` and `GOSUB ON x; …` are computed jumps that fall through
  when the index is out of range.
* `LABEL` gives lines names so you never have to write a line number.
* `POP` discards any kind of stack frame; `CONTINUE` resumes after a stop.

---

← [Expressions and operators](04-expressions-and-operators.md) · [Contents](README.md) · [Next: Procedures and functions →](06-procedures-and-functions.md)
