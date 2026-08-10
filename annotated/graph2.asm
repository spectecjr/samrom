; =====================================================================================================================
; GRAPH2.ASM -- BLITZ, FILL, the screen-to-check-screen converter, and coordinate handling
; =====================================================================================================================
;
; Four related pieces of the graphics system:
;
;   BLITZ a$          execute a string of compact graphics commands -- a miniature display list, far faster than
;                     the equivalent BASIC because nothing is parsed or evaluated at run time
;   FILL x,y          flood fill, optionally textured from a 128-byte pattern
;   TRANSCR/CHARCOMP  reduce a mode 2 or 3 area to one bit per pixel, used both to prepare the fill check screen
;                     and (as CHARCOMP) by SCREEN$ and by graphics COPY
;   GTFCOORDS etc.    unstack, range-check and transform coordinates for every graphics command, applying the
;                     XOS/YOS/XRG/YRG pseudo-variables
;
; GRAREC, at the end of the file, is the other half of BLITZ: with RECORD on, every graphics command appends its
; compact form to a string, so a sequence of PLOTs and DRAWs can be captured and replayed with BLITZ.
;
; ---------------------------------------------------------------------------------------------------------------------
; The BLITZ string format
; ---------------------------------------------------------------------------------------------------------------------
;
;     SGN X (00/FF), X, SGN Y (00/FF), Y     relative DRAW, 4 bytes
;     01, X, Y                               PLOT
;     02, X, Y                               DRAW TO
;     03, X, Y, R                            CIRCLE
;     04, O                                  OVER O
;     05, I                                  INK I
;     06, C                                  CLS C (0 = whole screen, 1 = window)
;     07, N                                  PAUSE N
;
; The first byte is both a command code and, for a relative draw, the sign of the X displacement; codes 0 and 1 are
; ambiguous with signs 00 and FF, which is resolved by the fact that a sign byte is only ever 00 or FF while a
; command code is 1 to 7. The decoder below untangles this with a single INC A and two comparisons.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; FDMAINLP -- the BLITZ interpreter loop
;
; One iteration decodes one command. The length remaining and the current position are kept on the machine stack
; across the command, and C holds the number of bytes the command occupied so that both can be advanced at
; MAINLPH.
;
; Entry:  DE = length remaining, HL = position in the string
; ---------------------------------------------------------------------------------------------------------------------

FDMAINLP:  EX DE,HL
           PUSH DE           ;LENGTH
           PUSH HL           ;POSN
           LD A,(HL)         ;SGN X OR CMD CODE
           LD E,A
           INC HL
           LD D,(HL)         ;ABS X OR SINGLE PARAM
           INC HL
           LD B,(HL)         ;SGN Y, OR ABS Y IF PLOT/DRAW TO/CIRCLE
           INC A             ;SGN=00 OR 01, PLOT CODE=02, DRAW TO=03
           CP 2
           JR C,DRCL         ;JR IF 00 OR 01 (REL. DRAW)

           SUB 4             ;2-> -2 (PLOT), 3-> -1 (DRAWTO), 4->0 (CIRCLE)
           JR NZ,FDNTCIR     ;JR IF CMD WAS NOT CIRCLE

           INC HL
           LD A,(HL)         ;GET RADIUS
           SCF

FDNTCIR:   JR NC,FDATTRS     ;JR IF 5 OR MORE (CODE NOW 1 OR MORE)

; PLOT, DRAW TO or CIRCLE. The coordinates are pushed onto the calculator stack as small integers so that the
; ordinary PLOT/DRAW/CIRCLE routines can be reused unchanged. The Y coordinate is converted from the BLITZ
; convention (0 at the top) to the BASIC one (0 at the bottom, plus ORGOFF), which can make it negative.

           EX AF,AF'         ;SAVE RADIUS AND Z FLAG, OR NZ AND -1/-2 (DTO/PLT)
           XOR A             ;'INTEGER'
           LD E,A            ;E (SGN) =00 (POS)
           LD C,E            ;MSB=00
           CALL STKSTORE     ;STACK AEDC - 00 00 X 00.
           LD A,(ORGOFF)
           LD D,A
           LD A,SCREENHEIGHT-1
           SUB B             ;A=Y WITH 191 AT TOP, 0 AT BOT
           SUB D             ;SUB ORGOFF
           LD D,A
           LD A,E            ;A=0
           JR NC,FDPOS

           DEC E             ;SGN=-VE **
           DEC C             ;MSB=FF

FDPOS:     CALL STKSTORE     ;STACK AEDC - 00 SGN  Y 00
           EX AF,AF'
           JR NZ,FDNTRAD

           LD C,A            ;RADIUS
           CALL CIRCLEFD
           JR MNLP4B

FDNTRAD:   INC A
           JR NZ,FDPLOT

           CALL DRAWTOFD     ;DRAW TO COORDS ON FPCS
           CP A              ;SET Z

FDPLOT:    CALL NZ,PLOTFD    ;PLOT THE COORDS ON FPC STACK
           LD C,3
           JR MAINLPH


; ---------------------------------------------------------------------------------------------------------------------
; FDATTRS -- the one-parameter commands: OVER, INK, CLS, PAUSE
;
; A is now the command code less 4, so the four are picked off by successive DECs and anything left over is an
; invalid BLITZ code.
; ---------------------------------------------------------------------------------------------------------------------

FDATTRS:   DEC A
           JR Z,FDOVER

           DEC A
           JR Z,FDINK

           DEC A
           JR Z,FDCLS

           DEC A
           JR NZ,FDINVERR

FDPAU:     LD C,D
           LD B,0
           RST &30           ;** BLITZ PAUSE BUG FIX
           DW PAU1
           JR FD1PARAM

FDCLS:     LD A,D
           CALL CLSBL        ;CLEAR WINDOW OR ALL SCREEN
           LD C,2
           JR MAINLPH

; INK sets both the mode 2/3 nibble-replicated ink (M23INKT) and the low three bits of ATTRT, so that text printed
; after a BLITZ INK comes out in the same colour.

FDINK:     LD A,D
           LD (M23INKT),A
           LD HL,ATTRT
           XOR (HL)
           AND &07
           XOR (HL)
           LD (HL),A
           JR FD1PARAM

