; =====================================================================================================================
; ENDPRINT.ASM -- Character rendering, screen addressing, and the fixed routines at the top of ROM0
; =====================================================================================================================
;
; The last stage of printing: given a character's 8-byte bitmap and a screen position, put pixels on the screen.
; Also the address arithmetic that every mode needs, string comparison, and -- at the very top of ROM0, at fixed
; addresses -- the paging primitives that both ROMs depend on.
;
; RENDERING
; ---------
; EPSUB is called from ROM1's print routine with:
;
;     DE = screen row and column
;     HL -> the character bitmap, 8 bytes, one per scan line, bit 7 leftmost
;     B  = the OVER mask:    &00 to replace, &FF to combine with what is there
;     C  = the INVERSE mask: &00 normal, &FF inverted
;
; It pages ROM1 out, maps the screen, and dispatches to one of four routines. Modes 0 and 1 write the bitmap byte
; directly and then set the attribute; modes 2 and 3 expand each nibble through CEXTAB into coloured pixels.
;
; Note the ordering: SELSCRN maps the screen into sections C and D *before* the bitmap is read, so the bitmap must
; live in ROM0 or the system page. That is the constraint documented in docs/font-rendering.md.
;
; THE FIXED ROUTINES
; ------------------
; From &3F8C to the end of ROM0 sits a block of small paging and unstacking routines, placed at fixed addresses by
; a DS directive so that external code -- and the other ROM -- can rely on them.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; EPSUB -- render one character
;
; Entry:  As described above. Called from ROM1.
; Exit:   Both port values restored.
; ---------------------------------------------------------------------------------------------------------------------

EPSUB:      CALL R1OSR                  ; ROM1 off; both port values stacked
            CALL SELSCRN                ; Map the screen being drawn on
            CALL EPSSR

POPOUT:     POP AF
            OUT (LRPORT),A

PPORT:      POP AF
            OUT (URPORT),A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; R1OSR -- page ROM1 out, stacking both port values for POPOUT to restore
;
; The return address is taken into IY so that the two PUSHes land beneath it.
; ---------------------------------------------------------------------------------------------------------------------

R1OSR:      POP IY
            IN A,(URPORT)
            PUSH AF
            IN A,(LRPORT)
            PUSH AF
            AND LMPRNOR1
            OUT (LRPORT),A
            JP (IY)


; ---------------------------------------------------------------------------------------------------------------------
; GTRLNN -- read the line number a header points at, used by RENUM
; ---------------------------------------------------------------------------------------------------------------------

GTRLNN:     EX DE,HL
            INC HL
            IN A,(URPORT)
            PUSH AF
            CALL FNDLINE
            LD   D,(HL)
            INC  HL
            LD   E,(HL)
            LD HL,(FIRST)
            JR PPORT


; ---------------------------------------------------------------------------------------------------------------------
; CWKSTK -- copy a string to workspace and stack its parameters
;
; Entry:  HL -> the text in common memory, BC = its length (1 to 16K).
; Exit:   DE = STKEND; the paging is unchanged.
; Notes:  Used by CHR$, STR$, HEX$ and the other functions that build a string result.
; ---------------------------------------------------------------------------------------------------------------------

CWKSTK:     CALL R1OSR
            PUSH HL
            CALL WKROOM                 ; DE = the room, BC unchanged
            POP HL
            PUSH DE
            PUSH BC
            LDIR
            POP BC
            POP DE
            CALL STKSTOREP
            EX DE,HL                    ; DE = STKEND
            JR POPOUT


; ---------------------------------------------------------------------------------------------------------------------
; EPSSR -- choose the renderer for the current mode
;
; Exit:   B' = the number of scan lines to draw, DE' = the bitmap pointer for modes 2 and 3.
; Notes:  Output is limited to 8 scans however tall the cell is -- see docs/font-rendering.md for what that means
;         for heights between 9 and 15.
; ---------------------------------------------------------------------------------------------------------------------

EPSSR:      LD A,(CSIZE)                ; The cell height
            PUSH HL
            EXX
            POP DE                      ; DE' = the bitmap, as modes 2 and 3 expect it
            CP CELLBYTES
            JR C,HPL2

            LD A,CELLBYTES

