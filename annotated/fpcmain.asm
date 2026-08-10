; =====================================================================================================================
; FPCMAIN.ASM -- The floating point calculator: opcode table and control loop
; =====================================================================================================================
;
; A byte-coded stack machine, entered by RST &28. The bytes following the RST are its program, and execution resumes
; after the terminating EXIT. See docs/machine-code-interface.md for how to drive it from outside the ROM.
;
; WHY IT EXISTS
; -------------
; Arithmetic sequences are written as calculator programs rather than as Z80 code because the byte codes are far
; more compact -- one byte per operation instead of a three-byte CALL. Much of the ROM's own numeric work, including
; most of the transcendental functions, is written this way, which is why calculator programs nest.
;
; THE STACK
; ---------
; Entries are five bytes each, growing upwards from FPSBOT with STKEND pointing at the first free byte. The same
; five bytes hold either a number or a string descriptor; see docs/tokenized-program-format.md for the number
; formats.
;
; OPCODE RANGES
; -------------
;   &00-&1F   Binary operations. Two entries are consumed and one produced, so DE is backed up five bytes before
;             dispatch and HL and DE point at the two operands.
;   &20-&5F   Unary operations. HL points at the single operand and DE at STKEND.
;   &C8-&CF   Store to a calculator memory and drop
;   &D0-&D7   Store to a calculator memory and keep
;   &D8-&DF   Recall from a calculator memory
;   &E0-&FF   Stack a constant
;
; Anything else raises ERR_FPC.
;
; =====================================================================================================================


; =====================================================================================================================
; FPATAB -- operation address table
; =====================================================================================================================
;
; Indexed by the opcode doubled. The EQU definitions of the opcode values are interleaved with the table, so that
; each name sits beside the routine it selects.
; ---------------------------------------------------------------------------------------------------------------------

; --- Binary operations ---

FPATAB:       DW FPMULT                 ; 00 multiply
              DW FPADDN                 ; 01 add, numeric
              DW FPCONCAT               ; 02 add, strings
              DW FPSUBN                 ; 03 subtract
              DW FPPOWER                ; 04 raise to a power
              DW FPDIVN                 ; 05 divide

              DW FPSWOP                 ; 06 exchange the top two entries
              DW FPDROP                 ; 07 discard the top entry

              DW FPMOD                  ; 08 MOD
              DW FPIDIV                 ; 09 DIV
              DW FPBOR                  ; 0A bitwise OR
              DW NONSENSE               ; 0B bitwise XOR -- never implemented
              DW FPBAND                 ; 0C bitwise AND

              DW FPOR                   ; 0D logical OR

MULT:      EQU &00
ADDN:      EQU &01
CONCAT:    EQU &02
SUBN:      EQU &03
POWER:     EQU &04
DIVN:      EQU &05
SWOP:      EQU &06
DROP:      EQU &07
MOD:       EQU &08
IDIV:      EQU &09
NUOR:      EQU &0D

              DW FPAND                  ; 0E n AND n
              DW FPNNOTE                ; 0F n <> n
              DW FPNLESE                ; 10 n <= n
              DW FPNGRTE                ; 11 n >= n
              DW FPNLESS                ; 12 n <  n
              DW FPNEQUAL               ; 13 n =  n
              DW FPNGRTR                ; 14 n >  n

              DW FPSAND                 ; 15 $ AND n
              DW FPSNOTE                ; 16 $ <> $
              DW FPSLESE                ; 17 $ <= $
              DW FPSGRTE                ; 18 $ >= $
              DW FPSLESS                ; 19 $ <  $
              DW FPSEQUAL               ; 1A $ =  $
              DW FPSGRTR                ; 1B $ >  $

; --- Internal binary operations ---

              DW FPSWOP13               ; 1C exchange the first and third entries
              DW FPSWOP23               ; 1D exchange the second and third
              DW FPJPTR                 ; 1E jump if true
              DW FPJPFL                 ; 1F jump if false

NUAND:     EQU &0E
NNOTE:     EQU &0F
NLESE:     EQU &10
NGRTE:     EQU &11
NLESS:     EQU &12
NEQUAL:    EQU &13
NGRTR:     EQU &14

SAND:      EQU &15
SNOTE:     EQU &16
SLESE:     EQU &17
SGRTE:     EQU &18
SLESS:     EQU &19
SEQUAL:    EQU &1A
SGRTR:     EQU &1B

SWOP13:    EQU &1C
SWOP23:    EQU &1D
JPTRUE:    EQU &1E
JPFALSE:   EQU &1F

