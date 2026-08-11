; =====================================================================================================================
; MISC32.ASM -- sound, colour items, BORDER, WINDOW and assorted small commands
; =====================================================================================================================
;
; SOUND
; -----
; The SAM has no sound chip on the base machine, so BEEP generates tone by toggling bit 4 of the keyboard port in a
; carefully cycle-counted loop. The loop's timing is the whole point of the code: every path through it is padded so
; that both halves of a cycle take the same number of T states, and the loop entry address is adjusted by two bytes
; to add or remove eight T states of resolution.
;
; ZAP, POW, BOOM and ZOOM are all sound effects built from repeated BEEPP2 calls with a sweeping period, sharing the
; PAF/SAD/SELP driver.
;
; COLOUR ITEMS
; ------------
; PRCOITEM2 handles INK, PAPER, FLASH, BRIGHT, INVERSE and OVER wherever they appear -- as statements, or embedded in
; a PRINT or PLOT list. Each one narrows to a mask in C and a value already shifted into position in B, and then
; COCHNG merges those bits into the temporary attribute byte.
;
; Three separate representations have to be kept in step:
;
;     ATTRT      the mode 0/1 attribute byte: FLASH, BRIGHT, PAPER, INK
;     MASKT      which bits of ATTRT are transparent, for INK 16/17 and PAPER 16/17
;     PFLAGT     the non-attribute flags: OVER, INVERSE, and the "contrast" forms of INK/PAPER 17
;     M23INKT    the mode 2/3 ink byte, holding the colour replicated across all the pixels in a byte
;     M23PAPT    likewise for paper
;
; The replication is what the RLCA sequences around CINKPAP0 are doing: mode 3 packs two four-bit pixels per byte, so
; a colour is stored as two copies of its nibble; mode 2 packs four two-bit pixels, so it becomes four copies of a
; two-bit field.
;
; =====================================================================================================================


; =====================================================================================================================
; BEEP -- BEEP duration, pitch
; =====================================================================================================================
;
; The pitch is a semitone offset from middle C, so the frequency is 55 * 2^((n+27)/12) Hz -- 27 semitones below
; middle C is the A at 55 Hz that anchors the scale.
; ---------------------------------------------------------------------------------------------------------------------

BEEP:      CALL SYNTAX8

           DB CALC                          ; length, note
           DB ONELIT
           DB 27
           DB ADDN                          ; length, note+27
           DB ONELIT
           DB 12
           DB DIVN                          ; length, (note+27)/12
           DB POWR2                         ; length, 2^((note+27)/12)
           DB ONELIT
           DB 55
           DB MULT                          ; length, frequency
           DB DUP
           DB SWOP13                        ; frequency, frequency, length
           DB RESTACK                       ; Force the full floating form so the exponents can be tested
           DB EXIT

           LD A,(HL)                        ; The exponent of the length
           CP &85
           JR C,BEEP2                       ; Durations up to 16 seconds are allowed

           RST &08
           DB ERR_NOTETOOLNG

BEEP2:     LD BC,-5
           ADD HL,BC
           LD A,(HL)                        ; The exponent of the frequency
           CP &84
           JR C,INVNOTE

           CP &8F
           JR C,BEEP3                       ; Frequencies from 8 Hz to 16 kHz are allowed

INVNOTE:   RST &08
           DB ERR_BADNOTE

BEEP3:     DB CALC                          ; frequency, frequency, length
           DB MULT                          ; frequency, cycles
           DB SWOP
           DB FIVELIT
           DB &93,&37
           DB &1B,0,0                       ; 375000, the number of 8T units in one half-cycle at 1 Hz
           DB SWOP
           DB DIVN                          ; cycles, 8T units per half-cycle
           DB ONELIT
           DB 15
           DB SUBN                          ; The loop itself costs 120 T states even with a count of zero, so
                                            ; fifteen 8T units are taken off the period
           DB EXIT

           CALL GETINT
           PUSH BC
           CALL GETINT
           EX DE,HL                         ; DE = the cycle count
           POP HL                           ; HL = the half-cycle period in 8T units
           OR B
           RET Z                            ; No cycles to do

           DEC DE                           ; A count of zero in the loop means one cycle


