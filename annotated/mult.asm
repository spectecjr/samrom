; =====================================================================================================================
; MULT.ASM -- the four arithmetic operations: multiply, divide, add, subtract
; =====================================================================================================================
;
; This is the numeric heart of the floating-point calculator. Every routine here is a calculator binary operation:
; entered with HL pointing at N1 and DE at N2, both five-byte numbers on the calculator stack, and exiting with the
; result written over N1 and DE pointing just past it as the new STKEND.
;
; THE TWO NUMBER FORMATS
; ----------------------
; A five-byte number is either
;
;     00  sign  lo  hi  00       a small integer, sign &00 for positive or &FF for negative
;     exp m1 m2 m3 m4            floating point, value (0.1m1m2m3m4 binary) * 2^(exp-128)
;
; In the floating form bit 7 of m1 is the sign, and the "true numeric bit" it displaces is always 1 -- a normalised
; mantissa is in the range 0.5 to just under 1, so the leading bit is known and need not be stored. Routines that do
; real arithmetic put it back with SET 7,D / OR &80 before working, and mask it out again at the end.
;
; FAST PATHS
; ----------
; The code takes the cheapest route it can:
;
;   * If both operands are integers, multiply and add use plain 16-bit arithmetic and stay in integer form. Only on
;     overflow do they fall through to the floating-point code.
;   * If either operand is an exact power of two -- mantissa &80 00 00 00, so a single 1 bit -- multiply and divide
;     reduce to adding or subtracting exponents and exclusive-oring the sign bits.
;   * Otherwise the full 32-bit shift-and-add algorithms below run.
;
; REGISTER CONVENTION IN THE FULL ROUTINES
; ----------------------------------------
; MUDIADSR unpacks both operands into registers, using the alternate set as the high halves of 32-bit quantities:
; HL'HL and DE'DE each hold a 32-bit mantissa, BC holds the two exponent bytes, and the result's sign bit sits in
; bit 7 of a value pushed on the stack. Below it on the stack is the pointer to N1, where the answer is finally
; written by LDMRSLT.
;
; SHARED TAILS
; ------------
; Multiply and divide converge at DIVISE, which normalises the result and rounds it; addition joins at FPADDNEN for
; the rounding step and subtraction at FPSUBNEN for the exponent range check and the store. This sharing is why the
; entry conditions of those three labels are spelled out so carefully in the original comments.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; QMULT -- unsigned 16-bit multiply, HL = HL * DE
;
; A shift-and-add loop over the bits of the original HL. If either operand fits in eight bits the routine swaps them
; if necessary so the eight-bit one is the multiplier, and runs only the second half of the loop.
;
; Entry:  HL, DE = the operands.
; Exit:   HL = the product; CY set on overflow past 16 bits, in which case HL is meaningless.
; Uses:   HL, AF. BC and DE are preserved.
; ---------------------------------------------------------------------------------------------------------------------

QMULT:        PUSH BC
              LD B,8                        ; Bits to do
              LD A,H
              AND A
              JR Z,QMULT2                   ; HL is only eight bits, so the short loop will do

              EX DE,HL                      ; Try the other way round
              LD A,H
              AND A

QMULT2:       LD C,L
              LD HL,0
              JR Z,SHORTMUL                 ; The multiplier fits in eight bits

QHLLP2:       ADD HL,HL                     ; Double the running product
              JR C,QOVERFL

              RLA                           ; Next bit of the multiplier's high byte
              JR NC,NOQADN

              ADD HL,DE
              JR C,QOVERFL

NOQADN:       DJNZ QHLLP2

              LD B,8

SHORTMUL:     LD A,C                        ; A = the multiplier's low byte

QHLLOOP:      ADD HL,HL
              JR C,QOVERFL

              RLA
              JR NC,NOQADDIN

              ADD HL,DE
              JR C,QOVERFL

NOQADDIN:     DJNZ QHLLOOP

QOVERFL:      POP BC
              RET                           ; NC: HL holds the product


; =====================================================================================================================
; FPMULT -- calculator multiply
; =====================================================================================================================
;
; Entry:  HL -> N1, DE -> N2 on the calculator stack; STKEND already pushed by the calculator.
; Exit:   The product replaces N1; DE = the new STKEND.
; ---------------------------------------------------------------------------------------------------------------------