HPL2:       LD B,A
            EXX                         ; B' = scans to draw, never more than 8
            LD A,(MODE)
            CP MODE4COL
            JR Z,M2PRINT

            JP NC,M3PRINT

            DEC A
            JR Z,M1PRINT


; =====================================================================================================================
; M0PRINT -- internal mode 0 (user MODE 1): ZX layout, 8x8 attributes
; =====================================================================================================================
;
; Entry:  DE = row and column, HL = the bitmap, B = OVER mask, C = INVERSE mask.
; ---------------------------------------------------------------------------------------------------------------------

M0PRINT:    CALL M0DEADDR               ; DE = the screen address
            PUSH DE
            EXX

M0PRLP:     EXX                         ; The scan counter lives in B'
            LD A,(DE)                   ; What is on the screen
            AND B                       ; Kept only when OVER is on
            XOR (HL)                    ; Combine the bitmap
            XOR C                       ; ... and the INVERSE mask
            LD (DE),A
            INC HL
            INC D                       ; The next scan of a character cell is one page on
            LD A,D
            AND &07
            JR NZ,M0PRNT2               ; Still inside the cell

            EX DE,HL                    ; Crossed a cell boundary, so use the proper stepper
            CALL NXTDOWN1
            EX DE,HL

M0PRNT2:    EXX
            DJNZ M0PRLP

            POP HL
            CP A                        ; Z, which POATTR0 needs
            JP POATTR0


; =====================================================================================================================
; M1PRINT -- internal mode 1 (user MODE 2): linear layout, 8x1 attributes
; =====================================================================================================================

M1PRINT:    CALL M1DEADDR
            EXX

M1PRLP:     EXX
            LD A,(DE)                   ; What is on the screen
            AND B                       ; Zero when OVER is off, &FF when it is on
            XOR (HL)
            XOR C
            LD (DE),A
            INC HL
            LD A,E
            ADD A,SCANBYTESM01
            LD E,A                      ; Down one scan

            JR NC,M1PRNC

            INC D

M1PRNC:     EXX
            DJNZ M1PRLP

            EXX
            LD HL,&1F00                 ; The displacement from the last scan back to the top attribute
            ADD HL,DE
            CALL SETATTR                ; Apply ATTRT; HL is preserved and A returns the new attribute
            LD B,7                      ; This mode has one attribute per scan, so seven more to write
            LD DE,SCANBYTESM01

M1PRATTR:   ADD HL,DE
            LD (HL),A
            DJNZ M1PRATTR

            RET


; =====================================================================================================================
; M2PRINT -- internal mode 2 (user MODE 3): 512x192, four colours, two bits per pixel
; =====================================================================================================================
;
; A character is either 8 pixels wide, occupying two whole screen bytes, or 6 pixels wide, occupying one and a half.
; Both cases share the 6-pixel routine: the 8-pixel path rotates each bitmap byte one place right into a scratch
; buffer and then calls the even-column entry with the right-hand mask forced open, so both bytes are written whole.
;
; The upshot is that at width 6 only bits 6 to 1 of each bitmap byte reach the screen. See docs/font-rendering.md.
; ---------------------------------------------------------------------------------------------------------------------

M2PRINT:    CALL M2DEADDR               ; CY if 6-pixel cells; then Z for an even column, NZ for an odd one
            LD H,CEXTAB/256             ; The expansion table lies within one page
            LD A,C
            EXX
            LD C,A                      ; C' = the INVERSE mask
            JR C,PR80COL

; --- 8-pixel cells: pre-rotate the bitmap so the 6-pixel routine renders all eight bits ---

            LD HL,MEMVAL
            PUSH BC

P64AL:      LD A,(DE)
            RRCA
            LD (HL),A
            INC HL
            INC DE
            DJNZ P64AL

            POP BC
            LD DE,MEMVAL                ; The rotated copy
            EXX
            LD C,B                      ; Right-hand mask equals the left-hand one, so nothing is preserved
            JR PR80EVEN


; ---------------------------------------------------------------------------------------------------------------------
; PR80COL -- 6-pixel cells, 85 columns
;
; Entry:  NZ for an odd column, Z for an even one.
; ---------------------------------------------------------------------------------------------------------------------

PR80COL:    EXX
            LD A,B                      ; The OVER mask
            JR NZ,PR80ODD

            OR &0F
            LD C,A                      ; Even columns preserve the low nibble of the second byte

