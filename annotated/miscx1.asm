; =====================================================================================================================
; MISCX1.ASM -- the routines that run from a RAM buffer: RENUMBER, GET, DELETE, KEYIN, POP and INPUT
; =====================================================================================================================
;
; WHY THESE ROUTINES ARE DIFFERENT
; --------------------------------
; ROM1 occupies section D, at &C000. So does nothing else -- but a routine running in ROM1 cannot page ROM1 out, and
; several of these routines have to reach parts of memory that are only accessible with a particular page
; configuration, or have to call back into ROM0.
;
; The solution is to copy the routine into a RAM buffer and run it from there. Each block below is assembled with
; `ORG INSTBUF` (or `ORG HDR` for the one that needs a larger buffer), so they all assemble to the same addresses
; and overlay one another; only one is ever resident at a time. The caller copies the block in and jumps to it.
;
; The `xxxLN: EQU end+n-start` lines at the end of each block give the byte count the caller needs for that copy.
; They are why the ORG directives and the label positions here are load-bearing: change the layout and the lengths
; silently change with it.
;
; RENUMBER
; --------
; A two-pass algorithm. MAKETABLE builds a translation table in the screen page -- SBO holds the old line numbers
; and SBN, a fixed distance above it, the new ones -- and then CHGREF walks the whole program rewriting every line
; number *reference* before CHGLL rewrites the line numbers themselves.
;
; Rewriting a reference is more involved than it looks, because a line number in the program text is stored twice:
; as the ASCII digits the user typed, and as the invisible five-byte binary form the interpreter actually uses (see
; docs/tokenized-program-format.md). Both have to change, and the new digits may not be the same length as the old
; ones, so ADJLINE opens or closes the difference and fixes up the line's stored length.
;
; RENTAB lists the tokens that can be followed by a line number. LINE is a special case: it only counts as a line
; number reference when preceded by a closing quote or a "$", as in SAVE "name" LINE 10, since LINE also appears in
; INPUT LINE and PALETTE ... LINE.
;
; =====================================================================================================================

           ORG INSTBUF


; =====================================================================================================================
; RNMP2 -- RENUMBER, copied to INSTBUF for execution
;
; RENUMBER <first> TO <last> LINE <n> STEP <m>, all parts optional; LINE and STEP both default to 10.
; =====================================================================================================================

RNMP2:     LD HL,10
           LD   (RLINE),HL                  ; Default starting line
           LD   (RSTEP),HL                  ; Default step
           CALL BRKLSSL                     ; Parse the optional <first> TO <last> range
           RST  &18
           LD   HL,RLINE
           CP   TOK_LINE
           CALL Z,REVAL
           LD   HL,RSTEP
           CP   STEPTOK
           CALL Z,REVAL
           CALL CHKEND

           LD B,24
           CALL TESTROOM                    ; Abort unless at least 6K is free
           CALL SPSS                        ; The translation table is built in the screen page


; ---------------------------------------------------------------------------------------------------------------------
; MAKETABLE -- build the old-to-new line number translation table
;
; SBO receives the old numbers in program order and SBN the new ones. The two tables are a fixed distance apart, so
; TRANSFORM can find an entry in one and read the answer from the other by adding a constant to H.
; ---------------------------------------------------------------------------------------------------------------------

MAKETABLE: LD   HL,(RLINE)
           LD   BC,(RSTEP)
           LD   DE,SBN+2

           EXX
           LD   HL,SBO
           PUSH HL
           LD   DE,&0000

MKTBLP:    POP  HL
           LD   (HL),D                      ; Record the old line number
           INC  HL
           LD   (HL),E
           DEC  HL
           PUSH HL
           LD   HL,(LAST)                   ; &FEFF if the range runs to the end of the program
           SBC  HL,DE
           JR C,RENUM3                      ; Past the end of the block, or at the program terminator

           CALL GTRLNN
           SCF
           SBC  HL,DE
           JR   NC,MKTBLP

           POP  HL
           INC  HL
           INC  HL
           PUSH HL

           EXX
           EX   DE,HL
           LD   (HL),D                      ; Record the new line number
           INC  HL
           LD   (HL),E
           INC  HL
           INC H
           JR Z,NRFLERR                     ; The new table would run past the end of the page

           DEC H
           EX   DE,HL
           ADD  HL,BC                       ; Next new line number
           JR C,NRFLERR

           LD A,H
           EXX

           INC  A
           JR   NZ,MKTBLP                   ; Stop if the numbers have passed &FEFF

