; =====================================================================================================================
; MISC2.ASM -- Error dispatch, ROM1-to-RAM stubs, LET, RUN/CLEAR, and the syntax helpers
; =====================================================================================================================
;
; ERROR DISPATCH
; --------------
; ERROR2 is the body of RST &08. It records where the error happened, offers it to the RST8V vector, and then either
; hands it to a resident DOS or stores it in ERRNR and unwinds the stack to ERRSP.
;
; Codes of 128 and above are DOS hook codes rather than errors, and may return normally.
;
; THE ROM1-TO-RAM STUBS
; ---------------------
; Several commands must read or write the BASIC program while executing. Their code cannot live in ROM1, because
; ROM1 occupies the same addresses as the program. The bodies are therefore assembled in ROM1 one after another,
; copied into a RAM buffer on demand, and executed there.
;
; Each stub loads HL with the body's address in ROM1 -- computed as &C000 plus the summed lengths of all the bodies
; before it -- and falls into BUFMV, which copies it to INSTBUF (or another buffer) and returns into it.
;
; The lengths themselves are the RENLN, GETLN, DELLN ... constants defined in MISCX1.ASM and MISCX2.ASM.
;
; SYNTAX HELPERS
; --------------
; The second half of the file is the library of argument-shape checkers that every command uses. They share one
; idiom: at syntax-check time each discards its caller's return address, so the command routine is abandoned once
; its arguments have been validated. That is what lets one routine serve both passes.
;
; =====================================================================================================================


; =====================================================================================================================
; ERROR2 -- the body of RST &08
; =====================================================================================================================
;
; Entry:  The byte following the RST is the error or hook code.
; Exit:   For an error, does not return: SP is reset from ERRSP. A hook handled by the DOS may return.
; ---------------------------------------------------------------------------------------------------------------------

ERROR2:     LD HL,(CHAD)
            LD (XPTR),HL                ; Remember where to print the flashing '?'
            EX AF,AF'
            LD A,(CHADP)
            LD (XPTRP),A
            POP DE
            LD A,(DE)
            INC DE
            PUSH DE                     ; The return address, now past the code byte
            DEC DE
            LD HL,(RST8V)
            INC H
            DEC H
            CALL NZ,HLJUMP              ; Let a utility see the error first

            LD A,(DOSCNT)
            RRCA
            LD A,(DE)                   ; The code
            JR C,NORMERR                ; The DOS is already in control, so do not recurse into it

            LD A,(DOSFLG)
            AND A
            LD A,(DE)
            JR NZ,PTDOS                 ; A DOS is resident, so it sees everything

            CP HOOK_BOOT
            JR C,NORMERR                ; An ordinary error

NODOS:      LD A,ERR_NODOS              ; A hook code with no DOS to handle it

NORMERR:    LD (ERRNR),A
            LD HL,DOSCNT
            RES 0,(HL)                  ; The DOS is no longer in control
            LD SP,(ERRSP)
            JP SETSTK


; ---------------------------------------------------------------------------------------------------------------------
; PTDOS -- hand an error or hook code to the DOS
;
; The DOS is paged into section A, which means running on a stack of its own since the caller's may be anywhere.
; Its entry points are &4200 for a hook code and &4203 for an error.
; ---------------------------------------------------------------------------------------------------------------------

PTDOS:      AND A
            JR Z,NORMERR                ; Code zero is "OK", which the DOS has no interest in

            LD E,A                      ; The code
            LD C,LRPORT
            IN B,(C)
            LD HL,0
            ADD HL,SP
            LD A,(DOSFLG)               ; Zero, or the DOS page
            DEC A                       ; One less, so the DOS itself lands in section B
            DI
            OUT (LRPORT),A              ; DOS at &4000, ROM0 on, ROM1 off
            LD SP,&8000                 ; A stack inside the DOS page
            EI
            PUSH BC                     ; B = the previous LMPR
            PUSH HL                     ; ... and the previous stack pointer
            LD A,E
            CP HOOK_BOOT
            JR NC,DOSHK

            CALL &4203                  ; An error rather than a hook
            SCF                          ; Record that it came from the error path

DOSHK:      CALL NC,&4200               ; A hook. The DOS must return NC from &4200.

