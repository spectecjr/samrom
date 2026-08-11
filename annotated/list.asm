; =====================================================================================================================
; LIST.ASM -- Listing, screen clearing and the PRINT command
; =====================================================================================================================
;
; Three groups of routines that happen to share this file:
;
;   Listing        AUTOLIST, LIST, LLIST, and the code that moves the '>' cursor up and down the displayed listing
;   Clearing       CLS in its several forms, plus the fast whole-screen clear
;   PRINT          The PRINT and LPRINT commands and their item and separator handling
;
; THE AUTOLIST
; ------------
; After every direct command the main loop re-lists the program around the current line. SDTOP holds the line number
; displayed at the top of the screen and EPPC the line carrying the '>' cursor. AUTOLIST adjusts SDTOP so that EPPC
; is always visible without needing to scroll.
;
; The line pointer table LPT records, for each of the 30 screen rows, whether a program line begins there. That is
; what lets the cursor keys step from one listed line to the next without re-scanning the program.
;
; FAST CLEARING
; -------------
; CLSG clears the screen by pointing SP at it and using PUSH, which writes two bytes per instruction and manages
; roughly seven T-states per byte. Interrupts are disabled for the duration, since SP is not a stack for that time.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; AUTOLIST -- re-list the program around the current line
;
; Entry:  Nothing; reads EPPC and SDTOP.
; Exit:   The upper screen holds a listing with EPPC visible, and SDTOP names its top line.
; Notes:  LISTSP is set so that answering "no" to a scroll prompt can abandon the listing cleanly from any depth.
; ---------------------------------------------------------------------------------------------------------------------

AUTOLIST:   CALL CLSLOWER
            LD HL,EPPC
            CALL REALN                  ; Make sure EPPC names a line that actually exists

; --- AUL2: entry from AUTO, which has already fixed EPPC ---

AUL2:       LD HL,SDTOP
            CALL REALN                  ; Likewise for the top-of-screen line

            CALL CLSUP                  ; Clear the upper window and select channel S
            LD A,FTVAUTOLIST
            LD (TVFLAG),A               ; Autolisting, upper screen
            LD HL,FLAGS2
            SET 0,(HL)                  ; FFL2DIRTY: the screen is no longer clear
            LD HL,(SDTOP)
            LD DE,(EPPC)
            LD (LAST),DE                ; The listing must reach at least as far as EPPC
            AND A
            SBC HL,DE
            EX DE,HL                    ; HL = EPPC
            JR NC,AUL4                  ; EPPC is at or above the current top line, so make it the new top

; --- EPPC lies below the top line: check it is not so far below that it would need scrolling to reach ---

            CALL FNDLINE                ; Address of the EPPC line
            IN A,(URPORT)
            PUSH AF
            PUSH HL                     ; Its address should be roughly &0100 beyond the address for SDTOP,
            LD HL,(SDTOP)               ; so that it appears without scrolling
            CALL FNDLINE
            POP DE                      ; EPPC's address
            DEC C
            DEC D                       ; Aim for a top line about 512 bytes before EPPC in the listing
            POP AF                      ; EPPC's page

AULLP:      LD C,URPORT
            IN B,(C)                    ; B = the page of the candidate top line
            CP B
            JR NZ,AUL25                 ; Different pages, so the candidate is certainly too far back

            SBC HL,DE                   ; Compare the candidate against EPPC-512
            ADD HL,DE
            JR NC,AUL3                  ; Close enough: use this line

AUL25:      INC HL                      ; Step to the following line and try again
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            ADD HL,BC
            PUSH AF
            CALL CHKHL                  ; Keep the pointer inside the paging window
            POP AF
            INC HL
            JR AULLP

AUL3:       LD D,(HL)                   ; Read the line number of the chosen top line
            INC HL
            LD E,(HL)
            EX DE,HL

AUL4:       LD (SDTOP),HL
            LD (LISTSP),SP              ; Let a refused scroll prompt unwind to here
            CALL LIST5                  ; List from this line, with indenting on

AULX:       LD HL,TVFLAG                ; Always returns here, even if the listing was abandoned
            RES 4,(HL)                  ; FTVAUTOLIST clear
            LD BC,IOPOF
            JP R1XJP                    ; Turn indented output off with ROM1 paged out


