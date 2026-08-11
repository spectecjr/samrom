; =====================================================================================================================
; TPRINT.ASM -- the top of the print path: ASCII characters, tokens, UDGs, and the control codes
; =====================================================================================================================
;
; Everything printed to any stream arrives here. A character is dispatched by its code:
;
;     &00-&1F   a control code, handled by PRCRLCDS through a displacement table
;     &20-&7F   an ASCII character, whose bitmap is looked up in CHARS
;     &80-&FF   either a keyword token or a graphic character, depending on context
;
; The actual pixel-pushing happens further down, in endprint.asm; this file finds the bitmap and decides where it
; goes. The two are separated by the PATOUT vector, so a program can substitute its own renderer.
;
; TOKENS VERSUS GRAPHICS
; ----------------------
; Codes &85 upwards are keyword tokens when listing a program and graphic characters when printing a string. PRGR80
; distinguishes them by INQUFG and the INPUT-line flag: inside quotes, or in an INPUT line, they are graphics.
; Codes &80 to &84 are always graphics.
;
; MESSAGE COMPRESSION
; -------------------
; Keywords, error messages and function names are all stored the same way: as runs of characters with bit 7 set on
; the last character of each, so no lengths or pointers are needed. Bytes below &20 within a message are
; compression codes standing for whole common words, which POMSR3 expands by calling itself recursively against
; COMPLIST. A compressed word cannot itself contain compression codes, so the recursion is only ever one deep.
;
; Whether a token prints with a leading space, a trailing space, both or neither depends on which list it came from
; -- POBTL, POTRNL and POMSP2 each set a different pair of flags before joining POGEN.
;
; DOUBLE HEIGHT
; -------------
; A CSIZE height of 16 or more selects double-height characters. DBCHAR expands the eight-byte bitmap into sixteen
; bytes by duplicating each scan, and ENDOUTP then prints it as two ordinary characters one above the other, with
; DHADJ shifting the second one down eight scans.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; PROM1 -- the main print entry: dispatch on the character code
; ---------------------------------------------------------------------------------------------------------------------

PROM1:     CP &20
           JP C,PRCRLCDS                    ; A control code

           CP &80
           JP NC,PRGR80                     ; A token or a graphic

PRASCII:   LD DE,(CHARS)
           LD HL,FLAGS
           SET 0,(HL)                       ; Remember that a space was just printed
           CP &20
           JR Z,PRINTMN1

           RES 0,(HL)

PRINTMN1:  LD L,A
           LD H,0
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL                        ; Eight bytes per character
           ADD HL,DE                        ; HL -> the bitmap

IOPENT:    LD (OPCHAR),A                    ; LPRINT reads the code from here
           LD B,A


; ---------------------------------------------------------------------------------------------------------------------
; NLENTRY -- wrap to a new line if the print position has run past the right margin, then print the character
;
; Entry:  HL -> the bitmap, B = the character code.
;
; A print position one past the right margin means the line filled naturally; anything further means a carriage
; return was printed. The distinction matters during a listing, because a naturally wrapped line gets its
; continuation indented (INDOPEN) while an explicit newline does not.
; ---------------------------------------------------------------------------------------------------------------------

NLENTRY:   CALL POFETCH                     ; DE = the column and row, A = the right margin
           CP E
           JR NC,PRNONWLN                   ; Still within the margin

           DEC E
           SUB E                            ; Z if exactly one past the margin, so the line simply filled
           LD C,A
           PUSH BC
           LD E,&FF                         ; Column &FF marks this as a recursive newline
           LD A,(DEVICE)
           ADD A,&FE                        ; CY if the device is the printer
           PUSH HL
           CALL PRENTER
           POP HL
           POP BC
           LD A,(INDOPFG)
           AND A
           JR Z,NLENTRY                     ; No indentation wanted, so this is not a listing

           LD A,C
           AND A
           JR NZ,NLENTRY                    ; A carriage return was used, so no indent

           PUSH BC
           CALL INDOPEN                     ; The line filled, so indent the continuation
           POP AF
           RST &10
           RET

