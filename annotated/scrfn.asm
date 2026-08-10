; =====================================================================================================================
; SCRFN.ASM -- COPY, the SCREEN$ function, program listing output, and the listing indent machinery
; =====================================================================================================================
;
; SCREEN$
; -------
; SCREEN$(line,column) has to work backwards: read the pixels at that cell and find which character they came from.
; The cell is first normalised into SCRNBUF as a plain eight-by-eight bitmap -- which in modes 2 and 3 means
; reducing multi-bit pixels back to one bit each, taking the cell's top-left pixel as the background colour -- and
; then compared against the character set.
;
; SCREENSR does the comparison, but starts with bytes 3 and 4 rather than byte 0. Those are the middle scans, where
; characters differ most, so nearly every non-match is rejected in two compares instead of eight.
;
; The search covers codes 32 to 127 from the main character set and 128 to 168 from the UDG area. Codes outside
; those ranges, and cells that match nothing, return the empty string.
;
; PRETTY LISTING
; --------------
; When LISTFLG is non-zero, LIST indents block structures. The indent is tracked by four bytes -- CURSPCS and
; NXTSPCS, plus a "then" pair for the short IF form -- and SPACES adjusts them from the first token of each
; statement:
;
;     DO, IF (long), DEF PROC, FOR         indent from the next statement onwards
;     LOOP, END PROC, END IF, NEXT         cancel the indent for this statement and later ones
;     EXIT IF, ELSE (long), LOOP IF        cancel it for this statement only
;     IF (short), ON                       indent later statements on this line only
;     ELSE (short)                         cancels part of the short-IF indent
;
; The distinction between the long and short forms of IF and ELSE is set at syntax-check time; see
; docs/tokenized-program-format.md.
;
; THE LISTING CURSOR
; ------------------
; LPT is a 30-entry table, one per screen line, recording which lines carry a BASIC line number. It is what lets the
; up and down cursor keys move between program lines rather than screen lines, and STENTS scrolls it in step with
; the screen.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; COPY -- COPY, or COPY SCREEN$
;
; Both forms go through a vector, DMPV, so a printer driver can install itself. A is 0 for a text copy and &AF for a
; graphics copy; if no vector is installed the command does nothing.
; ---------------------------------------------------------------------------------------------------------------------

COPY:      CP &FF
           JR NZ,GRCOPY

; --- COPY SCREEN$ ---

           RST &20                          ; Step over the &FF function prefix
           CP CHRSTOK
           JP NZ,NONSENSE

           RST &20

GRCOPY:    CALL CHKEND

JGCOPY:    DB SKIP1LDA                      ; With the XOR A below as its operand this reads LD A,&AF

JTCOPY:    XOR A

           LD HL,(DMPV)

JPOPT:     INC H
           DEC H
           RET Z                            ; No vector installed

           JP (HL)                          ; A = 0 for a text copy, &AF for graphics


; ---------------------------------------------------------------------------------------------------------------------
; IMSCREENS -- the SCREEN$(line,column) function
;
; Returns a one-character string, or the empty string if the cell does not match any known character.
; ---------------------------------------------------------------------------------------------------------------------

IMSCREENS: CALL EXB2NUMB                    ; Check the two coordinates; CY if running
           RET NC

           LD A,(UWRHS)
           INC A
           LD L,A                           ; The column limit
           LD A,(UWBOT)
           ADD A,3                          ; Plus the two lines of the lower screen
           LD H,A                           ; The line limit
           CALL GETCP                       ; The position, in DE
           CALL IMSCSR
           JP NC,CWKSTK                     ; Found: stack a one-byte string

           XOR A
           JP STACKA                        ; Not found: the empty string


; ---------------------------------------------------------------------------------------------------------------------
; IMSCSR -- read one character cell and identify it
;
; Entry:  DE = the line and column.
; Exit:   CY if identified, with the code at (HL) and BC = 1; otherwise NC and A = 0.
;
; DEVICE is forced to the upper screen for the duration, since ANYDEADDR would otherwise resolve the position
; against whichever stream is current.
; ---------------------------------------------------------------------------------------------------------------------

