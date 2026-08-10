; =====================================================================================================================
; ROLL.ASM -- ROLL and SCROLL, and the editor's window scroller
; =====================================================================================================================
;
; Two BASIC commands and one internal service share the whole of this file:
;
;   ROLL   dir [,pix [,x,y,w,l]]     move a rectangle of the screen, wrapping what falls off one edge back in at the
;                                    other
;   SCROLL dir [,pix [,x,y,w,l]]     the same, but the vacated strip is filled with the current paper colour and the
;                                    displaced data is lost
;   SCROLL CLEAR / SCROLL RESTORE    nothing to do with moving pixels: these turn the editor's "scroll?" prompt off
;                                    and on again
;
; and, for the ROM's own use:
;
;   CLSWIND / EDRS...                clear or scroll the current character window, used by CLS and by the editor
;
; ROLL and SCROLL are the same routine throughout, distinguished only by TEMPB3 (RSROLL = &FF, RSSCROLL = 0). Where
; ROLL saves the strip that is about to be overwritten and copies it back in at the far edge, SCROLL skips the save
; and fills with M23PAPT instead.
;
; ---------------------------------------------------------------------------------------------------------------------
; Structure
; ---------------------------------------------------------------------------------------------------------------------
;
; The work splits four ways on direction and distance, because each case has a different innermost loop:
;
;   horizontal, 1 pixel     CRBBFN builds an unrolled RLD/RRD chain in CDBUFF; each scan is rotated a nibble at a
;                           time, and the nibble that falls out of one end is fed in at the other
;   horizontal, >= 1 byte   CRTBF builds an unrolled LDIR-equivalent; the displaced bytes are parked in RSBUFF and
;                           written back at the far edge (ROLL) or overwritten with paper (SCROLL)
;   vertical                RUPDN: whole scan lines move, so an unrolled LDI chain of the window width copies each
;                           scan to the row `pix` scans above or below it
;   mode 0 vertical         EDRSM0: the pixel data and the 8x8 attribute area have to be scrolled separately, by
;                           different amounts, using NEXTUP/NEXTDOWN to step across the ZX-layout thirds
;
; All the pixel loops run out of CDBUFF, the RAM code buffer, which is why almost every routine here is a wrapper
; that sets up B'/C'/DE/HL and then CALLs into it. See docs/memory-map.md for the buffer layout.
;
; ---------------------------------------------------------------------------------------------------------------------
; Coordinate conventions
; ---------------------------------------------------------------------------------------------------------------------
;
; Coordinates here are "fat" character-cell coordinates: X counts 4-pixel units and is forced even (so 8-pixel
; units), Y counts scan lines from the top of the screen. HL = Y,X on entry to the common code; the screen address is
; formed by the SCF/RR H/RR L sequence, which turns Y,X into &8000 + Y*128 + X/2 -- that is, a mode 2/3 screen
; address, this code being restricted to those modes by CHKMD23.
;
; Widths are held as w-1 so that a full 256-pixel width fits in a byte.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; JROLL -- ROLL/SCROLL entry from the public jump table
;
; Lets machine code roll an arbitrary rectangle without going through the BASIC parser. The parameters arrive in
; registers rather than on the calculator stack, and are pushed onto the machine stack in the same order the parsing
; path leaves them in, so both paths converge at JROLL2.
;
; Entry:  A  = RSROLL to wrap, RSSCROLL to fill with paper
;         B  = pixels to move by
;         C  = direction, RDIRLEFT..RDIRDOWN
;         HL = top left coordinates (H = Y, L = X)
;         D  = length in scan lines
;         E  = width
; ---------------------------------------------------------------------------------------------------------------------

JROLL:     DEC E             ;WIDTH IS HELD AS W-1 THROUGHOUT
           LD (TEMPB3),A     ;ROLL=FF, SCROLL=00
           PUSH DE           ;LENGTH, WIDTH-1
           PUSH HL           ;COORDS
           LD A,B
           PUSH AF           ;PIXELS
           JR JROLL2


; ---------------------------------------------------------------------------------------------------------------------
; ROLL / SCROLL -- the BASIC commands
;
; Both are reached from the command dispatcher with CHAD pointing at the token. SCROLL first has to rule out the two
; keyword forms, SCROLL CLEAR and SCROLL RESTORE, which set SPROMPT rather than touching the screen.
;
; Entry:  A = the character following the command token (for SCROLL)
; ---------------------------------------------------------------------------------------------------------------------

ROLL:      LD A,RSROLL
           JR RSCOMM

SCROLL:    CP TOK_CLEAR
           JR Z,SETPROMPT    ;JR IF PROMPT TO BE TURNED OFF

           SUB TOK_RESTORE   ;RESTORETOK - ZERO RESULT FOR "PROMPT ON"
           JR NZ,SCRNINOT

SETPROMPT: LD B,A            ;&B3 FOR CLEAR (NZ), 0 FOR RESTORE
           CALL SABORTER     ;SKIP CLEAR/RESTORE

           LD A,B
           LD (SPROMPT),A    ;0=PROMPTS ON
           RET

SCRNINOT:  XOR A             ;RSSCROLL


; ---------------------------------------------------------------------------------------------------------------------
; RSCOMM -- parse and perform ROLL/SCROLL
;
; Three argument forms are accepted, each defaulting the arguments the previous one supplied:
;
;   ROLL dir                 1 pixel, whole screen
;   ROLL dir,pix             whole screen
;   ROLL dir,pix,x,y,w,l     an arbitrary rectangle
;
; The arguments are evaluated left to right onto the calculator stack and then popped in reverse, which is why the
; code below reads back-to-front relative to the syntax.
;
; Entry:  A = RSROLL or RSSCROLL
; ---------------------------------------------------------------------------------------------------------------------