; ---------------------------------------------------------------------------------------------------------------------
; BEEPP2 -- the tone generator
;
; Entry:  DE = the number of cycles minus one, HL = the half-cycle period, with H counting 2048T units and L
;         counting 8T units.
;
; Even with HL = 0 the loop takes 118 T states, which contention on the OUT rounds up to 120.
;
; The period has 8T resolution but the inner delay loop only steps in 16T, so the odd bit of L is handled by choosing
; between two entry points into the loop: BEEPLP, which begins with two LD B,B instructions costing 8 T states, and
; BEEPLP+2, which skips them. IX holds whichever was chosen.
;
; The two halves of each cycle must take identical time, so BEEPR4 exists purely to burn the 4 T states that the
; other path spends on its DE test.
; ---------------------------------------------------------------------------------------------------------------------

BEEPP2:    DI
           PUSH BC
           LD BC,BEEPLP
           SRL L                            ; L now counts 16T units
           JR C,BEEPER2                     ; It was odd, so use the loop that is 8 T states longer

           INC BC
           INC BC

BEEPER2:   PUSH BC
           POP IX                           ; IX = the chosen loop entry
           LD A,(BORDCOL)                   ; Bit layout: SOFF, THRO MIDI, intensity, 0, MIC, green, red, blue
           OR &18                           ; Speaker bit high (on), MIC bit high (off)
           JR BPLENT                        ; Enter the loop at the toggle, pulsing the speaker off first

BEEPLP:    LD B,B                           ; Two do-nothing instructions, 8 T states, skipped by the short entry
           LD B,B

; --- The short loop entry point, used when the period is an even number of 16T units ---

           INC C
           INC B                            ; Guard against a count of zero, which would loop 256 times

BPTMLP:    DEC B
           JR NZ,BPTMLP                     ; 16 T states per pass

           LD B,127                         ; The outer pass costs 32 T states, so 126*16+32 = 2048
           DEC C
           JP NZ,BPTMLP

BPLENT:    XOR &10                          ; Flip the speaker bit
           OUT (&FE),A
           LD B,A                           ; Keep the port value
           LD C,H
           BIT 4,A
           JR NZ,BEEPR4                     ; That was the first half of the cycle

           LD A,D
           OR E
           JR Z,BEEPR5                      ; All cycles done

           DEC DE

BEEPR3:    LD A,B
           LD B,L
           JP (IX)

BEEPR4:    LD A,B                           ; A 4 T state delay, matching the DE test on the other path
           JR BEEPR3

BEEPR5:    POP BC
           EI
           RET


; ---------------------------------------------------------------------------------------------------------------------
; ZAP, BOOM, ZOOM, POW -- the four canned sound effects
;
; All four sweep the tone period across a series of BEEPP2 calls. ZAP does six short bursts at a fixed period; BOOM
; and ZOOM sweep it upwards and downwards respectively; POW plays a period sequence read from a table at DE.
;
; The alternate register set holds the sweep state -- B' the remaining steps, BC the period increment -- so the main
; set is free for BEEPP2.
; ---------------------------------------------------------------------------------------------------------------------

ZAP:       CALL CHKEND

           LD B,6

ZPL:       PUSH BC
           LD BC,2
           LD E,1
           LD A,30
           CALL PAF
           DI
           POP BC
           DJNZ ZPL

           EI
           RET


BOOM:      CALL CHKEND

           LD E,1
           LD BC,12                         ; A rising period, so a falling pitch
           JR ZPC

ZOOM:      CALL CHKEND

           LD E,6
           LD BC,65533                      ; -3: a falling period, so a rising pitch

ZPC:       LD A,78

PAF:       LD L,255
           PUSH AF                          ; The step count, collected by the POP BC below

           LD H,0
           LD D,H

SAD:       EXX
           POP BC                           ; B' = the step count

SELP:      EXX
           PUSH DE
           PUSH HL
           CALL BEEPP2
           DI
           POP HL
           POP DE
           ADD HL,BC                        ; Sweep the period
           EXX
           DJNZ SELP

           EXX
           EI
           RET

POW:       CALL CHKEND
           EX DE,HL                         ; DE -> the period table
           LD B,0                           ; 256 entries

PWLP:      LD A,(DE)
           LD L,A
           LD H,0
           INC DE
           PUSH DE
           LD DE,1                          ; One cycle at each period
           CALL BEEPP2
           DI
           POP DE
           DJNZ PWLP

           EI
           RET


; ---------------------------------------------------------------------------------------------------------------------
; BGRAPHICS -- BGRAPHICS 0 or 1, choosing what character codes 128 to 143 draw
;
; BGRAPHICS 1 uses the built-in quarter-cell block graphics; BGRAPHICS 0 uses the user-defined graphics instead.
; ---------------------------------------------------------------------------------------------------------------------