; --- Internal unary operations ---

              DW FPJUMP                 ; 20 unconditional jump
              DW FPLDBREG               ; 21 load BREG from the next byte
              DW FPDECB                 ; 22 decrement BREG and jump if non-zero
              DW FPSTKBR                ; 23 stack BREG as a number
              DW FPUSEB                 ; 24 execute the opcode held in BREG
              DW FPDUP                  ; 25 duplicate the top entry
              DW FP1LIT                 ; 26 stack a one-byte literal
              DW FP5LIT                 ; 27 stack a five-byte literal
              DW FPSOMELIT              ; 28 stack several literals
              DW FPLKADDRB              ; 29 read a byte from an inline address
              DW FPLKADDRW              ; 2A read a word from an inline address
              DW FPREDARG               ; 2B reduce a trigonometric argument
              DW FPLESS0                ; 2C true if negative
              DW FPLESE0                ; 2D true if negative or zero
              DW FPGRTR0                ; 2E true if positive and non-zero
              DW FPGRTE0                ; 2F true if positive or zero
              DW FPTRUNCT               ; 30 truncate towards zero
              DW FPFORM                 ; 31 convert to floating point form
              DW FPPOWR2                ; 32 two to the power of
              DW FPEXIT                 ; 33 leave the calculator
              DW FPEXIT2                ; 34 leave, unwinding the RST frame
              DW FPEXIT2                ; 35 spare
              DW FPEXIT2                ; 36 spare
              DW FPEXIT2                ; 37 spare
              DW FPEXIT2                ; 38 spare

JUMP:      EQU &20
LDBREG:    EQU &21
DECB:      EQU &22
STKBREG:   EQU &23
USEB:      EQU &24
DUP:       EQU &25
ONELIT:    EQU &26
FIVELIT:   EQU &27
SOMELIT:   EQU &28
LKADDRB:   EQU &29
LKADDRW:   EQU &2A
REDARG:    EQU &2B
LESS0:     EQU &2C
LESE0:     EQU &2D
GRTR0:     EQU &2E
GRTE0:     EQU &2F
TRUNC:     EQU &30
RESTACK:   EQU &31
POWR2:     EQU &32
EXIT:      EQU &33
EXIT2:     EQU &34


; --- Functions reachable from BASIC. Priority 16, numeric argument, numeric result. ---

              DW FPSIN                  ; 39 SIN
              DW FPCOS                  ; 3A COS
              DW FPTAN                  ; 3B TAN
              DW FPARCSIN               ; 3C ASN
              DW FPARCCOS               ; 3D ACS
              DW FPARCTAN               ; 3E ATN
              DW FPLOGN                 ; 3F LN
              DW FPEXP                  ; 40 EXP

SIN:       EQU &39
COS:       EQU &3A
TAN:       EQU &3B
ASN:       EQU &3C
ACS:       EQU &3D
ATN:       EQU &3E
LOGN:      EQU &3F
EXP:       EQU &40

              DW FPABS                  ; 41 ABS
              DW FPSGN                  ; 42 SGN
              DW FPSQR                  ; 43 SQR
              DW FPINT                  ; 44 INT

              DW FPUSR                  ; 45 USR
              DW FPIN                   ; 46 IN
              DW FPPEEK                 ; 47 PEEK
              DW FPDPEEK                ; 48 DPEEK
              DW FPDVAR                 ; 49 DVAR
              DW FPSVAR                 ; 4A SVAR
              DW FPBUTTON               ; 4B BUTTON
              DW FPEOF                  ; 4C EOF
              DW FPPTR                  ; 4D PTR
              DW NONSENSE               ; 4E unused

ABS:       EQU &41
SGN:       EQU &42
SQR:       EQU &43
INT:       EQU &44
INP:       EQU &46
PEEK:      EQU &47
EOF:       EQU &4C

; --- Priority 15, string argument, numeric result ---

              DW FPUDG                  ; 4F UDG address
              DW NONSENSE               ; 50 unused
              DW FPLEN                  ; 51 LEN
              DW FPCODE                 ; 52 CODE

; --- Priority 15, string argument, string result ---

              DW FPVALS                 ; 53 VAL$

; --- Priority 15, string argument, numeric result ---

              DW FPVAL                  ; 54 VAL

; --- Priority 15, string argument, string result ---

              DW FPTRUSTR               ; 55 TRUNC$

UDGA:      EQU &4F
LEN:       EQU &51
CODE:      EQU &52
VALS:      EQU &53
VAL:       EQU &54