RSCOMM:    LD (TEMPB3),A     ;ROLL=FF, SCROLL=00
           CALL EXPT1NUM     ;DIRECTION
           CP ","
           JR Z,ROLL4        ;GET PIX IF SPECIFIED

           CALL CHKEND       ;ELSE CHECK END AND USE DEFAULT
           LD A,1            ;OF 1-PIXEL ROLL
           JR ROLL5

ROLL4:     CALL SEXPT1NUM    ; PIXELS
           CP ","
           JR Z,ROLL6        ;GET AREA IF SPECIFIED

           CALL CHKEND

           CALL GETBYTE      ;PIXELS

; Whole-screen defaults: the full 192 scan lines by the full 256 pixels, anchored at the top left.

ROLL5:     LD HL,&C0FF       ;LEN=192, W-1=255 ARE DEFAULTS
           PUSH HL
           LD HL,&0000       ;Y=0, X=0 (TOP LHS) ARE DEFAULTS
           PUSH HL
           JR ROLL7

; The full form. SEXPT4NUMS is shared with GRAB/PUT and leaves x,y,w,l on the calculator stack.

ROLL6:     CALL SEXPT4NUMS   ;SKIP X,Y,W,L - SR SHARED WITH GRAB
           CALL CHKEND

           CALL GETBYTE      ;L
           AND A
           JR Z,IOORHP2      ;LENGTH MUST BE 1-255 INITIALLY

           PUSH AF           ;LENGTH
           CALL GETINT       ;WIDTH. LEGAL=2-256
           RES 0,C           ;EVEN WIDTHS ONLY
           DEC BC            ;1-255
           LD A,B
           AND A
           JR NZ,IOORHP2

           POP AF            ;L
           LD B,A            ;L,W-1 IN B,C
           PUSH BC
           CALL GTFIDFCDS    ;B=Y, C=X (FAT COORDS FORCED)
           RES 0,C           ;EVEN X ONLY (OR FOR THINPIX, MULTIPLES OF 4 ONLY)
           PUSH BC
           CALL GETBYTE      ;A=PIX

ROLL7:     PUSH AF
           CALL GETBYTE      ;DIRECTION TO C


; ---------------------------------------------------------------------------------------------------------------------
; JROLL2 -- common body, entered with the parameters on the machine stack
;
; Stack (top first): direction, pixels, coordinates, length/width-1.
;
; CHKMD23 rejects modes 0 and 1: the byte-oriented loops below assume the linear 128-bytes-per-scan layout of the
; high-resolution modes. GRATEMPS copies the permanent window variables of the current device into the temporary
; ones so that SCROLL respects the current window; SPSSR saves the paging state and pages the screen in.
; ---------------------------------------------------------------------------------------------------------------------

JROLL2:    PUSH BC
           CALL CHKMD23
           CALL GRATEMPS     ;SET TEMPS FROM PERM LS OR US VARS - USE FOR SCROLL
           CALL SPSSR        ;STORE PAGE, SELECT SCREEN
           POP BC            ;C=DIRECTION
           POP AF            ;PIX
           POP HL            ;COORDS
           POP DE            ;L, W-1
           AND A
           JR Z,IOORHP2      ;A MOVEMENT OF ZERO PIXELS IS NOT ALLOWED

           LD B,A            ;PIX
           LD A,C            ;DIR. 1234=L/U/R/D
           DEC A
           CP RDIRMAX
           JR C,ROLL75       ;ORIG DIR MUST BE 1-4

IOORHP2:   RST &08
           DB ERR_IOOR

; Bounds check. The rectangle must lie wholly on screen; for a downward move HL is repointed at the bottom row,
; because the copy then runs upwards from the bottom to avoid overwriting source data with destination data.

ROLL75:    LD A,H            ;TOP=0, BOT=191
           ADD A,D
           JR C,IOORHP2

           CP SCREENHEIGHT+1
           JR NC,IOORHP2     ;ERROR IF AREA FALLS OFF BOTTOM

           BIT RDIRBITDOWN,C
           JR Z,NTRDOWN

           LD H,A
           DEC H             ;H=Y IF ROLL DOWN

NTRDOWN:   LD A,L
           ADD A,E           ;ADD X,W-1
           JR C,IOORHP2      ;JR IF OFF SCREEN ON RHS

           LD A,D

           EXX
           LD B,A            ;B"=LENGTH (1-192)
           EXX

; Turn Y,X into a screen address. SCF then rotating Y,X right one place as a 16-bit pair gives &8000 + Y*128 + X/2,
; which is exactly the mode 2/3 address of that pixel column: 128 bytes per scan, two fat-pixel columns per byte.

           SCF
           RR H
           RR L              ;HL=SCR ADDR (LHS, TOP IF LT, RT OR UP; BOT IF DN)
           LD A,E
           ADD A,1           ;WIDTH=2-256. CY IF 256
           RRA               ;GET WIDTH IN BYTES (1-128)
           LD E,A            ;E=WIDTH IN BYTES
           LD D,B            ;D=PIX
           BIT RDIRBITLR,C   ;01=L,10=U,11=R,100=D
           JP Z,RUPDN        ;JP IF UP OR DOWN

           DEC E             ;E=W-1, IN BYTES (0-127)
           DJNZ RLBYTE       ;JR IF MOVING MORE THAN 1 PIX - USE BYTES

           LD D,C


