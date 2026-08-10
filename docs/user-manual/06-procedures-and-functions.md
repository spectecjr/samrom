# 6. Procedures and Functions

← [Decisions and loops](05-decisions-and-loops.md) · [Contents](README.md) · [Next: Input and output →](07-input-and-output.md)

---

Procedures are what make SAM BASIC pleasant to write large programs in. They
have real names, real parameters, call by value or by reference, and local
variables — and you call one simply by writing its name.

## 6.1 Defining and calling a procedure

```
DEF PROC name [[REF] parameter [, [REF] parameter …]]
  statements
END PROC
```

Call it by writing the name as a statement:

```basic
  10 greeting
  20 greeting
  30 STOP
1000 DEF PROC greeting
1010   PRINT "Hello!"
1020 END PROC
```

Procedure names follow the same rules as variable names: they begin with a
letter and continue with letters, digits and underscores. They live in a
namespace of their own, so a procedure and a variable may share a name.

Definitions are usually put at the end of the program, after a `STOP`. If
execution ever reaches a `DEF PROC` by falling into it, the whole body is
skipped — running into a definition is harmless.

`END PROC` returns to the statement after the call. It also unwinds any local
variables and re-arms `ON ERROR`, which is what makes an error handler
written as a procedure work more than once.

## 6.2 Parameters

Arguments follow the call, separated by commas:

```basic
  10 box 10, 5, "*"
  20 STOP
1000 DEF PROC box w, h, ch$
1010   FOR y = 1 TO h
1020     PRINT STRING$(w, ch$)
1030   NEXT y
1040 END PROC
```

A mismatch between the number or type of arguments and parameters gives
error 26, *Parameter error*.

### By value (the default)

The argument is evaluated and copied into a new local variable of the
parameter's name. Any existing global of that name is hidden for the duration
and restored by `END PROC`. Changing the parameter inside the procedure has
no effect on the caller.

### By reference — `REF`

```basic
1000 DEF PROC swap REF a, REF b
1010   LOCAL t
1020   LET t = a: LET a = b: LET b = t
1030 END PROC
```

```basic
10 LET p = 1: LET q = 2
20 swap p, q
30 PRINT p; " "; q        : REM 2 1
```

A `REF` argument must be a **variable name**, not an expression. On return,
the final value is copied back into the caller's variable.

For strings and arrays, `REF` does not copy at all — the caller's variable is
*renamed* to the parameter's name for the duration and renamed back by
`END PROC`. That makes passing a large array by reference free.

```basic
1000 DEF PROC fill_array REF a
1010   FOR i = 1 TO LENGTH(1, a)
1020     LET a(i) = i * i
1030   NEXT i
1040 END PROC
```

### Optional parameters and `DEFAULT`

A parameter the caller did not supply is created holding a value that
`DEFAULT` treats as absent, so:

```basic
1000 DEF PROC window_at x, y, w, h
1010   DEFAULT w = 20
1020   DEFAULT h = 10
1030   …
1040 END PROC
```

`window_at 3, 4` uses the defaults; `window_at 3, 4, 40` overrides just the
width.

### Taking arguments as data — `DEF PROC … DATA`

```
DEF PROC name DATA
```

Instead of binding named parameters, this points the `DATA` read pointer at
the caller's argument list. The procedure then pulls arguments off with
`READ`, as many or as few as it likes:

```basic
  10 plot_points 10,10, 20,30, 40,15, 0,0
  20 STOP
1000 DEF PROC plot_points DATA
1010   DO
1020     READ x, y
1030     EXIT IF x = 0 AND y = 0
1040     PLOT x, y
1050   LOOP
1060 END PROC
```

`ITEM` tells you what remains, so you can write a procedure that adapts to
however many arguments it was given:

```basic
1000 DEF PROC total DATA
1010   LOCAL sum
1020   DO WHILE ITEM = 2
1030     READ n: LET sum = sum + n
1040   LOOP
1050   PRINT sum
1060 END PROC
```

## 6.3 Local variables — `LOCAL`

```
LOCAL variable [, variable …]
```

Hides any global of that name and creates a fresh local, which `END PROC`
discards. Locals start out empty — `DEFAULT` sees them as not existing, so
the idiom above works for them too.

```basic
1000 DEF PROC counter
1010   LOCAL i, total$
1020   FOR i = 1 TO 5: LET total$ = total$ + STR$ i: NEXT i
1030   PRINT total$
1040 END PROC
```

`LOCAL` is implemented as a procedure call with an empty argument list, using
exactly the same machinery as parameter binding — which is why it works
identically for numbers, strings and arrays, and why `LOCAL REF x` is not
accepted.

Note that a local numeric variable reuses a dead slot from a previous call
rather than growing the variable area, so repeated calls do not leak memory.

## 6.4 Recursion

Procedures are fully re-entrant provided their working variables are `LOCAL`:

