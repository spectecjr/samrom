; =====================================================================================================================
; USING.ASM -- pointer adjustment, printer output, the heap, INSTR, LENGTH, STRING$, and curved DRAW
; =====================================================================================================================
;
; Despite its name this file has nothing to do with PRINT USING. It is a collection of unrelated routines that
; happened to be assembled together.
;
; XOINTERS
; --------
; Whenever MAKEROOM or RECLAIM shifts memory, every pointer that referred to something above the change has to move
; with it. XOINTERS walks the fourteen system variables that hold such pointers and adjusts each one, and then --
; if the variables area itself moved, meaning the program was edited -- walks the BASIC stack adjusting the return
; addresses stored in its DO, GOSUB and PROC frames as well.
;
; The one rule worth remembering: pointers at or below the change location are *not* adjusted. See
; docs/memory-map.md.
;
; A subtlety handled by SMBW/SMBS: an address in section D of one page and the same address in section C of the next
; page are the same physical byte, written two different ways. Several pointers must share a base page with ELINE
; for later arithmetic to work, so they are normalised into whichever form ELINE uses.
;
; SELF-MODIFYING BLOCK OPERATIONS
; -------------------------------
; CRBBFN and CRTBF build unrolled instruction sequences in CDBUFF and then call them. Scrolling a screen line by one
; pixel means an RLD or RRD on every byte of the line; writing that as a loop would cost more in loop overhead than
; in useful work, so the routine writes out one RLD and one pointer increment per byte, terminated by a RET.
; CRTBF does the same for LDI and LDD.
;
; CURVED DRAW
; -----------
; DRCURVE draws DRAW x,y,angle as a sequence of short straight chords. The number of chords is derived from the
; chord length and the angle, capped at four; each chord's endpoint is found by rotating the previous displacement
; through a fixed angle, which is the pair of multiply-and-add steps at CURVLP. The rotation constants are computed
; once, into calculator memories 3 and 4, so the loop itself needs no trigonometry.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; XOINTERS -- adjust all the pointers that follow a memory move
;
; Entry:  HL = the location of the change, already paged in; CDE = the amount; CY to subtract.
; Exit:   PAGCOUNT and MODCOUNT hold the size of the block that has to move; AHL = the old WKEND.
; ---------------------------------------------------------------------------------------------------------------------

; XOI3:      LD B,3
;         LD IY,NUMENDP
;        JR X31

XOINTERS:  LD B,14                          ; Fourteen system variables hold adjustable pointers
           LD IY,SAVARSP                    ; The first of them

X31:       EX AF,AF'                        ; CY' remembers whether this is an addition or a subtraction
           LD (TEMPW4),BC
           LD (TEMPW5),DE
           EX DE,HL
           IN A,(URPORT)
           AND &1F
           LD C,A
           BIT 6,D
           JR Z,PNT1

           INC C                            ; Normalise the location into section C of the next page
           RES 6,D

PNT1:    ;  PUSH BC
;           PUSH DE           ;ADJUSTED LOCN
           LD A,(WKENDP)
           LD HL,(WKEND)
           BIT 6,H
           JR Z,PNT15

           INC A                            ; Same normalisation for WKEND
           RES 6,H

PNT15:     PUSH AF                          ; The old WKEND, which is the end of the block that must move
           PUSH HL
           IN A,(URPORT)
           PUSH AF
           CALL ADDRNV
           PUSH HL
           CALL PNLP                        ; Adjust the B system variables
           LD A,C
           POP BC
           LD HL,(NVARS)
           AND A
           SBC HL,BC
           CALL NZ,SADJ                     ; NVARS moved, so the program itself changed and the BASIC stack's
                                            ; stored addresses need adjusting too.
                                            ; Note: a deletion of exactly 16K leaves NVARS apparently unchanged and
                                            ; is therefore missed.
           LD C,A
           POP AF
           OUT (URPORT),A
           LD A,(ELINEP)
           CALL SMBW                        ; Put WORKSP and WKEND on the same base page as ELINE
           LD L,A
           LD A,(CLA+1)
           AND A
           LD A,L
           LD L,CHADP\256
           CALL Z,SMBS                      ; And CHAD too, if the edit line is what is running

           POP HL
           POP AF                           ; AHL = the old WKEND
