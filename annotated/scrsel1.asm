; =====================================================================================================================
; SCRSEL1.ASM -- Screens, streams, page allocation, interrupts and the keyboard
; =====================================================================================================================
;
; Two unrelated halves share this file.
;
; The first half implements the SAM's multiple-screen model and the memory allocation that underpins it:
;
;   SCREEN n                 make screen n the one PRINT, PLOT and the rest draw on
;   OPEN SCREEN n,mode       allocate two pages for a new screen and initialise them
;   CLOSE SCREEN n           give those pages back
;   OPEN #s,"c" / CLOSE #s   attach a stream to a channel, or detach it
;   OPEN n / CLOSE n         reserve or release n 16K pages for BASIC's own use
;
; Screens are described by two tables. SCLIST has one byte per screen (mode in bits 6-5, first page in bits 4-0,
; &FF if closed) and ALLOCT has one byte per 16K page of physical memory saying who owns it. A screen occupies two
; consecutive pages starting on an even boundary, because the largest screen mode needs 24K.
;
; The second half is the interrupt service routine and the keyboard scanner it drives:
;
;   INTS                     the RST &38 handler, dispatching on the STATPORT interrupt-source bits
;   LINEINT                  line interrupts, which is how per-scan-line palette changes are done
;   FRAMINT                  the frame interrupt: palette reload, flashing inks, the clock, the mouse, the keyboard
;   KEYSCAN / KINTER         reading the key matrix and turning it into characters
;
; The keyboard scanner works on *changes* rather than on the current state, so that a new key is noticed even while
; other keys are still held down; releases are ignored. See KEYSCAN for the detail.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; JSCRN / SCREEN -- select the current screen
;
; Switching screens means saving the current screen's variables into its own page and loading the new screen's
; variables out of its page, so that cursor position, window, colours and mode all follow the screen. The SCLIST
; entry for the outgoing screen is refreshed first, because its mode may have been changed by a MODE command since
; it was selected.
;
; If CURDISP is zero the display follows the selected screen; otherwise the display stays where DISPLAY put it and
; only drawing moves.
;
; Entry:  JSCRN -- screen number in C (jump table entry); SCREEN -- CHAD at the argument
; Errors: ERR_BADSCRNUM if the screen is not open
; ---------------------------------------------------------------------------------------------------------------------

JSCRN:     CALL SCRNTLK2
           JR JSCR2

SCREEN:    CALL SYNTAX6

           CALL SCRNTLK1     ;GET MODE/PAGE FOR SCREEN C, Z IF UNUSED

JSCR2:     JR Z,ISCEH        ;'INVALID SCREEN NUMBER' IF NOT OPEN

           LD A,(CUSCRNP)
           LD DE,(SCPTR)
           LD (DE),A         ;UPDATE SCLIST MODE AS WE SWITCH OUT THIS SCREEN
           LD (SCPTR),HL
           LD A,(HL)
           PUSH AF
           CALL SSVARS       ;SAVE SCREEN VARS TO STORE IN SCREEN PAGE
           POP AF
           CALL PRSVARS       ;COPY VARS FROM SELECTED SCREEN TO SYS VARS
           LD A,(CURDISP)
           AND A
           JP Z,DEFDISP

           RET               ;RET - DISPLAY FIXED ON A GIVEN SCREEN


; ---------------------------------------------------------------------------------------------------------------------
; SCRNTLK1 / SCRNTLK2 -- look a screen up in SCLIST
;
; Entry:  SCRNTLK1 -- screen number on the calculator stack; SCRNTLK2 -- screen number in C
; Exit:   HL points at the SCLIST entry, A = the entry, Z if the screen is closed (A = SCLISTFREE)
; Errors: ERR_BADSCRNUM if the number is not 1-16
; ---------------------------------------------------------------------------------------------------------------------

SCRNTLK1:  CALL GETBYTE      ;GET SCREEN NUMBER FROM FPCS

SCRNTLK2:  DEC C
           LD A,C
           CP MAXSCREENS

ISCEH:     JP NC,ISCRERR     ;LIMIT SCREENS TO ORIG. OF 1-16

           LD HL,SCLIST
           LD B,0
           ADD HL,BC
           LD A,(HL)         ;BIT 7=0, BITS 6-5=MODE, BITS 4-0=PAGE (BIT 0=0)
           CP SCLISTFREE
           RET               ;Z IF FF (CLOSED)


; ---------------------------------------------------------------------------------------------------------------------
; CLSCRN -- the CLOSE command, in its three forms
;
;   CLOSE #s          detach a stream. Streams 0-3 revert to their default channels rather than becoming unattached,
;                     which is what the STRMTAB+5 lookup is for; 4-15 are simply zeroed.
;   CLOSE SCREEN n    free a screen's two pages
;   CLOSE n           release n pages of BASIC's allocation
;
; A stream open to a channel DOS installed is closed by DOS, through the CSHK hook.
;
; Entry:  A = the character after the CLOSE token
; ---------------------------------------------------------------------------------------------------------------------

CLSCRN:    CP "#"
           JR NZ,CLNCH       ;JR IF NOT A STREAM CLOSE

           CALL SSYNTAX6     ;CLOSE #S

           CALL STRMINFO
           RET Z             ;RET IF CLOSED

           PUSH HL
           CALL CHLTCHK
           JR Z,CLOS1        ;OK IF K, S, P, $ OR B **
                             ;HL=PTR TO LETTER IN CHANNEL, A=LETTER
           POP DE            ;STREAM PTR
           RST &08           ;CLOSE A NON-K/S/P STREAM.
           DB CSHK           ;DOS CLOSE.
           RET