PRNONWLN:  PUSH DE                          ; The print position
           LD A,(OVERT)
           CP 1                             ; OVER 0 gives CY
           SBC A,A
           CPL                              ; OVER 0 gives &00, OVER 1 to 3 give &FF
           LD B,A
           LD A,(INVERT)                    ; &00 or &FF
           LD C,A
           LD IX,(PATOUT)                   ; Usually ENDOUTP
           CALL IXJUMP
           POP HL
           INC L                            ; Move right one column


; ---------------------------------------------------------------------------------------------------------------------
; POSTORE -- store the print position for the current device
;
; DEVICE is 0 for the upper screen, 1 for the lower, 2 for the printer or any other stream.
; ---------------------------------------------------------------------------------------------------------------------

POSTORE:   LD A,(DEVICE)
           AND A
           JR Z,POSUSCRN

           DEC A
           JR Z,POSLSCRN

           LD (PRPOSN),HL                   ; L = the printer column
           RET

POSLSCRN:  LD (SPOSNL),HL
           RET

POSUSCRN:  LD (SPOSNU),HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; ENDOUTP -- the default renderer: hand the bitmap to the mode-specific routine, or to the printer
; ---------------------------------------------------------------------------------------------------------------------

ENDOUTP:   LD A,(DMPFG)
           AND A
           RET NZ                           ; A screen dump is in progress, so nothing is drawn

           LD A,(DEVICE)
           CP 2
           JR Z,ENDOP2                      ; The printer

           LD A,(CSIZE)
           CP 16
           JP C,EPSUB                       ; Normal height

           CALL DBCHAR                      ; Double height: expand the bitmap to sixteen scans
           PUSH BC
           PUSH DE
           CALL EPSUB                       ; The top half
           LD A,8
           LD (DHADJ),A                     ; Shift the addressing down eight scans
           POP DE
           POP BC
           LD HL,MEMVAL+16                  ; The bottom half
           CALL EPSUB
           XOR A
           LD (DHADJ),A
           RET

ENDOP2:    LD A,(OPCHAR)
           JP CHBOP                         ; Send the character code on channel B


; =====================================================================================================================
; PRGR80 -- codes &80 and above: a keyword token or a graphic character
; =====================================================================================================================

PRGR80:    LD C,A
           LD A,(INQUFG)                    ; Bit 0 set means inside quotes
           RRCA
           LD H,A
           LD A,(FLAGX)                     ; Bit 7 set means an INPUT line
           OR H
           RLA
           JR C,POUDGH                      ; Inside quotes or in an INPUT line: graphics, not tokens

           LD A,C
           CP &85

POUDGH:    JP C,POUDG                       ; &80 to &84 are always graphics

; --- PRGR802: also the entry channel R uses ---

PRGR802:   LD HL,(PRTOKV)
           CALL JPOPT                       ; A user token printer may be installed

           INC A
           JP Z,POFN                        ; &FF introduces a function code

           SUB &86                          ; Plus one, to undo the INC above
           LD DE,KWDS85                     ; The keyword table is split into four to keep the scan short
           CP &1B
           JR C,POBTL                       ; &85 to &9F

           SUB &1B
           LD H,&20
           LD DE,KWDSA0                     ; &A0 to &BF
           CP H
           JR C,POBTL

           SUB H
           LD DE,KWDSC0                     ; &C0 to &DF
           CP H
           JR C,POBTL

           SUB H
           LD DE,KWDSE0                     ; &E0 to &FE
           JR POBTL


; =====================================================================================================================
; Printing error messages, keywords, function names and other stored messages
; =====================================================================================================================
;
; POFN handles the two-byte function tokens. The &FF prefix cannot be decoded until the following byte arrives, so
; the output routine is redirected to POSTFF for one character and restored afterwards -- the same trick the control
; codes with operands use.
; ---------------------------------------------------------------------------------------------------------------------

POFN:      LD DE,POSTFF
           JP SVSETOP                       ; Save the current output address and redirect to DE

