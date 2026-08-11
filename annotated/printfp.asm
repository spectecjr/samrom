; =====================================================================================================================
; PRINTFP.ASM -- convert a floating-point number to its printed decimal form
; =====================================================================================================================
;
; This file turns the number on top of the calculator stack into the character string BASIC prints, and is what STR$
; and every numeric PRINT ultimately call. The result is left in PRNBUFF with its length in BC.
;
; THE TWO STAGES
; --------------
; PRFPBUF produces a "raw" rendering: the significant digits, a leading zero, a leading minus if needed, and a
; decimal point only if the value has a fractional part. It records in EPOWER the power of ten it had to apply, and
; in DIGITS how many of the nine digit positions are still unused.
;
; PFSTRS then post-processes that raw form into what the user sees: rounding at the ninth digit, deleting trailing
; zeros, choosing between plain and exponent notation, inserting the leading "0.000" of a small fraction, and
; appending the "E+nn" suffix.
;
; The split exists because the rounding decision depends on the ninth digit, which only exists once the raw form has
; been generated -- and rounding can cascade all the way back to the leading zero, turning 0.99999999 into 1.
;
; GETTING THE DIGITS OUT
; ----------------------
; A binary mantissa cannot be converted to decimal one digit at a time without either division or a lot of care.
; The code sidesteps division entirely:
;
;   * The integer part is converted by DECIMIZE, a shift-and-DAA loop. Each bit of the binary value is shifted into
;     a five-byte packed-BCD accumulator which is simultaneously doubled by adding it to itself with DAA -- so after
;     n bits the accumulator holds the decimal value of those n bits.
;
;   * The fractional part is converted by repeated multiplication by ten. Each multiply pushes one decimal digit out
;     of the top of the 32-bit fraction, and TENX/TENMUL do that multiply with shifts and adds.
;
;   * Numbers too large or too small for that to work directly are first scaled by a power of ten, computed by
;     POFTEN using binary exponentiation, so that they land in the 8-or-9-digit integer range where DECIMIZE works.
;     DECDIGP and DECDIGN work out which power to use, from the binary exponent times log10(2).
;
; WORKING VARIABLES
; -----------------
;     DIGITS      digit positions remaining; reaching zero means the buffer is full
;     EPOWER      the power of ten applied, or 0 if the value needed no scaling
;     DECPNTED    non-zero once a decimal point has been emitted
;     NPRPOS      the current write position in PRNBUFF
;     FRACLIM     how many leading zeros a fraction may have before exponent form is used instead
;     BCDBUFF     the five-byte packed-BCD accumulator, which overlaps the tail of PRNBUFF
;
; =====================================================================================================================


; =====================================================================================================================
; PFSTRS -- render the number on the calculator stack into PRNBUFF
; =====================================================================================================================
;
; Exit:   DE -> PRNBUFF, BC = the length.
;
; PFSTRSC is the same entry with a caller-chosen FRACLIM. Nothing in the ROM calls it and it is not in the jump
; table, so FRACLIM is effectively fixed at 6: PFSTRS rewrites it on every call.
; ---------------------------------------------------------------------------------------------------------------------

PFSTRS:    LD A,6                           ; Up to four leading zeros in a fraction before exponent form is used

PFSTRSC:   LD (FRACLIM),A
           CALL PRFPBUF
           LD A,(DIGITS)
           AND A
           JR NZ,PFNRND                     ; Fewer than nine digits were produced, so the result is exact

; --- All nine digits were used, so the ninth decides whether to round up ---

           LD HL,(NPRPOS)
           DEC HL
           LD (NPRPOS),HL                   ; The ninth digit itself is discarded
           LD A,(HL)
           CP "5"
           JR C,PFNRND                      ; No rounding, as in 12345678.4

PFRNDLP:   LD (HL),"0"

PFPSLP:    DEC HL
           LD A,(HL)
           CP "."
           JR Z,PFPSLP                      ; Step over the decimal point

           INC A
           CP "9"+1
           JR NC,PFRNDLP                    ; This digit overflowed, so zero it and carry into the next. In the
                                            ; extreme case the carry ripples right back to the leading zero, which
                                            ; is why PRFPBUF always emits one.
           LD (HL),A

