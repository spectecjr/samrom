; =====================================================================================================================
; MAINLP.ASM -- The interpreter main loop
; =====================================================================================================================
;
; The centre of the whole system. Contains the syntax-check pass, the statement dispatcher used for both checking and
; running, the outer edit-and-execute loop, line insertion, and error handling.
;
; ONE DISPATCHER, TWO MODES
; -------------------------
; A line is walked by exactly the same code whether it is being checked or run; FLAGS bit 7 (FFLAGRUN) selects which.
; Every command routine begins by testing that flag and, at check time, discards its own return address so that only
; the argument validation happens. That idiom lives in the SYNTAX helpers in MISC2.ASM.
;
; The check pass is not merely a validation. As the expression evaluator walks each numeric literal it writes the
; pre-converted binary value into the line, and each FN or PROC reference gains a call buffer. See
; docs/tokenized-program-format.md.
;
; WHERE EXECUTION LIVES
; ---------------------
; CHAD is the interpreter's program counter. CLA points at the start of the line being executed and NXTLINE at the
; one after it, so that a jump can be resolved without rescanning. PPC and SUBPPC name the current line and
; statement for error reports and CONTINUE. NSPPC is &FF when execution simply flows on, or a statement number when
; a jump to NEWPPC is pending.
;
; ERROR PATH
; ----------
; RST &08 resets SP from ERRSP. During normal execution ERRSP points at a frame whose return address is MAINER, so
; every error, and the normal end of a program, arrives there.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; LINESCAN -- syntax-check the edit line
;
; Entry:  The tokenised line in ELINE.
; Exit:   ERRNR holds the result; the line has gained its invisible numeric forms and call buffers.
; ---------------------------------------------------------------------------------------------------------------------

LINESCAN:     LD HL,FLAGS
              RES 7,(HL)                ; FFLAGRUN clear: checking, not running
              XOR A
              LD H,A
              LD L,A
              LD (IFTYPE),HL            ; Long IF, and no FN seen yet in this line
              LD (SUBPPC),A             ; Start at statement zero
              LD (ERRNR),A              ; No error yet
              CALL EVALLINO             ; Step over any line number
              JR NC,STMTLP1             ; In range

NONSENSE:     RST &08
              DB ERR_NONSENSE


; ---------------------------------------------------------------------------------------------------------------------
; LOOPEL / LINERUN -- run the edit line
;
; Entry:  LOOPEL with C = the statement to start at (used by RETURN and LOOP when the frame refers to the edit line);
;         LINERUN to start wherever NSPPC says.
; Notes:  CLA's high byte is forced to zero. That is the marker for "the current line is the edit line", which
;         RETURN, NEXT and LOOP all test before trying to treat CLA as a program address.
; ---------------------------------------------------------------------------------------------------------------------

LOOPEL:       LD A,C

LOOPEL2:      LD (NSPPC),A

LINERUN:      XOR A
              LD (CLA+1),A              ; A zero page byte marks the edit line
              LD HL,&FFFF               ; PPC = &FFFF, which the number printer renders as 0
              LD (PPC),HL
              CALL AELP                 ; Address ELINE and set the page bytes to match
              EX DE,HL
              LD HL,(WORKSP)
              DEC HL                    ; DE -> the start of the line, HL -> its end
              LD A,(NSPPC)
              JP NEXTLINE


; ---------------------------------------------------------------------------------------------------------------------
; SEARCH -- find a matching structure keyword and continue there
;
; Entry:  D = the token that counts as "intervening" for nesting, E = the token to find,
;         the byte after the CALL = the error code if it is not found.
;         The search starts at CHAD.
; Exit:   Never returns to the caller. On success execution resumes at the token found; on failure the error is
;         raised.
;
; Used by DO (find LOOP), DEF PROC (find END PROC) and the long IF forms.
; ---------------------------------------------------------------------------------------------------------------------

SEARCH:       CALL SEARCHALL
              JP NC,&0008               ; Not found: the byte after the CALL becomes the error code

