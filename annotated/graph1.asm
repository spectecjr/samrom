; =====================================================================================================================
; GRAPH1.ASM -- PLOT, and the per-mode pixel plotting routines
; =====================================================================================================================
;
; PLOT itself is short; most of this file is the family of routines that actually set a pixel, one per combination
; of screen mode and OVER setting.
;
; THE IY DISPATCH
; ---------------
; DRAW and CIRCLE plot thousands of points, so the mode and OVER settings are resolved once, before the loop, rather
; than tested at every pixel. SETIY chooses the right routine and leaves its address in IY; the drawing loops then
; simply JP (IY). For modes 2 and 3 it also returns the ink colour, which the loops park in D'.
;
; The plot routines return through IX rather than by RET, so the caller can choose where control goes -- DRAW uses
; that to have each plotted point fall into its edge-checking code when the line is running off-screen.
;
; FAT AND THIN PIXELS
; -------------------
; Internal mode 2 is 512 pixels wide. With thin pixels the X coordinate runs 0 to 511 and a pixel is one screen
; pixel; with fat pixels it runs 0 to 255 and each is doubled. Thin plotting has its own routine, and SETIY signals
; it by returning CY without setting IY.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; JPLOT -- plot a point (jump table entry &0139)
;
; Entry:  C = X and B = Y for fat pixels, or HL = X and B = Y for thin.
; ---------------------------------------------------------------------------------------------------------------------

JPLOT:      LD A,(THFATT)
            AND A
            JR NZ,JPLOT3                ; Fat pixels

            JR THINPLOT


; ---------------------------------------------------------------------------------------------------------------------
; PLOT -- the PLOT command
;
; Accepts colour items before the coordinates, as in PLOT INK 3;x,y.
; ---------------------------------------------------------------------------------------------------------------------

PLOT:       CALL SYNTAX9                ; Colour items, then two numbers
            CALL CHKEND

; --- PLOTFD: the entry BLITZ uses, with the coordinates already on the calculator stack ---

PLOTFD:     CALL GTFCOORDS              ; Apply the origin and range variables; Y ends 0 at the top
            JP C,THINPLOT               ; Thin pixels: HL = X, B = Y

            LD E,1                      ; BLITZ record code for a fat PLOT
            CALL GRAREC                 ; Append it if RECORD is active

JPLOT3:     CALL SPSS                   ; Save the paging and map the screen
            LD H,C
            LD L,B
            LD (YCOORD),HL              ; Record the position: Y, and the low byte of X
            LD H,B                      ; H = Y, with zero at the top
            LD L,C                      ; L = X
            CALL SETIY
            EXX
            LD D,A                      ; D' = the ink colour, for modes 2 and 3
            EXX
            LD IX,TRCURP                ; The plot routine returns straight to the paging restore
            JP (IY)


; =====================================================================================================================
; THINPLOT -- thin-pixel plot in internal mode 2
; =====================================================================================================================
;
; Entry:  HL = X, already checked as 0 to 511; B = Y.
;
; Two bits per pixel, four pixels per byte, so the address is &8000 + Y*128 + X/4 and the pixel is selected by a
; two-bit mask rotated into place.
; ---------------------------------------------------------------------------------------------------------------------

THINPLOT:   CALL SPSS
            CALL TDPLOT
            JP TRCURP

; --- TDPLOT: entered by DRAW, which has already mapped the screen ---

TDPLOT:     LD (XCOORD),HL
            LD A,B
            LD (YCOORD),A

; --- M2CTPLOT: entered by CIRCLE, which does not want the coordinate variables changed ---

M2CTPLOT:   POP IX                      ; The caller's return address becomes the exit route
            PUSH HL
            PUSH DE
            PUSH BC
            LD A,L                      ; A = X
            RR H
            RR L                        ; L = X/2
            LD H,B                      ; H = Y
            AND &03                     ; Which of the four pixels within the byte
            INC A
            LD B,A                      ; The mask is rotated twice per pixel position
            SCF
            RR H
            RR L                        ; HL = &8000 + Y/2 + X/4
            LD A,&FC                    ; A two-bit hole in a field of ones

