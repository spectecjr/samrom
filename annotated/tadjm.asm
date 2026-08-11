; =====================================================================================================================
; TADJM.ASM -- Core services: calculator stack, program search, memory management, page arithmetic
; =====================================================================================================================
;
; The routines nearly every other module depends on.
;
;   Keyboard          GETKEY, READKEY, KBFLUSH
;   Calculator stack  STACKA/BC/HL, STKSTORE, STKFETCH, FDELETE, GETINT
;   Program search    SRCHPROG and the FINDER engine behind DO, IF, DATA, FOR and RENUM
;   Memory            MAKEROOM, RECLAIM, WKROOM, and the pointer adjustment that keeps everything consistent
;   Addressing        the page-form arithmetic used for every address above 64K
;   Tape              the edge timer
;
; PAGE FORM
; ---------
; SAM addresses up to 512K, so a pointer is a page number plus a 16-bit address normalised into the &8000-&BFFF
; window. Arithmetic on such pointers goes through AHLNORM, which converts to a flat 19-bit value, and PAGEFORM,
; which converts back. ADDAHLBC and friends wrap the pair.
;
; MAKEROOM AND RECLAIM
; --------------------
; Inserting or deleting bytes in the middle of the BASIC area moves everything above the change. Both routines call
; XOINTERS, which adjusts the fourteen pointer system variables, every FOR variable's loop-back address and every
; BASIC stack frame, then shift the block with FARLDIR or FARLDDR. Anything below the change point is untouched --
; which is what makes the "raise PROG to carve a hole" trick in docs/hudg.md work.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; NMISTOP -- the super-break handler, reached through the NMI vector
;
; Abandons whatever was running and reports BREAK, on a freshly reset stack.
; ---------------------------------------------------------------------------------------------------------------------

NMISTOP:    LD SP,ISPVAL
            LD DE,MAINER
            PUSH DE
            LD (ERRSP),SP
            RST &08
            DB ERR_BRKINTO


; ---------------------------------------------------------------------------------------------------------------------
; GETKEY -- take a key from the buffer
;
; Exit:   NZ with the code in A, or Z and A = 0 if none.
; ---------------------------------------------------------------------------------------------------------------------

GETKEY:     CALL KEYRD
            RET Z

            JR KBF2


; ---------------------------------------------------------------------------------------------------------------------
; READKEY -- read the keyboard directly, as INKEY$ does (jump table entry &0169)
;
; Performs a fresh hardware scan rather than reading the queue, so a key that has since been released is not
; reported. That also means it cannot be satisfied by pre-loading the queue.
;
; Exit:   CY and NZ with the code in A, or Z and NC if no key is down.
; ---------------------------------------------------------------------------------------------------------------------

READKEY:    RST &30
            DW TWOKSC                   ; Scan for up to two simultaneous keys
            JR Z,RKY2

            XOR A
            RET                         ; Z, NC: nothing pressed

RKY2:       RST &30
            DW KYVL                     ; Translate the port readings into a key code
            AND A                       ; NZ
            SCF                          ; "got a key"

; --- KBFLUSH: empty the queue (jump table entry &0166) ---

KBFLUSH:    LD HL,0
            LD (KBQP),HL                ; Head and tail both zero

KBF2:       LD HL,FLAGS
            RES 5,(HL)                  ; FFLAGKEY clear: no key waiting
            RET


; ---------------------------------------------------------------------------------------------------------------------
; KEYRD -- scan the keyboard and return the queue head
; ---------------------------------------------------------------------------------------------------------------------

KEYRD:      RST &30
            DW KEYRD2
            LD A,(FLAGS)
            AND FFLAGKEY                ; Z if no key arrived
            LD A,(LASTK)
            JR KBF2


; =====================================================================================================================
; The floating point calculator stack
; =====================================================================================================================
;
; Every entry is NUMVALSIZE bytes. STKEND points at the first free byte and the stack grows upwards from FPSBOT.
; The same five bytes hold either a number or a string descriptor -- see docs/machine-code-interface.md.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; STACKHL / STACKA / STACKBC -- push a small integer
;
; Exit:   DE = the new STKEND.
; ---------------------------------------------------------------------------------------------------------------------

STACKHL:    LD D,L
            LD C,H
            JR STACKCM

STACKA:     LD B,0
            LD C,A