FPMULT:       LD A,(DE)
              OR (HL)
              JR NZ,FPMULT2                 ; At least one operand is floating point

; --- Both are integers: try a 16-bit multiply and keep the result in integer form ---

              PUSH DE                       ; N2 pointer
              PUSH HL                       ; N1 pointer
              CALL FETCHI                   ; DE = |N1|, C = its sign
              PUSH DE
              LD B,C
              INC HL
              INC HL                        ; Point at N2
              CALL FETCHI
              POP HL                        ; HL = N1
              LD A,C
              XOR B
              LD C,A                        ; Signs multiply: unlike signs give a negative result
              CALL QMULT
              POP DE                        ; N1 pointer
              EX DE,HL                      ; HL -> N1, DE = the product
              JR C,QMOVERF                  ; Too big for 16 bits, so redo it in floating point

              JR STICZ


; ---------------------------------------------------------------------------------------------------------------------
; STORADE -- store integer DE at (HL), with the sign given as 1 or &FF in A
;
; The CP/SBC/CPL sequence maps 1 to &FF and &FF to &00, which is the sign convention STOREI wants. The PUSH DE only
; exists to balance the POP that STOREI performs to fetch the new STKEND.
; ---------------------------------------------------------------------------------------------------------------------

STORADE:   CP 2
           SBC A,0                          ; 01 -> 00, FF -> FF
           CPL                              ; 01 -> FF, FF -> 00
           LD C,A
           PUSH DE                          ; Balance STOREI's POP

STICZ:     LD A,D
           OR E
           JR NZ,STOREI

           LD C,A                           ; Zero is always stored as positive


; ---------------------------------------------------------------------------------------------------------------------
; STOREI -- write a small integer to (HL)
;
; Entry:  HL -> the five-byte slot, DE = the magnitude, C = the sign (&00 or &FF), new STKEND on the stack.
; Exit:   DE = the new STKEND.
; Notes:  Negative values are stored as the two's complement of the magnitude, not as sign and magnitude.
; ---------------------------------------------------------------------------------------------------------------------

STOREI:       LD (HL),0                     ; Byte 0 = 0 marks the integer form
              INC HL
              LD (HL),C                     ; Sign
              INC HL
              INC C
              JR NZ,STORPI                  ; Positive

              LD A,E                        ; Negative, so store the two's complement
              CPL
              LD E,A
              LD A,D
              CPL
              LD D,A
              INC DE

STORPI:       LD (HL),E
              INC HL
              LD (HL),D
              POP DE                        ; New STKEND
              RET


; ---------------------------------------------------------------------------------------------------------------------
; FETCHI -- read a small integer from (HL)
;
; Entry:  HL -> the five-byte slot.
; Exit:   DE = the magnitude, C = the sign byte, HL -> the high byte of the stored value.
; ---------------------------------------------------------------------------------------------------------------------

FETCHI:       INC HL
              LD C,(HL)
              INC HL
              LD E,(HL)
              INC HL
              LD D,(HL)
              DEC C
              INC C
              RET Z                         ; Positive: the stored value is already the magnitude

; --- NEGDE / CPLDE: negate DE, returning Z if the result is zero ---

NEGDE:        DEC DE

CPLDE:        LD A,E
              CPL
              LD E,A
              LD A,D
              CPL
              LD D,A
              OR E                          ; Z if DE is now zero
              RET

; --- NEGDEDE: negate the 32-bit quantity in DE'DE. Exits with the alternate register set selected ---

NEGDEDE:      CALL NEGDE
              EXX
              JR NZ,CPLDE                   ; The low word was non-zero, so the high word is only complemented

              JR NEGDE                      ; The low word borrowed, so the high word must also be decremented


; --- The integer multiply overflowed; discard the integer working and fall into the floating-point path ---

QMOVERF:      POP DE                        ; N2 pointer


; =====================================================================================================================
; FPMULT2 -- floating-point multiply
; =====================================================================================================================
;
; Entry:  HL -> N1, DE -> N2.
; ---------------------------------------------------------------------------------------------------------------------