BGRAPHICS: CALL SYNTAX6

           LD DE,(2*256)+ERR_IOOR           ; Values must be below 2
           CALL LIMBYTE

           DEC A
           LD (BGFLG),A                     ; 0 for blocks, &FF for UDGs
           RET


; ---------------------------------------------------------------------------------------------------------------------
; KEY -- KEY position, value: redefine one entry of the keyboard translation table
;
; Positions run 1 to 280; position 0 exists but is unused.
; ---------------------------------------------------------------------------------------------------------------------

KEY:       CALL SYNTAX8

           CALL GETBYTE                     ; The value
           PUSH AF
           CALL GETINT                      ; The position
           POP AF
           LD HL,-281
           ADD HL,BC
           JP C,IOORERR

           LD HL,(KBTAB)
           ADD HL,BC
           LD (HL),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; SLDEVICE -- DEVICE, selecting where SAVE and LOAD go
;
; Accepts a letter and an optional number: DEVICE T:, DEVICE N:, DEVICE D2, or DEVICE T45 to set the tape speed.
; The letter and number are stored in PSLD for the file routines to consult.
;
; Any letter is accepted. Only N (network) and T (tape) are special-cased here; everything else defaults its number
; to 1 and is left for the DOS to interpret, which uses D for a disk drive.
;
; Defaults: a network station number of 0, the standard tape speed, and drive 1 for a disk.
;
; Note:   The original comment gives the disk examples as "DEVICE M:" and "DEVICE M2". No SAM DOS uses M -- both
;         SAMDOS 2 and MasterDOS take D, as in DEVICE D2 and the "D1:name" file-name prefix.
; ---------------------------------------------------------------------------------------------------------------------

SLDEVICE:  CALL GETALPH
           AND &DF                          ; Force upper case
           PUSH AF
           RST &20
           CALL FETCHNUM                    ; The number, or zero if absent
           POP DE
           CALL CHKEND

           PUSH DE
           CALL GETBYTE                     ; The number, in C
           POP AF                           ; The letter
           CP "N"
           JR Z,DEVI3                       ; Network: use the number as given, defaulting to station 0

           CP "T"
           JR NZ,DEVI2

           INC C
           DEC C
           JR NZ,DEVI3

           LD C,TSPEED                      ; Tape with no number: the default speed

DEVI2:     INC C
           DEC C
           JR NZ,DEVI3

           INC C                            ; Disk with no number: drive 1

DEVI3:     LD HL,PSLD
           LD (HL),A                        ; The device letter
           INC HL
           LD (HL),C                        ; Drive, station or speed
           RET


; ---------------------------------------------------------------------------------------------------------------------
; PAUSE -- PAUSE n, waiting n frames or until a key is pressed
;
; PAUSE 0 waits for a key with no time limit. The frame count is decremented only on genuine frame interrupts, which
; is what the LASTSTAT test distinguishes -- line interrupts and MIDI interrupts also wake the HALT.
; ---------------------------------------------------------------------------------------------------------------------

PAUSE:     CALL SYNTAX3

           CALL GETINT
           LD E,7                           ; BLITZ record code for PAUSE
           CALL GRAREC                      ; The parameter is recorded modulo 256, in C

PAU1:      CALL KBFLUSH                     ; Returns HL -> the flags byte
           HALT
           CALL BRKCR                       ; BREAK stops the program
           LD A,(LASTSTAT)                  ; The status port as read by the last interrupt
           AND 8
           JR NZ,PAU1                       ; Not a frame interrupt, so it does not count

           LD A,B
           OR C
           JR Z,PAU2                        ; PAUSE 0 never counts down

           DEC BC
           LD A,B
           OR C
           RET Z

PAU2:      BIT 5,(HL)
           JR Z,PAU1                        ; No key pressed yet

           RES 5,(HL)                       ; Consume the keypress
           RET


; =====================================================================================================================
; PRCOITEM2 -- apply one colour item
; =====================================================================================================================
;
; Entry:  A = the item's token minus &10, so 0 is INK, 1 PAPER, 2 FLASH, 3 BRIGHT, 4 INVERSE and 5 OVER;
;         D = the parameter value.
;
; Each branch sets C to the mask of bits it owns and B to the parameter already shifted into those bit positions,
; then COCHNG merges them.
; ---------------------------------------------------------------------------------------------------------------------