DOSC:       POP HL
            POP BC
            DI
            OUT (C),B                   ; Restore the paging
            LD SP,HL
            EI

            LD HL,(DOSER)
            INC H
            DEC H
            JR NZ,DHLJ                  ; The DOS asked to be re-entered elsewhere

            JR NC,DOSNC                 ; The carry set above distinguishes error entry from hook entry

            LD HL,(ERRSP)               ; It was an error, so clear the stack back to the error frame
            DEC HL
            DEC HL
            LD SP,HL

DOSNC:      AND A
            JR NZ,NORMERR               ; A non-zero code remains, so report it

            DEC E
            JP Z,LDFL                   ; Hook 1: load the body of an already-opened file

            DEC E
            JP Z,SVFL                   ; Hook 2: save the whole file

            DEC E
            JP Z,LKTH                   ; Hook 3: find the header, then load the file

            RET                         ; Handled: return to the statement after the RST

DHLJ:       JP (HL)


; =====================================================================================================================
; Stubs for the command bodies that execute from RAM
; =====================================================================================================================
;
; Each loads the address of its body in ROM1 and falls through to BUFMV.
; ---------------------------------------------------------------------------------------------------------------------

MEPROG:                                 ; MERGE

 LD HL,&C000+RENLN+GETLN+DELLN+KEYLN+POPLN+INPLN+DKLN+RDLN+DFNLN+TOKLN
            DB SKIP3IX

INPUT:      LD HL,&C000+RENLN+GETLN+DELLN+KEYLN+POPLN
            DB SKIP3IX

RENUM:      LD HL,&C000                 ; The first body in ROM1
            LD BC,RENLN
            JR BUFMV


; ---------------------------------------------------------------------------------------------------------------------
; KEYIN -- KEYIN a$
;
; Copied to the header buffer rather than INSTBUF, so that a command executed by KEYIN cannot overwrite the copy
; that is running. Only the save and load executives disturb HDR, and they do so harmlessly here.
; ---------------------------------------------------------------------------------------------------------------------

KEYIN:      LD HL,&C000+RENLN+GETLN+DELLN
            LD DE,HDR
            LD BC,KEYLN
            JR BUFMV2


; ---------------------------------------------------------------------------------------------------------------------
; TOKMAIN / TOKDE -- run the tokeniser
;
; Entry:  TOKMAIN tokenises the edit line or workspace; TOKDE (used by VAL) tokenises the text at DE.
; Notes:  The tokeniser runs at CDBUFF+&80 rather than INSTBUF, because INSTBUF is in use by whichever command
;         invoked it.
; ---------------------------------------------------------------------------------------------------------------------

TOKMAIN:    CALL SETDE                  ; DE = the start of the edit line or of workspace

TOKDE:      EXX
            LD HL,&C000+RENLN+GETLN+DELLN+KEYLN+POPLN+INPLN+DKLN+RDLN+DFNLN
            LD DE,CDBUFF+&80            ; &4D80 to &4E24
            LD BC,TOKLN
            JR BUFMV2

GET:        LD HL,&C000+RENLN
            DB SKIP3IX

DELETE:     LD HL,&C000+RENLN+GETLN
            DB SKIP3IX

POP:        LD HL,&C000+RENLN+GETLN+DELLN+KEYLN
            DB SKIP3IX

DEFKEY:     LD HL,&C000+RENLN+GETLN+DELLN+KEYLN+POPLN+INPLN
            DB SKIP3IX

DEFFN:      LD HL,&C000+RENLN+GETLN+DELLN+KEYLN+POPLN+INPLN+DKLN+RDLN
            LD BC,&91                   ; DEF KEYCODE's own length is &90


; ---------------------------------------------------------------------------------------------------------------------
; BUFMV -- copy a body from ROM1 into RAM and enter it
;
; Entry:  HL = the body in ROM1, BC = its length; BUFMV2 also takes DE = the destination.
; Exit:   Returns *into* the copy, since the destination address is pushed as the return.
; ---------------------------------------------------------------------------------------------------------------------

BUFMV:      LD DE,INSTBUF

BUFMV2:     PUSH DE                     ; The copy's address becomes the return address
            PUSH AF
            LD A,LMPRSYSR1
            OUT (LRPORT),A              ; ROM1 on, so the body is readable
            LDIR
            LD A,LMPRSYS
            OUT (LRPORT),A              ; ROM1 off again, so the copy can reach the program
            POP AF
            RET                         ; ... into INSTBUF