FPMULT2:      CALL DFPFORM                  ; Convert both to floating form. Z if N1 is a power of two, CY if it is
                                            ; zero; F' says the same about N2
              RET C                         ; N1 is zero, so the product is zero -- and N1 is already that zero

              EX AF,AF'
              JR C,MSETZ2                   ; N2 is zero

              PUSH HL                       ; N1 pointer
              EX AF,AF'
              JR Z,FPQM1                    ; N1 is a power of two

              EX AF,AF'
              JR NZ,FPMULT3                 ; Neither is a power of two, so do it the long way

; --- One or both operands is an exact power of two: mantissa &80 00 00 00 or &00 00 00 00.
;     Exclusive-oring the mantissas produces the right sign bit and copies whichever mantissa is non-trivial, so all
;     that remains is to add the exponents. ---

FPQM1:        LD A,(DE)                     ; N2 exponent
              LD C,A
              LD B,0
              LD L,(HL)                     ; N1 exponent
              LD H,B
              ADD HL,BC
              LD BC,-129                    ; Remove one excess-128 bias, and one for the implied 0.1 mantissa

; --- FPQMDC: also entered from the quick divide, with BC = +129 ---

FPQMDC:       ADD HL,BC
              INC H
              JR Z,MSETZERO                 ; Exponent underflowed: the result is zero

              DEC H
              JP NZ,NTLERR                  ; Exponent overflowed: "number too large"

              LD A,L                        ; Result exponent
              AND A
              JR Z,MSETZERO                 ; Exponent zero also means zero

              POP HL                        ; N1 pointer
              LD (HL),A
              LD B,4

FPQMULP:      INC HL
              INC DE
              LD A,(DE)
              XOR (HL)                      ; Combine the sign bits and copy the non-zero mantissa
              LD (HL),A
              DJNZ FPQMULP

              INC HL
              EX DE,HL                      ; DE = the new STKEND
              RET

MSETZERO:     POP HL                        ; Discard the N1 pointer

MSETZ2:       JP SETFALSE                   ; Leave zero as the result


; ---------------------------------------------------------------------------------------------------------------------
; FPMULT3 -- the general 32 x 32 bit mantissa multiply
;
; The multiplier is held in A'B'C'A, the multiplicand in DE'DE, and the 32-bit running product in HL'HL. For each of
; the 32 multiplier bits, taken from the least significant end, the multiplicand is conditionally added and the
; product is then halved -- so the product accumulates in place without ever needing 64 bits.
;
; If a whole multiplier byte is zero the eight halvings are done as a byte-wide shift instead, which is much faster.
; The bits that fall off the bottom of the product are kept in A; the top two of them are needed for rounding.
; ---------------------------------------------------------------------------------------------------------------------

FPMULT3:      CALL MUDIADSR                 ; N1 to B DE'DE, N2 to C A'B'C'A, result sign pushed, true numeric bits set

              PUSH BC                       ; The two exponent bytes
              LD HL,0                       ; Product, low word
              EXX
              LD HL,0                       ; Product, high word
              EXX

              LD C,4                        ; Four multiplier bytes

FPMULCLP:     LD B,8                        ; Eight bits in each
              AND A
              JR NZ,FPMULBLP                ; This byte has at least one bit set

; --- The whole byte is zero, so the only effect is to shift the product right eight places ---

              LD B,L                        ; The bits shifted out
              LD L,H

              EXX
              LD A,L
              LD L,H
              LD H,0
              EXX

              LD H,A                        ; 0 -> H' -> L' -> H -> L -> B
              JR NXMBYTE

FPMULBLP:     RRA                           ; Test the next multiplier bit, low end first
              JR NC,FPMULT25

              ADD HL,DE                     ; Add the multiplicand: HL'HL += DE'DE
              EXX
              ADC HL,DE
              EXX

FPMULT25:     EXX                           ; Halve the product
              RR H
              RR L                          ; High word
              EXX
              RR H
              RR L                          ; Low word, taking the carry from above
              DJNZ FPMULBLP

              RRA
              LD B,A                        ; Keep the bits that fell off, in case this was the last byte

NXMBYTE:      EXX
              LD A,C
              LD C,B
              EX AF,AF'
              LD B,A
              EX AF,AF'                     ; A' -> B' -> C' -> A: A is now the next multiplier byte
              EXX

              DEC C
              JR NZ,FPMULCLP

              LD A,B                        ; The lost bits; only 7 and 6 matter for rounding
              LD B,C                        ; C is zero here
              EX DE,HL                      ; Keep the product's low word in DE
              POP HL                        ; The exponent bytes, both known non-zero
              LD C,H                        ; BC = N1 exponent
              LD H,B                        ; HL = N2 exponent
              ADD HL,BC                     ; Both carry a +128 bias, so the sum is 128 too large
              LD BC,-&80


