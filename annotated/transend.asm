; =====================================================================================================================
; TRANSEND.ASM -- transcendental functions: SIN, COS, TAN, EXP, LN, ATN, ASN, ACS and the power operator
; =====================================================================================================================
;
; Almost none of this file is Z80 code. Each function is a program for the floating-point calculator, written as a
; stream of opcode bytes between a DB CALC and a DB EXIT2. The calculator's fetch-execute loop is FPCMAIN in
; fpcmain.asm, and the opcode names used here are the EQUs defined there.
;
; Attribution: the sine and exponential approximations are credited in the original source to W. E. Thomson.
;
; READING A CALCULATOR PROGRAM
; ----------------------------
; The comment at the end of each line shows the calculator stack after that operation, top of stack rightmost. So
;
;     DB DUP            ; X,X
;     DB MULT           ; X*X
;
; reads "duplicate the top value, then multiply the two, leaving the square".
;
; Several opcodes are followed by inline operand bytes, which the interpreter steps over:
;
;   ONELIT   n            push the one-byte value n
;   FIVELIT  b1..b5       push a literal five-byte floating-point number
;   SOMELIT  len, ...     push several five-byte numbers at once; len is the total byte count
;   LDBREG   n            load the loop counter B with n
;   DECB     offset       decrement B and, if non-zero, jump by the signed offset
;   JPTRUE   offset       pop a flag; jump by the signed offset if it is true
;   JPFALSE  offset       likewise if it is false
;
; The signed offsets are relative to the byte after the offset itself, so DB &FC is a jump back four bytes.
;
; THE SERIES EVALUATIONS
; ----------------------
; Every function here reduces its argument to a small range and then evaluates a Chebyshev polynomial in that range
; by Clenshaw's recurrence -- the repeated "recall, multiply, add" pattern driven by a DECB loop. The coefficient
; block is pushed onto the calculator stack in one SOMELIT, so the loop simply consumes one stack entry per pass.
;
; ATN and LN share the longer twelve-term evaluator at SERIES, which is why LN's coefficient block is followed by an
; EXIT and a JR SERIES rather than by its own loop.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; FPSIN -- SIN, in radians
;
; The argument is folded into a quarter-turn range by REDARG, then a five-term odd polynomial in w*w is evaluated
; and multiplied by w. Because the series is in w*w and the final multiply supplies the odd factor, only five
; coefficients are needed for full working precision.
; ---------------------------------------------------------------------------------------------------------------------

FPSIN:     DB CALC                          ; X
           DB REDARG                        ; W, the reduced argument
           DB DUP
           DB DUP
           DB MULT                          ; W, W*W
           DB STOD0                         ; W  (memory 0 = W*W)
           DB STKHALFPI                     ; W, first coefficient
           DB SOMELIT
           DB 25                            ; Five five-byte coefficients follow

           DB &80,&A5,&5D,&E7,&2A
           DB &7D,&23,&35,&E0,&36
           DB &79,&99,&68,&97,&AE
           DB &74,&28,&0A,&10,&9E
           DB &6E,&E6,&4F,&48,&19

           DB LDBREG
           DB &05                           ; Five terms

SINELP:    DB RCL0                          ; Clenshaw step: acc = acc*(W*W) + next coefficient
           DB MULT
           DB ADDN
           DB DECB
           DB &FC                           ; Back to SINELP

           DB MULT                          ; Multiply the even series by W to make it odd
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPCOS -- COS, computed as SIN(x + pi/2)
; ---------------------------------------------------------------------------------------------------------------------

FPCOS:     DB CALC
           DB STKHALFPI
           DB ADDN
           DB SIN
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPTAN -- TAN, computed as SIN(x) / COS(x)
; ---------------------------------------------------------------------------------------------------------------------

FPTAN:     DB CALC
           DB DUP
           DB SIN
           DB SWOP
           DB COS
           DB DIVN
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPREDARG -- reduce an angle to the range the sine series needs
;
; Scales the argument into turns, discards the whole turns, and rescales so that a full turn is four units. The
; result is then folded through the symmetry of the sine curve so that the series only ever sees one quadrant.
; ---------------------------------------------------------------------------------------------------------------------

FPREDARG:  DB CALC
           DB FIVELIT
           DB &7E,&22,&F9
           DB &83,&6E                       ; 1/(2*pi)
           DB MULT                          ; X measured in whole turns
           DB DUP
           DB STKHALF                       ; Half a turn, that is 180 degrees
           DB ADDN
           DB INT
           DB SUBN                          ; X reduced to plus or minus half a turn
           DB ONELIT
           DB &04
           DB MULT                          ; Rescaled so a quarter turn is one unit
           DB DUP
           DB ABS
           DB STKFONE
           DB SUBN
           DB DUP
           DB GRTR0
           DB JPTRUE                        ; To REDARG2 if the value is outside one quadrant
           DB 3

           DB DROP
           DB EXIT2