IMSCSR:    LD HL,DEVICE
           LD A,(HL)
           LD (HL),0
           PUSH AF
           PUSH HL
           CALL ANYDEADDR                   ; DE = the screen address; CY if 6-pixel characters are in use, and
                                            ; then NZ or Z for an odd or even column
           POP HL
           POP BC
           LD (HL),B                        ; Restore DEVICE
           EX DE,HL
           LD DE,SCRNBUF                    ; The buffer holds the cell in a standard eight-by-eight form
           PUSH AF
           LD A,(MODE)
           CP 2
           JR C,SCM01

; --- Modes 2 and 3: reduce multi-bit pixels to one bit each ---

           POP AF
           PUSH AF
           CALL CHARCOMP                    ; Compress the cell, treating its top-left pixel as the background
           POP AF
           JR NC,SCBMCH                     ; Eight-pixel characters, so the buffer is already aligned

           LD BC,&087E                      ; Eight bytes to rotate one pixel, and a mask that trims the two edge
                                            ; bits which may hold parts of the neighbouring characters
           LD HL,SCRNBUF
           JR Z,SC6EAL

SC6OAL:    LD A,(HL)                        ; Odd column: rotate left to centre the six pixels
           RLCA
           AND C
           LD (HL),A
           INC HL
           DJNZ SC6OAL

           JR SCBMCH

SC6EAL:    LD A,(HL)                        ; Even column: rotate right
           RRCA
           AND C
           LD (HL),A
           INC HL
           DJNZ SC6EAL

           JR SCBMCH

; --- Modes 0 and 1 are already one bit per pixel, so the cell just needs copying, inverted if its top-left pixel
;     is set ---

SCM01:     POP AF
           LD BC,&0800                      ; Eight bytes, no inversion
           CALL SREAD
           RLA
           JR NC,SCM01L

           DEC C                            ; The mask becomes &FF, inverting every byte

SCM01L:    CALL SREAD
           XOR C
           LD (DE),A
           CALL NXTDOWN                     ; Drop to the next scan
           INC DE
           DJNZ SCM01L

; --- Match the buffer against the character set ---

SCBMCH:    LD HL,(CHARS)
           INC H                            ; CHARS is biased low by 256, so this reaches code 32
           LD A,96                          ; Codes 32 to 127
           CALL SCREENSR
           JR NC,SCRNFND

           LD HL,(UDG)                      ; UDG points at code 144
           LD BC,-128
           ADD HL,BC                        ; Back up to code 128
           LD A,41                          ; Codes 128 to 168
           CALL SCREENSR
           RET C                            ; Nothing matched

UDGFND:    ADD A,96                         ; 1 to 41 becomes 97 to 137

SCRNFND:   ADD A,32                         ; And then 128 to 168; the main set's 1 to 96 becomes 32 to 127
           LD BC,1
           LD HL,TEMPW1
           LD (HL),A
           RET                              ; NC: found


; ---------------------------------------------------------------------------------------------------------------------
; SCREENSR -- search a run of character bitmaps for one matching SCRNBUF
;
; Entry:  A = how many characters to check, HL -> the first bitmap.
; Exit:   NC with A = the index of the match, counting from 0; CY if nothing matched.
;
; Bytes 3 and 4 are compared first because they are the scans through the middle of a character, where the set
; varies most. Only when both agree is the full eight-byte comparison worth doing.
; ---------------------------------------------------------------------------------------------------------------------

SCREENSR:  LD B,A
           EX AF,AF'                        ; Keep the original count for the index calculation
           LD DE,SCRNBUF+4
           LD A,(DE)
           LD C,A                           ; C = byte 4 of the target
           DEC DE
           LD A,(DE)                        ; A = byte 3 of the target
           INC HL
           INC HL
           INC HL                           ; Point at byte 3 of the first bitmap
           LD DE,8                          ; The step to the next character
           DB SKIP1CP                       ; Skip the ADD HL,DE on the first pass

SCREENLP:  ADD HL,DE
           CP (HL)
           JR Z,SCREEN2

SCREEN1:   DJNZ SCREENLP

           SCF
           RET