; ---------------------------------------------------------------------------------------------------------------------
; Horizontal movement by exactly one pixel
;
; One fat pixel is one nibble, so the whole scan can be shifted with a chain of RLD/RRD instructions -- each one
; rotates a nibble out of A into (HL) and the displaced nibble of (HL) back into A. CRBBFN builds that chain in
; CDBUFF, one instruction per byte of the window width, terminated by RET.
;
; The nibble seeded into A before the chain runs is what appears at the leading edge: for ROLL, the nibble taken
; from the far end of the same scan; for SCROLL, the paper pattern.
;
; Entry:  C/D = direction, E = width-1 in bytes, HL = screen address, B' = length in scans, A = width in bytes
; ---------------------------------------------------------------------------------------------------------------------

           RST &30
           DW CRBBFN
           DEC D             ;DEC DIR
           JR NZ,NTNRL       ;JR IF ROLL RIGHT

           LD A,L
           ADD A,E
           LD L,A            ;HL=RHS IF ROLL LEFT BY 1 PIX
           LD A,E
           NEG
           LD E,A            ;E=NEGATED WIDTH-1 IF ROLL LEFT. ALLOWS PT TO LHS

NTNRL:     LD A,(TEMPB3)     ;ROLL=FF, SCROLL=00
           LD D,A
           LD C,SCANBYTESM23 ;SCAN LEN
           EXX

NLRLP:     EXX
           LD B,L
           LD A,L
           ADD A,E
           LD L,A            ;PT TO OTHER END OF LINE. CY IF E -VE (ROLL LEFT)
           LD A,(M23PAPT)
           INC D
           DEC D
           JR Z,ROLL8        ;JR IF SCROLL - A=BG COLOUR

           LD A,(HL)         ;GET NIBBLE TO WRAP ROUND
           JR NC,ROLL8       ;JR IF ROLL RIGHT

           RRCA              ;ELSE GET NIBBLE TO OTHER SIDE OF A
           RRCA
           RRCA
           RRCA

ROLL8:     LD L,B            ;HL PTS TO ORIG LINE END AGAIN
           PUSH HL
           CALL CDBUFF
           POP HL
           LD B,0
           ADD HL,BC
           EXX
           DJNZ NLRLP        ;DO B" SCANS

           JR RCURPH         ;RESET UR PORT


; ---------------------------------------------------------------------------------------------------------------------
; RLBYTE -- horizontal movement by two or more pixels, i.e. a whole number of bytes
;
; The displacement M is pix/2 bytes; the odd pixel of an odd displacement is discarded, since a nibble-granular
; shift of a whole strip would need the RLD chain above run repeatedly. CRTBF builds an unrolled block move of
; (width - M) bytes, which is the part of each scan that survives the move.
;
; Four tails follow, one per direction and per ROLL/SCROLL, because they differ in the direction the block move must
; run and in what happens to the vacated bytes.
;
; Entry:  B = pixels (2 or more), C = direction, E = width-1 in bytes, HL = screen address, B' = length
; ---------------------------------------------------------------------------------------------------------------------

RLBYTE:    INC B             ;B=PIX (2+)
           LD A,B
           RRA               ;BYTES OF MOVEMENT (1+). CALL IT M
           LD D,A
           LD A,E            ;WIDTH-1 IN BYTES (0-127)
           SUB D             ;BYTES OF MOVEMENT (M)
           JP C,IOORHP2      ;JR IF M ISN"T LESS THAN WIDTH

           INC A
           RST &30
           DW CRTBF
           SCF               ;CY=LEFT
           DEC C             ;Z IF LEFT, NZ IF RIGHT
           JR Z,RLBY2

           LD A,L
           ADD A,E
           LD L,A            ;HL PTS TO RHS IF RIGHT AND BYTE MOVING. NC

RLBY2:     INC C
           LD B,0
           LD A,(TEMPB3)
           CP 1              ;C IF SCROLL, NC IF ROLL
           DEC C             ;Z IF LEFT, NZ IF RIGHT
           LD A,D            ;A=M
           EXX
           JR C,SCROLLLR

           JR NZ,RRBMLP

; ROLL LEFT BY BYTES. The M bytes at the start of the scan are copied to RSBUFF, the rest of the scan is moved left
; over them by the unrolled LDIR, and the saved bytes are written back at the right-hand end.

RLBMLP:    EXX
           LD C,A            ;BC=M
           PUSH HL
           PUSH HL           ;SCRN PTR
           LD DE,RSBUFF
           LDIR              ;SAVE M BYTES FROM LINE START, ADVANCE SRC
           POP DE            ;ORIG HL
           CALL CDBUFF       ;COPY THE SCAN
           LD HL,RSBUFF
           INC B             ;B=0
           LD C,A            ;BC=M
           LDIR              ;WRAP BYTES FROM BUFFER
           POP HL            ;LINE START
           LD C,SCANBYTESM23
           ADD HL,BC         ;DROP 1 SCAN
           EXX
           DJNZ RLBMLP

RCURPH:    JP RCURPR         ;RESTORE THE PAGING SAVED BY SPSSR

; ROLL RIGHT BY BYTES. The mirror image: save from the right-hand end downwards, move the scan right with a
; descending block move, wrap the saved bytes in at the left.

RRBMLP:    EXX
           LD C,A            ;BC=M
           PUSH HL
           PUSH HL           ;SCRN PTR
           LD DE,RSBUFF+SCANBYTESM23-1
           LDDR              ;SAVE M BYTES FROM LINE END, MOVE SRC PTR LEFT
           POP DE            ;ORIG HL
           CALL CDBUFF       ;MOVE THE SCAN
           LD HL,RSBUFF+SCANBYTESM23-1
           INC B
           LD C,A            ;BC=M
           LDDR              ;WRAP BYTES FROM BUFFER
           POP HL            ;LINE START
           LD C,SCANBYTESM23
           ADD HL,BC         ;DROP 1 SCAN
           EXX
           DJNZ RRBMLP

           JR RCURPH

