; =====================================================================================================================
; SCRSEL2.ASM -- GOTO/GOSUB, the keyword matcher, MODE and CSIZE, AUTO, SOUND, and the disk boot loader
; =====================================================================================================================
;
; A mixed file. The three parts worth knowing about:
;
; GETTOKEN
; --------
; The inner loop of the tokeniser. Given a candidate word copied into the edit line and the keyword table in
; text.asm, it finds which keyword the word matches. The table is one long run of characters with bit 7 set on the
; last character of each keyword, so no length bytes or pointers are needed -- the matcher walks it directly.
; The original comments record the cost: roughly 35 microseconds per five-letter keyword, or 5.3 milliseconds to
; sweep all 150-odd words.
;
; MODE AND CSIZE
; --------------
; MODPT2 changes screen mode and CSIZE changes the character cell size, but both end up in MDSR, which recomputes
; everything that depends on cell geometry: the window bounds, the graphics origin offset, and the leftover pixels
; between the upper and lower screens.
;
; Mode 2 is the awkward one. It is the only mode whose colours are two bits rather than four, so switching in or out
; of it has to convert the stored colour bytes between the two packed forms (M3TO2 and CVLSP, in misc32.asm) and
; swap the palette. It is also the only mode with a choice of 6- or 8-pixel character widths and of thin or fat
; pixels, both of which change the column count and hence the window bounds.
;
; THE BOOT LOADER
; ---------------
; BOOT finds a free 16K page, marks it for DOS, and reads track 4 sector 1 straight off the disk into it by talking
; to the WD1772 floppy controller directly -- there is no DOS resident yet to do it. If the first four bytes of what
; it reads spell "BOOT" it jumps into the loaded code at &8009. The original source marks this section as
; Bruce Gordon's code.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; GOTO / GOSUB -- and their ON forms
;
; Both share the parsing; only the handler address in HL differs. GOTO ON x;100,200,300 evaluates x and then
; evaluates its way along the list, discarding each value until it reaches the one selected.
; ---------------------------------------------------------------------------------------------------------------------

GOSUB:     LD HL,GOSUB2
           DB SKIP3IX                       ; The LD HL below becomes the operand of LD IX,nn

GOTO:      LD HL,GOTO2

GSUBTOC:   PUSH HL
           CP &DE                           ; ONTOK
           JR Z,GOTON

           CALL EXPT1NUM                    ; The line number
           POP HL
           CALL CHKEND

           JP (HL)

; --- The ON form ---

GOTON:     CALL SEXPT1NUM                   ; Skip the ON token, evaluate the selector
           PUSH AF
           CP ";"
           JP NZ,NONSENSE

           POP AF
           JR C,GOTON2                      ; Running, rather than syntax checking

           POP HL                           ; Discard the handler address

GOTONSL:   CALL SEXPT1NUM                   ; Syntax-check the whole list
           CP ","
           JR Z,GOTONSL

           RET

GOTON2:    CALL FPTOA                       ; The selector, in C; CY if it exceeded 255
           SBC A,A                          ; &FF if out of range, else 0
           JR Z,GOTONRL

           LD C,A                           ; Out of range, so use 255 and let the list run out

GOTONRL:   PUSH BC
           CALL SEXPT1NUM
           POP BC
           DEC C
           RET Z                            ; This is the selected line number, so return into GOTO or GOSUB

           CALL FDELETE                     ; Discard it and try the next
           RST &18
           CP ","
           JR Z,GOTONRL

           POP DE                           ; The list ran out, so discard the handler address and fall through to
           RET                              ; the next statement

GOSUB2:    CALL GETINT
           LD A,H
           INC A
           JP Z,IOORERR

           LD B,BSTKGOSUB
           PUSH HL
           CALL BSTKE                       ; Stack the return address
           POP HL
           JP GOTO3


; ---------------------------------------------------------------------------------------------------------------------
; GETTOKEN -- match a word against the keyword table (jump table entry &0142)
;
; Entry:  A = the number of keywords to check plus one; HL -> the keyword table; DE -> the candidate word, copied
;         into the edit line workspace.
; Exit:   A = the index of the matching keyword, counting from 1; Z if nothing matched.
;
; The table format is one keyword after another with no separators: the last character of each has bit 7 set. So the
; outer loop, GTTOK1/GTTOK2, simply scans forward for a byte with bit 7 set to find the next keyword's start.
;
; The comparison is `XOR (HL) : AND &DF`, which ignores bit 5 and so matches case-insensitively. Bit 7 is masked off
; separately at GTTOK4 so a match can succeed on the final, flagged character.
;
; Two refinements:
;   * A space in a table entry, as in "DEF FN", may be present or absent in the input.
;   * A keyword must not be followed by a letter, so PRINTX is a variable and not PRINT X. The exception is the
;     entries ending in "=", ">" or "$", where a following letter is legitimate -- CHR$A, or the <> operator.
; ---------------------------------------------------------------------------------------------------------------------