STACKBC:    LD D,C
            LD C,B

STACKCM:    XOR A                       ; Exponent zero marks the small-integer form; also gives NC
            LD B,A                      ; High byte of the value
            LD E,A                      ; Sign: positive

; --- STKSTOREX: entry from TRUNC$, which wants DE returned as STKEND ---

STKSTOREX:  CALL STKSTORE
            EX DE,HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; STKSTOREP / STKST0 / STKSTOS / STKSTORE -- push a five-byte entry
;
; Entry:  STKSTOREP with DE = start and BC = length of a string in the currently mapped page;
;         STKSTORE (jump table entry &0127) with the five bytes already in A, E, D, C, B.
;
; For a string: A = page with bit 7 set if the old copy should be deleted after assignment, DE = start, BC = length.
; For a number: A = exponent (or zero), E = sign, DC = value, B = 0.
; ---------------------------------------------------------------------------------------------------------------------

STKSTOREP:  IN A,(251)

STKST0:     AND &7F                     ; Bit 7 clear: an array element or slice, so do not delete the original

STKSTOS:    LD HL,FLAGS
            RES 6,(HL)                  ; FFLAGNUM clear: the result is a string

STKSTORE:   LD HL,(STKEND)
            LD (HL),A                   ; Page and flags for a string; exponent for a number
            INC HL
            LD (HL),E                   ; Sign for a small integer
            INC HL
            LD (HL),D                   ; Start address for a string
            INC HL
            LD (HL),C                   ; CD is the value for a small integer
            INC HL
            LD (HL),B                   ; Length for a string
            INC HL
            LD (STKEND),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; STKFETCH -- pop a five-byte entry (jump table entry &0124)
;
; Exit:   A, E, D, C, B -- the exact inverse of STKSTORE.
; ---------------------------------------------------------------------------------------------------------------------

STKFETCH:   LD HL,(STKEND)
            DEC HL
            LD B,(HL)
            DEC HL
            LD C,(HL)
            DEC HL
            LD D,(HL)
            DEC HL
            LD E,(HL)
            DEC HL
            LD A,(HL)

STSTKE:     LD (STKEND),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; FDELETE -- drop the top entry without copying it
;
; Exit:   HL -> the dropped value, so the caller can still read or move it.
; Notes:  Only the low byte of STKEND is written on the fast path, which is valid because the stack is small and
;         page-aligned; the high byte is only corrected when the subtraction borrows, which never happens on a
;         standard machine.
; ---------------------------------------------------------------------------------------------------------------------

FDELETE:    LD HL,(STKEND)
            LD A,L
            SUB NUMVALSIZE
            LD L,A
            LD (STKEND),A
            RET NC

            DEC H
            JR STSTKE


; ---------------------------------------------------------------------------------------------------------------------
; HLTOFPCS -- push the five bytes at (HL)
; ---------------------------------------------------------------------------------------------------------------------

HLTOFPCS:   LD BC,NUMVALSIZE
            LD DE,(STKEND)
            LDIR
            LD (STKEND),DE
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GETINT / GETBYTE -- pop an integer (jump table entry &0121)
;
; Exit:   GETINT gives BC and HL, GETBYTE gives A and C.
; Notes:  Raises ERR_IOOR for a negative value, or one too large for the requested width.
; ---------------------------------------------------------------------------------------------------------------------

GETINT:     CALL FPTOBC
            JR GETIBC

GETBYTE:    CALL FPTOA

GETIBC:     JR C,IOORERR                ; Out of range

            RET Z                       ; Positive

IOORERR:    RST &08
            DB ERR_IOOR


; ---------------------------------------------------------------------------------------------------------------------
; FPTOBC -- pop the top entry as a 16-bit integer
;
; Exit:   BC and HL = the value, A = C.
;         CY if it will not fit, NZ if it was negative.
; Notes:  A floating point value is first rounded by adding a half and taking INT, which also converts it to the
;         small-integer form when it fits.
; ---------------------------------------------------------------------------------------------------------------------

FPTOBC:     LD HL,(STKEND)
            LD BC,-NUMVALSIZE
            ADD HL,BC
            LD A,(HL)
            AND A                       ; NC
            JR Z,FPBCINT                ; Already a small integer

            DB CALC
            DB STKHALF
            DB ADDN
            DB INT                      ; Rounds, and converts to integer form where possible
            DB EXIT