SCROLLLR:  JR NZ,SRBYPRE     ;JR IF SCROLL RIGHT

; SCROLL LEFT BY BYTES. No save; the M bytes freed at the right-hand end are filled with the paper pattern.

SLBMLP:    EXX
           LD C,A            ;BC=M
           PUSH HL           ;SCRN PTR
           LD D,H
           LD E,L
           ADD HL,BC
           CALL CDBUFF       ;MOVE SCAN LEFT
           LD B,A
           LD C,A
           LD A,(M23PAPT)

SLBBLP:    LD (DE),A         ;BLANK END OF SCAN
           INC DE
           DJNZ SLBBLP

           LD A,C
           POP HL
           LD C,SCANBYTESM23
           ADD HL,BC         ;DROP 1 SCAN
           EXX
           DJNZ SLBMLP

RCURH2:    JR RCURPH

; SCROLL RIGHT BY BYTES. SBC HL,BC is used rather than a signed ADD, so carry has to be clear on the first pass;
; the ADD HL,BC that ends each pass leaves it clear thereafter.

SRBYPRE:   AND A             ;NC FOR FIRST SBC

SRBMLP:    EXX
           LD C,A            ;BC=M
           PUSH HL           ;SCRN PTR
           LD D,H
           LD E,L
           SBC HL,BC         ;DE PTS TO RHS. MOVE HL SLIGHTLY (M) BYTES LEFT
           CALL CDBUFF       ;MOVE SCAN RIGHT
           LD B,A            ;B=M
           LD C,A            ;SAVE M BRIEFLY
           LD A,(M23PAPT)

SRBBLP:    LD (DE),A         ;BLANK LHS (M BYTES)
           DEC DE
           DJNZ SRBBLP

           LD A,C            ;A=M
           POP HL
           LD C,SCANBYTESM23
           ADD HL,BC         ;DROP 1 SCAN. NC
           EXX
           DJNZ SRBMLP

           JR RCURH2


; =====================================================================================================================
; RUPDN -- ROLL/SCROLL up or down
; =====================================================================================================================
;
; Vertical movement copies whole scan lines, so the unrolled buffer is a chain of LDIs of the window width and the
; only thing that changes between up and down is the sign of the step from one scan to the next.
;
; The window is treated as two parts: the "main block", the scans that survive the move, and the `pix` scans at the
; trailing edge that are displaced. ROLL saves those to RSBUFF first (RSSTBLK) and writes them back at the leading
; edge afterwards; SCROLL fills the leading edge with paper instead. If the movement equals the whole window length
; there is no main block at all and the operation degenerates to a clear (SCROLL) or a no-op copy (ROLL).
;
; Entry:  E   = width in bytes
;         HL  = top left screen address (up) or bottom left (down)
;         B'  = length in scans
;         D   = pixels of displacement
;         C   = direction, RDIRLEFT..RDIRDOWN
; ---------------------------------------------------------------------------------------------------------------------

RUPDN:     BIT RDIRBITDOWN,C ;010=UP, 100=DOWN
           LD BC,SCANBYTESM23 ;BC = DISP TO ROW BELOW IF ROLL UP
           JR Z,RUPDN2

           DEC B             ;BC=FF80=-128 IF ROLL DOWN

; ---------------------------------------------------------------------------------------------------------------------
; RUPDN2 -- vertical mover, entered directly by EDRS with BC already set to the signed scan step
;
; Entry:  BC = signed bytes from one scan to the next (+/- the scan length for the mode)
;         DE = D pixels of displacement, E width in bytes
;         HL = leading-edge screen address
;         B' = window length in scans
; ---------------------------------------------------------------------------------------------------------------------

RUPDN2:    LD A,E
           RST &30
           DW CRTBFI       ;CREATE BUFFER OF A LDI"S
           LD A,E
           EX AF,AF'       ;A" = WIDTH, FOR RSSTBLK
           LD A,D            ;PIX

           EXX
           LD C,A            ;C"=PIX
           LD A,B            ;GET LENGTH FROM B"
           LD B,C            ;B"=PIX
           EXX

           SUB D             ;SUB LEN,PIX
           JP C,IOORHP2      ;ERROR IF MOVEMENT IS GREATER THAN WIN LEN

           PUSH AF           ;SAVE MAIN BLOCK SCANS, Z IF MOVE=WIND LEN
           LD A,(TEMPB3)
           AND A
           CALL NZ,RSSTBLK   ;STORE WRAPPED AREA IF ROLL
           POP AF            ;LINES IN MAIN BLOCK
           JR Z,RUPFIN       ;JR IF MOVEMENT=LENGTH OF WINDOW (CLS)

           EXX
           LD B,A            ;B"=LINES IN MAIN BLOCK (AREA NOT WRAPPED)
           EXX

; DE is the destination (the leading edge); HL is stepped `pix` scans into the window to become the source.

           LD A,D            ;PIX
           LD D,H
           LD E,L            ;DE IS SCREEN DEST

ADDDISP:   ADD HL,BC
           DEC A             ;DEC PIX TO MOVE BY
           JR NZ,ADDDISP     ;MOVE HL UP OR DOWN TO START OF MAIN BLOCK

           CALL RSMOVSR
           EX DE,HL

; The main block has been moved; DE now addresses the `pix` scans at the leading edge that need filling.