; --- Found. CLA and CHAD are set and A holds the statement number the target was in. ---
; --- CHAD points past END PROC, LOOP, ELSE, END IF or NEXT (with its variable skipped). A LOOP may still have a  ---
; --- WHILE or UNTIL clause to step over.                                                                        ---

              POP DE                    ; Discard the return address and the error byte with it
              LD (SUBPPC),A

; --- EXCHAD2: resume execution at CHAD. Also used by FOR and the short IF. ---

EXCHAD2:      IN A,(URPORT)
              CALL STPGS                ; Set CHADP, NXTLINEP and CLAPG to the current page
              LD HL,(CLA)
              INC H
              DEC H
              JR Z,STMHOP               ; The edit line: PPC and NXTLINE are already right

              LD D,(HL)
              INC HL
              LD E,(HL)                 ; The line number
              INC HL
              LD (PPC),DE
              LD E,(HL)
              INC HL
              LD D,(HL)                 ; The line length
              INC HL
              ADD HL,DE
              LD (NXTLINE),HL           ; Where the following line begins

STMHOP:       RST &18
              CP TOK_WHILE
              JR C,STMTLP2

              CP TOK_UNTIL+1
              CALL C,SKIPCSTAT          ; A WHILE or UNTIL clause: skip the rest of the statement

              JR STMTLP2


; =====================================================================================================================
; The statement loop
; =====================================================================================================================
;
; This is both the syntax checker and the run-time engine. Each pass isolates one statement, looks up its command
; routine, and calls it with NEXTSTAT pushed as the return address.
; ---------------------------------------------------------------------------------------------------------------------

STMTLP:       INC HL                    ; Step over the ':' that ended the previous statement

STMTLP05:     LD (CHAD),HL

; --- STMTLP1: entry from ELSE, and the first statement of a line ---

STMTLP1:      CALL SETWORK              ; Discard any workspace the last statement created
              LD HL,SUBPPC
              INC (HL)

; --- STMTLP2: entry from ELSE during a syntax check ---

STMTLP2:      LD HL,(CHAD)

STMTLP25:     LD A,(HL)
              CP CC_SIGNIF
              JR NC,STMTLP3             ; A significant character

              CP CC_ENTER
              JP Z,LINEEND

              INC HL                    ; Skip spaces and control codes
              LD (CHAD),HL
              JR STMTLP25

STMTLP3:      CP ":"
              JR Z,STMTLP                ; An empty statement

              LD DE,NEXTSTAT            ; Command routines return here

ON4ENT:       PUSH DE                   ; ON enters here with its own return address
              LD (CSA),HL               ; Remember where this statement starts
              LD HL,(CMDV)
              INC H
              DEC H
              CALL NZ,HLJUMP            ; Let a utility add or intercept commands

              LD (CURCMD),A             ; SAVE/LOAD and the colour commands read this back
              SUB TOK_CMDFIRST
              JP C,PROCS                ; Below &90: a letter, so this is a procedure call

              CP TOK_CMDLAST-TOK_CMDFIRST
              JR NC,NONSX               ; Above the last implemented command

              ADD A,A                   ; Two bytes per table entry
              LD C,A
              LD B,0
              LD HL,(CMDADDRT)
              ADD HL,BC
              LD C,LRPORT
              IN B,(C)
              SET 6,B
              OUT (C),B                 ; ROM1 on, since the table lives there
              LD E,(HL)
              INC HL
              LD D,(HL)
              RST &20                   ; Step CHAD past the command token
              BIT 7,D
              JR NZ,R1CMD               ; A ROM1 address (&C000 and above), so leave ROM1 paged in

              RES 6,B
              OUT (C),B                 ; A ROM0 routine, so page ROM1 back out

R1CMD:        EX DE,HL
              JP (HL)                   ; Execute. At check time the routine returns early via ABORTER.