;           POP DE
;          POP BC            ;CDE=ORIG LOCN
           PUSH AF
           PUSH HL
           CALL SUBAHLCDE                   ; AHL = the block size to move, for MAKEROOM
           EX AF,AF'
           JR NC,PNBS                       ; This is a MAKEROOM

           EX AF,AF'
           LD BC,(TEMPW4)
           LD DE,(TEMPW5)
           CALL SUBAHLCDE                   ; A RECLAIM moves less, by the amount reclaimed
           EX AF,AF'

PNBS:      EX AF,AF'
           RES 7,H
           LD (PAGCOUNT),A
           INC HL                           ; One extra, since MODCOUNT may now be a full &4000
           LD (MODCOUNT),HL
           POP HL
           POP AF                           ; AHL = the old WKEND
           RET


; ---------------------------------------------------------------------------------------------------------------------
; SMBW / SMBS -- put a pointer on the same base page as ELINE
;
; SMBW does WORKSP, WKEND and KCUR; SMBS does the single pointer at (HL).
;
; Entry:  A = ELINE's page, HL -> the page byte of the pointer.
;
; If the pointer is one page higher, it is rewritten as the equivalent section D address in the lower page: the page
; byte is decremented and bit 6 of the address's high byte is set.
; ---------------------------------------------------------------------------------------------------------------------

SMBW:      LD HL,WORKSPP
           CALL SMBS
           LD L,WKENDP\256
           CALL SMBS
           LD L,KCURP\256

SMBS:      PUSH AF
           XOR (HL)
           AND &1F
           JR Z,SMBS2                       ; Already the same page

           DEC (HL)
           INC HL
           INC HL
           SET 6,(HL)                       ; The address moves from section C to section D

SMBS2:     POP AF
           RET


; ---------------------------------------------------------------------------------------------------------------------
; SADJ -- adjust the addresses held in BASIC stack frames
;
; Each frame's first byte holds the page in its low five bits and the frame type in its top three: BSTKDO (&80),
; BSTKPROC (&40) or BSTKGOSUB (&00). The type bits have to be preserved across the adjustment, which is why the byte
; is saved and merged back rather than simply rewritten.
;
; A PROC frame is followed by a variable-length list terminated by two zero bytes, which FPTLP skips.
;
; Once the whole stack has been walked, AFLPS in ROM0 adjusts the FOR/NEXT loop records as well.
; ---------------------------------------------------------------------------------------------------------------------

SADJ:      PUSH BC                          ; The old NVARS, still correct at this point
           LD C,A                           ; CDE = the change location
           LD HL,(BSTKEND)

SADJL:     LD A,(HL)
           CP &FF
           JR NZ,SADJ2                      ; Not the stack terminator

           POP HL                           ; NVARS
           PUSH DE
           LD (TEMPW3),DE
           LD D,C
           EX AF,AF'
           CALL R1OFFCL
           DW AFLPS                         ; Adjust the FOR/NEXT records, in ROM0
           EX AF,AF'
           POP DE
           LD A,C
           RET

SADJ2:     PUSH AF                          ; Keep the frame type bits
           PUSH HL
           CALL ASSV                        ; Adjust this frame's address as if it were a system variable
           POP HL
           POP AF
           AND &E0
           OR (HL)
           LD (HL),A                        ; Restore the type bits over the adjusted page
           INC HL
           INC HL
           INC HL                           ; Past the page, the address and the offset
           INC HL                           ; And the statement number
           AND &E0
           CP BSTKPROC
           JR NZ,SADJL

FPTLP:     LD A,(HL)                        ; A PROC frame carries a list terminated by two zero bytes
           INC HL
           OR (HL)
           JR NZ,FPTLP

           INC HL
           JR SADJL


; ---------------------------------------------------------------------------------------------------------------------
; SNDA2 -- send one byte to the parallel printer
;
; Waits for the busy line to clear, writes the data, and pulses the strobe. The strobe pulse is about 2.6
; microseconds, which is the time the two OUT instructions take.
; ---------------------------------------------------------------------------------------------------------------------