; =====================================================================================================================
; LET and DEFAULT
; =====================================================================================================================
;
; DEFAULT assigns only when the variable does not exist, or holds "minus zero" -- the value PROC parameter binding
; writes into a shadowed second copy precisely so that DEFAULT treats it as undefined.
; ---------------------------------------------------------------------------------------------------------------------

DEFAULT:    LD A,&FF
            DB SKIP1CP

LET:        XOR A

            LD (LTDFF),A                ; &FF for DEFAULT, 0 for LET
            DB SKIP1CP

LETLP:      RST &20                     ; Skip the comma between assignments

            CALL SYNTAX1                ; Assess the destination
            RST &18
            CP "="
            JP NZ,NONSENSE

            RST &20
            LD A,(LTDFF)
            INC A
            JR NZ,LET3                  ; LET always assigns

            CALL RUNFLG                 ; DEFAULT still checks the value at syntax time
            JR NC,LET3

            LD A,(FLAGX)
            RRA
            JR C,LET3                   ; FFLXNEWVAR: it does not exist, so assign as LET would

;           LD HL,FLAGS
;           BIT 6,(HL)
;           JR Z,LET2                   ; Jump if a string

            LD A,(DFTFB)
            AND A
            JR Z,LET3                   ; It holds minus zero, so treat it as undefined

LET2:       CALL EXPTEXPR               ; It exists: evaluate the value only to step over it. Slower than a
                                        ; dedicated skip routine, but avoids needing one.
            CALL FDELETE
            JR LET4

LET3:       CALL VALFET1

LET4:       RST &18
            CP ","
            JR Z,LETLP

            RET


; ---------------------------------------------------------------------------------------------------------------------
; LABEL -- LABEL name
;
; Inert at run time. The compile pass assigns each label's line number to the named variable.
; ---------------------------------------------------------------------------------------------------------------------

LABEL:      CALL RUNFLG
            JP C,SKIPCSTAT

            DB SKIP1CP

; --- SVNUMV / VNUMV: skip and insist on a valid numeric variable. Used by COMPILE and POP. ---

SVNUMV:     RST &20

VNUMV:      CALL SYNTAX1
            LD HL,FLAGS
            BIT 6,(HL)
            RET NZ                      ; FFLAGNUM: numeric, as required

            RST &08
            DB ERR_NONSENSE


; =====================================================================================================================
; RUN and CLEAR
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; RUN -- RUN [line]
;
; Equivalent to GOTO line, RESTORE 0, CLEAR 0.
; ---------------------------------------------------------------------------------------------------------------------

RUN:        CALL SYNTAX3                ; A line number, or zero
            CALL GOTO2                  ; Set up the jump
            CALL RESTOREZ               ; RESTORE 0, which also maps the program page
            JR CLR1


; ---------------------------------------------------------------------------------------------------------------------
; CLEAR -- CLEAR [address]
;
; Clears the variables and stacks, and optionally moves RAMTOP.
; ---------------------------------------------------------------------------------------------------------------------

CLEAR:      CALL SYNTAX3
            CALL UNSTLEN                ; The address, in page form
            LD C,A
            DEC C
            OR H
            OR L
            SET 7,H
            JR NZ,CLR3                  ; An address was given

CLR1:       LD A,(RAMTOPP)              ; Otherwise keep the current RAMTOP
            LD HL,(RAMTOP)
            LD C,A

CLR3:       PUSH BC
            PUSH HL
            CALL ADDRNV
            EX DE,HL
            LD C,A                      ; CDE = NVARS
            LD HL,(ELINE)
            LD A,(ELINEP)
            CALL SUBAHLCDE              ; AHL = ELINE - NVARS, at least &025D
            LD BC,&025D                 ; The space a cleared variables area occupies
            CALL SUBAHLBC               ; AHL = the surplus to reclaim
            LD B,H
            LD C,L
            LD HL,(NVARS)
            CALL RECL2BIG
            CALL CLRSR                  ; Clear the variables and stacks
            CALL DOCOMP                 ; Labels and call buffers must be resolved again
            CALL MCLS
            LD HL,(WKEND)
            LD A,(WKENDP)
            LD BC,180                   ; A minimum working margin
            CALL ADDAHLBC
            POP DE
            POP BC                      ; CDE = the requested RAMTOP
            CALL SUBAHLCDE
            JR NC,RTERR                 ; It would leave too little room above the workspace

            LD A,(LASTPAGE)
            CP C
            JR NC,CLR4                  ; The page must be one BASIC owns

