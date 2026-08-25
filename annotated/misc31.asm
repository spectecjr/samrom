; =====================================================================================================================
; MISC31.ASM -- CALL, cold-start initialisation, NEW, the character set unpacker, and PALETTE
; =====================================================================================================================
;
; COLD START
; ----------
; MNINIT is where the machine begins after a reset. It sizes the RAM by writing and reading back a byte in every
; 16K page, builds the page allocation table, copies the keyboard tables, channel table and default DEF KEY strings
; into place, unpacks the character set, and then falls into NEW to build an empty BASIC environment.
;
; PALETTE AND THE LINE INTERRUPT TABLE
; ------------------------------------
; The SAM's palette is sixteen entries, each holding a colour from 0 to 127. Two parallel tables are kept: PALTAB
; and, twenty bytes later, the alternate colours. The frame interrupt loads one or the other, so an entry whose two
; colours differ flashes -- at a rate set by SPEEDINK.
;
; PALETTE also supports changing a colour partway down the screen, via LINICOLS. That is a sorted list of four-byte
; entries, scan line then palette index then the two colours, terminated by &FF. The line interrupt walks it as the
; raster descends. Because the interrupt reads the list asynchronously, every insertion and deletion runs with
; interrupts disabled.
;
; The mode 2 problem again: mode 2 has only four inks, so entering or leaving it swaps palette entries 0 to 3 with a
; saved set (PALSW), the same way misc32.asm's colour bytes are swapped.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; CALLER -- the CALL command: CALL address, parameter, parameter, ...
;
; Each parameter is evaluated and then rearranged on the calculator stack so that it is followed by a type byte and
; the whole group sits underneath the call address. The count ends up in TEMPB3. See
; docs/machine-code-interface.md for the layout the called code sees.
;
; The type byte is the FLAGS value at the time the parameter was evaluated, whose bit 6 distinguishes numeric from
; string. The commented-out lines record an earlier attempt to derive it from the carry flag, which failed because A
; holds the next source character by that point rather than the expression's type.
; ---------------------------------------------------------------------------------------------------------------------

CALLER:    CALL EXPT1NUM                    ; The address
           LD C,0                           ; The parameter count

FCALERLP:  CALL RCRC                        ; RST &18 then CRCOLON
           JR Z,FCALERCE                    ; End of statement

           CALL INSISCOMA
           PUSH BC
           CALL EXPTEXPR                    ; Z for string, NZ for numeric; CY if running
           POP BC
           INC C
           JR NC,FCALERLP                   ; Syntax checking, so nothing is stacked

   ;        RLA               ;NC=STR, CY=NUMB
    ;       SBC A,A           ;STR=00, NUM=FF BUG**A IS CHAR BY THIS TIME
     ;      INC A             ;STR=01, NUM=00
           LD A,(FLAGS)
           LD B,A                           ; The type byte; C is preserved through the calculator

           DB CALC                          ; address, value
           DB SWOP                          ; value, address
           DB STKBREG                       ; value, address, type
           DB SWOP                          ; value, type, address
           DB EXIT

           JR FCALERLP

FCALERCE:  LD A,C
           LD (TEMPB3),A                    ; The parameter count, for the called code to read
           CALL ABORTER

           CALL R1OFFJP
           DW CALLX                         ; Page ROM1 out and jump


; ---------------------------------------------------------------------------------------------------------------------
; SETUPVARS -- create the three system variables ERROR, LINO and STAT
;
; Called by the error handler so that an ON ERROR routine can inspect what went wrong. Each is a normal numeric
; variable created through the usual path, with its name copied from the ERVT table into the tokenised-name buffer
; that the variable creator searches with.
; ---------------------------------------------------------------------------------------------------------------------

SETUPVARS: LD A,(ERRNR)
           LD DE,ERVT                       ; "error"
           CALL CRTVAR2
           LD HL,(PPC)
           LD DE,ERVT+6                     ; "lino"
           CALL CRTVAR3
           LD A,(SUBPPC)
           LD DE,ERVT+11                    ; "stat"

CRTVAR2:   LD H,0
           LD L,A

CRTVAR3:   PUSH DE
           CALL STACKHL                     ; The value goes on the calculator stack
           POP HL
           LD DE,TLBYTE
           LD A,(HL)                        ; The name length, which the searcher wants in A
           LD BC,6                          ; Long enough for the longest of the three names
           LDIR
           CALL R1OFFJP
           DW CRTVAR4