SNDA2:     PUSH BC
           PUSH AF
           LD BC,(LPTPRT1)                  ; C = the control port, B = 1, the strobe bit

SENDLP:    CALL BRKCR                       ; BREAK escapes a printer that never becomes ready
           IN A,(C)
           RRCA
           JR C,SENDLP                      ; Still busy

           DEC C
           POP AF
           OUT (C),A                        ; Data to the data port
           INC C
           OUT (C),B                        ; Raise the strobe
           DEC B
           OUT (C),B                        ; And lower it again
           POP BC
           RET


; ---------------------------------------------------------------------------------------------------------------------
; HEAPROOM -- reserve or release space on the heap
;
; Entry:  BC = the bytes to reserve, or the negative of the bytes to release.
; Exit:   DE = the old heap end, which is the start of any newly reserved room; HL = the new heap end.
;         NC if there was not enough room, in which case HL is the shortfall.
; Notes:  BC is preserved. BC = 0 is allowed. Releasing more than the heap contains simply empties it, so
;         LD BC,&C000 : CALL HEAPRM is the idiom for clearing the heap.
; ---------------------------------------------------------------------------------------------------------------------

HEAPROOM:  LD HL,(HEAPEND)                  ; Normally somewhere between &4200 and &4A00
           ADD HL,BC
           LD A,H
           CP &40
           JR NC,HEAPR2

           LD HL,(HPST)                     ; The adjustment took it below the start, so empty it
           JR HEAPR3

HEAPR2:    LD DE,(BSTKEND)
           SBC HL,DE
           RET NC                           ; It would collide with the BASIC stack

           ADD HL,DE

HEAPR3:    LD DE,(HEAPEND)
           LD (HEAPEND),HL
           RET


; =====================================================================================================================
; IMINSTR -- the INSTR function
; =====================================================================================================================
;
; INSTR(search$, target$) or INSTR(start, search$, target$). Returns the position of the first occurrence, counting
; from 1, or 0 if it is not found.
;
; The target string is copied to a fixed buffer in page 0, so the actual search can run with the search string's
; page paged in. INSTHASH holds a hash byte precomputed from the target, which the ROM0 inner loop uses to reject
; most positions with a single compare.
;
; A search longer than &3F00 bytes cannot be done in one call, because the search string would cross a page
; boundary partway through; INSTBKLP therefore breaks it into &3EFF-byte pieces and adjusts the start position for
; each.
; ---------------------------------------------------------------------------------------------------------------------

IMINSTR:      CALL SINSISOBRK               ; The opening bracket
              CALL EXPTEXPR                 ; Z for a string, NZ for a number; CY if running
              JR NZ,INSTR2                  ; A start position was given

              JR NC,INSTR3                  ; Syntax checking, so nothing needs stacking

              DB CALC                       ; search$
              DB STKONE                     ; search$, 1
              DB SWOP                       ; 1, search$
              DB EXIT

              JR INSTR3

INSTR2:       CALL EXPTCSTR                 ; A comma and the search string

INSTR3:       CALL EXPTCSTRB                ; A comma, the target string, and the closing bracket
              RET NC

              IN A,(URPORT)
              PUSH AF

              CALL SBFSR                    ; Copy the target to INSTBUF; "invalid argument" if it exceeds 255
              PUSH AF                       ; Its length
              CALL GETSTRING                ; DE = the search string, BC = its length, its page now in
              PUSH DE
              PUSH BC
              CALL GETINT                   ; The start position
              OR B
              JP Z,SWER2                    ; Position 0 does not exist

              LD A,(INSTHASH)

              EXX
              LD C,A                        ; C' = the target's hash byte
              EXX

              DEC  BC                       ; Positions count from 1, offsets from 0
              POP HL                        ; The search string's length
              POP DE                        ; Its start
              POP AF                        ; The target's length
              CALL INARRAYEN
              POP AF
              JP OSBC                       ; OUT (URPORT),A then JP STACKBC
            ;  OUT (URPORT),A
             ; JP STACKBC


; ---------------------------------------------------------------------------------------------------------------------
; INARRAYEN -- the search proper
;
; Entry:  A = the target length, DE = the search string, HL = its length, the start offset on the stack.
; Exit:   BC = the position found, or 0.
; ---------------------------------------------------------------------------------------------------------------------