NRFLERR:   RST &08
           DB ERR_NOROOMLINE

RENUM3:    POP BC
           LD HL,(SBO)
           LD (TEMPW1),HL                   ; Keep a copy readable once the screen page is switched out
           CALL RCURP
           LD HL,PPC
           CALL TRANSHL                     ; Renumber the current line pointer too
           PUSH BC
           LD A,(SUBPPC)
           PUSH AF

           LD A,D
           INC A
           JR NZ,REN3                       ; DE is a real line number

           LD E,A                           ; Otherwise DE = &FF00, one past the highest line

; --- Check that the renumbered block will not overlap the lines outside it ---

REN3:      XOR A                            ; NC
           PUSH DE
           EXX
           POP  DE
           SBC  HL,BC
           SBC  HL,BC
           SBC  HL,DE
           JR   NC,NRFLERR                  ; The new numbers would collide with the lines after the block

           LD   HL,(TEMPW1)
           LD   D,L
           LD   E,H
           LD   HL,(RLINE)
           SBC  HL,DE
           JR C,NRFLERR                     ; Or with the lines before it

           CALL CHGREF                      ; Rewrite every reference first

; --- Then rewrite the line numbers themselves ---

           LD   HL,(FIRST)
           CALL FNDLINE

CHGLL:     LD   B,(HL)
           INC  HL
           LD   C,(HL)
           PUSH HL
           CALL TRANSFORM
           POP  HL
           JR C,REN5                        ; Past the end of the block

           LD   (HL),C
           DEC  HL
           LD   (HL),B
           INC  HL
           INC  HL
           LD   C,(HL)
           INC  HL
           LD   B,(HL)                      ; BC = the line length
           INC  HL
           ADD  HL,BC                       ; On to the next line
           CALL CHKHL
           JR   CHGLL

REN5:      LD HL,EPPC
           CALL TRANSHL
           LD L,SDTOP\256                   ; SDTOP shares a page with EPPC, so only L changes
           CALL TRANSHL
           CALL MCLS                        ; The listing on screen is now wrong, so clear it
           JP GT4P                          ; Unstack the statement and line, and set up as if for a GOTO


; ---------------------------------------------------------------------------------------------------------------------
; CHGREF -- rewrite every line number reference in the program
;
; For each token in RENTAB, SRCHPROG finds every occurrence and the code below parses what follows it, transforms
; the number, and writes it back in both its ASCII and its five-byte binary forms.
; ---------------------------------------------------------------------------------------------------------------------

FAILED:    CALL FDELETE                     ; Discard the value left on the calculator stack

NBLKL:     POP  BC                          ; Unwind the three saved pointers and move on
           POP  BC
           POP  BC
           JP CHGR7

CHGREF:    LD   IX,RENTAB-1

RENCL:     INC  IX
           CALL ADDRPROG
           LD A,(HL)
           INC A
           RET Z                            ; Empty program

           LD   (CLA),HL
           INC  HL
           INC  HL
           INC  HL
           INC  HL
           LD   (CHAD),HL

RLOOP:     LD   A,(IX+0)
           AND  A
           RET  Z                           ; End of RENTAB

           LD   E,A
           CALL SRCHPROG                    ; Find the next occurrence of this token
           JR   NC,RENCL                    ; None left, so move to the next token

           LD   (SUBPPC),A
           IN   A,(URPORT)
           LD   (CHADP),A
           LD A,(IX+0)
           CP TOK_LINE
           JR NZ,CHGRY

           DEC HL                           ; LINE only counts as a line number reference when it follows a string
           DEC HL
           LD A,(HL)
           CP "$"
           JR Z,CHGRY                       ; SAVE name$ LINE 10

           CP &22
           JR NZ,RLOOP                      ; SAVE "name" LINE 10; anything else is a different use of LINE