ERVT:      DB 4
           DM "error"
           DB 3
           DM "lino"
           DB 3
           DM "stat"


; =====================================================================================================================
; MNINIT -- cold start
; =====================================================================================================================
;
; Entered from the reset vector. Nothing is set up yet, so this runs on a stack it establishes itself and must not
; assume any system variable holds anything meaningful.
; ---------------------------------------------------------------------------------------------------------------------

MNINIT:    XOR A
           LD I,A
           IM 1

; --- Size the RAM: write and read back a byte in every 256-byte block of every 16K page ---

RMPS:      LD BC,CLUTPORT
           LD D,A
           ADD A,A
           ADD A,A
           ADD A,A
           OUT (C),A                        ; Vary colour 0 as the test proceeds, so the border flickers visibly
           LD A,D
           OUT (URPORT),A                   ; Page the candidate page in at &8000
           LD HL,&8000
           LD DE,&8001
           LD BC,&3FFF
           LD (HL),L
           LDIR                             ; Clear the page
           LD HL,&8000
           INC B                            ; BC = &0100, the step between test locations
           LD E,&40                         ; 64 blocks of 256 bytes

RMCK:      LD (HL),&FF
           LD D,(HL)
           INC D
           JR NZ,RAMEX                      ; Not every bit could be set, so the page is absent

           LD (HL),D                        ; D is zero here, so this clears the byte
           LD D,(HL)
           INC D
           DEC D
           JR NZ,RAMEX                      ; It would not clear, so the page is absent

           ADD HL,BC
           DEC E
           JR NZ,RMCK

           INC A
           CP &20
           JR C,RMPS                        ; Up to 32 pages, that is 512K

           LD A,&FE
           IN A,(&FE)
           RRA
           LD A,&10                         ; 256K
           JR NC,RAMEX                      ; Holding SHIFT at reset forces a 256K machine

           ADD A,A                          ; &20 pages, that is 512K

; --- Build the page allocation table ---

RAMEX:     LD B,A
           DEC A
           LD E,A
           LD (PRAMTP),A                    ; The highest physical page: usually &0F or &1F
           OUT (VIDPORT),A                  ; Any non-zero value stops the system variables showing as attributes
           LD SP,ISPVAL
           LD HL,ALLOCT
           PUSH HL

ATIF:      LD (HL),0                        ; Mark every existing page free
           INC HL
           DJNZ ATIF

           SUB &21
           CPL                              ; &0F becomes &11, &1F becomes &01
           LD B,A

ATIX:      LD (HL),&FF                      ; Fill the rest with the non-existent marker
           INC HL
           DJNZ ATIX

           POP HL
           LD A,&40                         ; In use, context 0
           LD B,4                           ; The four pages BASIC itself needs

ATIU:      LD (HL),A
           INC HL
           DJNZ ATIU

           LD A,L
           DEC A
           LD (LASTPAGE),A                  ; The last page BASIC owns
           LD (RAMTOPP),A

           LD L,E
           DEC L                            ; Point at the top pair of pages, which become the screen
           LD A,L
           OR &60                           ; That page pair, mode 3, MIDI-through inactive
           LD (FISCRNP),A
           LD A,&C0                         ; The "screen" marker
           LD (HL),A
           INC HL
           LD (HL),A
           LD HL,&BFFF
           LD (RAMTOP),HL

; --- Copy the fixed tables into RAM. Each LDIR leaves HL pointing at the next source block, so the source address
;     is only loaded once and the following blocks follow on -- which is why two LD HL instructions are commented
;     out below rather than deleted. ---

           LD HL,KSRC
           LD DE,KTAB+1
           LD C,70*3
           LDIR                             ; The three main keyboard tables

           EX DE,HL                         ; DE -> the value-and-displacement table that PBSL walks
           LD HL,KTAB+238                   ; Destination for the BRIGHT control code
           CALL PBSL                        ; B must be zero on entry, and is unchanged on exit

           LD HL,&5CB6+31+&4000
           LD (PROG),HL

           LD DE,&5CB6
           LD (CHANS),DE
           LD HL,CHANTAB
           LD C,31
           LDIR                             ; The six default channels

           LD HL,DKSRC
           LD DE,DKBU
           LD C,DKEN-DKSRC+1
           LDIR                             ; The default DEF KEY strings

   ;       LD HL,CHIT
           LD DE,LNCUR
           LD C,18
           LDIR                             ; The first eighteen system variables

      ;    LD HL,MAIT
           LD DE,BASSTK
           LD C,26
           LDIR                             ; Thirteen important addresses

           LD HL,NMISTOP
           LD (NMIV),HL

           LD HL,ANYI
           LD (ANYIV),HL

           CALL UPACK
           LD HL,CHARSVAL-256
           LD (CHARS),HL                    ; Biased so code 32 indexes the first bitmap
           LD HL,CHARSVAL+896
           LD (UDG),HL
           JR NEW2