CLOS1:     LD DE,0           ;VALUE FOR STRM PTR IF CLOSING 4-15
           LD A,C
           CP 4
           JP NC,OLT4

           LD E,A
           LD HL,STRMTAB+5
           ADD HL,DE         ;PT HL TO INITIAL VALUE FOR STREAMS 0-3
           JP OPEN2

CLNCH:     CP TOK_SCREEN
           JR Z,CLSC0


; ---------------------------------------------------------------------------------------------------------------------
; CLTO -- CLOSE n: release n pages from BASIC's allocation
;
; The pages released are the topmost ones. BASIC must keep at least RAMTOPP+1 pages, so the check is on what would
; be left rather than on what is being freed.
;
; Errors: ERR_NOMEM if the close would take BASIC below its minimum
; ---------------------------------------------------------------------------------------------------------------------

           CALL SYNTAX6      ;NUMBER OF PAGES TO CLOSE

CLTO:      CALL OCPSR        ;GET L=PAGES USED NOW, HL PTING TO PAST LAST
                             ;ENTRY IN ALLOCT, B/C=PAGES TO CLOSE
           LD A,(RAMTOPP)
           INC A             ;NO. OF PAGES THAT *MUST* BE USED BY BASIC
           LD E,A            ;(UNLESS RAMTOP MOVED)
           LD A,L
           SUB C             ;PAGES THAT WILL BE LEFT AFTER CLOSE
           JR C,OMH

           CP E

OMH:       JP C,OOMERR       ;MUST BE >=MINIMUM NO.

           XOR A             ;PAGEFREE

CLPL1:     DEC HL
           LD (HL),A         ;FREE PAGE
           DJNZ CLPL1

SETLPG:    DEC HL
           LD A,L
           LD (LASTPAGE),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; JCLSCR / CLSC0 -- CLOSE SCREEN n