CHGRY:     RST  &18

CHGR1:     CP   TOTOK
           JR   NZ,CHGR2

           RST  &20

CHGR2:     PUSH HL
           LD   B,&FF                       ; The digit counter, pre-decremented
           CP   TOK_ON
           JR   NZ,CHGR5

CHGR3:     RST  &20                         ; GOTO ON x;100,200: skip past the selector to the semicolon
           CP   ";"
           JR   NZ,CHGR3

           RST  &20
           POP  DE
           PUSH HL
           DB SKIP2LDDE                     ; LD DE,nn swallows the INC HL below

CHGR4:     INC HL
           LD A,(HL)

CHGR5:     CALL NUMERIC
           INC  B
           JR   C,CHGR4                     ; Count the ASCII digits

           PUSH BC

CHGR6:     LD A,(HL)
           INC HL
           CP " "
           JR Z,CHGR6                       ; Skip any spaces between the digits and the hidden form

           PUSH HL
           CP   NUMMARKER
           JR   NZ,NBLKL                    ; No hidden numeric form, so this is not a literal line number

           CALL HLTOFPCS                    ; Read the five-byte form
           LD   (CHAD),HL
           CALL GETINT
           RST  &18
           CALL COCRCOTO                    ; It must be followed by end of statement, TO or a comma
           JR NZ,FAILED

           CALL TRANSFORM
           JR   C,NBLKL                     ; The referenced line is outside the renumbered block

           CALL STACKBC
           LD HL,-5
           ADD HL,DE                        ; Point at the new five-byte form on the calculator stack
           POP  DE
           CALL LDI5                        ; Copy it over the old one, in the line
           CALL JPFSTRS                     ; BC = the length of the new number as digits
           POP  AF                          ; The old digit count
           POP  DE
           LD   HL,(CLA)


; ---------------------------------------------------------------------------------------------------------------------
; ADJLINE -- replace a run of characters in a program line with one of a different length
;
; Entry:  HL -> the start of the line, DE -> where the replacement goes, BC = the new length, A = the old length.
;
; Opens or closes the difference with MAKEROOM or RECLAIM2, fixes the line's stored length word, and then copies the
; new text in from PRNBUFF.
; ---------------------------------------------------------------------------------------------------------------------

ADJLINE:   SUB C
           JR Z,ADLNO                       ; Same length, so just overwrite

           INC  HL
           INC  HL
           PUSH BC
           PUSH AF
           LD   C,(HL)
           INC  HL
           LD   B,(HL)                      ; The current line length
           PUSH HL
           NEG
           LD   L,A
           RLA
           SBC  A,A                         ; Sign-extend the difference into HL
           LD   H,A
           ADD  HL,BC
           LD   B,H
           LD   C,L
           POP  HL
           LD   (HL),B
           DEC  HL
           LD   (HL),C                      ; The new line length
           POP  AF
           LD   B,0
           JR   NC,ADJL2                    ; The new text is shorter, so close the gap

           NEG
           LD   C,A
           EX   DE,HL
           CALL MAKEROOM
           JR   ADJL3

ADJL2:     LD   C,A
           EX DE,HL
           CALL RECLAIM2

ADJL3:     EX DE,HL
           POP BC

ADLNO:     LD HL,PRNBUFF
           LDIR                             ; Copy the new digits in
           EX DE,HL
           LD C,6                           ; Step over the five-byte hidden form and its marker
           ADD HL,BC
           LD (CHAD),HL

CHGR7:     CALL RCRC                        ; RST &18 then CRCOLON
           JP Z,RLOOP                       ; End of statement, so look for the next occurrence

           CALL COCRCOTO
           JP NZ,RLOOP

           RST &20                          ; A comma or TO, so another line number follows
           JP CHGR1


; --- The tokens that can introduce a line number reference ---