; =====================================================================================================================
; NEW -- clear the program and reset the environment
; =====================================================================================================================
;
; Also the tail of the cold start, entered at NEW2. Interrupts are disabled because the screen list and the page
; allocation table are both being rewritten while the interrupt routine may be reading them.
;
; NEW does not return: it resets SP, pushes MAINER as the error handler, and ends with the copyright banner report,
; which waits for a keypress. See docs/hudg.md for why that makes NEW impossible to drive from a program.
; ---------------------------------------------------------------------------------------------------------------------

NEW:       CALL CHKEND
           DI

NEW2:      LD HL,SCLIST
           LD (SCPTR),HL
           DEC HL                           ; Point at FISCRNP, just below the list
           LD A,(HL)
           LD (CUSCRNP),A
           OUT (VIDPORT),A
           LD B,16

SCLI:      INC HL
           LD (HL),A
           LD A,&FF                         ; The first entry is the current screen; the other fifteen are closed
           DJNZ SCLI

           LD A,(PRAMTP)
           DEC A
           DEC A                            ; Skip past screen 1, which stays open
           LD L,A
           LD H,ALLOCT/256

CSPL:      LD A,(HL)
           CP &C0
           JR NZ,DCSP                       ; Not a screen page

           LD (HL),B                        ; B is zero here, so the page is released

DCSP:      DEC L
           JR NZ,CSPL

; --- Reinitialise the streams ---

           LD C,L                           ; L is zero here
           LD HL,STREAMS-4
           LD DE,STRMTAB                    ; This table must live in ROM0, since ROM1 is not paged in
           LD B,9

STRIL:     LD A,(DE)
           INC DE
           LD (HL),A
           INC HL
           LD (HL),C
           INC HL
           DJNZ STRIL

           LD B,24                          ; Twelve more stream pointers to clear

CLSTL:     LD (HL),C
           INC HL
           DJNZ CLSTL

; --- Build an empty program and variable area ---

           CALL ADDRPROG
           LD (HL),&FF                      ; The program terminator
           INC HL
           LD (NVARS),HL
           LD (NVARSP),A
           LD (ELINEP),A
           CALL RESTOREZ
           LD HL,&0321
           LD (REPDEL),HL                   ; Key repeat delay 33 frames, period 3
           LD HL,MEMVAL
           LD (MEM),HL
           LD A,H
           LD (RASP),A
           LD (SPEEDIC),A                   ; Any non-zero value will do
           LD (THFATT),A                    ; Temporary setting: fat pixels
           XOR A
           LD (THFATP),A                    ; Permanent setting: thin
           LD (MODE),A                      ; Not mode 3 yet, so XRG is not halved by the mode change below
           CALL CLRSR                       ; Clear the calculator stack, BASIC stack, and both variable areas
           LD HL,(SAVARS)
           INC HL
           LD (ELINE),HL
           CALL SETMIN
           LD A,3
           CALL MODET                       ; Set the mode, cell size and windows
           CALL CLSHS2
           LD SP,ISPVAL
           LD HL,MAINER
           PUSH HL
           LD (ERRSP),SP

; --- Build the default rainbow: sixteen palette entries changing every eleven scan lines ---

           LD DE,PALTAB+1
           LD HL,LINICOLS
           LD B,L                           ; The scan number, starting at zero
           LD C,L                           ; Palette entry 0

RBOWL:     LD (HL),B                        ; Scan line
           INC HL
           LD (HL),C                        ; Palette entry
           INC HL
           LD A,(DE)
           INC DE
           LD (HL),A                        ; Main colour
           INC HL
           LD (HL),A                        ; Alternate colour, the same so it does not flash
           INC HL
           LD A,B
           ADD A,11
           LD B,A
           CP 166
           JR C,RBOWL

           LD (HL),&FF                      ; Terminate the list

           RST &08
           DB ERR_BANNER                    ; Print the copyright banner and wait for a key