; ---------------------------------------------------------------------------------------------------------------------
; DIVISE -- normalise and round the result of a multiply or a divide
;
; Entry:  HL'DE = the 32-bit mantissa, A = the bits that fell off the bottom, BC = the exponent correction
;         (-&80 from multiply, +&81 from divide), HL = the combined exponent, and on the stack the result sign in
;         bit 7 of an AF value, below it the N1 pointer.
;
; The smallest possible product of two normalised mantissas is 0.5 * 0.5 = 0.25, so at most one left shift is ever
; needed to renormalise. The same is true of the division result, which is why the two share this code.
; ---------------------------------------------------------------------------------------------------------------------

DIVISE:       ADD HL,BC                     ; Correct the exponent bias
              EXX
              BIT 7,H                       ; H' -- the top bit of the mantissa
              JR NZ,MULNORM                 ; Already normalised

              EXX
              DEC HL                        ; One more halving of the value, so one less on the exponent
              RLA                           ; Shift the mantissa left, pulling in the top lost bit
              RL E
              RL D
              EXX

              ADC HL,HL

MULNORM:      EXX
              RLA                           ; The next lost bit decides the rounding


; ---------------------------------------------------------------------------------------------------------------------
; FPADDNEN -- round up if CY, then fall into the store
;
; Also entered from FPADDN with CY set if the addition needs rounding up. The increment ripples through all four
; mantissa bytes; if it carries out of the top the mantissa becomes 0.1000... and the exponent is incremented.
; ---------------------------------------------------------------------------------------------------------------------

FPADDNEN:     JR NC,RNDDONE

              INC E
              JR NZ,RNDDONE

              INC D
              JR NZ,RNDDONE

              EXX
              INC L
              EXX
              JR NZ,RNDDONE

              EXX
              INC H
              EXX
              JR NZ,RNDDONE

              INC HL                        ; The carry rippled all the way out
              EXX
              LD H,&80                      ; Mantissa becomes 0.1000000
              EXX

RNDDONE:      POP AF                        ; Bit 7 = the result sign


; ---------------------------------------------------------------------------------------------------------------------
; FPSUBNEN -- range-check the exponent and write the result
;
; Entry:  bit 7 of A = the sign, HL'DE = the mantissa, HL = the exponent, (SP) = the N1 pointer.
; ---------------------------------------------------------------------------------------------------------------------

FPSUBNEN:     INC H
              JP Z,MSETZERO                 ; Exponent went negative: underflow to zero

              DEC H
              JP NZ,NTLERR                  ; Exponents are one byte, so H must be zero by now

              INC L
              DEC L
              JP Z,MSETZERO                 ; Exponent zero means the value is zero

              EXX
              PUSH HL                       ; Fetch the mantissa's high word out of HL'
              EXX

              POP BC
              XOR B
              AND &80                       ; Take bit 7 from the sign, the rest from the mantissa
              XOR B
              LD B,L                        ; B = the exponent

LDMRSLT:      POP HL                        ; N1 pointer
              LD (HL),B                     ; Exponent
              INC HL
              LD (HL),A                     ; Mantissa 1, with the sign in bit 7
              INC HL
              LD (HL),C
              INC HL
              LD (HL),D
              INC HL
              LD (HL),E
              INC HL
              EX DE,HL                      ; DE -> N2, which becomes the new STKEND
              RET


; =====================================================================================================================
; FPDIVN -- calculator divide
; =====================================================================================================================
;
; A restoring 34-bit division. The mantissa quotient of two normalised numbers lies between 0.5/0.999 and
; 0.999/0.5, that is between roughly 0.5 and 2.0; the algorithm used here produces half that range, 0.25 to 0.999,
; so the exponent is always incremented by one to compensate. A 33rd bit may be needed to renormalise and a 34th
; for rounding, which is why the loop counter C runs &FD, &FE, &FF, &00 -- four bytes, and then a two-bit tail.
;
; Entry:  HL -> N1 (dividend), DE -> N2 (divisor).
; ---------------------------------------------------------------------------------------------------------------------

