; =====================================================================================================================
; EVAL.ASM -- The expression evaluator
; =====================================================================================================================
;
; Evaluates the expression at (CHAD). Paging is left exactly as it was found.
;
; Entry:  CHAD points at the first character.
; Exit:   Running       the result is on the calculator stack
;         Checking      the syntax has been verified and the invisible 5-byte forms inserted
;         Always        FLAGS bit 6 (FFLAGNUM) set for a numeric result, clear for a string;
;                       CHAD points at the first character that cannot be part of the expression, which is also in A,
;                       and HL = CHAD.
;
; HOW IT WORKS
; ------------
; A conventional operator-precedence scanner. Each operator and function is pushed on the machine stack as a
; (priority, operation) pair. When the incoming priority does not exceed the one on top of the stack, the stacked
; operation is performed -- or, at check time, merely type-checked -- and the comparison repeated. The scan ends when
; both the stacked and incoming priorities are zero.
;
; The priority byte carries the type rules as well as the precedence:
;
;     bit 7   result is numeric (clear = string)
;     bit 6   argument is numeric (clear = string)
;     bits 4-0 binding priority
;
; That lets the check pass verify "$ + $" but reject "$ MOD $" without a separate table of type rules.
;
; String operands remap the operation code: '+' becomes CONCAT, and each comparison becomes its string variant seven
; codes higher. See PRIGRTR.
;
; LITERAL OPTIMISATION
; --------------------
; Numeric literals are converted once, at check time, and the binary value is written into the program line after the
; digits, introduced by NUMMARKER. At run time the digits are skipped and the five bytes copied straight onto the
; calculator stack -- no text conversion ever happens while a program is running. See SDECIMAL and INSERT5B.
;
; String literals are not copied at all. Unless they contain a doubled quote, the descriptor stacked at run time
; points directly into the program line. See SQUOTE.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; SCANNING -- evaluate an expression, callable from either ROM
;
; Exit:   C = the terminating character, A = FLAGS.
; ---------------------------------------------------------------------------------------------------------------------

SCANNING:     CALL R1OFFCL              ; The scanner must see the program, so ROM1 is paged out
              DW SCANSR
              LD C,A                    ; The character that stopped the scan
              LD A,(FLAGS)
              RET


; ---------------------------------------------------------------------------------------------------------------------
; SCANSR -- the scanner proper
; ---------------------------------------------------------------------------------------------------------------------

SCANSR:       LD D,0                    ; Priority zero: the stopper that ends the scan
              RST &18                   ; First character; HL = CHAD
              DB SKIP1CP                ; Skip the RST &20 on the way in

SCANPLP:      RST &20                   ; Step to the next character

              PUSH DE                   ; Stack the pending (priority, operation)

; --- SCANLP: entered from unary plus, with HL = CHAD ---

SCANLP:       LD E,A
              AND &DF                   ; Fold letters to upper case

              CP "Z"+1
              JR NC,ABOVLETS

              CP "A"
              JP C,BELOWLETS            ; Not a letter


; ---------------------------------------------------------------------------------------------------------------------
; SLETTER -- a variable reference
;
; Inside a DEF FN, single-letter names may refer to the function's parameters, which are searched first.
; ---------------------------------------------------------------------------------------------------------------------

SLETTER:      LD A,(DEFADD+1)           ; Non-zero while a DEF FN is being evaluated
              AND A
              JR NZ,SLLKFV

SLET1:        LD A,(HL)
              CALL LKVARS2
              JP Z,VNFERR               ; No such variable

              LD A,(FLAGS)
              ADD A,A                   ; CY if running
              JP P,SLET2                ; A string

              BIT 5,C
              JR Z,SLET3                ; A simple numeric, not an array

SLET2:        CALL STKVAR2              ; Strings: stack start and length. Numeric arrays: HL -> the element.
              LD A,(FLAGS)
              ADD A,A

              JP P,SCONT1               ; A string, which may be followed by a slicer

SLET3:        CALL C,HLTOFPCS           ; Running: stack the number

SLET4:        CALL SELCHADP             ; The variable search may have changed the page
              RST &18
              JP OPERATOR               ; An operator or a terminator must follow

SLLKFV:       CALL LKFNVAR              ; Look in the DEF FN parameter list
              JR NC,SLET1               ; Not there, or checking: use the ordinary variables

              CP "$"
              JP Z,SCONT2               ; A string parameter, which may be sliced

              JR SLET4


