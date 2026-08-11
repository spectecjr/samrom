# 12. Errors and Debugging

← [Data, files and devices](11-data-files-and-devices.md) · [Contents](README.md) · [Next: Memory and machine code →](13-memory-and-machine-code.md)

---

## 12.1 How a report looks

When a program stops, SAM prints a report on the lower screen:

```
29 Not understood, 120:2
```

That is the error **number**, the **message**, and then the **line** and
**statement** at which it happened — statement 2 of line 120. A report from a
direct command shows line 0.

Two reports are special:

* **Error 2** prints the offending name first: `2 total not found, 40:1`.
* Codes &51 and above are DOS errors; their text comes from the DOS, not the
  ROM.

Reports 0 and 14 to 17 are not faults at all:

| Code | Report | Meaning |
|---|---|---|
| 0 | `OK` | The program reached the end |
| 14 | `BREAK - CONTINUE to repeat` | BREAK during I/O; the statement will be re-run |
| 15 | `BREAK into program` | BREAK between statements |
| 16 | `STOP statement` | A `STOP` was executed |
| 17 | `STOP in INPUT` | BREAK during `INPUT` |

The full list of 56 reports is in [Appendix B](appendix-b-error-messages.md).

## 12.2 Syntax errors while typing

A line that does not parse is not stored. Instead the cursor is placed back
in it with a **flashing `?`** marking where the checker gave up.

The syntax check is thorough: it validates types (`a$ + 1` is rejected),
statement shapes, and the contents of `DATA` statements. It is also what
inserts the pre-converted numeric values and the `FN`/`PROC` calling buffers
into the stored line, so a line that fails the check has none of that work
done and is simply discarded.

What the check *cannot* know is whether a procedure or function exists — that
is resolved by the compile pass before each `RUN`, and reported only when the
call is executed.

## 12.3 `CONTINUE`

`CONTINUE` resumes from where the program stopped. It uses `OLDPPC` and
`OSPPC`, which record the line and statement of the last halt.

```basic
100 PRINT "before"
110 STOP
120 PRINT "after"
```

```
RUN
before
16 STOP statement, 110:1
CONTINUE
after
```

After report 14 (BREAK during I/O) the *same* statement is re-run, because it
may not have completed. After report 15 execution resumes at the next
statement.

You may edit lines between the stop and the `CONTINUE`, including the line
you stopped in — the stack frames hold line numbers and statement numbers
rather than raw addresses, so they still make sense.

## 12.4 `ON ERROR`

```
ON ERROR statement
ON ERROR STOP
```

`ON ERROR` records where it is and then **skips** the statement that follows
it, carrying on normally. When an error occurs, execution re-enters that
statement and runs the handler.

```basic
  10 ON ERROR GOTO 9000
  20 INPUT "Divide 100 by: "; n
  30 PRINT 100/n
  40 GOTO 20
9000 PRINT "That did not work: error "; error; " at line "; lino
9010 GOTO 20
```

`ON ERROR STOP` disarms it.

### The three variables a handler sees

Before the handler runs, three numeric variables are created for it:

| Variable | Contents |
|---|---|
| `error` | The error number |
| `lino` | The line the error happened in |
| `stat` | The statement number within that line |

```basic
9000 IF error = 22 THEN PRINT "end of file": GOTO 100
9010 IF error = 30 THEN PRINT "number out of range": GOTO 100
9020 PRINT "Unexpected error "; error; " at "; lino; ":"; stat
9030 STOP
```

### Arming, and re-arming

`ON ERROR` sets two flags: a permanent one and a temporary one. The temporary
one is **consumed when the handler fires**, so an error inside the handler is
not trapped again and will stop the program properly. That is deliberate: it
stops a broken handler looping forever.

`END PROC` re-arms the temporary flag. So the robust way to write a handler
is as a procedure:

```basic
  10 ON ERROR recover
  20 REM ... main program ...
  30 STOP
1000 DEF PROC recover
1010   PRINT "error "; error; " at "; lino; ":"; stat
1020   REM tidy up and carry on
1030 END PROC
```

That handler works every time, not just once. Note that the procedure returns
to the statement *after* the `ON ERROR` — that is, to wherever the program
was when the handler was armed, not to where the error happened.

`ON ERROR` used in a direct command merely disarms, since there would be
nothing to return to.

## 12.5 Trapping and recovering

`ON ERROR` is the way to make a program survive things it cannot check in
advance:

```basic
  10 REM does this file exist?
  20 ON ERROR GOTO 100
  30 LOAD "data" DATA a()
  40 ON ERROR STOP
  50 PRINT "loaded": GOTO 200
 100 ON ERROR STOP
 110 PRINT "no data file; starting fresh"
 120 DIM a(100)
 200 REM carry on
```