RUPFIN:    EX DE,HL          ;DE=SCRN DEST
           LD A,(TEMPB3)
           AND A
           JR Z,SCRUDBLK     ;JR IF SCROLL AND BLANKING OF NEW AREA NEEDED

                             ;ELSE WRAP DATA FROM BUFFER
           LD HL,RSBUFF
           EXX
           LD B,C            ;B"=PIX

; SCRUDWRAP -- copy the saved strip back in at the leading edge.
; DE PTS TO BLOCK, BC=SGNED SCAN LEN, B"=SCANS TO DO

SCRUDWRAP: EXX
           PUSH DE           ;SCRN DEST
           PUSH BC           ;DISP TO NEXT SCAN
           CALL CDBUFF       ;COPY A SCAN
           POP BC
           POP DE
           EX DE,HL
           ADD HL,BC         ;MOVE SCRN PTR UP OR DOWN A SCAN
           EX DE,HL
           EXX
           DJNZ SCRUDWRAP    ;COPY "PIX" SCANS

           JR RCUHP

; ---------------------------------------------------------------------------------------------------------------------
; SCRUDBLK -- fill `pix` scans with the paper pattern
;
; Rather than a fill loop, each scan is seeded with one byte and then CDBUFF+2 is called: that enters the unrolled
; LDI chain one LDI in, so the remaining width-1 LDIs propagate the seed byte along the scan (source one byte behind
; destination). One instruction's worth of setup replaces a second unrolled buffer.
;
; Entry:  DE = block address, BC = signed scan length, C' = scans to do, M23PAPT = the fill byte
; ---------------------------------------------------------------------------------------------------------------------

SCRUDBLK:  EX DE,HL          ;HL PTS TO BLOCK TO CLEAR
           LD A,(M23PAPT)
           EXX
           LD B,C            ;B"=PIX

SCRUBOLP:  EXX
           LD D,H
           LD E,L
           INC E
           LD (HL),A
           PUSH BC
           PUSH HL
           CALL CDBUFF+2
           POP HL
           POP BC
           ADD HL,BC         ;MOVE UP OR DOWN A SCAN
           EXX
           DJNZ SCRUBOLP    ;BLANK "PIX" SCANS AT TOP OR BOTTOM

RCUHP:     JP RCURPR


; ---------------------------------------------------------------------------------------------------------------------
; RSSTBLK -- save the strip that is about to be overwritten. Also used by GRAB
;
; The strip goes to RSBUFF, which runs from &E003 to the top of memory. The size check allows 16 bytes for the PUT
; stack and 3 for the coordinate/width/length bytes GRAB stores ahead of the data, so the usable space is 8K-19
; bytes; anything larger is "Stored area too big".
;
; Entry:  HL = screen address (top or bottom), BC = signed scan length, D = pixels, B' = pixels, A' = width
; Exit:   as entry except B' = 0; TEMPW2 = bytes used by the strip
; Errors: ERR_AREATOOBIG
; ---------------------------------------------------------------------------------------------------------------------

RSSTBLK:   PUSH DE
           PUSH HL
           EX AF,AF'         ;WIDTH
           LD E,A
           LD HL,0
           LD A,D            ;A=PIX
           LD D,H            ;DE=WIDTH

CALCSPLP:  ADD HL,DE
           DEC A
           JR NZ,CALCSPLP    ;CALC WIDTH*PIX=STRIP MEM USE

           LD (TEMPW2),HL    ;SAVE SPACE REQUIRED FOR DATA (FOR GRAB)
           LD DE,RSBUFF+16   ;E013H
           ADD HL,DE
           JR NC,STSTPOK

           RST &08
           DB ERR_AREATOOBIG ;"Stored area too big"
                             ;ERROR IF STRIP USES MORE THAN (8K-19 BYTES)
                             ;(16 BYTES FOR PUT STACK, 3 FOR CC,W,L)
STSTPOK:   POP HL
           PUSH HL
           LD DE,RSBUFF
           EXX

STSTPLP:   EXX
           PUSH BC           ;SCAN LEN
           PUSH HL           ;SCRN SRC
           CALL CDBUFF
           POP HL
           POP BC
           ADD HL,BC         ;PT TO SCAN ABOVE OR BELOW (BC IS SIGNED SCAN LEN)
           EXX
           DJNZ STSTPLP

           EXX
           POP HL            ;SCRN ADDR
           POP DE            ;D=PIX
           RET


; =====================================================================================================================
; CLS and the editor's scroll routines
; =====================================================================================================================
;
; These work in character rows rather than pixels and are driven by the window variables (WINDTOP/BOT/LHS/RHS) of the
; current device, so they honour whatever WINDOW is in force. CALCPIX turns rows into scan lines using CSIZE.
; ---------------------------------------------------------------------------------------------------------------------


; ---------------------------------------------------------------------------------------------------------------------
; CLSWIND -- clear the current character window
;
; Implemented as a scroll up by the full window length, which leaves nothing of the old contents and fills the whole
; window with paper. On the upper screen the "left over" scans below the last whole character row (LSOFF) are
; included, so that a window whose height is not a whole number of rows is cleared right to its bottom edge.
; ---------------------------------------------------------------------------------------------------------------------

CLSWIND:   LD HL,WINDBOT
           LD A,(HL)
           DEC HL
           SUB (HL)          ;SUB WINDTOP
           INC A             ;GET ROWS OF WINDOW LEN

           LD C,RDIRUP
           CALL EDRSSR       ;GET B"=LEN, D=DISP (SAME)
           LD A,(DEVICE)
           AND A
           LD A,D
           JR NZ,CLSW1       ;JR IF NOT UPPER SCREEN

           LD A,(LSOFF)
           ADD A,D           ;INCLUDE "LEFT OVER" SCANS
           LD D,A