; ---------------------------------------------------------------------------------------------------------------------
; ABOVLETS -- above 'Z': the only valid character is the function prefix
;
; The byte after the prefix is the function code. Subtracting &1A maps the stored range &3B-&83 onto the evaluator's
; internal range &21-&69, which is what its tables are indexed by.
; ---------------------------------------------------------------------------------------------------------------------

ABOVLETS:     INC E
              JR NZ,EVNONSE             ; Not &FF, so not a function

              INC HL
              LD A,(HL)                 ; The function code
              SUB &1A                   ; Stored &3B-&83 becomes internal &21-&69
              LD E,A
              LD (CHAD),HL              ; Step past the prefix

              LD HL,(EVALUV)
              INC H
              DEC H
              CALL NZ,HLJUMP            ; Let a utility add functions; A holds the code

              CP SIN
              JR C,IMMEDCODES           ; Below SIN: an immediate function, evaluated here and now

              LD D,&CF                  ; Priority 15, numeric argument, numeric result
              CP EOF+3
              JR C,SCANPLP              ; SIN through EOF, PTR and POS all take that default

              CP NOT+1
              JR NC,EVNONSE             ; Above NOT: not a function at all

SCANUMEN:     LD D,0                    ; The remainder have their own priority bytes
              LD HL,FNPRIORT-UDGA
              ADD HL,DE
              LD D,(HL)                 ; Priority plus the input and output type bits
              JR SCANPLP


; ---------------------------------------------------------------------------------------------------------------------
; IMINKEYS -- INKEY$ without a stream
;
; The stream form is left to the calculator, but plain INKEY$ cannot use the normal input path: that would return
; LASTK without performing a scan, so a key released before the call would still be reported.
; ---------------------------------------------------------------------------------------------------------------------

IMINKEYS:     RST &20                   ; Skip INKEY
              CP "#"
              LD E,INKEY
              POP BC                    ; Discard the return to STRCONT
              JR Z,SCANUMEN             ; INKEY$ #n: queue it for the calculator, which will skip the '#'

              PUSH BC
              CALL ABORTER              ; Nothing to do at check time

              CALL READKEY              ; A real scan; CY and the code in A if a key is down
              RST &30
              DW FPINKEN-&8000          ; Build a one-character string and stack its parameters