; --- Priority 16, numeric argument, string result ---

              DW FPCHRS                 ; 56 CHR$
              DW FPSTRS                 ; 57 STR$
              DW FPBINS                 ; 58 BIN$
              DW FPHEXS                 ; 59 HEX$
              DW FPUSRS                 ; 5A USR$
              DW FPINKEY                ; 5B INKEY$

CHRS:      EQU &56
STRS:      EQU &57
INKEY:     EQU &5B

; --- Functions with their own priorities ---

              DW FPNOT                  ; 5C NOT,    priority 4
              DW FPNEGAT                ; 5D NEGATE, priority 9

NOT:       EQU &5C
NEGATE:    EQU &5D


; --- Opcode values that are not table entries ---

CALC:      EQU &EF                      ; The RST &28 opcode itself, so "DB CALC" starts an inline program
STOD0:     EQU &C8                      ; Store to memory 0 and drop
STOD1:     EQU &C9
STOD2:     EQU &CA
STOD3:     EQU &CB
STOD4:     EQU &CC                      ; Used by the DRAW curve code

STO0:      EQU &D0                      ; Store to memory 0 and keep
STO1:      EQU &D1
STO2:      EQU &D2
STO3:      EQU &D3
STO4:      EQU &D4                      ; Used by the DRAW curve code
STO5:      EQU &D5                      ; Used by the DRAW curve code

RCL0:      EQU &D8                      ; Recall memory 0
RCL1:      EQU &D9
RCL2:      EQU &DA
RCL3:      EQU &DB
RCL4:      EQU &DC                      ; Used by the DRAW curve code
RCL5:      EQU &DD                      ; Used by the DRAW curve code

STKHALF:   EQU &E0                      ; Stack 0.5
STKZERO:   EQU &E1                      ; Stack 0
STK16K:    EQU &E2                      ; Stack 16384
STKFONE:   EQU &E6                      ; Stack 1.0 in floating point form
STKONE:    EQU &E9                      ; Stack 1 as an integer
STKTEN:    EQU &EC                      ; Stack 10
STKHALFPI: EQU &F0                      ; Stack pi/2


; =====================================================================================================================
; FPCMAIN -- the fetch-execute loop
; =====================================================================================================================
;
; Entry:  From RST &28, with IX pointing at the first opcode. B holds whatever the caller had, which becomes BREG.
; Exit:   On EXIT, back to the RST &28 handler in ROM0.
; ---------------------------------------------------------------------------------------------------------------------

FPCMAIN:   LD DE,(STKEND)

FPCLP:     LD BC,FPCLP
           PUSH BC                      ; Every handler returns here by RET
           LD (STKEND),DE               ; Refresh it: a binary operation has just combined two entries into one,
                                        ; or a value has been stacked

           LD A,(IX+0)                  ; The next opcode
           INC IX

; --- BREGEN: entered directly when the opcode is already in A ---

BREGEN:    LD HL,(RST28V)
           INC H
           DEC H
           CALL NZ,HLJUMP               ; A utility sees every opcode, with IX past it and DE = STKEND. That is
                                        ; enough to translate the whole ZX Spectrum calculator set through a lookup
                                        ; table, apart from its opcode &34.

           LD B,0
           CP &20
           JR C,FPCBIN                  ; &00-&1F: binary

           CP &60
           JR C,FPCUNA                  ; &20-&5F: unary

           ADD A,&20                    ; &E0-&FF becomes &00-&1F
           JR C,FPCONST

           ADD A,8                      ; &D8-&DF becomes &00-&07
           JR C,FPRCL

           LD HL,-NUMVALSIZE
           ADD HL,DE                    ; HL = the top entry, the source for a store
           ADD A,8                      ; &D0-&D7 becomes &00-&07
           JR C,FPSTO

           ADD A,8                      ; &C8-&CF becomes &00-&07
           JR C,FPSTOD

           RST &08
           DB ERR_FPC


; ---------------------------------------------------------------------------------------------------------------------
; FPCBIN / FPCUNA -- dispatch an operation
;
; Exit to the handler with HL and DE pointing at the operands: for a unary operation HL = STKEND-5 and DE = STKEND;
; for a binary one HL = STKEND-10 and DE = STKEND-5, so the result overwrites the first operand.
; ---------------------------------------------------------------------------------------------------------------------

FPCBIN:    LD HL,-NUMVALSIZE
           ADD HL,DE
           EX DE,HL                     ; Back DE up one entry