CLSW1:     EXX
           LD B,A
           EXX
           JR EDRSF


; ---------------------------------------------------------------------------------------------------------------------
; EDRSADN / EDRS1UP / EDRSAUP -- scroll the current window by whole character rows
;
; The line pointer table (the per-line record of which screen rows a logical line occupies) has to be scrolled in
; step with the pixels, which is what the STENTS call does; D holds the direction for it (0 = down, 1 = up).
;
; Entry:  A = rows to scroll (EDRSADN, EDRSAUP)
; ---------------------------------------------------------------------------------------------------------------------

EDRSADN:   LD D,0            ;SCROLL LPT DOWN
           PUSH AF
           RST &30
           DW STENTS         ;SCROLL LINE PTR TABLE
           POP AF
           LD C,RDIRDOWN
           JR EDRS

EDRS1UP:   LD A,1            ;LPT SCROLL BY 1 ROW
           LD D,A            ;SCROLL LPT UP AS D=1
           RST &30
           DW STENTS
           LD A,1            ;WINDOW SCROLL BY 1 ROW

EDRSAUP:   LD C,RDIRUP


; ---------------------------------------------------------------------------------------------------------------------
; EDRS -- the editor's roll/scroll routine
;
; In modes 2 and 3 this is just a call to RUPDN with the window geometry worked out by EDRSSR. Modes 0 and 1 need
; more: their pixel data and colour data live in separate areas, so the scroll has to be done twice.
;
;   mode 1  pixels at &8000, attributes at &A000 (one byte per 8x1 cell). The same RUPDN2 machinery handles both,
;           the second pass differing only in the base address (SET 5,H adds &2000) and in the fill byte, which is
;           zero for the pixels but ATTRT for the attributes.
;   mode 0  the ZX-style interleaved layout means consecutive scans are not consecutive addresses, so EDRSM0 steps
;           with NEXTUP/NEXTDOWN through IX instead of adding a constant.
;
; Entry:  window variables define the character window, A = rows to scroll, C = RDIRUP or RDIRDOWN
; ---------------------------------------------------------------------------------------------------------------------

EDRS:      CALL EDRSSR

EDRSF:     CALL SPSSR        ;STORE PAGE, SELECT SCREEN
           LD A,(MODE)
           CP MODE4COL
           JP NC,RUPDN

           BIT RDIRBITDOWN,C
           LD BC,SCANBYTESM01
           LD IX,NEXTDOWN    ;IN CASE MODE 0
           JR Z,EDRSM1       ;JR IF UP

           LD BC,-SCANBYTESM01
           LD IX,NEXTUP      ;IN CASE MODE 0

EDRSM1:    LD A,(MODE)
           AND A
           JR Z,EDRSM0       ;JR IF MODE 0

           XOR A
           LD (M23PAPT),A    ;MAKE "PAPER COLOUR" BLANK PIXEL PATTERN
           PUSH BC           ;SIGNED SCAN LEN
           PUSH DE           ;D=PIX,E=WIDTH
           PUSH HL           ;SCREEN ADDR
           EXX
           PUSH BC           ;LEN IN SCANS
           EXX
           CALL RUPDN2
           EXX
           POP BC
           EXX
           POP HL
           SET 5,H           ;ADD 2000H - PT TO MODE 1 ATTR
           POP DE
           POP BC
           LD A,(ATTRT)
           LD (M23PAPT),A    ;SET COLOUR FOR M1 ATTRIBUTE SCROLL
           CALL SPSSR
           JP RUPDN2


; ---------------------------------------------------------------------------------------------------------------------
; EDRSM0 -- mode 0 window scroll
;
; Mode 0 keeps the ZX Spectrum display layout, so "the scan below this one" is a function of the current address
; rather than a fixed offset: IX points at NEXTUP or NEXTDOWN and every step goes through IXJUMP. The attribute area
; is 32 bytes per character row and is scrolled separately at the end, by rows rather than scans, via RSMOVSR and
; SCRUDBLK.
;
; Entry:  D = pixels to move by, E = width in bytes, HL = screen address, BC = signed attribute row length,
;         B' = window length in scans, IX = NEXTUP or NEXTDOWN
; ---------------------------------------------------------------------------------------------------------------------

EDRSM0:    LD A,E
           RST &30
           DW CRTBFI
           PUSH BC           ;+/-32

           EXX
           LD A,B            ;GET PIX OF WINDOW LEN
           EXX

           SUB D             ;SUB WINDOW LEN, PIX TO MOVE BY="MAIN BLOCK" LEN
           JP C,IOORHP2      ;ERROR IF MOVED BY MORE THAN WIND LEN

           EXX
           LD B,A            ;MAIN BLOCK LEN IN B"
           EXX

           LD A,D            ;PIX. Z IF WIND LEN=MOVEMENT (CLS)
           PUSH AF
           LD C,E            ;C=WIDTH
           LD B,D            ;B=PIX
           LD D,H
           LD E,L            ;DE=SCRN DEST
           JR Z,EDRSM0L1


EDRSM0P:   CALL IXJUMP       ;MOVE UP OR DOWN A SCAN
           DJNZ EDRSM0P      ;PT HL TO SRC
                             ;B=0 SO BC=WIDTH
EDRSM0L1:  POP AF            ;PIX. Z/NZ
           PUSH AF           ;PIX
           PUSH DE
           PUSH HL           ;SAVE FOR ATTR SCROLL
           PUSH AF           ;PIX, Z/NZ

           EXX
           JR Z,EDRSM0L2

