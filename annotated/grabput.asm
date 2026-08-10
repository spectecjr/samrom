; =====================================================================================================================
; GRABPUT.ASM -- Block graphics, and the universal cross-page block move
; =====================================================================================================================
;
; GRAB captures a rectangle of screen into a string; PUT writes one back. Both require internal mode 2 or 3, whose
; screens are linear and free of attributes.
;
; THE BLOCK FORMAT
; ----------------
; A grabbed block is an ordinary BASIC string, so it can be assigned, saved, or passed to a procedure. Its first
; three bytes are a header:
;
;     +0   &00      a control code marking this as a PUT block
;     +1   width    in bytes
;     +2   length   in scan lines
;     +3.. the pixel data, one row of "width" bytes per scan line
;
; PUT validates the header before using it, so an arbitrary string cannot be mistaken for a block.
;
; PUT MODES
; ---------
; The current OVER and INVERSE settings choose one of five inner loops, all of the same length so that the
; dispatcher can index them arithmetically. A sixth handles a mask string, which lets an irregularly shaped sprite
; be drawn without disturbing the background around it.
;
; FARLDIR
; -------
; The second half of this file is the ROM's general memory copy. Because source and destination may lie in different
; 16K pages -- and either may cross a page boundary mid-transfer -- it moves the data in 256-byte instalments through
; a buffer in the system page, which is the only page always mapped.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; GRAB -- GRAB a$,x,y,width,length
;
; Entry:  CHAD at the variable name.
; Exit:   The captured block is assigned to the named string.
; ---------------------------------------------------------------------------------------------------------------------

GRAB:       CALL SYNTAX1                ; Assess the destination variable
            LD HL,FLAGS
            BIT 6,(HL)
            JR NZ,GNONSH                ; FFLAGNUM: a numeric destination makes no sense

            RST &18
            CP ","

GNONSH:     JP NZ,NONSENSE

            CALL SEXPT4NUMS             ; x, y, width, length
            CALL CHKEND

            CALL CHKMD23                ; Internal mode 2 or 3 only
            LD DE,(SCREENHEIGHT*256)+ERR_IOOR
            CALL LIMDB                  ; Length 1-192, returned decremented to 0-191
            INC A
            PUSH AF                     ; The length
            CALL GETINT                 ; The width in pixels
            DEC BC                      ; 0 becomes &FFFF, 256 becomes 255
            LD A,B
            AND A
            JP NZ,IOORERR               ; Widths outside 1-256 are rejected

            INC BC                      ; Back to 1-256
            INC BC                      ; Round up to a whole number of bytes: an even width gains a bit that the
                                        ; shift discards, an odd one is rounded up
            SRL B                       ; B becomes zero
            RR C                        ; C = the width in bytes, 1-128
            POP DE                      ; D = the length
            LD E,C                      ; E = the width
            PUSH DE
            CALL GTFIDFCDS              ; Unstack x and y into C and B, checked and forced to fat coordinates
            POP DE
            CALL JGRAB
            CALL STKSTOS                ; Stack the result as a string
            JP ASSIGN


; ---------------------------------------------------------------------------------------------------------------------
; JGRAB -- capture a block (jump table entry &0136)
;
; Entry:  D = length in scan lines, E = width in bytes, B = y, C = x
; Exit:   DE -> the block in the current screen page, BC = its total length including the three header bytes
; ---------------------------------------------------------------------------------------------------------------------

