# 4. Expressions and Operators

← [Numbers, strings and variables](03-numbers-strings-and-variables.md) · [Contents](README.md) · [Next: Decisions and loops →](05-decisions-and-loops.md)

---

An expression is anything that produces a value: a literal, a variable, a
function call, or those combined with operators. This chapter is the complete
reference for how SAM BASIC builds and evaluates them.

## 4.1 The complete operator table

Operators are listed **highest priority first**. Everything on the same row
binds equally tightly and is evaluated left to right.

| Priority | Operator | Meaning | Operands | Result |
|---|---|---|---|---|
| 15 | *any function* | See §4.4 | varies | varies |
| 15 | `^` | Raise to a power | num, num | num |
| 14 | `MOD` | Remainder: `a − b*INT(a/b)` | num, num | num |
| 14 | `DIV` | Integer division: `INT(a/b)` | num, num | num |
| 9 | `−` (unary) | Negate | num | num |
| 8 | `*` | Multiply | num, num | num |
| 8 | `/` | Divide | num, num | num |
| 6 | `+` | Add, or **concatenate** | num,num or str,str | same |
| 6 | `−` | Subtract | num, num | num |
| 5 | `=` | Equal | num,num or str,str | num |
| 5 | `<>` | Not equal | num,num or str,str | num |
| 5 | `<` | Less than | num,num or str,str | num |
| 5 | `>` | Greater than | num,num or str,str | num |
| 5 | `<=` | Less or equal | num,num or str,str | num |
| 5 | `>=` | Greater or equal | num,num or str,str | num |
| 4 | `NOT` | Logical not | num | num |
| 3 | `AND` | Logical and | num,num or **str,num** | num or str |
| 3 | `BAND` | Bitwise and | num, num | num |
| 2 | `OR` | Logical or | num, num | num |
| 2 | `BOR` | Bitwise or | num, num | num |

Unary `+` is accepted and does nothing at all.

### Three consequences worth memorising

**`MOD` and `DIV` bind tighter than `*` and `/`.** This is unusual and is a
real trap:

```basic
PRINT 10 * 7 MOD 3      : REM 10 * (7 MOD 3) = 10, not (10*7) MOD 3 = 1
```

Bracket them whenever they share an expression with `*` or `/`.

**Functions bind at the same priority as `^`, and functions are applied
first.**

```basic
PRINT SIN x^2           : REM (SIN x)^2
PRINT SIN (x^2)         : REM what you probably meant
```

**Unary minus binds tighter than `*` but looser than `^`.**

```basic
PRINT -2^2              : REM -4, i.e. -(2^2)
```

### There is no `BXOR`

`BOR` and `BAND` exist; the corresponding exclusive-or was allocated a token
but never implemented, and the keyword table holds a placeholder in its slot.
Build it from what you have:

```basic
DEF FN x(a,b) = (a BOR b) - (a BAND b)
```

## 4.2 How the evaluator works

SAM uses an operator-precedence scanner. Each operator is stacked as a
(priority, operation) pair; when an incoming operator does not bind more
tightly than the one on top of the stack, the stacked one is performed.

The priority byte also carries the *type rules* — one bit says whether the
operation wants a numeric argument, another whether it yields one. That is
why a type error such as `a$ MOD b$` is caught when you type the line, not
when it runs.

Two remappings happen automatically when the left operand turns out to be a
string:

* `+` becomes concatenation.
* Each comparison becomes its string variant.

Everything else applied to two strings is rejected.

## 4.3 Logical values and the two families of logic

There is no boolean type. **False is 0 and true is 1**, and any non-zero
value counts as true in a test.

### Logical operators

| Expression | Result |
|---|---|
| `a AND b` | `a` if *b* is non-zero, otherwise `0` |
| `a OR b` | `1` if *b* is non-zero, otherwise `a` |
| `NOT a` | `1` if *a* is zero, otherwise `0` |

These are the ZX Spectrum semantics, and they are more useful than they look:

```basic
PRINT "Score: "; s; " (high)" AND s > best
LET step = 1 + 9 * (fast = 1)      : REM careful: comparisons give 0/1
LET limit = n AND n < 100          : REM n, or 0 if n is 100 or more
```