PSTFF2:    CALL RESTOP                      ; Restore it; A = the byte that followed the &FF
           SUB PITOK
           CP SINTOK-PITOK
           JR C,POIMFN                      ; An immediate function

           SUB MODTOK-PITOK
           JR C,POFPCFN                     ; A calculator function

           LD DE,BINFNTL                    ; A binary operator
           CP ANDTOK-MODTOK+1
           JR C,POBTL                       ; MOD through AND get spaces on both sides

           JR POMSP2                        ; <>, >= and <= get none


POIMFN:    LD DE,IMFNTL
           CP FNTOK-PITOK
           JR Z,POTRNL

           CP BINTOK-PITOK
           JR Z,POTRNL                      ; FN and BIN get a trailing space but no leading one

           JR POMSP2                        ; The rest get neither

POFPCFN:   ADD A,MODTOK-SINTOK
           LD DE,FPCFNTL

POTRNL:    AND A
           PUSH AF                          ; Trailing space wanted
           SCF                              ; No leading space
           JR POGEN1

POMSPX:    SCF
           PUSH AF
           PUSH AF
           LD HL,MSGBUFF+11
           CALL POMSR2
           JR POGEN2

POMSP2:    SCF                              ; Neither leading nor trailing space
           DB SKIP1LDH                      ; LD H,n swallows the AND A below

POBTL:     AND A                            ; Both leading and trailing spaces

POGEN:     PUSH AF                          ; Trailing

POGEN1:    PUSH AF                          ; Leading
           CALL POMSR                       ; Expand the message into MSGBUFF

POGEN2:    POP AF
           JR C,POMSG3

           LD A,(FLAGS)
           RRA
           LD A," "
           CALL NC,&0010                    ; A leading space, but only if the previous character was not one

POMSG3:    CALL PRINTSTR                    ; Print BC characters from (DE)
           POP AF
           RET C

           DEC DE
           LD A,(DE)                        ; The last character of the message
           CP "A"
           JR NC,POMSG4                     ; A letter, so a trailing space is wanted

           CP "$"
           RET NZ                           ; "$" also takes one, but "=", ">" and "#" do not

POMSG4:    LD A," "
           RST &10
           RET


; ---------------------------------------------------------------------------------------------------------------------
; POMSR -- expand message number A from the list at DE into MSGBUFF
;
; Exit:   DE -> the buffer, BC = the length.
;
; LKHIBTLP skips whole messages by scanning for the byte with bit 7 set. The original comment measures it: with
; about four characters per token, finding the thirtieth word takes roughly 0.7 milliseconds.
; ---------------------------------------------------------------------------------------------------------------------

POMSR:     LD HL,MSGBUFF

POMSR2:    PUSH HL
           CALL POMSR3
           POP DE
           AND A
           SBC HL,DE
           LD B,H
           LD C,L
           RET

POMSR3:    LD B,A
           INC B
           JR POMSR4

LKHIBTLP:  LD A,(DE)
           INC DE
           RLA
           JR NC,LKHIBTLP                   ; Scan to the end of this message

POMSR4:    DJNZ LKHIBTLP

MVWORDLP:  LD A,(DE)
           AND &7F
           CP &20
           JR NC,MVWORD2                    ; An ordinary character

           PUSH DE                          ; A compression code: expand the word it stands for
           LD DE,COMPLIST
           CALL POMSR3                      ; Recursive, but only ever one level deep
           POP DE
           DB SKIP2LDBC                     ; LD BC,nn swallows the LD (HL),A and INC HL below

MVWORD2:   LD (HL),A
           INC HL

MVWORD3:   LD A,(DE)
           INC DE
           RLA
           JR NC,MVWORDLP                   ; Bit 7 marks the last character. A main message may mix compression
                                            ; codes and ASCII; a compressed word may not contain compression codes.
           RET


; =====================================================================================================================
; POUDG -- print a graphic character: a block graphic or a user-defined graphic
; =====================================================================================================================
;
; Codes &80 to &8F are quarter-cell block graphics when BGFLG says so, built on the fly by replicating the low four
; bits of the code across the cell. Everything else comes from the UDG bitmaps.
; ---------------------------------------------------------------------------------------------------------------------