; ---------------------------------------------------------------------------------------------------------------------
; NEXTSTAT -- return point after every statement
;
; Deals with a pending jump if there is one, otherwise moves on to the next statement or line.
; ---------------------------------------------------------------------------------------------------------------------

NEXTSTAT:     CALL BRKSTOP              ; BREAK is tested between statements

NOBREAK:      CALL R1OCHP               ; ROM1 off, CHAD's page selected
              LD A,(NSPPC)
              INC A
              JR Z,STMTNEXT             ; &FF: no jump pending

              LD HL,(NEWPPC)            ; The line to jump to
              INC H
              JP Z,LINERUN              ; &FFxx means the edit line

              DEC H
              CALL FNDLNHL              ; Find the line, or the first one after it
              PUSH AF
              IN A,(URPORT)
              CALL STPGS
              POP AF
              LD A,(NSPPC)
              JR Z,LINEUSE              ; Exact match

              AND A
              JP NZ,STATLOST            ; RETURN and friends demand the exact statement; only GOTO and GOSUB,
                                        ; which use statement 0, tolerate a missing line

              LD C,(HL)                 ; Line number high byte, or the program terminator
              INC C
              JR NZ,LINEUSE             ; A real line follows, so run that instead

OKERR:        RST &08
              DB ERR_OK                 ; Ran off the end of the program


STMTNEXT:     RST &18

STMTNEXT1:    CP ":"

STMTLPH:      JP Z,STMTLP

              CP TOK_THEN
              JR Z,STMTLPH              ; THEN also separates statements, as IF needs

              CP CC_ENTER
              JR Z,LINEEND

NONSX:        RST &08
              DB ERR_NONSENSE

REMARK:       POP AF                    ; REM: discard the NEXTSTAT return and ignore the rest of the line


; ---------------------------------------------------------------------------------------------------------------------
; LINEEND -- the end of a line has been reached
; ---------------------------------------------------------------------------------------------------------------------

LINEEND:      CALL ABORTER              ; Returns to the caller's caller at syntax check time
              JR LNEND2

; --- OLNEND: used by ON at run time, where only one statement should execute ---

OLNEND:       CALL R1OCHP

LNEND2:       LD HL,(NXTLINE)
              LD A,(HL)
              INC A
              JR Z,OKERR                ; The program terminator: the program has finished

              XOR A                     ; Statement 0, which LINEUSE turns into 1. The distinction matters only
                                        ; when a jump target is missing, which cannot apply here.

; ---------------------------------------------------------------------------------------------------------------------
; LINEUSE / NEXTLINE -- begin executing the line at HL
;
; Entry:  HL -> the line, A = the statement to start at
; ---------------------------------------------------------------------------------------------------------------------

LINEUSE:      CP 1
              ADC A,0                   ; Statement 0 becomes 1; anything else is unchanged
              BIT 6,H
              JR Z,NONEWCLAPG           ; Still inside the paging window

              PUSH AF
              CALL INCURPAGE            ; Crossed into the next 16K, so advance the page

; --- RLEPI: entered with A = page, (SP) = statement, HL -> the line ---

RLEPI:        CALL STPGS                ; Set CLAPG, CHADP and NXTLINEP
              POP AF

NONEWCLAPG:   LD (CLA),HL               ; Recorded so GOSUB and DO can return here
              LD D,(HL)
              INC HL
              LD E,(HL)
              INC HL
              LD (PPC),DE
              LD E,(HL)
              INC HL
              LD D,(HL)
              EX DE,HL                  ; DE -> the length high byte
              INC HL                    ; HL = length + 1
              ADD HL,DE                 ; -> the first character of the next line
              INC DE                    ; -> the first character of this one

NEXTLINE:     LD (NXTLINE),HL
              EX DE,HL                  ; HL -> the first character
              LD D,A                    ; The statement wanted
              LD A,&FF
              LD (NSPPC),A              ; No further jump pending
              ADD A,D
              LD (SUBPPC),A             ; Statement number minus one
              JP Z,STMTLP05             ; Statement 1: start straight away

              CALL SKIPSTATS            ; Skip forward, leaving CHAD on the ':' or THEN before it
              JP Z,STMTNEXT1