REDARG2:   DB STKFONE                       ; Reflect through the quadrant boundary
           DB SUBN
           DB SWOP
           DB LESS0
           DB JPTRUE                        ; To REDARG3
           DB 2
           DB NEGATE

REDARG3:   DB EXIT2


; =====================================================================================================================
; FPEXP -- EXP, the natural exponential
; =====================================================================================================================
;
; e^x is computed as 2^(x/ln 2), because a power of two is nearly free: the integer part of the exponent is simply
; added to the result's exponent byte, and only the fractional part needs a series.
; ---------------------------------------------------------------------------------------------------------------------

FPEXP:     PUSH HL                          ; Pointer to the exponent byte of X

           DB CALC                          ; X
           DB FIVELIT
           DB &81,&38
           DB &AA,&3B,&29                   ; 1/ln 2

           DB MULT                          ; Y = X/ln 2; the answer is now 2^Y
           DB EXIT

           POP HL


; ---------------------------------------------------------------------------------------------------------------------
; FPPOWR2 -- compute 2^Y, where Y is on top of the calculator stack
;
; Y is split into its integer and fractional parts. A seven-term series gives 2^frac, and the integer part is then
; folded straight into the exponent byte -- the only Z80 code in this file of any length.
;
; Entry:  HL -> the exponent byte of the top stack entry.
; ---------------------------------------------------------------------------------------------------------------------

FPPOWR2:   PUSH HL

           DB CALC
           DB DUP
           DB INT                           ; Y, INT Y
           DB STO1                          ; The integer part is added to the exponent later
           DB SUBN                          ; W = Y - INT Y, the fractional part

           DB STOD0                         ; Memory 0 = W
           DB STKFONE                       ; The leading coefficient is 1
           DB SOMELIT
           DB 35                            ; Seven five-byte coefficients follow

           DB &80,&31,&72,&18,&16
           DB &7E,&75,&FD,&E5,&E7
           DB &7C,&63,&59,&85,&4A
           DB &7A,&1D,&82,&11,&42
           DB &77,&30,&07,&1F,&00
           DB &74,&15,&F0,&51,&92
           DB &71,&35,&A0,&6F,&0B

           DB LDBREG
           DB &07

EXPLP:     DB RCL0
           DB MULT
           DB ADDN
           DB DECB
           DB &FC                           ; Back to EXPLP

           DB RCL1                          ; 2^W, INT Y
           DB EXIT

           CALL FPTOA                       ; Fetch the integer part: CY if it exceeds &FF, Z if positive
           JR Z,FPEXP3                      ; Positive, and BC holds it

           JR NC,FPEXP2                     ; Negative and in range, held as &FF down to &01

           POP HL                           ; Out of range downwards, so the result underflows to zero

SETFALSH:  JP SETFALSE

FPEXP2:    NEG
           LD C,A
           DEC B                            ; Negate BC

FPEXP3:    POP HL                           ; Pointer to 2^W
           LD E,(HL)
           LD D,0                           ; DE = the exponent byte of 2^W
           EX DE,HL
           ADD HL,BC                        ; Adding the integer power scales by that power of two
           EX DE,HL                         ; DE = the new exponent, HL -> the value
           INC D
           JR Z,SETFALSH                    ; Underflow

           DEC D
           JP NZ,NTLERR                     ; Overflow: "number too large"

           LD A,E
           AND A
           JR Z,SETFALSH                    ; An exponent byte of zero also means zero

           LD (HL),A
           JP SETUPDE


; =====================================================================================================================
; FPPOWER -- the ^ operator, N1 to the power N2
; =====================================================================================================================
;
; The general case is exp(N2 * ln N1), but two special cases are handled first. If N2 is a small non-negative
; integer, up to &3F, repeated multiplication is both faster and exact. And zero to any non-zero power is zero,
; which the logarithm route could not produce.
;
; The B register is loaded from N2's low mantissa byte masked to six bits before the calculator starts; the
; STKBREG/SUBN/JPFALSE sequence then tests whether that guess actually equals N2.
; ---------------------------------------------------------------------------------------------------------------------

