# 1. First Steps

← [Contents](README.md) · [Next: The editor →](02-the-editor.md)

---

## 1.1 What you see when you switch on

The SAM starts in **MODE 4** — 256 × 192 pixels with sixteen colours — and
prints the copyright banner. Press any key and you are in BASIC.

The screen is divided into two windows:

* The **upper screen** is where `PRINT`, `LIST` and all the graphics go. It
  is initially 19 rows tall (rows 0 to 18).
* The **lower screen** is the two rows at the bottom where you type. Error
  reports appear here too.

You do not need to do anything to "enter" the editor. Whatever you type goes
into the lower screen, and pressing **ENTER** acts on it.

## 1.2 Your first command

Type this and press ENTER:

```basic
PRINT "Hello"
```

`Hello` appears on the upper screen. That is a **direct command** — a
statement with no line number, executed immediately.

Almost every statement in SAM BASIC can be used directly. Try:

```basic
PRINT 2+2
PRINT 22/7
BORDER 2
PRINT "The answer is "; 6*7
```

`PRINT` takes a list of things to print, separated by `;` (join them),
`,` (move to the next column stop) or `'` (start a new line). Chapter 7
covers the full set.

## 1.3 Your first program

Put a line number in front of a statement and it is stored instead of run:

```basic
10 PRINT "SAM Coupe"
20 PRINT "1 2 3"
```

Nothing appears. The lines are now in memory, and the listing at the top of
the screen updates to show them — SAM re-lists your program after every
direct command, which is called the **autolist**.

Run it:

```basic
RUN
```

Line numbers may be anything from **1 to 65279**. Convention is to number in
tens so you have room to insert lines later; `AUTO` (chapter 2) does that for
you.

To replace a line, type it again with the same number. To delete one, type
just its number and ENTER.

## 1.4 The four commands you will use constantly

| Command | Effect |
|---|---|
| `RUN` | Clear the variables and run from the first line. `RUN 100` starts at line 100 |
| `LIST` | List the program. `LIST 100` lists from line 100 on; `LIST 100 TO 200` lists a range |
| `NEW` | Erase the program and all variables, and reset the machine |
| `STOP` | (Typed as part of a program) halt with a report |

Press **ESCAPE** (or the BREAK key) while a program is running to stop it.
You will get report 15, *BREAK into program*, and can then use `CONTINUE` to
carry on from where you left off.

> `NEW` finishes by printing the copyright banner and waiting for a keypress.
> That is why `NEW` cannot usefully be run from inside a program.

## 1.5 Statements, lines and separators

A **line** holds one or more **statements**, separated by colons:

```basic
10 PRINT "one": PRINT "two": PRINT "three"
```

Statements are numbered within the line starting at 1, which is why an error
report says something like `29 Not understood, 10:2` — statement 2 of line 10.

Spaces are almost always optional; the tokeniser removes them from keywords
and from variable names. `PRINTX` is *not* `PRINT X`, though — a keyword may
not be immediately followed by a letter. When in doubt, leave the space in.

Case does not matter. `print`, `Print` and `PRINT` are the same keyword, and
`Total`, `total` and `TOTAL` are the same variable.

## 1.6 Keywords are single characters inside the machine

When you press ENTER, SAM replaces each spelled-out keyword with a single
**token** byte before storing the line. This has three visible consequences:

1. **Programs take less memory than they look.** `RANDOMIZE` costs one byte.
2. **Spelling is normalised when you list.** You can type `GOTO` or `GO TO`,
   `ENDIF` or `END IF`, `DEFPROC` or `DEF PROC` — all match, and all list
   back in the ROM's own spelling.
3. **A few keywords are synonyms.** Notably, typing `INK` stores the `PEN`
   token, so `INK 3` lists back as `PEN 3`. They are the same command.

Inside a string literal nothing is tokenised, and after `REM` the rest of the
line is left exactly as typed.

## 1.7 Variables, briefly

Assign with `LET`, which is **not** optional:

```basic
10 LET count = 10
20 LET name$ = "SAM"
30 PRINT name$; " has "; count
```

If you leave `LET` out, SAM reads the leading name as the name of a
*procedure* to call (see chapter 6) and you get *Missing DEF PROC*. This
catches everyone at least once.

* Names ending in `$` hold **strings**; all others hold **numbers**.
* Numeric names may be up to 32 characters and may contain letters, digits
  and underscores. Spaces inside a name are ignored, so `price of bread` and
  `priceofbread` are the same variable.
* String and array names are limited to 10 characters.

Chapter 3 covers all of this properly.

## 1.8 A slightly larger program

Type this in. It shows a loop, a condition, and input:

```basic
10 INPUT "How many stars? "; n
20 IF n < 1 OR n > 20 THEN PRINT "Between 1 and 20 please": GOTO 10
30 FOR i = 1 TO n
40   PRINT "*";
50 NEXT i
60 PRINT
70 PRINT "That was "; n; " stars."
```

Note the indentation on lines 40 — SAM's lister can add that automatically.
Try `LIST FORMAT 2` and then `LIST`: nested blocks are indented two columns
per level. `LIST FORMAT 0` turns it off again.

## 1.9 Getting out of trouble

| Situation | What to do |
|---|---|
| A program will not stop | Press ESCAPE/BREAK |
| The machine appears frozen | Press the NMI ("super break") button if fitted |
| You want the program back after `NEW` | You cannot. Save often |
| A flashing `?` appears in your line | That marks where the syntax error is |
| You get a report you do not understand | See [Appendix B](appendix-b-error-messages.md) |

After an error you can usually fix the offending line and type `CONTINUE` to
resume — SAM remembers the line and statement it stopped at.

## 1.10 Saving your work

```basic
SAVE "myprog"
LOAD "myprog"
VERIFY "myprog"
```

By default these go to whatever device `DEVICE` last selected — tape (`T`) on
a bare machine, a disk drive if you have one and DOS is loaded. Chapter 11
covers files fully.

To make a program start automatically when loaded:

```basic
SAVE "myprog" LINE 10
```

---

## Summary

* Statements without a line number run at once; with a line number they are
  stored.
* `RUN`, `LIST`, `NEW`, `SAVE`, `LOAD` manage the program.
* Lines hold colon-separated statements; statements are numbered from 1.
* Keywords become single bytes; case and most spaces are irrelevant.
* `$` marks a string variable; everything else is numeric.

---

← [Contents](README.md) · [Next: The editor →](02-the-editor.md)