; ---------------------------------------------------------------------------------------------------------------------
; LIST / LLIST -- the LIST command
;
; Forms:  LIST                 list from the current line to the end
;         LIST n               list from line n to the end
;         LIST n TO m          list a range
;         LIST FORMAT n        set the pretty-listing indent to n columns (0 disables it)
;         LIST #s ...          list to a stream
;
; Exit:   EPPC becomes the first line listed.
; ---------------------------------------------------------------------------------------------------------------------

LLIST:      LD C,3                      ; Stream 3: the printer
            DB SKIP2LDHL                ; Skip the next two bytes

LIST:       LD C,2                      ; Stream 2: the screen
            XOR A
            LD (TVFLAG),A               ; Not an autolist
            CALL RUNFLG
            LD A,C
            CALL C,SETSTRM
            RST &18
            CP TOK_FORMAT
            JR NZ,LIST1

; --- LIST FORMAT n ---

            CALL SSYNTAX6               ; Skip the keyword and insist on a number

            LD DE,(3*256)+ERR_IOOR      ; D = limit, E = error code: accept 0-2
            CALL LIMBYTE
            LD (LISTFLG),A
            RET

LIST1:      CALL PRHSH1                 ; An optional "#stream"
            RST &18
            CALL COMMASC
            JR NZ,LIST2

            RST &20                     ; Skip a comma or semicolon after the stream

LIST2:      CALL BRKLSSL                ; Parse the bracketless range into FIRST and LAST; CY if out of range
            LD HL,FLAGS
            BIT 7,(HL)
            RET Z                       ; FFLAGRUN clear: syntax check only

            PUSH AF                     ; CY still records whether the range was out of range
            AND A
            JR NZ,LIST3                 ; A range of two numbers, so leave LAST alone

            DEC A                       ; A single number: LIST 10 means 10 to the end.
            LD (LAST+1),A               ; (DELETE 10, sharing this parser, keeps it as one line.)

LIST3:      LD HL,(FIRST)
            LD A,H
            OR L
            JR Z,LIST4                  ; LIST 0: ignore the range error this would otherwise cause

            POP AF
            JP C,IOORERR

            PUSH AF

LIST4:      POP AF
            LD (EPPC),HL                ; The first line listed becomes the current line

LIST5:      CALL FNDLINE
            LD BC,LSTLNS
            JP IOPCL                    ; Call it with indented output enabled

LSTLNS:     RST &30
            DW LSTR1-&8000              ; The listing loop proper lives in ROM1


; ---------------------------------------------------------------------------------------------------------------------
; SPACAN -- cancel any pending pretty-listing indent
; ---------------------------------------------------------------------------------------------------------------------

SPACAN:     XOR A
            LD (NXTSPCS),A
            LD (NXTHSPCS),A
            RET


; =====================================================================================================================
; CLS and its variants
; =====================================================================================================================
;
; CLS       clear the whole screen and reset the graphics origin
; CLS 1     clear only the current window
; CLS #     reset the windows, streams and colours as well (handled in ROM1)
; ---------------------------------------------------------------------------------------------------------------------

MCLS:       XOR A                       ; Internal entry: clear everything
            JR CLSBL

CLS:        CP "#"
            JR NZ,CLSNH

            RST &30
            DW CLSHS-&8000              ; CLS # is handled in ROM1

CLSNH:      CALL SYNTAX3                ; An optional numeric argument, defaulting to zero

            CALL GETBYTE                ; 0 clears the whole screen, 1 the window
            LD E,6                      ; BLITZ record code for CLS
            CALL GRAREC                 ; Append it if RECORD is active
            LD A,C

; --- CLSBL: also the BLITZ and jump table entry, with the parameter already in A ---

CLSBL:      CP 1
            JR Z,CLU1                   ; Window only

            CALL CLU1                   ; Whole screen: clear the upper part, then fall into the lower


; ---------------------------------------------------------------------------------------------------------------------
; CLSLOWER -- clear the lower screen and select channel K
;
; If INPUT prompts have grown the lower window beyond its usual two lines, the overlap into the upper window is
; cleared first, using the upper window's colours so no coloured band is left behind.
; ---------------------------------------------------------------------------------------------------------------------

CLSLOWER:   LD HL,LWBOT
            LD A,(HL)
            DEC HL
            SUB (HL)                    ; Height of the lower window, minus one
            DEC A
            JR Z,CLSL2                  ; The usual two lines: nothing has spilled upwards

            LD A,(HL)                   ; Define a temporary window covering the overlap
            LD (WINDTOP),A
            INC HL
            LD A,(HL)                   ; LWBOT
            DEC A
            DEC HL
            LD (HL),A                   ; Shrink the lower window back to two lines
            DEC A
            LD (WINDBOT),A
            LD HL,(LWRHS)
            LD (WINDRHS),HL             ; Right and left edges together
            LD HL,(M23PAPP)
            LD (M23PAPT),HL
            LD A,(ATTRP)
            LD (ATTRT),A                ; Use the upper window's colours for the overlap
            CALL CLSWIND