; --- Compute the length, and remove trailing zeros where they are not significant ---

PFNRND:    LD HL,(NPRPOS)
           LD DE,PRNBUFF
           AND A
           SBC HL,DE
           LD C,L
           LD B,H
           DEC L
           RET Z                            ; A single character can only be the zero, so return length 1

           ADD HL,DE
           INC HL                           ; HL = NPRPOS again
           LD A,(DECPNTED)
           AND A
           JR NZ,MTRZDLP                    ; A decimal point was used, so 1.2300 should lose its trailing zeros

EFCHECK:   LD A,(EPOWER)
           AND A
           JR Z,PFNPNT                      ; Not exponent form, so trailing zeros are significant

MTRZDLP:   DEC C
           DEC HL
           LD A,(HL)
           CP "0"
           JR Z,MTRZDLP

           LD A,(HL)
           CP "."
           JR Z,EFCHECK                     ; The point itself is dropped; if this is not exponent form we are done,
                                            ; otherwise the point was notional and more zeros may follow

           INC C                            ; Put back the last character, which was neither "0" nor "."

; --- Remove the leading zero, unless rounding consumed it ---

PFNPNT:    LD A,(DE)
           CP "-"
           JR NZ,PFNMIN                     ; Step over a leading minus

           INC DE
           LD A,(DE)

PFNMIN:    CP "0"
           JR NZ,PFEXIT                     ; The leading zero was used by the rounding, as when 0.0998 rounds to
                                            ; 0.0999 but 0.0999 rounds to 0.1000 -- one fewer division by ten

           LD A,(EPOWER)
           DEC A                            ; 0 becomes &FF
           CP &80                           ; CY if the power is positive and non-zero, that is a fraction
           ADC A,1                          ; Leaves A unchanged if the power was zero or negative, else adds one
           CP 8
           JR Z,PFNEZ                       ; A fraction that rounded all the way up to 1

           LD (EPOWER),A                    ; An extra leading zero compensates for the division that was skipped

PFNEZ:     DEC C                            ; The leading zero is about to go, so the length drops
           LD A,C
           LD HL,(NPRPOS)
           DEC HL
           LD (NPRPOS),HL                   ; Keep NPRPOS consistent for the nine-digit integer path below
           LD H,D
           LD L,E
           INC HL
           LD C,10
           LDIR                             ; Shift left: 01.23 becomes 1.23
           LD C,A

; --- Decide between plain and exponent notation ---

PFEXIT:    LD DE,PRNBUFF
           LD A,(DIGITS)
           LD HL,DECPNTED
           OR (HL)
           LD L,A                           ; L = 0 only for a nine-digit integer
           LD A,(EPOWER)
           LD H,A
           AND A
           LD A,L
           JR NZ,PFEFORM                    ; Exponent form; fractions are always nominally exponent form

; --- Not scaled, but a nine-digit integer must still be printed in exponent form ---

           AND A
           RET NZ                           ; Fewer than nine digits, so print it as it stands

           DEC A
           LD (EPOWER),A                    ; A power of &FF corresponds to E+8
           JR PFNRND

PFEFORM:   AND A
           JR Z,PFPOWOK                     ; A nine-digit integer produced by the scaling, so the mantissa is
                                            ; already in the 0.x form the exponent assumes

           INC H                            ; Otherwise the form is like 12345678.9, because the chosen power was
                                            ; too small; bumping the exponent converts 0.x to x.x

PFPOWOK:   LD A,(FRACLIM)                   ; Normally 6, allowing up to four leading zeros
           LD L,A
           LD A,H
           SUB 8
           JR Z,PFSPBH                      ; Rounding removed the leading zeros entirely, as 0.999999 to 1

           CP L
           JR C,PFFRACT                     ; 1 for 0.1, 2 for 0.01, up to 5 for 0.00001

           BIT 7,H
           JR Z,NEGEFORM

           CPL

; --- Append the "E+nn" or "E-nn" suffix ---