JGRAB:      CALL SPSS                   ; Save the paging and map the current screen at &8000
            LD HL,RSBUFF-3              ; Build the header just below the data buffer
            LD (HL),0                   ; The control code
            INC HL
            LD (HL),E                   ; Width
            INC HL
            LD (HL),D                   ; Length
            CALL GPVARS                 ; A' = width, D and B' = length, HL = screen address, BC = 128
            LD A,E
            RST &30
            DW CRTBFI                   ; Build a run of E LDI instructions in the code buffer.
                                        ; Note the full address: bit 15 set makes this a call, not a jump.
            LD A,E
            EX AF,AF'                   ; RST &30 corrupted A', so restore it
            CALL RSSTBLK                ; Copy the rows out, using the same routine the roll and scroll use
            LD DE,RSBUFF-3              ; -> the control code
            LD BC,(TEMPW2)              ; The data length, as recorded by RSSTBLK
            INC BC
            INC BC
            INC BC                      ; ... plus the three header bytes
            IN A,(251)
            JP RCURP                    ; Restore the paging


; ---------------------------------------------------------------------------------------------------------------------
; GPTRUNC -- shorten a block that would fall off the bottom of the screen
;
; Entry:  D = the block length, B = the y coordinate
; Exit:   D reduced so that the block ends at the last scan line.
; ---------------------------------------------------------------------------------------------------------------------

GPTRUNC:    LD A,D
            DEC A
            ADD A,B                     ; The last row the block would occupy
            JR C,GPTRUNC2               ; Wrapped past 255, so it certainly overhangs

            SUB SCREENHEIGHT
            RET C                       ; It fits

            SUB &40                     ; Compensate for the ADD below

GPTRUNC2:   ADD A,&40                   ; Rows overhanging, biased by &40
            CPL                         ; 0-&3F becomes &FF-&C0, a negative count
            ADD A,D
            LD D,A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GPVARS -- set up the registers common to GRAB and PUT
;
; Entry:  E = width in bytes, D = length, B = y, C = x
; Exit:   A' and E = width, D and B' = length, HL = the screen address, BC = 128
; ---------------------------------------------------------------------------------------------------------------------

GPVARS:     LD A,E
            EX AF,AF'                   ; A' = width
            CALL GPTRUNC                ; Clip the length if necessary
            LD A,D

            EXX
            LD B,A                      ; B' = length
            EXX

            LD H,B                      ; y
            LD L,C                      ; x
            SCF
            RR H
            RR L                        ; addr = &8000 + y*128 + x/2
            LD BC,SCANBYTESM23
            RET


; =====================================================================================================================
; PUT -- PUT x,y,a$ [,mask$]
; =====================================================================================================================
;
; Honours OVER 0 to 3 and INVERSE. With a mask string, only the pixels where the mask has one bits are altered.
; ---------------------------------------------------------------------------------------------------------------------

PUT:        CALL SYNTAX9                ; Colour items, then x and y
            CALL EXPTCSTR               ; The block string
            CP ","
            JR NZ,PUTL1

            CALL SSYNTAXA               ; A mask string as well

            LD HL,RSBUFF+&0FFD          ; &F000: the second half of the staging area
            CALL PSCHKMHL               ; Validate it and copy it there
            LD A,5                      ; Inner loop 5: the masked one
            JR PUTLC

PUTL1:      CALL CHKEND

            XOR A                       ; No mask

PUTLC:      PUSH AF
            LD HL,RSBUFF-3              ; &E000: the first half
            CALL PSCHKMHL               ; Validate the block and copy it there
            CALL GTFIDFCDS              ; B = y, C = x
            CALL SPSS
            POP AF
            AND A
            JR Z,PUTL2                  ; Not masked; NC

            EXX
            LD HL,RSBUFF+&1000          ; HL' -> the mask data, past its own three-byte header
            EXX

            LD HL,(RSBUFF-2)            ; Width and length of the block
            LD DE,(RSBUFF+&0FFE)        ; ... and of the mask
            SBC HL,DE
            JR Z,PUT05                  ; They agree, and A is still 5

            RST &08
            DB ERR_PUTMASK

PUTL2:      LD DE,(INVERT)              ; E = INVERSE mask, D = graphics OVER mode
            LD A,E
            OR D
            LD A,4
            JR Z,PUT05                  ; OVER 0 with INVERSE 0 uses the fast LDIR loop

            LD A,D
            AND 3                       ; Otherwise select by OVER mode