PRCOITEM2:    LD B,D                        ; B doubles as the parameter
              SUB 16
              JP Z,COINK

              DEC A
              JP Z,COPAPER

              DEC A
              JR Z,COFLASH

              DEC A
              JR Z,COBRIGHT

              DEC A
              JR NZ,COOVER

COINVERSE:    LD C,4                        ; Bit 2 of PFLAGT
              LD A,D
              CP 2
              JR NC,INVCOLERR               ; Only INVERSE 0 and 1 exist

              DEC A
              CPL                           ; 0 or 1 becomes &00 or &FF
              LD (INVERT),A
              LD A,D
              RLCA
              RLCA
              LD B,A                        ; The parameter bit moved to bit 2
              JR COINOVC

COOVER:       LD C,1                        ; Bit 0 of PFLAGT
              LD A,D
              CP 4
              JR NC,INVCOLERR               ; OVER 0 to 3

              LD E,4                        ; BLITZ record code for OVER
              PUSH BC
              LD C,A
              PUSH AF
              CALL GRAREC
              POP AF
              POP BC
              LD (GOVERT),A                 ; Graphics OVER accepts all four values
              CP 2
              RET NC                        ; OVER 2 and 3 are graphics-only, so PFLAGT is left alone

              LD (OVERT),A
              LD A,B

COINOVC:      LD HL,PFLAGT
              JP COCHNG


; --- BRIGHT. In modes 2 and 3 brightness is not a separate attribute bit but part of the colour number, so
;     BRIGHT 1 has to add 8 to both the ink and the paper colour and BRIGHT 0 has to take it away. ---

COBRIGHT:     LD C,&40                      ; Bit 6 of ATTRT
              LD A,(MODE)
              CP 2
              LD A,D
              JR Z,COBRI2                   ; Mode 2 has only four inks, so leave the colours alone

              CP 2
              JR NC,COBRI2                  ; BRIGHT 8, the transparent form

              AND A
              LD A,(M23PAPT)
              LD E,A
              LD A,(M23INKT)
              JR Z,COBRI1                   ; BRIGHT 0

              OR &88                        ; Add 8 to the ink, in both replicated nibbles
              PUSH AF
              LD A,E
              OR &88                        ; And to the paper
              JR COBRI15

COBRI1:       AND &77                       ; Take 8 away from both
              PUSH AF
              LD A,E
              AND &77

COBRI15:      LD (M23PAPT),A
              POP AF
              LD (M23INKT),A
              LD A,D

COBRI2:       RRCA                           ; One rotation here, one at COBRFLC, puts the parameter in bit 6
              JR COBRFLC

COFLASH:      LD C,&80                      ; Bit 7 of ATTRT
              LD A,D

COBRFLC:      RRCA                          ; The parameter reaches bit 7 for FLASH, bit 6 for BRIGHT
              LD B,A
              LD A,D
              CP 16
              JR NZ,COBFC2                  ; 0 and 1 are the normal values; 8 and 16 mean transparent

              RRCA                          ; 16 becomes 8
              RRC B                         ; Keep B in step

COBFC2:       CP 8
              JR Z,COFBOK

              CP 2
              JR C,COFBOK

INVCOLERR:    RST &08
              DB ERR_BADCOLOUR

COFBOK:       LD HL,ATTRT
              LD A,B
              CALL COCHNG                   ; Merge into ATTRT; COCHNG leaves HL pointing at MASKT
              LD A,B
              RRCA
              RRCA
              RRCA                          ; The transparent form moves to the matching bit of MASKT
              JR COCHNG


; --- INK and PAPER ---

COINK:        LD C,7                        ; Bits 0 to 2 of ATTRT
              JR CINKPAPC

COPAPER:      LD C,&38                      ; Bits 3 to 5 of ATTRT
              LD A,D
              RLCA
              RLCA
              RLCA
              LD B,A                        ; The parameter shifted into the paper field

CINKPAPC:     LD HL,ATTRT
              LD A,D
              CP 16
              JR NC,CINKPAP0                ; 16 and 17 are the transparent and contrasting forms

              RLCA
              RLCA
              RLCA
              RLCA
              OR D                          ; Two copies of the colour nibble: the mode 3 byte form
              LD E,A
              RLCA
              JR NC,CONFBRI                 ; Colours below 8 need no brightness

              SET 6,(HL)                    ; Colours 8 to 15 force BRIGHT 1 in the mode 0/1 attribute