POUDG:     LD A,(DEVICE)
           CP 2
           JR NZ,PUDGS

           LD A,C
           LD (OPCHAR),A                    ; LPRINT reads it from here
           LD HL,(LPRTV)
           CALL JPOPT                       ; A printer graphics vector may be installed

PUDGS:     LD A,(BGFLG)
           AND A
           LD A,C
           JR NZ,POFUDG                     ; BGRAPHICS 0: use UDGs instead of blocks

           CP &90
           JR NC,POFUDG                     ; &90 and above are UDGs regardless

           CALL QUADBITS                    ; The low four bits of A, each quadrupled, into DE
           LD HL,MEMVAL
           PUSH HL
           LD B,4

BKGRL1:    LD (HL),E                        ; The top half of the cell
           INC HL
           DJNZ BKGRL1

           LD B,4

BKGRL2:    LD (HL),D                        ; The bottom half
           INC HL
           DJNZ BKGRL2

           POP HL
           LD B,C
           JP NLENTRY


; ---------------------------------------------------------------------------------------------------------------------
; POFUDG -- find a UDG bitmap
;
; Codes &A9 and above index the high UDG area through HUDG; below that they index the normal UDG area, which UDG
; points at biased so that code 144 is its first entry.
;
; Notes:  HUDG is never written by the ROM, so unless a program sets it this path reads bitmaps from address 0.
;         See docs/hudg.md.
; ---------------------------------------------------------------------------------------------------------------------

POFUDG:    LD HL,(HUDG)
           SUB &A9
           JR NC,POUDG1                     ; A high UDG

           LD A,C
           LD DE,&FB80                      ; Compensates for A being &80 to &A8 while UDG points at code 144
           LD HL,(UDG)
           ADD HL,DE

POUDG1:    EX DE,HL
           JP PRINTMN1


; =====================================================================================================================
; PRCRLCDS -- the control codes, &06 to &17
; =====================================================================================================================
;
; Dispatched through CCPTB, a table of single-byte displacements rather than addresses. Each entry is measured from
; a point one further along the table than the last, which is why the table's entries carry a decreasing correction
; -- it lets a two-byte address be replaced by one byte.
;
; Codes outside &06 to &17 print a question mark.
; ---------------------------------------------------------------------------------------------------------------------

PRCRLCDS:  CP 24
           JR NC,PRQUERY

           CP 6
           JR C,PRQUERY

           LD E,A
           LD D,0
           LD HL,CCPTB-6
           ADD HL,DE
           LD E,(HL)
           ADD HL,DE                        ; HL = the handler
           LD C,A
           CALL POFETCH                     ; D = row, E = column, A = the right margin, CY if printing
           JP (HL)

CCPTB:

;           DB PRQUERY-CCPT      ;0
;          DB PRQUERY-CCPT-1    ;1
;         DB PRQUERY-CCPT-2    ;2
;        DB PRQUERY-CCPT-3    ;3  CLS?
;       DB PRQUERY-CCPT-4    ;4
;      DB PRQUERY-CCPT-5    ;5
           DB PRCOMMA-CCPTB      ;6  PRINT COMMA
           DB PRQUERY-CCPTB-1    ;7  (EDIT)
           DB CURLF-CCPTB-2      ;8  CURSOR LEFT
           DB CURRT-CCPTB-3      ;9  CURSOR RIGHT
           DB CURDN-CCPTB-4      ;10 CURSOR DOWN
           DB CURUP-CCPTB-5      ;11 CURSOR UP
           DB PRDELL-CCPTB-6     ;12 DELETE LEFT
           DB PRENTER-CCPTB-7    ;13 ENTER
           DB PRDELR-CCPTB-8     ;14 DELETE RIGHT
           DB PRQUERY-CCPTB-9    ;15
           DB CC1OP-CCPTB-10     ;16 INK
           DB CC1OP-CCPTB-11     ;17 PAPER
           DB CC1OP-CCPTB-12     ;18 FLASH
           DB CC1OP-CCPTB-13     ;19 BRIGHT
           DB CC1OP-CCPTB-14     ;20 INVERSE
           DB CC1OP-CCPTB-15     ;21 OVER
           DB CC2OPS-CCPTB-16    ;22 AT
           DB CC2OPS-CCPTB-17    ;23 TAB