INARRAYEN:    PUSH BC                       ; The start offset
              LD C,A
              LD B,0                        ; BC = the target length
              AND A
              JP Z,NOTFND2                  ; An empty target is never found

              SBC HL,BC
              POP BC
              JR C,NOTFND3H                 ; The target is longer than the search string

              INC HL
              SBC HL,BC                     ; Take off the start offset

NOTFND3H:     JP C,NOTFND3                  ; The start is past the last possible match

              EX DE,HL
              INC DE                        ; DE = the number of positions to try
              EX AF,AF'
              ADD HL,BC                     ; Advance to the start position
              CALL C,PGOVERF                ; Bring HL back into &8000-&BFFF if it overflowed

INSTBKLP:     CALL CHKHL                    ; And again, if it has since drifted out
              LD A,D
              CP &3F
              JR C,MINSR                    ; Short enough to search in one go

              PUSH DE
              LD DE,&3EFF
              CALL MINSR                    ; Search the first &3EFF bytes
              JR NC,JUNKS                   ; Found; BC holds the position

;              POP DE              ;JUNK PREVIOUS LEN
;             RET                 ;FOUND - BC=POSN FOUND, NC

              EX DE,HL                      ; A' = the target length, DE = the string, HL = the start position
              LD BC,&3EFF
              ADD HL,BC                     ; Advance the start position
              EX (SP),HL
              SBC HL,BC
              EX DE,HL                      ; DE = the remaining length, HL = the string pointer
              POP BC
              JR INSTBKLP


; ---------------------------------------------------------------------------------------------------------------------
; MINSR -- one bounded search, performed in ROM0
;
; Entry:  A' = the target length, HL = the search pointer, DE = the bytes to search, BC = the start position.
; ---------------------------------------------------------------------------------------------------------------------

MINSR:        EX AF,AF'
              PUSH AF
              LD (BCSTORE),BC
              CALL R1OFFCL
              DW R0INST

JUNKS:        EX AF,AF'
              POP AF
              EX AF,AF'
              RET


; =====================================================================================================================
; IMLENGTH -- the LENGTH function
; =====================================================================================================================
;
; LENGTH(n, variable) reports one of three things about a variable, chosen by n:
;
;     0    the address of the variable's data
;     1    the number of elements
;     2    the element length
;
; For a simple string the element length is 1 and the element count is the string length. For a one-dimensional
; array the element count is the dimension and the length is 1; for a two-dimensional array the second dimension
; becomes the element length, which is how a string array's fixed-width slots are described.
; ---------------------------------------------------------------------------------------------------------------------

IMLENGTH:  CALL SINSISOBRK
           CALL EXPT1NUM                    ; n
           CALL INSISCOMA
           CALL R1OFFCL
           DW LENGSR                        ; Locate the variable; sets bit 6 of FLAGS for numeric or string
           JP Z,VNFERR                      ; Not found at run time

           RST &18
           CALL EXCBRF                      ; A following "()" means an array
           EX AF,AF'
           BIT 5,C
           JR Z,IMLEN2                      ; Not a numeric array

           RST &18
           CALL EXCBRF                      ; A numeric array needs the second bracket pair, as in LENGTH(1,a())
           RET NC

           JR IMLEN3

; --- A simple variable ---

IMLEN2:    EX AF,AF'
           RET NC                           ; Syntax time

           JP P,IMLEN3                      ; A string variable

           CALL GETBYTE                     ; A simple numeric variable only has an address
           AND A
           JR NZ,IMLERR

           LD HL,(MEMVAL)

IMLENC:    LD  A,(MEMVAL+2)
           LD B,A
           JP ASBHL                         ; Normalise BHL to a page-relative address and stack it

IMLEN3:    PUSH BC                          ; C = the type byte
           CALL GETBYTE                     ; n
           POP BC
           LD HL,MEMVAL+3                   ; The header data LENGSR left behind
           PUSH AF