RTERR:      RST &08
            DB ERR_BADCLEAR

; --- Reset the machine stack. It should already be empty, but this guarantees it. ---

CLR4:       LD A,C
            LD (RAMTOPP),A
            LD (RAMTOP),DE
            POP HL                      ; The next-statement return
            POP BC                      ; The error handler
            LD SP,ISPVAL
            PUSH BC
            LD (ERRSP),SP
            JP (HL)


; ---------------------------------------------------------------------------------------------------------------------
; CLRSR -- clear variables, stacks and recording state
;
; Clears the calculator stack, the BASIC stack, the numeric and string variables, and turns off RECORD, the sound
; chip and ON ERROR.
; ---------------------------------------------------------------------------------------------------------------------

CLRSR:      CALL CLSND                  ; Silence the sound chip; returns A = 0
            LD (GRARF),A                ; Graphics recording off
            LD (ONERRFLG),A             ; ON ERROR off
            LD HL,(BASSTK)
            LD (HL),&FF                 ; The BASIC stack terminator
            LD (BSTKEND),HL
            CALL ADDRNV
            LD B,46

CLNVP:      LD (HL),&FF                 ; Empty every letter's chain
            INC HL
            DJNZ CLNVP                  ; 23 of the 26 roots; the remaining three are written from PSVTAB

            EX DE,HL
            LD HL,PSVTAB
            LD C,26
            LDIR                        ; The last three roots, plus the YOS and YRG pseudo-variables
            LD HL,PSVT2
            LD C,20
            LDIR                        ; ... and again for XOS and XRG
            EX DE,HL
            CALL SETNE                  ; NUMEND = here
            INC H
            INC H                       ; Leave 512 bytes of gap
            CALL SETSAV                 ; SAVARS = here
            LD (HL),VARSTERM
            DEC H
            DEC H
            DEC HL
            DEC HL
            DEC HL
            LD (HL),B                   ; B is zero: change YRG's stored 192 to 0 ...
            INC HL
            LD (HL),1                   ; ... and the next byte to 1, making it 256
            LD A,(THFATT)
            AND A
            RET NZ

            INC (HL)                    ; Thin pixels in mode 2, so XRG becomes 512
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SETSAV / SETNE / SETSYS -- store the current page and HL into a pointer system variable
;
; Adjusts the address into the &8000-&BFFF window if necessary, without changing HL. Only F and IY are altered.
; ---------------------------------------------------------------------------------------------------------------------

SETSAV:     LD IY,SAVARSP
            JR SETSYS

SETNE:      LD IY,NUMENDP

SETSYS:     PUSH AF
            IN A,(251)
            AND LMPRPAGE
            LD (IY+0),A
            LD (IY+1),L
            LD (IY+2),H
            POP AF
            BIT 6,H
            RET Z

            RES 6,(IY+2)                ; The address was in section D, so record the page above
            INC (IY+0)
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CLSND -- silence the sound chip by zeroing all 32 registers
; ---------------------------------------------------------------------------------------------------------------------

CLSND:      LD A,32

CSRL:       LD BC,SNDPORT+&0100         ; The address register is at &01FF
            DEC A
            OUT (C),A                   ; Select the register
            DEC B                       ; BC now addresses the data port
            OUT (C),B                   ; B is zero, so write zero
            AND A
            JR NZ,CSRL

            RET


; ---------------------------------------------------------------------------------------------------------------------
; PSVTAB / PSVT2 -- initial contents of the graphics pseudo-variables
;
; The X, Y and Z chain roots, followed by the YOS/YRG and XOS/XRG variables that scale graphics coordinates.
; ---------------------------------------------------------------------------------------------------------------------

PSVTAB:     DW &0019                    ; The X chain
            DW &0003                    ; The Y chain
            DW &FFFF                    ; The Z chain: empty

PSVT2:      DB 2                        ; Type/length: a two-character name
            DW 8
            DM "os"
            DB 0,0,0,0,0                ; YOS = 0

            DB 2
            DW &FFFF
            DM "rg"
            DB 0,0,192,0,0              ; YRG = 192, patched to 256 or 512 by CLRSR