STATLOST:     RST &08
              DB ERR_NOSTMT


; ---------------------------------------------------------------------------------------------------------------------
; BREAK testing
;
; BRKCR reports "BREAK - CONTINUE to repeat", used inside operations that should be resumed; BRKSTOP reports
; "BREAK into program", used between statements.
; ---------------------------------------------------------------------------------------------------------------------

BRKCR:        CALL BRKTST
              RET NZ

BRCERR:       RST &08
              DB ERR_BRKCONT

BRKSTOP:      CALL BRKTST
              RET NZ                    ; ESC not pressed

              RST &08
              DB ERR_BRKINTO

; --- BRKTST: Z if ESC is pressed and BREAK has not been disabled ---

BRKTST:       LD A,&F7                  ; Select the keyboard half-row holding ESC
              IN A,(STATPORT)
              AND &20                   ; The ESC bit
              RET NZ

              LD A,(BREAKDI)            ; Non-zero disables BREAK
              AND A
              RET


; =====================================================================================================================
; The outer loop: edit, tokenise, check, then insert or run
; =====================================================================================================================

; --- AULL: entry from AUTO, which has already listed the program ---

AULL:         CALL AUL2
              JR MAINX

MAINEADD:     CALL INSERTLN             ; The line had a number, so insert it
              LD A,(ERRNR)
              AND A
              JP NZ,MAINER              ; No room

MAINEXEC:     CALL AUTOLIST

MAINX:        CALL SETMIN               ; Empty the edit line

MAINELP:      CALL STRM0
              CALL EDITOR               ; Returns when ENTER is pressed
              CALL TOKMAIN              ; Replace spelled-out keywords with tokens
              CALL LINESCAN             ; Check the syntax and embed the invisible forms
              LD A,(SUBPPC)
              RLA
              JR NC,MAINE1              ; 127 statements or fewer

              LD A,ERR_NOROOMLINE       ; More than that cannot be addressed by a one-byte statement number
              LD (ERRNR),A

MAINE1:       LD A,(ERRNR)
              AND A
              JR Z,MAINE2               ; No error

              LD A,(DEVICE)
              DEC A
              JR NZ,MAINER              ; Not the lower screen, so report the error properly

              CALL ADDRELN              ; Interactive: buzz and let the user correct the line
              CALL REMOVEFP             ; Strip the forms the check pass inserted
              CALL RSPNS
              JR MAINELP

MAINE2:       CALL EVALLINO             ; A line number at the start?
              JP C,NONSENSE             ; Out of range

              JR NZ,MAINEADD            ; Yes: insert the line into the program

              RST &18
              CP CC_ENTER
              JR Z,MAINEXEC             ; The line was just ENTER

; --- A direct command: run it ---

              LD A,(FLAGS2)
              RRA
              CALL C,CLSUP              ; FFL2DIRTY: clear the listing away first
              CALL CLSLOWER
              LD A,(UWTOP)
              LD B,A
              LD A,(SPOSNU+1)
              SUB B
              INC A                     ; Rows already used in the upper screen
              LD (SCRCT),A              ; ... may scroll away without a prompt
              LD HL,FLAGS
              SET 7,(HL)                ; FFLAGRUN: running
              DEC HL
              XOR A
              LD (HL),A                 ; ERRNR = 0
              INC A
              LD (NSPPC),A              ; Begin at statement 1
              CALL COMPILE              ; Resolve labels, DEF FN and DEF PROC call buffers
              CALL LINERUN


; =====================================================================================================================
; MAINER -- where every program ends
; =====================================================================================================================
;
; Reached by RST &08 for an error, for a normal end, and for STOP. Restores a sane state, then either transfers to an
; ON ERROR handler or prints a report.
; ---------------------------------------------------------------------------------------------------------------------