Always disarm with `ON ERROR STOP` as soon as the risky section is over.
Leaving a handler armed across the whole program turns every mistake into a
mystery.

## 12.6 Debugging technique

### Stop and look

Because SAM keeps its variables after a program stops, the most powerful
debugging tool is simply typing expressions:

```
STOP
PRINT x, y, count
PRINT a$(1 TO 20)
PRINT LENGTH(1, table)
LET x = 99
CONTINUE
```

### Trace by hand

There is no `TRACE` command, but a procedure gets you most of the way:

```basic
1000 DEF PROC trace msg$
1010   IF debug THEN PRINT #0; msg$; " ";
1020 END PROC
```

with `LET debug = 1` at the top. Printing to stream 0 keeps the trace on the
lower screen and out of the way of your display.

### Capture the trace instead of printing it

```basic
10 LET log$ = ""
20 RECORD TO log$
30 REM ... run the suspect section, with PRINT #16 traces ...
40 RECORD STOP
50 PRINT log$
```

### Slow it down

```basic
POKE SVAR &141, 0     : REM make sure BREAK is enabled
```

and add `PAUSE 25` or `GET k$` at the point you want to inspect.

### Check the shape of things

| Expression | Tells you |
|---|---|
| `FREE` | Bytes of memory left |
| `LENGTH(1, v)` | How many elements a variable has |
| `LENGTH(2, v)` | How long each element is |
| `LENGTH(0, v)` | Where the data actually lives |
| `PEEK 23606` etc. | The state of any system variable (chapter 14) |

### Common causes of confusing reports

| Report | Usual cause |
|---|---|
| 12 *Missing DEF PROC* | You wrote `x = 1` and forgot `LET` |
| 29 *Not understood* | A type mismatch, or a DOS command with no DOS |
| 4 *Subscript wrong* | An array index of 0, or a slice past the end |
| 2 *…not found* | A typo in a variable name — remember spaces are ignored, so `my var` and `myvar` are the same but `my_var` is not |
| 30 *Integer out of range* | A negative value where 0–65535 was needed, e.g. in `BAND`, `POKE` or `CHR$` |
| 41 *BASIC stack full* | Runaway recursion, or a `DO` loop exited with `GOTO` instead of `EXIT IF` |
| 1 *Out of memory* | Often string fragmentation; `CLEAR` between phases helps |

### The `GOTO`-out-of-a-loop trap

Leaving a `DO` loop or a `GOSUB` with a `GOTO` leaves its frame on the BASIC
stack. Do it in a loop and you will eventually get error 41. Use `EXIT IF`,
or `POP` the frame explicitly:

```basic
100 IF give_up THEN POP: GOTO 900
```

## 12.7 Disabling BREAK

`BREAKDI` (system variable offset &141) disables the BREAK test between
statements when non-zero:

```basic
POKE SVAR &141, 1     : REM uninterruptible
POKE SVAR &141, 0     : REM back to normal
```

Use it around a critical section — but be sure there is a way out, or you
will need the NMI button.

## 12.8 What happens internally

Understanding the mechanism makes odd behaviour less mysterious:

* Every error is raised by a restart carrying the error code. The handler
  records where it happened (for the flashing `?`), offers the code to the
  `RST8V` vector so a utility can see it first, and then either passes it to
  a resident DOS or stores it and unwinds the stack.
* Codes 128 and above are not errors at all but **DOS hook codes** — that is
  how BASIC asks the DOS to open a file or read a directory. Without a DOS
  they become error 53.
* The unwinding resets the stack pointer from `ERRSP`, so any partially
  completed operation is simply abandoned. This is why an error never leaves
  the interpreter in a half-finished state, and why machine code called from
  BASIC cannot catch an error raised inside a ROM routine it called (see
  chapter 13).

---

## Summary

* A report is `number message, line:statement`; codes 0 and 14–17 are not
  faults.
* A syntax error shows a flashing `?` at the point of failure and the line is
  not stored.
* `CONTINUE` resumes; after a BREAK during I/O the same statement re-runs.
* `ON ERROR statement` traps errors and gives the handler `error`, `lino` and
  `stat`; `ON ERROR STOP` disarms.
* A handler written as a procedure re-arms itself, because `END PROC` does so.
* `POP` the frame when leaving a loop or subroutine with `GOTO`, or the BASIC
  stack fills up.

---

← [Data, files and devices](11-data-files-and-devices.md) · [Contents](README.md) · [Next: Memory and machine code →](13-memory-and-machine-code.md)