; =====================================================================================================================
; S16OSR -- output to stream 16
; =====================================================================================================================
;
; Stream 16 is mapped internally onto stream -4, and its output is appended to a string variable. CLOSE #16 and
; OPEN #16 are not permitted.
;
;     RECORD TO a$: LET a$="": PRINT #16;"TESTING"
;
; leaves a$ holding "TESTING" and a carriage return. That gives serial files, token expansion into a string, CAT to
; a string, and the recording of graphics commands.
;
; Entry:  A = the character. Called with ROM1 paged out.
; ---------------------------------------------------------------------------------------------------------------------

S16OSR:     LD B,A
            IN A,(URPORT)
            PUSH AF
            PUSH BC
            LD HL,STRM16NM              ; The recorded type byte and name
            LD DE,TLBYTE
            LD BC,11
            LD A,(HL)
            LDIR
            LD C,A
            CALL STARYLK2
            JP Z,VNFERR                 ; The variable has been deleted since RECORD TO named it

            POP BC                      ; B = the character
            IN A,(URPORT)
            PUSH AF
            PUSH HL                     ; -> the length field
            PUSH BC
            LD A,(HL)
            INC HL
            LD C,(HL)
            INC HL
            RRCA
            RRCA
            OR (HL)
            LD B,A                      ; BC = the current length
            INC BC
            LD A,B
            INC A
            JR NZ,S16OK                 ; Lengths above &FEFF are refused

STLERR:     RST &08
            DB ERR_STRTOOLONG

S16OK:      PUSH BC                     ; The new length
            ADD HL,BC                   ; -> the last byte of the text
            CALL C,PGOVERF
            CALL CHKHL
            CALL MKRM1                  ; Open one byte at the end
            POP BC
            POP AF
            LD (HL),A                   ; Append the character
            POP DE
            POP AF
            OUT (URPORT),A              ; Map the length field again
            CALL MBC                    ; Write the new length
            POP AF
            OUT (URPORT),A
            RET

; --- MBC: store BC as the pages-plus-remainder length at (DE) ---

MBC:        CALL SPLITBC
            LD HL,PAGCOUNT
            LD BC,3
            LDIR
            RET


; =====================================================================================================================
; Syntax helpers
; =====================================================================================================================
;
; Each checks that the arguments have a particular shape. At syntax-check time they discard the caller's return
; address, abandoning the command routine once its arguments are validated.
; ---------------------------------------------------------------------------------------------------------------------

SSYNTAX3:   RST &20

; --- SYNTAX3: a number, or zero if the statement ends here ---

SYNTAX3:    RST &18
            CALL FETCHNUM
            RET C                       ; Running

            POP AF                      ; Checking: abandon the command
            RET

SSYNTAX6:   RST &20

; --- SYNTAX6: insist on one number ---

SYNTAX6:    CALL EXPT1NUM
            RET C

            POP AF
            RET

SSYNTAX8:   RST &20

; --- SYNTAX8: insist on two numbers ---

SYNTAX8:    CALL EXPT2NUMS
            RET C

            POP AF
            RET

SSYNTAXA:   RST &20

; --- SYNTAXA: insist on a string ---

SYNTAXA:    CALL EXPTSTR
            RET C

            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; Character class tests on the current character
; ---------------------------------------------------------------------------------------------------------------------

COMMASC:    CP ","                      ; Z for a comma or semicolon
            RET Z

            CP ";"
            RET


COCRCOTO:   CP TOTOK                    ; Z for TO, comma, colon or carriage return
            RET Z

COMCRCO:    CP ","                      ; Z for a comma, colon or carriage return
            RET Z

            DB SKIP1CP

RCRC:       RST &18                     ; Fetch, then test for colon or carriage return

CRCOLON:    CP ":"
            RET Z

            CP CC_ENTER
            RET

RICSC:      RST &18


; ---------------------------------------------------------------------------------------------------------------------
; Insisters -- demand a particular character and step over it
; ---------------------------------------------------------------------------------------------------------------------

INSISCSC:   CP ";"                      ; A comma or semicolon
            JR Z,INSCOMN

INSISCOMA:  CP ","
            JR NZ,SYNONS

INSCOMN:    RST &20
            RET

SINSISOBRK: RST &20

INSISOBRK:  CP "("
            JR NZ,SYNONS

            RST &20
            RET