; Move the main block, one scan at a time, stepping both pointers with IXJUMP.

EDRSM0LP:  EXX
           PUSH HL
           PUSH DE
           PUSH BC
           CALL CDBUFF
           POP BC
           POP HL
           CALL IXJUMP       ;ADJ DEST PTR
           EX DE,HL
           POP HL
           CALL IXJUMP       ;ADJ SRC PTR
           EXX

           DJNZ EDRSM0LP     ;LOOP FOR ALL SCANS

EDRSM0L2:  LD B,D            ;B"=ROWS FOR ATTR SCROLL
           EXX

; Blank the `pix` scans of pixel data at the leading edge. E is the fill byte, which for pixels is always zero.

           EX DE,HL          ;HL=SCRN DEST
           POP DE            ;D=PIX TO MOVE BY (AND BLANK)
           LD E,&00

EDRSM0DL:  PUSH HL           ;SCAN START
           LD B,C            ;USE B AS WIDTH COUNTER

EDRSM0BL:  LD (HL),E
           INC L
           DJNZ EDRSM0BL

           POP HL
           CALL IXJUMP
           DEC D
           JR NZ,EDRSM0DL

; Now the same move over the attribute area. The saved pixel source and destination addresses are converted to
; attribute addresses by CTAA and the block is moved by whole rows, then the vacated rows are filled with ATTRT.

           POP HL
           CALL CTAA         ;CONVERT SRC TO ATTR ADDR
           EX DE,HL          ;SRC IN DE
           POP HL
           CALL CTAA         ;CONVERT DEST
           EX DE,HL
           POP AF            ;Z/NZ
           POP BC            ;+/-32
           CALL NZ,RSMOVSR
           LD A,(ATTRT)
           LD (M23PAPT),A    ;SET COLOUR FOR M1 ATTRIBUTE SCROLL

;DE PTS TO BLOCK, BC=SGNED SCAN LEN, C"=SCANS TO DO, A"=WIDTH, M23PAPT=VALUE

           JP SCRUDBLK


; ---------------------------------------------------------------------------------------------------------------------
; CTAA -- convert a mode 0 pixel address to the address of its attribute byte
;
; A mode 0 display file address is %010T TSSS RRRC CCCC (T = third, S = scan within the character row, R = row
; within the third, C = column). The attribute for that cell is at &9800 + third*256 + row*32 + column, so the two
; third bits have to move from bits 3-4 of H down to bits 0-1, which is what the three RRCAs do.
;
; Entry:  HL = pixel address
; Exit:   HL = attribute address
; Uses:   AF
; ---------------------------------------------------------------------------------------------------------------------

CTAA:      LD A,H
           RRCA
           RRCA
           RRCA
           AND 3
           OR &98
           LD H,A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; RSMOVSR -- move a block of scans, used for mode 0 attributes and as the main vertical mover
;
; Entry:  HL = source, DE = destination, BC = signed step from one scan to the next, B' = scans to move,
;         CDBUFF holds an unrolled LDI chain of the width
; Exit:   HL and DE advanced past the last scan moved
; ---------------------------------------------------------------------------------------------------------------------

RSMOVSR:   EXX

UPDNLP:    EXX
           PUSH HL           ;SCRN SRC PTR
           PUSH DE           ;DEST
           PUSH BC           ;DISP TO ROW ABOVE OR BELOW
           CALL CDBUFF
           POP BC            ;DISP
           POP HL            ;DEST
           ADD HL,BC         ;ADJUST BY SCAN LEN
           EX DE,HL
           POP HL
           ADD HL,BC         ;SRC IS AJUSTED BY SIGNED SCAN LEN
           EXX

           DJNZ UPDNLP       ;DO B" SCANS

           EXX
           RET


; ---------------------------------------------------------------------------------------------------------------------
; EDRSSR -- work out the geometry of a window scroll
;
; Turns character-row window variables into the pixel quantities the movers want. The leading-edge address differs
; by direction: scrolling up it is the top row of the window, scrolling down it is the bottom, and for the bottom
; case the address of the row below the window is computed and then backed up by one scan -- cheaper than working
; out the last scan of the last row directly, and correct in every mode.
;
; Entry:  A = rows to move by, C = RDIRUP or RDIRDOWN, window variables set
; Exit:   HL = leading-edge screen address
;         D  = displacement in scan lines
;         E  = width in bytes for the current mode
;         B' = window length in scan lines
;         D' = rows to do (for a mode 0 attribute scroll)
;         C  preserved
; ---------------------------------------------------------------------------------------------------------------------

EDRSSR:    EXX
           LD C,A            ;C"=ROWS TO MOVE BY
           EXX

           CALL CALCPIX
           PUSH AF           ;SAVE AMOUNT TO MOVE BY, IN SCANS (PIX)
           XOR A
           LD (TEMPB3),A     ;"SCROLL"
           LD DE,(WINDLHS)   ;DE=TOP/LHS ROW
           BIT 1,C
           JR NZ,EDRS1       ;JR IF SCROLL UP

           LD A,(WINDBOT)    ;ELSE GET BOTTOM
           INC A
           LD D,A
           CALL ANYDEADDR    ;GET ADDR 1 SCAN (SIC) LOWER THAN NEEDED - NOW
           LD A,(MODE)       ;BACK UP BY 1
           LD HL,-SCANBYTESM23 ;MINUS SCAN LEN FOR M2 OR M3
           CP MODE4COL
           JR NC,EDRS0       ;JR IF M2 OR M3

           LD L,&E0          ;MINUS SCAN LEN FOR M1=FFE0
           DEC A
           JR Z,EDRS0

           EX DE,HL
           CALL NEXTUP       ;IF MODE 0
           DB SKIP1CP        ;"JR+1" OVER THE ADD HL,DE