FDOVER:    LD A,D
           INC HL
           LD (GOVERT),A

FD1PARAM:  LD C,2
           JR MAINLPH


; ---------------------------------------------------------------------------------------------------------------------
; DRCL -- relative DRAW: four bytes of sign, X, sign, Y
;
; Each displacement is stacked as a signed small integer, the sign byte serving directly as the value's high byte
; (00 or FF), which is exactly the small-integer format's sign convention.
; ---------------------------------------------------------------------------------------------------------------------

DRCL:      INC HL
           LD A,(HL)         ;ABS Y . NOW E/D=SGN X/X, B/A=SGN Y,Y
                             ;(SGN=00 OR FF)
           EX AF,AF'         ;SAVE Y
           XOR A             ;'INTEGER'
           LD C,E            ;MSB MATCHES SGN
           CALL STKSTORE     ;STACK AEDC
           EX AF,AF'
           LD E,B
           LD D,A
           XOR A
           LD C,E
           CALL STKSTORE     ;STACK AEDC
           CALL DRAWFD

MNLP4B:    LD C,4

; MAINLPH -- advance past the command just executed and test for the end of the string.
; The position may cross a 16K boundary, which is what the FFxx test and INCURPAGE handle.

MAINLPH:   XOR A
           LD B,A
           POP HL            ;POSN
           ADD HL,BC         ;ADVANCE POSN, NC
           LD A,H
           INC A
           CALL Z,INCURPAGE  ;ONLY IF ADDR IS FFXX IS THERE A NEED TO INC PAGE
           EX DE,HL
           POP HL            ;LENGTH

FDLNTST:   SBC HL,BC         ;SUB BYTES PROCESSED IN LAST GRAPHICS CMD
           JP NC,FDMAINLP    ;JR TILL PAST END

           POP AF
           LD (GRARF),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; BLITZ -- the command
;
; RECORD is turned off for the duration and restored at the end, so a BLITZ inside a recording does not record
; everything it draws a second time.
;
; The loop is entered at the length test rather than at the top, with BC = 1, so that a zero-length string exits
; immediately and every later test can be on carry alone rather than on carry-or-zero.
;
; Entry:  BLITZ -- CHAD at the string expression; JBLITZ -- DE = string start, BC = length, already paged in
; Errors: ERR_BADBLITZ
; ---------------------------------------------------------------------------------------------------------------------

BLITZ:     CALL SYNTAXA

           CALL GETSTRING    ;DE=START, BC=LEN, PAGED IN

JBLITZ:    PUSH DE
           PUSH BC
           CALL GRATEMPS
           POP BC
           POP DE
           LD HL,GRARF
           LD A,(HL)
           PUSH AF
           XOR A             ;NC
           LD (HL),A         ;GR. RECORD OFF, BUT CURRENT STATUS REPLACED AT END
           LD H,B
           LD L,C            ;HL=LENGTH, DE=POSN
           LD BC,1           ;AT START,SUB 1 FROM LEN, EXIT IF LEN WAS 0. ALSO
                             ;ALLOWS LATER LEN TEST TO BE ON CY/NC, NOT CY+Z
           JR FDLNTST

FDINVERR:  RST &08
           DB ERR_BADBLITZ   ;INVALID BLITZ CODE


; =====================================================================================================================
; FILL -- textured flood fill
; =====================================================================================================================
;
;    EG FILL X,Y               ;USES CURRENT INK
;    EG FILL USING A$,X,Y      ;USES INKS CODED IN PATTERN STRING
;    EG FILL INK 3,X,Y
;    EG FILL USING A$,INK 3,X,Y GIVES SOLID FILL, IGNORES A$
;
; The algorithm works on a *check screen* rather than on the display: a one-bit-per-pixel bitmap at &E000 in which
; a set bit means "this pixel is not part of the region to fill", either because it was already a different colour
; from the seed pixel or because the fill has since reached it. TRANSCR builds that bitmap by comparing every pixel
; with the colour at the seed point. Working on one bit per pixel makes the boundary test a single AND, and makes
; the mode 2 and mode 3 cases identical from the flood algorithm's point of view.
;
; The flood itself is the classic scanline-stack method: from a seed, run left to the boundary, then run right
; filling as you go, pushing the coordinates of any newly-exposed pixel above or below onto the machine stack. The
; stack is moved to FILLSTK for the duration, because a complicated region can need far more space than the normal
; BASIC stack has.
;
; Colour comes from FILBUFF, a 128-byte pattern tiled across the screen: the low three bits of the screen column
; and the low four bits of the Y coordinate index into it, so the texture repeats every 8 bytes horizontally and
; every 16 scans vertically.
;
; From the jump table: if DE=0 do a solid fill, otherwise use 128 bytes at DE as the pattern; A=0 means build the
; check screen (skip it if the caller has already prepared one).
; ---------------------------------------------------------------------------------------------------------------------

JFILL:        LD (TEMPW1),HL   ;BYTE OFFSET IF MODE 2
              PUSH BC          ;START COORDS
              LD B,1           ;USE 128 BYTES SINCE BC<>131
              LD (TEMPB1),A
              JR JFILL2

FILL:         CP USINGTOK
              JR NZ,PASTUSNG

              CALL SEXPTSTR
              CALL INSISCSC    ;REQUIRE COMMA OR SEMICOLON
              CP A             ;SET ZERO FLAG

PASTUSNG:     CALL NZ,CONDSTK0 ;STACK 0 IF NO 'USING' AND RUNNING

              CALL SYNTAX9     ;CHECK FOR COLOURS, X,Y
              CP ","
              JR NZ,FCKE

              CALL SSYNTAX6    ;0 OR DEFAULT MEANS 'COPY TO CHK SCRN', 1 MEANS
                               ;'SUPRESS COPYING'

              LD DE,&0200+ERR_IOOR
              CALL LIMBYTE     ;ACCEPT 0 OR 1 ONLY
              JR FSCY

FCKE:         CALL CHKEND
              XOR A

FSCY:         LD (TEMPB3),A
              CALL CHKMD23     ;INSIST ON MODE 2 OR 3
              RST &30
              DW CIFILSR       ;COORDS TO BC, OFFSET IF MODE 2 TO TEMPW1
              JR NC,FILLX4     ;JR IF MODE 3 ELSE HL=PIX OFFSET