; ---------------------------------------------------------------------------------------------------------------------
; PRCOMMA -- the PRINT comma: advance to the next tab stop
;
; TABVAR chooses between 16-column and 8-column stops. If the next stop is past the right margin, the line is simply
; filled with spaces to the margin.
; ---------------------------------------------------------------------------------------------------------------------

PRCOMMA:   LD A,E
           LD HL,WINDLHS
           SUB (HL)                         ; The distance from the window's left edge
           PUSH AF
           LD A,(TABVAR)
           AND A
           LD BC,&F010                      ; Mask and step for 16-column stops
           JR Z,PCOM2

           LD BC,&F808                      ; Mask and step for 8-column stops

PCOM2:     LD A,(WINDRHS)
           CP E
           JR C,PC25                        ; The line is already full

           POP AF
           AND B                            ; Round down to the previous stop
           ADD A,C                          ; And on to the next one
           ADD A,(HL)                       ; As an absolute column
           DEC HL
           CP (HL)
           JR C,PCOM3                       ; It fits within the margin

           LD A,(HL)                        ; It does not, so stop at the margin
           INC A

PCOM3:     SUB E

OPAORZ:    RET Z

OPASPACES: LD B,A

OPSPLP:    LD A," "
           RST &10
           DJNZ OPSPLP

           RET

PC25:      POP AF
           LD B,C
           JR OPSPLP

PRQUERY:   LD A,"?"
           RST &10
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CURLF / CURUP / CURRT -- cursor movement control codes
;
; Cursor left at the left edge wraps to the right edge of the previous line. Cursor right is implemented as printing
; a space with OVER 1, which leaves whatever is there untouched while advancing the position.
; ---------------------------------------------------------------------------------------------------------------------

CURLF:     LD A,(WINDLHS)
           CP E
           LD A,(WINDRHS)
           JR Z,CURLF2                      ; At the left edge

           DEC E
           CP E
           JR NC,POSTOREH                   ; Not past the right margin

           LD E,A                           ; The position was "line full", so pull it back to the margin

POSTOREH:  EX DE,HL
           JP POSTORE

CURLF2:    LD E,A                           ; Wrap to the right edge
           LD A,(DEVICE)
           ADD A,&FE                        ; CY if the printer

CURUP:     JR C,PRQUERY                     ; The printer cannot move up, so print a question mark

           LD A,(WINDTOP)
           CP D
           RET Z                            ; Already at the top of the window

           DEC D
           JR POSTOREH

CURRT:     LD HL,(OVERT)
           PUSH HL
           LD A,(M23PAPT)
           PUSH AF
           LD HL,&0001                      ; OVER 1, INVERSE 0
           LD B,1
           JR SPOX


; ---------------------------------------------------------------------------------------------------------------------
; PRDELL / PRDELR -- delete left and right
; ---------------------------------------------------------------------------------------------------------------------

PRDELL:    JR C,PRQUERY                     ; Not on the printer

           LD A,8
           RST &10                          ; Backspace
           CALL SPO0                        ; Print a space over the character
           LD A,8
           RST &10                          ; And back again
           RET


; ---------------------------------------------------------------------------------------------------------------------
; EROC2 -- erase the old line cursor from the listing
;
; Exit:   A and C = the cursor's screen row relative to the window, H = the high byte of LPT.
; ---------------------------------------------------------------------------------------------------------------------

EROC2:     LD A,(WINDTOP)
           LD C,A
           LD A,(LNPTR)
           SUB C
           JR NC,EROC3

           XOR A                            ; The cursor is above the window

EROC3:     LD C,A
           LD E,5
           CALL ATSR2                       ; Move to column 5 of that row
           CALL SPO0
           LD A,C
           LD H,LPT/256
           RET