PR80EVEN:   EXX                         ; The left-hand mask for an even column is &00 or &FF

M2PREVLP:   LD A,(DE)                   ; A bitmap byte, tracked in the comments as 01234560
            XOR C
            INC DE
            EXX

            PUSH AF
            RRCA                        ; 01234560 -> 00123456
            RRCA                        ;          -> 60012345
            RRCA                        ;          -> 56001234
            AND &0F                     ; The upper nibble of the character: pixels 1 to 4
            LD L,A                      ; -> the coloured expansion of that nibble
            LD A,(DE)                   ; What is on the screen
            XOR (HL)
            AND B                       ; The left-hand OVER mask
            XOR (HL)
            LD (DE),A

            INC E                       ; The next screen byte
            POP AF                      ; 01234560
            RLCA                        ; 12345600
            AND &0F                     ; The lower nibble: pixels 5 and 6, plus two bits that will be masked away
            LD L,A
            LD A,(DE)
            XOR (HL)
            AND C                       ; The right-hand mask keeps the low nibble on an even column
            XOR (HL)
            LD (DE),A
            LD A,E
            ADD A,SCANBYTESM23-1
            LD E,A                      ; Down one scan and back one byte
            JR NC,M2PRNCE

            INC D

M2PRNCE:    EXX
            DJNZ M2PREVLP

            RET


; ---------------------------------------------------------------------------------------------------------------------
; PR80ODD -- an odd column, which begins in the middle of a screen byte
; ---------------------------------------------------------------------------------------------------------------------

PR80ODD:    OR &F0
            LD C,A                      ; Odd columns preserve the high nibble of the first byte
            EXX                         ; The right-hand mask for an odd column is &00 or &FF

M2PRODLP:   LD A,(DE)                   ; 01234560
            XOR C
            INC DE
            EXX

            PUSH AF
            RLCA                        ; 12345600
            RLCA                        ; 23456001
            RLCA                        ; 34560012
            AND &0F                     ; Only the low two bits survive the mask: pixels 1 and 2
            LD L,A
            LD A,(DE)
            XOR (HL)
            AND C                       ; Keep the high nibble
            XOR (HL)
            LD (DE),A

            INC E
            POP AF
            RRCA                        ; 00123456
            AND &0F                     ; Pixels 3 to 6
            LD L,A
            LD A,(DE)
            XOR (HL)
            AND B
            XOR (HL)
            LD (DE),A
            LD A,E
            ADD A,SCANBYTESM23-1
            LD E,A
            JR NC,M2PRNCO

            INC D

M2PRNCO:    EXX
            DJNZ M2PRODLP

            RET


; =====================================================================================================================
; M3PRINT -- internal mode 3 (user MODE 4): 256x192, sixteen colours, four bits per pixel
; =====================================================================================================================
;
; Each nibble of the bitmap expands to a word, so a cell is four bytes wide.
;
; Takes about 294 T-states per scan, against a possible 218 for an OVER 0 only routine using LDI.
; ---------------------------------------------------------------------------------------------------------------------

M3PRINT:    CALL M3DEADDR
            LD H,CEXTAB/256
            LD A,C

            EXX
            LD C,A                      ; C' = the INVERSE mask

M3PRLP:     LD A,(DE)
            XOR C
            INC DE
            EXX

            LD C,A                      ; Keep the byte for the second half
            RRA
            RRA
            RRA
            AND &1E                     ; The upper nibble, doubled: entries are words
            LD L,A
            LD A,(DE)
            AND B                       ; The OVER mask
            XOR (HL)
            LD (DE),A
            INC L                       ; The second byte of the expansion
            INC E

            LD A,(DE)
            AND B
            XOR (HL)
            LD (DE),A
            INC E

            LD A,C                      ; The bitmap byte again

            RLA
            AND &1E                     ; The lower nibble, doubled
            LD L,A
            LD A,(DE)
            AND B
            XOR (HL)
            LD (DE),A
            INC L
            INC E

            LD A,(DE)
            AND B
            XOR (HL)
            LD (DE),A
            LD A,E
            ADD A,SCANBYTESM23-3
            LD E,A                      ; Down one scan and back three bytes
            JR NC,M3PRNC

            INC D