; --- Decode the header. Exit: HL -> the text, DE = the element length, BC = the element count ---

           LD A,C
           AND &60
           LD A,(HL)
           INC HL
           LD C,(HL)
           INC HL
           JR NZ,ASSAR4                     ; An array

           RRCA                             ; A simple string: the length's high bits are packed into the type byte
           RRCA
           OR (HL)
           LD B,A

ASSAR3:    LD DE,1                          ; One byte per element
           JR ASSAR5

ASSAR4:    INC HL
           LD A,(HL)                        ; The number of dimensions
           INC HL
           LD C,(HL)
           INC HL
           LD B,(HL)
           DEC A
           JR Z,ASSAR3                      ; One dimension: BC is the count, the element length is 1

           INC HL                           ; Two dimensions: the second becomes the element length
           LD E,(HL)
           INC HL
           LD D,(HL)

ASSAR5:    LD A,L
           SUB (MEMVAL+2)\256               ; How far the dimensions ran, and so where the text starts
           LD HL,(MEMVAL)
           ADD A,L
           LD L,A
           JR NC,ASSAR6

           INC H

; --- HL = the data start, DE = the element length, BC = the element count. Return whichever was asked for ---

ASSAR6:    POP AF
           AND A
           JR Z,IMLENC                      ; n = 0: the address

           DEC A
           JP Z,STACKBC                     ; n = 1: the element count

           EX DE,HL
           DEC A
           JP Z,STACKHL                     ; n = 2: the element length

IMLERR:    RST &08
           DB ERR_IOOR


; ---------------------------------------------------------------------------------------------------------------------
; IMSTRINGS -- the STRING$(n, s$) function
;
; Builds the result by copying the source into a buffer and then LDIRing repeatedly with the destination one copy
; ahead of the source -- so the first LDIR copies the string onto itself and each subsequent one appends another
; copy. The result is limited to 511 characters, which is the buffer size.
; ---------------------------------------------------------------------------------------------------------------------

IMSTRINGS: CALL EXBNCSB                     ; (n, s$)
           RET NC

           DB CALC                          ; n, s$
           DB STOD0                         ; n
           DB DUP                           ; n, n
           DB RCL0                          ; n, n, s$
           DB DUP                           ; n, n, s$, s$
           DB LEN                           ; n, n, s$, LEN s$
           DB SWOP23                        ; n, s$, n, LEN s$
           DB MULT                          ; n, s$, the result length
           DB EXIT

           CALL GETINT
           OR B
           JR Z,STRINGSN                    ; A zero-length result

           LD A,B
           CP 2
           JP NC,STLERR                     ; Longer than 511, which will not fit the buffer

           PUSH BC                          ; The result length
           CALL SBUFFET                     ; Copy the source to the buffer; it must be 255 or shorter
           PUSH BC                          ; Its length
           PUSH DE                          ; The buffer start
           CALL GETBYTE                     ; n
           POP HL
           LD D,H
           LD E,L                           ; Source and destination both start at the buffer
           POP BC

STRSL:     PUSH BC
           PUSH HL
           LDIR                             ; The first pass copies the string onto itself
           POP HL
           POP BC
           DEC A
           JR NZ,STRSL

           POP BC
           JP CWKSTK                        ; Copy the result to the workspace and stack it

; --- STRING$(0,"aa") or STRING$(10,"") both give the empty string ---

STRINGSN:  DB CALC
           DB DROP
           DB DROP
           DB EXIT

           JP STACKBC


; ---------------------------------------------------------------------------------------------------------------------
; CIFILSR -- unstack the coordinates for CIRCLE and FILL
;
; Exit:   NC with Y in B and X in C for fat pixels; CY with the adjusted coordinates in BC and TEMPW1 holding the
;         offset that maps the eight-bit X back onto the 512-pixel screen.
;
; FILL always works in the thin-pixel coordinate system, so in mode 2 with fat pixels selected the X coordinate is
; doubled here. The CURCMD/MODE arithmetic is a compact way of testing all three conditions at once: it only comes
; out zero for mode 2, fat pixels, and the FILL token.
;
; The offset itself has three cases. A centre in the left half of the screen needs no offset; one in the right half
; needs &0100; anything in between is expressed as a displacement from a pretended centre of 128, so that the
; circle loop's eight-bit arithmetic can never leave the screen.
; ---------------------------------------------------------------------------------------------------------------------