PUT05:      LD HL,RSBUFF-2              ; -> the width byte
            JR PUT06


; ---------------------------------------------------------------------------------------------------------------------
; JPUT -- write a block (jump table entry &0133)
;
; Entry:  A = mode 0-5, B = y, C = x, HL -> the width and length bytes, HL' -> mask data if mode 5
; Exit:   The block is drawn, clipped at the bottom of the screen if necessary.
; ---------------------------------------------------------------------------------------------------------------------

JPUT:       LD E,A
            CALL SPSS
            LD A,E

PUT06:      ADD A,A                     ; Each inner loop is exactly 10 bytes long
            LD E,A
            ADD A,A
            ADD A,A                     ; A = mode * 8
            ADD A,E                     ; ... + mode * 2 = mode * 10
            LD E,A
            LD D,0
            LD IY,PUTSRTAB
            ADD IY,DE                   ; IY -> the chosen loop

            LD E,(HL)                   ; Width in bytes, from the block header
            INC HL
            LD D,(HL)                   ; Length
            INC HL
            PUSH HL                     ; -> the pixel data
            CALL GPVARS
            LD A,C
            SUB E                       ; Scan length minus block width: the step to the next row
            POP DE                      ; The pixel data
            LD IX,PUTRET                ; The inner loops "return" through IX, avoiding a CALL per row

            EXX
            LD E,A                      ; E' = the row step
            LD A,(INVERT)
            EX AF,AF'                   ; A' = the INVERSE mask
            LD C,A                      ; C' = the block width

PUTSCLP:    EXX

; At this point:
;   HL = screen pointer, DE = data source, A = width
;   B' = rows remaining, C' = width, E' = step to the next row, A' = INVERSE mask
;   HL' may point at the mask data
;   B is used as the byte counter and C as the INVERSE mask

            LD B,A
            EX AF,AF'
            LD C,A                      ; The INVERSE mask
            JP (IY)                     ; Enter the chosen loop, which returns through IX with B = 0

PUTRET:     LD A,C
            EX AF,AF'                   ; Preserve the INVERSE mask in A'

            EXX
            LD A,E                      ; The row step
            EXX

            LD C,A
            ADD HL,BC                   ; Move down one row

            EXX
            LD A,C                      ; The width again
            DJNZ PUTSCLP

            JP RCURP


; =====================================================================================================================
; PUTSRTAB -- the inner loops
; =====================================================================================================================
;
; Entry:  DE -> the data, HL -> the screen, B = bytes to do, C = the INVERSE mask, IX = the return address.
; Exit:   B = 0.
;
; Each is padded to exactly 10 bytes so that PUT06 can index them by multiplying the mode by ten.
; ---------------------------------------------------------------------------------------------------------------------

PUTSRTAB:

OVER0LP:    LD A,(DE)                   ; Mode 0: replace
            XOR C
            LD (HL),A
            INC DE
            INC HL
            DJNZ OVER0LP
            JP (IX)
            NOP                         ; Pad to ten bytes

OVER1LP:    LD A,(DE)                   ; Mode 1: XOR
            XOR C
            XOR (HL)
            LD (HL),A
            INC DE
            INC HL
            DJNZ OVER1LP
            JP (IX)

OVER2LP:    LD A,(DE)                   ; Mode 2: OR
            XOR C
            OR (HL)
            LD (HL),A
            INC DE
            INC HL
            DJNZ OVER2LP
            JP (IX)

OVER3LP:    LD A,(DE)                   ; Mode 3: AND
            XOR C
            AND (HL)
            LD (HL),A
            INC DE
            INC HL
            DJNZ OVER3LP                ; About 64T per byte; INC L instead of INC HL would give 56T
            JP (IX)

NOINVER:    EX DE,HL                    ; Mode 4: OVER 0 with INVERSE 0, so a straight copy
            LD C,B
            LD B,0
            LDIR                        ; About 32T per byte
            EX DE,HL
            JP (IX)
            NOP