; ---------------------------------------------------------------------------------------------------------------------
; UPACK -- unpack the character set
;
; The stored font is five bits wide and seven scans tall. Each character is expanded to a full eight-by-eight cell
; with two blank columns on the left, one on the right, and a blank bottom scan. Thirteen characters that do need
; the bottom scan -- the comma and semicolon descenders among them -- are patched afterwards from U8TAB.
;
; The original comment records the trade: the routine is 101 bytes where a plain LDIR of an already-expanded font
; would be 11, but the packed source is far smaller, for a net saving of 402 bytes. (The comment notes the figure is
; out of date, since the foreign character set was dropped.)
;
; The bit extraction uses a neat trick: C is loaded with a source byte and a set carry is rotated in behind it, so
; when C reaches zero the last real data bit has gone and a new byte is fetched.
; ---------------------------------------------------------------------------------------------------------------------

UPACK:     LD HL,99*256+7                   ; H counts the characters, L the scans within each
           EXX
           LD HL,CHARSRC
           LD DE,CHARSVAL
           XOR A
           LD B,5                           ; Five bits per scan

UPKGC:     LD C,(HL)
           INC HL
           SCF                              ; The marker bit that signals when C is exhausted

UPKBL:     RL C
           JR Z,UPKGC                       ; C has emptied, so fetch the next source byte

           RLA
           DJNZ UPKBL                       ; Five bits assembled in A

           RLCA                             ; Centre them: two blank columns left, one right
           LD (DE),A
           INC DE
           XOR A                            ; Clears A and carry together
           LD B,5
           EXX
           DEC L
           EXX
           JR NZ,UPKBL                      ; Seven scans per character

           LD (DE),A                        ; The eighth scan is blank
           INC DE

           EXX
           LD L,7
           DEC H
           EXX
           JR NZ,UPKBL

           LD HL,95*8+CHARSVAL+1            ; The second byte of the copyright sign, the first of five needing
                                            ; bit 6 set -- it is six columns wide, unlike everything else
SB5L:      SET 6,(HL)
           INC HL
           DJNZ SB5L                        ; B is 5 here, left over from the unpack loop

; --- Patch the characters that use the bottom scan ---

           LD DE,U8TAB
           LD HL,CHARSVAL+103               ; Scan 7 of the comma


; ---------------------------------------------------------------------------------------------------------------------
; PBSL -- place bytes at scattered destinations
;
; Entry:  DE -> a table of alternating value and displacement bytes, terminated by a zero displacement;
;         HL -> the first destination; B = 0.
;
; Each pair writes one byte and then advances HL by the displacement to reach the next destination. Also used during
; the cold start to scatter the control-key values through the keyboard table.
; ---------------------------------------------------------------------------------------------------------------------

PBSL:      LD A,(DE)
           INC DE
           LD (HL),A
           LD A,(DE)                        ; The displacement to the next destination, or zero to stop
           INC DE
           LD C,A
           ADD HL,BC
           AND A
           JR NZ,PBSL

           RET


; ---------------------------------------------------------------------------------------------------------------------
; CLSHS -- CLS #, clearing the lower screen and resetting its colours
;
; CLSHS2 is the entry NEW uses. The colour reset is done by printing the control codes rather than by writing the
; variables, so that the stream's own state stays consistent.
; ---------------------------------------------------------------------------------------------------------------------

CLSHS:     CALL SABORTER

CLSHS2:    CALL STREAMFE                    ; Stream "S", the lower screen
           LD BC,&0510                      ; Five codes, ending at code &10

CLHSL:     LD A,B
           ADD A,C
           RST &10                          ; Control codes &15 down to &11
           XOR A
           RST &10                          ; OVER 0, INVERSE 0, BRIGHT 0, FLASH 0, PAPER 0
           DJNZ CLHSL

           LD A,C
           RST &10                          ; Code &10, PEN
           LD A,7
           RST &10                          ; PEN 7
           CALL PER3                        ; Make those temporary settings permanent
 ;         CALL ZBCI
;          JP MCLS

;ZBCI:      XOR A
           XOR A
           CALL SETBORD
           CALL COLINIT
           JP MCLS