FPCUNA:    LD C,A
           RLC C                        ; Two bytes per table entry
           LD HL,FPATAB
           ADD HL,BC
           LD C,(HL)
           INC HL
           LD B,(HL)
           PUSH BC                      ; The handler's address
           LD HL,-NUMVALSIZE
           ADD HL,DE
           RET                          ; Enter the handler; CY is set


; ---------------------------------------------------------------------------------------------------------------------
; FPUSEB -- execute the opcode held in BREG
;
; How the expression evaluator performs a queued operator: the code is placed in B before the RST.
; ---------------------------------------------------------------------------------------------------------------------

FPUSEB:    LD A,(BCREG+1)
           JR BREGEN


; ---------------------------------------------------------------------------------------------------------------------
; FPSTOD / FPSTO / FPRCL -- the calculator memories
;
; Six five-byte slots at (MEM), by default MEMVAL. Store-with-drop is used about 27 times in the ROM, so it shares
; almost all its code with plain store.
; ---------------------------------------------------------------------------------------------------------------------

FPSTOD:    PUSH HL                      ; Drop: the stack top becomes STKEND-5
           DB SKIP1CP

FPSTO:     PUSH DE                      ; Keep: STKEND is unchanged

           EX DE,HL
           CALL LOCMEM1                 ; HL -> the memory slot, BC = 5
           EX DE,HL

           LDIR
           POP DE
           RET

FPRCL:     CALL LOCMEM1
           LDIR
           RET

LOCMEM1:   LD HL,(MEM)

LOCMEM2:   LD C,A
           ADD A,A
           ADD A,A
           ADD A,C                      ; The slot number times five
           LD C,A
           LD B,0
           ADD HL,BC
           LD C,NUMVALSIZE
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPCONST -- stack a constant from FPCTAB
;
; Entry:  A = the opcode minus &E0, which is a byte offset into the table. Many values are meaningless.
; ---------------------------------------------------------------------------------------------------------------------

FPCONST:   LD C,A
           LD HL,FPCTAB
           ADD HL,BC
           LD C,NUMVALSIZE
           LDIR
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPCTAB -- the constants, overlapping so that each opcode picks five consecutive bytes
; ---------------------------------------------------------------------------------------------------------------------

FPCTAB:    DB &80                       ; offset 0  -- 0.5
           DB 0                         ; offset 1  -- zero
           DB 0                         ; offset 2  -- 16384
           DB 0
           DB 0
           DB &40
           DB &81                       ; offset 6  -- 1.0 in floating point form
           DB 0
           DB 0
           DB 0                         ; offset 9  -- 1 as an integer
           DB 0
           DB 1
           DB 0                         ; offset &0C -- ten
           DB 0
           DB 10
           DB 0

           DB &81,&49,&0F,&DA,&A2       ; offset &10 -- pi/2


; ---------------------------------------------------------------------------------------------------------------------
; FPEXIT / FPEXIT2 -- leave the calculator
;
; FPEXIT2 also discards the RST &28 frame, so that a routine written as "DB CALC ... DB EXIT2" returns directly to
; the caller of the routine rather than to the code after its own RST.
; ---------------------------------------------------------------------------------------------------------------------

FPEXIT:    POP BC                       ; Discard the FPCLP loop address
           RET

FPEXIT2:   POP BC                       ; The loop address
           POP BC                       ; The RST &28 return
           POP AF                       ; The saved port value
           POP IX                       ; The caller's IX
           JP LRPOUT


; ---------------------------------------------------------------------------------------------------------------------
; FPDUP / FPDROP -- duplicate or discard the top entry
;
; DUP is unary, so HL is the entry and DE is STKEND. DROP is binary, so DE has already been backed up: doing nothing
; discards the top entry.
; ---------------------------------------------------------------------------------------------------------------------

FPDUP:     LD BC,NUMVALSIZE
           LDIR

FPDROP:    RET


; ---------------------------------------------------------------------------------------------------------------------
; FPLDBREG / FPDECB -- load BREG, or decrement it and loop
; ---------------------------------------------------------------------------------------------------------------------

FPLDBREG:  LD A,(IX+0)
           CP A                         ; Force Z, so the jump below is skipped
           JR FPLDDCC

FPDECB:    LD A,(BCREG+1)
           DEC A

FPLDDCC:   LD (BCREG+1),A
           JR Z,FPPSKIP                 ; The count reached zero, so fall out of the loop


; ---------------------------------------------------------------------------------------------------------------------
; FPJUMP -- jump by the signed displacement in the next byte
; ---------------------------------------------------------------------------------------------------------------------

