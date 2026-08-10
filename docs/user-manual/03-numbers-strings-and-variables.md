# 3. Numbers, Strings and Variables

← [The editor](02-the-editor.md) · [Contents](README.md) · [Next: Expressions and operators →](04-expressions-and-operators.md)

---

SAM BASIC has exactly two kinds of value: **numbers** and **strings**. There
is no separate integer type visible to the programmer, no records, and no
pointers. Everything else is built out of those two plus arrays.

## 3.1 Numbers

### Range and precision

Every number occupies five bytes and is held in one of two forms, chosen
automatically:

* **Small integer form** for any whole number from −65535 to 65535.
  Arithmetic on these takes a fast integer path.
* **Floating-point form** for everything else: a sign, an 8-bit exponent and
  a 32-bit mantissa.

| | |
|---|---|
| Largest magnitude | about 1.7 × 10³⁸ |
| Smallest non-zero magnitude | about 2.9 × 10⁻³⁹ |
| Significant digits | 9 |

Exceeding the range gives error 28, *Number too large*.

Because the mantissa is binary, familiar decimal fractions are not exact:

```basic
PRINT 0.1+0.2-0.3
```

does not print exactly `0`. Compare numbers with a tolerance rather than for
equality when fractions are involved.

### Writing numbers

| Form | Example | Notes |
|---|---|---|
| Decimal | `42`, `3.14159`, `.5` | A leading digit is not required |
| Exponent | `1.5E6`, `2E-9` | `E` may be upper or lower case |
| Hexadecimal | `&FF`, `&C000` | `&` prefix |
| Binary | `BIN 10110`, `BIN 11111111` | `BIN` prefix |

`&` and `BIN` are just literal syntax — they produce ordinary numbers.

> **How literals are stored.** When you enter a line, the syntax checker
> converts each numeric literal once and writes the five-byte value into the
> line, invisibly, immediately after the digits. At run time the digits are
> skipped and the binary value is copied straight to the calculator stack.
> Nothing is ever converted from text while a program runs — which is why
> constants cost nothing at run time, and why the stored form of a line is
> larger than the text you typed.

### How numbers print

`PRINT` (and `STR$`) render up to nine significant digits, drop trailing
zeros, and switch to exponent notation when the number is very large or very
small. The changeover for small numbers is controlled by `FRACLIM` (system
variable offset &19A, default 6): a fraction may have that many leading zeros
after the point before `E` notation is used instead.

```basic
PRINT 1/3          : REM 0.333333333
PRINT 1e10         : REM 10000000000
PRINT 1e-7         : REM 1E-7
POKE SVAR &19A,10  : PRINT 1e-7   : REM 0.0000001
```

## 3.2 Strings

A string literal is written between double quotes. To include a quote,
double it:

```basic
PRINT "She said ""no"""
```

Strings may be up to 65535 characters long in principle; individual
operations have their own limits (a string built by `STRING$` is capped at
511 characters, one built from a literal with doubled quotes at 255).
Exceeding a limit gives error 42, *String too long*.

An empty string is `""`. Concatenate with `+`:

```basic
LET a$ = "SAM" + " " + "Coupe"
```

> **A detail worth knowing.** A string literal that contains no doubled quote
> is never copied — at run time the descriptor points directly into the
> program line. Only literals containing `""` are copied to workspace so the
> escapes can be collapsed. This is invisible in normal use but explains why
> literals are effectively free.

### Slicing

Any string expression may be followed by a **slicer** in brackets:

| Form | Meaning |
|---|---|
| `a$()` | The whole string |
| `a$(n)` | The single character at position *n* (counting from 1) |
| `a$(m TO n)` | Characters *m* to *n* inclusive |
| `a$(m TO)` | From *m* to the end |
| `a$( TO n)` | From the start to *n* |

```basic
LET a$ = "SAM Coupe"
PRINT a$(1 TO 3)      : REM SAM
PRINT a$(5)           : REM C
PRINT a$(5 TO)        : REM Coupe
```