; ---------------------------------------------------------------------------------------------------------------------
; IMMEDCODES -- functions evaluated immediately rather than queued
;
; A function is handled here if it takes no argument at all (PI), takes its arguments in brackets (POINT, INSTR), or
; takes a stream (INKEY$ #n) -- in each case the normal one-argument mechanism does not fit.
;
;   Numeric results:  PI, RND, POINT, FREE, LENGTH, ITEM, ATTR, FN, BIN, XMOUSE, YMOUSE, XPEN, YPEN, RAMTOP, INSTR
;   String results:   INKEY$, SCREEN$, MEM$, PATH$, STRING$
; ---------------------------------------------------------------------------------------------------------------------

IMMEDCODES:   SUB PI
              JR C,EVNONSE              ; Below PI

              ADD A,A                   ; Two bytes per table entry
              LD E,A
              LD D,0
              LD HL,IMFNATAB
              ADD HL,DE
              LD C,(HL)
              INC HL
              LD B,(HL)
              LD HL,NUMCONT             ; Where to continue afterwards
              CP 0+(INSTR-PI)*2+1
              JR C,IMMEDNUM             ; Numeric result

              LD HL,STRCONT             ; String result

IMMEDNUM:     PUSH HL
              BIT 7,B
              JP NZ,R1ONCLBC            ; A ROM1 address, so page ROM1 in for the call

              PUSH BC
              RET                       ; Jump to BC

STRCONT:      CALL SLLPEX               ; Record that the result is a string
              JR SCONT2


; ---------------------------------------------------------------------------------------------------------------------
; BELOWLETS -- below 'A'
; ---------------------------------------------------------------------------------------------------------------------

BELOWLETS:    LD A,E                    ; The unfolded character
              CP "0"
              JP C,BELOWNUM

              CP &3A                    ; '9' + 1
              JR C,SDECIMAL             ; A digit

EVNONSE:      RST &08
              DB ERR_NONSENSE


; =====================================================================================================================
; Numeric literals
; =====================================================================================================================
;
; At check time the value is computed once and written into the line as NUMMARKER followed by five bytes, placed
; immediately after the digits. At run time the digits are skipped and those five bytes copied to the calculator
; stack.
; ---------------------------------------------------------------------------------------------------------------------

IMBIN:        POP AF                    ; BIN arrives through the immediate function table; discard that return
              RST &18                   ; HL = CHAD

SDECIMAL:     LD A,(FLAGS)
              RLA
              JR NC,INSERT5B            ; Checking: compute the value and embed it

; --- Running: the value is already there, just after the digits ---

LK0ELP:       INC HL
              LD A,(HL)
              CP NUMMARKER
              JR NZ,LK0ELP              ; Scan forward to the marker

              INC HL
              LD BC,NUMVALSIZE
              LD DE,(STKEND)
              LDIR                      ; Copy the five bytes straight to the calculator stack
              LD (STKEND),DE

SCHADNUM:     LD (CHAD),HL
              JR NUMCONT


; ---------------------------------------------------------------------------------------------------------------------
; INSERT5B -- convert a literal and embed its value in the line
; ---------------------------------------------------------------------------------------------------------------------

INSERT5B:     CALL CALC5BY              ; Evaluate the decimal, hex or binary literal onto the calculator stack
              LD HL,(CHAD)              ; CHAD now points just past the digits
              CALL MAKESIX              ; Open six bytes there and write the marker; HL -> the five that follow
              EX DE,HL
              CALL FDELETE              ; Drop the value, leaving HL pointing at it
              LD BC,NUMVALSIZE
              LDIR                      ; Copy it into the line
              EX DE,HL
              JR SCHADNUM


; ---------------------------------------------------------------------------------------------------------------------
; SSLICER -- a '(' following a string expression is a slicer
; ---------------------------------------------------------------------------------------------------------------------

SSLICER:      LD HL,FLAGS
              BIT 6,(HL)
              JR NZ,SLOOP               ; A number cannot be sliced, so the expression ends here

              RST &20                   ; Skip the '('
              CALL SLICING
              RST &20
              JR SLSTRLP


; ---------------------------------------------------------------------------------------------------------------------
; NUMCONT / SCONT1 / SCONT2 -- record the result type and look for what follows
; ---------------------------------------------------------------------------------------------------------------------

NUMCONT:      LD HL,FLAGS
              SET 6,(HL)                ; FFLAGNUM: numeric
              RST &18
              JR OPERATOR

SCONT1:       CALL SELCHADP

SCONT2:       RST &18                   ; A string expression may be followed by a slicer, as in (STR$ 123)(2),
                                        ; so check for that before looking for an operator
SLSTRLP:      CP "("
              JR Z,SSLICER


; =====================================================================================================================
; OPERATOR -- recognise a binary operator
; =====================================================================================================================
;
; Single-character operators are identified by arithmetic on their character codes; the alphabetic operators and the
; two-character comparisons arrive as &FF followed by a code.
; ---------------------------------------------------------------------------------------------------------------------

OPERATOR:     LD D,0                    ; Priority zero unless an operator is found
              INC A
              JR NZ,OPERAT2             ; Not the function prefix

              INC HL
              LD A,(HL)                 ; The operator code
              SUB FN_MOD
              JR C,SLOOP                ; Below MOD: a function, so not an operator

              CP &0A
              JR NC,SLOOP               ; Above '>=': likewise

              LD (CHAD),HL              ; Step past the prefix

              ADD A,8                   ; MOD to '>=' become internal codes &08-&11
              JR OPERAT3

OPERAT2:      SUB "*"+1                 ; '*' becomes 0, '+' 1, '-' 3, '/' 5, '<' &12, '>' &14
              JR C,SLOOP                ; Below '*'

              CP 4
              JR Z,SLOOP                ; '.' is not an operator

              CP 6
              JR C,OPERAT3              ; '*' through '/'

              CP &12
              JR C,SLOOP                ; Between '/' and '<'

              CP &15
              JR C,OPERAT3              ; '<', '=' or '>'

              CP &34                    ; '^' -- to the power of
              LD A,POWER
              JR NZ,SLOOP

OPERAT3:      LD E,A                    ; E = the internal operation code, &00-&14
              LD HL,OPPRIORT
              ADD HL,DE
              LD D,(HL)                 ; Its priority byte, or zero if the code is unused


; ---------------------------------------------------------------------------------------------------------------------
; SLOOP -- compare the incoming priority with the stacked one
;
; If the stacked operation binds at least as tightly, perform it now; otherwise stack the new one and read on.
; ---------------------------------------------------------------------------------------------------------------------

SLOOP:        POP BC                    ; B = stacked priority, C = stacked operation
              LD A,B
              SUB D
              AND &10                   ; Bit 4 is set when the incoming priority nibble is the higher
              JR NZ,PRIGRTR             ; The new operator binds tighter, so wait

              OR B                      ; The stacked one binds at least as tightly
              JP Z,&0018                ; Both priorities zero: the expression is complete, exit through RST &18

              PUSH DE                   ; Re-stack the incoming pair
              LD HL,FLAGS
              LD A,(HL)
              RLA
              JR C,EXECOP               ; Running: perform the operation

              LD A,B                    ; Checking: verify the operand type instead.
              XOR (HL)                  ; Bit 6 of the priority byte says whether this operation wants a numeric
                                        ; argument; bit 6 of FLAGS says what the last value actually was.
              ADD A,A
              JP M,EVNONSE              ; They disagree

              JR CHKEXECC

EXECOP:       PUSH BC
              LD B,C                    ; The operation code goes to the calculator in B

              DB CALC
              DB USEB                   ; Execute the operation held in BREG
              DB EXIT

              POP BC
              LD HL,FLAGS

CHKEXECC:     LD A,B                    ; The priority byte of the operation just performed
              POP DE                    ; The incoming pair again
              SET 6,(HL)                ; Assume a numeric result
              RLA                       ; Bit 7 of the priority byte says whether that is right
              JR C,SLOOP

              RES 6,(HL)                ; A string result after all
              JR SLOOP


; ---------------------------------------------------------------------------------------------------------------------
; PRIGRTR -- the incoming operator binds more tightly, so stack it and read on
;
; If the left operand was a string, the operation code and its type bits must be remapped: string comparisons live
; seven codes above their numeric equivalents, and '+' becomes CONCAT.
; ---------------------------------------------------------------------------------------------------------------------

PRIGRTR:      PUSH BC                   ; Re-stack the pending pair
              LD A,(FLAGS)
              ADD A,A
              JP M,SCANPLP              ; A numeric left operand: the type bits are already right

              LD A,E                    ; The incoming operation code

              RES 7,D                   ; A string result, as for '+' and "$ AND n"
              CP NUAND
              JR Z,SCANPLPH             ; "$ AND n" keeps a numeric right operand

              RES 6,D                   ; Otherwise the right operand is a string too: "$+$", "$<$"
              INC E                     ; '+' (code 1) becomes CONCAT (code 2)
              CP ADDN
              JR Z,SCANPH2

              SET 7,D                   ; A comparison of two strings yields a number
              CP NUAND
              JP C,NONSENSE             ; "$ MOD $" and the like are meaningless

SCANPLPH:     ADD A,7                   ; The string variants sit seven codes higher
              LD E,A

SCANPH2:      JP SCANPLP


; =====================================================================================================================
; OPPRIORT -- priorities of the binary operators
; =====================================================================================================================
;
; Indexed by the internal operation code. Bit 7 = numeric result, bit 6 = numeric argument, bits 4-0 = priority.
; ---------------------------------------------------------------------------------------------------------------------

OPPRIORT:     DB &C8                    ; &00  '*'
              DB &C6                    ; &01  '+'
              DB 0                      ; &02  (CONCAT, reached only by remapping)
              DB &C6                    ; &03  '-'
              DB &CF                    ; &04  '^'
              DB &C8                    ; &05  '/'
              DB 0                      ; &06  (SWOP)
              DB 0                      ; &07  (DROP)
              DB &CE                    ; &08  MOD
              DB &CE                    ; &09  DIV
              DB &C2                    ; &0A  BOR
              DB &C2                    ; &0B  BXOR
              DB &C3                    ; &0C  BAND
              DB &C2                    ; &0D  OR

              DB &C3                    ; &0E  AND   -- add 7 for the string forms of AND through '>'
              DB &C5                    ; &0F  '<>'
              DB &C5                    ; &10  '<='
              DB &C5                    ; &11  '>='
              DB &C5                    ; &12  '<'
              DB &C5                    ; &13  '='
              DB &C5                    ; &14  '>'


; =====================================================================================================================
; FNPRIORT -- priorities of the functions that are not simply "priority 15, numeric in, numeric out"
; =====================================================================================================================
;
; Indexed by the internal function code minus UDGA. Bit 7 = numeric result, bit 6 = numeric argument.
; ---------------------------------------------------------------------------------------------------------------------

FNPRIORT:     DB &8F                    ; UDG      string in, numeric out
              DB &8F                    ; (unused)
              DB &8F                    ; LEN
              DB &8F                    ; CODE
              DB &0F                    ; VAL$     string in, string out
              DB &8F                    ; VAL
              DB &0F                    ; TRUNC$
              DB &4F                    ; CHR$     numeric in, string out
              DB &4F                    ; STR$
              DB &4F                    ; BIN$
              DB &4F                    ; HEX$
              DB &4F                    ; USR$
              DB &4F                    ; INKEY$

              DB &C4                    ; NOT      priority 4
              DB &C9                    ; NEGATE   priority 9


; =====================================================================================================================
; IMFNATAB -- addresses of the immediate functions
; =====================================================================================================================
;
; The order matches the token order; the split between numeric and string results falls at INSTR.
; ---------------------------------------------------------------------------------------------------------------------

IMFNATAB:     DW IMPI                   ; Numeric results
              DW IMRND
              DW IMPOINT
              DW IMMEM                  ; FREE
              DW IMLENGTH
              DW IMITEM
              DW IMATTR
              DW IMFN
              DW IMBIN
              DW IMMOUSEX
              DW IMMOUSEY
              DW IMPENX
              DW IMPENY
              DW IMHIMEM                ; RAMTOP
              DW NONSENSE               ; (INARRAY, never implemented)
              DW IMINSTR

              DW IMINKEYS               ; String results
              DW IMSCREENS
              DW IMMEMRYS
              DW NONSENSE               ; (CHAR$)
              DW IMPATHS
              DW IMSTRINGS
              DW NONSENSE               ; (USING$)
              DW NONSENSE               ; (SHIFT$)


; =====================================================================================================================
; BELOWNUM -- characters below '0' that can begin an expression
; =====================================================================================================================
;
; Namely: '"' &22, '&' &26, '(' &28, '+' &2B, '-' &2D and '.' &2E.
; ---------------------------------------------------------------------------------------------------------------------

BELOWNUM:     CP &22
              JR Z,SQUOTE

              CP "&"
              JR Z,SDECIMALH            ; A hexadecimal literal

              CP "("
              JR Z,SBRACKET

              CP "-"
              JR Z,UNARMIN

              CP "."

SDECIMALH:    JP Z,SDECIMAL             ; A fraction with no leading digit

              CP "+"
              JP NZ,NONSENSE

UNARPLU:      RST  &20                  ; Unary plus does nothing at all
              JP SCANLP

UNARMIN:      LD E,NEGATE
              JP SCANUMEN

SBRACKET:     RST  &20
              CALL SCANNING             ; Recursive: the bracketed expression
              LD A,C
              CALL INSISCBRK
              JP SCONT2


; =====================================================================================================================
; SQUOTE -- a string literal
; =====================================================================================================================
;
; A literal with no doubled quote is left where it is: the descriptor stacked at run time points into the program
; line itself. Only a literal containing "" needs copying, so that the escapes can be collapsed.
; ---------------------------------------------------------------------------------------------------------------------

SQUOTE:       INC HL                    ; Skip the opening quote
              PUSH HL                   ; Start of the text
              LD A,(FLAGS)
              RLA
              EX AF,AF'                 ; CY in F' records whether we are running
              LD BC,&FFFF               ; Length counter, pre-decremented

QUTSRLP:      LD A,(HL)
              INC HL
              INC BC
              CP CC_ENTER
              JP Z,NONSENSE             ; The line ended inside a string

              CP &22
              JR NZ,QUTSRLP

              POP DE                    ; Start
              LD A,(HL)
              CP &22                    ; Is the closing quote doubled?

              JR Z,SQUOTE2              ; Yes, so the literal must be copied and de-escaped

              LD (CHAD),HL              ; No: it can stay in the line exactly as it is
              EX AF,AF'
              CALL C,STKSTOREP          ; Running: stack a descriptor pointing into the line

STRCONTH:     JP STRCONT


; ---------------------------------------------------------------------------------------------------------------------
; SQUOTE2 -- a literal containing doubled quotes
;
; Copied to the buffer with each "" reduced to one quote, then moved to workspace.
; ---------------------------------------------------------------------------------------------------------------------

SQUOTE2:      LD HL,INSTBUF             ; Room for 256 bytes
              LD C,0
              PUSH HL

SQUCOPY:      LD A,(DE)
              INC DE
              CP &22
              JR Z,SQUCO3

SQUCO1:       LD B,A
              EX AF,AF'
              JR NC,SQUCO2              ; Checking: count the characters but do not store them

              LD (HL),B
              INC HL

SQUCO2:       EX AF,AF'
              INC C
              JR NZ,SQUCOPY             ; At most 255 characters

              RST &08
              DB ERR_STRTOOLONG

SQUCO3:       LD A,(DE)
              INC DE
              CP &22
              JR Z,SQUCO1               ; A second quote: store one and continue

              LD B,0
              DEC DE                    ; -> just past the closing quote
              LD (CHAD),DE
              POP HL                    ; Start of the buffer
              EX AF,AF'
              CALL C,CWKSTK             ; Running: copy to workspace and stack the parameters
              JR STRCONTH


; =====================================================================================================================
; CALC5BY -- convert a numeric literal to a value
; =====================================================================================================================
;
; Entry:  HL and CHAD point at the first character, which is '&', '.', a digit, or the BIN token.
; Exit:   The value is on the calculator stack.
; ---------------------------------------------------------------------------------------------------------------------

CALC5BY:      LD A,(HL)
              CP "&"
              JR NZ,NAMP

              RST &30
              DW AMPERSAND-&8000        ; Hexadecimal, handled in ROM1

NAMP:         CP BINTOK
              JP NZ,DECIMAL

; --- A binary literal: BIN followed by 0s and 1s ---

              LD BC,0

NXBINDIG:     RST &20                   ; Skip BIN, then each digit
              CP "0"
              JR Z,BINDIG

              CP "1"
              SCF
              JP NZ,STACKBC             ; Anything else ends the number

BINDIG:       RL C                      ; Shift the digit in from the carry
              RL B
              JR NC,NXBINDIG            ; Still within 16 bits

              RST &08
              DB ERR_NUMTOOBIG


; ---------------------------------------------------------------------------------------------------------------------
; DECIMAL -- a decimal literal
;
; Handles 0.123, .123, 1.234, 1E4, 1.23E+4, 7.89E-32 and 1.E5.
; ---------------------------------------------------------------------------------------------------------------------

DECIMAL:      CP "."
              JR NZ,DECINT

              RST &20
              CALL NUMERIC
              JP NC,NONSENSE            ; A lone '.' is not a number

              DB CALC
              DB STKZERO                ; The integer part of a bare fraction is zero
              DB EXIT

              JR CONVFRAC

DECINT:       CALL INTTOFP              ; The integer part
              CP "."
              JR NZ,EFORMAT

              RST &20
              CALL NUMERIC
              JR NC,EFORMAT             ; "1." with no fraction digits

; --- The fractional part: each digit is worth a tenth of the last ---

CONVFRAC:     DB CALC
              DB STKFONE
              DB STOD0                  ; Memory 0 holds the place value, starting at 1
              DB EXIT

              RST &18
              JR CONVFRAC2

CONVFRALP:    SUB "0"
              LD B,A

              DB CALC
              DB STKBREG                ; The digit
              DB RCL0                   ; ... the place value
              DB STKTEN
              DB DIVN                   ; ... divided by ten
              DB STO0                   ; ... becomes the new place value
              DB MULT                   ; digit * place value
              DB ADDN                   ; ... added to the running total
              DB EXIT

              RST &20

CONVFRAC2:    CALL NUMERIC
              JR C,CONVFRALP


; ---------------------------------------------------------------------------------------------------------------------
; EFORMAT -- an optional exponent
; ---------------------------------------------------------------------------------------------------------------------

EFORMAT:      AND &DF                   ; Fold to upper case
              CP "E"
              RET NZ                    ; No exponent

              RST &20
              LD C,"+"
              CP C
              JR Z,GEXSGN1

              CP "-"
              JR NZ,GEXSGN2             ; No sign, so the digits start here

              LD C,A

GEXSGN1:      RST &20                   ; Skip the sign

GEXSGN2:      CALL NUMERIC
              JP NC,NONSENSE            ; The exponent must have digits

              PUSH BC                   ; C = the sign character
              CALL INTTOFP
              CALL FPTOA
              JR C,NTLERR               ; Over 255

              RLCA
              JR NC,GEXSGN3             ; 127 or less

NTLERR:       RST &08
              DB ERR_NUMTOOBIG

GEXSGN3:      RRCA
              POP BC
              BIT 1,C                   ; '+' is &2B, '-' is &2D: bit 1 distinguishes them
              JR NZ,POFTENH

              NEG

POFTENH:      RST &30
              DW POFTEN-&8000           ; Multiply the value by ten to the power in A


; ---------------------------------------------------------------------------------------------------------------------
; INTTOFP -- accumulate a run of ASCII digits
;
; Entry:  A = the first character; the rest follow at CHAD.
; Exit:   The value is on the calculator stack (zero if there were no digits), A = the first non-digit, NC.
; ---------------------------------------------------------------------------------------------------------------------

INTTOFP:      LD B,A

              DB CALC
              DB STKZERO                ; Running total
              DB EXIT

              LD A,B
              JR INTTOFP3

INTTOFPLP:    SUB "0"
              LD B,A

              DB CALC                   ; B is captured into BREG by the RST
              DB STKTEN
              DB MULT                   ; total = total * 10
              DB STKBREG
              DB ADDN                   ; ... + digit
              DB EXIT

              CALL NXCHAR               ; The &0074 entry: no skipping, so "1 2" is not read as 12

INTTOFP3:     CALL NUMERIC
              JR C,INTTOFPLP

              RET


; =====================================================================================================================
; USR, USR$ and CALL
; =====================================================================================================================
;
; All three resolve their address the same way and enter the target with HL and BC holding the mapped entry address.
; What is done with the result distinguishes them: USR stacks BC, USR$ stacks a string descriptor from A, DE and BC,
; and CALL stacks nothing.
; ---------------------------------------------------------------------------------------------------------------------

R0USRS:       LD HL,STKSTOS             ; USR$: stack DE, BC and A as a string descriptor
              DB SKIP3IY                ; Skip the LD HL below

R0USR:        LD HL,STACKBC             ; USR: stack BC as a number

USRCOM:       PUSH HL                   ; The chosen result handler becomes the return address

; --- CALLX: entered from the CALL command, which wants no result handler ---

CALLX:        PUSH IX
              CALL PDPSUBR              ; Map the address; HL = it, A = the entry HMPR value
              LD B,H
              LD C,L                    ; The target also arrives in BC
              PUSH AF                   ; Stacked in section B, which stays mapped
              LD A,(TEMPB3)             ; The CALL parameter count, or junk for USR
              CALL HLJUMP
              POP AF
              OUT (URPORT),A
              POP IX
              RET                       ; To STACKBC, STKSTOS, or the next statement


; ---------------------------------------------------------------------------------------------------------------------
; IMMEMRYS -- MEM$(n1 TO n2)
; ---------------------------------------------------------------------------------------------------------------------

IMMEMRYS:     CALL SINSISOBRK
              CALL EXPT1NUM
              CP TOTOK
              JP NZ,NONSENSE

              CALL SEX1NUMCB            ; Skip TO, take the second number and the bracket; CY if running
              RET NC

              RST &30
              DW MEMRYSP2-&8000


; ---------------------------------------------------------------------------------------------------------------------
; IMHIMEM -- RAMTOP
; ---------------------------------------------------------------------------------------------------------------------

IMHIMEM:      CALL SABORTER

              LD HL,(RAMTOP)            ; Held in &8000-&BFFF form with a separate page byte
              LD A,(RAMTOPP)
              LD B,A

; --- ASBHL: stack the page-form address in BHL, relative to the current base page. Also used by PEEK. ---

ASBHL:        IN A,(LRPORT)
              LD C,A
              LD A,B
              SUB C                     ; Make the page relative to the base
              JR STKPGFORM


; ---------------------------------------------------------------------------------------------------------------------
; IMMEM -- FREE
; ---------------------------------------------------------------------------------------------------------------------

IMMEM:        CALL SABORTER

              CALL GETROOM              ; AHL = free memory as a 19-bit value
              JR STK19BIT


; ---------------------------------------------------------------------------------------------------------------------
; STKPGFORM / STK19BIT -- stack a large address as a number
;
; A 19-bit value will not fit the small-integer form, so it is assembled on the calculator stack as
; high * 65536 + low.
; ---------------------------------------------------------------------------------------------------------------------

STKPGFORM:    CALL AHLNORM              ; Page form to a 19-bit value

STK19BIT:     PUSH AF
              CALL STACKHL              ; The low 16 bits
              POP BC

              DB CALC                   ; low
              DB STKBREG                ; low, high
              DB STK16K
              DB MULT                   ; low, high * 16384
              DB STKHALF
              DB DIVN                   ; low, high * 32768
              DB STKHALF
              DB DIVN                   ; low, high * 65536
              DB ADDN
              DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; Mouse and light pen functions
; ---------------------------------------------------------------------------------------------------------------------

IMMOUSEX:     CALL SABORTER

              LD HL,(MXCRD)
              JP STACKHL

IMMOUSEY:     CALL SABORTER

              LD A,(MYCRD)
              JR STACKAH

IMPENX:       CALL SABORTER

              LD BC,CLUTPORT            ; A8 low selects the pen X reading
              IN A,(C)
              RRA
              RRA
              AND &3F
              JR STACKAH

IMPENY:       CALL SABORTER

              LD BC,&0100+CLUTPORT      ; A8 high selects pen Y instead of pen X
              JR FPIN2


; ---------------------------------------------------------------------------------------------------------------------
; FPIN -- the IN function
; ---------------------------------------------------------------------------------------------------------------------

FPIN:         CALL GETINT               ; The port number

FPIN2:        IN A,(C)

STACKAH:      JP STACKA


; =====================================================================================================================
; Calculator stack entry swaps
; =====================================================================================================================
;
; Callable directly, and also the implementations of the SWOP, SWOP13 and SWOP23 calculator operations. FOR uses them
; to reorder value, limit and step; OPEN uses them too.
;
; Exit:   DE = STKEND.
; ---------------------------------------------------------------------------------------------------------------------

FPSWOP13:     LD C,-10                  ; Exchange the first and third entries
              JR SWOPCOM1

FPSWOP23:     LD C,-5                   ; Exchange the second and third
              LD DE,-10
              JR SWOPCOM2

SWOP12:       LD C,-5                   ; Exchange the first and second

SWOPCOM1:     LD DE,-5

SWOPCOM2:     LD B,D                    ; B = &FF, since D is the high byte of a small negative number
              LD HL,(STKEND)
              ADD HL,DE
              LD D,H
              LD E,L                    ; DE = STKEND-5, or -10 for SWOP23
              ADD HL,BC                 ; HL = STKEND-10, or -15

; --- FPSWOP: the calculator entry, arriving with HL and DE already pointing at the two entries ---

FPSWOP:       LD B,NUMVALSIZE

FPSWOPLP:     LD A,(DE)
              LD C,(HL)
              LD (HL),A
              LD A,C
              LD (DE),A
              INC HL
              INC DE
              DJNZ FPSWOPLP

              LD DE,(STKEND)
              RET


; ---------------------------------------------------------------------------------------------------------------------
; IMPI -- the PI function
; ---------------------------------------------------------------------------------------------------------------------

IMPI:         CALL SABORTER             ; Skip PI, and abort if only checking

              DB CALC
              DB STKHALFPI
              DB EXIT

              INC (HL)                  ; Incrementing the exponent doubles it, giving pi
              RET


; ---------------------------------------------------------------------------------------------------------------------
; IMITEM -- the ITEM function: what kind of DATA remains in the current statement
;
; Exit:   0 nothing left in this DATA statement, 1 the next item is a string, 2 it is numeric.
; ---------------------------------------------------------------------------------------------------------------------

IMITEM:       CALL SABORTER

              IN A,(URPORT)
              PUSH AF
              CALL ADDRDATA             ; Look at where the DATA pointer stands
              LD BC,0
              LD A,(HL)
              CP " "
              JR Z,IMITEM2              ; A space follows the DATA keyword, so an item follows

              CP ","
              JR NZ,IMITEM3             ; Neither: everything in this statement has been read

IMITEM2:      INC C                     ; Assume a string
              CALL FORESP               ; Skip to the next significant character
              CP &22
              JR Z,IMITEM3              ; A quote confirms it

IMITEMLP:     LD A,(HL)
              INC HL
              CALL ALPHANUM
              JR C,IMITEMLP             ; Letters and digits may be part of a variable name

              CP " "
              JR Z,IMITEMLP             ; So may spaces

              CP "$"
              JR Z,IMITEM3              ; A name ending in '$' is a string

              INC C                     ; Otherwise numeric

IMITEM3:      POP AF
              OUT (URPORT),A
              JP STACKBC