RENTAB:    DB TOK_DELETE
           DB TOK_ONERROR
           DB TOK_LINE
           DB TOK_LLIST
           DB TOK_LIST
           DB TOK_RESTORE
           DB TOK_GOTO
           DB TOK_GOSUB
           DB TOK_RUN
           DB 0


; ---------------------------------------------------------------------------------------------------------------------
; REVAL -- evaluate the LINE or STEP value of RENUMBER and store it at (HL)
; ---------------------------------------------------------------------------------------------------------------------

REVAL:     PUSH HL
           CALL GIR
           POP HL
           RET C                            ; Syntax checking

           LD A,B
           OR C
           JP Z,IOORERR                     ; Zero is not a valid line number or step

           LD (HL),C
           INC HL
           LD (HL),B
           RST &18
           RET


; ---------------------------------------------------------------------------------------------------------------------
; TRANSHL / TRANSFORM -- map an old line number to its new one
;
; TRANSHL reads the number from (HL), transforms it, and writes it back.
;
; TRANSFORM takes BC and returns the new number in BC, or CY if the line is outside the renumbered block. The lookup
; scans SBO until it finds an entry at or past the wanted number, then reads the corresponding SBN entry by adding
; the fixed distance between the two tables to H.
; ---------------------------------------------------------------------------------------------------------------------

TRANSHL:   LD C,(HL)
           INC HL
           LD B,(HL)
           PUSH HL
           CALL TRANSFORM
           POP HL
           RET C

           LD (HL),B
           DEC HL
           LD (HL),C
           RET

TRANSFORM: LD   HL,(LAST)
           AND  A
           SBC  HL,BC
           RET  C                           ; Past the end of the block

           LD   HL,(FIRST)
           SBC  HL,BC
           JR   Z,TRANS2

           CCF
           RET  C                           ; Before the start of the block

TRANS2:    CALL SPSS                        ; The tables live in the screen page
           LD   HL,SBO+2

TRANS3:    LD A,(HL)
           CP B
           JR NZ,TRANS4

           INC HL
           LD A,(HL)
           DEC HL
           CP C

TRANS4:    JR   NC,TRANS5

           INC  HL
           INC  HL
           JR   TRANS3

TRANS5:    LD   A,H
           ADD  A,0+(SBN-SBO)/256           ; Step across to the new-numbers table; the tables are page-aligned
           LD   H,A
           LD   B,(HL)
           INC  HL
           LD   C,(HL)

TRANSF:    JP   RCURP

RENLN:     EQU TRANSF+3-RNMP2               ; The byte count the caller copies


; =====================================================================================================================
; GETP2 -- the GET command, copied to INSTBUF for execution
;
; GET waits for a single keypress and assigns it to a variable. A string variable receives the character; a numeric
; variable receives its value as a hexadecimal digit, so "0" to "9" give 0 to 9 and "A" to "F" give 10 to 15.
; =====================================================================================================================

           ORG INSTBUF

GETP2:     CALL SYNTAX1                     ; A valid variable must follow
           CALL CHKEND

           LD HL,FLAGS
           PUSH HL
           RES 5,(HL)                       ; Discard any key already waiting
           CALL WKBR                        ; Wait for a key, with BREAK still working
           POP HL
           BIT 6,(HL)
           JR NZ,GT2                        ; A numeric variable

           CALL STACKA

           DB CALC
           DB CHRS                          ; Turn the key code into a one-character string
           DB EXIT

           JR GT4

GT2:       CALL NUMERIC
           JR C,GT3                         ; "0" to "9"

           AND &DF                          ; Force upper case
           SUB 7                            ; So that "A" lands seven above "9"

GT3:       SUB &30                          ; "0" becomes 0, "A" becomes 10
           CALL STACKA

GT4:       CALL NOISE                       ; The keyclick
           JP ASSIGN

GETLN:     EQU GT4+6-GETP2


; =====================================================================================================================
; DELPT2 -- the DELETE command, copied to INSTBUF for execution
;
; DELETE <first> TO <last>, either end optional. The whole range is removed in a single RECL2BIG, which can span
; pages, rather than line by line.
; =====================================================================================================================

           ORG INSTBUF