P80RLP:     RRCA
            RRCA
            DJNZ P80RLP

            LD C,A                      ; C = the mask: zeros where the pixel is
            LD DE,(OVERT)               ; E = OVER 0 or 1, D = &00 or &FF for INVERSE
            LD A,(M23INKT)
            INC D
            JR NZ,M2TPIN0               ; INVERSE 0, so use the ink

            LD A,(M23PAPT)              ; INVERSE 1, so use the paper

M2TPIN0:    LD B,A
            DEC E
            JR Z,M2TPOV1                ; OVER 1

            LD A,(HL)
            XOR B
            AND C                       ; Clear the pixel's two bits ...
            XOR B                       ; ... and set them to the chosen colour
            JR M2TPC

M2TPOV1:    DEC D
            JR NZ,DRPLEND2              ; OVER 1 with INVERSE 1 does nothing at all

            LD A,C
            CPL                          ; Ones where the pixel is
            XOR (HL)                    ; Invert just that pixel

M2TPC:      LD (HL),A
            JR DRPLEND2


; =====================================================================================================================
; M0DPLOT / M1DPLOT -- plot in internal modes 0 and 1
; =====================================================================================================================
;
; One bit per pixel plus an attribute. Entry with L = X and H = Y.
;
; The four combinations of OVER and INVERSE are:
;
;     OVER 0, INVERSE 0    force the pixel on
;     OVER 1, INVERSE 0    invert it
;     OVER 0, INVERSE 1    force it off
;     OVER 1, INVERSE 1    leave it alone
; ---------------------------------------------------------------------------------------------------------------------

M0DPLOT:    PUSH HL
            PUSH DE
            PUSH BC
            LD B,H
            LD C,L
            CALL M0PIXAD                ; HL = the address, A = the bit offset
            LD B,A
            JR M01DPCOM

M1DPLOT:    PUSH HL
            PUSH DE
            PUSH BC
            CALL M1PIXAD                ; HL = &8000 + Y/8 + X/8, B = the bit offset 0-7

M01DPCOM:   LD A,&FE                    ; A single zero bit
            INC B

DPM2FLP:    RRCA
            DJNZ DPM2FLP                ; Rotate it to the pixel's position

            LD C,A                      ; C = the mask: zero where the pixel is
            LD DE,(OVERT)               ; E = 0 for OVER 0, D = &00 or &FF for INVERSE
            LD A,(HL)
            DEC E
            JR Z,DYOVER1                ; OVER 1: keep the existing pixel

            AND C                       ; OVER 0: clear it first

DYOVER1:    INC D
            JR Z,DRPLEND                ; INVERSE 1: leave it clear, or leave it as found

            XOR C
            CPL                          ; Set the pixel

DRPLEND:    LD (HL),A
            CALL POATTR01               ; Modes 0 and 1 also need the attribute set

DRPLEND2:   POP BC
            POP DE
            POP HL
            JP (IX)


; =====================================================================================================================
; M3DPOV0 to M3DPOV3 -- plot in internal modes 2 and 3, one routine per OVER mode
; =====================================================================================================================
;
; Entry:  HL = Y in H and X in L, IX = the return address, D' = the ink colour already doubled into both nibbles.
;
; Two pixels share a byte, so each routine has an even and an odd branch. The address is formed by shifting HL right
; once with carry set, which both halves the coordinates into an address and leaves the odd/even bit in carry. The
; original HL is restored afterwards with ADD HL,HL, plus an INC L for an odd pixel.
; ---------------------------------------------------------------------------------------------------------------------

; --- OVER 0: replace the pixel ---

M3DPOV0:    SCF
            RR H
            RR L                        ; HL = &8000 + Y/2 + X/2
            LD A,(HL)
            EXX
            JR C,M3DPOV0OD

            XOR D
            AND &0F                     ; Change only the low nibble, the even pixel
            XOR D
            EXX
            LD (HL),A
            ADD HL,HL                   ; Restore the coordinates
            JP (IX)