NEGEFORM:  LD L,&2F                         ; "0" minus one; the loop below does the first INC

CALCELP:   INC L
           SUB 10
           JR NC,CALCELP                    ; Repeated subtraction gives the tens digit in L

           ADD A,&3A                        ; And converts the remainder to the units digit
           PUSH AF
           EX DE,HL                         ; E = the tens digit, A = the units digit
           ADD HL,BC                        ; HL now points just past the digits already in the buffer
           LD (HL),"E"
           INC HL
           LD (HL),"+"
           BIT 7,D
           JR NZ,POWSOK

           LD (HL),"-"

POWSOK:    INC HL
           LD A,E
           CP "0"
           JR Z,POWL10                      ; A single-digit exponent needs no tens digit

           INC C
           LD (HL),E
           INC HL

POWL10:    POP AF
           LD (HL),A
           INC C
           INC C
           INC C                            ; The "E", the sign, and one digit
           LD HL,PRNBUFF
           LD A,(HL)
           CP "-"
           JR NZ,NOMINUS2

           INC HL

NOMINUS2:  INC HL                           ; Step over the first digit
           LD A,(HL)
           CP "E"

PFSPBH:    JR Z,PFSETPRB                    ; Something like 1E+7 needs no decimal point inserting

           INC C
           LD A,1
           CALL PFSPACE                     ; Open one byte after any minus sign
           INC HL
           INC HL                           ; Point at the gap, just after the first digit
           LD (HL),"."
           JR PFSETPRB


; ---------------------------------------------------------------------------------------------------------------------
; PFFRACT -- insert the leading "0.", "0.0", "0.00" and so on in front of a small fraction
;
; Entry:  A = the number of leading zeros needed, minus one; C = the current length.
; ---------------------------------------------------------------------------------------------------------------------

PFFRACT:   INC A
           CP 20                            ; PRINT USING can ask for up to seventeen leading zeros
           JR C,PFFRACT2

           LD A,19

PFFRACT2:  LD B,A                           ; 2 gives 0.1, 8 gives 0.0000001
           CALL PFSPACE
           INC HL                           ; Point at the gap
           LD A,C
           ADD A,B
           CP 22
           JR C,PFFRACT3

           LD A,21

PFFRACT3:  LD C,A                           ; The new length, capped at 21
           LD (HL),"0"
           LD A,"."                         ; The point goes in on the first pass, zeros thereafter
           JR FRACLPEN

FRACLZLP:  LD (HL),A
           LD A,"0"

FRACLPEN:  INC HL
           DJNZ FRACLZLP

PFSETPRB:  LD DE,PRNBUFF                    ; BC = the length
           RET


; ---------------------------------------------------------------------------------------------------------------------
; PFSPACE -- open a gap in PRNBUFF, just after any leading minus sign
;
; Entry:  A = the gap size, 1 to 19.
; Exit:   HL -> the byte before the gap. BC preserved.
; ---------------------------------------------------------------------------------------------------------------------

PFSPACE:   PUSH BC
           LD H,&FF
           NEG
           LD L,A                           ; HL = -gap
           PUSH HL
           LD BC,21                         ; The buffer length; this overlaps BCDBUFF, which is finished with by now
           ADD HL,BC                        ; So at most 15 bytes move, and fewer for a larger gap
           LD B,H
           LD C,L
           POP HL
           LD A,(PRNBUFF)
           CP "-"
           JR NZ,PFSKMIN

           DEC C                            ; A leading minus stays where it is

PFSKMIN:   LD DE,PRNBUFF+20                 ; Copy backwards from the end of the buffer
           ADD HL,DE
           LDDR
           POP BC
           RET


; =====================================================================================================================
; PRFPBUF -- render the number on the calculator stack in raw form
; =====================================================================================================================
;
; Produces the significant digits with no rounding, no exponent suffix and no inserted leading zeros. There is
; always exactly one leading zero, a leading minus if the value is negative, and a decimal point only if the value
; actually has a fractional part.
;
; Examples of the raw output: "-0.123", "01234.5", "01.2345".
;
; Exit:   PRNBUFF holds the digits, DIGITS counts the unused positions, EPOWER holds the power of ten applied.
; ---------------------------------------------------------------------------------------------------------------------