CLSL2:      CALL STREAMFD               ; Channel K
            LD A,FTVLOWER
            LD (TVFLAG),A               ; Lower screen, do not clear on a keystroke, not an autolist
            CALL CLWC                   ; Clear the window and refresh the channel
            INC H
            LD (SPOSNL),HL              ; Position at the left edge, one row down
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CLSUP / CLU1 -- clear the upper screen
;
; Also resets the graphics position to the origin, which is why it runs a short calculator program.
; ---------------------------------------------------------------------------------------------------------------------

CLSUP:      LD A,1                      ; Clear the window rather than the whole screen

CLU1:       PUSH AF

            DB CALC                     ; Push graphics coordinates 0,0
            DB STKZERO
            DB STKZERO
            DB EXIT

            CALL SETESP                 ; Odd XOS/YOS values must not raise an error during a CLS
            CALL GTFCOORDS              ; Convert 0,0 through the offset and range variables
            JR C,CLU2                   ; Thin pixels: HL = X, B = Y

            LD L,C                      ; Fat pixels: C = X
            LD H,0

CLU2:       LD (XCOORD),HL
            LD A,B
            LD (YCOORD),A
            POP HL
            LD (ERRSP),HL               ; Restore the error frame saved by SETESP
            XOR A
            LD (XPTR+1),A               ; Cancel any '?' error marker
            LD (ERRNR),A
            INC A
            LD (SCRCT),A                ; One line may scroll before the next prompt
            CALL STREAMFE               ; Channel S
            POP AF
            AND A
            JR NZ,CLS2                  ; Window only

            CALL CLSE                   ; Clear the entire screen
            CALL CLWC2                  ; Refresh the channel without clearing again
            CP A                        ; Force Z so the call below is skipped

CLS2:       CALL NZ,CLWC                ; Window only: clear it and refresh the channel
            LD (SPOSNU),HL
            LD HL,FLAGS2
            RES 0,(HL)                  ; FFL2DIRTY clear: the screen is clean

; --- Clear the line pointer table: no listed line begins on any row now ---

            LD HL,LPT
            LD B,30
            XOR A

ZTEL:       LD (HL),A
            INC HL
            DJNZ ZTEL

            DEC A
            LD (LNPTR),A                ; &FF: the '>' cursor is not on screen
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CLWC / CLWC2 -- clear the current window and refresh the channel
;
; The channel's input and output addresses are rewritten from MNOP because a control code may have diverted them.
; ---------------------------------------------------------------------------------------------------------------------

CLWC:       CALL CLSWIND

CLWC2:      LD DE,(CURCHL)
            LD HL,MNOP
            LD BC,4
            LDIR                        ; Restore the standard output and input addresses
            LD HL,(WINDLHS)             ; Top left of the window, as the new print position
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CLSE -- clear the entire screen quickly
;
; Chooses the right span and fill value for the mode, then clears with stacked PUSHes.
; ---------------------------------------------------------------------------------------------------------------------

CLSE:       LD A,(MODE)
            CP MODE4COL
            JR NC,CLS1                  ; Internal modes 2 and 3

            LD H,&98                    ; End of the mode 0/1 pixel data
            LD E,0                      ; Clear it with zeros
            LD BC,&8002                 ; B = 128 groups of 16 bytes, C = 2 passes: &1800 bytes
            PUSH AF
            CALL CLSG
            POP AF                      ; The mode
            LD DE,(ATTRP)               ; Attributes are cleared to the current attribute
            LD H,&B8                    ; End of the mode 1 attributes
            LD BC,&8002                 ; &1800 bytes
            AND A
            JR NZ,CLSG                  ; Internal mode 1

            LD H,&9B                    ; Internal mode 0 has only &300 bytes of attributes
            LD BC,&3001
            JR CLSG

CLS1:       LD H,&E0                    ; Internal modes 2 and 3: clear &8000-&DFFF
            LD DE,(M23PAPP)             ; ... to the paper colour
            LD BC,&0006                 ; 256 groups of 16 bytes, 6 passes: &6000 bytes