DELPT2:    LD HL,1
           CALL DELSR                       ; Default first line is 1, or the first line after it
           RST &18
           CP TOTOK
           JR Z,DL2

           CALL GIR2
           CALL NC,DELSR                    ; Only act if running

           RST &18
           CP TOTOK
           JP NZ,NONSENSE

DL2:       RST &20
           CALL CRCOLON
           LD HL,&FEFF                      ; Default last line is the highest legal one
           CALL NZ,GIR2

           CALL RUNFLG
           JR NC,DL4                        ; Syntax checking

           CALL FNDLINE
           JR NZ,DL4                        ; That line does not exist, so HL is already the next line's start

           CALL NEXTONE                     ; It does, so the deletion must run to just past its end
           EX DE,HL

DL4:       CALL CHKHL
           IN A,(URPORT)
           LD D,A
           CALL CHKENDCP

           LD A,(LAST)
           LD C,A
           CALL TSURPG                      ; Page in the start of the range
           LD A,D                           ; AHL = the end address
           LD DE,(FIRST)                    ; CDE = the start address
           CALL SUBAHLCDE
           RET C                            ; The range is inverted, as in DELETE 2 TO 1

           LD B,H
           LD C,L                           ; ABC = the length to remove
           EX DE,HL
           CALL RECL2BIG
           JP GT4R                          ; Re-enter as if for a GOTO, so the line pointers are rebuilt

DELSR:     CALL FNDLINE
           CALL CHKHL
           LD (FIRST),HL
           IN A,(URPORT)
           LD (LAST),A

DELFIN:    JP SELCHADP

DELLN:     EQU DELFIN+3-DELPT2


; =====================================================================================================================
; KEYP2 -- the KEYIN command, copied to HDR for execution
;
; KEYIN s$ behaves as though the string had been typed at the keyboard: it is tokenised, syntax-checked, and then
; either executed as a direct command or inserted into the program as a numbered line.
;
; It uses HDR rather than INSTBUF because it needs the larger buffer -- the string is copied into the edit line and
; the whole editor and tokeniser path runs over it.
;
; The string is copied indirectly, via a buffer, so that KEYIN "..." works even though the literal being copied is
; itself inside the line being replaced.
; =====================================================================================================================

           ORG HDR

KEYP2:     CALL SYNTAXA

           LD A,&FE
           CALL SBFSR2                      ; Copy the string to a buffer; lengths up to 511 are fine
           RET Z                            ; An empty string does nothing

           LD HL,(PPC)
           PUSH HL
           LD A,(SUBPPC)
           PUSH AF                          ; Remember where we were, for the GOTO at the end
           PUSH DE                          ; The string
           PUSH BC                          ; Its length
           CALL CLEARSP
           POP BC
           PUSH BC
           CALL ADDRELN
           CALL MAKEROOM
           EX DE,HL
           POP BC
           POP HL
           LDIR                             ; Copy the string into the edit line
           CALL SETESP                      ; Errors now return here; the old ERRSP is on the stack
           CALL TOKMAIN                     ; Tokenise it
           CALL LINESCAN                    ; Syntax-check it
           LD A,(ERRNR)
           AND A
           JR NZ,KI3

           LD HL,FLAGS
           SET 7,(HL)                       ; Running
           CALL EVALLINO                    ; CY if the line number is out of range, Z if there is none
           JP C,NONSENSE

           JR NZ,KI2                        ; It has a line number, so insert it

           INC C                            ; Statement 1
           CALL LOOPEL                      ; No line number, so execute it directly
           SCF

KI2:       CALL NC,INSERTLN

KI3:       POP HL                           ; The old ERRSP
           CALL RESESP                      ; Restore it and report any error that occurred
           CALL CLEARSP

KEYFIN:    JP GT4P                          ; Re-enter as if for a GOTO, so a line can be keyed in ahead of the one
                                            ; currently executing

KEYLN:     EQU KEYFIN+3-KEYP2