A reversed range such as `a$(5 TO 2)` yields the empty string rather than an
error. A genuinely out-of-range position gives error 4, *Subscript wrong*.

Slicing works on any string expression, not just a variable:

```basic
PRINT (STR$ 12345)(2 TO 3)   : REM 23
```

Assigning to a slice overwrites in place without changing the length:

```basic
LET a$ = "abcdef"
LET a$(2 TO 3) = "XY"
PRINT a$                     : REM aXYdef
```

## 3.3 Variable names

| Kind | Maximum length | Characters allowed |
|---|---|---|
| Numeric | 32 | Letters, digits, underscore; must start with a letter |
| String (`name$`) | 10 | As above, plus the trailing `$` |
| Array (`name(…)`) | 10 | As above |

Rules that apply to all of them:

* **Case is ignored.** `Total`, `total` and `TOTAL` are one variable.
* **Spaces inside a name are ignored.** `price of bread` and `priceofbread`
  are the same variable — this is deliberate, and lets you write readable
  names.
* **Underscores are kept.** `first_name` is distinct from `firstname`.

A name longer than 10 characters used for a string or array gives error 40,
*Invalid variable name*.

```basic
LET number of items = 12
PRINT numberofitems        : REM 12 -- the same variable
```

### Where variables live

Numeric variables are held in 26 chains, one per initial letter, so lookup is
fast regardless of how many you have. Strings and arrays are held in a single
list that is scanned linearly, so a program with hundreds of strings pays for
it. This is worth knowing if you are optimising an inner loop.

## 3.4 Assignment

```
LET     variable = expression
DEFAULT variable = expression
```

`LET` is **required**. A statement that begins with a bare name is read as a
procedure call, so `x = 1` will give *Missing DEF PROC*.

`DEFAULT` assigns only if the variable does not already exist. It is the
clean way to give a procedure parameter a default value:

```basic
10 DEF PROC box w, h
20   DEFAULT w = 10
30   DEFAULT h = 5
40   PRINT w; " by "; h
50 END PROC
```

(A procedure parameter that was not supplied by the caller is created holding
"minus zero", a value `DEFAULT` treats as not existing. That is exactly what
makes the idiom above work.)

The four **graphics pseudo-variables** are ordinary numeric variables created
by `RUN`/`CLEAR`, and you assign to them the same way:

| Name | Default | Meaning |
|---|---|---|
| `xos` | 0 | X origin offset |
| `yos` | 0 | Y origin offset |
| `xrg` | 256 (512 with thin pixels) | X coordinate range |
| `yrg` | 192 | Y coordinate range |

See chapter 9.

## 3.5 Arrays

```
DIM name(d1 [, d2 …])
DIM name$(d1 [, d2 …])
```

`DIM` deletes any existing variable of the same name and creates a new array
with every element cleared. Subscripts run from **1** to *d*.

```basic
DIM score(10)             : REM 10 numbers
DIM grid(8,8)             : REM 64 numbers
DIM name$(20,12)          : REM 20 strings of 12 characters
```

Several arrays may be dimensioned in one statement:

```basic
DIM a(8), b(6,5), a$(2)
```

### Numeric arrays

Each element takes 5 bytes. Subscript with brackets:

```basic
LET score(3) = 99
PRINT score(3)
```

### String arrays

A string array is a *fixed-width* table of characters, not an array of
variable-length strings. `DIM name$(20,12)` gives 20 slots of 12 characters
each, space-filled.

* `name$(3)` is the whole of slot 3 — a 12-character string.
* `name$(3, 4 TO 6)` slices within slot 3.
* Assigning a shorter string pads with spaces; a longer one is truncated.

A one-dimensional string array `DIM a$(20)` is simply a 20-character string,
which is why `a$(5)` gives a single character in both cases.

### Reporting on a variable — `LENGTH`

```
LENGTH(n, variable)
```

| *n* | Returns |
|---|---|
| 0 | The address of the variable's data |
| 1 | The number of elements |
| 2 | The element length |