M3PRNC:     EXX
            DJNZ M3PRLP

            RET


; =====================================================================================================================
; Print position and messages
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; POFETCH -- fetch the current print position
;
; Exit:   D = row, E = column, A = the right margin, CY for the printer.
; ---------------------------------------------------------------------------------------------------------------------

POFETCH:    LD A,(DEVICE)
            AND A                       ; NC, and test for zero
            JR Z,POF2                   ; The upper screen

            LD DE,(SPOSNL)
            DEC A
            JR Z,POF3                   ; The lower screen

            LD DE,(PRPOSN)              ; The printer
            LD A,(PRRHS)
            SCF
            RET

POF2:       LD DE,(SPOSNU)

POF3:       LD A,(WINDRHS)
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CCRESTOP / POSTFF -- resume normal output after collecting control code operands
; ---------------------------------------------------------------------------------------------------------------------

CCRESTOP:   CALL RESTOP
            RST &30
            DW CCRP2-&8000              ; ROM1 applies TAB, AT, PAPER and the rest

POSTFF:     RST &30
            DW PSTFF2-&8000             ; ROM1 prints the function name after an &FF prefix


; ---------------------------------------------------------------------------------------------------------------------
; UTMSG / POMSG -- print a message
;
; Entry:  UTMSG with A = a utility message number; POMSG (jump table entry &0115) with DE = the list as well.
; ---------------------------------------------------------------------------------------------------------------------

UTMSG:      LD DE,(UMSGS)

POMSG:      RST &30
            DW POMSPX-&8000


; =====================================================================================================================
; Screen address calculation
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; ANYDEADDR -- address of row D, column E, in whatever mode is current
;
; Exit:   DE = the address; CY when mode 2 is using 6-pixel cells, and then Z for an even column.
; ---------------------------------------------------------------------------------------------------------------------

ANYDEADDR:  LD A,(MODE)
            AND A
            JR Z,M0DEADDR

            DEC A
            JR Z,M1DEADDR

            DEC A
            JR Z,M2DEADDR


; ---------------------------------------------------------------------------------------------------------------------
; M3DEADDR -- internal mode 3: &8000 + row*height*&80 + column*4
; ---------------------------------------------------------------------------------------------------------------------

M3DEADDR:   CALL CLCPO                  ; D = the row in scan lines
            LD A,E
            ADD A,A
            ADD A,A
            ADD A,A                     ; column * 8, giving 0-248
            SCF
            RR D                        ; Halve the scan count into the address, setting bit 15
            RRA
            LD E,A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; M1DEADDR -- internal mode 1: &8000 + row*height*&20 + column
; ---------------------------------------------------------------------------------------------------------------------

M1DEADDR:   CALL CLCPO                  ; D holds the scan line, effectively 256 times the pixel row
            LD A,D
            RRCA                        ; 128 *
            RRCA                        ; 64 *
            RRCA                        ; 32 *
            LD D,A
            XOR E
            AND &E0                     ; Combine the low three bits of the scan with the column
            XOR E
            LD E,A
            LD A,D
            AND &1F                     ; The upper five bits of the scan line
            OR &80
            LD D,A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; M0DEADDR -- internal mode 0, whose layout needs the general pixel address routine
; ---------------------------------------------------------------------------------------------------------------------

M0DEADDR:   CALL CLCPO
            PUSH BC
            LD B,D
            LD A,E
            ADD A,A
            ADD A,A
            ADD A,A
            LD C,A                      ; BC = the pixel coordinates
            EX DE,HL
            CALL M0PIXAD
            EX DE,HL
            POP BC
            RET


; ---------------------------------------------------------------------------------------------------------------------
; M2DEADDR -- internal mode 2: &8000 + row*height*&80 + column*2, or *3/2 for 6-pixel cells
;
; Exit:   NC for 8-pixel cells; CY with Z or NZ for an even or odd 6-pixel column.
; ---------------------------------------------------------------------------------------------------------------------

M2DEADDR:   CALL CLCPO
            LD A,(FL6OR8)
            AND A
            LD A,E
            JR Z,M2DEADDR2              ; 6-pixel cells

            ADD A,A                     ; 0-126
            ADD A,A                     ; 0-252
            SCF
            RR D
            RRA                         ; NC: 8-pixel cells
            LD E,A
            RET