GETTOKEN:  LD C,A
           EX AF,AF'                        ; Keep the original count for the index calculation at the end

GTTOK1:    INC HL

GTTOK2:    BIT 7,(HL)
           JR Z,GTTOK1                      ; Scan to the end of the current keyword. 32 T states per pass.

           DEC C
           RET Z                            ; All keywords checked and none matched, so Z means failure

           INC HL
           LD A,(DE)
           XOR (HL)
           AND &DF                          ; Case-insensitive compare of the first letter
           JR NZ,GTTOK2                     ; About 80 T states per rejected keyword

           PUSH DE                          ; Remember the start of the candidate word
           INC DE

GTTOK3:    INC HL
           LD A,(HL)
           CP " "
           LD A,(DE)
           INC DE
           JR NZ,GTTOK4                     ; No space in the table entry here

           CP (HL)
           JR Z,GTTOK3                      ; The input has a space too, so accept it

           INC HL                           ; The input has no space, so skip the table's

GTTOK4:    XOR (HL)
           AND &DF
           JR Z,GTTOK3                      ; Still matching

           AND &7F                          ; Ignore the end-of-keyword flag bit
           JR NZ,GTTOK5                     ; A genuine mismatch

           LD A,(HL)
           RLCA
           JR C,GTTOK6                      ; The table entry ended here, so this is a candidate match

GTTOK5:    POP DE
           JR GTTOK2                        ; Try the next keyword

GTTOK6:    CP &7E                           ; After the RLCA, "=" is &7B, ">" is &7D and "$" is &49
           CCF                              ; NC for those three
           LD A,(DE)                        ; The input character following the matched word
           CALL C,ALDU                      ; Everything else must not be followed by a letter
           JR C,GTTOK5

           POP HL
           EX AF,AF'
           SUB C                            ; 1 if the first keyword matched, 2 for the second, and so on
           RET


; =====================================================================================================================
; MODPT2 -- change screen mode
; =====================================================================================================================
;
; Entry:  A = the internal mode, 0 to 3.
;
; The mode bits live in the video page register alongside the display page number, so the new mode has to be merged
; into CUSCRNP rather than simply written. The hardware register is only updated if the screen being changed is the
; one currently displayed.
; ---------------------------------------------------------------------------------------------------------------------

MODPT2:    AND &03
           LD HL,MODE
           LD C,(HL)
           PUSH BC                          ; The previous mode
           LD (HL),A
           CP 2
           PUSH AF
           CALL NC,SUET                     ; Modes 2 and 3 need the pixel expansion table

           POP AF
           PUSH AF
           RRCA
           RRCA
           RRCA                             ; The mode bits move to bits 6 and 5
           LD C,A
           LD HL,CUSCRNP
           LD A,(HL)                        ; Keep the current video page ...
           XOR C
           AND &9F                          ; ... and take only bits 6 and 5 from C
           XOR C
           LD (HL),A
           IN A,(VIDPORT)
           XOR (HL)
           AND &1F
           JR NZ,MDL2                       ; A different screen is being displayed, so leave the hardware alone

           LD A,(HL)
           OUT (VIDPORT),A

MDL2:      POP AF                           ; The new mode
           POP BC                           ; C = the previous mode
           PUSH AF
           CP 1
           SBC A,A                          ; &FF for mode 0, 0 otherwise
           LD HL,&0809                      ; Cell width 8, height 9, for modes 1 to 3
           ADD A,L
           LD L,A                           ; Mode 0 uses height 8, so the cells align with the attribute grid
           POP AF

           CALL MDSR

           LD A,(TEMPB1)                    ; The old mode
           JR Z,M2ST                        ; Mode 2 is being set

           CP 2
           JR NZ,ECLS                       ; Neither the old nor the new mode is 2, so nothing to convert