MAINER:       CALL R1OCHP
              EI
              LD HL,SUBPPC
              LD A,(HL)
              AND A
              JR NZ,MAINER1

              LD A,(ONSTORE)            ; ON fakes SUBPPC while dispatching; recover the real value
              LD (HL),A

MAINER1:      LD HL,0
              LD (DEFADD),HL            ; Not inside a DEF FN any more
              LD (XPTR),HL              ; No error position marker
              LD A,H
              INC HL
              LD (STREAMS+6),HL         ; Stream 0 points at channel K again
              LD (FLAGX),A
              LD (AUTOFLG),A            ; AUTO off
              CALL SETDISP              ; Show the current screen
              CALL SETMIN

              LD A,(ERRNR)
              AND &EF                   ; Ignore the difference between OK (0) and STOP (&10)
              JR Z,MAINER3              ; Neither is an error, so no ON ERROR handler runs

              CALL KBFLUSH
              LD HL,FLAGS
              SET 7,(HL)                ; VAL may have cleared the running flag; restore it
              LD HL,ONERRFLG
              BIT 7,(HL)
              RES 7,(HL)                ; Consume the temporary arming; the permanent bit is untouched
              JR Z,MAINER3              ; ON ERROR was not armed

              CALL ERRHAND2             ; Record CONTINUE information without printing a report
              LD HL,MAINER
              PUSH HL                   ; The handler's own errors come back here
              RST &30
              DW SETUPVARS              ; Create the variables lino, stat and error
              LD A,(ERRNR)
              CP ERR_BRKINTO
              JR NZ,MAINER2

              CALL CONTINUE2            ; After BREAK, CONTINUE holds the right place to resume
              LD (PPC),HL
              DEC D
              LD A,D
              LD (SUBPPC),A             ; Resume at the same statement, not the next one

MAINER2:      LD HL,(ERRLN)             ; The line holding the ON ERROR statement
              CALL FNDLNHL
              JR NZ,STATLH

              INC HL
              INC HL
              INC HL
              INC HL
              LD A,(ERRSTAT)
              LD D,A
              CALL SKIPSTATS
              RST &20                   ; -> the ON ERROR token
              CP TOK_ONERROR

STATLH:       JP NZ,STATLOST            ; The line has been edited since; the handler no longer exists

              RST &20                   ; Step past it to the handler itself, typically GOTO or GOSUB.
                                        ; CLA, NXTLINE and PPC still describe the line the error occurred in.
              JP STMTLP25

MAINER3:      CALL CLSLOWER
              LD HL,TVFLAG
              SET 5,(HL)                ; FTVCLRLS: the report is cleared by the next keystroke
              DEC HL                    ; -> FLAGS
              RES 7,(HL)                ; FFLAGRUN clear, so line searches start from PROG while editing
              LD A,(ERRNR)
              CALL ERRHAND1
              JP MAINELP


; ---------------------------------------------------------------------------------------------------------------------
; ERRHAND1 -- print an error report
;
; Entry:  A = the error code.
; Notes:  Code &50 is not an error but the copyright banner, used by MNINIT and NEW. Codes &51 and above are DOS
;         errors, whose text comes from the DOS page rather than the ROM table.
; ---------------------------------------------------------------------------------------------------------------------

ERRHAND1:     CP ERR_BANNER
              JR NZ,EHZ

; --- The MGT banner, shown at startup and after NEW ---

              XOR A
              CALL UTMSG                ; "  MILES GORDON TECHNOLOGY PLC" / "    C 1990  SAM Coup"
              LD HL,BGFLG
              LD A,&82                  ; The accented e, which needs the extended character set
              LD (HL),A                 ; Non-zero selects the foreign set
              RST &10
              LD (HL),0
              LD A," "
              RST &10
              LD A,(PRAMTP)
              INC A                     ; 16 or 32 pages
              LD L,A
              LD H,0
              ADD HL,HL                 ; Each page is 16K, so four doublings give the size in K
              ADD HL,HL
              ADD HL,HL
              ADD HL,HL
              LD B,H
              LD C,L
              RST &30
              DW PRNUMB1
              LD A,"K"
              RST &10