PRFPBUF:   LD HL,DIGITS
           LD (HL),10                       ; Ten positions, of which the leading zero takes one
           INC HL
           XOR A
           LD (HL),A                        ; EPOWER = 0, meaning not exponent form
           INC HL
           LD (HL),A                        ; DECPNTED = 0, no decimal point yet
           INC HL
           LD (NPRPOS),HL                   ; Start writing at the beginning of PRNBUFF

           DB CALC
           DB RESTACK                       ; Force the full floating form
           DB DROP
           DB EXIT                          ; DE -> just past the dropped number

           LD HL,5
           ADD HL,DE

           EX DE,HL                         ; HL -> the number, DE = the old STKEND
           INC HL
           BIT 7,(HL)                       ; NZ if negative
           DEC HL

           LD A,"-"
           CALL NZ,NPRINT
           CALL NPRZERO                     ; The leading zero gives rounding somewhere to carry into
           LD A,(HL)
           AND A
           RET Z                            ; The value is zero, and "0" is already in the buffer

           CP &81
           JR C,PRBORS                      ; Less than 1, so there is nothing before the binary point

           SUB &80                          ; The number of bits before the binary point, 1 to &7F
           CP 30
           JR NC,PRBORS                     ; More than 29 bits might not fit in nine decimal digits

; --- PRMEDN: the value is a manageable integer, so convert it directly ---

PRMEDN:    INC HL
           LD D,(HL)
           SET 7,D                          ; Restore the implied leading bit
           INC HL
           LD E,(HL)
           INC HL
           PUSH DE
           EXX
           POP HL                           ; High word into HL'
           EXX
           LD D,(HL)
           INC HL
           LD E,(HL)
           EX DE,HL                         ; Low word into HL
           CALL DECIMIZE                    ; Convert the top A bits of HL'HL to packed BCD
           EX DE,HL                         ; Keep the remaining low word safe
           CALL PRBCD                       ; Emit the BCD digits
           EX DE,HL
           RET C                            ; The buffer filled up

           LD A,H
           OR L
           EXX
           OR H
           OR L
           RET Z                            ; Nothing left below the binary point

; --- The bits left in HL'HL are the fraction. Multiply by ten repeatedly to shake out its digits ---

PRFRACT:   CALL NPRPNT                      ; Emit the decimal point
           EX DE,HL
           EXX
           EX DE,HL                         ; Move the value into DE'DE

PRFRLP:    XOR A                            ; No carry in on the first byte
           CALL TENX                        ; Low word times ten, carry out in A
           LD D,L
           EXX
           CALL TENX                        ; High word times ten, taking that carry in
           LD D,L
           EXX
           CALL NPRINTC                     ; The final carry out is the next decimal digit
           JR NC,PRFRLP

           RET


; ---------------------------------------------------------------------------------------------------------------------
; TENX / TENMUL -- multiply by ten with a carry digit
;
; TENX:   LE = DE*10 + A, leaving the carry digit in A.
; TENMUL: HL = C*10 + A, leaving the carry digit in A and the result byte in L.
;
; The multiply is (x*4 + x)*2, which is three ADD HL,HL and one ADD HL,BC.
; ---------------------------------------------------------------------------------------------------------------------

TENX:      LD C,E
           CALL TENMUL
           LD E,L
           LD C,D

TENMUL:    LD L,C
           LD H,0
           LD B,H
           ADD HL,HL
           ADD HL,HL
           ADD HL,BC                        ; Times five
           ADD HL,HL                        ; Times ten
           LD C,A
           ADD HL,BC                        ; Plus the incoming carry digit
           LD A,H                           ; H is the outgoing carry, L the result byte
           RET


; ---------------------------------------------------------------------------------------------------------------------
; PRBORS -- the value needs scaling by a power of ten before it can be converted
;
; Values below 1 have exponents of 1 to &80. An exponent of &80 means no zero bits after the binary point, &71 means
; fifteen of them, and so on.
;
; Entry:  CY if the value is small, NC if it is large.
; ---------------------------------------------------------------------------------------------------------------------