M2DEADDR2:  ADD A,A
            ADD A,E                     ; column * 3, giving 0-252
            SCF
            RR D
            RRA                         ; ... halved to 0-126, the offset from the left edge
            BIT 0,E                     ; Z if the original column was even
            LD E,A
            SCF                          ; CY: 6-pixel cells
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CLCPO -- convert a character row to a scan line, allowing for the lower screen
; ---------------------------------------------------------------------------------------------------------------------

CLCPO:      CALL CALCPIXD
            LD D,A
            LD A,(DEVICE)
            AND A
            RET Z                       ; The upper screen starts at scan zero

            LD A,(LSOFF)                ; The lower screen starts after the spare scans
            ADD A,D
            LD D,A
            RET


; =====================================================================================================================
; Pixel address calculation
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; ANYPIXAD -- address of pixel B,C (or B,HL with thin pixels) in any mode
;
; Exit:   HL = the address, A = the pixel offset within the byte; in mode 3, CY for an odd pixel.
; ---------------------------------------------------------------------------------------------------------------------

ANYPIXAD:   LD A,(THFATT)
            AND A
            JR NZ,NTTHINPIX

            LD C,L                      ; Keep the original low byte of X
            RR H
            RR L                        ; Thin pixels: halve X
            DB SKIP1CP

NTTHINPIX:  LD L,C

            LD H,B
            LD A,(MODE)
            AND A
            JR Z,M0PIXAD

            DEC A
            JR Z,M1PIXAD

            LD A,C
            JR M1PIXAD2                 ; Modes 2 and 3 share mode 1's final shift


; ---------------------------------------------------------------------------------------------------------------------
; M0PIXAD -- internal mode 0 pixel address for point C,B
;
; The ZX layout interleaves scan lines within a cell and cells within a third, so the address is assembled by
; shuffling bits rather than by multiplication.
;
; Exit:   HL = &8000-&97FF, A = the pixel offset. Only HL and A are altered.
; ---------------------------------------------------------------------------------------------------------------------

M0PIXAD:    LD L,B
            LD A,B
            OR A
            RRA
            RRA
            SCF
            RRA
            AND &9F
            XOR L
            AND &F8
            XOR L
            LD H,A
            LD A,C
            RLCA
            RLCA
            RLCA
            XOR L
            AND &C7
            XOR L
            RLCA
            RLCA
            LD L,A
            LD A,C
            AND &07
            RET


; ---------------------------------------------------------------------------------------------------------------------
; M1PIXAD -- internal mode 1 pixel address
;
; Entry:  L = X, H = Y.
; Exit:   HL = the address, B and A = the pixel offset 0-7.
; ---------------------------------------------------------------------------------------------------------------------

M1PIXAD:    LD A,L
            AND A
            RR H                        ; A zero is rotated in
            RR L
            AND A
            RR H
            RR L


M1PIXAD2:   AND &07
            LD B,A
            SCF
            RR H
            RR L                        ; HL = &8000 + Y/8 + X/8
            RET


; =====================================================================================================================
; Attributes
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; POATTR01 / POATTR0 / SETATTR -- set the attribute for a cell
;
; Entry:  POATTR01 with HL = the pattern address; SETATTR with HL already pointing at the attribute.
; Uses:   HL, BC, AF.
;
; MASKT selects which bits come from the existing attribute. PFLAGT bits 4 and 6 implement INK 9 and PAPER 9, which
; choose black or white for contrast against the other colour.
; ---------------------------------------------------------------------------------------------------------------------

POATTR01:   LD A,(MODE)
            AND A
            LD A,H
            SET 5,A                     ; Add &2000, the mode 1 attribute offset

; --- POATTR0: mode 0 enters here, with Z set so CTAA is called ---

POATTR0:    CALL Z,CTAA                 ; Mode 0 attributes are laid out by thirds

            LD H,A

SETATTR:    LD BC,(ATTRT)               ; C = the attribute, B = the mask
            LD A,(HL)
            XOR C
            AND B                       ; Set mask bits keep the existing attribute
            XOR C
            LD BC,(PFLAGT)
            BIT 4,C
            JR Z,POATTR1                ; Not INK 9

            OR &07                      ; Force white ink ...
            BIT 5,A
            JR Z,POATTR1                ; ... unless the paper is light, in which case

            XOR 7                       ; ... use black instead