CIFILSR:   CALL R1OFFCL                     ; v2.6
           DW  GTFCOORDS                    ; Y in B and X in C, or X in HL with CY for thin pixels
           JR C,CIFISR2

           LD A,(CURCMD)
           LD HL,MODE
           ADD A,(HL)
           SUB &EB+2                        ; FILLTOK plus 2
           SCF
           CCF                              ; NC
           RET NZ                           ; Only mode 2, fat pixels and FILL reach the next instruction

           LD L,C
           LD H,A
           ADD HL,HL                        ; X doubled

CIFISR2:   LD A,H
           AND A
           LD A,L
           JR NZ,THINC2

; --- X is &00FF or less ---

           CP &80
           JR C,THINC3                      ; Below &80: use L as X with an offset of 0

           JR THINC4

; --- X is &0100 or more ---

THINC2:    CP &80
           JR C,THINC4                      ; Above &017F: use L as X with an offset of &0100

; --- X is at or above &0180, or below &0080 ---

THINC3:    LD C,L
           LD L,0
           JR THINC5

; --- X is between &0080 and &017F ---

THINC4:    LD DE,&80
           LD C,E                           ; Pretend the centre is at 128
           AND A
           SBC HL,DE                        ; The offset that recovers the real coordinate

THINC5:    LD (TEMPW1),HL
           SCF                              ; Thin pixels
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CRBBFN -- build an unrolled nibble-rotate routine in CDBUFF
;
; Entry:  A = the number of bytes, C = 1 to move right, anything else to move left.
;
; Emits A copies of "RRD : INC L" (moving right) or "RLD : DEC L" (moving left), followed by a RET. RLD and RRD are
; two-byte ED-prefixed opcodes, so each copy is three bytes: the ED, the second opcode byte, and the pointer step.
; ---------------------------------------------------------------------------------------------------------------------

CRBBFN:    PUSH DE
           PUSH HL
           LD B,A
           LD DE,&672C                      ; The second byte of RRD, then INC L
           DEC C
           JR NZ,CRBB2

           LD DE,&6F2D                      ; The second byte of RLD, then DEC L

CRBB2:     LD A,&ED                         ; The prefix both share
           LD HL,CDBUFF

CRBBL:     LD (HL),A
           INC HL
           LD (HL),D
           INC HL
           LD (HL),E
           INC HL
           DJNZ CRBBL

           LD (HL),&C9                      ; RET
           POP HL
           POP DE
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CRTBF / CRTBFI -- build an unrolled block-copy routine in CDBUFF
;
; Entry:  A = the number of bytes; at CRTBF, C = 1 for LDI or anything else for LDD. CRTBFI always builds LDI.
; ---------------------------------------------------------------------------------------------------------------------

CRTBF:     PUSH BC
           DEC C
           LD C,&A8                         ; The second byte of LDD
           JR NZ,CRTB2

           DB SKIP1LDC                      ; LD C,n swallows the LD C,&A0 below

CRTBFI:    PUSH BC

CRTB1:     LD C,&A0                         ; The second byte of LDI

CRTB2:     PUSH HL
           LD B,A
           LD A,&ED
           LD HL,CDBUFF

CRTBL:     LD (HL),A
           INC HL
           LD (HL),C
           INC HL
           DJNZ CRTBL

           LD (HL),&C9                      ; RET
           POP HL
           POP BC
           RET


; =====================================================================================================================
; DRCURVE -- curved DRAW
; =====================================================================================================================
;
; DRAW x,y,angle draws an arc from the current position to a point x,y away, bulging by the given angle in radians.
; The arc is approximated by up to four straight chords.
;
; The geometry: with the chord length L and the total angle Z, each of n sub-chords subtends Z/n, and the ratio
; between the full chord and a sub-chord is sin(Z/2)/sin(Z/2n). Multiplying the original displacement by that ratio
; gives the first sub-chord's displacement, and each subsequent one is that vector rotated by Z/n -- which is the
; standard two-multiply rotation held in memories 3 and 4 as cos and sin of the step angle.
;
; Very small angles, and arcs whose computed chord is under one pixel, fall through to LINEDRAW and are drawn as a
; single straight line.
; ---------------------------------------------------------------------------------------------------------------------