EX1NUMCB:   CALL EXPT1NUM               ; A number then a closing bracket

INSISCBRK:  CP ")"
            JR NZ,SYNONS

            RST &20
            RET

EXPTCSTR:   RST &18                     ; A comma then a string
            CP ","
            JR NZ,SYNONS

SEXPTSTR:   RST &20

; --- EXPTSTR: insist on a string expression (jump table entry &011B) ---

EXPTSTR:    CALL SCANNING
            ADD A,A                     ; CY if running
            LD A,C
            RET P                       ; A string

SYNONS:     RST &08
            DB ERR_NONSENSE


; ---------------------------------------------------------------------------------------------------------------------
; Compound argument shapes
; ---------------------------------------------------------------------------------------------------------------------

EXPTCSTRB:  CALL EXPTCSTR               ; ",string)"
            JR EXCBRF

EXB2NUMB:   CALL SINSISOBRK             ; "(n,n)"
            CALL EXPT2NUMS
            JR EXCBRF

EXBSCNB:    CALL SINSISOBRK             ; "(a$,n)"
            CALL EXPTSTR
            CP ","
            JR NZ,SYNONS

SEX1NUMCB:  CALL SEXPT1NUM

EXCBRF:     CALL INSISCBRK

; --- RUNFLG: CY if running, P if the last value was a string, M if numeric ---

RUNFLG:     LD A,(FLAGS)
            ADD A,A
            RET

EXBNCSB:    CALL SINSISOBRK             ; "(n,a$)"
            CALL EXPT1NUM
            JR EXPTCSTRB

SEXPT4NUMS: RST &20

EXPT4NUMS:  CALL EXPT2NUMS              ; "n,n,n,n"
            CP ","
            JR NZ,SYNONS

SEXPT2NUMS: RST &20

EXPT2NUMS:  CALL EXPT1NUM               ; "n,n"

EXPTCNUM:   CP ","
            JR NZ,SYNONS

SEXPT1NUM:  RST &20

; --- EXPT1NUM: insist on a numeric expression (jump table entry &0118) ---

EXPT1NUM:   CALL SCANNING
            ADD A,A                     ; CY if running
            LD A,C
            RET M                       ; Numeric

            JR SYNONS


; ---------------------------------------------------------------------------------------------------------------------
; GETALPH -- insist that A is a letter
; ---------------------------------------------------------------------------------------------------------------------

GETALPH:    CALL ALPHA
            RET C

            JR SYNONS


; ---------------------------------------------------------------------------------------------------------------------
; SYNTAX9 -- colour items followed by a coordinate pair
;
; Used by PLOT, CIRCLE and FILL, as in "PLOT INK 3,PAPER 1;x,y".
; ---------------------------------------------------------------------------------------------------------------------

SYNTAX9:    CALL SYNT9SR
            JR EXPT2NUMS


; ---------------------------------------------------------------------------------------------------------------------
; FETCHNUM -- a number, or zero if the statement ends here
;
; Exit:   CY if running.
; ---------------------------------------------------------------------------------------------------------------------

FETCHNUM:   CALL CRCOLON
            JR NZ,EXPT1NUM

CONDSTK0:   LD A,(FLAGS)
            RLA
            RET NC                      ; Not running

            XOR A
            CALL STACKA                 ; Supply the default of zero
            SCF
            RET


SEXPTEXPR:  RST &20

; --- EXPTEXPR: an expression of either type (jump table entry &011E). Z for a string, NZ for a number. ---

EXPTEXPR:   CALL SCANNING
            RLA                         ; CY if running
            BIT 7,A
            LD A,C
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CHKENDCP / CHKEND / ABORTER -- end-of-statement handling
;
; ABORTER returns normally when running; otherwise it discards a return address, abandoning the command routine.
; ---------------------------------------------------------------------------------------------------------------------

CHKENDCP:   CALL SELCHADP
            DB SKIP1CP

SABORTER:   RST &20                     ; Skip and abort at syntax time. Used by PI, RAMTOP, FREE and the like.

CHKEND:
ABORTER:    LD C,A
            LD A,(FLAGS)
            RLA
            LD A,C
            RET C

            POP AF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; Character classification
; ---------------------------------------------------------------------------------------------------------------------

; --- ALPHA: CY if A is a letter ---