SCREEN2:   LD A,C
           INC HL
           CP (HL)                          ; Byte 4 as well
           DEC HL
           LD A,(HL)
           JR NZ,SCREEN1

           PUSH HL                          ; Both middle bytes agree, so check all eight
           PUSH BC
           DEC HL
           DEC HL
           DEC HL                           ; Byte 0 of the bitmap
           LD DE,SCRNBUF
           LD B,8

FULCKLP:   LD A,(DE)
           CP (HL)
           JR Z,FULCK1

           POP BC
           POP HL
           LD A,(HL)
           LD DE,8
           JR SCREEN1                       ; A near miss; keep looking

FULCK1:    INC HL
           INC DE
           DJNZ FULCKLP

           POP BC
           POP HL
           EX AF,AF'
           SUB B                            ; The first character gives 0, the last gives the count minus one
           RET                              ; NC: matched


; =====================================================================================================================
; LSTR1 -- the second half of LIST
; =====================================================================================================================
;
; Prints lines until the last one asked for has gone past. During an AUTOLIST it then keeps going to fill the rest
; of the screen, so the display never has a ragged bottom edge.
; ---------------------------------------------------------------------------------------------------------------------

LSTR1:     CALL SPACAN

LSTLNL:    CALL OUTLINE
           RET C                            ; End of program

           RST &10                          ; A carriage return between lines
           CALL R1OFRD
           LD B,A
           CALL CHKHL
           INC HL
           CALL R1OFRD
           LD C,A
           DEC HL                           ; BC = the number of the next line
           EX DE,HL
           LD HL,(LAST)                     ; The last line requested; EPPC during an AUTOLIST
           AND A
           SBC HL,BC
           EX DE,HL
           JR NC,LSTLNL

           LD A,(TVFLAG)
           AND FTVAUTOLIST
           RET Z

           LD A,(WINDBOT)                   ; Keep listing until the screen is full
           LD E,A
           LD A,(SPOSNU+1)
           SUB E
           JR C,LSTLNL

           RET


; ---------------------------------------------------------------------------------------------------------------------
; OUTLINE -- print one program line
;
; Exit:   CY if the program terminator was reached; otherwise NC with the line printed but no carriage return.
;
; The current line, the one EPPC names, gets a ">" marker instead of the usual space after its number. LPT records
; which screen line the number landed on, so the cursor keys can navigate by program line.
; ---------------------------------------------------------------------------------------------------------------------

OUTLINE:   CALL R1OFRD                      ; The line number's high byte
           LD B,A
           ADD A,1
           RET C                            ; &FF is the program terminator

           INC HL
           CALL R1OFRD
           LD C,A                           ; BC = the line number
           LD A,(NXTSPCS)
           LD (OLDSPCS),A                   ; If this line is the last on the screen it will be printed twice, so
                                            ; the indent state has to be restorable
           XOR A
           EX DE,HL
           LD HL,(EPPC)
           SBC HL,BC                        ; NC if this line is at or before the current one
           EX DE,HL                         ; NC with Z means this is the current line
           PUSH AF
           JR NC,OUTLN2

           INC A

OUTLN2:    LD (BCREG),A                     ; 1 once the current line has been printed
           CALL PRNUMB2                     ; The line number, right-aligned in five columns
           LD A,(DEVICE)
           AND A
           JR NZ,OUTLN22                    ; Not the upper screen, so there is no LPT to maintain

           LD A,(WINDTOP)
           LD E,A
           LD A,(SPOSNU+1)
           SUB E                            ; The screen line relative to the window
           ADD A,LPT\256
           LD E,A
           LD D,LPT/256
           LD A,D
           LD (DE),A                        ; Mark this screen line as carrying a line number

OUTLN22:   INC HL
           INC HL
           INC HL                           ; Step over the number and the length word
           POP AF
           JR NZ,OUTLN3

           CALL PRLCU                       ; The current line gets an inverse ">"

; --- OUTLN25: also entered by EDPRNT, which has already positioned the cursor ---

OUTLN25:   EX DE,HL
           LD HL,FLAGS
           SET 0,(HL)                       ; Suppress the leading space before the first token
           EX DE,HL
           JR OUTLN4

OUTLN3:    LD A," "
           RST &10                          ; A space also sets the no-leading-space flag