; --- DRTCRV: the DRAW TO form, entered with the displacements already in registers. Put them back on the
;     calculator stack and recover the curvature from memory 0. ---

DRTCRV:    LD A,(THFATT)
           AND A                            ; Z for thin pixels
           LD A,E                           ; The X direction sign
           NEG
           LD E,B
           PUSH DE                          ; The Y sign and distance
           EX DE,HL
           JR Z,DRT2                        ; Thin pixels: DE already holds the X distance

           LD D,0
           LD E,C

DRT2:      LD HL,(STKEND)
           CALL STORADE                     ; Store DE as a signed integer on the calculator stack
           INC HL
           INC HL
           POP DE                           ; The Y sign and distance
           LD A,D
           LD D,0
           CALL STORADE
           INC HL
           INC HL
           LD (STKEND),HL

           DB CALC
           DB RCL0                          ; Recover the curvature
           DB EXIT


DRCURVE:   DB CALC                          ; X, Y, -Z
           DB NEGATE                        ; The angle is reversed so the curve bulges the way the user expects
           DB STO5                          ; Memory 5 = Z
           DB STKHALF
           DB MULT                          ; Z/2
           DB SIN
           DB DUP
           DB NOT                           ; True if sin(Z/2) is zero
           DB JPTRUE                        ; Effectively a straight line
DRHLB:     DB DROPEX-DRHLB

           DB STOD0                         ; Memory 0 = sin(Z/2)
           DB NEGATE                        ; Y is negated because the screen's Y axis is inverted
           DB SWOP                          ; Y, X
           DB DUP
           DB ABS
           DB SWOP                          ; Y, |X|, X
           DB SWOP13                        ; X, |X|, Y
           DB DUP
           DB ABS
           DB SWOP23                        ; X, Y, |X|, |Y|
           DB ADDN                          ; X, Y, |X|+|Y| -- a cheap approximation to the chord length
           DB RCL0
           DB DIVN                          ; Divided by sin(Z/2): call the result FF
           DB ABS
           DB RCL0
           DB SWOP                          ; X, Y, sin(Z/2), FF
           DB DUP
           DB STKFONE
           DB SUBN
           DB GRTE0                         ; True if FF is at least 1
           DB JPTRUE                        ; A genuine curve
           DB &07

           DB DROP                          ; Too small to curve

DROPEX:    DB DROP                          ; X, Y
           DB EXIT

           JP LINEDRAW

; --- Work out how many chords to use: |Z| * sqrt(FF) / 2, rounded down to a multiple of four and capped at four ---

DRCURV3:   DB DUP
           DB SQR
           DB ONELIT
           DB &02
           DB SWOP
           DB DIVN                          ; 2/sqrt(FF)
           DB RCL5
           DB SWOP
           DB DIVN                          ; Z*sqrt(FF)/2
           DB ABS
           DB EXIT

           CALL FPTOA
           LD B,&FC
           JR C,DRCURV4                     ; Too big for a byte, so use the maximum

           AND B
           ADD A,4
           JR Z,DRCURV4                     ; Overflowed to zero, so also the maximum

           LD B,A

DRCURV4:   PUSH BC                          ; B = the number of arcs