ALPHA:      CP "A"
            CCF
            RET NC                      ; Below 'A'

            CP "z"+1
            RET NC                      ; Above 'z'

            CP "Z"+1
            RET C                       ; Upper case

            CP "a"
            CCF
            RET                         ; Between 'Z' and 'a', so not a letter

; --- ALPHANUM: CY if A is a letter or digit ---

ALPHANUM:   CALL ALPHA
            RET C

; --- NUMERIC: CY if A is a digit ---

NUMERIC:    CP "9"+1
            RET NC

            CP "0"
            CCF
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ALDU -- CY if A is a letter, an underline or a '$'
;
; This is the test the tokeniser applies to the character after a matched keyword. It is why "printer", "print_out"
; and "print$" are left alone while "print1" and "print:" are tokenised.
; ---------------------------------------------------------------------------------------------------------------------

ALDU:       CALL ALPHA
            RET C

            CP "$"
            SCF
            RET Z

            JR CKUND

; --- ALNUMUND: CY if A is a letter, digit or underline ---

ALNUMUND:   CALL ALPHANUM
            RET C

CKUND:      CP "_"
            SCF
            RET Z

            AND A
            RET


; =====================================================================================================================
; BRKLSSL -- the bracketless slicer
; =====================================================================================================================
;
; Parses the line range used by LIST, DELETE and AUTO: "10 TO 30", "TO 100", "100 TO", "TO", or nothing at all.
;
; Entry:  CHAD at the possible range, A = the character there.
; Exit:   FIRST and LAST hold the range, defaulted where a value was omitted. CHAD points at the first character
;         that is neither alphanumeric nor TO. When running, CY means a value was out of range, and A is zero when
;         only a single number was given.
; ---------------------------------------------------------------------------------------------------------------------

BRKLSSL:    LD HL,1                     ; The default lower bound
            LD DE,MAXLINENUM            ; ... and upper
            LD (FIRST),HL
            LD (LAST),DE
            CP TOTOK
            JR Z,BRL2                   ; The range begins with TO

            CALL ALPHANUM
            RET NC                      ; No range at all, as in a bare LIST; NC means "in range"

            CALL GIR2                   ; Evaluate the first number; NC if running
            JR C,BRL1                   ; Not running

            LD BC,(FIRST)               ; The minimum
            SBC HL,BC
            ADD HL,BC
            LD (FIRST),HL
            RET C                       ; Below the minimum

BRL1:       CP TOTOK
            LD A,0                      ; XOR A cannot be used: it would disturb the flags
            JR NZ,BRL3                  ; A single number, flagged by A = 0. LAST becomes the same value.

BRL2:       RST &20
            CALL ALPHANUM
            RET NC                      ; "LIST 10 TO" with nothing after it

            CALL GIR2
            CCF
            RET NC                      ; Syntax check of, say, "LIST 10 TO 20"

            LD HL,(LAST)                ; The maximum
            SBC HL,BC
            RET C                       ; Above it

            LD H,B
            LD L,C

BRL3:       LD (LAST),HL
            AND A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GIR / GIR2 -- evaluate a number, but only when running
;
; Entry:  GIR with CHAD before the expression, GIR2 with CHAD at it.
; Exit:   CHAD past it, A = the next character, BC and HL = the value when running. CY when not running.
; ---------------------------------------------------------------------------------------------------------------------

GIR:        RST &20

GIR2:       CALL EXPT1NUM
            CCF
            RET C                       ; Not running

            CALL GETINT
            RST &18
            LD H,B
            LD L,C
            AND A
            RET


; =====================================================================================================================
; DISPLAY -- select which screen is shown
; =====================================================================================================================
;
; DISPLAY 0 means "show whichever screen is being drawn on".
; ---------------------------------------------------------------------------------------------------------------------

DISPLAY:    CALL SYNTAX3

            CALL GETBYTE

SETDISP:    LD (CURDISP),A
            AND A
            JR Z,DEFDISP

            RST &30
            DW SCRNTLK2                 ; Look the screen up; Z if it is not open
            JR NZ,VIDSEL

ISCRERR:    RST &08
            DB ERR_BADSCRNUM            ; An error resets CURDISP to zero

; --- DEFDISP: show the current screen. Also used when reporting errors. ---

DEFDISP:    LD A,(CUSCRNP)              ; The page being drawn on, including its mode bits