PRBORS:    LD (STKEND),DE                   ; Put the number back on the calculator stack
           JR NC,PRBIGN

           CALL DECDIGN                     ; How many leading decimal zeros the value has
           ADD A,9                          ; Scale up to an eight- or nine-digit integer
           JR SHIFTDEC

; --- A large value, exponent &9E to &FF, with at least nine decimal digits ---

PRBIGN:    CALL DECDIGP                     ; Decimal digits before the point, minus one -- nine or more
           SUB 9
           CPL                              ; Negate and offset, giving the power that scales it down to 8 or 9 digits

SHIFTDEC:  DEC A
           LD (EPOWER),A                    ; &FE is E+9, &FF is E+8, 0 is no scaling, 9 is E-1, 10 is E-2 ...
           INC A
           CALL POFTEN                      ; Multiply the stack top by ten to the power A

           CALL FDELETE
           LD A,(HL)                        ; The exponent of the scaled value
           SUB &80
           JP PRMEDN                        ; It is now an integer that DECIMIZE can handle


; ---------------------------------------------------------------------------------------------------------------------
; NPRINT family -- write one character to PRNBUFF
;
;   NPRPNT   emit "." and record that the value has a fractional part
;   NPRZERO  emit "0" and count it
;   NPRINTC  emit the digit in A, count it, and return CY once the buffer is full
;   NPRINT   emit the character in A without counting it, for "-" and "."
; ---------------------------------------------------------------------------------------------------------------------

NPRPNT:    LD A,"."
           LD (DECPNTED),A                  ; Mark the value as non-integer
           JR NPRINT

NPRZERO:   XOR A

NPRINTC:   ADD A,&30                        ; Digit to ASCII
           PUSH HL
           LD HL,DIGITS
           DEC (HL)
           JR NZ,NPRINT2                    ; Room remains

           SCF                              ; CY: the buffer is now full, though this character still goes in
           DB SKIP2LDHL                     ; LD HL,nn swallows the PUSH HL below, so this is a two-byte skip

NPRINT:    PUSH HL

NPRINT2:   AND A                            ; NC

NPRINT3:   LD HL,(NPRPOS)
           LD (HL),A
           INC HL
           LD (NPRPOS),HL
           POP HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; DECDIGP / DECDIGN -- how many decimal digits a power of two spans
;
; Multiplies the binary exponent by log10(2) = 0.30103 and truncates, which gives the number of decimal digits
; before the point minus one (DECDIGP), or the number of leading zeros after the point (DECDIGN).
;
; Entry:  A = the power of two. Enter at DECDIGN for a negative power, held as 1 to &80.
; Exit:   A = the digit count.
; ---------------------------------------------------------------------------------------------------------------------

DECDIGN:   LD C,A
           LD A,&80
           SUB C                            ; 1 to &80 becomes &7F down to 0

DECDIGP:   CALL STACKA

           DB CALC
           DB FIVELIT
           DB &7F,&1A,&20
           DB &9A,&85                       ; 0.30103, that is log10(2)
           DB MULT
           DB TRUNC
           DB DROP
           DB EXIT

           INC DE
           INC DE
           LD A,(DE)
           RET


; ---------------------------------------------------------------------------------------------------------------------
; DECIMIZE -- convert the top A bits of HL'HL to packed BCD in BCDBUFF
;
; Shift-and-double: each pass shifts one bit out of the top of the 32-bit value and into a five-byte BCD
; accumulator which is doubled at the same time. ADC A,A doubles a byte and adds the incoming carry; DAA then fixes
; up the result to packed BCD and produces the carry into the next byte. After A passes the accumulator holds the
; decimal value of those A bits -- up to ten BCD digits.
; ---------------------------------------------------------------------------------------------------------------------

DECIMIZE:  LD C,A

           XOR A
           LD B,5
           LD DE,BCDBUFF                    ; Clear the five-byte accumulator