; =====================================================================================================================
; POPP2 -- the POP command, copied to INSTBUF for execution
;
; POP discards the top entry of the BASIC stack, optionally assigning the line number it held to a variable. It
; accepts any frame type -- DO, GOSUB or PROC -- and for a PROC frame also discards that procedure's local
; variables.
; =====================================================================================================================

           ORG INSTBUF

POPP2:     CALL CRCOLON

           CALL NZ,VNUMV                    ; An optional numeric variable to receive the line number

POP1:      EX AF,AF'                        ; Z if no variable was given
           CALL CHKEND

           EX AF,AF'
           PUSH AF
           LD HL,(BSTKEND)
           LD A,(HL)
           INC A
           JR NZ,POP2

           RST &08
           DB ERR_NOPOPDATA

POP2:      CALL RETLOOP2                    ; HL = the line, A = the frame type and page
           LD B,A
           POP AF
           PUSH BC
           JR Z,POP4                        ; No variable to assign to

           INC H
           DEC H
           LD D,H
           LD E,H
           JR Z,POP3                        ; The frame refers to the edit line, so report line 0

           LD A,B
           CALL TSURPG
           LD D,(HL)
           INC HL
           LD E,(HL)                        ; DE = the line number

POP3:      EX DE,HL
           CALL STACKHL
           CALL ASSIGN

POP4:      POP AF
           AND &E0
           CP BSTKPROC
           JP Z,DELOCAL                     ; A PROC frame: discard its local variables too

POP5:      RET

POPLN:     EQU POP5-POPP2+1


; =====================================================================================================================
; INPP2 -- the INPUT command, copied to INSTBUF for execution
;
; INPUT accepts the same item list as PRINT -- separators, TAB, colour items, and parenthesised print items -- mixed
; with the variables being read. IPITEM decides which of those each item is.
;
; Reading a value runs the full editor over a workspace buffer, so all the line-editing keys work during INPUT. For
; a numeric or string variable the buffer is pre-loaded with a pair of quotes (strings) or left empty (numbers) and
; the result is syntax-checked as an expression; for INPUT LINE the raw characters are taken verbatim with no
; checking at all.
;
; A private error handler at INPERR catches typing mistakes and simply restarts the edit rather than aborting the
; program -- but only when reading from the keyboard channels, since a stream from a file has no way to retry.
; =====================================================================================================================

           ORG INSTBUF

INPP2:     CALL RUNFLG
           CALL C,CLSLOWER                  ; Clear the lower screen and select channel K, if running
           CALL SPACAN                      ; No indentation during INPUT
           INC A                            ; A = 1
           LD (TVFLAG),A
           CALL INPSL
           XOR A
           LD (FLAGX),A                     ; Not INPUT LINE, so listing works normally again
           CALL CHKENDCP

           CALL CLSLOWER
           LD A,(SPOSNU+1)
           LD HL,UWTOP
           SUB (HL)
           INC A
           LD (SCRCT),A                     ; Everything above the print position has been seen, so those lines can
                                            ; scroll off without a "scroll?" prompt
           RET


; --- INPSL: the item loop ---

INPSL:     RST &18
           CALL PRTERM
           JR Z,IP2CR                       ; End of statement

           CALL PRSEPR
           RET Z                            ; A terminator followed a separator

           CALL C,IPITEM
           JR INPSL

IP2CR:     LD A,(DEVICE)
           AND A
           JP Z,RUNCR                       ; A closing newline, on the upper screen

           RET


; --- IPITEM: one item, which may be a print item or a variable to read ---

IPITEM:    CP "("
           JR NZ,INP2

           RST &20
           CALL PRINT2                      ; A parenthesised print item
           RST &18
           JP INSISCBRK

INP2:      CP TOK_LINE
           JR Z,INP4

           CALL ALPHA
           JP NC,PRITEM                     ; Not a letter, so it must be a print item

           CALL SYNTAX1                     ; A variable; exits with DE -> FLAGX
           LD HL,FLAGX
           RES 7,(HL)
           JR INP5

INP4:      CALL SSYNTAX1                    ; Skip LINE and evaluate the variable
           CALL RUNFLG
           JP M,NONSENSE                    ; INPUT LINE needs a string variable

           LD HL,FLAGX
           SET 7,(HL)                       ; Using INPUT LINE