EDRS0:     ADD HL,DE

           EX DE,HL          ;DE=DESIRED SCREEN ADDR
           CP A              ;SET Z

;ENTRY AT EDRS1 IS NZ

EDRS1:     CALL NZ,ANYDEADDR  ;USES DE/A ONLY. GETS DE=SCRN ADDR
           LD HL,WINDBOT
           LD A,(HL)
           DEC HL
           SUB (HL)          ;SUB WINDTOP
           INC A             ;GET ROWS OF WINDOW LEN

           EXX
           SUB C
           LD D,A            ;ROWS TO DO (IN CASE M0 ATTR SCROLL)
           ADD A,C           ;WINDOW LEN IN ROWS
           CALL CALCPIX
           LD B,A            ;B"=SCANS OF WINDOW LEN
           EXX

           DEC HL
           DEC HL
           LD A,(HL)         ;WINDRHS
           INC HL
           SUB (HL)          ;SUB WINDLHS
           INC A             ;WIDTH IN CHARS.
           EX DE,HL          ;HL=SCREEN ADDR
           POP DE            ;D=AMOUNT TO MOVE BY IN SCANS
           LD E,A            ;MODE 0 OR 1 USES 1 BYTE/CHAR
           LD A,(MODE)
           CP MODE4COL
           RET C

           CP MODE16COL
           JR Z,EDRS3

; Mode 2 (user MODE 3): 4 pixels per byte, so an 8-pixel character is 2 bytes and a 6-pixel character 1.5 bytes.
; The 1.5 case is computed as width + ceil(width/2).

           LD A,(FL6OR8)
           AND A
           LD A,E
           JR NZ,EDRS2       ;JR IF 8 PIXEL, 2 BYTE CHARS

           INC E
           SRL E

EDRS2:     ADD A,E           ;A=WIDTH*1.5, ROUNDED UP, WIDTH*2
           LD E,A
           RET

EDRS3:     LD A,E            ;MODE 3 USES 4 BYTES/CHAR
           ADD A,A
           ADD A,A
           LD E,A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CALCPIX -- convert character rows to scan lines
;
; A row is CSIZE-height scans tall. The multiply is done as rows*5 plus (height-5) further additions of rows, so no
; general multiply is needed and the minimum height of 6 costs one loop iteration.
;
; DHADJ is added at the end: when the bottom half of a double-height character is being printed the effective
; position is 8 scans further down, and every caller of CALCPIX wants that included.
;
; Entry:  A = rows (CALCPIXD takes them in D instead)
; Exit:   A = scan lines, plus DHADJ
; Uses:   AF
; ---------------------------------------------------------------------------------------------------------------------

CALCPIXD:  LD A,D

CALCPIX:   PUSH BC
           LD C,A            ;C=ROWS
           LD A,(CSIZE)
           SUB MINCHARHT-1
           LD B,A            ;B=HEIGHT-5 (AT LEAST 1)
           LD A,C
           ADD A,A
           ADD A,A
           ADD A,C           ;A=ROWS*5

CLPXL:     ADD A,C
           DJNZ CLPXL        ;A=ROWS*6 IF B=1, ROWS*7 IF B=2 ETC

           LD C,A
           LD A,(DHADJ)      ;8 IF BOTTOM HALF OF DOUBLE-HEIGHT CHAR BEING
                             ;PRINTED, ELSE 0
           ADD A,C
           POP BC
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NEXTUP -- mode 0: move HL up one scan line
;
; In the ZX layout the low three bits of H are the scan within the character row, so most steps are a simple DEC H.
; When that borrows out of the character row (H's low three bits going from 0 to 7) the row must be backed up by 32
; bytes in L, and if that in turn borrows, the third changes and H drops by 8 pages.
;
; Entry:  HL = mode 0 screen address
; Exit:   HL = the address one scan line above
; Uses:   AF
; ---------------------------------------------------------------------------------------------------------------------

NEXTUP:    DEC H
           LD A,H
           OR &F8
           INC A
           RET NZ            ;STILL WITHIN THE SAME CHARACTER ROW

           LD A,L
           SUB SCANBYTESM01
           LD L,A
           RET C             ;CROSSED INTO THE PREVIOUS THIRD

           LD A,H
           SUB &F8
           LD H,A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NXTDOWN -- move HL down one scan line, modes 0 and 1. Used by SCREEN$
;
; Entry:  HL = screen address
; Exit:   HL = the address one scan line below
; Uses:   AF, HL only
; ---------------------------------------------------------------------------------------------------------------------

NXTDOWN:   LD A,(MODE)
           AND A
           JR Z,NEXTDOWN

           LD A,SCANBYTESM01 ;MODE 1 IS LINEAR: JUST ADD THE SCAN LENGTH
           ADD A,L
           LD L,A
           RET NC

           INC H
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NEXTDOWN -- mode 0: move HL down one scan line. The mirror of NEXTUP; used by ROLL/SCROLL
;
; Entry:  HL = mode 0 screen address
; Exit:   HL = the address one scan line below
; Uses:   AF
; ---------------------------------------------------------------------------------------------------------------------

NEXTDOWN:  INC H
           LD A,H
           AND &07
           RET NZ              ;NC=NO CRSSING OF CHAR BORDER

NXTDOWN1:  LD A,L
           ADD A,SCANBYTESM01
           LD L,A
           RET C               ;RET IF NEW THIRD

           LD A,H
           ADD A,&F8           ;SET CY
           LD H,A
           RET