WTFK:         CALL READKEY              ; A direct hardware scan, so a queued key will not satisfy it
              JR Z,WTFK

              CALL CLSLOWER
              LD A,&FF
              LD (LINICOLS),A           ; Switch off the rainbow border
              JP ERRHAND2

EHZ:          JR C,EH0                  ; Below &51: an ordinary ROM error

              SUB ERR_DOSBASE           ; A DOS error: renumber from zero
              LD C,A
              LD A,(DOSFLG)
              CALL SELURPG              ; Page the DOS in at &8000
              LD HL,(&8210)             ; Its message table
              LD A,C
              DB SKIP3IX                ; Skip the LD HL below

EH0:          LD HL,(ERRMSGS)

EH15:         EX DE,HL
              RST &30
              DW POMSR                  ; Expand the message into the buffer; BC = its length
              LD A,(WINDRHS)
              SUB C                     ; Columns left over
              CP 13                     ; Room for ", 12345:11" plus a little
              PUSH AF
              JR NC,EH1                 ; It will fit on one line

              LD A,(LWTOP)
              LD (SPOSNL+1),A           ; Start on the upper of the two lower-screen lines

EH1:          PUSH BC
              LD A,(ERRNR)
              PUSH AF
              RST &30
              DW PRAREG                 ; Print the error number
              LD A," "
              RST &10
              POP AF
              SUB ERR_NOTFOUND
              JR NZ,EH2                 ; Not the "not found" error

; --- Error 2 names the variable, so print it before the message ---

              LD B,A
              LD HL,TLBYTE
              LD A,(HL)
              AND TLNAMELEN
              LD C,A                    ; Name length for strings and arrays, length-1 for simple numerics
              BIT 5,(HL)                ; TLNUMARRAY
              INC HL
              LD D,H
              LD E,L
              ADD HL,BC                 ; -> past the name, or its last character for a numeric
              INC BC                    ; The true length for a numeric, or room for a '$' or '('
              JR NZ,PMV1                ; A numeric array

              LD A,(FLAGS)
              BIT 6,A
              JR NZ,PMV2                ; A simple numeric

              LD (HL),"$"
              JR PMV2

PMV1:         LD (HL),"("
              INC HL
              LD (HL),")"
              INC C                     ; Allow for the closing bracket

PMV2:         CALL PRINTSTR

EH2:          POP BC
              LD DE,MSGBUFF
              CALL PRINTSTR             ; The message itself
              POP AF
              LD A,CC_ENTER
              JR C,EH3                  ; Using two lines, so break here

              LD A,","
              RST &10
              LD A," "

EH3:          RST &10
              LD BC,(PPC)
              RST &30
              DW PRNUMB1                ; The line number
              LD A,":"
              RST &10
              LD A,(SUBPPC)
              RST &30
              DW PRAREG                 ; The statement number


; ---------------------------------------------------------------------------------------------------------------------
; ERRHAND2 -- record where CONTINUE should resume
;
; Called with the report already printed, or instead of printing when an ON ERROR handler is taking over.
; ---------------------------------------------------------------------------------------------------------------------

ERRHAND2:     CALL CLEARSP
              LD A,(ERRNR)
              AND A
              RET Z                     ; CONTINUE after "OK" would be meaningless

              SUB ERR_STOPSTMT          ; 0 for STOP, &FF for BREAK, and CY for both
              LD B,0
              ADC A,B
              JR NZ,ERRHAND3            ; Any other error: resume at the same statement

              LD A,(CURCMD)
              CP TOK_NEXT
              JR Z,ERRHAND3             ; BREAK inside NEXT: resume at NEXT, so the loop is not skipped

              INC B                     ; STOP or BREAK elsewhere: resume at the following statement