INP5:      CALL ABORTER

           PUSH HL
           CALL SETWORK
           POP HL
           SET 5,(HL)                       ; INPUT mode
           SET 6,(HL)                       ; Assume a numeric result
           LD BC,1
           CALL RUNFLG
           JP M,INP6                        ; Numeric: one byte of workspace, for the terminator

           RES 6,(HL)                       ; String result
           BIT 7,(HL)
           JR NZ,INP6                       ; INPUT LINE also needs only one byte

           LD C,3                           ; A string variable is primed with a pair of quotes

INP6:      CALL WKROOM
           LD (HL),&0D                      ; The terminator
           DEC C
           JR Z,INP7

           DEC HL
           LD A,&22
           LD (HL),A                        ; The closing quote
           LD (DE),A                        ; And the opening one

INP7:      LD (KCUR),HL                     ; The cursor starts at the terminator, or between the quotes
           IN A,(URPORT)
           LD (KCURP),A
           LD A,(FLAGX)
           RLA
           JR C,INP9                        ; INPUT LINE takes the text verbatim, with no syntax check

           LD A,(CHADP)
           PUSH AF
           LD HL,(CHAD)
           PUSH HL
           LD HL,(ERRSP)
           PUSH HL

INPERR:    LD HL,INPERR                     ; A typing error re-enters here rather than aborting
           PUSH HL
           XOR A
           LD (ERRNR),A
           CALL KSCHK
           JR NZ,INP8                       ; Not the keyboard, so retrying is not possible

           LD (ERRSP),SP

INP8:      CALL ADDRWK
           CALL REMOVEFP
           CALL EDITOR
           CALL TOKMAIN
           LD HL,FLAGS
           RES 7,(HL)                       ; Syntax time
           CALL INPAS
           AND A                            ; NC, so the CALL C below is skipped

INP9:      CALL C,EDCX                      ; INPUT LINE uses the plain editor

           CALL KSCHK
           JR NZ,INPA

           LD (KCUR+1),A                    ; No cursor wanted now
           CALL EDPRT                       ; Print the finished input line
           LD HL,(OLDPOS)
           LD BC,POSTORE
           CALL R1ONCLBC                    ; Leave the print position past the end of it

INPA:      LD HL,FLAGX
           LD A,(HL)
           RES 7,(HL)
           RES 5,(HL)
           RLA
           JR NC,INPC                       ; Not INPUT LINE

           CALL ADDRWK                      ; INPUT LINE: take the characters up to the terminator as the string
           LD D,H
           LD E,L
           LD BC,&FFFF                      ; -1, so the count excludes the terminator

INPBL:     LD A,(HL)
           INC HL
           INC BC
           CP &0D
           JR NZ,INPBL

           CALL STKSTOREP
           JP ASSIGN

INPC:      POP AF                           ; Discard the INPERR handler
           POP HL
           LD (ERRSP),HL
           POP HL
           LD (PRPTR),HL
           POP AF
           LD (PRPTRP),A                    ; The original CHAD, parked in an auto-adjusted system variable
           LD HL,FLAGS
           SET 7,(HL)                       ; Running
           CALL INPAS
           LD A,(PRPTRP)
           CALL SETCHADP
           LD HL,(PRPTR)
           LD (CHAD),HL
           RET


; --- INPAS: evaluate what was typed and assign it ---

INPAS:     LD HL,(WORKSP)
           LD (CHAD),HL
           LD A,(WORKSPP)
           CALL SETCHADP
           RST &18
           CP TOK_STOP
           JR NZ,INPA2

           CALL RUNFLG
           RET NC                           ; Syntax time, so STOP is just a word

           RST &08
           DB ERR_STOPINPUT

INPA2:     LD A,(FLAGX)
           CALL VALFET2
           RST &18
           CP &0D
           RET Z

           RST &08
INPFIN:    DB ERR_NONSENSE

INPLN:     EQU INPFIN+1-INPP2

                                            ; INPUT