The string form `a$ AND n` yields *a$* when *n* is non-zero and `""`
otherwise, which is the idiomatic conditional-text construction:

```basic
PRINT "You win!" AND score > 100
```

### Bitwise operators

`BAND` and `BOR` convert both operands to 16-bit integers and combine them
bit by bit. Operands must be in the range 0 to 65535 — a negative or
too-large value raises error 30, *Integer out of range*.

```basic
PRINT BIN$ (BIN 1100 BAND BIN 1010)     : REM 1000
PRINT BIN$ (BIN 1100 BOR  BIN 1010)     : REM 1110
```

Note the brackets: `BAND` at priority 3 binds looser than the implicit
function application of `BIN$`.

### Comparisons on strings

Strings compare character by character using their character codes, so
ordering is by code, not by dictionary rules: all upper-case letters sort
before all lower-case ones. A shorter string that is a prefix of a longer one
sorts first.

```basic
PRINT "abc" < "abd"      : REM 1
PRINT "ABC" < "abc"      : REM 1
PRINT "ab"  < "abc"      : REM 1
```

## 4.4 The complete function list

Functions take their argument without brackets unless the table says
otherwise; brackets are always permitted and often clearer.

### No argument

| Function | Result | Notes |
|---|---|---|
| `PI` | 3.14159265 | |
| `RND` | Random 0 ≤ *r* < 1 | See `RANDOMIZE` |
| `FREE` | Free bytes | |
| `RAMTOP` | The current RAMTOP address | |
| `ITEM` | 0/1/2 | What remains in the current `DATA` statement: nothing / string / number |
| `XMOUSE`, `YMOUSE` | Mouse position | Needs a mouse driver in the `MOUSV` vector |
| `XPEN`, `YPEN` | Light pen position | Read from the palette port |
| `INKEY$` | The key now held, or `""` | Performs a fresh keyboard scan |

### One numeric argument, numeric result

| Function | Result |
|---|---|
| `ABS n` | Magnitude |
| `SGN n` | −1, 0 or 1 |
| `INT n` | Floor — `INT -5.9` is `-6` |
| `SQR n` | Square root |
| `SIN n`, `COS n`, `TAN n` | Trigonometric, argument in radians |
| `ASN n`, `ACS n`, `ATN n` | Inverse trigonometric, result in radians |
| `LN n` | Natural logarithm |
| `EXP n` | e to the power *n* |
| `NOT n` | 1 if zero, else 0 (priority 4) |
| `PEEK n` | The byte at address *n* |
| `DPEEK n` | The 16-bit word at address *n* |
| `IN n` | Read hardware port *n* |
| `SVAR n` | The **address** of system variable *n* |
| `USR n` | Call machine code at *n*; the result is whatever it leaves in BC |
| `BUTTON n` | 1 if mouse button *n* is down; `BUTTON 0` tests all three |
| `RND(n)` | A whole number from 0 to *n* |

`SVAR` is not a peek — it returns an address, so you almost always write
`PEEK SVAR n`. See chapter 14.

### One string argument

| Function | Result | Type |
|---|---|---|
| `LEN a$` | Length in characters | num |
| `CODE a$` | Character code of the first character | num |
| `VAL a$` | Evaluate as a numeric expression | num |
| `UDG a$` | Address of that character's 8-byte bitmap | num |
| `VAL$ a$` | Evaluate as a string expression | str |
| `TRUNC$ a$` | The string with trailing spaces removed | str |

`VAL` and `VAL$` run the full tokeniser and evaluator, so they accept
anything you could type — including variables and keywords.

### One numeric argument, string result

| Function | Result |
|---|---|
| `CHR$ n` | The one-character string with code *n* |
| `STR$ n` | The number as `PRINT` would show it |
| `BIN$ n` | Binary text, using the digit characters in `BIN1DIG`/`BIN0DIG` |
| `HEX$ n` | Hexadecimal text |
| `USR$ n` | Call machine code at *n*; the result is the string descriptor it leaves in A/DE/BC |

### Bracketed and multi-argument