; Mode 2: four pixels to the byte, so the X coordinate splits into a byte offset (kept in TEMPW1 and always even,
; since the check screen works in units of eight display pixels) and a pixel offset within the group of eight.

              LD A,L
              RR H
              RRA
              RRA              ;A=OFFSET/4 (BYTE)
              AND &7E
              LD (TEMPW1),A    ;OFFSET 0,2,4 ETC
              LD A,L
              AND 7
              ADD A,C
              LD C,A

FILLX4:       PUSH BC          ;COORDS TO START AT
              CALL GETSTRING   ;SWITCHES IT IN, GETS DE=START, BC=LEN (<4000)

; Load FILBUFF with the pattern. With no USING, the buffer is filled with the current ink by writing one byte and
; letting LDIR propagate it. A string exactly FILGETBLKLEN long is assumed to be a GRAB of a 2x2 character block,
; whose three-byte header is skipped.

JFILL2:       LD HL,FILBUFF    ;STORES PATTERN
              LD A,D
              OR E
              JR NZ,DEFPAT

              LD A,(M23INKT)
              LD (HL),A        ;IF NO 'USING', USE SOLID CURRENT INK
              LD D,H           ;STRING START OF 0 MEANS USE SOLID PATTERN
              LD E,L
              INC DE           ;DE=BUFFER START+1
              LD BC,FILPATLEN-1
              JR SOLIDEN       ;BUFFER WILL BE FILLED WITH SOLID INK

DEFPAT:       LD A,B
              AND A
              JR NZ,DEFPAT1

              LD A,C
              CP FILGETBLKLEN
              JR NZ,DEFPAT1    ;JR IF LEN NOT THAT OF A 2*2 GET BLOCK
                               ;(CONTROL CODE, WIDTH, LENGTH, 128 BYTES)

              INC DE
              INC DE
              INC DE           ;POINT TO DATA

DEFPAT1:      EX DE,HL
              LD BC,FILPATLEN

SOLIDEN:      LDIR             ;COPY STRING TO BUFFER

              CALL SPSS        ;SAVE PAGE,SELECT SCREEN (NO USE OF HL)
              LD A,(TEMPB3)
              AND A
              POP HL           ;START COORDS
              PUSH HL
              CALL Z,TRANSCR   ;NOW COPY SCREEN TO CHECK SCREEN

              POP BC           ;START COORDS
              LD (TEMPW3),SP
              LD SP,FILLSTK    ;END OF SCREEN GIVES MORE SPACE FOR STACK
              CALL FILLMN
              LD SP,(TEMPW3)
              JP TRCURP        ;RESET PAGE AND TEMP COLOURS


; ---------------------------------------------------------------------------------------------------------------------
; FILLMN -- the flood loop
;
; The stack holds pending seed coordinates as BC pairs (B = Y, C = X), below a stopper of &FE in B, which is not a
; legal Y coordinate. Off-screen seeds are recognised by B being &C0 or more: Y wraps to &FF when it goes above the
; top and reaches &C0 (192) when it falls off the bottom.
;
; Registers through the inner loops:
;   BC      current coordinates
;   D       the bit mask for the current pixel within its check-screen byte
;   E       flags: bit 7 set in mode 2, bit 0 "the pixel above is filled", bit 1 "the pixel below is filled"
;   IX      current check-screen address, also held in TEMPW2
;   BC'/HL' pattern indexing: C' is the Y-derived part of the FILBUFF index, H' its page
;   DE'     the real screen address
; ---------------------------------------------------------------------------------------------------------------------

FILLMN:       LD A,&FE
              PUSH AF          ;STOPPER TO STACK, START COORDS TO HL
              PUSH BC          ;START COORDS

UNSTK:        POP  BC
              LD   A,B
              CP   &FE
              RET Z            ;EXIT IF STOPPER

              CP   &C0
              JR   NC,UNSTK    ;LOOP IF OFF-SCREEN (FF IF TOO LOW, B0 IF TOO HI)
                               ;CARRY ALWAYS SET HERE

; Coordinates to a check-screen address: the bitmap is 32 bytes per scan, so the address is FILCHKSCRN + Y*32 + X/8.
; Rotating B and L right together three times performs both divisions at once.

              LD L,C           ;NOW GET CHK SCREEN ADDRESS FROM COORDS
              RRA              ;A=B
              RR L
              RRA
              RR L
              RRA
              RR L
              OR FILCHKSCRN/256
              LD H,A           ;HL=Y/8+X/8+FILL CHK SCRN (MUST BE ON 8K PAGE)

              LD A,C
              AND &07
              LD E,A           ;BIT OFFSET
              INC E
              LD A,&01

FRTMASK:      RRCA
              DEC E
              JR NZ,FRTMASK

              LD   D,A
              AND  (HL)
              JR   NZ,UNSTK    ;JR IF POINT IS FILLED ALREADY

; Run left to the first blocked pixel, or off the left-hand edge of the screen.

FINDEDG:      AND  (HL)
              JR   NZ,FOUNDEDG

              RLC  D           ;MOVE BIT MASK LEFT - CARRY IF OVERFLOW
              DEC C            ;MOVE X COORD LEFT
              LD   A,D
              JR   NC,FINDEDG  ;JR UNLESS NEED TO ALTER ADDR

              DEC L            ;1 BYTE LEFT
              INC C
              JR Z,FOUNDEDG1   ;JR IF WE FELL OFF LHS SCREEN EDGE

              DEC C
              JR FINDEDG

FOUNDEDG:     INC C            ;MAKE CURRENT POSN ONE

FOUNDEDG1:    RRC  D           ; PIXEL RIGHT OF BLOCKAGE
              JR   NC,NBACK    ;JR IF NO ADDRESS CHANGE NEEDED

              INC  L

NBACK:        LD (TEMPW2),HL
              PUSH HL
              POP  IX          ;POSN ALSO IN IX
              LD A,(MODE)
              SUB MODE16COL
              JR Z,FILLFLGS

              LD A,&80

FILLFLGS:     LD   E,A         ;INIT FLAGS. BIT 7=1 IF MODE 2
              PUSH BC          ;XY

              EXX
              POP BC
              LD A,B           ;A=Y
              ADD A,A
              ADD A,A
              ADD A,A
              OR &80           ;A=80-F8 (8*Y MOD 16)
              LD C,A
              LD H,FILBUFF/256
              EXX

              JR   FILLC