FPBCINT:    LD (STKEND),HL              ; Drop it
            XOR A
            SUB (HL)                    ; NC only if the exponent byte is zero, i.e. integer form
            INC HL
            BIT 7,(HL)                  ; NZ if negative
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            LD A,C
            LD H,B
            LD L,C
            RET Z                       ; Positive

            RET C                       ; Out of range

            SBC HL,HL                   ; HL = 0
            SBC HL,BC                   ; Negate: the result is NZ with CY
            CCF
            LD B,H
            LD C,L
            LD A,C
            RET                          ; The negated value in HL and BC; NZ, NC


; ---------------------------------------------------------------------------------------------------------------------
; FPTOA -- pop the top entry as a byte
;
; Exit:   A and C = the value; CY if it exceeds 255, NZ if it was negative.
; ---------------------------------------------------------------------------------------------------------------------

FPTOA:      CALL FPTOBC
            RET C

            EX AF,AF'
            INC B                       ; Test B without disturbing the flags
            EX AF,AF'
            DJNZ FPTOA2                 ; B was non-zero, so the value exceeds 255

            RET

FPTOA2:     SCF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SETMIN / SETWORK / SETSTK -- reset the working areas
;
; SETMIN empties the edit line, SETWORK the workspace, SETSTK the calculator stack. Each falls into the next.
; ---------------------------------------------------------------------------------------------------------------------

SETMIN:     IN A,(URPORT)
            PUSH AF
            CALL ADDRELN
            CALL SETKC2                 ; Put the cursor at the start
            LD (HL),CC_ENTER            ; An empty line is just a carriage return ...
            INC HL
            LD (HL),VARSTERM            ; ... followed by the stopper
            INC HL
            LD (WORKSP),HL
            LD (WORKSPP),A
            POP AF
            OUT (URPORT),A

SETWORK:    LD HL,(WORKSP)
            LD A,(WORKSPP)
            LD (WKEND),HL
            LD (WKENDP),A

SETSTK:     LD HL,(FPSBOT)
            LD (STKEND),HL
            RET


; =====================================================================================================================
; The program searcher
; =====================================================================================================================
;
; One engine serves DO/LOOP, IF/ELSE/END IF, DEF FN, DATA, FOR/NEXT and RENUM. It walks the program from CHAD
; looking for a target token, counting nested occurrences of a second token so that structures match up correctly.
;
; Entry:  E   the token to find
;         D   the token that opens a nested structure, or TOK_THEN meaning "none"
;         B   nesting depth, normally 1
;         C   a secondary target, armed only when the depth returns to zero (used for ELSE)
;         C'  the value C is reloaded with at that point
;         B'  &FF to search the whole program, 0 for one line only
;         A'  the current statement number
;
; Exit:   CY with CHAD just past the target and A = the statement number it was found in.
;         The alternate A' holds which of the two targets matched.
;
; Invisible numeric forms, quoted strings and REM statements are all stepped over, so a colon inside a string or a
; byte inside a stored number can never be mistaken for a separator.
; ---------------------------------------------------------------------------------------------------------------------

SRCHPROG:   LD D,TOK_THEN               ; No nesting token

SEARCHALL:  EXX
            LD BC,&FF00+TOK_THEN        ; Whole program; no secondary target
            EXX

SRCHALL2:   LD BC,&0100+TOK_THEN        ; Depth 1; no secondary target

SRCHALL3:   RST &18                     ; Start at CHAD
            LD A,(SUBPPC)
            JR FINDERS

; --- FINCSTAT: a statement separator, so count it ---

FINCSTAT:   EX AF,AF'
            INC A

FINDERS:    EX AF,AF'
            JR FINDER

FSKIP5:     INC HL                      ; Step over the five bytes of an invisible form

FSKIP4:     INC HL                      ; Step over a four-byte line header
            INC HL
            INC HL
            INC HL