CONFBRI:      LD A,(MODE)
              CP 2
              LD A,E
              JR NZ,COIPM3

              RLCA
              RLCA                          ; Bits 5,4 and 1,0 move to 7,6 and 4,3
              XOR E
              AND &CC                       ; Keep bits 7, 6, 4 and 3 from the rotated copy
              XOR E                         ; Four copies of the two-bit colour: the mode 2 byte form
              RLCA                          ; Correct for the bit swap the rotation introduced

COIPM3:       BIT 0,C                       ; Bit 0 of the mask is set only for INK
              JR Z,COPAPM3

              LD (M23INKT),A
              LD E,5                        ; BLITZ record code for PEN
              PUSH BC
              LD C,A
              CALL GRAREC
              POP BC
              JR CINKPAP2

COPAPM3:      LD (M23PAPT),A
              JR CINKPAP2

; --- INK 16/17 and PAPER 16/17: transparent, and contrasting ---

CINKPAP0:     CP 18
              JR NC,INVCOLERR

              LD   A,(HL)                   ; The current ATTRT
              JR   Z,CINKPAP1               ; 16 is transparent: ATTRT is untouched, only MASKT changes

              OR   C                        ; Force the field white
              CPL                           ; Then black, flipping the other bits with it
              AND  &24                      ; Test the middle bit of each of the two colour fields
              JR Z,CINKPAP2                 ; The existing colour is light, so black contrasts

              LD   A,C                      ; It is dark, so white contrasts

CINKPAP1:     LD B,A

CINKPAP2:     LD A,B
              CALL COCHNG                   ; Merge into ATTRT
              LD A,15                       ; Below both 16 and 17, so the comparison sets carry for either
              CALL COCHNGP                  ; Merge into MASKT
              RLCA
              RLCA
              AND &50
              LD C,A
              LD A,16                       ; Below 17 only, so carry is set only for the contrasting form,
                                            ; which is then merged into PFLAGT

; ---------------------------------------------------------------------------------------------------------------------
; COCHNG / COCHNGP -- merge B's bits into (HL) under the mask in C
;
; COCHNGP first turns "is D greater than A" into an all-ones or all-zeros byte, so a threshold test can be used
; directly as the value to merge.
;
; Entry:  A = the value (or the threshold, at COCHNGP), C = the mask, HL -> the byte.
; Exit:   A = C, HL advanced by one to the next byte in the ATTRT/MASKT/PFLAGT run.
; ---------------------------------------------------------------------------------------------------------------------

COCHNGP:      CP D
              SBC A,A                       ; &FF if D is greater than A, otherwise &00

COCHNG:       XOR (HL)
              AND C
              XOR (HL)                      ; Take the masked bits from A and the rest from (HL)
              LD (HL),A
              LD A,C
              INC HL
              RET


; =====================================================================================================================
; BORDER -- BORDER n
; =====================================================================================================================
;
; The border colour goes to the keyboard port, whose colour bits are in an awkward order: green, red and blue in
; bits 2 to 0, with the intensity bit at 5. BORDCOL keeps a copy for SAVE, LOAD and BEEP to restore, preserving the
; two high bits which are the sound-off and MIDI-through flags rather than colour.
;
; BORDCR is the attribute used for the lower screen, chosen to contrast with the border, and M23LSC is the
; equivalent pair of packed colour bytes for modes 2 and 3.
; ---------------------------------------------------------------------------------------------------------------------

BORDER:    CALL SYNTAX6

           LD DE,(16*256)+ERR_BADCOLOUR     ; Colours 0 to 15
           CALL LIMBYTE

SETBORD:   LD C,A
           LD L,C
           RLCA
           RLCA
           LD B,A
           XOR C
           AND &20                          ; The intensity bit comes from the rotated copy, at bit 5
           XOR C
           OR &08                           ; MIC off
           EX DE,HL
           LD HL,BORDCOL
           XOR (HL)
           AND &3F                          ; Bits 7 and 6, sound-off and MIDI-through, come from the stored copy
           XOR (HL)
           LD (HL),A
           EX DE,HL
           OUT (KEYPORT),A
           LD A,B
           RLCA                             ; The colour, aligned as an attribute paper field
           LD H,0                           ; Black ink
           BIT 5,A
           JR NZ,BORD1                      ; A light border, so black ink contrasts

           LD H,&FF                         ; A dark border: white ink, colour 15 in mode 3 or 3 in mode 2
           OR &07                           ; And white ink in the attribute too