FPJUMP:    LD A,(IX+0)
           LD C,A
           RLA
           SBC A,A
           LD B,A                       ; Sign-extend the displacement
           ADD IX,BC
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPJPFL / FPJPTR -- conditional jumps
;
; Both are binary operations, so the value tested is dropped as the branch is taken or not.
; ---------------------------------------------------------------------------------------------------------------------

FPJPFL:    CALL TSTZERO                 ; Z if the value at (DE) is zero
           JR FPJPTF

FPJPTR:    LD H,D
           LD L,E
           INC HL
           INC HL                       ; -> the low byte of the 1 or 0
           DEC (HL)                     ; Z when it was 1, meaning true

FPJPTF:    JR Z,FPJUMP

FPPSKIP:   INC IX                       ; Step over the displacement
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPSOMELIT / FP5LIT -- stack literals from the program
;
; SOMELIT takes a byte count first, so several five-byte constants can be stacked with one opcode.
; ---------------------------------------------------------------------------------------------------------------------

FPSOMELIT: LD B,(IX+0)
           INC IX
           DB SKIP2LDHL

FP5LIT:    LD B,NUMVALSIZE

FIVLTLP:   LD A,(IX+0)
           LD (DE),A
           INC IX
           INC DE
           DJNZ FIVLTLP

           RET                          ; DE is the new STKEND


; ---------------------------------------------------------------------------------------------------------------------
; FPLKADDRB / FPLKADDRW -- read memory at an inline address
; ---------------------------------------------------------------------------------------------------------------------

FPLKADDRB: CALL LKADDRSR
           JR STACKC

FPLKADDRW: CALL LKADDRSR
           JP STACKBC

LKADDRSR:  EX DE,HL
           LD E,(IX+0)
           INC IX
           LD D,(IX+0)
           INC IX
           EX DE,HL                     ; DE = STKEND again, HL = the address
           LD C,(HL)
           INC HL
           LD B,(HL)
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPSTKBR / FP1LIT -- stack a single byte
; ---------------------------------------------------------------------------------------------------------------------

FPSTKBR:   LD A,(BCREG+1)
           LD C,A
           JR STACKC

FP1LIT:    LD C,(IX+0)
           INC IX
           JR STACKC


; =====================================================================================================================
; Truth tests
; =====================================================================================================================
;
; Each overwrites the value with the integer 1 or 0.
; ---------------------------------------------------------------------------------------------------------------------

FPGRTE0:   CALL TSTZERO2                ; True if the value is positive or zero
           EX DE,HL
           JR Z,SETTRUE

FPGRTR0:   INC HL                       ; True if positive and non-zero
           LD A,(HL)
           RLA                          ; CY if negative
           DEC HL
           JR C,SETFALSE

           INC HL
           INC HL
           INC HL
           LD A,(HL)                    ; High byte
           DEC HL
           OR (HL)                      ; Low byte
           DEC HL
           DEC HL
           OR (HL)                      ; Exponent
           JR Z,SETFALSE

           JR SETTRUE

FPNOT:     CALL TSTZERO2                ; True if the value is zero
           EX DE,HL

ZTRUE:     JR Z,SETTRUE

           JR SETFALSE

FPLESE0:   CALL TSTZERO2                ; True if negative or zero
           EX DE,HL
           JR Z,SETTRUE

FPLESS0:   INC HL                       ; True if negative
           LD A,(HL)
           DEC HL
           RLA

CYTRUE:    JR NC,SETFALSE

; --- SETTRUE / SETFALSE: overwrite the value at (HL) with 1 or 0 ---

SETTRUE:   LD C,1
           DB SKIP1CP

SETFALSE:  LD C,&00
           LD D,H
           LD E,L

; --- STACKC: write the small integer in C at (DE) ---

STACKC:    XOR A
           LD (DE),A                    ; Exponent zero: an integer
           INC DE
           LD (DE),A                    ; Positive
           INC DE
           LD A,C
           LD (DE),A                    ; Low byte
           XOR A
           INC DE
           LD (DE),A                    ; High byte zero
           INC DE
           INC DE
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPAND / FPOR / FPSAND -- logical operators
;
; Each is binary, so the second operand has already been dropped by the time the result is decided.
; ---------------------------------------------------------------------------------------------------------------------

FPAND:     CALL TSTZERO
           JR Z,SETFALSE                ; n2 was zero, so the result is zero

           RET                          ; Otherwise the result is n1