VIDSEL:     RST &30
            DW CUS2                     ; Is it already the one displayed?

            RET Z

            PUSH DE                     ; D = the new page
            AND A                       ; NC: save the palette
            CALL SDISR                  ; Map the outgoing screen and copy the working palette into it, so that it
                                        ; can be restored if that screen is displayed again
            POP AF
            OUT (VIDPORT),A             ; Show the new one
            SCF                          ; CY: load the palette

; --- SDISR: copy the palette between PALTAB and a screen's own store. CY to load, NC to save. ---

SDISR:      EX AF,AF'
            IN A,(251)
            PUSH AF
            EX AF,AF'
            PUSH AF
            INC A                       ; The second page of the screen holds the palette
            CALL TSURPG
            LD HL,PALBUF-&4000
            LD DE,PALTAB
            POP AF
            JR C,SDIS2

            EX DE,HL                    ; Saving rather than loading

SDIS2:      LD BC,PALTABLEN
            LDIR
            JP PPORT                    ; Restore the paging and return


; ---------------------------------------------------------------------------------------------------------------------
; PRSVARS / RSVARS / SSVARS -- move the print variables between a screen and the system variables
;
; Each screen keeps its own windows, cursor position and colours in the spare space at the end of its second page.
; ---------------------------------------------------------------------------------------------------------------------

PRSVARS:    LD (CUSCRNP),A

RSVARS:     SCF                          ; Restore from the screen
            DB SKIP1LDH

SSVARS:     AND A                       ; Save to the screen

            LD HL,BGFLG
            LD DE,PVBUFF
            JR NC,SSVRC

            EX DE,HL

SSVRC:      CALL SPSSR
            LD BC,PRPOSN-BGFLG          ; The first block: BGFLG to SPOSNL
            LDIR
            LD C,CEXTAB-PRPOSN
            ADD HL,BC
            EX DE,HL
            ADD HL,BC                   ; Step both pointers on to the expansion tables
            EX DE,HL
            LD C,&40                    ; CEXTAB and EXTAB together
            LDIR
            JP RCURPR


; =====================================================================================================================
; R0INST -- the INSTR search
; =====================================================================================================================
;
; Entry:  HL -> where to start in the search string, BC = the starting position, DE = bytes to check,
;         the target is at INSTBUF with its length in A, and C' holds the wildcard character.
; Exit:   BC = the one-based position of the match, or zero with CY if there was none.
; ---------------------------------------------------------------------------------------------------------------------

R0INST:     PUSH BC                     ; The starting position
            LD B,D
            LD C,E                      ; BC = bytes to check
            LD DE,INSTBUF               ; The target
            PUSH BC

LOOKLP:     PUSH AF                     ; The target length
            EX   AF,AF'                 ; A' counts down the characters matched so far
            LD   A,(DE)                 ; The target's first character
            CPIR                        ; Find it in the search string
            JP PO,NOTFND0               ; Not present at all

            PUSH HL                     ; The search position
            DB SKIP1LDA                 ; HL already points at the second character

CHKNXTC:    INC HL

            EX   AF,AF'
            DEC  A
            JR   Z,FOUND                ; Every character matched

            EX   AF,AF'
            INC  DE
            LD   A,(DE)
            CP   (HL)
            JR   Z,CHKNXTC

            EXX
            CP C                        ; C' is the wildcard, normally '#'
            EXX

            JR   Z,CHKNXTC              ; The wildcard matches anything

            LD DE,INSTBUF               ; The match failed, so start the target again
            POP  HL
            POP  AF
            JR   LOOKLP


FOUND:      POP  HL                     ; The search position
            POP  HL                     ; The target length
            POP  HL                     ; The original byte count
            AND A
            SBC  HL,BC                  ; ... minus those left gives the number examined
            POP  BC                     ; The starting position
            ADD  HL,BC
            LD   B,H
            LD   C,L
            RET                         ; BC = the position; NC


; --- NOTFND0: the first character never appeared; HL is past the last position examined ---

NOTFND0:    POP  AF                     ; The target length
;           EX AF,AF'
            POP  AF                     ; The byte count

NOTFND2:    POP  DE                     ; The starting position

NOTFND3:    LD   BC,&0000
            SCF
            RET

                                        ; Routines in this file: LET/DEFAULT, LABEL, RUN, CLEAR, S16OP, the syntax
                                        ; helpers, DISPLAY, SCREEN, SETSV