; --- Leaving mode 2: restore the four-bit colour forms that were saved on the way in ---

           LD HL,(M3PAPP)
           LD (M23PAPP),HL
           LD HL,(M3LSC)
           LD (M23LSC),HL
           LD C,A                           ; Non-zero: the X coordinate must be halved
           JR M2ST2

; --- Entering mode 2 ---

M2ST:      CP 2
           JR Z,ECLS                        ; Already in mode 2

           LD HL,(M23PAPP)
           LD (M3PAPP),HL                   ; Save the four-bit forms for the way back out
           CALL M3TO2
           PUSH AF
           LD L,H
           CALL M3TO2
           LD H,L
           POP AF
           LD L,A
           LD (M23PAPP),HL                  ; Converting both bytes prevents striped inks in mode 2
           LD HL,(M23LSC)
           LD (M3LSC),HL
           CALL CVLSP                       ; Convert the lower-screen colours too
           LD C,0                           ; Zero: the X coordinate must be doubled

M2ST2:     LD A,(THFATP)                    ; Crossing the mode 2 boundary changes whether pixels are thin, which
           AND A                            ; changes what an X coordinate means
           LD A,C
           CALL Z,SETFP                     ; Rescale XCOORD and XRG

           CALL PALSW                       ; Swap the palette

ECLS:      CALL R1OFFJP
           DW MCLS                          ; Page ROM1 out and jump to MCLS


; ---------------------------------------------------------------------------------------------------------------------
; MDSR -- recompute everything that depends on the character cell size
;
; Entry:  A = the new mode with Z set if it is mode 2, C = the previous mode, H = the cell width and L the height.
; Exit:   Z if the new mode is 2.
;
; Called from MODPT2 when the mode changes, and from WIDTH when CSIZE changes.
;
; The screen is 192 pixels tall, so the number of text lines is 192 divided by the cell height; the remainder
; becomes LSOFF, the gap between the bottom of the upper screen and the two-line lower screen. The graphics origin
; sits two cell heights up from the bottom of the screen, which is ORGOFF.
;
; The column count depends on the mode and, in mode 2, on the character width: 32 columns normally, 64 in mode 2
; with 8-pixel characters, and 85 in mode 2 with 6-pixel characters.
; ---------------------------------------------------------------------------------------------------------------------

MDSR:      PUSH AF
           LD A,C                           ; The previous mode; the same as the new one when called from CSIZE
           LD (TEMPB1),A
           LD (CSIZE),HL                    ; H = width, L = height
           LD A,192
           LD E,&FC                         ; -4, so E counts up to the bottom line number

MDSL:      INC E
           SUB L
           JR NC,MDSL                       ; Divide the screen height by the cell height

           ADD A,L                          ; The leftover pixels
           LD (LSOFF),A                     ; They form the gap above the lower screen
           LD A,L
           ADD A,A
           LD (ORGOFF),A                    ; The graphics origin is two cell heights up from the bottom
           LD D,31                          ; 32 columns in modes 0, 1 and 3
           POP AF
           PUSH AF
           JR NZ,MDSR3

           LD D,63                          ; Mode 2 with 8-pixel characters: 64 columns
           LD A,(FL6OR8)
           AND A
           JR NZ,MDSR3

           LD D,84                          ; Mode 2 with 6-pixel characters: 85 columns
           LD A,6
           LD (CSIZE+1),A

MDSR3:     LD HL,UWRHS                      ; The eight window bytes are contiguous, so one walk sets them all
           LD (HL),D                        ; Upper window right
           INC HL
           XOR A
           LD (HL),A                        ; Upper window left
           INC HL
           LD (HL),A                        ; Upper window top
           INC HL
           LD (HL),E                        ; Upper window bottom
           INC HL
           LD (HL),D                        ; Lower window right
           LD (WINDMAX),DE                  ; The limits WINDOW validates against
           INC HL
           LD (HL),A                        ; Lower window left
           INC HL
           INC E
           LD (HL),E                        ; Lower window top
           INC HL
           INC E
           LD (HL),E                        ; Lower window bottom
           POP AF
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FATPIX -- FATPIX 0 or 1, choosing thin or fat pixels in mode 2
;
; Mode 2 is 512 pixels wide but BASIC's coordinate system is nominally 256 wide. FATPIX 1 doubles each pixel so the
; coordinates match; FATPIX 0 gives access to all 512. Changing the setting rescales the current X coordinate and
; the X range variable so that the graphics position does not move on screen.
; ---------------------------------------------------------------------------------------------------------------------