FPPOWER:   INC DE
           INC DE
           LD A,(DE)
           AND &3F
           LD B,A                           ; If N2 is in 0 to &3F this is its value

           DB CALC                          ; N1, N2
           DB DUP                           ; N1, N2, N2
           DB STKBREG                       ; N1, N2, N2, B
           DB SUBN                          ; N1, N2, N2-B
           DB JPFALSE                       ; To IPOWER if B really is N2
           DB &0C

           DB SWOP                          ; N2, N1
           DB DUP                           ; N2, N1, N1
           DB JPFALSE                       ; To ZPOWER if N1 is zero
           DB &05

           DB LOGN                          ; N2, ln N1
           DB MULT
           DB EXP                           ; e^(N2 * ln N1)
           DB EXIT2

; --- Zero raised to a non-zero power ---

ZPOWER:    DB SWOP                          ; 0, N2
           DB DROP                          ; 0
           DB EXIT2

; --- N1 raised to a small integer power, 0 to &3F ---

IPOWER:    DB DROP                          ; N1
           DB STOD0                         ; Memory 0 = N1
           DB STKONE                        ; The running product starts at 1
           DB STKBREG
           DB JPFALSE                       ; Power zero, so the answer is that 1
           DB &05

           DB RCL0
           DB MULT
           DB DECB
           DB &FD                           ; Multiply by N1 B times over

           DB EXIT2


; =====================================================================================================================
; FPLOGN -- LN, the natural logarithm
; =====================================================================================================================
;
; The exponent byte gives the logarithm's integer part directly: x = m * 2^e with m in 0.5 to 1, so
; ln x = e*ln 2 + ln m. The mantissa is left in place with its exponent forced to &80, reducing it to that range,
; and the exponent is recovered separately through the B register.
;
; If the reduced mantissa is below 0.8 it is doubled and one is taken off the exponent term, narrowing the range the
; series has to cover.
; ---------------------------------------------------------------------------------------------------------------------

FPLOGN:    DB CALC                          ; X
           DB RESTACK                       ; Force the full floating form
           DB DUP
           DB LESE0                          ; X, true if X <= 0
           DB DROP
           DB EXIT

           INC DE
           INC DE
           LD A,(DE)
           AND A
           JP NZ,INVARG                     ; Zero or negative: "invalid argument"

           LD A,(HL)                        ; The exponent byte of X
           LD (HL),&80                      ; Reduce the value to the range 0.5 to 0.999999
           LD B,A

           DB CALC
           DB STKBREG                       ; NX, the raw exponent byte
           DB ONELIT
           DB &80
           DB SUBN                          ; NX, the true exponent, possibly negative
           DB SWOP                          ; TE, NX
           DB DUP
           DB FIVELIT
           DB &80,&CC,&CC
           DB &CC,&CD                       ; -0.8
           DB ADDN                          ; TE, NX, NX-0.8
           DB GRTR0
           DB SWOP23                        ; NX, TE, flag
           DB JPTRUE                        ; To LOGN3 if NX is already at least 0.8
           DB &07

           DB STKFONE                       ; NX below 0.8: use 2*NX and TE-1 instead
           DB SUBN
           DB SWOP
           DB STKHALF
           DB DIVN                          ; Dividing by 0.5 doubles it
           DB SWOP

LOGN3:     DB FIVELIT
           DB &80,&31,&72
           DB &17,&F8                       ; ln 2
           DB MULT                          ; NX, TE * ln 2
           DB SWOP
           DB STKFONE
           DB SUBN                          ; The series is in NX-1
           DB DUP
           DB FIVELIT
           DB &82,&20,&00                   ; 2.5
           DB &00,&00
           DB MULT
           DB STKHALF
           DB SUBN                          ; 2.5*NX - 3, the Chebyshev argument
           DB STOD0
           DB SOMELIT
           DB 60                            ; Twelve five-byte coefficients follow

           DB &80,&6E,&23,&80,&93
           DB &7D,&A7,&9C,&7E,&5E
           DB &7A,&1B,&43,&CA,&36
           DB &77,&A0,&FE,&5C,&FC
           DB &74,&31,&9F,&B4,&00
           DB &71,&CB,&DA,&96,&00
           DB &6E,&70,&6F,&61,&00
           DB &6C,&90,&AA,&00,&00
           DB &69,&30,&C5,&00,&00
           DB &66,&DA,&A5,&00,&00
           DB &64,&09,&00,&00,&00
           DB &61,&AC,&00,&00,&00

           DB EXIT

           JR SERIES                        ; Share the twelve-term evaluator with ATN