; ---------------------------------------------------------------------------------------------------------------------
; PRDELR / SPO0 / OPBSP -- print spaces with OVER 0 and INVERSE 0
;
; The current OVER, INVERSE and mode 2/3 paper settings are saved, forced to the plain permanent values, and
; restored afterwards -- so a space really erases, whatever the user's OVER setting.
;
; Entry:  at OPBSP, B = the number of spaces.
; ---------------------------------------------------------------------------------------------------------------------

PRDELR:

SPO0:      LD B,1

OPBSP:     LD HL,(OVERT)                    ; OVERT and INVERT are adjacent
           PUSH HL
           LD A,(M23PAPT)
           PUSH AF
           LD A,(M23PAPP)
           LD (M23PAPT),A                   ; The permanent paper colour
           LD HL,&0000                      ; OVER 0, INVERSE 0

SPOX:      LD (OVERT),HL

OPSL:      LD A,&20
           RST &10
           DJNZ OPSL

           POP AF
           LD (M23PAPT),A
           POP HL
           LD (OVERT),HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CURDN / PRENTER -- move down a line, and the carriage return
;
; The print position uses column &FE to mean "the line is full but no newline has been issued yet", and column &FF
; to mean the newline came from a line that filled naturally. That is how PRENTER knows whether a carriage return
; should move down a line or merely reset the column: two returns in a row must both take effect, but a full line
; followed by a return must not skip a line.
;
; Scrolling happens here, when a newline is issued on the bottom line of the window.
; ---------------------------------------------------------------------------------------------------------------------

CURDN:     PUSH DE
           LD E,&FE                         ; Force an actual downward move
           CALL PRENTER
           POP DE
           LD L,E                           ; The column is unchanged
           JR PRENT5

PRENTER:   JR C,LPRENT                      ; The printer

           LD A,E
           CP &FE
           JR C,PRENT3                      ; The previous character was not a newline, so just mark the line full

           LD A,(WINDBOT)
           CP D
           JR NZ,PRENT2                     ; Not on the bottom line

           PUSH DE
           CALL SCRLSCR                     ; Scroll the window up
           POP DE
           DEC D                            ; So the row ends up as the bottom line again

PRENT2:    INC D
           INC E                            ; Z if the column was &FF, that is a recursive newline
           LD A,(WINDLHS)
           JR Z,PRENT4                      ; The next character starts at the left edge

PRENT3:    LD A,&FE                         ; Line full, but not from a recursive newline

PRENT4:    LD E,A
           EX DE,HL

PRENT5:    JP POSTORE

LPRENT:    LD A,&0D
           CALL CHBOP
           XOR A
           LD (PRPOSN),A
           LD A,(AFTERCR)
           AND A
           RET Z

                                            ; AFTERCR is usually &0A, sent after the carriage return


; ---------------------------------------------------------------------------------------------------------------------
; CHBOP -- send the character in A on channel B, the printer channel
; ---------------------------------------------------------------------------------------------------------------------

CHBOP:     LD HL,(CHANS)
           LD DE,25
           ADD HL,DE                        ; Channel B is the sixth entry
           JP HLJPI
;           LD E,(HL)
;          INC HL
;         LD D,(HL)
;        EX DE,HL          ;HL=O/P ADDR (USUALLY 'SENDA')
;       JP (HL)


; ---------------------------------------------------------------------------------------------------------------------
; CC1OP / CC2OPS -- control codes that take operands
;
; INK, PAPER, FLASH, BRIGHT, INVERSE and OVER take one operand; AT and TAB take two, though TAB discards the second.
; The operands arrive as subsequent characters, so the output routine is redirected until they have all been
; collected, and the control code itself is parked in TVDATA.
; ---------------------------------------------------------------------------------------------------------------------

CC1OP:     LD DE,CCRESTOP
           JR SETADCOM

CC2OPS:    LD DE,PRERESTOP

SETADCOM:  CALL SVSETOP
           LD A,C
           LD (TVDATA),A
           RET

SVSETOP:   PUSH DE
           CALL SVCUROP
           POP DE
           JP POCHNG