```basic
  10 hanoi 4, 1, 3, 2
  20 STOP
1000 DEF PROC hanoi n, from, to, via
1010   IF n = 0 THEN END PROC
1020   hanoi n-1, from, via, to
1030   PRINT "Move disc "; n; " from "; from; " to "; to
1040   hanoi n-1, via, to, from
1050 END PROC
```

Depth is limited only by the BASIC stack (error 41, *BASIC stack full*) and
by the string/array area for local strings.

## 6.5 User-defined functions — `DEF FN`

```
DEF FN name[$] ( [parameter [, parameter …]] ) = expression
```

```basic
1000 DEF FN cube(x) = x*x*x
1010 DEF FN max(a,b) = a*(a>=b) + b*(b>a)
1020 DEF FN pad$(s$) = s$ + STRING$(20-LEN s$, " ")
```

Call with `FN`:

```basic
PRINT FN cube(3)
PRINT FN pad$("name"); "|"
```

Rules:

* The name follows variable-name rules; it must end in `$` if — and only if —
  the body yields a string. A mismatch is a syntax error.
* **Parameters must be single letters** (optionally followed by `$`). Inside
  the body, those single letters refer to the arguments rather than to any
  global of the same name.
* The body is a single expression. There are no statements and no local
  variables beyond the parameters.
* `DEF FN` does nothing at run time; falling into one is harmless.

A function may take no parameters at all:

```basic
1000 DEF FN e() = EXP 1
```

A call to an `FN` for which there is no `DEF FN` gives error 7, *FN without
DEF FN*.

## 6.6 How calls are resolved

Neither procedure calls nor `FN` calls search the program by name while it is
running. When you enter a line, the syntax checker opens a six-byte
**calling buffer** immediately after each call's name. Before every `RUN`, a
*compile pass* fills each buffer in with the page and address of the matching
definition.

Three things follow from this:

1. Calls cost a table lookup, not a search — they are fast regardless of
   program size.
2. Because the buffers are re-resolved on every run, a program can be edited,
   `RENUM`bered, saved, and reloaded at a different address without anything
   going stale.
3. A definition that does not exist is only detected at the moment of the
   call, giving *Missing DEF PROC* (12) or *FN without DEF FN* (7).

The buffers are invisible: they are introduced by a marker byte that every
part of the ROM — the lister, the searcher, the statement skipper — steps
over.

## 6.7 External commands

A statement beginning with a full stop is an **external command**: a call
into code supplied by a DOS or a utility rather than into a `DEF PROC`.

```basic
.dir
```

The ROM itself has no part in this. It does not recognise `.` at the start of
a statement — a bare machine gives *Not understood* — and although there is a
system variable named `XCMDP` reserved for "the first external command list",
no ROM code ever reads it. External commands are entirely a convention built
on the `CMDV` vector, which sees every statement before the ROM dispatches it.

[extending-basic.md](../extending-basic.md#9-worked-example-4--external-commands)
implements the mechanism from scratch if you want your own.

## 6.8 Executing generated code — `KEYIN`

```
KEYIN string
```

Tokenises and runs the string exactly as though it had been typed. It can run
a command, or — if the string starts with a line number — add a line to the
program.

```basic
10 FOR i = 1 TO 5
20   KEYIN STR$ (1000 + i*10) + " PRINT " + STR$ i
30 NEXT i
```

`KEYIN` is copied to the tape header buffer before running so that a command
executed by `KEYIN` cannot overwrite the copy that is running — which means a
`KEYIN` can safely contain another `KEYIN`.

## 6.9 Style

A program written the SAM way looks like this:

```basic
   10 REM ---- main ----
   20 setup
   30 DO
   40   draw_frame
   50   read_input
   60   EXIT IF quit
   70   update
   80 LOOP
   90 tidy_up
  100 STOP
  110
 1000 DEF PROC setup
 1010   MODE 4: CLS: BORDER 0
 1020   LET quit = 0
 1030 END PROC
 1040
 1050 DEF PROC read_input
 1060   LOCAL k$
 1070   LET k$ = INKEY$
 1080   IF k$ = "q" THEN LET quit = 1
 1090 END PROC
```

No `GOTO`, no line numbers referenced anywhere, every procedure short enough
to read at a glance. `LIST FORMAT 2` will indent it for you.

---

## Summary

* `DEF PROC name params … END PROC`; call it by writing the name.
* Parameters are by value unless marked `REF`; `REF` on a string or array is
  free because it renames rather than copies.
* `DEFAULT` gives optional parameters their defaults.
* `DEF PROC name DATA` turns the argument list into a `DATA` list read with
  `READ`, with `ITEM` reporting what remains.
* `LOCAL` hides globals for the duration of the call, which is what makes
  recursion safe.
* `DEF FN name(a,b) = expression` defines an expression function; parameters
  are single letters and the body is one expression.
* Calls are resolved by a compile pass before each run, so they are fast and
  survive editing.

---

← [Decisions and loops](05-decisions-and-loops.md) · [Contents](README.md) · [Next: Input and output →](07-input-and-output.md)