FATPIX:    CALL SYNTAX6

           LD DE,(2*256)+ERR_IOOR
           CALL LIMBYTE

           LD HL,THFATP
           CP (HL)
           RET Z                            ; No change

           LD (HL),A
           LD A,(MODE)
           CP 2
           RET NZ                           ; Only mode 2 has thin pixels, so nothing to rescale

           LD A,(HL)

SETFP:     LD HL,(XCOORD)
           AND A
           JR Z,FPX2                        ; Changing from fat to thin, so double the coordinate

           SRL H
           RR L                             ; Thin to fat, so halve it
           DB SKIP1LDA                      ; LD A,n swallows the ADD HL,HL below

FPX2:      ADD HL,HL

           LD (XCOORD),HL                   ; A is now 0 for the doubling path, &29 for the halving path

           PUSH AF
           CALL ADDRNV
           POP AF
           LD DE,87
           ADD HL,DE                        ; Point at XRG within the numeric variable
           CALL R1OFFJP
           DW CGXRG                         ; XRG lives in a page ROM1 covers, so page it out first

PXIOOR:    RST &08
           DB ERR_IOOR


; ---------------------------------------------------------------------------------------------------------------------
; WIDTH -- the CSIZE command: CSIZE width, height
;
; Width may be 6 or 8, but 6 only takes effect in mode 2. Height may be 6 to 32; 16 or more gives double-height
; characters. Heights below 6 are rejected as nonsensical, though 6 and 7 are allowed since a suitable character set
; could use them.
; ---------------------------------------------------------------------------------------------------------------------

WIDTH:     CALL SYNTAX8

           CALL GETBYTE                     ; Height
           PUSH BC
           CALL GETBYTE                     ; Width
           CP 6
           JR Z,CSZ2

           CP 8
           JR NZ,PXIOOR

CSZ2:      POP DE                           ; E = height
           LD D,A                           ; D = width
           LD A,E
           CP 6
           JR C,PXIOOR

           CP 33
           JR NC,PXIOOR

           EX DE,HL
           LD A,H
           SUB 6
           LD (FL6OR8),A                    ; Zero for width 6, non-zero otherwise
           LD A,(MODE)
           LD C,A                           ; MDSR wants the "previous mode", which here is the current one
           CP 2
           PUSH AF
           CALL MDSR
           POP AF
           RET NZ                           ; Only mode 2 needs the expansion table rebuilding, since only there
                                            ; does the width choice change the output routine


; ---------------------------------------------------------------------------------------------------------------------
; SUET -- build the pixel expansion table
;
; Entry:  A = the mode, with Z set for mode 2.
;
; Character bitmaps are one bit per pixel, but modes 2 and 3 need two and four bits per pixel respectively. EXTAB
; is a lookup that expands a nibble of bitmap into the packed pixel bytes: one byte per entry in mode 2, two in
; mode 3.
; ---------------------------------------------------------------------------------------------------------------------

SUET:      LD HL,EXTAB
           LD C,0
           JR Z,DBTABCLP                    ; Mode 2 doubles each bit; mode 3 quadruples it

QUADTCLP:  LD A,C
           CALL QUADBITS
           LD (HL),D
           INC HL
           LD (HL),E
           INC HL
           INC C
           LD A,C
           CP 16
           JR C,QUADTCLP                    ; All sixteen nibble values

           RET

DBTABCLP:  LD A,C
           CALL DBBITS
           LD (HL),E
           INC HL
           INC C
           LD A,C
           CP 16
           JR C,DBTABCLP

           RET


; ---------------------------------------------------------------------------------------------------------------------
; QUADBITS / DBBITS -- replicate each bit of A into DE
;
; DBBITS turns each bit into two, so &0F becomes &00FF; QUADBITS applies it twice, turning each bit into four.
; The loop rotates A right, shifts the bit into DE, then rotates A back and right again so the same bit is used
; twice.
; ---------------------------------------------------------------------------------------------------------------------

QUADBITS:  CALL DBBITS
           LD A,E

DBBITS:    LD B,8

DBBITSLP:  RRCA
           RR D
           RR E                             ; One copy of the bit
           RLCA
           RRCA                             ; Put the bit back and take it again
           RR D
           RR E                             ; The second copy
           DJNZ DBBITSLP

           RET