; =====================================================================================================================
; FPARCTAN -- ATN
; =====================================================================================================================
;
; For |x| < 1 the series is evaluated directly. For |x| >= 1 the identity atn(x) = +/-pi/2 - atn(1/x) is used, which
; keeps the series argument small; the sign of the pi/2 term follows the sign of x.
; ---------------------------------------------------------------------------------------------------------------------

FPARCTAN:  DB CALC
           DB DUP                           ; X, X
           DB ABS                           ; X, |X|
           DB STKFONE
           DB SUBN                          ; X, |X|-1
           DB GRTE0
           DB DUP                           ; X, flag, flag -- 1 if |X| >= 1
           DB JPFALSE                       ; To ARCTAN2 with X and 0 on the stack
           DB &0B

           DB SWOP                          ; 1, X
           DB DIVN                          ; 1/X
           DB NEGATE                        ; -1/X
           DB DUP
           DB STKHALFPI                     ; -1/X, -1/X, pi/2
           DB SWOP
           DB LESS0
           DB JPTRUE                        ; To ARCTAN2 if -1/X is negative
           DB &02

           DB NEGATE                        ; Otherwise use -pi/2

ARCTAN2:   DB SWOP                          ; The offset term (0 or +/-pi/2), then V
           DB DUP
           DB DUP
           DB MULT                          ; V, V*V
           DB STKHALF
           DB DIVN                          ; V, 2*V*V
           DB STKFONE
           DB SUBN                          ; V, 2*V*V-1, the Chebyshev argument
           DB STOD0

           DB SOMELIT
           DB 60                            ; Twelve five-byte coefficients follow

           DB &80,&61,&A1,&B3,&0C
           DB &7C,&D8,&DE,&63,&BE
           DB &79,&36,&73,&1B,&5D
           DB &76,&B5,&09,&36,&BE
           DB &73,&42,&C4,&00,&00
           DB &70,&DB,&E8,&B4,&00
           DB &6E,&00,&36,&75,&00
           DB &6B,&98,&FD,&00,&00
           DB &68,&39,&BC,&00,&00
           DB &65,&E4,&8D,&00,&00
           DB &63,&0E,&00,&00,&00
           DB &60,&B2,&00,&00,&00

           DB EXIT


; ---------------------------------------------------------------------------------------------------------------------
; SERIES -- the shared twelve-term Chebyshev evaluator, used by LN and ATN
;
; Entry:  the twelve coefficients on the calculator stack, with the argument X = 2*t*t-1 on top of them.
;
; This is Clenshaw's recurrence in its two-register form. Memory 1 holds the previous partial sum and memory 2 the
; one before that, and each pass computes n' = c + n*2X - n''. The final RCL2/SUBN/MULT/ADDN combines the two
; partial sums into the answer.
; ---------------------------------------------------------------------------------------------------------------------

SERIES:    LD B,12

           DB CALC
           DB RCL0                          ; Only the coefficients and the argument X matter from here on
           DB STKHALF
           DB DIVN                          ; 2*X
           DB STOD0
           DB STKZERO
           DB STO1                          ; The recurrence starts at zero

SERILP:    DB DUP                           ; N, N
           DB RCL0
           DB MULT                          ; N, N*2X
           DB RCL1
           DB STO2                          ; Memory 2 remembers the older partial sum
           DB SUBN                          ; N, N*2X - N''
           DB SWOP23
           DB ADDN                          ; N, C + N*2X - N''
           DB SWOP
           DB STOD1
           DB DECB
           DB &F5                           ; Back to SERILP

           DB RCL2
           DB SUBN
           DB MULT
           DB ADDN
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPARCSIN -- ASN, from the identity asn(x) = 2 * atn( x / (1 + sqrt(1 - x*x)) )
;
; This half-angle form is used rather than atn(x/sqrt(1-x*x)) because it stays well conditioned as x approaches 1.
; ---------------------------------------------------------------------------------------------------------------------

FPARCSIN:  DB CALC                          ; X
           DB DUP
           DB DUP
           DB MULT                          ; X, X*X
           DB STKFONE
           DB SWOP
           DB SUBN                          ; X, 1-(X*X)
           DB SQR
           DB STKFONE
           DB ADDN                          ; X, sqrt(1-X*X)+1
           DB DIVN
           DB ATN
           DB STKHALF
           DB DIVN                          ; Dividing by 0.5 doubles it
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPARCCOS -- ACS, from acs(x) = pi/2 - asn(x)
; ---------------------------------------------------------------------------------------------------------------------

FPARCCOS:  DB CALC
           DB ASN
           DB STKHALFPI
           DB SWOP
           DB SUBN
           DB EXIT2