; =====================================================================================================================
; COLOUR -- the PALETTE command
; =====================================================================================================================
;
; Forms accepted:
;
;     PALETTE                       reset every entry and clear the line interrupt list
;     PALETTE i,c                   set entry i to colour c
;     PALETTE i,b,c                 set entry i to alternate between b and c
;     PALETTE i,c LINE l            set entry i to c from scan line l downwards
;     PALETTE i,b,c LINE l          likewise, alternating
;     PALETTE i LINE l              delete the change to entry i at line l
;
; i is 0 to 15 and the colours are 0 to 127. Alternating entries flash after SPEEDINK interrupts; if the two
; colours match, nothing flashes.
;
; A line value of l produces an interrupt at the end of scan l-1 and the colour change at the start of scan l. BASIC
; line coordinates run 175 down to -16, which maps to scans 0 to 191; line 175 is rejected because there is no
; preceding scan to interrupt at. Up to 127 changes can be queued per screen.
; ---------------------------------------------------------------------------------------------------------------------

COLOUR:      CALL CRCOLON
             JR NZ,COLOUR1                  ; Something follows, so it is not a bare PALETTE

             CALL CHKEND

COLINIT:     LD A,&FF
             LD (LINICOLS),A                ; Empty the line interrupt list
             LD DE,PALTAB
             CALL COLINIT1                  ; Main colours
             CALL COLINIT1                  ; Alternate colours, from the same source
             LD A,(MODE)
             CP 2
             RET NZ

; --- PALSW: swap palette entries 0 to 3 between the mode 2 set and the four-bit set ---

PALSW:     LD DE,PALTAB
           LD HL,PALTAB+16                  ; Where the inactive set is parked
           CALL PL4S                        ; Swap the main colours; exits with HL = PALTAB+20
           LD DE,PALTAB+36

PL4S:      LD B,4
           JP FPSWOPLP                      ; Swap the alternate colours

COLINIT1:    LD BC,20
             LD HL,INITCOLS
             LDIR
             RET


; --- PALETTE i LINE l: delete an entry ---

COLOUR1:     CALL EXPT1NUM                  ; i
             CP LINETOK
             JR NZ,COLOUR5

             CALL SSYNTAX6                  ; l

             CALL COLATSR
             PUSH AF                        ; The scan line
             LD DE,(16*256)+ERR_BADCOLOUR
             CALL LIMBYTE                   ; i
             POP DE                         ; D = the line
             LD E,A                         ; E = i
             LD HL,LINICOLS

COLDELP:     LD A,(HL)
             INC HL
             CP D
             JR Z,COLDEL2                   ; Found the right scan line

             RET NC                         ; Past it, or at the terminator, so there is nothing to delete

COLDEL1:     INC HL
             INC HL
             INC HL
             JR COLDELP

COLDEL2:     LD A,(HL)
             CP E
             JR NZ,COLDEL1                  ; Right line, wrong palette entry

             LD D,H                         ; Delete the four-byte entry by closing the gap
             LD E,L
             DEC DE                         ; DE -> the line byte of this entry
             INC HL
             INC HL
             INC HL                         ; HL -> the line byte of the next entry
             PUSH HL
             CALL FLITD                     ; BC = the length to the terminator
             POP HL
             DI
             LDIR                           ; If the interrupt's pointer is before the deleted entry this is
             EI                             ; harmless; if after, it simply reads one entry twice
             RET

INKVALERR:   RST &08
             DB ERR_BADCOLOUR


; --- PALETTE i,c and PALETTE i,b,c, with or without LINE ---

COLOUR5:     CALL EXPTCNUM                  ; The colour after the comma
             CP ","
             JR Z,COLOURFL                  ; A third parameter follows

             CP LINETOK
             JR NZ,COLSING

             CALL SSYNTAX6                  ; The line of PALETTE i,c LINE l

             CALL COLATSR
             JR COLOUR10

COLSING:     CALL CHKEND

             LD A,&FF                       ; No line

COLOUR10:    PUSH AF
             LD DE,(128*256)+ERR_BADPALETTE
             CALL LIMBYTE                   ; The single colour
             PUSH AF                        ; Stack it as the alternate colour too, so it does not flash
             JR COLOUR2

COLOURFL:    CALL SEXPT1NUM                 ; The second colour
             CP LINETOK
             JR Z,COLATL

             CALL CHKEND

             LD A,&FF                       ; No line
             PUSH AF
             JR COLOUR15

COLATL:      CALL SSYNTAX6                  ; The line

COLATL2:     CALL COLATSR
             PUSH AF

COLOUR15:    LD DE,(128*256)+ERR_BADPALETTE
             CALL LIMBYTE                   ; The second colour

             PUSH AF
             CALL LIMBYTE                   ; The first colour