FPDIVN:       CALL DFPFORM                  ; Both to floating form; Z if N1 is a power of two, CY if it is zero
              RET C                         ; 0/n is zero, and N1 already holds it

              PUSH HL                       ; N1 pointer
              EX AF,AF'
              JP C,NTLERR                   ; Division by zero reports "number too large"

              JR NZ,FPDIVN2                 ; N2 is not a power of two, so do it the long way

; --- N2 is an exact power of two, so the division is just an exponent subtraction ---

FPQD1:        LD A,(DE)
              LD C,A
              LD B,0
              LD L,(HL)
              LD H,B                        ; NC here, as required by the SBC
              SBC HL,BC                     ; N1 exponent - N2 exponent
              LD BC,129                     ; Restore the bias lost in the subtraction, plus one
              JP FPQMDC


; ---------------------------------------------------------------------------------------------------------------------
; FPDIVN2 -- the general 32-bit mantissa division
;
; The divisor is negated once, up front, so each trial step is an addition rather than a subtract-and-compare. The
; quotient bits are rotated into A and shuffled through A'B'C'A a byte at a time, mirroring the multiply.
; ---------------------------------------------------------------------------------------------------------------------

FPDIVN2:      CALL MUDIADSR
              EX DE,HL
              EXX
              EX DE,HL
              EXX                           ; Divisor in DE'DE, dividend in HL'HL

              CALL NEGDEDE                  ; Negate the divisor
              EXX                           ; NEGDEDE exits with the alternate set selected

              PUSH BC                       ; The exponent bytes

           LD BC,&08FC                      ; B = 8 bits per byte. C counts &FC, &FD, &FE, &FF, 0 -- four result
                                            ; bytes, with the 33rd bit left in carry on the final pass
           JR FPDIVE

FPDIV3:    LD B,8

           EXX
           EX AF,AF'
           LD A,B
           EX AF,AF'
           LD B,C
           LD C,A                           ; A' <- B' <- C' <- A: shift the completed result bytes along
           EXX

FPDIVLP:   ADD HL,HL
           EXX
           ADC HL,HL                        ; Shift the dividend left
           EXX
           JR NC,FPDIVE

           ADD HL,DE                        ; The dividend overflowed, so the subtraction must succeed
           EXX
           ADC HL,DE
           SCF
           JR FPDIV4

FPDIVE:    ADD HL,DE                        ; Trial subtraction: add the negated divisor
           EXX
           ADC HL,DE
           JR C,FPDIV4                      ; It fitted, so keep it and record a 1 bit

           EXX                              ; It did not, so undo the subtraction
           SBC HL,DE
           EXX
           SBC HL,DE                        ; NC, so a 0 bit is recorded

FPDIV4:    EXX
           RLA                              ; Shift the quotient bit in
           DJNZ FPDIVLP

           INC C
           JP M,FPDIV3                      ; C was &FD, &FE or &FF: another whole byte to do

           PUSH AF                          ; The last whole result byte, or the 33rd and 34th bits

           LD B,2
           JR Z,FPDIVLP                     ; C reached 0: two more bits for normalisation and rounding

           EXX                              ; Move the result from A'B'C'A into HL'DE
           LD A,C
           EXX
           LD D,A
           EXX
           LD L,B                           ; L'
           EX AF,AF'
           LD H,A                           ; H'
           EXX
           POP AF                           ; The 33rd and 34th bits
           RRCA
           RRCA                             ; Move them to bits 7 and 6, where DIVISE expects them
           POP HL
           LD E,H

           POP BC                           ; The exponent bytes
           LD L,B
           LD H,0
           LD B,H                           ; HL = N1 exponent, BC = N2 exponent
           AND A
           SBC HL,BC
           LD C,&81                         ; +&80 restores the bias cancelled by the subtraction, and +1 corrects
                                            ; for the quotient landing in the 0.25 to 0.999 range

           JP DIVISE                        ; Normalise and round, shared with multiply


; =====================================================================================================================
; FPSUBN / FPADDN -- calculator subtract and add
; =====================================================================================================================
;
; Subtraction is addition with N2 negated.
; ---------------------------------------------------------------------------------------------------------------------

FPSUBN:       EX DE,HL
              PUSH HL
              CALL FPNEGAT                  ; Negate N2 in place
              POP HL
              EX DE,HL