OUTLN4:    XOR A
           LD (NXTHSPCS),A
           LD A,(LISTFLG)
           AND A
           CALL R1OFRD                      ; The first character of the line
           PUSH HL
           CALL NZ,SPACES                   ; Apply the indent, if pretty listing is on
           POP HL
           EX DE,HL                         ; DE = the line pointer
           XOR A
           LD (INQUFG),A

; --- The character loop ---

OUTLNLP:   LD HL,(XPTR)
           AND A
           SBC HL,DE
           CALL Z,PRFLQUERY                 ; A flashing "?" marks where a syntax error was found
           CALL OPCURSOR
           EX DE,HL
           CALL R1OFFCL
           DW RDCN                          ; LD A,(HL) followed by CALL NUMBER, with ROM1 paged out
           LD (LSPTR),HL                    ; The cursor output routine needs to know where we are
           INC HL
           CP &0D
           RET Z

           EX DE,HL

           CP ":"
           JR NZ,OUTCH2

; --- A statement separator: start a new indented line, unless it is inside quotes or this is INPUT mode ---

           LD H,A
           LD A,(LISTFLG)
           AND A
           LD A,H
           JR Z,OUTCH3                      ; No pretty listing

           LD A,(INQUFG)
           RRCA
           LD A,H
           JR C,OUTCH3                      ; Inside quotes

           LD A,(FLAGX)
           AND FFLXINPUT
           LD A,H
           JR NZ,OUTCH3                     ; INPUT mode

; --- On the lower screen use TAB 0, which overwrites the rest of the line with spaces; on the upper screen a plain
;     carriage return is quicker. Either way, follow with six spaces to indent the continuation. ---

           LD A,(INDOPFG)
           PUSH AF
           XOR A
           LD (INDOPFG),A                   ; So the TAB fill does not itself get indented
           LD A,(DEVICE)
           DEC A
           LD A,&0D
           JR NZ,TABS2

           LD A,&17                         ; TAB
           RST &10
           XOR A
           RST &10
           XOR A

TABS2:     RST &10
           LD B,6
           CALL OPBSP
           POP AF
           LD (INDOPFG),A

           EX DE,HL
           CALL R1OFRD                      ; The character after the colon
           EX DE,HL
           CALL SPACES                      ; Recompute the indent from the new statement's first token
           JR OUTLNLP

OUTCH2:    CP &22
           JR NZ,OUTCH3

           LD HL,INQUFG
           INC (HL)                         ; Flip bit 0: inside or outside quotes

OUTCH3:    RST &10
           JR OUTLNLP


; ---------------------------------------------------------------------------------------------------------------------
; STENTS -- scroll the listing line table in step with the screen
;
; Entry:  A = the number of lines to scroll by, D = 1 to scroll up, anything else to scroll down.
;
; LPT has one entry per screen line, non-zero where a BASIC line number was printed. Scrolling up also moves the
; recorded cursor line, LNPTR.
; ---------------------------------------------------------------------------------------------------------------------

STENTS:    LD L,A
           LD A,30
           SUB L
           LD C,A                           ; BC = 30 minus the scroll distance, the bytes to move
           XOR A
           LD B,A
           LD H,A                           ; HL = the scroll distance
           LD A,L

           DEC D
           JR Z,PTU

; --- Scrolling down ---

           LD DE,LPT+29
           PUSH DE
           EX DE,HL
           SBC HL,DE                        ; HL = LPT+29 minus the distance
           POP DE
           LDDR
           LD B,A
                                            ; The cursor's new line is set when the line is reprinted
           XOR A

PDCL:      LD (DE),A                        ; The vacated entries become zero
           DEC DE
           DJNZ PDCL

           RET

; --- Scrolling up ---

PTU:       LD DE,LPT
           ADD HL,DE
           LDIR
           LD B,A
           LD HL,LNPTR
           LD A,(HL)
           SUB B
           LD (HL),A                        ; The cursor's line moves up with the text
           XOR A

PTCL:      LD (DE),A
           INC DE
           DJNZ PTCL

           RET