COLOUR2:     PUSH AF
             LD DE,(16*256)+ERR_BADCOLOUR
             CALL LIMBYTE                   ; The palette entry

             LD E,A                         ; E = i
             POP BC                         ; B = the first colour
             POP AF
             LD C,A                         ; C = the second
             POP AF                         ; The line, or &FF


; ---------------------------------------------------------------------------------------------------------------------
; JPALET -- install a palette change (jump table entry &0148)
;
; Entry:  A = the scan line, or &FF for an immediate change; E = the palette entry; B and C = the two colours.
; ---------------------------------------------------------------------------------------------------------------------

JPALET:      CP &FF
             JR NZ,COLRLINE

             LD HL,PALTAB
             LD D,0
             ADD HL,DE
             LD (HL),B                      ; The main colour
             LD E,20
             ADD HL,DE
             LD (HL),C                      ; The alternate colour, usually the same
             RET

COLFULERR:   RST &08
             DB ERR_PALFULL

; --- A line change: find the insertion point in the sorted list ---

COLRLINE:    LD HL,LINICOLS
             LD D,A

COLRLP:      LD A,(HL)
             INC HL
             CP D
             JR NC,COLRL2                   ; Reached the terminator, or a line at or past the wanted one

COLRLP2:     INC HL
             INC HL
             INC HL
             JR COLRLP

COLRL2:      JR NZ,COLRL3                   ; This line has no entries yet, so one must be inserted

             LD A,(HL)
             CP E
             JR NZ,COLRLP2                  ; Same line, different palette entry

             DI                             ; Overwrite in place, with the interrupt held off
             JR LD2COL

; --- Insert four bytes at HL-1, which may be the terminator position ---

COLRL3:      DEC HL
             PUSH BC                        ; The colours
             PUSH DE                        ; The line and the palette entry
             PUSH HL                        ; Where the new entry goes
             CALL FLITE                     ; HL = the table end, BC = its length
             INC BC
             INC BC
             INC BC
             INC BC
             LD A,B
             ADD A,&FE
             JR C,COLFULERR                 ; The list would exceed &01FF bytes, that is 127 entries

             POP DE                         ; The insertion point
             PUSH HL
             SBC HL,DE                      ; How much has to move
             LD B,H
             LD C,L
             INC BC                         ; Inclusive of the terminator byte itself
             POP DE
             LD HL,4
             ADD HL,DE
             EX DE,HL                       ; DE -> the terminator plus four, HL -> the terminator
             DI
             LDDR
             INC HL                         ; The four-byte gap
             POP DE
             POP BC
             LD (HL),D                      ; Line
             INC HL
             LD (HL),E                      ; Palette entry

LD2COL:      INC HL
             LD (HL),B                      ; Main colour
             INC HL
             LD (HL),C                      ; Alternate colour
             EI
             RET


; ---------------------------------------------------------------------------------------------------------------------
; FLITE / FLITD -- measure the line interrupt list
;
; FLITE:  from the start. Exit HL = the terminator, BC = the length including it.
; FLITD:  from HL. Exit BC = the distance from HL to the terminator, plus one.
; ---------------------------------------------------------------------------------------------------------------------

FLITE:       LD HL,LINICOLS

FLITD:       LD BC,1

FLITL:       LD A,(HL)
             INC A
             RET Z                          ; The &FF terminator

             INC HL
             INC HL
             INC HL
             INC HL
             INC BC
             INC BC
             INC BC
             INC BC
             JR FLITL


; ---------------------------------------------------------------------------------------------------------------------
; COLATSR -- convert the LINE value on the calculator stack to a scan number
;
; BASIC's Y coordinates run 175 at the top down to -16 at the bottom; scans run 0 to 191 the other way. The
; coordinate machinery expects a pair, so the value is duplicated and the dummy X discarded afterwards.
;
; Exit:   A = the scan, 0 to 190 -- one less than the display line the change first appears on, since the interrupt
;         has to arrive at the end of the line before it.
; Notes:  LINE 175, the top line, is therefore rejected: it would need an interrupt at the end of the scan before
;         the first, which does not exist.
; ---------------------------------------------------------------------------------------------------------------------

COLATSR:     DB CALC
             DB DUP                         ; So COORDFID has a pair to work on
             DB EXIT

             CALL COORDFID
             CALL USYCOORD                  ; Y as 0 to 191
             PUSH AF
             CALL FDELETE                   ; Discard the dummy X
             POP AF
             SUB 1
             RET NC

             RST &08
             DB ERR_IOOR

                                            ; RECORD, FATPIX, CSIZE, WINDOW,