FINDER:     LD A,(HL)
            INC HL
            CP NUMMARKER
            JR Z,FSKIP5

            CP CC_ENTER
            JR Z,FINDER5                ; End of the line

            CP TOK_REM
            JR Z,FREMARK                ; Skip REM text, which may contain anything

            CP &22
            JR Z,FQUOTE                 ; Skip a quoted string

            CP ":"
            JR Z,FINCSTAT

            CP TOK_THEN
            JR Z,FINCSTAT               ; THEN also separates statements

            CP D
            JR Z,FINTERV                ; A nested structure opens here

                                        ; The secondary target is inert unless this is a LELSE or LIF search and
                                        ; the nesting count shows we are at the outermost level
            CP C
            JR Z,FOUNDY

FINDER4:    CP E
            JP NZ,FINDER

            DJNZ FOUNDX                 ; Depth is not yet zero, so this belongs to a nested structure

FOUNDY:     LD (CHAD),HL                ; CHAD -> just past the target
            EX AF,AF'
            SCF
            RET

FOUNDX:     DJNZ FINDN1                 ; The count was more than one

            EXX                         ; It has just fallen to one, so arm the secondary target
            LD A,C
            EXX
            LD C,A

FINDN1:     INC B                       ; Undo the DJNZ's decrement
            JR FINDER

FREMARK:    LD A,CC_ENTER

FREMLP:     CP (HL)
            INC HL
            JP NZ,FREMLP                ; Run to the end of the line

FINDER5:    LD A,(HL)                   ; High byte of the next line number, or the program terminator
            EXX
            CP B                        ; B' is 0 for a one-line search or &FF for the whole program
            EXX                         ; The edit line needs a terminator for this to work
            RET NC                      ; Finished

            BIT 6,H
            CALL NZ,INCURPAGE
            LD (CLA),HL                 ; Track the line we are now in
            LD A,1                      ; Statement 1
            EX AF,AF'
            JP FSKIP4                   ; Step over the header and continue

FQUOTE:     CP (HL)
            INC HL
            JP NZ,FQUOTE                ; Run to the closing quote

            JR FINDER

FINTERV:    INC B                       ; One more level to close
            LD C,TOK_THEN               ; Disarm the secondary target while nested
            JR FINDER4


; =====================================================================================================================
; MAKEROOM and RECLAIM
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; MKRMCH -- open BC bytes at (HL) with no free-space reserve
;
; Used only by the editor, which may legitimately use the last of memory.
; ---------------------------------------------------------------------------------------------------------------------

MKRMCH:     XOR A
            PUSH HL
            CALL TSTRMBIG
            JR MKRM2


; ---------------------------------------------------------------------------------------------------------------------
; MKRM1 / MAKEROOM / MKRBIG -- open space at (HL)
;
; Entry:  MKRM1 for one byte, MAKEROOM for BC bytes (BC below &4000), MKRBIG for A pages plus BC bytes.
; Exit:   HL -> the space, DE -> its last byte when it is under 16K.
; Notes:  Insists on a 150-byte reserve remaining, so that the interpreter always has room to report an error.
; ---------------------------------------------------------------------------------------------------------------------

MKRM1:      LD BC,1

MAKEROOM:   XOR A

MKRBIG:     PUSH HL                     ; Where to open the space
            CALL TSTRMBIG
            LD HL,150
            SBC HL,DE
            JP NC,OOMERR

MKRM2:      LD D,B
            LD E,C
            LD C,A
            LD A,D
            AND &3F
            LD D,A                      ; CDE = the size in page form; NC signals "making room"
            POP HL
            PUSH DE                     ; The size modulo 16K
            PUSH HL                     ; Where
            RST &30
            DW XOINTERS                 ; Adjust every pointer at or above here; returns AHL = the old WKEND and
                                        ; sets PAGCOUNT and MODCOUNT to the block that must move
            LD DE,(WKEND)
            LD BC,(WKENDP)              ; CDE = the new WKEND
            CALL FARLDDR                ; Shift the block up, working downwards to avoid overlap
            POP DE                      ; Where
            POP HL                      ; The size
            ADD HL,DE
            EX DE,HL
            DEC DE                      ; DE -> the last byte of the new space
            RET


; ---------------------------------------------------------------------------------------------------------------------
; FNORECL / NORECL -- delete a program line
; ---------------------------------------------------------------------------------------------------------------------

FNORECL:    CALL FNDLINE
            RET NZ                      ; No such line

NORECL:     CALL NEXTONE                ; BC = the whole length of the line
            JR RECLAIM2