; The rightward run. Each iteration marks one pixel in the check screen, paints it on the real screen from the
; pattern, and inspects the pixels above and below; a transition from filled to unfilled either way pushes a new
; seed. The "above/below is filled" bits in E mean only one seed is pushed per contiguous run.

FILLB:        INC C
              JR   Z,UNSTK     ;JP IF X COORD PAST RHS

              RRC  D           ;ROTATE MASK
              CALL C,MVRGT     ;CALL IF TIME TO MOVE 1 BYTE RIGHT

FILLC:        LD   HL,(TEMPW2)
              LD   A,D
              AND  (HL)
              JR   NZ,UNSTK    ;JR IF PIXEL FILLED

              LD   A,D         ;ELSE
              OR   (HL)        ;FILL
              LD   (HL),A      ;PIXEL IN CHECK SCREEN
              LD A,B           ;Y

              EXX
              SCF
              RRA
              LD D,A
              EXX

              LD A,C           ;X COORD
              BIT 7,E

              EXX
              RRA
              JR NZ,FILLM2     ;JR IF MODE 2 (NZ SET BY BIT 7,E)

; Mode 3: two pixels (nibbles) to the byte, so the mask B is &0F or &F0 depending on whether X is even or odd.

              LD E,A           ;DE'=REAL SCREEN ADDR
              LD B,&0F
              JR NC,FILLOEC    ;JR IF EVEN X COORD

              LD B,&F0
              JR FILLOEC

; Mode 2: four pixels to the byte, and the byte offset from TEMPW1 has to be added. The mask is one of four
; two-bit fields.

FILLM2:       SRA A            ;KEEP BIT 7 THE SAME
              AND &BF          ;1011 1111. BIT 7 FROM Y IS KEPT, BITS 5-0=X/4
              LD E,A
              LD A,(TEMPW1)    ;OFFSET FROM LHS
              ADD A,E
              LD E,A           ;DE'=REAL SCREEN ADDR
              EXX

              LD A,C           ;X COORD

              EXX
              LD B,&3F         ;MASK FOR BITS TO ZERO
              AND 3
              JR Z,FILLM2M

              LD B,&CF
              DEC A
              JR Z,FILLM2M

              LD B,&F3
              DEC A
              JR Z,FILLM2M

              LD B,&FC

FILLM2M:      LD A,E

; Merge pattern and screen through the mask: the XOR/AND/XOR sequence replaces only the bits selected by B.

FILLOEC:      AND &07          ;A=PHYSICAL SCREEN COLUMN MOD 8
              OR C             ;GET BITS DETERMINED BY Y COORD
              LD L,A           ;HL' IS NOW COMPLETE FILBUFF ADDR
              LD A,(DE)
              XOR (HL)
              AND B            ;MIX BITS FROM FILBUFF PATTERN AND SCREEN
              XOR (HL)         ; ACCORDING TO MASK B
              LD (DE),A
              EXX

; Look above (32 bytes back in the check screen) and below (32 forward).

              LD   A,(IX-32)   ;A=BYTE ABOVE
              BIT  0,E
              JR   NZ,FILLE

              AND  D
              JR   NZ,FILLF    ;JR IF BIT FILLED

              DEC  B           ;GET Y OF LOCATION ABOVE
              PUSH BC          ;SAVE COORDS OF PLACE ABOVE
              INC  B
              SET  0,E         ;'ABOVE IS FILLED'
              JR   FILLF

FILLE:        AND  D
              JR   Z,FILLF    ;JR IF ABOVE NOT FILLED

              RES  0,E         ;'ABOVE NOT FILLED'

FILLF:        LD   A,(IX+32)   ;GET BYTE BELOW
              BIT  1,E
              JR   NZ,FILLG

              AND  D
              JR   NZ,FILLB    ;JR IF BELOW IS FILLED

              INC  B           ;INC Y
              PUSH BC          ;SAVE COORDS OF PLACE BELOW
              DEC  B
              SET  1,E         ;'BELOW IS FILLED'
              JR   FILLB

FILLG:        AND  D
              JR   Z,FILBH     ;JR IF NOT FILLED BELOW

              RES  1,E         ;'BELOW IS NOT FILLED'

FILBH:        JP   FILLB


; ---------------------------------------------------------------------------------------------------------------------
; MVRGT -- step the check-screen pointer one byte right, with an eight-pixel fast path
;
; Called when the rightward run crosses a byte boundary. If the whole of the next check-screen byte is empty *and*
; the runs above and below are in the same state right across it, then all eight pixels can be filled at once: the
; check-screen byte is set to &FF and the pattern is copied straight into the two (mode 2) or four (mode 3) screen
; bytes, skipping eight iterations of the main loop. This is what makes large flat areas fill quickly.
;
; If the fast path runs off the right-hand edge, the caller's return address is discarded and control goes straight
; back to UNSTK for the next seed.
; ---------------------------------------------------------------------------------------------------------------------

MVRGT:        LD   IX,(TEMPW2)
              INC  IX
              LD   (TEMPW2),IX   ;MOVE 1 COL RIGHT IN CHECK SCREEN

              LD   A,(IX+32)   ;BYTE BELOW
              BIT  1,E
              JR   NZ,MVRGT1

              INC  A
              JR   Z,MVRGT2

              RET

MVRGT1:       AND  A
              RET  NZ

MVRGT2:       LD   A,(IX-32)

              BIT  0,E
              JR   NZ,MVRGT3

              INC  A
              JR   Z,MVRGT4

              RET

MVRGT3:       AND  A
              RET  NZ