; ---------------------------------------------------------------------------------------------------------------------
; SPACES -- update the listing indent from the first token of a statement
;
; Entry:  A = the token.
;
; Four bytes are involved: CURSPCS and NXTSPCS hold the indent for this statement and the next, and a second pair
; holds the equivalent for the short IF form, which only applies to the rest of the current line. LISTFLG holds the
; indent step.
;
; SPACES4 then emits the accumulated indent, capped so that at least six columns of text remain, and skipped
; entirely if the window is ten columns or narrower.
; ---------------------------------------------------------------------------------------------------------------------

SPACES:    LD HL,NXTSPCS
           PUSH HL
           LD B,(HL)
           INC HL
           LD (HL),B                        ; Current spaces = next spaces
           INC HL
           LD B,(HL)
           INC HL
           LD (HL),B                        ; And the same for the short-IF pair
           POP HL

           CP TOK_DO
           JR Z,INCSPCS

           CP TOK_LIF
           JR Z,INCSPCS

           CP TOK_DEFPROC
           JR Z,INCSPCS

           CP TOK_FOR
           JR Z,INCSPCS                     ; These four indent from the next statement onwards

           CP TOK_LOOP
           JR Z,DECSPCS

           CP TOK_ENDPROC
           JR Z,DECSPCS

           CP TOK_ENDIF
           JR Z,DECSPCS                     ; These, and NEXT below, cancel the indent for this statement and later

           CP TOK_NEXT
           JR NZ,SPACES2

DECSPCS:   CALL SPACESR                     ; Current = current minus the step
           LD B,(HL)
           DEC HL
           LD (HL),B                        ; Next = current
           JR SPACES4

SPACES2:   CP TOK_EXITIF
           JR Z,SPACES3

           CP TOK_LELSE
           JR Z,SPACES3

           CP TOK_LOOPIF
           JR Z,SPACES3                     ; These cancel the indent for this statement only

           INC HL
           INC HL                           ; Point at the short-IF pair, which cancels at end of line
           CP TOK_ELSE
           JR NZ,SPACES35                   ; A short ELSE cancels part of that, as does ON

SPACES3:   CALL SPACESR
           JR SPACES4

SPACES35:  CP TOK_SIF
           JR Z,INCSPCS                     ; A short IF indents the later statements on this line

           CP TOK_ON
           JR NZ,SPACES4

INCSPCS:   LD A,(LISTFLG)
           ADD A,(HL)
           LD (HL),A
           DB SKIP1CP                       ; CP &3E, then LD B,&FE: skips over INDOPEN's LD A,6

; --- INDOPEN: called by the print routine when a line fills, to indent the continuation ---

INDOPEN:   LD A,6
           DB SKIP1CP                       ; Skips the XOR A below

SPACES4:   XOR A
           LD HL,CURSPCS
           ADD A,(HL)
           INC HL
           INC HL
           ADD A,(HL)                       ; The total of both indent counters
           RET Z

           LD B,A
           LD HL,(WINDRHS)
           LD A,L
           SUB H                            ; The window width minus one
           CP 10
           RET C                            ; Too narrow to indent at all

           SUB 5
           CP B
           JR NC,SPCS5                      ; There is room for the full indent

           LD B,A                           ; Otherwise indent by the width minus six

SPCS5:     JP OPBSP

SPACESR:   INC HL
           LD A,(LISTFLG)
           LD B,A
           LD A,(HL)
           SUB B
           LD (HL),A
           RET NC

           LD (HL),&00                      ; Never let the indent go negative
           RET


; =====================================================================================================================
; EDPTR2 -- reprint the line being edited on the lower screen
; =====================================================================================================================
;
; Called after every keystroke. The whole line is printed afresh, then any characters left over from a longer
; previous version are blanked with spaces -- which is what the EDBL loop does, comparing the new end-of-line
; position against the old one.
;
; A private error handler is installed at EDPE so that a line too malformed to print does not abort the editor; it
; sounds the warning buzzer and unwinds cleanly.
; ---------------------------------------------------------------------------------------------------------------------