; ---------------------------------------------------------------------------------------------------------------------
; CCRP2 -- all operands collected, so act on the control code
;
; Entry:  H = the first operand if there were two, L = the control code, A = the last operand.
; ---------------------------------------------------------------------------------------------------------------------

CCRP2:     LD HL,(TVDATA)

           LD D,A
           LD A,L
           CP &16
           JP C,PRCOITEM                    ; A colour item

           JR Z,POATCC                      ; AT

; --- TAB: only the first operand, the column, matters ---

           CALL POFETCH                     ; D = row, E = column, A = the right margin, CY if printing
           LD C,A
           CP E
           LD A,H
           JR C,TAB2                        ; The line is full

           LD A,(WINDLHS)
           ADD A,H                          ; The absolute tab column
           SUB E                            ; The spaces needed to reach it
           RET Z

           JR NC,TAB2                       ; Not past it yet

           LD A,H                           ; Past it, so fill this line and then reach the stop on the next
           ADC A,C
           SUB E

TAB2:      AND A
           JP OPAORZ


; ---------------------------------------------------------------------------------------------------------------------
; POATCC -- the AT control code
;
; A row past the bottom of the window is an error on the upper screen, but on the lower screen it grows the window
; upwards instead, scrolling the upper screen out of the way as needed.
; ---------------------------------------------------------------------------------------------------------------------

POATCC:    EX DE,HL
           LD E,H                           ; D = the row, E = the column
           LD HL,WINDLHS
           LD A,(HL)
           ADD A,E
           LD E,A                           ; The absolute screen column
           DEC HL
           LD A,(HL)                        ; WINDRHS
           CP E
           JR C,PATER                       ; Too far right

           INC HL
           INC HL                           ; WINDTOP
           LD A,(HL)
           ADD A,D
           LD D,A                           ; The absolute screen row
           INC HL
           LD A,(HL)                        ; WINDBOT
           SUB D
           JR NC,POSTORH                    ; Within the window

           NEG
           LD B,A                           ; How many extra rows the lower screen needs
           LD A,(DEVICE)
           AND A
           JR Z,PATER                       ; The upper screen cannot grow

           LD D,(HL)
           PUSH DE

SLSLP:     PUSH BC
           CALL SCRLS                       ; Each scroll adds one row to the top of the lower screen
           POP BC
           DJNZ SLSLP

           POP DE

POSTORH:   EX DE,HL
           JP POSTORE

PATER:     RST &08
           DB ERR_OFFSCREEN


; ---------------------------------------------------------------------------------------------------------------------
; SVCUROP -- save the current channel's output address in OPSTORE
; ---------------------------------------------------------------------------------------------------------------------

SVCUROP:   LD HL,(CURCHL)
           LD E,(HL)
           INC HL
           LD D,(HL)
           LD (OPSTORE),DE
           RET


; ---------------------------------------------------------------------------------------------------------------------
; SCRLSCR -- scroll the current window up one line
;
; Three cases. During an AUTOLIST, scrolling means the listing has filled the screen, so it stops -- unless the
; current line has not been printed yet, in which case it must keep going. On the upper screen, scrolling counts
; down SCRCT and issues the "Scroll?" prompt when it reaches zero. On the lower screen it goes to SCRLS, which may
; also have to scroll the upper screen.
; ---------------------------------------------------------------------------------------------------------------------

SCRLSCR:   LD A,(TVFLAG)
           AND FTVAUTOLIST
           JR Z,SCRLSCR2

           LD A,(BCREG)
           DEC A
           JR NZ,DOSCRL                     ; The current line has not been printed yet

           CALL SETSTRM                     ; Stream zero
           LD SP,(LISTSP)                   ; Discard the listing's stack frames
           JP AULX                          ; Mark the autolist as finished

SCRLSCR2:  LD A,(DEVICE)
           DEC A
           JR Z,SCRLS                       ; The lower screen

           CALL BRKCR
           LD A,(SPROMPT)
           AND A
           JR NZ,DOSCRL                     ; Prompts are switched off

           LD HL,SCRCT
           DEC (HL)
           JR NZ,DOSCRL                     ; Not yet a full screen since the last prompt

           CALL SETSCRCT
           CALL SVTEMPS                     ; The prompt would otherwise disturb the temporary attributes
           LD HL,(CURCHL)
           PUSH HL
           EXX
           PUSH DE
           LD A,1                           ; The "Scroll?" message
           CALL WTBRK
           POP DE
           EXX
           CP " "
           JR Z,BRCH

           AND &DF
           CP "N"