ERRHAND3:     LD HL,NSPPC
              LD A,(HL)
              LD (HL),&FF               ; Cancel any pending jump
              LD HL,(NEWPPC)
              BIT 7,A
              JR Z,ERRHAND4             ; A jump was about to happen, so resume at its target

              LD A,(SUBPPC)
              ADD A,B
              LD HL,(PPC)

ERRHAND4:     INC H
              RET Z                     ; CONTINUE would return to the edit line, which is not useful

              DEC H
              LD (OLDPPC),HL
              LD (OSPPC),A
              RET


; ---------------------------------------------------------------------------------------------------------------------
; DFKNL -- tail of DEF KEYCODE in its statement form
;
; Checks the syntax of the rest of the line and then removes the invisible forms from it, since that text is about to
; be stored as a key definition rather than executed.
; ---------------------------------------------------------------------------------------------------------------------

DFKNL:        EX (SP),HL                ; Discard the next-statement return, stack the rest of the line
              CALL STMTNEXT
              POP HL

; ---------------------------------------------------------------------------------------------------------------------
; REMOVEFP -- strip every invisible numeric form between (HL) and the end of the line
; ---------------------------------------------------------------------------------------------------------------------

REMOVEFP:     LD C,NUMFORMLEN
              LD A,(HL)
              SUB NUMMARKER
              LD B,A                    ; B is zero only when this is a marker, giving BC = 6
              CALL Z,RECLAIM2
              LD A,(HL)
              INC HL
              CP CC_ENTER
              JR NZ,REMOVEFP

              RET


; ---------------------------------------------------------------------------------------------------------------------
; EVALLINO -- read the line number at the start of the edit line
;
; Exit:   BC = the number, Z if there was none (or it was zero), CY if it exceeded MAXLINENUM.
; ---------------------------------------------------------------------------------------------------------------------

EVALLINO:     CALL AELP                 ; Address ELINE and set the page bytes
              LD (CHAD),HL
              RST &30
              DW SMBW                   ; Point MEM at a scratch area, since the calculator is about to be used
              RST &18
              CALL INTTOFP              ; Accumulate the leading digits
              CALL FPTOBC
              RET C                     ; Over 65535

              LD A,B
              ADD A,1
              RET C                     ; Over MAXLINENUM

              LD A,B
              OR C
              RET                       ; Z if the number was zero, meaning there was none


; ---------------------------------------------------------------------------------------------------------------------
; AELP / STPGS -- address the edit line, and set the three page bytes together
; ---------------------------------------------------------------------------------------------------------------------

AELP:         CALL ADDRELN

STPGS:        AND LMPRPAGE
              LD (CLAPG),A
              LD (CHADP),A
              LD (NXTLINEP),A
              RET


; =====================================================================================================================
; INSERTLN -- insert the edit line into the program
; =====================================================================================================================
;
; Entry:  BC = the line number; the checked text follows it in ELINE.
; Exit:   The line replaces any existing line of that number. A line whose text is just a carriage return deletes it.
;
; The bytes copied are exactly what the syntax check left behind: tokens, invisible numeric forms and call buffers
; alike. Nothing is recomputed later except the call buffer addresses, which COMPILE resolves before each run.
; ---------------------------------------------------------------------------------------------------------------------

INSERTLN:     PUSH BC                   ; The line number
          ;   LD HL,(INSLV)
          ;   INC H
          ;   DEC H
          ;   CALL NZ,HLJUMP

              CALL SCOMP                ; Mark the whole program as needing recompilation

              LD HL,(WORKSP)
              LD BC,(CHAD)              ; CHAD points just past the line number
              LD A,(BC)
              CP " "
              JR NZ,INSLN3

              INC BC
              LD A,(BC)
              CP CC_ENTER
              JR NZ,INSLN2              ; Drop one space after the number, so that repeated edit-and-enter
                                        ; cycles do not accumulate spaces in "10 test"
              DEC BC                    ; ... but leave "10 " alone

INSLN2:       LD (CHAD),BC