;
; Marks the SCLIST entry closed and releases both ALLOCT entries. Screen 1 can never be closed (it is the one the
; system starts in and its page holds the system's own screen variables), and neither can whichever screen is
; currently selected.
;
; Errors: ERR_BADSCRNUM for screen 1, ERR_CURSCREEN for the selected screen
; ---------------------------------------------------------------------------------------------------------------------

JCLSCR:    CALL SCRNTLK2
           JR JCS2

CLSC0:     CALL SSYNTAX6      ;N

           CALL SCRNTLK1

JCS2:      RET Z             ;END IF NOT USED YET

           INC C
           DEC C             ;Z IF ORIG SCREEN NUMBER WAS 1 (C=0)
           JP Z,ISCRERR      ;CANNOT CLOSE SCREEN 1!

           AND SCLISTPAGE    ;ISOLATE PAGE USED BY SCREEN TO CLOSE
           LD B,A
           LD A,(CUSCRNP)
           AND SCLISTPAGE
           CP B
           JR NZ,CNCS

           RST &08           ;CANNOT CLOSE CURRENT SCREEN
           DB ERR_CURSCREEN  ;'Current screen'

CNCS:      LD (HL),SCLISTFREE ;MARK SCREEN ENTRY AS CLOSED
           LD L,B            ;HL WILL PT TO ALLOC TABLE ENTRY FOR SCRN PAGE
           LD H,ALLOCT/256
           XOR A             ;PAGEFREE
           LD (HL),A
           INC HL
           LD (HL),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; OPSCRN -- the OPEN command, in its four forms
;
;   OPEN #s,a$        attach stream s to the channel named by a$
;   OPEN SCREEN n,m   allocate and initialise a new screen
;   OPEN n            reserve n more pages for BASIC
;   OPEN TO n         reserve or release pages so that BASIC ends up owning exactly n
;
; A channel name of more than one character, or one that is not k/s/p/$/b, is passed to DOS through the OSHK hook,
; which is how the disk system installs its own channels.
;
; Entry:  A = the character after the OPEN token
; Errors: ERR_STRMOPEN if the stream is already attached to a non-reassignable channel
; ---------------------------------------------------------------------------------------------------------------------

OPSCRN:    CP "#"
           JP NZ,OPNCH       ;JR IF NOT 'OPEN TO A CHANNEL'

;CHECK FOR OPEN #S;A$ OR OPEN #S,A$

           CALL SEXPT1NUM
           CALL INSISCSC     ;',/;'
           CALL SYNTAXA

           CALL SWOP12       ;GIVES NAME,STREAM
           CALL STRMINFO     ;Z IF CLOSED. HL PTS TO STRM PTR MSB
           PUSH HL
           JR Z,OPEN1        ;JR IF CHANNEL IS CLOSED

           CALL CHLTCHK
           JR NZ,SAOERR      ;ERROR IF NOT OPEN TO K/S/P/$/B/N ALREADY

           JR NC,OPEN1       ;JR IF OPEN TO K/S/P, ERROR IF OPEN TO $/B/N

SAOERR:    RST &08
           DB ERR_STRMOPEN   ;'Stream is already open'

OPEN1:     CALL SBFSR        ;COPY FILE NAME TO BUFFER. DE=START, A/C=LEN
           JP Z,IFNER        ;JP IF LEN ZERO

           DEC A
           JR NZ,INVCHP      ;ERROR (OR DOS) IF NAME LONGER THAN 1. E.G.
                             ;OPEN #4;"S" IS OK BUT OPEN #4;"FILE" JUMPS
           LD A,(DE)
           OR &20            ;LETTERS BECOME L.C. AND '$' UNCHANGED
           LD HL,CLTAB
           LD B,5            ;CHECK 5 CHANNEL TYPES

OPCL:      CP (HL)
           INC HL
           JR Z,OPEN2

           INC HL
           DJNZ OPCL

INVCHP:    POP HL            ;PTR TO STREAM PTR MSB
                             ;DE POINTS TO NAME, C=LEN
           RST &08           ;OPEN #S,A$ WITH A$ NOT K, S, P, $, OR B OR LEN>1
           DB OSHK           ;DOS OPEN
           RET

OPEN2:     LD E,(HL)         ;GET DISPLACEMENT FROM TABLE

OLT4:      POP HL
           LD (HL),0
           DEC HL
           LD (HL),E
           RET

; The five built-in channels and their displacements into the channel area: keyboard, screen, printer, string
; (used by OPEN #s,"$" for output into a string) and buffer.

CLTAB:     DB "k",1
           DB "s",6
           DB "p",16
           DB "$",21
           DB "b",26


; ---------------------------------------------------------------------------------------------------------------------
; OPNCH -- OPEN with something other than "#": SCREEN, TO, or a page count
;
; OPEN TO n normalises to an OPEN or a CLOSE of the difference, and then falls into the common code with the count
; already stacked. The CP A at TOPO sets Z so the CALL NZ,SYNTAX6 at NOTP is skipped -- the argument has already
; been evaluated.
; ---------------------------------------------------------------------------------------------------------------------

OPNCH:     CP TOK_SCREEN
           JR Z,OPSCR0

;OPEN N PAGES  OR OPEN TO PAGE N

           CP TOTOK
           JR NZ,NOTP

           CALL SSYNTAX6

           CALL GETBYTE
           DEC C             ;E.G. OPEN TO 1 DOES NOTHING IF LASTPAGE=0
           LD A,(LASTPAGE)
           SUB C
           RET Z             ;RET IF OPEN TO CORRECT PAGE ALREADY

           JR C,TOPO

           CALL STACKA
           JP CLTO

TOPO:      NEG               ;GET PAGES TO OPEN
           CALL STACKA
           CP A

;OPEN N PAGES - NZ ON ENTRY

NOTP:      CALL NZ,SYNTAX6   ;NUMBER OF PAGES TO OPEN

           CALL OCPSR        ;GET HL PTING TO PAST LAST CURRENT PAGE
                             ;ENTRY IN ALLOCT, B/C=PAGES TO CLOSE

; Every page about to be claimed must currently be free. INC/DEC (HL) is a two-byte way of testing a byte for zero
; without disturbing A.

OPL1:      INC (HL)
           DEC (HL)
           JP NZ,OOMERR      ;ERROR IF NOT ENOUGH FREE PAGES ABOVE CONTEXT'S
                             ;CURRENT PAGES
           INC HL
           DJNZ OPL1

           LD B,C
           CALL SETLPG       ;DEC HL, SET LAST PAGE

OPL4:      LD (HL),PAGEBASIC ;RESERVE PAGE
           DEC HL
           DJNZ OPL4

           RET


; ---------------------------------------------------------------------------------------------------------------------
; JOPSCR / OPSCR0 -- OPEN SCREEN n,mode
;
; Finds two consecutive free pages on an even boundary, claims them, writes the mode and page into SCLIST, and then
; initialises the new screen by temporarily making it current and running the ordinary MODE code over it. That is
; why the current screen's variables and palette are saved first and restored afterwards -- for the duration of
; MODPT2 the system genuinely is pointing at the new screen.
;
; THFATP is forced to 1 across the call so that MODPT2 does not disturb the current FATPIX setting.
;
; Entry:  JOPSCR -- mode in B, screen number in C; OPSCR0 -- CHAD at the arguments
; Errors: ERR_SCROPEN if the screen is already open, ERR_NOMEM if no 32K block is free
; ---------------------------------------------------------------------------------------------------------------------

JOPSCR:    PUSH BC           ;MODE IN B
           CALL SCRNTLK2     ;CHECK SCREEN C
           JR JOPS2

;OPEN SCREEN N,M    (NUMBER, MODE)

OPSCR0:    CALL SSYNTAX8     ;N,M

           LD DE,&0400+ERR_BADMODE
           CALL LIMDB        ;MODE 0-3 FROM ORIG OF 1-4
           PUSH AF           ;MODE
           CALL SCRNTLK1     ;GET N FROM FPCS, LOOK IN TABLE FOR SCREEN N

JOPS2:     JR Z,OPSCR4       ;OK IF NOT USED YET

           RST &08
           DB ERR_SCROPEN    ;'Screen already open'

; Search ALLOCT downwards two entries at a time. Because the scan starts at the terminator and steps by two, the
; pair examined always begins on an even page, which is the alignment a screen needs.

OPSCR4:    PUSH HL           ;SCREEN LIST PTR
           LD HL,ALLOCT+&20  ;HL PTS TO ALLOCT TERMINATOR

OPSCRLP:   DEC L
           LD A,(HL)
           DEC L
           JP Z,OOMERR       ;OUT OF MEMORY IF NO SPACE FOR NEW SCREEN

           OR (HL)           ;Z IF 2 PAGES UNUSED (0)
           JR NZ,OPSCRLP     ;LOOP UNTIL FOUND A FREE 32K BLOCK, EVEN START PAGE

           POP DE            ;SCLIST PTR
           POP AF            ;MODE TO OPEN IN
           PUSH AF

;A=MODE, HL PTS TO ALLOCT ENTRY, DE TO SCLIST ENTRY
;MARK ALLOCT, SCLIST

           LD (HL),PAGESCREEN
           INC HL
           LD (HL),PAGESCREEN ;RESERVE PAGES IN SYSTEM PAGE ALLOC TABLE
           DEC HL            ;L=PAGE NUMBER 02-1EH

; Pack mode and page into one byte. Two RRCAs then one SRL leave the mode (0-3) in bits 6-5 with bit 7 clear; the
; XOR/AND/XOR sequence then merges in the page number from L without disturbing the mode field.

           RRCA
           RRCA
           SRL A             ;0MMX XXXX
           XOR L
           AND &E0           ;TAKES BITS 7-5, BUT BIT 7 IS ALREADY CLEAR
           XOR L             ;0MM FROM A, PAGE FROM L
           LD (DE),A         ;MODE/PAGE DATA TO SCRN LIST
           PUSH AF           ;MODE/PAGE FOR NEW SCREEN
           CALL SSVARS       ;STORE CURRENT SCREEN VARS SINCE WE ARE FIDDLING...
           CALL SDISRC       ;STORE CURRENT PALTAB
           LD HL,CUSCRNP
           LD B,(HL)
           POP AF            ;NEW MODE/PAGE
           LD (HL),A
           POP DE            ;D=MODE FOR NEW SCREEN
           PUSH BC           ;B=NORMAL CUSCRNP
           PUSH DE           ;MODE
           LD HL,THFATP
           LD B,(HL)
           LD (HL),1         ;ENSURE NO XRG CHANGE
           POP AF            ;MODE
           PUSH BC
           CALL MODPT2       ;CLEAR NEW SCREEN IN DESIRED MODE, SET UP EXPAN.
                             ;TABLES, ETC

           CALL SDISRC       ;COPY PALTAB TO NEW SCREEN AREA
           POP AF
           LD (THFATP),A     ;ORIG STATUS
           CALL SSVARS       ;SET UP VARS IN NEW SCREEN PAGE
           POP AF            ;ORIG CUSCRNP
           CALL PRSVARS      ;RESTORE SCREEN VARS
           SCF               ;"RESTORE PALTAB"
           DB SKIP1LDA       ;"JR+1"

SDISRC:    AND A             ;NC - "SAVE PALTAB"

           LD A,(CUSCRNP)
           JP SDISR


; ---------------------------------------------------------------------------------------------------------------------
; SPGLOOK -- is page L in use as a screen page?
;
; Entry:  L = page number
; Exit:   Z if some screen in this context uses it, NZ if not
; ---------------------------------------------------------------------------------------------------------------------

SPGLOOK:   LD B,MAXSCREENS
           LD DE,SCLIST

SPGLKLP:   LD A,(DE)
           INC DE
           AND SCLISTPAGE
           CP L
           RET Z             ;RET IF THIS CONTEXT USES PG L AS A SCREEN ALREADY

           DJNZ SPGLKLP
           RET               ;NZ IF UNUSED


; ---------------------------------------------------------------------------------------------------------------------
; OCPSR -- common setup for OPEN n and CLOSE n
;
; Entry:  page count on the calculator stack
; Exit:   B = C = the count, HL points just past BASIC's last allocated ALLOCT entry, L (and D) = pages in use
; Errors: ERR_IOOR unless the count is 1-30
; ---------------------------------------------------------------------------------------------------------------------

OCPSR:     LD DE,&1E00+ERR_IOOR
           CALL LIMDB        ;ALLOW ONLY 1-30
           LD B,C            ;B AND C=PAGES TO OPEN
           LD HL,ALLOCT

OCL1:      INC HL
           LD A,(HL)
           CP PAGEBASIC
           JR Z,OCL1         ;LOOK PAST LAST PAGE RESERVED BY BASIC

           LD D,L             ;NUMBER OF PAGES CURRENTLY USED
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CHLTCHK -- identify a channel by its letter
;
; Entry:  DE = displacement from CHANS to the channel
; Exit:   HL points at the channel letter, A = the letter
;         Z and NC for K, S or P -- reassignable, so OPEN over them is allowed
;         Z and CY for $ or B    -- already open to something, so OPEN over them is an error
;         NZ              -- a DOS channel
; ---------------------------------------------------------------------------------------------------------------------

CHLTCHK:   LD HL,(CHANS)
           ADD HL,DE         ;PT TO 2ND BYTE OF CHANNEL
           INC HL
           INC HL
           INC HL
           LD A,(HL)
           CP "K"
           RET Z

           CP "S"
           RET Z

           CP "P"
           RET Z

           CP "$"
           SCF
           RET Z

           CP "B"
           SCF
           RET Z

           AND A
           RET


; =====================================================================================================================
; INTS -- the interrupt service routine, entered via RST &38
; =====================================================================================================================
;
; STATPORT reports which of five sources caused the interrupt, active low, in bits 0-4: line, COMS (originally the
; mouse), MIDI in, frame, MIDI out. They are tested in that order by rotating C right, so the earliest test is the
; most time-critical one -- a line interrupt has only the border period in which to change the palette.
;
; Four of the five simply call a user vector if one is installed. The frame interrupt does the housekeeping the
; whole system depends on: reloading the palette, flashing inks, advancing the clock, polling the mouse and
; scanning the keyboard.
;
; Entry:  C = STATPORT value, BC and DE already pushed by the RST &38 stub, SPSTORE holding the return frame
; ---------------------------------------------------------------------------------------------------------------------

INTS:      LD A,C
           LD (LASTSTAT),A
           PUSH BC           ;HMPR/STAT
           PUSH DE
           RRA
           JP NC,LINEINT

           RRA
           JR NC,COMINT

           RRA
           JR NC,MIPINT

           RRA
           JR NC,FRAMINT

;MIDI OUTPUT (OR OTHER) INTERRUPT

           LD HL,(MOPV)
           JR CMMDIC

;COMS (EX MOUSE) INTERRUPT

COMINT:    LD HL,(COMSV)
           JR CMMDIC

;MIDI INPUT INTERRUPT

MIPINT:    LD HL,(MIPV)
           IN A,(MDIPORT)    ;READ MIDI INPUT BYTE (AUTOMATIC INT CANCEL?)

CMMDIC:    INC H
           DEC H
           CALL NZ,HLJUMP    ;CALL THE USER VECTOR IF ONE IS INSTALLED

           JP INTEND


; ---------------------------------------------------------------------------------------------------------------------
; FRAMINT -- the 50Hz frame interrupt
;
; In order: the user's frame vector, then the line-interrupt colour list is rewound and its first scan line written
; to STATPORT so line interrupts start again for this frame, then the 16-entry palette is reloaded with OTDR, then
; the flashing-ink timer, the five-byte frame counter, the mouse and finally the keyboard.
;
; Flashing inks work by keeping two colours in each LINICOLS entry and swapping them over every SPEEDINK frames;
; PALFLAG bit 0 selects which of the two palettes in PALTAB is loaded, and is flipped at the same time.
;
; The screen blanker: SOFFCT counts down once every 256 frames (about 5.1 seconds) and any key press resets it to
; zero, so if it ever reaches zero by counting the keyboard has been idle for around 22 minutes and the display is
; turned off via KEYPORT bit 7. SOFE disables the feature.
; ---------------------------------------------------------------------------------------------------------------------

FRAMINT:   LD HL,(FRAMIV)
           LD A,H
           OR L
           CALL NZ,HLJUMP

           LD HL,LINICOLS
           LD (LINIPTR),HL           ;RESET LINE INT COL CHANGE LIST PTR
                                     ;TO START
           LD A,(HL)                 ;LINE TO INT ON,
           OUT (STATPORT),A          ;OR FF FOR 'NEVER INTERRUPT'

           LD A,(PALFLAG)
           LD HL,PALTAB+15
           RRA
           JR NC,FRMI3

           LD L,(PALTAB+35)\256      ;USE THE SECOND PALETTE

FRMI3:     LD BC,16*256+CLUTPORT
           OTDR                      ;SET UP PALETTE MEMORIES

           LD HL,SPEEDIC             ;COUNTER FOR DELAY BETWEEN SWAPPING INKS
           DEC (HL)
           JR NZ,FRMI5

           INC HL                    ;PT TO PALETTE FLAG
           INC (HL)                  ;FLIP BIT 0 OF PALFLAG - USE OTHER PALET
           LD A,(SPEEDINK)
           DEC HL
           LD (HL),A                 ;RELOAD COUNTER TILL NEXT FLASH
           LD HL,LINICOLS
           JR FRMI4

; Walk the line-interrupt list swapping each entry's two colours, so that line-interrupt colours flash too. Each
; entry is four bytes: scan line, palette memory number, colour 1, colour 2.

FISCL:     INC HL
           INC HL
           LD A,(HL)         ;COL 1
           INC HL
           LD B,(HL)         ;COL 2
           LD (HL),A
           DEC HL
           LD (HL),B
           INC HL
           INC HL            ;NEXT LINE

FRMI4:     LD A,(HL)
           INC A
           JR NZ,FISCL       ;LOOP UNTIL THE FF TERMINATOR

FRMI5:     LD HL,FRAMES
           INC (HL)
           JR NZ,INTS3

           LD A,(SOFFCT)     ;DECED EVERY 5.1 SECS OR SO, SET TO 0 BY KEYBD USE.
           DEC A             ;IF DECED TO ZERO, KYBD NOT USED FOR ABOUT 22 MINS.
           LD (SOFFCT),A
           JR NZ,INTS2       ;JR IF USED WITHIN LAST 22 MINS.

           LD A,(SOFE)
           AND A
           JR NZ,INTS2       ;JR IF 'SCREEN OFF' DISABLED

           LD A,&80
           OUT (KEYPORT),A
           LD (SOFLG),A      ;'SCREEN OFF'

INTS2:     INC HL
           INC (HL)          ;INC SECOND BYTE OF FRAMES
           JR NZ,INTS3

           INC HL
           INC (HL)          ;AND THIRD
           JR NZ,INTS3

           LD HL,(FRAMES34)
           INC HL            ;FOURTH AND FIFTH
           LD (FRAMES34),HL

; The mouse. If no mouse vector is installed the mouse interface is still read nine times, which is what resets its
; internal shift register -- otherwise a mouse left plugged in would desynchronise the next program that did want to
; read it.

INTS3:     LD HL,(MOUSV)
           DEC H
           LD A,H
           INC H
           JR NZ,INTS4       ;IF JR NOT TAKEN, A=FF

           IN A,(KEYPORT)
           LD HL,MSEDP
           LD B,8            ;READ MOUSE 9 TIMES TO CANCEL IT

MSDML:     LD A,&FF
           IN A,(KEYPORT)
           LD (HL),A
           INC HL
           DJNZ MSDML        ;ALWAYS Z HERE

INTS4:     CALL NZ,HLJUMP

INTS5:     CALL KEYRD2
           JR INTEND


; ---------------------------------------------------------------------------------------------------------------------
; LINEINT -- line interrupt: change the palette part-way down the frame
;
; LINIPTR walks a list of four-byte entries (scan line, palette memory, colour, alternate colour) sorted by scan
; line, terminated by a scan line of &FF. On entry the border period for the interrupting line has already begun,
; so there is a narrow window in which to write CLUTPORT before the change would be visible mid-line.
;
; Timing, measured by the author: the first colour costs about 32 T-states and each further one about 80, so two
; changes fit in the border period and about three in the visible part of a line. Overrunning is worse than losing
; a colour, because if the routine is still busy when the next line interrupt is due, STATPORT never gets set up
; and every later change in the frame is lost as well.
;
; The pen-Y register on port &01F8 counts scan lines and is used to wait for the exact line; if the light pen has
; frozen that register the wait is skipped rather than hanging.
;
; Entry:  LINIPTR points at the scan line byte of the current entry
; ---------------------------------------------------------------------------------------------------------------------

LINEINT:     LD HL,(LINIPTR)

LNINSCAN:    LD D,(HL)                 ;D=SCAN LINE IN LINICOL ENTRY
             LD BC,&0100+CLUTPORT      ;PORT BC READS PEN Y (SCAN LINE)
             IN A,(KEYPORT)
             AND &20
             JR NZ,LINILP              ;JR IF LIGHT PEN KEEPS PEN Y FROZEN

LNWAITLP:    IN A,(C)
             CP D
             JR Z,LNWAITLP             ;WAIT FOR NEXT SCAN'S BORDER

LINILP:      INC HL
             LD B,(HL)                 ;PALETTE MEMORY NO.
             INC HL
             LD A,(HL)                 ;NEW VALUE
             OUT (C),A                 ;OUT (BC) WRITES DESIRED PAL. MEM.
             INC HL                    ;SKIP ALTERNATE VALUE FOR FLASHING
             INC HL
             LD A,(HL)                 ;NEXT SCAN VALUE (MIGHT BE THE SAME)
             SUB D
             JR Z,LINILP               ;DO MORE CHANGES FOR THIS SCAN (SCAN D+1)
                                       ;TAKES ABOUT 32 T'S FOR FIRST COLOUR,
                                       ;THEN ABOUT 80 T'S PER LOOP, SO SHOULD
                                       ;GET 2 CHANGES IN BORDER TIME, AND ABOUT
                                       ;3 IN MIDDLE PART.
                                       ;(IF WE USE TOO MANY CHANGES, WE MIGHT
                                       ;MISS A CLOSE-FOLLOWING LINE INT CHANGE
                                       ;AND THEN MISS ALL LATER CHANGES COS
                                       ;LINE INT REG NOT SET UP.)

             CP 1                      ;IS NEXT ENTRY FOR NEXT SCAN?
             JR Z,LNINSCAN             ;IF SO, WAIT FOR IT

             ADD A,D
             LD (LINIPTR),HL
             OUT (STATPORT),A          ;IF A>191, NO MORE COLOUR CHANGES

INTEND:      LD HL,(SPSTORE)
             POP DE
             POP AF          ;A=FORMER HMPR
             RET


; ---------------------------------------------------------------------------------------------------------------------
; KEYRD2 -- move a character from the type-ahead queue into LASTK
;
; The queue is eight bytes with separate head and tail displacements packed into KBQP (L = tail, where the scanner
; writes; H = head, where the reader takes from). Equal means empty. Only one character is handed over per
; interrupt, and only if the program has consumed the previous one -- FLAGS bit 5 is the "key available" flag and
; is cleared by whoever reads LASTK.
; ---------------------------------------------------------------------------------------------------------------------

KEYRD2:    CALL KINTER       ;SCAN KEYBD, PLACE CHAR IN BUFFER IF THERE IS ONE.
           LD HL,(KBQP)      ;L=KEY BUFFER QUEUE END (POSN TO PLACE CHAR AT)
                             ;H=QUEUE HEAD (PTS TO NEXT CHAR TO BE READ)
                             ;BOTH ARE DISPLACEMENTS FROM KBQB (BUFFER START)
                             ;IF H=L, BUFFER IS EMPTY.
           LD A,H
           CP L
           RET Z             ;RET IF NO CHARS IN BUFFER

           LD HL,FLAGS
           BIT 5,(HL)
           RET NZ            ;RET IF LAST KEY NOT READ YET (KEY AVAILABLE)

           SET 5,(HL)        ;'KEY PRESSED'
           LD L,A
           LD H,0
           INC A
           AND KBQMASK
           LD (KBQP+1),A     ;NEW HEAD POSN REFLECTS CHAR TRANSFER TO COME
           LD DE,KBQB
           ADD HL,DE         ;PT TO HEAD
           LD A,(HL)
           LD (LASTK),A      ;TRANSFER TO LASTK
           RET


; ---------------------------------------------------------------------------------------------------------------------
; KINTER -- scan the keyboard and queue a character if a new key has been pressed
;
; Debouncing and auto-repeat both hang off NLASTH, a three-entry history of the last, previous and
; previous-but-one scan code. A code that matches the last or the one before is treated as the same key still being
; held, which starts or continues auto-repeat; anything else is a new press. ENTER is checked against all three
; entries, since it was found to stutter.
;
; Auto-repeat: REPCT counts down from REPDEL for the first repeat and from REPPER thereafter. Before repeating, the
; key is confirmed to be still down by looking it up in the raw KBUFF bitmap through LKPB (the port and bit the key
; was found at), and repeats are suppressed while a character is still unread, so holding a key does not fill the
; queue with a burst that arrives long after the key is released.
; ---------------------------------------------------------------------------------------------------------------------

KINTER:    CALL KEYSCAN
           LD A,0
           JR NZ,LDLH        ;JR IF NO KEY PRESSED
                             ;(NLASTH=0 IF NO KEY OR JUST A SHIFT KEY. USED BY
                             ;AUTO-REPEAT)
           LD HL,NLASTH
           LD A,E            ;UNSHIFTED KEY CODE
           CP (HL)
           JR Z,KBCR         ;JR IF SAME KEY AS LAST TIME

           INC HL
           CP (HL)
           JR Z,KBCR         ;OR TIME BEFORE

           CP KBENTERCODE    ;CODE FOR ENTER KEY - PRONE TO STUTTER
           JR NZ,KBCR

           INC HL            ;EXTRA CHECK FOR ENTER KEY ONLY
           CP (HL)           ;TIME-BEFORE-TIME BEFORE

KBCR:      PUSH AF
           CALL KYVL         ;GET A=CHAR, USING D AND E
           LD C,A
           LD HL,REPCT
           POP AF
           JR NZ,KBDI        ;JR IF NOT SAME KEY AS LAST TIME, OR TIME BEFORE

           DEC (HL)
           RET NZ            ;RET IF NOT TIME TO REPEAT KEY

           PUSH HL           ;ELSE CHECK IT IS STILL HELD DOWN (NOT SOME OTHER
           LD DE,KBUFF+8     ;KEY)
           LD HL,(LKPB)
           LD A,H            ;A=1 FOR PORT FE, 9 FOR FF
           ADD A,E
           LD E,A
           LD A,(DE)         ;A=BYTE FOR DESIRED PORT FROM KBUFF BIT MAP
                             ;'CURRENT' DATA
                             ;L=1 FOR BIT 7, 8 FOR BIT 0
KBXL:      RLCA
           DEC L
           JR NZ,KBXL        ;GET DESIRED KEY BIT TO CARRY

           POP HL
           RET C             ;NO AUTO-REPEAT IF KEY NO LONGER HELD DOWN

           INC (HL)
           LD A,(FLAGS)
           AND FFLAGKEY
           RET NZ            ;RET IF STILL KEYS IN BUFFER (DO NOT ACCUMULATE
                             ;AUTO-REPEATING KEYS)

           LD A,(REPPER)     ;RELOAD REPCT FROM REPPER (DELAY BETWEEN REPEATS)
           JR KBRK

KBDI:      LD A,(REPDEL)

KBRK:      LD (HL),A         ;NEW KEY - SET UP REPCT FOR INITIAL DELAY BEFORE
                             ;AUTO-REPEAT

           LD HL,(KBQP)      ;L=KEY BUFFER QUEUE END (POSN TO PLACE CHAR AT)
                             ;H=QUEUE HEAD (PTS TO NEXT CHAR TO BE READ)
                             ;BOTH ARE DISPLACEMENTS FROM KBQB (BUFFER START)
                             ;IF H=L, BUFFER IS EMPTY. IF *NEW* POSN OF H=L,
                             ;BUFFER IS FULL
           LD A,L
           INC A
           AND KBQMASK
           CP H
           RET Z             ;RET IF BUFFER FULL (WRAPPED SO END=HEAD)

           LD (KBQP),A
           LD H,0
           LD DE,KBQB
           ADD HL,DE         ;PT TO END
           LD (HL),C         ;PLACE CHAR IN BUFFER
           LD A,(LASTKV)

; Shuffle the three-entry scan code history down, inserting A at the front.

LDLH:      LD HL,NLASTH
           LD C,(HL)
           LD (HL),A
           INC HL
           LD B,(HL)
           LD (HL),C
           INC HL
           LD (HL),B
           RET


; ---------------------------------------------------------------------------------------------------------------------
; KYVL -- turn a scan code and shift state into a character
;
; (KBTAB) points at the unshifted table; the caps, symbol and control tables follow it at KBSHIFTTAB-byte intervals,
; so the shift state selects one by repeated addition.
;
; Caps lock is applied afterwards rather than by table, since it should affect only letters.
;
; Entry:  E = scan code, D = shift state (KBSHNONE..KBSHCTRL)
; Exit:   A = character
; ---------------------------------------------------------------------------------------------------------------------

KYVL:      LD HL,(KBTAB)
           LD A,D            ;00 IF NO SHIFT, OR 1/2/3 FOR CAPS/SYM/CNTRL
           LD D,0
           ADD HL,DE
           AND A
           JR Z,KINT4       ;JR IF NO SHIFT USED

           LD E,KBSHIFTTAB

KYVLP:     ADD HL,DE         ;PT TO CAPS SHIFT/SYM/CNTRL TABLE
           DEC A
           JR NZ,KYVLP

KINT4:     LD A,(FLAGS2)
           AND FFL2CAPS      ;Z=CAPS LOCK OFF
           LD A,(HL)
           RET Z

           CALL ALPHA
           RET NC            ;RET IF NOT A LETTER

           AND &DF           ;FORCE LOWER CASE LETTERS TO UPPER CASE
           RET


; =====================================================================================================================
; KEYSCAN -- read the key matrix
; =====================================================================================================================
;
; The scanner looks for bits that have *changed* since the previous scan rather than for bits that are currently
; low, so that a new key is detected even while others are held down. Releases are ignored. If nothing has changed,
; the previous result is returned again -- unless every key is now up, in which case the null result is returned.
;
; KBUFF is 18 bytes: nine bytes of current scan followed by nine of previous scan, one byte per matrix row. Eight
; rows come from ports &FEFE to &7FFE, with bits 4-0 from KEYPORT and bits 7-5 from STATPORT (the SAM has more keys
; per row than the Spectrum did, and the extra three bits are read from a different port at the same address). The
; ninth row is the special port &FFFE, which carries the CONTROL key and a few others and for which only bits 4-0
; are meaningful.
;
; CAPS SHIFT, SYMBOL SHIFT and CONTROL are masked out of the change detection and scanned separately at the end, so
; that pressing a shift key alone is not reported as a key press.
;
; Entry:  none. Enter at KEYSCAN+3 with HL pointing at a different 18-byte buffer to scan into that instead.
; Exit:   NZ = no key pressed, DE = &FFFF
;         Z  = E is the scan code and D the shift state (KBSHNONE..KBSHCTRL)
; ---------------------------------------------------------------------------------------------------------------------

; TWOKSC -- used by INKEY$: scan twice, in case an interrupt consumed the first scan's change information.

TWOKSC:    CALL KEYSCAN
           RET Z

KEYSCAN:   LD HL,KBUFF       ;18-BYTE STORE
           PUSH HL
           LD BC,&FE00+KEYPORT
                             ;C HAS PORT FOR BITS 4-0, B STARTS
                             ;WITH A8 LOW FOR 1ST KEY ROW
           LD D,&E0          ;MASK TO KEEP BITS 7-5 OF A, USE 4-0 OF E

KBSL:      IN E,(C)          ;READ BITS 4-0
           LD A,B            ;A WILL BE ON HI ADDR LINES DURING PORT READ
           IN A,(STATPORT)   ;READ BITS 7-5
           XOR E
           AND D
           XOR E
           INC B
           JR Z,KBEL         ;JR IF WE JUST DID 'SPECIAL' PORT FFFEH

           LD (HL),A
           DEC B
           INC HL
           RLC B             ;NEXT PORT (FEFE, FDFE, FBFE...7FFE)
           JR C,KBSL         ;LOOP UNTIL BACK TO PORT FEFE AGAIN

           LD B,&FF
           JR KBSL

KBEL:      OR &E1            ;ONLY BITS 4-0 VALID FOR PORT FFFE, AND FORCE
           LD (HL),A         ;BIT 0 (CONTROL KEY BIT) HI TOO
           POP HL            ;KBUFF
           LD D,H
           LD E,L
           SET 0,(HL)        ;'NO CAPS SHIFT' (SCAN SEPARATELY FOR IT)
           INC HL
           INC HL
           INC HL
           SET 5,(HL)        ;'NO ESC'
           INC HL
           INC HL
           INC HL
           INC HL
           SET 1,(HL)        ;'NO SYM. SHIFT' (SCAN SEPARATELY FOR IT)
           INC HL
           INC HL            ;PT TO LAST SCAN DATA (BYTES 10-18)
           LD B,KBROWS       ;(HL=KBUFF+9, DE=KBUFF)

; Change detection. For each row: XOR this scan with the last to get changed bits, complement so changes are zeros,
; then OR with the last scan so that a change is only kept as a zero if the bit went 1->0 (i.e. was pressed rather
; than released). The result overwrites the current-scan half of KBUFF, and the raw reading is kept as the new
; previous scan.

KBCL:      LD A,(DE)         ;THIS SCAN DATA
           LD C,(HL)         ;LAST SCAN DATA
           LD (HL),A         ;LAST SCAN DATA UPDATED WITH NEW DATA - BUT WE
                             ;HAVE IT IN C NOW
           XOR C
           CPL               ;GET ALTERED BITS SINCE LAST SCAN AS 0'S
           OR (HL)           ;KEEP AS 0'S IF CHANGE WAS 1->0 (PRESSED)
           LD (DE),A         ;'CHANGED' DATA TO KBUFF
           INC HL
           INC DE
           DJNZ KBCL

           LD B,KBROWS

KBDL:      DEC DE
           LD A,(DE)
           INC A
           JR NZ,KBYK        ;JR IF ANY BIT RESET

           DJNZ KBDL

;NO NEW PRESSES SINCE LAST SCAN. HL=KBUFF+18

           LD B,KBROWS
           LD DE,(LASTKV)    ;E=LAST VALUE

KBAKL:     DEC HL
           LD A,(HL)
           INC A
           JR NZ,KBSH        ;JR IF KBUFF SHOWS ANY KEY PRESSED APART FROM SHIFT
                             ;USE LAST VALUE, PLUS CURRENT SHIFT STATUS
           DJNZ KBAKL

           INC B             ;NZ
           RET

; A new press. Find which bit it was, and turn (port, bit) into a scan code: nine keys per row, numbered so that
; code = (bit-1)*9 - (row-1) with bit counted from 8 for bit 0.

KBYK:      DEC A
           LD C,9            ;BIT NUMBERS RUN 1 (BIT 7) TO 8 (BIT 0)

KBBL:      DEC C
           RRA
           JR C,KBBL         ;CHANGE BIT POSN TO NUMBER IN C (1-8)

           LD (LKPB),BC      ;LAST KEY PORT/BIT SAVED FOR AUTO-REPEAT CHECKING
                             ;B=1 IF LAST PORT = FEFE, 9 IF FFFE. C=8 FOR BIT
                             ;0, 1 FOR BIT 7
           LD A,C
           ADD A,A           ;*2
           ADD A,A           ;*4
           ADD A,A           ;*8
           ADD A,C           ;*9 (09-48H)
           SUB B             ;SUB 1-9 TO GET 00-47H
           LD E,A            ;SCAN CODE TO E

; A key press cancels the screen blanker and resets its idle counter.

           LD HL,SOFFCT
           XOR A
           LD (HL),A         ;ZERO SCREEN OFF COUNTER - KEYBOARD USED
           INC HL
           ADD A,(HL)        ;SOFLG
           JR Z,KBSH         ;JR IF SCREEN NOT TURNED OFF BY NO KEY USE

           XOR A
           LD (HL),A         ;'ON'
           LD A,(BORDCOL)
           AND &7F
           LD (BORDCOL),A
           OUT (KEYPORT),A

; Read the three shift keys directly. CAPS SHIFT is bit 0 of port &FEFE, CONTROL bit 0 of &FFFE, SYMBOL SHIFT bit 1
; of &7FFE. Only one is reported, in that order of precedence.

KBSH:      LD BC,&FEFE
           IN A,(C)
           LD D,KBSHCAPS
           AND D
           JR Z,KBLD         ;JR IF CAPS SHIFT - D=1
                             ;ELSE D=1
           INC B
           IN A,(C)
           AND D
           LD D,KBSHCTRL
           JR Z,KBLD         ;JR IF CONTROL - D=3

           DEC D
           LD B,&7F
           IN A,(C)
           AND D
           JR Z,KBLD         ;JR IF SYM SHIFT - D=2

           DEC D
           DEC D             ;Z=KEY OBTAINED. D=0 FOR NO SHIFT

KBLD:      LD (LASTKV),DE
           RET
                                  ;KEYRD2