MVRGT4:       LD   HL,(TEMPW2)
              LD   A,(HL)
              AND  A
              RET  NZ          ;RET IF NOT SIMPLE BLANK IN CHK SCREEN

              LD   (HL),&FF    ;ELSE FILL 8 PIX AT ONCE

              LD A,B

              EXX
              SCF
              RRA
              LD D,A
              EXX

              LD A,C           ;X
              INC A            ;MOVE RIGHT ONTO 1ST. PIXEL OF 8-PIX BLOCK
              BIT 7,E

              EXX
              RRA
              JR Z,FILLM3B

              SRA A            ;KEEP BIT 7 THE SAME
              AND &BF          ;1011 1111. BIT 7 FROM Y IS KEPT, BITS 5-0=X/4
              LD E,A
              LD A,(TEMPW1)    ;OFFSET FROM LHS
              ADD A,E

              LD E,A           ;DE'=REAL SCREEN ADDR
              AND &07          ;A=PHYSICAL SCREEN COLUMN MOD 8
              OR C             ;GET BITS DETERMINED BY Y COORD
              LD L,A           ;HL' IS NOW COMPLETE FILBUFF ADDR
              JR FILLBC        ;COPY 2 BYTES FROM PATTERN IN MODE 2

FILLM3B:      LD E,A           ;DE'=REAL SCREEN ADDR
              AND &07          ;A=PHYSICAL SCREEN COLUMN MOD 8
              OR C             ;GET BITS DETERMINED BY Y COORD
              LD L,A           ;HL' IS NOW COMPLETE FILBUFF ADDR
                               ;COPY 4 BYTES FROM FILLBUF PATTERN IN M3
              LD A,(HL)
              LD (DE),A
              INC E
              INC L

              LD A,(HL)
              LD (DE),A
              INC E
              INC L

FILLBC:       LD A,(HL)
              LD (DE),A
              INC E
              INC L

              LD A,(HL)
              LD (DE),A        ;COPY 8 PIXELS
              EXX

              LD A,C
              ADD A,8
              JR Z,MVRGT5    ;JR IF AT RHS OF SCREEN

              LD   C,A
              JR   MVRGT

MVRGT5:       POP  HL          ;JUNK RET ADDR
              JP   UNSTK


; =====================================================================================================================
; TRANSCR -- build the fill check screen
; =====================================================================================================================
;
; Reduces the mode 2 or mode 3 display (or, for CHARCOMP, a single character cell) to one bit per pixel: a bit is
; set where the pixel's colour differs from the seed colour, so a set bit is a boundary the fill must not cross.
;
; Mode 3 is a straight nibble comparison, two pixels per source byte, eight source bytes per output byte. Mode 2 is
; the same idea on two-bit pixels, sixteen pixels per output byte -- but mode 2 stores its two bits as separate
; planes within a byte, hence the two-bit rotate in the inner loop.
;
; The comparison itself is the SUB/CP 1/RL C idiom: subtracting the seed colour gives zero on a match, CP 1 then
; sets carry only for zero, and RL C shifts that carry into the result byte. The whole byte is complemented at the
; end so that matching pixels are zeros.
;
; Entry:  HL = coordinates of the fill origin
;         TRANSODD -- entered by the mode 2/3 screen dump with A = the background colour
; Uses:   HL, DE, BC, HL', DE', BC'
; ---------------------------------------------------------------------------------------------------------------------

TRANSCR:      SCF
              LD C,L           ;X
              RR H
              RR L
              LD A,(MODE)
              CP MODE16COL
              JR Z,TRANSL1

              LD A,L
              SRA A            ;KEEP BIT 7 THE SAME
              AND &BF          ;1011 1111. BIT 7 FROM Y IS KEPT, BITS 5-0=X/4
              LD L,A
              LD A,(TEMPW1)    ;OFFSET FROM LHS
              ADD A,L
              LD L,A           ;HL=M2 SCREEN ADDR
              LD A,C           ;X
              AND 3
              INC A
              LD B,A
              LD A,(HL)

TRAM2RLP:     RLCA
              RLCA
              DJNZ TRAM2RLP

              JR TRANSODD

TRANSL1:      LD A,(HL)
              BIT 0,C
              JR NZ,TRANSODD

              RLCA
              RLCA
              RLCA
              RLCA

;ENTRY USED BY MODE 2/3 SCREEN DUMP WITH A=BACKGROUND COLOUR

TRANSODD:     EXX
              LD HL,FILCHKSCRN ;HL' IS DEST SCREEN PTR FOR FILL CHECKING
              LD DE,&C020      ;D'=192 SCANS, E'=32 BYTES/SCAN IN CHECK SCREEN
              EXX

              LD HL,&8000      ;REAL SCREEN START

; CHARCOMP2 -- the conversion proper. Called with D' = scans to do and E' = bytes per scan, so the same code serves
; the whole screen (192 x 32) and a single character (1 x 1) for CHARCOMP.

CHARCOMP2:    AND &0F          ;GET COLOUR TO SET TO ZEROS IN CHECK SCREEN
              LD D,A
              RLCA
              RLCA
              RLCA
              RLCA             ;GET DESIRED INK IN MS NIBBLE
              LD E,A
              LD A,(MODE)
              CP MODE16COL
              JR Z,TRANSM3

              LD A,(TEMPW1)
              LD L,A           ;OFFSET REAL SCREEN ADDR
              LD A,D
              AND 3
              LD D,A

              EXX

TRAM2DLP:     LD C,E           ;RELOAD BYTES/SCAN COUNTER C'

TRAM2CLP:     LD B,2

TRAM2OLP:     EXX
              LD E,(HL)        ;E=DATA FROM M2 SCRN
              LD B,4           ;4 DOUBLE BITS/BYTE