INSLN3:       SCF
              SBC HL,BC                 ; Length of the text, including its carriage return
              LD A,H
              CP MAXLINELEN/256
              JP NC,OOMERR              ; Longer than &3EFF

              EX (SP),HL                ; Stack the length, recover the line number
              LD (EPPC),HL
              CALL FNORECL              ; Find and delete any existing line of this number
              POP BC                    ; The text length
              LD A,C
              DEC A
              OR B
              RET Z                     ; Just a carriage return, so the line was only being deleted

              PUSH BC
              INC BC
              INC BC
              INC BC
              INC BC                    ; Room for the four-byte header as well
          ;   PUSH BC
          ;   PUSH HL
          ;   CALL GAPSZ
          ;   LD (4020H),HL
          ;   POP HL
          ;   POP BC

              CALL MAKEROOM
              LD BC,(EPPC)
              LD (HL),B                 ; Line number, most significant byte first
              INC HL
              LD (HL),C
              INC HL
              POP BC                    ; The text length
              LD (HL),C                 ; ... stored least significant byte first
              INC HL
              LD (HL),B
              CALL SPLITBC              ; Set PAGCOUNT and MODCOUNT for the copy
              INC HL
              EX DE,HL
              IN A,(URPORT)
              LD C,A                    ; CDE = the space just opened
              CALL ADDRCHAD             ; AHL = the text in the edit line
              JP FARLDIR


; =====================================================================================================================
; Statement skipping
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; SKIPCSTAT -- skip the rest of the current statement
;
; Used by DATA, LABEL, DEF FN and the LOOP conditions, all of which are inert at run time.
; ---------------------------------------------------------------------------------------------------------------------

SKIPCSTAT:    RST &18
              LD DE,&0100               ; D = one statement, E = not inside a string
              JR SKIPS15


; ---------------------------------------------------------------------------------------------------------------------
; SKIPSTATS -- skip forward D statements
;
; Entry:  D = statements to skip plus one, HL = the position to start from
; Exit:   CHAD points just before the wanted statement, at its ':' or THEN, or at the carriage return.
;         Z, NC   found it
;         Z, CY   the line ended just as the count reached zero
;         NZ, CY  the line ended too soon
;
; Colons and THEN inside a string literal do not count, and invisible numeric forms are stepped over whole.
; ---------------------------------------------------------------------------------------------------------------------

SKIPSTATS:    DEC HL                    ; Compensate for the INC below, so short statements are not missed

; --- SKIPS0: entry from ON ---

SKIPS0:       XOR A                     ; Not inside a string; also clears carry
              LD E,A
              JR SKIPS5

SKIPS1:       INC HL

SKIPS15:      LD A,(HL)
              CP NUMMARKER
              CALL Z,NUMBER             ; Step over an invisible form

              CP &22
              JR NZ,SKIPS2

              DEC E                     ; A quote toggles the inside-a-string flag

SKIPS2:       CP ":"
              JR Z,SKIPS4

              CP TOK_THEN
              JR Z,SKIPS4

              CP CC_ENTER
              JR NZ,SKIPS1

              DEC D                     ; Z if the line end is exactly the statement wanted
              SCF                       ; Report that the line ended
              JR SKIPS6

SKIPS4:       BIT 0,E
              JR NZ,SKIPS1              ; Inside a string, so this separator does not count

SKIPS5:       DEC D
              JR NZ,SKIPS1

SKIPS6:       LD (CHAD),HL
              RET


; ---------------------------------------------------------------------------------------------------------------------
; DATA -- the DATA statement
;
; Inert at run time. At check time the items are validated, so that a syntax error in DATA is reported when the line
; is entered rather than when it is eventually read.
; ---------------------------------------------------------------------------------------------------------------------

DATA:         CALL RUNFLG
              JR C,SKIPCSTAT            ; Running: skip the whole statement

DATA1:        CALL SCANSR               ; Check one item
              CP ","
              RET NZ

              RST &20
              JR DATA1