BRCH:      CALL Z,IOPOF                     ; SPACE or N stops the listing
           JP Z,BRCERR

           POP HL
           LD (CURCHL),HL
           CALL CHANFLAG
           CALL RSTTEMPS
           CALL COLEX

DOSCRL:    JP EDRS1UP

SETSCRCT:  LD HL,(WINDTOP)
           LD A,H
           SUB L
           INC A                            ; The window height
           LD (SCRCT),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; SCRLS -- scroll the lower screen, growing it upwards
;
; The lower screen expands by taking a line from the upper screen. If its new top reaches the upper screen's print
; position, the upper screen has to scroll too -- from its top down to that position, so nothing already printed
; there is lost.
; ---------------------------------------------------------------------------------------------------------------------

SCRLS:     LD HL,LWTOP
           LD A,(HL)
           DEC A
           JR Z,PATER                       ; The window has reached the top of the screen

           LD (HL),A
           LD (WINDTOP),A                   ; The temporary window is the lower screen, so update that too
           LD HL,KPOS+1
           DEC (HL)                         ; Keep the recorded cursor line in step
           LD HL,SPOSNU+1
           CP (HL)
           JR NZ,DOSCRL                     ; No clash with the upper screen's print position.
                                            ; This also branches when WINDTOP is above that position.
           PUSH AF
           DEC (HL)                         ; The upper print position moves up a line
           CALL STREAMFE                    ; The main window
           POP AF
           LD (WINDBOT),A                   ; Its bottom becomes the former print position
           CALL EDRS1UP                     ; Scroll it up one
           CALL STREAMFD                    ; Back to the lower window
           JR DOSCRL


; ---------------------------------------------------------------------------------------------------------------------
; SVTEMPS / RSTTEMPS -- save and restore the eight temporary attribute bytes at THFATT
; ---------------------------------------------------------------------------------------------------------------------

RSTTEMPS:  AND A
           DB SKIP1LDH                      ; LD H,n swallows the SCF below

SVTEMPS:   SCF
           LD HL,THFATT
           LD DE,TEMPW1                     ; Eight bytes of temporary store
           JR C,SVRSTTMPS

           EX DE,HL                         ; Restoring, so copy the other way

SVRSTTMPS: JP LDIR8                         ; LD BC,8 : LDIR : RET


; ---------------------------------------------------------------------------------------------------------------------
; DBCHAR -- expand an eight-scan bitmap to sixteen by duplicating each scan
;
; Entry:  HL -> the bitmap.
; Exit:   HL -> MEMVAL+8, the expanded copy. MEMVAL+0 is left alone because it may be in use.
; ---------------------------------------------------------------------------------------------------------------------

DBCHAR:    PUSH BC
           PUSH DE
           LD DE,MEMVAL+8
           PUSH DE
           LD B,8

DHLP:      LD A,(HL)
           INC HL
           LD (DE),A
           INC DE
           LD (DE),A
           INC DE
           DJNZ DHLP

           POP HL
           POP DE
           POP BC
           RET


; ---------------------------------------------------------------------------------------------------------------------
; WTBRK -- clear the lower screen, print a prompt, and wait for a key
;
; Entry:  A = the message number. Used for "Start tape" and "Scroll?".
; ---------------------------------------------------------------------------------------------------------------------

WTBRK:     CALL WTB2
           CALL UTMSG
           CALL READKEY                     ; Discard anything already in the buffer
           CALL GTKBK

WTB2:      PUSH AF
           CALL CLSLOWER
           POP AF
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FONOP2 -- jump to the main output routine, used when printing the cursor
; ---------------------------------------------------------------------------------------------------------------------

FONOP2:    LD BC,(MNOP)
           PUSH BC
           RET