BORD1:     LD (BORDCR),A
           LD A,L
           RLCA
           RLCA
           RLCA
           RLCA
           OR L
           LD L,A                           ; Two copies of the paper nibble
           LD A,(MODE)
           CP 2
           JR NZ,BORD3

           CALL M3TO2
           INC A
           JR Z,BORD2                       ; Paper is already &FF, so use ink 0

           LD A,&FF                         ; Otherwise white ink

BORD2:     LD H,A

BORD3:     LD (M23LSC),HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CVLSP / M3TO2 -- convert a mode 3 packed colour byte to the mode 2 form
;
; Mode 3 stores two four-bit pixels per byte; mode 2 stores four two-bit pixels. The conversion replicates the low
; two bits of the colour across all four pixel fields. CVLSP is the entry MODE uses when switching into mode 2.
; ---------------------------------------------------------------------------------------------------------------------

CVLSP:     CALL M3TO2
           JR BORD3

M3TO2:     LD A,L
           RLCA
           RLCA                             ; Bits 5,4 and 1,0 move to 7,6 and 4,3
           XOR L
           AND &CC                          ; Keep bits 7, 6, 4 and 3 from the rotated copy
           XOR L                            ; Four copies of the two-bit colour
           RLCA                             ; Correct for the bit swap
           LD L,A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; WINDOW -- WINDOW left, right, top, bottom, or bare WINDOW to restore the full screen
;
; The four values are validated against WINDMAX, which holds the lowest usable line and the rightmost column for the
; current mode, and stored as two pairs: UWRHS holds left and right, UWTOP holds top and bottom. The print position
; is then moved to the new top-left corner.
; ---------------------------------------------------------------------------------------------------------------------

WINDOW:    CALL CRCOLON
           JR Z,ALLWIND                     ; No parameters

           CALL EXPT4NUMS                   ; left, right, top, bottom
           CALL CHKEND

           CALL GETBYTE                     ; Bottom
           LD A,(WINDMAX)
           SUB C
           JR C,WDERR                       ; Below the lowest usable line

           LD B,C
           PUSH BC
           CALL GETBYTE                     ; Top
           POP BC
           CP B
           JR Z,WND2                        ; A one-line window is allowed

           JR NC,WDERR                      ; The top is below the bottom

WND2:      LD C,A
           PUSH BC                          ; Bottom and top
           CALL GETBYTE                     ; Right
           LD A,(WINDMAX+1)
           CP C
           JR C,WDERR                       ; Past the right-hand margin

           PUSH BC
           CALL GETBYTE                     ; Left
           POP HL
           CP L
           JR NC,WDERR                      ; One character wide or less

SETWIND:   LD H,A
           LD (UWRHS),HL                    ; Left and right
           POP HL
           LD (UWTOP),HL                    ; Top and bottom
           LD H,L
           LD L,A
           LD (SPOSNU),HL                   ; Move the print position to the top-left corner
           RET

ALLWIND:   CALL CHKEND

           LD HL,(WINDMAX)                  ; L = the lowest line, H = the rightmost column
           XOR A
           LD D,L
           LD E,A                           ; Bottom and top
           PUSH DE
           LD L,H                           ; Right; A is still zero for the left
           JR SETWIND

WDERR:     RST &08
           DB ERR_BADWINDOW


; ---------------------------------------------------------------------------------------------------------------------
; OUT -- OUT port, value
; ---------------------------------------------------------------------------------------------------------------------

OUT:       CALL SYNTAX8

           CALL GETBYTE                     ; The value
           PUSH AF
           CALL GETINT                      ; The port, in BC
           POP AF
           OUT (C),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; STOP -- the STOP statement, which is simply a report
; ---------------------------------------------------------------------------------------------------------------------

STOP:      CALL CHKEND

           RST &08
           DB ERR_STOPSTMT


; ---------------------------------------------------------------------------------------------------------------------
; RANDOMIZE -- RANDOMIZE, or RANDOMIZE n
;
; A bare RANDOMIZE, or RANDOMIZE 0, seeds from the frame counter, which is unpredictable in practice. Any other
; value seeds deterministically, so a sequence can be repeated.
; ---------------------------------------------------------------------------------------------------------------------

RANDOMIZE: CALL SYNTAX3                     ; A number, or nothing

           CALL GETINT
           LD A,H
           OR L
           JR NZ,RANDOM1

           LD HL,(FRAMES)

RANDOM1:   LD (SEED),HL
           RET

                                            ; ON ERROR, FINDER, MNINIT, PALETTE, BLOCKS,
                                            ; KEY, DEVICE, PAUSE, COITEM2