; ---------------------------------------------------------------------------------------------------------------------
; RECLAIM1 / RECLAIM2 / RECL2BIG -- close up space
;
; Entry:  RECLAIM1 with DE = the start and HL = the end; RECLAIM2 (jump table entry &0163) with BC bytes at HL;
;         RECL2BIG with A pages plus BC bytes at HL.
; ---------------------------------------------------------------------------------------------------------------------

RECLAIM1:   CALL DIFFER                 ; BC = HL - DE, and HL becomes the start

RECLAIM2:   XOR A

RECL2BIG:   RES 7,B                     ; The size is at most 16K, so clear the two high bits
            RES 6,B
            LD D,A
            OR B
            OR C
            RET Z                       ; Nothing to do

            LD A,D
            LD D,B
            LD E,C
            LD C,A                      ; CDE = the size
            PUSH BC
            PUSH DE
            PUSH HL
            SCF                         ; CY signals "reclaiming"
            RST &30
            DW XOINTERS
            POP HL
            POP DE
            POP BC
            IN A,(251)
            PUSH AF
            PUSH HL
            BIT 6,H
            JR Z,RECL5

            RES 6,H                     ; Keep the source inside the window
            INC A

RECL5:      CALL ADDAHLCDE              ; AHL = just past the space, the source of the move
            POP DE
            POP BC
            LD C,B                      ; CDE = the space itself, the destination
            PUSH DE
            CALL FARLDIR
            POP HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; WKROOM -- extend the workspace (jump table entry &0109)
;
; Entry:  BC = bytes wanted.
; Exit:   DE -> the start of the new space, HL -> its end (when under 16K), BC unchanged, A preserved.
; Notes:  No block move is needed, since the workspace is the top of the movable area.
; ---------------------------------------------------------------------------------------------------------------------

WKROOM:     PUSH AF
            CALL TESTROOM               ; Check it fits; AHL = the new WKEND
            LD D,A
            LD A,(WKENDP)
            CALL SELURPG                ; Map the old end
            LD A,D
            LD (WKENDP),A
            LD DE,(WKEND)               ; The start of the new space
            LD (WKEND),HL
            LD H,D
            LD L,E
            ADD HL,BC
            DEC HL                      ; Its end, which may lie above &C000
            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ASSV -- adjust one stored page/address triple
;
; Entry:  HL -> the triple, CDE = the location bytes were inserted or removed at, CY' set when reclaiming.
; Notes:  A pointer at or below the location is left alone. That is what preserves anything stored below PROG.
; ---------------------------------------------------------------------------------------------------------------------

ASSV:       PUSH HL
            POP IY
            LD B,1

PNLP:       LD A,(IY+0)
            LD L,(IY+1)
            LD H,(IY+2)                 ; AHL = the stored pointer
            INC H
            DEC H
            JR Z,NPSV                   ; A zero high byte means the edit line, which never moves

            BIT 6,H
            JR Z,PNT2                   ; Already in section C

            INC A                       ; Normalise a section D address
            RES 6,H

PNT2:       AND LMPRPAGE
            CP C
            JR C,NPSV                   ; The change is in a higher page, so this pointer is unaffected

            JR NZ,PADJ                  ; The change is in a lower page, so it must be adjusted

            EX DE,HL
            SBC HL,DE                   ; Same page: compare the offsets
            ADD HL,DE
            EX DE,HL
            JR NC,NPSV                  ; The pointer is at or below the change point

PADJ:       PUSH BC
            PUSH DE
            LD BC,(TEMPW4)
            LD DE,(TEMPW5)              ; CDE = the amount to adjust by
            EX AF,AF'
            JR C,PRECL

            EX AF,AF'
            CALL ADDAHLCDE
            JR PNT3

PRECL:      EX AF,AF'
            CALL SUBAHLCDE

PNT3:       POP DE
            POP BC
            LD (IY+0),A
            LD (IY+1),L
            LD (IY+2),H

NPSV:       INC IY
            INC IY
            INC IY
            DJNZ PNLP

            RET


; ---------------------------------------------------------------------------------------------------------------------
; AFLPS -- adjust the loop-back address of every FOR variable
;
; Entry:  HL -> the numeric chain roots, C'D'E' = the change location.
; ---------------------------------------------------------------------------------------------------------------------

AFLPS:      EX AF,AF'
            LD C,D
            LD B,26                     ; One chain per letter