; --- Precompute the per-chord constants ---

           DB CALC                          ; FF
           DB RCL5                          ; FF, Z
           DB STKBREG                       ; FF, Z, arcs
           DB DIVN                          ; FF, Z/arcs
           DB DUP
           DB SIN
           DB STOD4                         ; Memory 4 = sin(Z/arcs), the rotation's sine
           DB DUP
           DB STKHALF
           DB MULT                          ; Z/(2*arcs)
           DB SIN
           DB STO1                          ; sin(Z/(2*arcs))
           DB SWOP
           DB STOD0                         ; Memory 0 = Z/arcs
           DB DUP
           DB MULT
           DB STKHALF
           DB DIVN                          ; 2*sin^2(Z/(2*arcs))
           DB STKFONE
           DB SWOP
           DB SUBN                          ; 1 - 2*sin^2 = cos(Z/arcs)
           DB STOD3                         ; Memory 3 = the rotation's cosine

           DB DROP                          ; X, Y, sin(Z/2)
           DB RCL1
           DB SWOP
           DB DIVN                          ; V = sin(Z/2)/sin(Z/(2*arcs)), the chord scaling ratio
           DB STOD1                         ; Memory 1 = V
           DB SWOP                          ; Y, X
           DB DUP
           DB RCL1
           DB MULT
           DB STOD2                         ; Memory 2 = X*V
           DB SWOP                          ; X, Y
           DB DUP
           DB RCL1
           DB MULT
           DB STOD1                         ; Memory 1 = Y*V
           DB RCL5
           DB RCL0
           DB SUBN                          ; Z - Z/arcs
           DB STKHALF
           DB MULT                          ; T = (Z - Z/arcs)/2, the half-angle the first chord is rotated by
           DB DUP
           DB SIN
           DB STO5                          ; Memory 5 = sin T
           DB SWOP
           DB COS
           DB STOD0                         ; Memory 0 = cos T
           DB RCL1
           DB MULT
           DB RCL0
           DB RCL2
           DB MULT
           DB ADDN                          ; P = sin(T)*Y*V + cos(T)*X*V, the first chord's X displacement
           DB RCL1
           DB SWOP
           DB STOD1                         ; Memory 1 = P
           DB RCL0
           DB MULT
           DB RCL5
           DB RCL2
           DB MULT
           DB SUBN                          ; J = cos(T)*Y*V - sin(T)*X*V, the first chord's Y displacement
           DB STO2                          ; Memory 2 = J
           DB ABS
           DB RCL1
           DB ABS
           DB ADDN                          ; |J| + |P|
           DB DROP
           DB EXIT                          ; (DE) = the exponent of |J| + |P|

           POP BC
           LD A,(DE)
           CP &81
           JP C,LINEDRAW                    ; The first chord is under one pixel, so draw it straight

; --- Convert the displacements to absolute endpoints and enter the loop ---

           DB CALC
           DB SWOP                          ; Y, X
           DB LKADDRW
           DW XCOORD
           DB STO0
           DB ADDN                          ; Y, X + XCOORD
           DB SWOP
           DB LKADDRB
           DW YCOORD
           DB STO5
           DB ADDN                          ; The endpoint
           DB RCL0
           DB RCL5                          ; And the start point
           DB EXIT

           DJNZ CUENTRY

           JR CURVEND


; --- CURVLP: rotate the displacement vector by one step angle ---

CURVLP:    DB CALC
           DB RCL1                          ; The previous X increment
           DB DUP
           DB RCL3
           DB MULT                          ; x*cos
           DB RCL4
           DB RCL2
           DB MULT                          ; y*sin
           DB SUBN
           DB STOD1                         ; The new X increment
           DB RCL4
           DB MULT                          ; x*sin
           DB RCL3
           DB RCL2
           DB MULT                          ; y*cos
           DB ADDN
           DB STOD2                         ; The new Y increment
           DB EXIT

; --- CUENTRY: turn the increments into a displacement from the current pen position and draw one chord ---

CUENTRY:   DB CALC
           DB STOD0
           DB RCL1                          ; The X increment
           DB ADDN
           DB DUP
           DB LKADDRW
           DW XCOORD
           DB SUBN                          ; Relative to where the pen is now
           DB RCL2                          ; The Y increment
           DB RCL0
           DB ADDN
           DB STO0
           DB SWOP
           DB LKADDRB
           DW YCOORD
           DB RCL0
           DB SUBN
           DB EXIT

           PUSH BC
           CALL R1OFFCL
           DW DRAWFD                        ; Draw the chord, with the range adjustments applied
           POP BC
           DJNZ CURVLP

CURVEND:   DB CALC                          ; Draw the final chord, straight to the recorded endpoint
           DB DROP
           DB DROP
           DB SWOP
           DB LKADDRW
           DW XCOORD
           DB SUBN
           DB SWOP
           DB LKADDRB
           DW YCOORD
           DB SWOP
           DB SUBN
           DB EXIT

LINEDRAW:  CALL R1OFFCL
           DW DRAWFD
           JP TRCURP