FPADDN:       LD A,(DE)
              OR (HL)
              JR NZ,FPADDN2                 ; At least one operand is floating point

; --- Both are integers. Because negatives are stored in two's complement, a plain 16-bit add works; the sign of the
;     result is derived by adding the sign bytes and the carry out, which detects a genuine overflow. ---

              PUSH DE                       ; N2 pointer
              INC HL
              PUSH HL                       ; Pointer to N1's sign byte
              INC HL
              LD C,(HL)
              INC HL
              LD B,(HL)                     ; BC = N1
              INC HL
              INC HL
              INC HL
              LD A,(HL)                     ; N2's sign
              INC HL
              LD E,(HL)
              INC HL
              LD D,(HL)                     ; DE = N2
              EX DE,HL
              ADD HL,BC
              LD B,0
              EX DE,HL                      ; DE = N1 + N2
              POP HL                        ; Pointer to N1's sign
              ADC A,(HL)                    ; Sum of the sign bytes plus the carry out of the addition
              RRCA
              ADC A,B
              JR NZ,ADDNOVERF               ; The result will not fit in a signed 16-bit integer

              SBC A,A
              LD (HL),A                     ; The result's sign byte

              LD A,D                        ; Guard against producing a "minus zero"
              OR E
              JR NZ,MIN0OK

              LD A,(HL)
              INC A
              JR NZ,MIN0OK                  ; It is a genuine positive zero, so leave it

              DEC HL                        ; 00 FF 00 00 really means -65536, so store it in floating form
              LD (HL),&91                   ; Exponent
              INC HL
              LD (HL),&80                   ; Mantissa 0.1000... -- the value 65536, with the sign already set

MIN0OK:       INC HL
              LD (HL),E
              INC HL
              LD (HL),D
              INC HL
              LD (HL),B                     ; Clear mantissa 4, needed if the branch above ran
              POP DE                        ; New STKEND
              RET


; ---------------------------------------------------------------------------------------------------------------------
; FPADDN2 -- floating-point addition
;
; The operand with the smaller exponent is shifted right until the exponents agree, then the mantissas are combined.
; Whether that is an addition or a subtraction depends on whether the two signs match, which MUDIADSR has already
; worked out and left as bit 7 of the stacked flags.
; ---------------------------------------------------------------------------------------------------------------------

ADDNOVERF:    POP DE
              DEC HL                        ; Restore the N1 and N2 pointers

FPADDN2:      PUSH HL                       ; N1 pointer
              CALL DFPFORM
              CALL MUDIADSR                 ; N1 in DE'DE, N2 in HL'HL, exponents in BC, signs compared on the stack
              LD A,C
              SUB B                         ; CY if N1's exponent is the larger
              JR NC,FPADD2                  ; The larger exponent is already in C

              LD C,B
              NEG                           ; A = the exponent difference
              EX DE,HL
              EXX
              EX DE,HL                      ; Swap the mantissas so HL'HL always holds the number with the larger
              EXX                           ; exponent and DE'DE the one that needs shifting
              CALL ADDALIGN                 ; Returns with B = 0
              JR FPADD3

FPADD2:       CALL NZ,ADDALIGN              ; Nothing to shift if the exponents already match
              EX DE,HL
              EXX
              EX DE,HL
              EXX
              LD B,0                        ; BC = the common exponent

FPADD3:       POP AF                        ; Bit 7 set means the signs differ
              RLA
              JR C,FPSUBN2

              ADD HL,DE

              EXX
              ADC HL,DE
              EXX

              EX DE,HL                      ; Result in HL'DE
              POP HL                        ; N1 pointer
              PUSH HL
              INC HL                        ; Point at the sign byte of the result
              JR NC,FPADD4                  ; No overflow, so the exponent stands

              INC BC                        ; The sum overflowed, so halve it and bump the exponent

              EXX
              RR H                          ; The carry shifts back in as the new top bit
              RR L
              EXX

              RR D
              RR E                          ; CY now says whether the discarded bit calls for rounding up.
                                            ; Note that negatives round the same way as positives, so they become
                                            ; slightly more negative -- consistent with multiply and divide.

FPADD4:       LD A,(HL)
              PUSH AF                       ; The result's sign
              LD H,B
              LD L,C                        ; HL = exponent, HL'DE = mantissa
              JP FPADDNEN                   ; CY if it needs rounding up