AFML:       PUSH HL

AFLL:       LD E,(HL)
            INC HL
            LD D,(HL)
            ADD HL,DE                   ; Follow the relative link
            JR C,AFLE                   ; The chain has ended

            BIT 6,(HL)
            JR Z,AFNF                   ; TLFORVAR clear: an ordinary variable

            PUSH HL
            PUSH BC
            LD A,(HL)
            AND TLNAMELEN
            ADD A,18                    ; 3 to reach the value, 15 more past value, limit and step
            LD E,A
            LD D,0
            ADD HL,DE                   ; -> the loop-back triple
            LD DE,(TEMPW3)
            CALL ASSV
            POP BC
            POP HL

AFNF:       INC HL
            JR AFLL

AFLE:       POP HL
            INC HL
            INC HL                      ; -> the next chain root
            DJNZ AFML

            EX AF,AF'
            RET


; =====================================================================================================================
; ADDRxxx -- page in a memory area and load its address
; =====================================================================================================================
;
; Each loads the low byte of the corresponding page-byte address, then falls into ADDRSV, which supplies the high
; byte. Exploits the fixed page/low/high layout of the pointer system variables.
;
; Exit:   A = the page (now selected), HL = the address.
; ---------------------------------------------------------------------------------------------------------------------

ADDRDEST:   LD L,DESTP\256
            JR ADDRSV

ADDRNV:     LD L,NVARSP\256
            JR ADDRSV

ADDRNE:     LD L,NUMENDP\256
            JR ADDRSV

ADDRSAV:    LD L,SAVARSP\256
            JR ADDRSV

ADDRWK:     LD L,WORKSPP\256
            JR ADDRSV

ADDRKC:     LD A,KCURP\256
            DB SKIP2LDHL

ADDRPROG:   LD A,PROGP\256
            DB SKIP2LDHL

ADDRELN:    LD A,ELINEP\256
            DB SKIP2LDHL

; --- ADDRDATA: used by READ and ITEM ---

ADDRDATA:   LD A,DATADDP\256
            DB SKIP2LDHL

ADDRCHAD:   LD A,CHADP\256

            LD L,A


; ---------------------------------------------------------------------------------------------------------------------
; ADDRSV -- page in and load from a pointer system variable
;
; Entry:  HL -> the page byte of the triple.
; Exit:   The page is selected, HL = the address, A = the page.
; ---------------------------------------------------------------------------------------------------------------------

ADDRSV:     LD H,VAR2/256

; --- ASV2: entered from the FN code with HL = DEFADDP ---

ASV2:       LD A,(HL)
            CALL SELURPG
            INC HL
            LD A,(HL)
            INC HL
            LD H,(HL)
            LD L,A
            IN A,(251)
            AND LMPRPAGE
            RET


; ---------------------------------------------------------------------------------------------------------------------
; NEXTONE / DIFFER -- measure a program line, and the gap between two pointers
; ---------------------------------------------------------------------------------------------------------------------

NEXTONE:    PUSH HL
            INC HL
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)                   ; The line length
            INC HL
            ADD HL,BC
            POP DE                      ; DE = the start, HL = the next line

DIFFER:     AND A
            SBC HL,DE
            LD B,H
            LD C,L
            ADD HL,DE
            EX DE,HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LIMDB / LIMBYTE -- range-check the top calculator value
;
; Entry:  D = the exclusive upper limit, E = the error code to raise if it is exceeded.
; Exit:   A and C = the value, DE unchanged.
; Notes:  LIMDB decrements the value before checking and returns it decremented, but leaves C alone; that suits
;         arguments quoted from one upwards, such as MODE.
; ---------------------------------------------------------------------------------------------------------------------

LIMDB:      LD A,&FF                    ; Added below, so the value is decremented
            DB SKIP1CP

LIMBYTE:    XOR A

            PUSH AF
            PUSH DE
            CALL FPTOA
            POP DE
            JR C,ERRORE                 ; Over 255

            JR NZ,ERRORE                ; Negative

            POP AF
            ADD A,C
            CP D
            RET C                       ; Within the limit

ERRORE:     LD HL,ERRNR
            LD (HL),E
            PUSH HL                     ; Popped and used as the "return address" by the error handler
            JP &0008