POATTR1:    BIT 6,C
            JR Z,POATTR2                ; Not PAPER 9

            OR &38                      ; Force white paper ...
            BIT 2,A
            JR Z,POATTR2                ; ... unless the ink is light

            XOR &38                     ; ... in which case black

POATTR2:    LD (HL),A
            RET


; =====================================================================================================================
; STRCOMP -- compare the two strings on the calculator stack
; =====================================================================================================================
;
; Exit:   Z if they match, CY if S1 < S2, NZ and NC if S1 > S2. HL = the S1 pointer.
; Uses:   HL, BC, AF, HL', DE', BC', AF'. The paging is restored.
;
; Both strings may be in different pages, so the page is switched for every character. Only strings under 16K are
; handled.
; ---------------------------------------------------------------------------------------------------------------------

STRCOMP:    CALL R1OSR
            PUSH HL
            CALL UNSTKPRT               ; BC = S2 length, DE = its start, A = the port value to reach it
            PUSH DE
            PUSH AF
            PUSH BC
            CALL UNSTKPRT               ; The same for S1
            POP HL                      ; S2's length
            AND A
            SBC HL,BC
            ADD HL,BC
            JR NC,STRCOMP2              ; S1 is the shorter

            LD B,H
            LD C,L                      ; Compare over the shorter of the two

STRCOMP2:   LD L,A                      ; L = S1's port value
            EX AF,AF'                   ; Z if the lengths are equal, CY if S1 is longer
            LD A,B
            CP &40
            JP NC,STLERR                ; Over 16K

            POP AF
            LD H,A                      ; H = S2's port value
            PUSH BC
            LD C,URPORT

            EXX
            POP BC                      ; BC' = the shorter length
            POP HL                      ; HL' = S2's start
            JR SCOMPBG

SCOMPLP:    EXX
            OUT (C),L                   ; Map S1
            LD A,(DE)
            INC DE
            OUT (C),H                   ; Map S2

            EXX
            CP (HL)
            JR NZ,SCOMPEX               ; CY if S2 is greater; NZ and NC if S1 is

            INC HL
            DEC BC

SCOMPBG:    LD A,B
            OR C
            JR NZ,SCOMPLP

            EX AF,AF'                   ; Z if the lengths matched, so the strings are equal
            JR Z,SCOMPEX

            CCF                          ; Otherwise the longer string is the greater

SCOMPEX:    POP HL                      ; S1's pointer

SCOMPC:     EX AF,AF'
            POP AF
            OUT (LRPORT),A
            POP AF
            OUT (URPORT),A
            EX AF,AF'
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SBUFFET -- copy the string on the calculator stack into the buffer (jump table entry &012A)
;
; Exit:   BC and A = the length, DE = INSTBUF. The paging is unchanged.
; Notes:  SBFSR is the same but returns Z for an empty string instead of raising an error. SBFSR2 takes a different
;         length limit in A, allowing 511 bytes.
; ---------------------------------------------------------------------------------------------------------------------

SBUFFET:    CALL SBFSR
            RET NZ

INVARG:     RST &08
            DB ERR_BADARG

SBFSR:      LD A,&FF                    ; Limit of 255

SBFSR2:     EX AF,AF'
            CALL R1OSR
            CALL GETSTRING              ; A = page, DE = start, BC = length; the page is mapped
            EX AF,AF'
            ADD A,B                     ; Add &FF or &FE to the length's high byte
            JR C,INVARG                 ; Longer than the limit

            LD A,B
            OR C
            JR Z,SCOMPC                 ; Empty: return Z with the paging restored

            EX DE,HL
            LD DE,INSTBUF
            PUSH BC
            PUSH DE
            LDIR
            POP DE
            POP BC                      ; BC = the length, A = C, NC
            JR SCOMPC                   ; The OR C above left NZ, which SCOMPC preserves


; ---------------------------------------------------------------------------------------------------------------------
; UNSTKPRT -- unstack a string and compute the port value that maps it
;
; Exit:   A = the port value, DE = the start, BC = the length.
; ---------------------------------------------------------------------------------------------------------------------

UNSTKPRT:   CALL STKFETCH
            LD H,A
            IN A,(URPORT)
            XOR H
            AND &E0                     ; Keep the top three bits of the current port value
            XOR H
            RET