EDPTR2:    CALL TEMPS
           CALL POFETCH
           PUSH DE                          ; Save the screen position so repeated calls all start in the same
                                            ; place rather than running on from each other
           LD A,(WINDTOP)
           LD (TEMPB2),A
           LD HL,TVFLAG
           RES 5,(HL)                       ; No need to clear the lower screen on the next keystroke
           RES 3,(HL)                       ; No need to copy the line to the lower screen
           LD HL,(ERRSP)
           PUSH HL
           LD HL,EDPE
           PUSH HL
           LD (ERRSP),SP
           CALL SETDE                       ; DE = the start of the edit line or the INPUT line
           LD HL,(OLDPOS)
           PUSH HL                          ; Where the line ended last time
           EX DE,HL
           LD BC,OUTLN25
           LD A,(FLAGX)
           AND FFLXINPUT
           JR NZ,EDIM                       ; INPUT mode is never indented

           LD A,(HL)
           CP &0D
           JR Z,EDCOP                       ; An empty line

           CALL SPACAN
           CALL IOPCL                       ; Print the line with indentation
           CP A                             ; Z

EDIM:      CALL NZ,BCJUMP                   ; Otherwise print it through OUTLN25

EDCOP:     EX DE,HL
           CALL OPCURSOR                    ; Print the cursor if it belongs at the end of the line
           CALL TEMPS
           CALL POFETCH
           POP HL                           ; The old end-of-line position
           CALL LSASR                       ; Adjust it if the lower screen has scrolled
           PUSH DE                          ; The new end-of-line position
           PUSH HL

; --- Blank anything the previous, longer version left behind ---

EDBL:      POP BC
           CALL POFETCH
           EX DE,HL
           AND A
           SBC HL,BC                        ; Normally the new position is further on, so NC; a deletion gives CY
           JR NC,EDBE

           PUSH BC
           LD A," "
           CALL FONOP
           JR EDBL

; --- Errors during the reprint arrive here ---

EDPE:      CALL WARNBZ
           CALL POFETCH
           DB SKIP2LDHL                     ; LD HL,nn swallows the POP DE below

EDBE:      POP DE                           ; The final end-of-line position
           POP HL                           ; The error handler address, discarded

           POP HL
           LD (ERRSP),HL
           LD (OLDPOS),DE
           POP HL                           ; The original screen position
           CALL LSASR
           CALL POSTORE
           XOR A
           LD (XPTR+1),A                    ; Clear any error marker
           RET


; ---------------------------------------------------------------------------------------------------------------------
; LSASR -- adjust a stored screen row if the lower screen has changed size
;
; The lower screen grows upwards as the edited line wraps, so a row recorded before the growth is now one line too
; low. TEMPB2 holds WINDTOP as it was when EDPTR2 started.
; ---------------------------------------------------------------------------------------------------------------------

LSASR:     LD A,(TEMPB2)
           LD B,A
           LD A,(WINDTOP)
           SUB B                            ; Negative if the lower screen has expanded upwards
           ADD A,H
           LD H,A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CUOPP -- the editor's cursor output routine, which also records the cursor's screen position
; ---------------------------------------------------------------------------------------------------------------------

CUOPP:
           LD BC,(SPOSNL)
           LD HL,(KPOS)
           AND A
           SBC HL,BC
           JR NZ,CUOP2

           LD HL,(LSPTR)
           LD (KCUR),HL
           PUSH AF
           CALL OPCUR2                      ; Print the new cursor before the old one disappears, so the line is
           POP AF                           ; never briefly seen one character short

CUOP2:     JP FONOP


; ---------------------------------------------------------------------------------------------------------------------
; OPCURSOR -- print the cursor if DE is where the cursor belongs
;
; Entry:  DE = the current position within the line being printed.
;
; The comparison has to include the page, since the edit line and the program can be in different pages and two
; different addresses can share the same 16-bit value.
; ---------------------------------------------------------------------------------------------------------------------

OPCURSOR:  LD HL,(KCUR)
           AND A
           SBC HL,DE
           RET NZ                           ; Not the cursor's position

           IN A,(URPORT)
           LD H,A
           LD A,(KCURP)
           XOR H
           AND &1F
           RET NZ                           ; Right address, wrong page

           LD HL,(SPOSNL)
           LD (KPOS),HL                     ; Remember where the cursor was drawn