; ---------------------------------------------------------------------------------------------------------------------
; SPLITBC -- express BC as PAGCOUNT 16K pages plus MODCOUNT bytes
; ---------------------------------------------------------------------------------------------------------------------

SPLITBC:    PUSH AF
            LD A,B
            RES 7,B
            RES 6,B
            LD (MODCOUNT),BC            ; The remainder, under 16K
            RLCA
            RLCA
            AND &03
            LD (PAGCOUNT),A             ; The whole pages, 0-3
            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GETROOM -- free memory
;
; Exit:   AHL = RAMTOP minus the end of workspace, as a 19-bit value; NZ if it is 64K or more.
; ---------------------------------------------------------------------------------------------------------------------

GETROOM:    PUSH BC
            PUSH DE
            CALL WENORMAL               ; AHL = the end of workspace

GRM2:       LD C,A
            EX DE,HL                    ; CDE = it
            CALL RTNORMAL               ; AHL = RAMTOP
            SCF
            SBC HL,DE
            SBC A,C
            POP DE
            POP BC
            RET


; =====================================================================================================================
; Page-window arithmetic
; =====================================================================================================================
;
; Pointers live in the &8000-&BFFF window. When arithmetic pushes one outside it, the page must change to match.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; PGOVERF / PGOA -- correct a pointer after an addition carried
;
; Entry:  HL = 0000-&BFFE, the wrapped result.
; Exit:   PGOVERF also updates HMPR; PGOA only adjusts A and HL.
; ---------------------------------------------------------------------------------------------------------------------

PGOVERF:    IN A,(URPORT)
            CALL PGOA
            JR PGOE

PGOA:       ADD A,2                     ; A carry means at least &10000 was passed, so two pages, and the address
                                        ; can be brought back down by 32K
            BIT 6,H
            JR Z,PGOA2

            RES 6,H                     ; Another 16K
            INC A

PGOA2:      BIT 7,H
            JR Z,PGOA3

            ADD A,2                     ; And another 32K

PGOA3:      SET 7,H
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ADDRELND / DECPTR / CHKPTR -- step a pointer back, correcting the page
;
; Entry:  DECPTR with HL = the address; CHKPTR when it has already been decremented.
; Notes:  Copes with an underflow of up to 32K, which is what SYNTAX4 can produce.
; ---------------------------------------------------------------------------------------------------------------------

ADDRELND:   CALL ADDRELN                ; The end of the string area is one below the edit line

DECPTR:     DEC HL

CHKPTR:     BIT 7,H
            RET NZ                      ; Still &8000 or above

            IN A,(251)
            DEC A
            SET 7,H
            BIT 6,H
            JR NZ,DECPT2                ; Fell into &4000-&7FFF: one page back

            DEC A                       ; Fell into 0000-&3FFF: two pages back

DECPT2:     RES 6,H

PGOE:       OUT (251),A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ADDAHLBC / SUBAHLBC -- add or subtract BC from a page-form address
;
; Entry:  A = page, HL = address, BC = any 16-bit value.
; Exit:   AHL updated, BC unchanged, CY on overflow.
; ---------------------------------------------------------------------------------------------------------------------

ADDAHLBC:   CALL AHLNORM
            ADD HL,BC
            ADC A,0
            JR PAGEFORM

SUBAHLBC:   CALL AHLNORM
            AND A
            SBC HL,BC
            SBC A,0
            JR PAGEFORM


; ---------------------------------------------------------------------------------------------------------------------
; ADDAHLCDE / SUBAHLCDE -- add or subtract two page-form addresses
;
; Entry:  AHL and CDE both in page form.
; Exit:   AHL updated, CDE unchanged, CY on overflow.
; ---------------------------------------------------------------------------------------------------------------------

ADDAHLCDE:  PUSH BC
            PUSH DE
            CALL TWOCONV
            ADD HL,DE
            ADC A,C
            JR PPFCOM

SUBAHLCDE:  PUSH BC
            PUSH DE
            CALL TWOCONV
            AND A
            SBC HL,DE
            SBC A,C

PPFCOM:     POP DE
            POP BC


; ---------------------------------------------------------------------------------------------------------------------
; PAGEFORM -- convert a 19-bit value in AHL back to page form
;
; Exit:   A = page, HL = &8000-&BFFF, CY if the value exceeded the addressable range.
; ---------------------------------------------------------------------------------------------------------------------