; ---------------------------------------------------------------------------------------------------------------------
; FPSUBN2 -- the signs differ, so the magnitudes are subtracted
;
; The subtraction may borrow, meaning the result's sign is the opposite of N1's; in that case the sign bit is
; flipped and the mantissa negated. The result then needs renormalising, which unlike multiply and divide can take
; any number of left shifts -- subtracting two nearly equal numbers loses many leading bits.
; ---------------------------------------------------------------------------------------------------------------------

FPSUBN2:      AND A
              SBC HL,DE
              EXX
              SBC HL,DE                     ; High word
              JR NZ,FPSUBN3                 ; The high word is non-zero, so the result cannot be zero

              EX AF,AF'                     ; Preserve the carry: both Z and CY are possible here
              EXX
              LD A,H
              OR L
              EXX

              JP Z,MSETZERO                 ; The low word is zero too, so the result is exactly zero

              EX AF,AF'                     ; Recover the carry

; --- HL'HL holds the non-zero result; CY says the sign must be reversed ---

FPSUBN3:      POP DE
              PUSH DE                       ; N1 pointer
              INC DE
              LD A,(DE)
              JR NC,FPSUBN4                 ; The original sign stands

              XOR &80                       ; Flip N1's sign bit
              EX AF,AF'
              EX DE,HL                      ; High word
              EXX
              EX DE,HL                      ; Low word: the result is now in DE'DE
              CALL NEGDEDE                  ; Negate it; exits with the alternate set selected
              EX DE,HL
              EXX
              EX DE,HL                      ; Back into HL'HL
              EXX
              EX AF,AF'
              JR FPSUBN4

FPSUBNLP:     EXX
              DEC BC                        ; Each left shift costs one from the exponent
              ADD HL,HL
              EXX
              ADC HL,HL

FPSUBN4:      BIT 7,H                       ; H' -- the top bit of the mantissa
              JR Z,FPSUBNLP                 ; Keep shifting until it is normalised

              EXX
              EX DE,HL                      ; Result in HL'DE
              LD H,B
              LD L,C
              JP FPSUBNEN                   ; Bit 7 of A = the sign, HL = the exponent, (SP) = the N1 pointer


; ---------------------------------------------------------------------------------------------------------------------
; ADDALIGN -- shift DE'DE right until the exponents agree
;
; Entry:  DE'DE = the mantissa to shift, A = the number of places.
; Exit:   B = 0. The value is rounded up if the last bit shifted out was a 1.
; Notes:  A shift of 33 or more reduces the value to zero, so the count is capped there.
; ---------------------------------------------------------------------------------------------------------------------

ADDALIGN:     LD B,A
              CP 33
              JR C,ADDALILP

              LD B,33                       ; Anything more just shifts it to zero anyway

ADDALILP:     EXX
              SRL D
              RR E                          ; High word
              EXX
              RR D
              RR E                          ; Low word
              DJNZ ADDALILP

              RET NC                        ; No rounding needed -- always the case if the value shifted to zero

              INC E
              RET NZ

              INC D
              RET NZ

              EXX
              INC DE                        ; Cannot carry out: bit 7 of the high word started as 0
              EXX
              RET


; ---------------------------------------------------------------------------------------------------------------------
; MUDIADSR -- unpack both operands into registers, for multiply, divide and add
;
; Entry:  HL -> N1, DE -> N2, both already in floating form.
; Exit:   DE'DE = N1's mantissa, A'B'C'A = N2's mantissa, B = N1's exponent, C = N2's exponent.
;         The result's sign is pushed on the stack, in bit 7 of the flags word: set if the two signs differ.
;         D' and H' have the implied leading 1 bit restored.
; Notes:  The sign word is pushed *underneath* the return address, so the caller finds it on the stack after the RET.
; ---------------------------------------------------------------------------------------------------------------------