; ---------------------------------------------------------------------------------------------------------------------
; IDERR -- the input routine installed in output-only channels
; ---------------------------------------------------------------------------------------------------------------------

IDERR:      RST &08
            DB ERR_BADDEVICE


; =====================================================================================================================
; Memory availability tests
; =====================================================================================================================
;
; Every allocation passes through here. All raise "Out of memory" rather than returning a failure.
; ---------------------------------------------------------------------------------------------------------------------

; --- TSTRMBIG: check ABC bytes are available, preserving A and BC ---

TSTRMBIG:   PUSH AF
            PUSH BC
            CALL TSTRMABC
            POP BC
            POP AF
            RET

; --- TSTRMABC / TSTRMAHL: check ABC or AHL bytes. Exit NC with AHL = the new workspace end. ---

TSTRMABC:   LD H,B
            LD L,C

TSTRMAHL:   CALL AHLNORM
            LD B,H
            LD C,L                      ; ABC = the space as a 19-bit value
            DB SKIP1CP

; --- TESTROOM: check BC bytes. Exit NC, BC unchanged, AHL = the new workspace end, DE = the space left. ---

TESTROOM:   XOR A

            PUSH BC
            LD D,A                      ; DBC = the space wanted
            CALL WENORMAL               ; AHL = the current workspace end
            ADD HL,BC
            ADC A,D                     ; ... plus the space
            CALL PAGEFORM
            PUSH AF
            PUSH HL
            EX DE,HL
            LD C,A
            LD A,(RAMTOPP)
            LD HL,(RAMTOP)
            CALL SUBAHLCDE              ; AHL = what would be left
            JR C,OOMERR                 ; The new end would be above RAMTOP

            CALL AHLNORM
            EX DE,HL
            AND A
            JR Z,TRM2

            SET 7,D                     ; More than 64K free: report an arbitrarily large value

TRM2:       POP HL
            POP AF                      ; AHL = the new workspace end
            POP BC
            RET

OOMERR:     RST &08
            DB ERR_NOMEM


; ---------------------------------------------------------------------------------------------------------------------
; SCOPYWK -- copy BC bytes from (DE) to workspace, terminated by a carriage return
;
; The source may be anywhere and need not be mapped. Lengths above 255 are silently truncated; a length of zero
; will crash. ROM1 must be paged out on entry.
;
; Used by READ and VAL.
; ---------------------------------------------------------------------------------------------------------------------

; The original two-stage version, which moved the string a byte at a time switching pages for each, is retained
; below as a comment. The version in use stages through INSTBUF instead.
;
;SCOPYWK:   PUSH DE           ;SRC
; ...

SCOPYWK:    INC B
            DEC B
            JR Z,SCOPYWK2               ; 256 bytes or fewer

            LD BC,&FF                   ; Truncate

SCOPYWK2:   CALL R1OSR
            EX DE,HL                    ; HL = the source
            LD DE,INSTBUF
            PUSH DE
            PUSH BC
            LDIR                        ; Stage it in the system page
            POP BC
            PUSH BC
            CALL WKROOM
            POP BC
            POP HL
            PUSH DE
            LDIR                        ; ... then into workspace
            EX DE,HL
            POP DE
            DEC HL
            LD (HL),CC_ENTER            ; Terminate it
            POP AF
            OUT (LRPORT),A
            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LENGSR -- look a variable up and record what was found
;
; Used by the LENGTH function and by SAVE DATA, both of which want a variable's size without evaluating it.
; ---------------------------------------------------------------------------------------------------------------------

LENGSR:     CALL LOOKVARS               ; HL -> the value, or the length field of a string or array
            PUSH AF                     ; Found or not
            PUSH BC
            PUSH DE
            LD (MEMVAL),HL
            IN A,(URPORT)
            LD DE,MEMVAL+2
            LD (DE),A
            INC DE
            LD C,7
            CALL SCOPN2                 ; Copy seven bytes of length information, then restore the page
            POP DE
            POP BC                      ; The type
            POP AF
            RET

            DS &3F8C-$                  ; The routines below sit at fixed addresses