FPOR:      CALL TSTZERO
           JR NZ,SETTRUE                ; n2 was non-zero, so the result is 1

           RET

FPSAND:    CALL TSTZERO
           RET NZ                       ; n2 was non-zero, so return the string unchanged

           DEC DE                       ; Otherwise make it the empty string
           LD (DE),A
           DEC DE
           LD (DE),A
           INC DE
           INC DE
           RET


; =====================================================================================================================
; String comparisons
; =====================================================================================================================
;
; Note the convention: S1 < S2 is true when S1 would come first alphabetically.
;
; STRCOMP returns with HL pointing at S1, which SETTRUE and SETFALSE overwrite with the result.
; ---------------------------------------------------------------------------------------------------------------------

FPSEQUAL:  CALL STRCOMP
           JR ZTRUE

FPSLESS:   CALL STRCOMP
           JR CYTRUE

FPSGRTR:   CALL STRCOMP
           JR Z,SETFALSE

           JR NCTRUE

FPSLESE:   CALL STRCOMP
           JR Z,SETTRUE

           JR CYTRUE

FPSGRTE:   CALL STRCOMP

NCTRUE:    CCF
           JR CYTRUE

FPSNOTE:   CALL STRCOMP

NZTRUE:    JR Z,SETFALSE

           JR SETTRUE


; =====================================================================================================================
; Numeric comparisons
; =====================================================================================================================
;
; Each is a three-byte calculator program: subtract, then test the sign of the difference.
; ---------------------------------------------------------------------------------------------------------------------

FPNEQUAL:  DB CALC
           DB SUBN
           DB NOT                       ; True when the difference is zero
           DB EXIT2

FPNLESS:   DB CALC
           DB SUBN
           DB LESS0
           DB EXIT2

FPNGRTR:   DB CALC
           DB SUBN
           DB GRTR0
           DB EXIT2

FPNLESE:   DB CALC
           DB SUBN
           DB LESE0
           DB EXIT2


FPNGRTE:   DB CALC
           DB SUBN
           DB GRTE0
           DB EXIT2

FPNNOTE:   DB CALC
           DB SUBN
           DB NOT                       ; True if equal ...
           DB NOT                       ; ... inverted, so true if unequal
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; TSTZERO / TSTZERO2 -- Z if the five-byte value is zero
;
; Entry:  TSTZERO tests (DE), TSTZERO2 tests (HL). Neither pointer is altered.
; ---------------------------------------------------------------------------------------------------------------------

TSTZERO:   EX DE,HL

TSTZERO2:  LD A,(HL)                    ; Exponent
           INC HL
           INC HL
           OR (HL)                      ; Low byte
           INC HL
           OR (HL)                      ; High byte
           DEC HL
           DEC HL
           DEC HL
           EX DE,HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPMOD / FPIDIV -- MOD and DIV, written as calculator programs
;
; MOD leaves INT(n1/n2) in memory 3 as a side effect, which UNSTLEN relies on to split a value into a page and an
; offset in one operation.
; ---------------------------------------------------------------------------------------------------------------------

FPMOD:     DB CALC                      ; n1, n2
           DB DUP                       ; n1, n2, n2
           DB SWOP13                    ; n2, n2, n1
           DB DUP                       ; n2, n2, n1, n1
           DB SWOP13                    ; n2, n1, n1, n2
           DB DIVN
           DB INT                       ; n2, n1, INT(n1/n2)
           DB STO3                      ; ... which UNSTLEN wants
           DB SWOP23                    ; n1, n2, INT(n1/n2)
           DB MULT                      ; n1, n2*INT(n1/n2)
           DB SUBN                      ; n1 - n2*INT(n1/n2)
           DB EXIT2

FPIDIV:    DB CALC                      ; n1, n2
           DB DIVN
           DB INT
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPBOR / FPBAND -- bitwise operations on 16-bit integers
; ---------------------------------------------------------------------------------------------------------------------

FPBOR:     CALL GETHLBC
           OR L
           LD C,A
           LD A,B
           OR H
           JR BSTKBCH

FPBAND:    CALL GETHLBC
           AND L
           LD C,A
           LD A,B
           AND H

BSTKBCH:   LD B,A
           JP STACKBC


; ---------------------------------------------------------------------------------------------------------------------
; GETHLBC -- pop two values as integers: n1 into BC, n2 into HL
; ---------------------------------------------------------------------------------------------------------------------

GETHLBC:   CALL GETINT
           PUSH BC
           CALL GETINT
           POP HL
           RET