; ---------------------------------------------------------------------------------------------------------------------
; PMASKLP -- mode 5: masked write
;
; One bits in the mask select pixels from the block; zero bits leave the screen alone.
;
; A mask is built like this: FILL INK 0 the background, GRAB a$, FILL INK 15 the background, PUT OVER 1 a$ -- which
; leaves the background as ones and the figure as zeros. Then GRAB a$, PUT INVERSE 1 a$, GRAB a$ inverts it, giving
; zeros for the background and ones for the figure.
; ---------------------------------------------------------------------------------------------------------------------

PMASKLP:    LD A,(DE)
            XOR C                       ; The INVERSE mask
            XOR (HL)                    ; Difference between the block and the screen
            EXX
            AND (HL)                    ; ... restricted to where the mask allows
            INC HL
            EXX
            INC DE
            XOR (HL)                    ; Apply that difference to the screen
            LD (HL),A
            INC HL
            DJNZ PMASKLP                ; About 96T per byte
            JP (IX)

PUTBLKERR:  RST &08
            DB ERR_BADPUTBLK


; ---------------------------------------------------------------------------------------------------------------------
; PSCHKMHL -- validate a PUT string and stage it in screen memory
;
; Entry:  HL = where to put it, in the spare part of the screen page.
; Exit:   The string is copied there; errors if it is empty or does not begin with CHR$ 0.
; ---------------------------------------------------------------------------------------------------------------------

PSCHKMHL:   LD (TEMPW1),HL              ; The destination
            CALL CHKMD23
         ;  CALL SPSS
            CALL GETSTRING              ; DE -> the string, BC = its length, its page mapped
            LD A,B
            OR C
            JR Z,PUTBLKERR              ; An empty string cannot be a block

            LD A,(DE)
            AND A
            JR NZ,PUTBLKERR             ; The first byte must be the control code

         ;  CALL SCRMOV
         ;  JP RCURP


; ---------------------------------------------------------------------------------------------------------------------
; SCRMOV -- copy BC bytes from (DE) to (TEMPW1) in the spare screen memory
;
; Uses:   HL, DE, BC, AF, AF'
; ---------------------------------------------------------------------------------------------------------------------

SCRMOV:     LD HL,(TEMPW1)
            ADD HL,BC
            JR C,PUTBLKERR              ; It would not fit in the space available

            CALL SPLITBC
            LD A,(CUSCRNP)
            LD C,A                      ; Destination page
            IN A,(251)                  ; Source page
            SCF
            JR SFLDIR


; =====================================================================================================================
; FARLDIR / FARLDDR -- the general block move
; =====================================================================================================================
;
; Copies (PAGCOUNT * 16K) + MODCOUNT bytes from page A, address HL to page C, address DE. Source and destination may
; be in any pages and either may cross a 16K boundary during the transfer.
;
; Because only one arbitrary page can be mapped into section C at a time, the data travels in 256-byte instalments
; through BUFF256 in the system page, which is always mapped.
;
; Entry:  A/HL = source page and address, C/DE = destination page and address, PAGCOUNT and MODCOUNT set
;         (SPLITBC will set those from a byte count in BC).
; Exit:   TEMPW1 and TEMPB2 point just past the destination, DE just past the source, and the paging is restored.
;         MODCOUNT must not exceed &3FFF; either count may be zero.
; ---------------------------------------------------------------------------------------------------------------------

FARLDDR:    BIT 6,H
            JR NZ,FLD3                  ; The source is already in section D

            DEC A                       ; Bring it there, so a descending copy has room to work
            SET 6,H

FLD3:       BIT 6,D
            JR NZ,FLD4

            DEC C                       ; The same for the destination
            SET 6,D

FLD4:       AND A                       ; NC selects the descending copy
            DB SKIP1LDB                 ; Skip the SCF below