; ---------------------------------------------------------------------------------------------------------------------
; AUTO -- AUTO line, step: automatic line numbering while typing
;
; With no parameters it continues from the current line plus ten. The step must be no greater than the starting
; line, since EPPC is set to line minus step and would otherwise underflow.
;
; AUTO does not return to the caller: it discards the next-statement and error-handler addresses and re-enters the
; main loop at AULL, which is the listing-and-edit entry rather than the normal one.
; ---------------------------------------------------------------------------------------------------------------------

AUTO:      CALL CRCOLON
           JR Z,AO1                         ; Bare AUTO: both defaults

           CALL GIR2                        ; The starting line, in HL and BC
           LD BC,10                         ; The default step
           CP ","
           JR NZ,AO2

           PUSH HL
           CALL GIR                         ; The step
           POP HL
           JR AO2

AO1:       LD HL,(EPPC)
           LD BC,10
           ADD HL,BC

AO2:       CALL RUNFLG
           RET NC                           ; Syntax checking. CHKEND cannot be used here because BC is needed.

           XOR A
           SBC HL,BC
           CCF
           ADC A,A                          ; 0 if the step exceeds the line, 1 otherwise
           LD (AUTOFLG),A
           RET Z                            ; The step was too big, so AUTO is simply switched off

           LD (EPPC),HL                     ; Start at line minus step, so the first line offered is the one asked for
           LD (AUTOSTEP),BC
           POP DE                           ; Discard the next-statement address
           POP DE                           ; And the error handler
           LD BC,AULL
           JP R1XJP                          ; Page ROM1 out and re-enter the main loop


; ---------------------------------------------------------------------------------------------------------------------
; SOUND -- SOUND register, value; register, value; ...
;
; Collects the register and value pairs into INSTBUF, terminates the list with &FF, and then writes them all to the
; sound chip. Register numbers are limited to 0 to 31, and the buffer holds at most 127 pairs.
;
; The chip has two ports one apart: the address register and the data register. B is decremented and incremented to
; move between them, since the port number is in BC for the OUT (C),r form.
; ---------------------------------------------------------------------------------------------------------------------

SOUND:     LD DE,INSTBUF

SNDLP:     PUSH DE
           CALL EXPT2NUMS
           POP DE
           JR NC,SND1                       ; Syntax checking, so nothing is stored

           PUSH DE
           CALL GETBYTE                     ; The value
           PUSH AF
           LD DE,(32*256)+ERR_IOOR
           CALL LIMBYTE                     ; The register, 0 to 31
           POP BC
           POP DE
           LD (DE),A
           INC E
           LD A,B
           LD (DE),A
           INC E
           JP Z,NRFLERR                     ; The buffer wrapped, so more than 127 pairs were given

SND1:      RST &18
           CP ";"
           JR NZ,SND2

           RST &20
           JR SNDLP

SND2:      CALL CHKEND

           LD A,&FF
           LD (DE),A                        ; Terminate the list
           LD BC,256+SNDPORT                ; B = 1, so BC addresses the address register
           LD HL,INSTBUF                    ; There is always at least one pair
           JR SND3

SNDOPL:    OUT (C),D                        ; Select the register
           DEC B                            ; Move to the data register
           OUT (C),E
           INC B

SND3:      LD D,(HL)
           INC L
           LD E,(HL)
           INC L
           CP D                             ; A is still &FF, the terminator
           JR NZ,SNDOPL

           RET


; =====================================================================================================================
; BOOT -- load and start DOS from disk
; =====================================================================================================================
;
; BOOT with no parameter, or BOOT 0, only auto-loads if DOS is already resident. BOOT 1 forces a full boot or reboot
; from disk, with no auto-load afterwards.
;
; The loader talks to the WD1772 controller directly, since there is no DOS yet to ask. It finds a free 16K page,
; steps the head to track 4, reads sector 1 into &8000, and checks that the first four bytes read "BOOT" before
; jumping to &8009.
; ---------------------------------------------------------------------------------------------------------------------

BOOT:      CALL SYNTAX3

           CALL GETBYTE
           AND A
           JR NZ,BOOTEX                     ; BOOT 1: force a boot, and do not auto-load

           LD A,(DOSFLG)
           AND A
           JR Z,BOOTNR                      ; No DOS resident, so a real boot is needed

           RST &08
           DB ALHK                          ; DOS is there already, so just auto-load
           RET

BOOTNR:    CALL BOOTEX

           RST &08
           DB BTHK                          ; Auto-load, but do not complain if there is nothing to load
           RET


; --- BOOTEX: find a page for DOS and read the boot sector into it ---