; ---------------------------------------------------------------------------------------------------------------------
; CLSG -- fill screen memory downwards from H:00 using the stack pointer
;
; Entry:  H = the high byte of the address just past the area, E = the fill byte,
;         B = groups of 16 bytes per pass, C = passes
; Exit:   The area is filled; SP and the paging are restored.
; ---------------------------------------------------------------------------------------------------------------------

CLSG:       CALL SPSSR                  ; Save the paging and select the screen
            LD D,E                      ; DE = the fill value as a word
            DI                          ; SP is about to stop being a stack pointer
            LD (TEMPW1),SP
            LD L,0
            LD SP,HL

CLSLP:      PUSH DE
            PUSH DE
            PUSH DE
            PUSH DE
            PUSH DE
            PUSH DE
            PUSH DE
            PUSH DE                     ; 16 bytes per iteration, about 7T per byte
            DJNZ CLSLP

            DEC C
            JR NZ,CLSLP                 ; &1000 bytes per pass

            LD SP,(TEMPW1)
            EI
            JP RCURPR                   ; Restore the paging


; =====================================================================================================================
; PRINT and LPRINT
; =====================================================================================================================
;
; A print statement is a sequence of items separated by ';', ',' or '''. The separator both delimits and acts:
; a comma prints a column tab and an apostrophe a newline. A trailing separator suppresses the final newline.
; ---------------------------------------------------------------------------------------------------------------------

LPRINT:     LD C,3                      ; Stream 3: printer
            DB SKIP2LDHL

PRINT:      LD C,2                      ; Stream 2: screen
            CALL RUNFLG
            LD A,C
            LD HL,INQUFG
            SET 0,(HL)                  ; FINQUOTES: everything printed is characters, so token bytes are UDGs
            CALL C,SETSTRM
            CALL TEMPS

PRINT2:     RST &18
            CALL PRTERM
            JR Z,PRINT3                 ; An empty statement such as "PRINT :"

MPRSEPLP:   CALL PRSEPR
            RET Z                       ; A separator followed by the end of the statement: no newline

            JR NC,MPRSEPLP              ; It was a separator, so look for another

            CALL PRITEM                 ; Not a separator, so it must be an item
            CALL PRSEPR
            RET Z
            JR NC,MPRSEPLP

PRINT3:     CP ")"
            RET Z                       ; An embedded print item inside INPUT ends at the bracket, with no newline
                                        ; as in: INPUT "old:";(x);" new:";x

; --- RUNCR: print a newline if running. Also entered from INPUT. ---

RUNCR:      LD C,CC_ENTER

; --- PRCIFRN: print the character in C, but only when running ---

PRCIFRN:    CALL RUNFLG
            RET NC

            LD A,C
            RST &10
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PRSEPR -- examine and act on a print separator
;
; Exit:   Z          a separator followed by the end of the statement
;         NZ, CY     not a separator at all
;         NZ, NC     a separator with more to come
; ---------------------------------------------------------------------------------------------------------------------

PRSEPR:     RST &18
            CP ";"
            JR Z,PRSEPR3                ; Semicolon: no output of its own

            LD C,CC_COMMA
            CP ","
            JR Z,PRSEPR2                ; Comma: a column tab

            CP "'"
            SCF
            RET NZ                      ; Not a separator

            LD C,CC_ENTER               ; Apostrophe: a newline

PRSEPR2:    CALL PRCIFRN

PRSEPR3:    RST &20                     ; Step over the separator

; --- PRTERM: Z if A ends the statement ---

PRTERM:     CP ")"
            RET Z

            CP ":"
            RET Z

            CP CC_ENTER
            SCF
            CCF                         ; NC without disturbing Z
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PRITEM -- print one item
;
; Handles TAB, AT, "#stream", colour items, and general expressions of either type.
; ---------------------------------------------------------------------------------------------------------------------

PRITEM:     RST &18
            CP TOK_TAB
            JR NZ,PRITEM2

            CALL SSYNTAX6               ; TAB n

            CALL GETINT
            LD D,C
            LD A,CC_TAB
            JR ATSR4

PRITEM2:    CP TOK_AT
            JR NZ,PRITEM4

            CALL SSYNTAX8               ; AT row,column

            CALL GETBYTE
            PUSH AF                     ; Column
            CALL GETBYTE                ; C = row
            LD D,C
            POP AF
            LD E,A                      ; D = row, E = column
            DB SKIP1CP                  ; Skip the LD D,A below

; --- ATSR2: print AT with the row in A and the column in E ---

ATSR2:      LD D,A

ATSR3:      LD A,CC_AT

ATSR4:      RST &10                     ; The control code
            LD A,D
            RST &10                     ; First operand
            LD A,E
            RST &10                     ; Second operand
            RET

PRITEM4:    CALL CITEMSR                ; A colour item?
            RET NC                      ; Yes, and it has been dealt with

            CP "#"
            JP Z,PRHSH2                 ; A stream redirection part way through the statement

            CALL EXPTEXPR
            RET NC                      ; Syntax check only

            IN A,(URPORT)
            PUSH AF
            JR NZ,PRITEM5               ; Numeric

            CALL GETSTRING              ; String: unstack it and page it in
            CP A                        ; Force Z so the conversion below is skipped

PRITEM5:    CALL NZ,JPFSTRS             ; Numeric: convert to text, giving BC bytes at (DE)

            CALL PRINTSTR
            POP AF
            OUT (URPORT),A
            RET


; =====================================================================================================================
; Moving the '>' cursor through the listing
; =====================================================================================================================
;
; LPT holds one byte per screen row, non-zero where a program line begins, and LNPTR the row carrying the cursor
; (a value of &40 or more means it is not on screen). Between them the cursor keys can find the previous or next
; listed line without re-scanning the program.
; ---------------------------------------------------------------------------------------------------------------------

FUPDN:      PUSH AF                     ; The direction code: &0B up, &09 down
            CALL STREAMFE               ; Channel S
            POP BC
            CALL FUPDN2
            JP STRM0

FUPDN2:     LD A,(LNPTR)
            CP &40
            JP NC,AUTOLIST              ; No cursor on screen, so simply re-list

            LD A,B
            CP CC_UP
            JR NZ,LPD                   ; Down

; --- Cursor up ---

            LD HL,(EPPC)
            PUSH HL
            CALL FNDLINE
            LD H,D
            LD L,E                      ; HL and DE both point at the line before EPPC; DE is needed later
            LD B,(HL)
            INC HL
            LD C,(HL)                   ; BC = the previous line's number
            LD (EPPC),BC
            POP HL                      ; The old EPPC
            AND A
            SBC HL,BC
            RET Z                       ; Already at the top of the program

            PUSH DE
            RST &30
            DW EROC2                    ; Erase the old cursor; returns A and C = LNPTR, H = the LPT page
            POP DE

LPUL:       AND A
            JR Z,MWDN                   ; Already on the top row, so the window must move down

            DEC A
            ADD A,LPT\256               ; Index into LPT (which lies wholly within one page)
            LD L,A
            SUB LPT\256
            LD B,(HL)
            INC B
            DJNZ LPC                    ; Found a row that starts a line

            JR LPUL


; ---------------------------------------------------------------------------------------------------------------------
; MWDN -- the cursor moved above the top row, so scroll the window down
;
; The new line's height is measured first by printing it with output discarded, so the window is scrolled by exactly
; the right number of rows.
; ---------------------------------------------------------------------------------------------------------------------

MWDN:       PUSH DE                     ; Start of the new EPPC line

            INC A                       ; A = 1
            LD (DMPFG),A                ; Discard output: this print is only to measure
            LD HL,(SPOSNU)
            PUSH HL
            LD HL,(WINDLHS)             ; L = left edge
            LD A,&41
            SUB C                       ; Rows from the top of the old cursor position
            LD H,A
            LD (SPOSNU),HL              ; Start on a high row, past any window bottom, so nothing scrolls

            EX DE,HL                    ; HL -> the first character
            CALL IOUTLNC                ; Dummy print to find the height
            XOR A
            LD (DMPFG),A
            LD HL,WINDTOP
            LD A,(WINDBOT)
            SUB (HL)
            INC A
            LD H,A                      ; Window height
            LD A,(SPOSNU+1)             ; Row the dummy print finished on
            SUB &40                     ; Rows the line occupied
            CP H
            JR C,MWDN2                  ; Shorter than the window

            LD A,H                      ; Longer: scroll by the whole window

MWDN2:      POP HL
            LD (SPOSNU),HL
            CALL EDRSADN                ; Scroll down A rows
            LD HL,(WINDLHS)
            LD (SPOSNU),HL              ; Print at the top left
            POP HL                      ; Start of the line

; --- IOUTLNC / IOUTLN / IOPCL: print one line with indenting enabled ---

IOUTLNC:    CALL SPACAN                 ; Reset the indent state first

IOUTLN:     LD BC,OUTLINC

IOPCL:      LD A,1
            LD (INDOPFG),A
            CALL BCJUMP                 ; Call (BC) with indented output on

IOPOF:      XOR A
            LD (INDOPFG),A
            RET

OUTLINC:    RST &30
            DW OUTLINE-&8000


; ---------------------------------------------------------------------------------------------------------------------
; LPD -- cursor down
; ---------------------------------------------------------------------------------------------------------------------

LPD:        LD HL,(EPPC)
            PUSH HL
            CALL ADVEPPC                ; Advance EPPC one line; the new number comes back in DE
            POP HL
            AND A
            SBC HL,DE
            RET Z                       ; Unchanged, so this was the last line

            ADD HL,DE
            PUSH HL                     ; The old EPPC
            LD DE,(WINDTOP)
            LD A,D                      ; Bottom
            SUB E
            INC A
            PUSH AF                     ; The row after the last, relative to the window
            RST &30
            DW EROC2                    ; Erase the old cursor; A and C = LNPTR, H = the LPT page
            POP DE                      ; D = the row after the last

LPDL:       INC A
            CP D
            JR NC,MWUP                  ; Off the bottom, so the window must scroll up

            ADD A,LPT\256
            LD L,A
            SUB LPT\256
            LD B,(HL)                   ; Zero if no line begins on this row
            INC B
            DEC B
            JR Z,LPDL

            POP HL                      ; Discard the old EPPC: no redraw needed

; --- LPC: draw the cursor on row A ---

LPC:        LD C,A
            LD A,(WINDTOP)
            ADD A,C
            LD (LNPTR),A                ; Record the row now carrying the cursor
            LD A,C
            LD E,5                      ; Column 5, just left of the line number
            CALL ATSR2
            RST &30
            DW PRLCU-&8000


; ---------------------------------------------------------------------------------------------------------------------
; MWUP -- the cursor moved below the bottom row, so scroll the window up
;
; The old current line is reprinted first: it may straddle the bottom of the screen, and printing it again forces
; the scroll to happen before the new line is drawn.
; ---------------------------------------------------------------------------------------------------------------------

MWUP:       CALL ADVSTOP                ; Move the top-of-screen line down by one
            XOR A
            LD (OVERT),A                ; OVER 0, so overprinting looks right
            LD E,A                      ; Column 0
            LD HL,SCRCT
            LD (HL),E                   ; Suppress the scroll prompt
            LD HL,WINDTOP
            LD A,(LNPTR)
            SUB (HL)
            CALL ATSR2
            POP HL                      ; The old EPPC
            CALL FNDLINE
            LD A,(OLDSPCS)
            LD (NXTSPCS),A              ; Restore the indent state so the second print matches the first
            CALL IOUTLN
            LD A,CC_ENTER
            RST &10
            JR IOUTLN                   ; Print the new EPPC, which will carry the '>' cursor


; ---------------------------------------------------------------------------------------------------------------------
; REALN -- make a stored line number refer to a line that exists
;
; Entry:  HL -> a two-byte system variable holding a line number
; Exit:   The variable holds that line, or the first line after it.
; ---------------------------------------------------------------------------------------------------------------------

REALN:      LD A,(HL)
            INC HL
            PUSH HL
            LD H,(HL)
            LD L,A                      ; HL = the line number
            JR ADVAC


; ---------------------------------------------------------------------------------------------------------------------
; ADVSTOP / ADVEPPC / ADVAN -- advance a stored line number to the next line
;
; Entry:  ADVAN with HL -> the variable; the two named entries choose SDTOP or EPPC.
; Exit:   DE = the new line number; HL is unchanged.
; ---------------------------------------------------------------------------------------------------------------------

ADVSTOP:    LD HL,SDTOP
            JR ADVAN

ADVEPPC:    LD HL,EPPC

ADVAN:      LD A,(HL)
            INC HL
            PUSH HL
            LD H,(HL)
            LD L,A
            INC HL                      ; Look for the line after this one

ADVAC:      CALL FNDLINE                ; Its address, or that of the program end
            CALL LNNM                   ; Its number, or the previous line's at the end of the program
            POP HL
            LD (HL),D
            DEC HL
            LD (HL),E
            RET

                                        ; Routines in this file: TABSR, CLS, PRINT, FUPDN, IOUTLN, PRLCU, ZTENTS,
                                        ; LNLEN, ATSR, REALN, ADVAN