| Function | Result |
|---|---|
| `POINT(x, y)` | Colour index of a pixel: 0/1 in modes 1 and 2, 0–3 in mode 3, 0–15 in mode 4 |
| `ATTR(line, column)` | The attribute byte of a character cell (modes 1 and 2 only) |
| `SCREEN$(line, column)` | The character at that cell, or `""` if it matches none |
| `INSTR(a$, b$)` | Position of *b$* within *a$*, or 0 |
| `INSTR(n, a$, b$)` | The same, starting at position *n* |
| `LENGTH(n, variable)` | 0 = address, 1 = element count, 2 = element length |
| `STRING$(n, a$)` | *a$* repeated *n* times (511 characters maximum) |
| `MEM$(n1 TO n2)` | Memory from address *n1* to *n2* as a string |
| `INKEY$ #s` | Read one character from stream *s* |

`MEM$` is a direct window onto memory as a string, which makes copying blocks
around trivially cheap:

```basic
LET screen$ = MEM$(16384 TO 22527)
```

### Supplied by DOS

These raise error 53, *No DOS*, on a bare machine:

| Function | Purpose |
|---|---|
| `DVAR n` | The address of a DOS variable, used like `SVAR` |
| `EOF #s` | End of file on stream *s* |
| `PTR #s` | File pointer of stream *s* |
| `PATH$` | The current path |

### User-defined

| Form | Meaning |
|---|---|
| `FN name(args)` | Call a function defined with `DEF FN` — see chapter 6 |

### Not implemented

The tokeniser reserves slots for `INARRAY`, `CHAR$`, `USING$`, `SHIFT$` and a
few others, but none of them has an entry in the keyword table — they cannot
be typed and are listed here only so you are not surprised by the gaps in the
token map ([Appendix D](appendix-d-tokens-and-priorities.md)).

## 4.5 Randomness

```
RANDOMIZE          seed unpredictably (from the frame counter)
RANDOMIZE 0        the same
RANDOMIZE n        seed deterministically with n
```

`RND` is a 16-bit linear congruential generator over the `SEED` system
variable, scaled into 0 ≤ *r* < 1. `RND(n)` gives a whole number from 0 to
*n* inclusive.

Seeding with a fixed value repeats a sequence exactly, which is invaluable
when debugging anything random:

```basic
10 RANDOMIZE 12345
20 FOR i = 1 TO 5: PRINT RND(100);" ";: NEXT i
```

## 4.6 Bracketing, and when the evaluator stops

A bracketed sub-expression is evaluated recursively. Note the one ambiguity
SAM resolves by context: a `(` immediately after a **string** expression is a
slicer, not a bracket.

```basic
PRINT (STR$ 1234)(2 TO 3)     : REM 23  -- slicing a bracketed expression
```

The scan ends at the first character that cannot continue the expression —
`:`, a comma, a closing bracket, or the end of the line. That is why print
items and function arguments do not need explicit terminators.

## 4.7 Speed

If you are optimising, these are the facts that matter:

* Whole numbers in ±65535 take a fast integer path through add, subtract and
  multiply. Keeping loop counters and coordinates integral is worth real time.
* Numeric literals cost nothing to parse — they are pre-converted.
* String literals cost nothing to copy unless they contain a doubled quote.
* Numeric variables are found through 26 per-letter chains; strings and arrays
  are found by scanning one flat list. Prefer numeric variables in hot loops,
  and declare frequently used strings early so they are found sooner.
* `VAL`, `VAL$` and `KEYIN` invoke the whole interpreter. Never put them in a
  loop that matters.
* Every function call, and every operator, goes through the same stack
  machine; complexity of an expression costs roughly linearly in operators.

---

## Summary

* Priorities, highest first: functions and `^` (15), `MOD`/`DIV` (14), unary
  minus (9), `*` `/` (8), `+` `−` (6), comparisons (5), `NOT` (4), `AND`
  `BAND` (3), `OR` `BOR` (2).
* `MOD` and `DIV` bind *tighter* than multiplication — bracket them.
* False is 0, true is 1; `AND`/`OR` return operands rather than booleans, and
  `a$ AND n` gives conditional text.
* `BOR` and `BAND` are bitwise on 0–65535; there is no `BXOR`.
* Type errors are caught when the line is entered.

---

← [Numbers, strings and variables](03-numbers-strings-and-variables.md) · [Contents](README.md) · [Next: Decisions and loops →](05-decisions-and-loops.md)