PAGEFORM:   RL H
            RLA
            RL H
            RLA                         ; Shift the two high bits of the address into the page; NC
            RR H
            SCF
            RR H                        ; Rebuild the address with bit 15 set
            CP &20                      ; 32 pages is the largest machine
            CCF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; TWOCONV / CDENORM -- convert page-form values to 19-bit
; ---------------------------------------------------------------------------------------------------------------------

TWOCONV:    CALL AHLNORM

CDENORM:    PUSH AF
            EX DE,HL
            LD A,C
            CALL AHLNORM
            EX DE,HL
            LD C,A
            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; RTNORMAL / WENORMAL -- fetch RAMTOP or the end of workspace as a 19-bit value
; ---------------------------------------------------------------------------------------------------------------------

RTNORMAL:   LD A,(RAMTOPP)
            LD HL,(RAMTOP)
            JR AHLNORM

WENORMAL:   LD A,(WKENDP)
            LD HL,(WKEND)
            BIT 6,H
            JR Z,AHLNORM

            INC A                       ; The workspace end may sit in section D


; ---------------------------------------------------------------------------------------------------------------------
; AHLNORM -- convert page form to a 19-bit value
;
; The top three bits of A and the top two of HL are ignored on entry.
; ---------------------------------------------------------------------------------------------------------------------

AHLNORM:    RLC H
            RLC H
            RRA
            RR H
            RRA
            RR H
            AND &07
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SETESP -- install a temporary error frame
;
; Exit:   The old ERRSP is on the stack. A routine that calls this may then call others and still regain control
;         after an error.
; Uses:   HL only.
; ---------------------------------------------------------------------------------------------------------------------

SETESP:     LD HL,(ERRSP)
            EX (SP),HL
            PUSH HL
            LD (ERRSP),SP
            RET


; ---------------------------------------------------------------------------------------------------------------------
; RDRLEN / RDLLEN / RDTHREE -- read a three-byte page-form value from a header buffer
;
; RDRLEN reads the requested header, RDLLEN the loaded one.
;
; Exit:   C = pages, DE = the remainder.
; ---------------------------------------------------------------------------------------------------------------------

RDRLEN:     LD L,(HDR+HDN+3)\256
            DB SKIP2LDDE

RDLLEN:     LD L,(HDL+HDN+3)\256

            LD H,HDR/256

RDTHREE:    LD C,(HL)
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            RET


; =====================================================================================================================
; EDGE2 -- the tape edge timer (jump table entry &017B)
; =====================================================================================================================
;
; Waits for the tape signal to change level, counting the time taken. The border is flipped on every edge, which
; produces the loading stripes and confirms visually that a signal is being received.
;
; Entry:  B = the previous edge type in bit 6, plus the border and MIC bits to preserve.
; Exit:   A and C = the pulse length; CY if an edge was found, NC and Z on timeout, NC on BREAK.
;
; EDGE2 waits for two edges, giving a full cycle; EDGSENS waits for one.
; ---------------------------------------------------------------------------------------------------------------------

EDGE2:      LD C,0

EDGEC:      CALL EDGSENS
            RET NC                      ; BREAK or timeout

            AND A                       ; NC

EDGSENS:    LD A,8                      ; A short settling delay, so one edge is not counted twice

EWL:        DEC A
            JR NZ,EWL

EDGLP:      IN A,(KEYPORT)
            INC C
            RET Z                       ; The counter wrapped: NC, Z means timeout

            XOR B                       ; Compare the EAR bit ...
            AND &40                     ; ... with the previous edge type
            LD A,B
            JR Z,EDGLP                  ; No change yet. 47T per pass, padded to near a multiple of 8.

            XOR &67                     ; Flip the edge type (bit 6) and the border (bits 2-0),
                                        ; leaving MIC (bit 3), the speaker (bit 4) and screen-off (bit 7) alone
            LD B,A

            AND &1F                     ; Clear screen-off, MIDI-through and the border's high bit

            OUT (KEYPORT),A             ; Show the edge on the border
            LD A,&F7
            IN A,(STATPORT)             ; Bit 5 is low while ESC is held
            RLCA
            RLCA
            RLCA                        ; Move it into carry
            LD A,C                      ; The pulse length
            RET                         ; CY if all is well, NC if ESC was pressed