; --- FARLDIR: the ascending entry ---

FARLDIR:    SCF

            EX DE,HL
            LD (TEMPW1),HL              ; The destination address

; --- SFLDIR: entered with C and (TEMPW1) as the destination, and A/DE as the source ---

SFLDIR:     LD H,A
            LD A,C
            LD (TEMPB2),A

; --- FARLDIR2: entered with H/DE as the source, when some of the data has already been moved. Used by CONCAT. ---

FARLDIR2:   EX AF,AF'                   ; CY' selects ascending
            CALL R1OSR                  ; ROM1 off; both port values saved
            LD A,H
            CALL TSURPG                 ; Map the source
            LD A,(PAGCOUNT)
            AND A
            JR Z,FLDIE                  ; No whole pages to move

FARLDILP:   PUSH AF
            LD BC,&4000
            CALL STRMOV1
            POP AF
            DEC A
            JR NZ,FARLDILP              ; One 16K instalment per page

FLDIE:      LD BC,(MODCOUNT)
            CALL STRMOV
            JP POPOUT                   ; Restore both port values


; ---------------------------------------------------------------------------------------------------------------------
; STRMOV -- move BC bytes via the system page
;
; Entry:  DE -> the source in the mapped page, (TEMPW1) and (TEMPB2) the destination, CY' set for an ascending copy.
; Exit:   DE just past the source with its page mapped, TEMPW1 and TEMPB2 just past the destination, HL = 0.
;         Handles counts from 0 to &FFFF.
; ---------------------------------------------------------------------------------------------------------------------

STRMOV:     LD A,B
            OR C
            RET Z

STRMOV1:    LD HL,(INSLV)
            INC H
            DEC H
            JP NZ,HLJUMP                ; A vector hook, unused by the ROM itself

            LD H,B
            LD L,C                      ; HL = bytes remaining

STRMOVL:    LD BC,&0100                 ; One instalment
            LD A,H
            AND A
            JR NZ,STRMOV2               ; At least 256 bytes left

            LD B,H                      ; Fewer: this is the last instalment
            LD C,L

STRMOV2:    PUSH HL                     ; Bytes remaining
            PUSH BC
            EX DE,HL
            LD DE,BUFF256
            EX AF,AF'
            JR C,DLDIR                  ; Ascending

; --- Descending: fill the buffer from the top down ---

            EX AF,AF'
            DEC E                       ; -> the far end of the buffer
            LDDR
            POP BC
            BIT 6,H
            CALL Z,DECURPAGE            ; The source dropped into section C, so step the page back
            JR STRM32

DLDIR:      EX AF,AF'
            LDIR                        ; Source into the buffer
            POP BC
            CALL CHKHL                  ; Keep the source pointer in the window

STRM32:     PUSH HL                     ; Source pointer
            IN A,(251)
            PUSH AF                     ; Source page
            LD A,(TEMPB2)
            CALL TSURPG                 ; Map the destination
            LD DE,(TEMPW1)
            PUSH BC                     ; Byte count
            EX AF,AF'
            LD HL,BUFF256
            JR C,STRM34

            EX AF,AF'
            DEC L                       ; Descending: work from the far end again
            LDDR
            EX DE,HL
            BIT 6,H
            CALL Z,DECURPAGE

            JR STRM38

STRM34:     EX AF,AF'
            LDIR                        ; Buffer into the destination
            EX DE,HL
            CALL CHKHL

STRM38:     IN A,(URPORT)
            LD (TEMPB2),A               ; The destination page may have advanced

STRMOV4:    LD (TEMPW1),HL              ; ... and so may its address
            EX DE,HL
            POP BC                      ; Byte count
            POP AF
            OUT (251),A                 ; Back to the source page
            POP DE                      ; Source pointer
            POP HL                      ; Bytes remaining
            AND A
            SBC HL,BC
            JR NZ,STRMOVL

            RET