For a simple string, the element count is the length and the element length
is 1. For `DIM a$(20,12)` the count is 20 and the element length 12. This is
how you interrogate an array whose shape you do not know:

```basic
DIM n$(20,12)
PRINT LENGTH(1, n$)      : REM 20
PRINT LENGTH(2, n$)      : REM 12
PRINT LENGTH(0, n$)      : REM where the characters actually are
```

`LENGTH(0, …)` is the route to `POKE`ing an array directly, or handing its
address to machine code.

## 3.6 Type checking

The expression evaluator carries the type of every operand and checks it as
the line is entered, not when it runs. `a$ + 1` and `a$ MOD b$` are rejected
at typing time with *Not understood*.

Two operations deliberately mix types:

* `a$ AND n` — yields `a$` if *n* is non-zero, `""` otherwise.
* Comparisons between two strings yield a number (0 or 1).

## 3.7 Converting between the two

| Function | Direction | Example |
|---|---|---|
| `STR$ n` | Number → text | `STR$ 3.5` = `"3.5"` |
| `VAL a$` | Text → number | `VAL "2+2"` = `4` |
| `VAL$ a$` | Text → string | `VAL$ """hi"""` = `"hi"` |
| `CHR$ n` | Code → character | `CHR$ 65` = `"A"` |
| `CODE a$` | Character → code | `CODE "A"` = `65` |
| `BIN$ n` | Number → binary text | `BIN$ 5` = `"101"` |
| `HEX$ n` | Number → hex text | `HEX$ 255` = `"FF"` |
| `TRUNC$ a$` | Strip trailing spaces | |
| `STRING$(n, a$)` | Repeat | `STRING$(3,"ab")` = `"ababab"` |
| `LEN a$` | Length | `LEN "SAM"` = `3` |
| `INSTR(a$, b$)` | Find substring | position, or 0 |

`VAL` and `VAL$` run the *whole* interpreter pipeline — tokenise, syntax
check, evaluate — so they accept complete expressions including spelled-out
keywords:

```basic
LET a = 3
PRINT VAL "a*2 + SIN 0"     : REM 6
```

That power costs time; do not put `VAL` inside a tight loop.

`BIN$` uses the characters in the system variables `BIN1DIG` (offset &03) and
`BIN0DIG` (offset &04), normally `1` and `0`, so you can change them:

```basic
POKE SVAR 3, CODE "#" : POKE SVAR 4, CODE "."
PRINT BIN$ 10                : REM #.#.
```

`INSTR` recognises a wildcard character, `INSTHASH` (offset &05, normally
`#`), which matches anything:

```basic
PRINT INSTR("hello world", "w#r")    : REM 7
```

Give `INSTR` a starting position as an optional first argument:
`INSTR(5, a$, b$)`.

## 3.8 Memory used by variables

| Kind | Bytes |
|---|---|
| Numeric, one letter name | 1 + 2 + 5 = 8 |
| Numeric, *n*-letter name | 1 + 2 + (*n*−1) + 5 |
| `FOR` control variable | the above + 5 + 5 + 4 = +14 |
| String or array | 1 + 10 (name) + 3 (length) + data |

Numeric array data is 5 bytes per element plus 1 byte for the dimension count
and 2 bytes per dimension; string array data is 1 byte per element plus the
same dimension overhead.

`FREE` reports how much memory is left.

---

## Summary

* Numbers are 5 bytes, 9 significant digits, with a fast integer path for
  whole numbers in ±65535.
* Literals are pre-converted at typing time and stored in binary in the line.
* Strings slice with `(n)`, `(m TO n)`, `(m TO)` and `( TO n)`, and slices can
  be assigned to.
* Names are case-insensitive and ignore embedded spaces; numerics may be 32
  characters, strings and arrays 10.
* `LET` is compulsory; `DEFAULT` assigns only when the variable is absent.
* String arrays are fixed-width character tables; `LENGTH` tells you their
  shape and where their data is.

---

← [The editor](02-the-editor.md) · [Contents](README.md) · [Next: Expressions and operators →](04-expressions-and-operators.md)