MUDIADSR:     INC DE
              LD A,(DE)                     ; N2's sign, in bit 7
              LD B,(HL)                     ; N1's exponent
              INC HL
              XOR (HL)                      ; Bit 7 is now set if the signs differ
              POP DE                        ; Return address
              PUSH AF
              PUSH DE                       ; Return address back on top
              LD D,(HL)                     ; N1 mantissa 1
              SET 7,D                       ; Restore the implied leading bit
              INC HL
              LD E,(HL)
              INC HL
              PUSH DE                       ; N1 mantissa bytes 1 and 2
              LD D,(HL)
              INC HL
              LD E,(HL)                     ; DE = N1 mantissa bytes 3 and 4
              INC HL
              LD C,(HL)                     ; BC = the two exponents
              INC HL
              EX AF,AF'
              LD A,(HL)                     ; A' = N2 mantissa 1
              OR &80                        ; Restore its implied leading bit
              EX AF,AF'
              INC HL
              LD A,(HL)
              INC HL

              EXX
              LD B,A                        ; B' = N2 mantissa 2
              LD L,A                        ; L' likewise, for the callers that want HL'HL
              EX AF,AF'
              LD H,A                        ; H' = N2 mantissa 1
              EX AF,AF'
              EXX

              LD A,(HL)
              INC HL

              EXX
              LD C,A                        ; C' = N2 mantissa 3
              POP DE                        ; DE' = N1 mantissa bytes 1 and 2
              EXX

              LD L,(HL)                     ; L = N2 mantissa 4
              LD H,A                        ; H = N2 mantissa 3
              LD A,L                        ; A = N2 mantissa 4
              RET


; ---------------------------------------------------------------------------------------------------------------------
; DFPFORM -- put both (HL) and (DE) into floating-point form
;
; Equivalent to EX DE,HL : CALL FPFORM : EX AF,AF' : EX DE,HL : JP FPFORM.
;
; Exit:   Z if the number at HL is an exact power of two, CY if it is zero; F' says the same about the number at DE.
; ---------------------------------------------------------------------------------------------------------------------

DFPFORM:      CALL FPFORMX
              EX AF,AF'

FPFORMX:      EX DE,HL


; ---------------------------------------------------------------------------------------------------------------------
; FPFORM -- convert the number at (HL) to floating-point form if it is not already
;
; Exit:   HL and DE unchanged; A and BC corrupt. Z if the number is an exact power of two, CY if it is zero.
; Notes:  The power-of-two test is what lets multiply and divide take their fast paths.
; ---------------------------------------------------------------------------------------------------------------------

FPFORM:       LD A,(HL)
              AND A
              JR Z,FPFORM2                  ; Integer form, so it must be converted

              INC HL
              LD A,(HL)
              DEC HL
              AND &7F                       ; Mantissa 1 without the sign bit
              RET NZ                        ; Not a power of two

              PUSH HL                       ; It might be; the other three mantissa bytes must all be zero too
              INC HL
              INC HL
              OR (HL)                       ; Mantissa 2
              INC HL
              OR (HL)                       ; Mantissa 3
              INC HL
              OR (HL)                       ; Mantissa 4
              POP HL
              RET                           ; Z means an exact power of two

; --- Convert a small integer to floating-point form ---

FPFORM2:      PUSH DE
              CALL FETCHI                   ; DE = the magnitude, HL -> mantissa 3
              XOR A
              INC HL
              LD (HL),A                     ; Mantissa 4
              DEC HL
              LD (HL),A                     ; Mantissa 3 -- both are always zero for a 16-bit value
              DEC HL
              DEC HL                        ; Point at mantissa 1
              LD A,D
              LD C,&90                      ; Exponent for a value with bit 15 set: 2^16 scaled
              AND A
              JR NZ,FPFORM3                 ; More than eight bits, so start shifting from the high byte

              OR E
              JR Z,FPFORM4                  ; The integer is zero

              LD E,0                        ; Only the low byte is significant, so shift it up into A
              LD C,&89                      ; Exponent for an eight-bit value

FPFORMLP:     DEC C

FPFORM3:      RL E                          ; NC on the first pass, and thereafter from the RLA
              RLA
              JR NC,FPFORMLP                ; Shift left until the top bit reaches the carry

              RL (HL)                       ; The stored sign byte's bit 7 into carry
              RRA
              RR E                          ; Rotate the sign in where the implied leading bit was
              LD (HL),A
              INC HL
              LD (HL),E
              DEC HL
              DEC HL
              LD (HL),C                     ; The exponent
              AND &7F                       ; Ignore the sign bit
              OR E
              POP DE
              RET                           ; Z if the value is an exact power of two

FPFORM4:      DEC HL
              POP DE
              SCF                           ; The value is zero
              RET