OPCUR2:    LD HL,(KURV)
           CALL JPOPT                       ; A user cursor routine may be installed

           LD HL,(KURCHAR)
           LD A,(FLAGS2)
           AND FFL2CAPS
           LD A,L
           JR Z,PRINVERT                    ; Caps lock off: the lower-case cursor

           LD A,H
           JR PRINVERT


; ---------------------------------------------------------------------------------------------------------------------
; PRLCU / PRFLQUERY / PRINVERT -- print a character in inverse video
;
; PRLCU prints the ">" that marks the current line; PRFLQUERY prints the "?" that marks a syntax error.
;
; PRINVERT goes through FONOP rather than RST &10 because an inverse character may be printed in the middle of a
; control code and its parameter, when the channel address has been changed. It also forces "in quotes" and the
; UDG flag so that a user-defined cursor character is drawn as a UDG rather than as a block graphic.
; ---------------------------------------------------------------------------------------------------------------------

PRLCU:     LD A,(SPOSNU+1)
           LD (LNPTR),A                     ; Remember which screen line the cursor marker is on
           LD A,(LNCUR)
           DB SKIP1CP                       ; CP &3E, then CCF: skips the LD A,"?" below

PRFLQUERY: LD A,"?"

PRINVERT:  LD B,A
           PUSH HL
           LD HL,PFLAGT
           LD A,(HL)
           PUSH AF
           SET 2,(HL)                       ; INVERSE 1
           LD A,(INVERT)
           PUSH AF
           LD A,(INQUFG)
           PUSH AF
           LD A,(BGFLG)
           PUSH AF
           LD A,&FF
           LD (INQUFG),A                    ; So a cursor character in the UDG range is drawn as a UDG
           LD (INVERT),A
           LD (BGFLG),A
           LD A,B
           PUSH DE
           CALL FONOP
           POP DE
           POP AF
           LD (BGFLG),A
           POP AF
           LD (INQUFG),A
           POP AF
           LD (INVERT),A
           POP AF
           LD (PFLAGT),A
           POP HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; PRAREG / PRNUMB1 / PRNUMB2 -- print an integer
;
;   PRAREG   A as one to three digits, no padding. Used for the STAT and ERROR numbers in reports.
;   PRNUMB1  BC with no padding. Used for line numbers in reports; values from &FF00 up print as 0, which is what
;            an edit-line "line number" comes out as.
;   PRNUMB2  BC padded to five characters with leading spaces. Used for line numbers in listings.
;
; Digits are produced by repeated addition of a negative power of ten from SUBTAB. E carries the character used for
; a leading zero: a space, or nothing at all, until the first significant digit switches it to "0".
;
; Uses BC, DE and AF; HL is preserved.
; ---------------------------------------------------------------------------------------------------------------------

PRAREG:    LD C,A
           LD B,0

PRNUMB1:   LD E,0                           ; No leading spaces
           LD A,B
           INC A
           JR NZ,PRNUMBC

           LD C,A
           LD B,A
           DB SKIP2LDNN                     ; LD (nn),HL swallows the LD E,&20 below

PRNUMB2:   LD E,&20                         ; Pad with leading spaces

PRNUMBC:   PUSH HL
           PUSH BC
           LD HL,SUBTAB

PRNUOLP:   LD C,(HL)
           INC HL
           LD B,(HL)
           INC HL
           EX (SP),HL                       ; HL = the number
           LD A,L
           INC C
           DEC C
           JR Z,PRNTNO1                     ; A zero low byte terminates the table: this is the units digit

           XOR A

PRNUILP:   INC A
           ADD HL,BC                        ; BC holds a negative power of ten
           JR C,PRNUILP

           SBC HL,BC                        ; One too many, so put it back
           DEC A
           JR Z,PRNTNO2                     ; A zero digit leaves the padding character alone

PRNTNO1:   LD E,&30                         ; After the first significant digit, zeros print as "0"

PRNTNO2:   ADD A,E
           CALL NZ,&0010                    ; Print, unless E is zero and the digit is suppressed entirely
           EX (SP),HL                       ; HL = the table pointer again
           INC C
           DEC C
           JR NZ,PRNUOLP

           POP HL
           POP HL
           RET

                                            ; OPCURSOR, PRLCU, PRINVERT, STENTS, PRAREG,
                                            ; PRNUMB