M3DPOV0OD:  XOR D
            AND &F0                     ; The odd pixel
            XOR D
            EXX
            LD (HL),A
            ADD HL,HL
            INC L
            JP (IX)


; --- OVER 1: exclusive-or the ink with what is there ---

M3DPOV1:    SCF
            RR H
            RR L
            EXX
            LD A,D
            EXX
            JR C,M3DPOV1OD

            AND &F0                     ; Leave the odd pixel alone
            XOR (HL)
            LD (HL),A
            ADD HL,HL
            JP (IX)

M3DPOV1OD:  AND &0F                     ; Leave the even pixel alone
            XOR (HL)
            LD (HL),A
            ADD HL,HL
            INC L

M3DPNUL:    JP (IX)                     ; Also the whole of the OVER 1 with INVERSE 1 routine


; --- OVER 2: or the ink with what is there ---

M3DPOV2:    SCF
            RR H
            RR L
            EXX
            LD A,D
            EXX
            JR C,M3DPOV2OD

            AND &F0
            OR (HL)
            LD (HL),A
            ADD HL,HL
            JP (IX)

M3DPOV2OD:  AND &0F
            OR (HL)
            LD (HL),A
            ADD HL,HL
            INC L
            JP (IX)


; --- OVER 3: and the ink with what is there ---

M3DPOV3:    SCF
            RR H
            RR L
            EXX
            LD A,D
            EXX
            JR C,M3DPOV3OD

            OR &0F                      ; Ones in the odd nibble leave it unchanged
            AND (HL)
            LD (HL),A
            ADD HL,HL
            JP (IX)

M3DPOV3OD:  OR &F0
            AND (HL)
            LD (HL),A
            ADD HL,HL
            INC L
            JP (IX)


; =====================================================================================================================
; SETIY -- choose the plot routine for the current mode and OVER setting
; =====================================================================================================================
;
; Exit:   IY = the routine; A = the colour to plot with in modes 2 and 3.
;         CY without IY set means thin-pixel mode 2, which has its own routine.
;
; The SETIYV vector allows the whole choice to be replaced.
; ---------------------------------------------------------------------------------------------------------------------

SETIY:      LD A,(SETIYV+1)
            AND A
            LD A,(MODE)
            JR NZ,STIY6                 ; A vector is installed

            LD IY,M0DPLOT
            AND A
            RET Z                       ; Internal mode 0

            LD IY,M1DPLOT
            DEC A
            RET Z                       ; Internal mode 1

            DEC A
            JR NZ,STIY1                 ; Internal mode 3

            LD A,(THFATT)               ; Internal mode 2: fat or thin?
            AND A
            SCF                          ; CY signals thin plotting
            RET Z

STIY1:      LD A,(GOVERT)
            LD IY,M3DPOV0
            AND A
            JR Z,STIY3                  ; OVER 0

            DEC A
            JR Z,STIY5                  ; OVER 1

            LD IY,M3DPOV2
            DEC A
            JR Z,STIY3                  ; OVER 2

            LD IY,M3DPOV3               ; OVER 3

STIY3:      LD A,(INVERT)
            AND A

STIY4:      LD A,(M23INKT)
            RET Z                       ; INVERSE 0: plot in ink

            LD A,(M23PAPT)              ; INVERSE 1: plot in paper
            RET

; --- OVER 1 ---

STIY5:      LD IY,M3DPOV1
            LD A,(INVERT)
            AND A
            JR Z,STIY4                  ; INVERSE 0: exclusive-or the ink onto the screen

            LD IY,M3DPNUL               ; INVERSE 1 with OVER 1 has no effect at all
            RET

; --- A vectored plot routine ---

STIY6:      PUSH HL
            LD HL,(SETIYV)
            CALL HLJUMP
            POP HL
            AND A                       ; NC: not thin pixels
            RET