TRAM2ILP:     LD A,E
              RLCA
              RLCA
              LD E,A
              AND 3
              SUB D
              CP 1
              RL C             ;BITS IN C SHOW IF PIXEL IN M2 SCRN IS 'INK'
              DJNZ TRAM2ILP

              INC HL           ;NEXT M2 SCREEN BYTE
              LD A,C           ;GET DATA IN CASE THIS IS SECOND BYTE
              EXX
              DJNZ TRAM2OLP    ;DO 2 (B') M2 SCREEN BYTES/CHECK SCREEN BYTE

              CPL              ;PIX THAT MATCH ORIGIN=0
              LD (HL),A
              INC HL
              DEC C            ;DO REQUIRED BYTES ACROSS (1 OR 32)
              JR NZ,TRAM2CLP

              EXX
              LD BC,64         ;DROP TO NEXT SCAN IF FILL, IRREL IF CHARCOMP
              ADD HL,BC
              EXX

              DEC D            ;DO D' SCANS
              JR NZ,TRAM2DLP

              EXX

              RET

; Mode 3. The eight-bit counter is the C register itself: it starts at 1 and each RL C shifts a result bit in, so
; when the original 1 falls out into carry after eight rotations the byte is complete.

TRANSM3:      LD B,1         ;CP WITH THIS TO SET CY IF A=0
              EXX

TRANSDLP:     LD C,E           ;RELOAD BYTES/SCAN COUNTER C'

TRANSCLP:     EXX
              LD C,B           ;C=1. CY WHEN BIT ROTATED OUT AFTER 8 ROTS.

TRANSBLP:     LD A,(HL)
              AND &F0
              SUB E            ;GET A=ZERO IF PIXEL MATCHES ORIGIN INK
              CP B             ;SET CARRY IF A=0
              RL C
              LD A,(HL)
              INC HL
              AND &0F
              SUB D
              CP B
              RL C
              JP NC,TRANSBLP

              LD A,C
              CPL              ;PIX THAT MATCH ORIGIN=0

              EXX
              LD (HL),A        ;MOVE TO CHECK SCREEN AT (HL')
              INC HL
              DEC C
              JR NZ,TRANSCLP   ;DO C' BYTES/SCAN IN CHECK SCREEN

              DEC D            ;AND D' SCANS
              JR NZ,TRANSDLP

              EXX
              RET


; ---------------------------------------------------------------------------------------------------------------------
; CHARCOMP -- compress a mode 2/3 character cell to the standard 8-byte bitmap form
;
; Used by SCREEN$, which has to recognise a character on the screen by comparing its bitmap against the font, and
; by graphics COPY. The "background" colour against which pixels are compared is taken from the top left pixel of
; the cell, which is where the character's own paper colour will be for anything drawn normally.
;
; Entry:  HL points at the cell in the mode 2/3 screen, DE at an 8-byte buffer,
;         CY = 6-bit characters, NZ/Z = odd/even column
;         GRCOMP -- entered by graphics COPY with NC and A already the background colour
; Uses:   AF, HL, DE, BC, HL', DE', BC'
; ---------------------------------------------------------------------------------------------------------------------

CHARCOMP:     PUSH AF
              CALL SPSSR     ;SELECT SCREEN, ROM1 OFF
              POP AF
              PUSH DE
              JR NC,CHCM2    ;JR IF NOT 6-PIX CHARS

              LD A,(HL)      ;SCREEN DATA
              JR Z,CHCM3     ;JR IF EVEN COLUMN - TOP LHS PIX IN BITS 7,6

              RRCA           ;ELSE DATA IN BITS 3,2
              RRCA
              JR CHCM4       ;NOW IN 1,0

CHCM2:        LD A,(MODE)
              CP MODE4COL
              LD A,(HL)      ;SCREEN DATA
              JR Z,CHCM3     ;JR IF MODE 2 - TOP LHS PIXEL DATA IS BITS 7,6

              RLCA           ;ELSE IT IS BITS 7,6,5,4
              RLCA

CHCM3:        RLCA
              RLCA           ;DATA NOW IN RH 2 OR 4 BITS

CHCM4:        EXX              ;A=BACKGROUND COLOUR - (TOP LHS PIXEL COLOUR)
              POP HL           ;BUFFER FOR 8-BYTE COMPRESSED FORM FOR SCREEN$
              SCF

;CALLED BY GRAPHICS COPY WITH NC

GRCOMP:       LD B,A
              CALL NC,SPSSR   ;SELECT SCREEN
              LD A,B
              LD B,CELLBYTES   ;8 SCANS

CHARCLP:      PUSH BC
              PUSH AF          ;BG COLOUR
              LD DE,&0101      ;1 SCAN AT A TIME, 1 BYTE ACROSS IN RESULT

              EXX
              PUSH HL
              LD (TEMPW1),HL   ;OFFSET FOR SCREEN SOURCE ADDR (USED BY MODE 2
                               ;FILL, AND CHARCOMP2 NEEDS IT)
              CALL CHARCOMP2   ;DO A SCAN
              POP HL
              LD A,L           ;NOW DROP TO NEXT SCAN
              ADD A,SCANBYTESM23 ;SCAN LEN
              LD L,A
              JR NC,CHARCNINC

              INC H

CHARCNINC:    EXX
              POP AF           ;BG COLOUR
              POP BC
              DJNZ CHARCLP

              JP RCURPR


; =====================================================================================================================
; Coordinate handling
; =====================================================================================================================
;
; Every graphics command takes its coordinates from the calculator stack and puts them through the same pipeline:
; the pseudo-variables XOS/YOS (origin offset) and XRG/YRG (coordinate range) are applied, the Y axis is inverted
; so that zero is at the top, and the result is range-checked.
;
; Two coordinate systems coexist. With FATPIX in force (and always outside mode 2) X runs 0-255 and fits in a byte;
; with thin pixels in mode 2 it runs 0-511 and needs a full register pair. The routines below signal which by the
; carry flag: CY means thin pixels and X in HL, NC means fat pixels and X in C.
; ---------------------------------------------------------------------------------------------------------------------


; ---------------------------------------------------------------------------------------------------------------------
; GTFIDFCDS -- coordinates with fat pixels forced. Used by GET and by ROLL/SCROLL
;
; Exit:   B = Y, C = X in fat-pixel units
; ---------------------------------------------------------------------------------------------------------------------

GTFIDFCDS:    CALL GTFCOORDS
              RET NC            ;RET IF FAT PIX

              RR H
              RR L
              LD C,L            ;HALVE X, MOVE TO C
              RET


; ---------------------------------------------------------------------------------------------------------------------
; GTFCOORDS / USCOORDS -- unstack a coordinate pair
;
; Entry:  X,Y on the calculator stack (GTFCOORDS applies the pseudo-variables first)
; Exit:   B = Y, corrected from the -16..175 range on the stack to 0-191 and then inverted so 0 is at the top
;         CY set: thin pixels, HL = X checked for 0-511
;         NC:     fat pixels, C = X checked for 0-255
; Errors: ERR_IOOR
; ---------------------------------------------------------------------------------------------------------------------

GTFCOORDS:    CALL COORDFID     ;APPLY OFFSETS AND RANGES

USCOORDS:     CALL USYCOORD
              PUSH AF           ;Y
              CALL GETINT       ;HL=X COORD. BC=HL
              LD (TEMPW2),HL    ;SAVE FOR 'RECORD' TO USE
              LD A,(THFATT)     ;A=0 IF THIN PIX
              AND A
              LD A,H            ;A=X MSB
              POP BC            ;B=Y
              JR NZ,THCKCHK

              CP 2              ;CHECK X MSB VS 2 - MUST BE ZERO OR 1
              RET C             ;CY SIGNALS THIN PIX
                                ;A MUST BE 2-FF HERE

THCKCHK:      LD C,L            ;C=X
              AND A
              RET Z             ;NC

              JR IOORERR1    ;X MSB MUST BE 0 UNLESS THIN PIX


; ---------------------------------------------------------------------------------------------------------------------
; USYCOORD -- unstack the Y coordinate, check it and convert to the 0-191 scale
;
; ORGOFF is how far below the bottom of the screen the graphics origin sits -- 16 for the standard 8-scan character
; height, so Y may legitimately run from -16 to 175. Adding ORGOFF maps that to 0-191, and subtracting from 191
; inverts the axis to match the display.
; ---------------------------------------------------------------------------------------------------------------------

USYCOORD:     CALL FPTOA        ;A (AND C)=ABS Y. Z IF POSITIVE
              JR C,IOORERR1

              LD A,(ORGOFF)      ;16 IF HEIGHT=8
              JR NZ,ADJNEG       ;JR IF Y IS -VE

              ADD A,C
              JR NC,ADJOK1      ;ADD 16 SO 0-175 BECOME 16-191

IOORERR1:     RST &08
              DB ERR_IOOR

ADJNEG:       SUB C             ;(16 IF HEIGHT=8)-ABS Y
              JR C,IOORERR1     ;IF Y IS NEGATIVE, ABS Y MUST BE <=ORGOFF
                                ;-1 TO -16 NOW 15 TO 0
ADJOK1:       LD B,A
              LD A,SCREENHEIGHT-1
              SUB B
              JR C,IOORERR1

              LD (TEMPB1),A      ;A=0-191. SAVE FOR 'RECORD' TO USE
              RET


; ---------------------------------------------------------------------------------------------------------------------
; TWONUMS -- unstack a pair of *displacements* for a relative DRAW
;
; Unlike coordinates these are signed and are not offset or inverted -- except that the sign of Y is reversed,
; because the Y axis on screen runs the opposite way to the BASIC one.
;
; Exit:   B = Y, D = sign of Y, E = sign of X (each 01 or FF)
;         CY set: thin pixels, HL = X displacement (0-511)
;         NC:     fat pixels, C = X displacement (0-255)
; Errors: ERR_IOOR
; ---------------------------------------------------------------------------------------------------------------------

TWONUMS:   CALL FPTOA
           JR C,IOORERR1     ;ERROR IF ABS Y>255

           LD B,&FF          ;-VE. REVERSE SGN BECAUSE Y COORD REVERSES
           JR Z,POSBYTE

           LD B,&01          ;+VE

POSBYTE:   PUSH BC           ;B=SGN Y, C=Y
           CALL FPTOBC       ;BC=X. Z IF +VE. CY IF OOR
           JR C,IOORERR1

           LD H,1            ;+VE
           JR Z,POSINT

           LD H,&FF          ;-VE. H=SGN X

POSINT:    POP DE            ;D=SGN Y, E=Y
           LD A,(THFATT)     ;THIN/FAT TEMP. ONLY SAYS THIN IF MODE 2.
           AND A
           LD A,B            ;X MSB
           LD B,E            ;B=Y
           LD E,H            ;E=SGN X
           JR Z,THINNUMS

           AND A
           JR NZ,IOORERR1    ;X MSB MUST BE ZERO IF FAT PIX IN USE

           RET               ;B=Y, C=X, D=SGN Y, E=SGN X. NC

THINNUMS:  LD L,C
           LD H,A            ;HL=X
           CP 2
           JR NC,IOORERR1

           RET               ;HL=X, E=SGN X, D=SGN Y, B=Y. CY SHOWS THIN STATUS
                             ;BC MUST BE 01FF OR LESS


; ---------------------------------------------------------------------------------------------------------------------
; COORDFID / DRCOORDFD -- apply the graphics pseudo-variables to a coordinate pair
;
; XOS and YOS shift the origin; XRG and YRG rescale the axes, so that a program can work in whatever coordinate
; range suits it. Each is applied only when it differs from its normal value, which is what CHECKPS tests -- so a
; program that never touches them pays only four comparisons.
;
; DRCOORDFD is the entry for DRAW, which needs the range scaling but not the origin offset: a displacement must not
; be shifted by where the origin happens to be.
;
; Entry:  X,Y on the calculator stack
; ---------------------------------------------------------------------------------------------------------------------

DRCOORDFD: SCF               ;'DON'T APPLY XOS'
           JR RGFIDEN

;RANGE AND OFFSET FIDDLE. USED BY E.G. PLOT.

COORDFID:  XOR A             ;NC='OFFSET'
           LD B,A
           LD C,A            ;BC=0=NORMAL YOS
           EX AF,AF'
           LD E,YOSDISP
           CALL PSEUDOSR     ;ADD YOS IF NON-NORMAL (<>ZERO)
           XOR A             ;NC='APPLY XOS'

RGFIDEN:   PUSH AF
           SCF               ;'RANGE'
           EX AF,AF'
           LD E,YRGDISP
           LD BC,SCREENHEIGHT
           CALL PSEUDOSR     ;APPLY YRG UNLESS IT IS 192
           CALL SWOP12       ;GET X COORD TO STACK TOP
           POP AF
           JR C,DOXRG        ;NC MEANS APPLY XOS. A=0

           LD B,A
           LD C,A
           EX AF,AF'
           LD E,XOSDISP
           CALL PSEUDOSR     ;ADD XOS IF NON-NORMAL (<>ZERO)
           SCF               ;'RANGE'

DOXRG:     EX AF,AF'
           LD BC,512
           LD A,(THFATT)
           AND A
           JR Z,GXRANGE      ;RANGE=512 IF THIN

           DEC B             ;BC=256

GXRANGE:   LD E,XRGDISP
           CALL PSEUDOSR     ;APPLY XRG UNLESS IT IS NORMAL
           JP SWOP12         ;GET Y TO TOP OF FPCS


; ---------------------------------------------------------------------------------------------------------------------
; PSEUDOSR -- apply one pseudo-variable to the value on top of the calculator stack
;
; Offsets are added; ranges rescale by multiplying by normal/range. Either way, nothing happens at all if the
; pseudo-variable still holds its normal value.
;
; Entry:  E = displacement from the pseudo-variable area to XOS/YOS/XRG/YRG
;         F' = CY for a range, NC for an offset
;         BC = the normal value of the variable
; ---------------------------------------------------------------------------------------------------------------------

PSEUDOSR:  IN A,(URPORT)
           PUSH AF
           CALL ADDRNV
           LD D,0
           ADD HL,DE
           LD D,H
           LD E,L            ;DE PTS TO PS START
           CALL CHECKPS      ;SEE IF PSEUDO VAR=BC (NORMAL)
           JP Z,PPORT        ;JR IF PSEUDO VAR=NORMAL, DON'T APPLY IT.
                             ;(POP AF, OUT, RET)
           PUSH BC           ;NORMAL VALUE
           EX DE,HL
           CALL HLTOFPCS     ;ELSE STACK PSEUDO-VAR
           POP BC
           POP AF
           OUT (URPORT),A
           EX AF,AF'
           JR C,APPLYRG

           DB CALC
           DB ADDN           ;ADD OFFSET
           DB EXIT2

APPLYRG:   CALL STACKBC

           DB CALC
           DB SWOP
           DB DIVN           ;NORM/RG
           DB MULT           ;COORD*NORM/RG
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; CHECKPS -- does the pseudo-variable at (HL) hold its normal value BC?
;
; Normal values are always small integers, whose five-byte form begins 00 00, so the test is two zero bytes
; followed by BC.
;
; Exit:   Z if normal
; ---------------------------------------------------------------------------------------------------------------------

CHECKPS:   LD A,(HL)
           INC HL
           OR (HL)
           RET NZ            ;NORMAL VALUES ALWAYS START 00 00

           INC HL
           LD A,C
           CP (HL)
           RET NZ

           INC HL
           LD A,B
           CP (HL)
           RET


; =====================================================================================================================
; GRAREC -- the graphics recorder
; =====================================================================================================================
;
; With RECORD in force, every graphics command calls here to append its BLITZ-format equivalent to the string being
; recorded. Output goes through stream 16, the "to string" stream, so the accumulating recording is an ordinary
; BASIC string and can be saved, edited or handed straight to BLITZ.
;
; Entry:  E = command code, as below
;         PLOT/DRAW TO/CIRCLE take their coordinates from TEMPB1 (Y) and TEMPW2 (X), where the coordinate
;         routines left them; CIRCLE has its radius in B
;         a relative DRAW uses E, C, D, B for sign X, X, sign Y, Y
;         PEN, OVER, PAUSE and CLS use E, C for code and parameter
;
;   E=FE/00 IF FAT REL. DRAW
;   E=1        FAT PLOT
;   E=2        FAT DRAW TO
;   E=3        CIRCLE
;   E=4        OVER
;   E=5        PEN
;   E=6        CLS
;   E=7        PAUSE
;
; PRINT is excluded, so that PRINT PEN 5; does not record a pen change that was only ever a print modifier.
; ---------------------------------------------------------------------------------------------------------------------

GRAREC:    LD A,(GRARF)
           AND A
           RET Z             ;RET IF RECORD OFF

           LD A,(CURCMD)
           CP TOK_PRINT
           RET Z             ;AVOID RECORD OF E.G. PRINT PEN 5;

           PUSH HL
           PUSH DE
           PUSH BC
           LD A,E
           LD HL,INSTBUF
           DEC A             ;SGN FE/00 GOES TO FD/FF
           CP &FD
           JR C,GRAR6        ;JR IF NOT REL. DRAW

; A relative draw. The internal sign convention (FE/00) is converted to the BLITZ one (FF/00) and the
; displacements are made positive, since BLITZ stores magnitude and sign separately. Y is un-inverted here,
; undoing the reversal TWONUMS applied.

           INC A
           JR Z,GRAR4        ;JR IF +VE X SGN (E=0)

           INC E             ;E=FF
           XOR A
           SUB C
           LD C,A            ;NEGATE X DISP

GRAR4:     INC D             ;Y SGN
           JR Z,GRAR5        ;JR IF -VE Y SGN.. Y IS REALLY +VE - FIDDLED BY
                             ;TWONUMS BECAUSE OF Y AXIS REVERSAL
           LD D,&FF
           XOR A
           SUB B
           LD B,A            ;NEGATE Y DISP

GRAR5:     LD (HL),E
           LD A,B
           LD B,D
           LD D,A            ;SWOP B AND D
           LD E,3            ;PRETEND 'CIRCLE'
           JR GRAR66

GRAR6:     CP 3
           JR NC,GRAR65

GRAR62:    LD A,(TEMPW2)
           LD C,A            ;X
           LD A,(TEMPB1)     ;Y
           LD B,A            ;COORDS TAKEN FROM STORES USED BY CRDFID

GRAR65:    LD (HL),E         ;BLITZ CODE

GRAR66:    INC HL
           LD (HL),C
           INC HL
           LD (HL),B         ;MAY BE JUNK
           INC HL
           LD (HL),D         ;MAY BE JUNK
           LD A,E
           DEC A
           LD C,3
           CP 2
           JR C,GRAR7        ;JR IF PLOT OR DRAWTO - 3 BYTES

           LD C,4
           JR Z,GRAR7        ;JR IF CIRCLE OR REL DRAW - 4 BYTES

           LD C,2

GRAR7:     LD HL,(CURCHL)
           PUSH HL
           PUSH BC
           LD A,16
           CALL SETSTRM      ;STREAM 16 - TO STRING
           POP BC
           LD B,0
           LD DE,INSTBUF
           CALL PRINTSTR     ;O/P BC FROM DE TO STRING
           POP HL
           LD (CURCHL),HL    ;STREAM 16 DOESN'T SET ANY FLAGS, SO NO NEED
           POP BC            ;TO CALL CHAN-FLAG TO RESET THEM.
           POP DE
           POP HL
           RET