; =====================================================================================================================
; FIXED ROUTINES
; =====================================================================================================================
;
; Placed at the very top of ROM0, at addresses both ROMs can rely on.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; UNSTLEN -- unstack a number as a page and address
;
; Exit:   A = the page, HL = &8000-&BFFF. When the number is a length rather than an address, the caller clears
;         bit 7 of H to get a page plus 0000-&3FFF.
; Notes:  Raises ERR_IOOR if the value is negative or above &07FFFF.
; ---------------------------------------------------------------------------------------------------------------------

UNSTLEN:    DB CALC                     ; n
            DB STK16K                   ; n, 16384
            DB MOD                      ; n mod 16384
            DB RCL3                     ; ... and INT(n/16384), which MOD left in memory 3
            DB EXIT

            CALL GETBYTE
            CP &21
            JP NC,IOORERR               ; The page must be 0 to &20: 0 is ROM, 1 to &20 RAM

            PUSH AF
            CALL GETINT
            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; NPDPS -- resolve a POKE or DPOKE address, keeping the result inside the window
; ---------------------------------------------------------------------------------------------------------------------

NPDPS:      CALL PDPSUBR
            LD A,H
            CP &C0
            RET C

            JR INCURPAGE


; ---------------------------------------------------------------------------------------------------------------------
; SPSSR / SPSS / SELSCRN -- select the screen being drawn on
;
; SPSSR also pages ROM1 out; SPSS saves the current page first; SELSCRN simply maps it.
; ---------------------------------------------------------------------------------------------------------------------

SPSSR:      IN A,(LRPORT)
            LD (CLRP),A
            AND LMPRNOR1
            OUT (LRPORT),A

SPSS:       IN A,(URPORT)
            LD (CURP),A

SELSCRN:    LD A,(CUSCRNP)
            JR SELURPG


; ---------------------------------------------------------------------------------------------------------------------
; SREAD -- read one byte of screen memory, forcing the screen in and ROM1 out
; ---------------------------------------------------------------------------------------------------------------------

SREAD:      CALL SPSSR
            LD A,(HL)


; ---------------------------------------------------------------------------------------------------------------------
; RCURPR / RCURP -- restore the paging saved by SPSSR or SPSS
; ---------------------------------------------------------------------------------------------------------------------

RCURPR:     EX AF,AF'
            LD A,(CLRP)
            OUT (LRPORT),A
            DB SKIP1LDA

TRCURP:
RCURP:      EX AF,AF'

RCUR2:      LD A,(CURP)
            OUT (URPORT),A
            EX AF,AF'
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SETCHADP / R1OCHP / SELCHADP -- map the page CHAD points into
;
; SETCHADP first records a new page, R1OCHP also pages ROM1 out.
; ---------------------------------------------------------------------------------------------------------------------

SETCHADP:   LD (CHADP),A

R1OCHP:     IN A,(LRPORT)
            AND LMPRNOR1
            OUT (LRPORT),A

SELCHADP:   LD A,(CHADP)
            JR TSURPG


; ---------------------------------------------------------------------------------------------------------------------
; GETSTRING -- unstack a string and map its page
;
; Exit:   DE = the start in &8000-&BFFF, BC = the length.
; ---------------------------------------------------------------------------------------------------------------------

TGTSTR:
GETSTRING:  CALL STKFETCH


; ---------------------------------------------------------------------------------------------------------------------
; SELURPG / TSURPG -- select the page in A for sections C and D
;
; The top three bits of the current port value are preserved, so the video and MIDI bits are undisturbed.
; ---------------------------------------------------------------------------------------------------------------------

SELURPG:
TSURPG:     PUSH HL
            LD H,A
            IN A,(URPORT)
            XOR H
            AND &E0
            XOR H
            OUT (URPORT),A
            POP HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; INCURPDE / CHKHL / INCURPAGE / DECURPAGE -- step the page when a pointer leaves the window
;
; Uses A, and alters D or H.
; ---------------------------------------------------------------------------------------------------------------------

INCURPDE:   RES 6,D
            JR INCURCOM

; --- CHKHL: advance the page only if HL has crossed into section D ---

CHKHL:      BIT 6,H
            RET Z

INCURPAGE:  RES 6,H

INCURCOM:   IN A,(URPORT)
            INC A
            JR SELURPG

DECURPAGE:  SET 6,H
            IN A,(URPORT)
            DEC A
            JR SELURPG