BOOTEX:    LD HL,ALLOCT+&1F                 ; Search the page allocation table from the top down

FDPL:      LD A,(HL)
           AND A
           JR Z,GDP                         ; A free page

           CP &60
           JR Z,GDP                         ; A page already marked for DOS, so this is a reboot

           DEC L
           JR NZ,FDPL

           RST &08
           DB ERR_NOMEM                     ; No page available for DOS

GDP:       LD A,L
           CALL SELURPG                     ; Page it in at &8000

; --- Reset the controller and find the index hole, to confirm a disk is present and spinning ---

           LD C,&D0                         ; Force interrupt: resets the chip
           CALL SDCX                        ; Exits with B = 0
           CALL REST

           LD H,&FE                         ; A long timeout: HL counts down from &FE00 ...
           LD E,H                           ; ... twice
           LD B,6                           ; Six index hole transitions

BOOT2:     DEC HL
           LD A,H
           OR L
           JR NZ,BOOT3

           INC E
           JR NZ,BOOT3

           RST &08
           DB ERR_NODISC

BOOT3:     IN A,(COMM)
           LD D,A
           XOR C
           AND 2
           JR Z,BOOT2                       ; Wait for the index hole signal to change state

           LD C,D
           DJNZ BOOT2

           CALL REST
           LD DE,&0401                      ; Track 4, sector 1


; ---------------------------------------------------------------------------------------------------------------------
; RSAD -- read one sector into &8000
;
; Entry:  D = the track, E = the sector.
;
; Steps the head towards the wanted track one track at a time, comparing against the controller's track register,
; then issues a read and transfers the data with INI in a polling loop. Errors are retried; the head is restored
; after five failures and the read abandoned after ten.
; ---------------------------------------------------------------------------------------------------------------------

RSAD:      XOR A
           EX AF,AF'                        ; A' counts the retries

RSA1:      LD A,E
           OUT (SECT),A

RSA2:      CALL BUSY
           IN A,(TRCK)
           CP D
           JR Z,RSA4                        ; On the right track

           LD C,STPOUT
           JR NC,RSA3

           LD C,STPIN

RSA3:      CALL SADC
           JR RSA2

RSA4:      DI
           LD C,DRSEC
           CALL SADC
           LD HL,&8000
           LD BC,DTRQ
           DB SKIP1CP                       ; CP n absorbs the ED of the INI below; the remaining A2 executes
                                            ; harmlessly as AND D, so the first poll happens before any transfer

RSA5:      INI

RSA6:      IN A,(COMM)
           BIT 1,A
           JR NZ,RSA5                       ; Data request: transfer another byte

           RRCA
           JR C,RSA6                        ; Still busy

           EI

; --- Check the controller's error bits ---

           AND &0E
           JR Z,BTNOE

           EX AF,AF'
           INC A
           CP 5
           PUSH AF
           CALL Z,REST                      ; After five failures, restore the head and try again
           POP AF
           CP 10
           JP NC,TERROR                     ; After ten, give up

           EX AF,AF'
           JR RSA1

; --- Verify the signature and start DOS ---

BTNOE:     LD DE,&80FF                      ; One before the loaded data, since the loop increments first
           LD HL,BTWD                       ; The four-character signature
           LD B,4

BTCK:      INC DE
           LD A,(DE)
           XOR (HL)
           AND &5F                          ; Ignore bits 7 and 5, so the comparison is case-insensitive
           JR Z,BTLY

           RST &08
           DB ERR_NODOS

BTLY:      INC HL
           DJNZ BTCK

           JP &8009                         ; DOS initialisation entry point


; ---------------------------------------------------------------------------------------------------------------------
; SADC / SDCX / REST / BUSY -- WD1772 controller primitives
;
;   SADC  wait for the controller, then issue the command in C
;   SDCX  issue the command without waiting first
;   REST  restore the head to track 0
;   BUSY  spin until the controller's busy bit clears, checking BREAK as it goes
;
; The DJNZ after each command is the settling delay the controller needs before its status is meaningful.
; ---------------------------------------------------------------------------------------------------------------------

SADC:      CALL BUSY

SDCX:      LD A,C
           OUT (COMM),A
           LD B,0

SDC1:      DJNZ SDC1

           RET

REST:      LD C,DRES
           CALL SADC

BUSY:      IN A,(COMM)
           RRCA
           RET NC

           CALL BRKCR
           JR BUSY