ZBCDBLP:   LD (DE),A
           INC DE
           DJNZ ZBCDBLP

DECIMCLP:  ADD HL,HL
           EXX
           ADC HL,HL
           EXX                              ; Shift the next bit of HL'HL out into carry

           LD DE,BCDBUFF+4                  ; Work from the least significant BCD byte upwards
           LD B,5

DECIMBLP:  LD A,(DE)
           ADC A,A                          ; Doubles the byte and adds the incoming carry: from HL'HL on the first
                                            ; byte, from the previous DAA thereafter
           DAA
           LD (DE),A
           DEC DE
           DJNZ DECIMBLP

           DEC C
           JR NZ,DECIMCLP

           RET


; ---------------------------------------------------------------------------------------------------------------------
; PRBCD -- emit the packed-BCD accumulator to PRNBUFF as ASCII digits
;
; Uses RLD to rotate the whole five-byte buffer left one nibble at a time, which both extracts the next digit into A
; and shifts a marker nibble in behind it. The marker starts as &0F, so once it has travelled all the way through
; the buffer the routine sees a non-BCD value and stops.
;
; Exit:   NC if all the BCD digits were used, CY if the print buffer filled first.
; Uses:   HL, BC, AF.
; ---------------------------------------------------------------------------------------------------------------------

PRBCD:     LD C,1                           ; Non-zero means "still skipping leading zeros"
           LD A,&0F                         ; Clear the high nibble and mark the low one as a terminator

BCDDIG:    LD B,5
           LD HL,BCDBUFF+4

BCDROTL:   RLD                              ; Low nibble of (HL) into A, high nibble down to low, low nibble of A
                                            ; into the high nibble of (HL)
           DEC HL
           DJNZ BCDROTL

           JR NZ,PRDIGIT                    ; The last RLD produced a non-zero digit

           OR C
           JR NZ,BCDDIG                     ; A leading zero, so skip it. Otherwise A is a significant zero.

PRDIGIT:   LD C,B                           ; B is zero here, so leading-zero suppression ends
           AND &0F
           CP &0A
           RET NC                           ; The terminator marker came round, so all the digits are done

           CALL NPRINTC
           JR NC,BCDDIG

           RET


; ---------------------------------------------------------------------------------------------------------------------
; POFTEN -- multiply the top of the calculator stack by ten to the power A
;
; Binary exponentiation. The running power P starts at ten and is squared each pass, while B is shifted right one
; bit at a time; whenever a bit is set the accumulator is multiplied by the current P -- or divided by it, if the
; requested power was negative.
;
; Entry:  A = the power, with negative powers held as values above &80.
; Notes:  B is corrupted by the multiply, but the calculator preserves BC across its operations.
; ---------------------------------------------------------------------------------------------------------------------

POFTEN:    LD C,A                           ; Bit 7 of C records whether the power is negative
           BIT 7,C
           JR Z,POF10L1

           NEG

POF10L1:   LD B,A                           ; B = the magnitude of the power

           DB CALC
           DB STKTEN                        ; N1, P where P starts at ten
           DB EXIT

           JR POF10LPE                      ; Enter the loop at the shift, before the first squaring

POF10LP:   DB CALC
           DB DUP                           ; N1, P, P
           DB MULT                          ; N1, P*P -- square the running power
           DB EXIT

POF10LPE:  SRL B
           JR NC,POF10L3                    ; This bit of the power is clear, so nothing to do

           BIT 7,C
           JR NZ,POF10L2                    ; A negative power divides instead

           DB CALC
           DB STO0                          ; Keep P
           DB MULT                          ; N1*P
           DB RCL0                          ; N1*P, P
           DB EXIT

           JR POF10L3

POF10L2:   DB CALC
           DB STO0
           DB DIVN                          ; N1/P
           DB RCL0                          ; N1/P, P
           DB EXIT

POF10L3:   INC B
           DJNZ POF10LP                     ; Loop until B has been shifted down to nothing

           LD (STKEND),HL                   ; EXIT left HL pointing at the last value, which is the leftover P
           RET                              ; Dropping it leaves just the scaled number
