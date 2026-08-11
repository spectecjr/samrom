; =====================================================================================================================
; DO.ASM -- Control flow: DO/LOOP, IF/ELSE, FOR/NEXT, GOSUB/RETURN and the line finder
; =====================================================================================================================
;
; THE BASIC STACK
; ---------------
; DO, GOSUB and PROC all need somewhere to remember where to come back to. They share one stack that grows downwards
; from BASSTK towards the heap, with BSTKEND marking its lowest used byte. Each frame is four bytes:
;
;     +0   type in the top three bits, page number in the low five
;     +1,2 address of the line to resume in
;     +3   statement number within it
;
; The three types are BSTKDO, BSTKPROC and BSTKGOSUB, and RETLOOP will only unstack a frame whose type matches what
; the caller expects -- which is how "LOOP without DO" and "RETURN without GOSUB" are detected.
;
; A frame records a line address, not a CHAD value, so execution resumes by re-entering the line and skipping to the
; statement. That survives the program being edited between the call and the return.
;
; THE TWO KINDS OF IF
; -------------------
; SAM BASIC has both a single-line IF ... THEN and a multi-line IF ... END IF. The tokeniser cannot tell them apart,
; because both are simply "IF", so it always emits TOK_LIF. The syntax check then rewrites the byte in the stored
; line to TOK_SIF when it finds a THEN. ELSE is treated the same way, becoming TOK_ELSE when the IF it belongs to
; was short. Both forms of each keyword list identically, so the distinction is invisible to the user.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; DO -- begin a loop
;
; Forms: DO, DO WHILE cond, DO UNTIL cond.
; ---------------------------------------------------------------------------------------------------------------------

DO:         CALL WHUNT                  ; Evaluate any WHILE or UNTIL; only returns here when running
            JR C,DO3                    ; The loop body should be executed

; --- The condition failed, so skip forward to the matching LOOP. Also the EXIT IF path. ---

DO2:        POP DE                      ; Discard the next-statement return
            LD DE,(TOK_DO*256)+TOK_LOOP ; Count nested DOs while searching for LOOP
            CALL SEARCH
            DB ERR_NOLOOP


; ---------------------------------------------------------------------------------------------------------------------
; DO3 / BSTKE -- push a BASIC stack frame
;
; Entry:  B = the frame type: BSTKDO, BSTKPROC or BSTKGOSUB.
; Exit:   HL -> the stacked statement number, which GOSUB and PROC increment so that they return to the statement
;         after the call.
; ---------------------------------------------------------------------------------------------------------------------

DO3:        LD B,BSTKDO

BSTKE:      LD HL,(BSTKEND)
            LD DE,-BSTKFRAME
            ADD HL,DE                   ; The proposed new BSTKEND; sets carry
            LD DE,(HEAPEND)             ; The heap grows up towards the stack
            SBC HL,DE
            JR NC,BSTKOK

BSFERR:     RST &08
            DB ERR_BSTKFULL

BSTKOK:     ADD HL,DE
            INC HL
            LD A,(CLAPG)
            AND LMPRPAGE
            OR B                        ; Type in the top bits, page in the low five
            LD (HL),A
            LD A,(SUBPPC)
            LD DE,(CLA)

; --- SEDA: store the address and statement. Also entered by LOCAL, which builds a frame by hand. ---

SEDA:       LD (BSTKEND),HL
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D
            INC HL
            LD (HL),A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LOOPIF / EXITIF -- conditional loop control
;
; LOOP IF cond loops back when the condition is true; EXIT IF cond leaves the loop when it is.
; ---------------------------------------------------------------------------------------------------------------------

LOOPIF:     CALL SYNTAX6                ; Insist on a numeric condition

            CALL TRUETST                ; Drop it and test
            RET Z                       ; False: carry on with the next statement

            SCF                         ; True: loop
            JR LOOP1

EXITIF:     CALL SYNTAX6

            CALL TRUETST
            RET Z                       ; False: carry on

            CALL LOOP1                  ; True: unstack the DO frame without looping
            JR DO2                      ; ... then skip forward past the LOOP


; ---------------------------------------------------------------------------------------------------------------------
; LOOP -- end of a loop
;
; Forms: LOOP, LOOP WHILE cond, LOOP UNTIL cond.
; ---------------------------------------------------------------------------------------------------------------------

LOOP:       CALL WHUNT                  ; CY if the loop should go round again

LOOP1:      EX AF,AF'                   ; Preserve the loop/no-loop decision.
                                        ; EXIT IF always arrives with NC, LOOP IF always with CY.
            LD B,BSTKDO
            CALL RETLOOP                ; Unstack the DO frame
            JR Z,LOOP2

            RST &08
            DB ERR_LOOPNODO

LOOP2:      EX AF,AF'
            RET NC                      ; No loop: continue with the next statement. When called from EXIT IF this
                                        ; returns into EXIT IF rather than to the caller.

            EX AF,AF'                   ; A = the page from the frame


; ---------------------------------------------------------------------------------------------------------------------
; RLEPCOM -- resume execution at a stored position
;
; Entry:  A = page, HL = the line address (or &00xx for the edit line), C = the statement number.
; Exit:   Never returns; execution continues there.
;
; Shared by RETURN, END PROC, LOOP and NEXT: each is really "go to statement C of the line at AHL".
; ---------------------------------------------------------------------------------------------------------------------

RLEPCOM:    POP DE                      ; Discard the next-statement return
            INC H
            DEC H
            JP Z,LOOPEL                 ; A zero high byte means the edit line; NSPPC is set from C and the pages
                                        ; from ELINEP, with CHAD found by skipping statements
            AND LMPRPAGE

; --- RLEPC2: entered from PROCS, which already has the page masked ---

RLEPC2:     LD B,C
            PUSH BC                     ; B = the statement, which RLEPI pops
            CALL SELURPG
            JP RLEPI                    ; Use HL as the line start and A as the page for CHAD, CLA and NXTLINE


; =====================================================================================================================
; ON -- ON value: statement : statement : ...
; =====================================================================================================================
;
; Selects the n'th of the statements that follow. A GOTO simply runs; anything else is made to end the line
; afterwards, so only one statement executes.
;
; A PROC call or GOSUB needs more care: it must return to the statement after the whole ON. That is arranged by
; pretending the current line is the next one and the current statement is zero, so the return lands on statement 1
; of the following line. ONSTORE keeps the real statement number for error reports.
; ---------------------------------------------------------------------------------------------------------------------

ON:         CALL SYNTAX6

            CALL GETBYTE
            LD D,A
            LD HL,SUBPPC
            ADD A,(HL)
            LD (HL),A                   ; Account for the statements about to be skipped
            RST &18
            CALL SKIPS0                 ; Skip D statements
            RET C                       ; Ran off the end of the line, so fall through to the next line

            RST &18                     ; -> the ':' before the chosen statement
            PUSH HL
            RST &20                     ; A = its first significant character
            POP HL
            CALL ALPHA
            JR C,ON2                    ; A letter, so a procedure call

            CP TOK_GOSUB
            JR NZ,ON3

; --- A PROC call or GOSUB: make it return to the next line ---

ON2:        LD (CHAD),HL                ; Point at the ':'
            LD HL,(NXTLINE)
            LD (CLA),HL                 ; Pretend we are already at the next line
            LD HL,SUBPPC
            LD A,(HL)
            LD (ONSTORE),A              ; Keep the real statement number: the error handler uses it when SUBPPC
                                        ; comes out as zero
            LD (HL),255                 ; Incremented to zero by the statement loop, so the call believes it is at
                                        ; statement 0 of the next line and returns to statement 1
            RET

ON3:        POP DE                      ; Discard the next-statement return
            CP TOK_GOTO
            JR Z,ON4                    ; GOTO keeps it, since it jumps anyway

            LD DE,OLNEND                ; Everything else ends the line after one statement

ON4:        CP ":"
            JP NZ,ON4ENT                ; Push DE and execute the statement

            EX DE,HL
            JP (HL)                     ; An empty statement: go straight to the line end


; ---------------------------------------------------------------------------------------------------------------------
; GOTO2 / GOTO3 / GOTO4 -- set up a pending jump
; ---------------------------------------------------------------------------------------------------------------------

GOTO2:      CALL GETINT
            LD A,H
            INC A

GTERRHP:    JP Z,IOORERR                ; Line numbers run 0 to MAXLINENUM

GOTO3:      XOR A                       ; Statement 0, meaning "the first one that exists"

GOTO4:      LD (NSPPC),A
            LD (NEWPPC),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CONTINUE -- resume where the program stopped
; ---------------------------------------------------------------------------------------------------------------------

CONTINUE:   CALL CHKEND

CONTINUE2:  LD A,(OSPPC)
            LD HL,(OLDPPC)
            JR GOTO4


; ---------------------------------------------------------------------------------------------------------------------
; CALBAS -- call a BASIC line from machine code (jump table entry &010F)
;
; Entry:  HL = the line number.
; Exit:   Z if the line completed normally, otherwise A = the error number.
;
; A GOSUB frame is pushed whose statement number is BSTKMCSTAT. When the line eventually returns, RETURN sees that
; value and exits to this routine's error frame instead of resuming BASIC.
; ---------------------------------------------------------------------------------------------------------------------

CALBAS:     CALL GOTO3                  ; NEWPPC = HL, NSPPC = 0
            LD B,A                      ; Type BSTKGOSUB, page 0
            DEC A
            LD (SUBPPC),A               ; Statement &FF marks the caller as machine code
            IN A,(251)
            PUSH AF
            CALL BSTKE
            CALL SETESP                 ; Errors now unwind to here rather than to the main loop
            CALL NEXTSTAT               ; Run the line
            POP HL
            LD (ERRSP),HL               ; Restore the previous error frame
            POP AF
            OUT (251),A
            LD A,(ERRNR)
            AND A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; RETURN -- return from a GOSUB
; ---------------------------------------------------------------------------------------------------------------------

RETURN:     CALL CHKEND

            LD B,BSTKGOSUB
            CALL RETLOOP
            JR NZ,RWGERR                ; Wrong frame type, or the stack is empty

            INC C                       ; Resume at the statement after the call
            JR NZ,ENDP1

            POP BC
            RET                         ; The statement was BSTKMCSTAT, so return to CALBAS

RWGERR:     RST &08
            DB ERR_RETNOGOSUB


; ---------------------------------------------------------------------------------------------------------------------
; ENDPROC -- return from a procedure
;
; As RETURN, but the procedure's local variables must be unwound first, and ON ERROR is re-armed so that an error
; handler written as a procedure works more than once.
; ---------------------------------------------------------------------------------------------------------------------

ENDPROC:    CALL CHKEND

            CALL DPRA                   ; Unstack a PROC frame: C = statement, HL = line, A = page
            PUSH HL
            PUSH BC
            PUSH AF
            CALL DELOCAL                ; Restore globals, copy REF values back, delete local strings
            POP AF
            POP BC
            POP HL

; --- ENDP1: entered from RETURN once the frame type has been checked ---

ENDP1:      LD B,A
            LD A,(ONERRFLG)
            RRA
            JR NC,ENDP2                 ; ON ERROR is not permanently enabled

            LD A,FONERRBOTH             ; Re-arm the temporary bit from the permanent one, so an error handler
            LD (ONERRFLG),A             ; written as a procedure or subroutine can fire again

ENDP2:      LD A,B
            JP RLEPCOM


; ---------------------------------------------------------------------------------------------------------------------
; WHUNT -- evaluate an optional WHILE or UNTIL clause
;
; Exit:   CY if the loop body should run, NC if it should not.
; Notes:  With no clause at all the routine discards its own return address and returns directly to DO or LOOP with
;         carry set, since an unconditional loop always runs.
; ---------------------------------------------------------------------------------------------------------------------

WHUNT:      CP TOK_WHILE
            JR Z,WHUNT2

            CP TOK_UNTIL
            SCF                         ; Remember which of the two it was
            JR Z,WHUNT2

            POP HL                      ; No clause: HL = the return address in DO or LOOP
            CALL RUNFLG
            RET NC                      ; Syntax check: go to the next statement, having checked DO or LOOP itself

            JP (HL)                     ; Running: CY says "execute the loop"

WHUNT2:     PUSH AF                     ; Which keyword it was
            CALL SEXPT1NUM              ; Skip it and evaluate the condition
            CALL RUNFLG
            JR NC,WHUNT3                ; Syntax check

            CALL TRUETST                ; Drop the value and test it
            JR Z,WHUNT4                 ; False

            POP AF                      ; True: UNTIL gives NC, WHILE gives CY
            CCF
            RET

WHUNT3:     POP AF                      ; Discard the keyword flag and the return address, and carry on

WHUNT4:     POP AF                      ; False: UNTIL gives CY, WHILE gives NC
            RET

; From LOOP, carry means "go round again"; from DO it means "execute the body", and no carry means "find the LOOP".


; ---------------------------------------------------------------------------------------------------------------------
; RETLOOP -- unstack a BASIC stack frame
;
; Entry:  B = the required type: BSTKDO, BSTKPROC or BSTKGOSUB.
; Exit:   A = type and page, HL = the line address, C = the statement number.
;         Z if the type matched (entering at RETLOOP); NZ means the wrong type or an empty stack, and nothing has
;         been unstacked.
; ---------------------------------------------------------------------------------------------------------------------

RETLOOP:    LD HL,(BSTKEND)
            LD A,(HL)
            AND BSTKTYPE
            CP B
            RET NZ                      ; Wrong type, or the &FF stopper

; --- RETLOOP2: accept any frame. Used by POP. ---

RETLOOP2:   LD A,(HL)
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC HL
            LD C,(HL)
            INC HL
            LD (BSTKEND),HL
            EX DE,HL
            RET


; =====================================================================================================================
; FNDLNHL -- find a program line by number
; =====================================================================================================================
;
; Entry:  FNDLNHL with the number in HL, FNDLNBC with it in BC, FNDLINE to force the search to start at PROG.
; Exit:   HL -> the line number high byte of the line found, or of the first line after it
;         DE -> the previous line (in the &8000-&BFFF window)
;         Z if the exact line was found
;         If there is no program at all, DE = HL.
; Uses:   HL, DE, BC, AF and TEMPW1.
;
; While running, a target at or after the current line is searched for from CLA rather than PROG, which makes a
; forward GOTO in a long program much faster.
; ---------------------------------------------------------------------------------------------------------------------

FNDLNHL:    LD B,H
            LD C,L

FNDLNBC:    CALL RUNFLG

            JR NC,FNDLP                 ; Not running, so start at PROG

            LD HL,(PPC)
            DEC HL                      ; So that a target equal to PPC still counts as "ahead"
            AND A
            SBC HL,BC
            JR NC,FNDLP                 ; The target is behind us. Always true when PPC is &FFFF (the edit line).

            LD HL,(CLA)                 ; Start from the current line
            LD A,(CLAPG)
            JR FNDL0

; --- FNDLINE: always start at PROG. RENUM needs this, since it rewrites the numbers as it goes. ---

FNDLINE:    LD B,H
            LD C,L

FNDLP:      LD HL,(PROG)
            LD A,(PROGP)

FNDL0:      CALL TSURPG                 ; Page in the block containing the program
            LD (TEMPW1),HL              ; Remember this line, so DE can point at it later
            JR FNDL2

FNDL1:      BIT 6,H
            CALL NZ,INCURPAGE           ; Keep the pointer inside the paging window
            LD (TEMPW1),HL
            INC HL
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC HL
            ADD HL,DE                   ; Add the line length to reach the next line

FNDL2:      LD A,(HL)                   ; Line number high byte -- also &FF at the program end, which is above any
            CP B                        ; real number and so terminates the search
            JP C,FNDL1                  ; Still before the target

            JR NZ,FNDL3                 ; Past it

            INC HL
            LD A,(HL)
            DEC HL
            CP C
            JP C,FNDL1                  ; The low byte says we are still short

FNDL3:      LD DE,(TEMPW1)
            RET


; =====================================================================================================================
; IF, ELSE and END IF
; =====================================================================================================================
;
; Examples:
;     IF x=1 THEN PRINT
;     IF x=1 THEN PRINT "Y": ELSE PRINT "N"
;     IF x=1: PRINT: PRINT: END IF
;
; Both forms enter here; the presence of THEN decides which this is, and the stored token is corrected to match.
; ---------------------------------------------------------------------------------------------------------------------

LIF:
SIF:        LD HL,(CHAD)

SIFLP:      DEC HL                      ; Walk back to the IF token itself
            LD A,(HL)
            CP CC_SIGNIF
            JR C,SIFLP

            PUSH HL
            CALL EXPT1NUM               ; The condition
            POP HL
            LD (IFTYPE),A               ; Remember whether this IF was long or short, so a later ELSE can match it.
                                        ; IFTYPE is set to "long" at the start of each line's syntax check.
            CP TOK_THEN
            LD D,A
            JR NZ,IFL1                  ; No THEN, so this is the long form and should be followed by ':'

            LD (HL),TOK_SIF             ; Rewrite the stored token. The tokeniser always produces TOK_LIF because
                                        ; "IF" appears first in the keyword table; the presence of THEN is what
                                        ; makes this the short form.

IFL1:       CALL CHKEND                 ; At check time this verifies the CR, ':' or THEN and returns

            CALL TRUETST                ; Drop the condition and test it
            RET NZ                      ; True: carry on with the next statement

            POP BC                      ; False: discard the next-statement return
            LD A,D
            CP TOK_THEN
            JR Z,SHORTIF

; --- A false long IF: find the matching ELSE or END IF, counting nested IFs ---

EIFLP:      EXX
            LD BC,&FF00+TOK_LELSE       ; Search the whole program; the secondary target reloads as LELSE
            EXX

            LD BC,(1*256)+TOK_LELSE     ; Nesting depth 1, secondary target LELSE
            LD DE,(TOK_LIF*256)+TOK_ENDIF
            CALL SRCHALL3               ; Find END IF, or an ELSE at the same nesting level
            JR NC,MEIERR

            LD (SUBPPC),A
            EX AF,AF'                   ; Which of the two was found
            CP E
            JP Z,XCHDH                  ; END IF: resume just after it

            RST &18
            CP TOK_SIF
            JP NZ,XCHDH                 ; A plain ELSE: resume just after it

; --- "ELSE IF cond": evaluate the new condition and repeat the search if it is also false ---

            CALL SEXPT1NUM
            CALL TRUETST
            JR Z,EIFLP

XCHDH:      JP EXCHAD2

MEIERR:     RST &08
            DB ERR_NOENDIF


; ---------------------------------------------------------------------------------------------------------------------
; SHORTIF -- a false single-line IF: look for an ELSE on this line only
; ---------------------------------------------------------------------------------------------------------------------

SHORTIF:    EXX
            LD BC,TOK_THEN              ; One line only; no secondary target
            EXX

            LD DE,(TOK_SIF*256)+TOK_ELSE
            CALL SRCHALL2               ; Find ELSE, counting nested short IFs
            JP NC,LINEEND               ; No ELSE, so the line is finished

            LD (SUBPPC),A
            JP STMTLP2                  ; Resume just after the ELSE; CHAD, CLA and NXTLINE are all still valid


; ---------------------------------------------------------------------------------------------------------------------
; LELSE -- the long form of ELSE
;
; The tokeniser always produces TOK_LELSE because "ELSE" appears first in the keyword table. At check time the token
; is rewritten to TOK_ELSE when the preceding IF on this line was short.
; ---------------------------------------------------------------------------------------------------------------------

LELSE:      LD C,A                      ; The character after ELSE
            CALL RUNFLG
            JR C,RLELSE                 ; Running a long ELSE

            LD HL,(CHAD)

FELSLP:     DEC HL                      ; Walk back to the ELSE token
            LD A,(HL)
            CP CC_SIGNIF
            JR C,FELSLP

            LD A,(IFTYPE)
            CP TOK_THEN
            JR Z,NLELS                  ; The preceding IF was short, so this ELSE must be too

            LD A,C
            SUB TOK_SIF
            ADC A,0                     ; Both TOK_SIF and TOK_LIF map to zero
            JR NZ,ELSE2                 ; A plain ELSE: just check what follows

            LD HL,(CHAD)
            LD (HL),TOK_SIF             ; "ELSE IF" becomes "ELSE SIF"
            CALL SEXPT1NUM              ; Check the condition
            CP TOK_THEN
            RET NZ

DNS:        RST &08                     ; "ELSE IF cond THEN" is rejected: it would nest in a confusing way
            DB ERR_NONSENSE

NLELS:      LD (HL),TOK_ELSE            ; Force the short form, since a short IF preceded it on this line
            JR ELSE2


; ---------------------------------------------------------------------------------------------------------------------
; RLELSE -- running a long ELSE: the true branch has finished, so skip to END IF
; ---------------------------------------------------------------------------------------------------------------------

RLELSE:     POP DE                      ; Discard the next-statement return
            LD DE,(TOK_LIF*256)+TOK_ENDIF
            CALL SEARCH                 ; Find END IF, counting nested IFs
            DB ERR_OK                   ; Falling off the end of the program is simply the end of the program


; ---------------------------------------------------------------------------------------------------------------------
; ELSE -- the short form: the true branch ran, so abandon the rest of the line
; ---------------------------------------------------------------------------------------------------------------------

ELSE:       CALL RUNFLG
            JP C,REMARK                 ; Running: ignore everything to the end of the line

ELSE2:      POP BC                      ; Discard the next-statement return
            JP STMTLP2                  ; Check the syntax of what follows without demanding a separator first


; ---------------------------------------------------------------------------------------------------------------------
; TRUETST -- drop the top calculator value and test it
;
; Exit:   NZ if it was non-zero (true).
; Notes:  ENDIF shares the RET, since END IF is only a marker and does nothing at run time.
; ---------------------------------------------------------------------------------------------------------------------

TRUETST:    LD HL,(STKEND)
            DEC HL
            DEC HL
            LD A,(HL)                   ; High byte of a small integer
            DEC HL
            OR (HL)                     ; Low byte
            DEC HL
            OR (HL)                     ; Sign -- probably unnecessary, since minus zero should not occur
            DEC HL
            OR (HL)                     ; Exponent
            LD (STKEND),HL              ; Drop it

ENDIF:      RET


; =====================================================================================================================
; FOR -- FOR var = start TO limit [STEP step]
; =====================================================================================================================
;
; The control variable's record is extended beyond the usual five bytes to hold the limit, the step, and where to
; loop back to:
;
;     value (5), limit (5), step (5), looping page (1), looping address (2), looping statement (1)
;
; If no iteration is possible the loop is skipped entirely by searching forward for the matching NEXT.
; ---------------------------------------------------------------------------------------------------------------------

FOR:          CALL SYNTAX4              ; Assess the control variable

              RST &18
              CP "="
              JR NZ,DNS

              CALL SEXPT1NUM            ; The starting value
              CP TOTOK
              JP NZ,DNS

              CALL SEXPT1NUM            ; The limit
              CP STEPTOK
              JR Z,FORSTEP

              CALL CHKEND

              DB CALC
              DB STKONE                 ; No STEP given, so use one
              DB EXIT

              INC D                     ; Force NZ so the call below is skipped

FORSTEP:      CALL Z,SSYNTAX6           ; The step

; --- The stack now holds value, limit, step ---

FOR2:         RST &18
              PUSH AF                   ; The character ending the statement
              CALL SWOP12               ; value, step, limit
              CALL FPSWOP13             ; limit, step, value

              LD HL,TLBYTE+33
              SET 6,(HL)                ; TLFORVAR on the name being created
              CALL ASSISR               ; Assign the value. If an ordinary variable of this name exists, DEST points
                                        ; at the previous link and FLAGX bit 0 says "new", so it is unlinked.
                                        ; On exit DE points past the five bytes just written: 14 more are available
                                        ; if this was already a FOR variable, otherwise NUMEND must be moved on.
              LD HL,(STKEND)
              LD BC,10
              AND A
              SBC HL,BC
              LD (STKEND),HL            ; Drop the limit and step from the calculator stack
              LDIR                      ; ... and copy them into the variable, giving value, limit, step
              POP AF                    ; The statement terminator
              PUSH DE
              DEC DE
              EX DE,HL                  ; Source: the end of the step
              LD DE,MEMVAL+14
              LD C,15
              LDDR                      ; Copy value, limit and step into calculator memories 0, 1 and 2
              CP CC_ENTER
              JR Z,FOR22                ; The loop body begins on the next line

              LD A,(SUBPPC)
              INC A
              LD C,A                    ; ... otherwise at the next statement of this line
              LD A,(PPC+1)
              INC A
              LD H,A
              JR Z,FOR25                ; The edit line

              LD HL,(CLA)
              JR FOR25

FOR22:        LD HL,(NXTLINE)
              LD C,1                    ; Statement 1 of the following line

FOR25:        EX DE,HL
              POP HL                    ; -> the loop-back fields in the variable
              LD A,(NXTLINEP)           ; The page of the current line, which equals CLAPG
              LD (HL),A                 ; Field order differs from ROM 1.0
              INC HL
              LD (HL),E
              INC HL
              LD (HL),D
              INC HL
              LD (HL),C
              INC HL
              LD A,(FLAGX)
              RRA
              EX DE,HL
              CALL C,NELOAD             ; A newly created variable: move NUMEND past it

              CALL NEXTTEST
              RET NZ                    ; At least one iteration is possible

; --- No iterations: skip the whole loop by finding the matching NEXT ---

              CALL SELCHADP

FORMLP:       LD E,TOK_NEXT
              CALL SRCHPROG
              JR C,FOR3

              RST &08
              DB ERR_FORNONEXT

FOR3:         LD (SUBPPC),A
              LD DE,TLBYTE+33
              CALL MATCHFN              ; Does this NEXT name our variable?
              JR C,FORMLP               ; No, so it belongs to another loop

              LD (CHAD),DE              ; Step past the variable name
              POP DE                    ; Discard the next-statement return
              JP EXCHAD2                ; Continue after "NEXT var"

NWFERR:       RST &08
              DB ERR_NEXTNOFOR


; =====================================================================================================================
; NEXT -- NEXT var
; =====================================================================================================================

NEXT:         CALL SYNTAX4              ; Assess the control variable
              CALL CHKEND

              CALL BRKSTOP              ; Test BREAK here, since the jump below bypasses the usual check

              LD A,(STRLEN)             ; The type byte, if the variable was found
              AND TLFORVAR
              JR Z,NWFERR               ; Not a FOR variable

                                        ; The record holds value (5), limit (5), step (5), address (2), page (1),
                                        ; statement (1)
              CALL ADDRDEST             ; -> the value
              CALL NEXTSR               ; Try the integer fast path
              JR Z,NEXT1                ; It succeeded

; --- Floating point: recompute value = value + step through the calculator ---

              LD HL,(DEST)
              PUSH HL
              LD DE,(MEM)
              LD BC,15
              LDIR                      ; Copy value, limit and step to memories 0, 1 and 2

              DB CALC
              DB RCL0                   ; value
              DB RCL2                   ; value, step
              DB ADDN
              DB STOD0                  ; memory 0 = value + step, and drop it
              DB EXIT

              EX DE,HL                  ; HL -> the dropped new value
              POP DE
              LD BC,NUMVALSIZE
              LDIR                      ; Write it back into the variable

              CALL NEXTTEST
              RET Z                     ; The limit has been passed

              DB SKIP2LDHL              ; Skip the two bytes below

NEXT1:        AND A
              RET Z                     ; The integer path says the limit has been passed

; --- Loop back ---

              LD DE,15
              LD HL,(DEST)
              ADD HL,DE
              LD A,(HL)                 ; Page of the looping line
              INC HL
              LD E,(HL)
              INC HL
              LD D,(HL)                 ; Its address, or &00xx for the edit line
              INC HL
              LD C,(HL)                 ; The statement to resume at
              EX DE,HL
              JP RLEPCOM


; ---------------------------------------------------------------------------------------------------------------------
; NEXTTEST -- has the limit been passed?
;
; Computes SGN(value - limit), or SGN(limit - value) when the step is negative, so that one test serves both
; directions.
;
; Exit:   NZ if another iteration is possible.
; ---------------------------------------------------------------------------------------------------------------------

NEXTTEST:     DB CALC
              DB RCL0
              DB RCL1
              DB RCL2                   ; value, limit, step
              DB GRTR0                  ; value, limit, (step > 0)
              DB JPTRUE
              DB &02                    ; -> NEXTTST1

              DB SWOP                   ; A negative step, so compare the other way round

NEXTTST1:     DB SUBN                   ; value - limit, or limit - value
              DB SGN
              DB DROP
              DB EXIT

              INC DE                    ; DE -> the dropped sign byte
              INC DE
              LD A,(DE)
              DEC A                     ; The sign is -1, 0 or 1, so A is zero only when it was 1
              RET                       ; NZ if the loop may continue


; ---------------------------------------------------------------------------------------------------------------------
; NEXTSR -- integer fast path for NEXT
;
; Entry:  HL -> the first byte of the FOR variable's value.
; Exit:   Z   the arithmetic was done in integers; A = &FF to loop or 0 to stop
;         NZ  one of the three numbers is in floating point form, so the caller must use the calculator
; ---------------------------------------------------------------------------------------------------------------------

NEXTSR:       XOR  A
              CP   (HL)
              RET  NZ                   ; The value is in floating point form

              INC  HL
              LD   B,(HL)
              INC  HL
              LD   E,(HL)
              INC  HL
              LD   D,(HL)               ; DE = value, B = its sign
              INC  HL
              INC  HL
              CP   (HL)
              RET  NZ                   ; The limit is floating point

              INC HL
              INC HL
              INC HL
              INC HL
              INC HL
              CP (HL)
              RET  NZ                   ; The step is floating point

              INC  HL
              LD   A,(HL)
              EX   AF,AF'               ; A and A' both hold the sign of the step
              LD   A,(HL)
              INC  HL
              LD   C,(HL)
              INC  HL
              LD   H,(HL)
              LD   L,C                  ; HL = step
              ADD  HL,DE                ; value + step
              ADC  A,B                  ; Combine the signs and the carry
              RRCA
              ADC  A,0
              RET  NZ                   ; The result will not fit in 16 bits, so fall back to floating point

              SBC  A,A                  ; A = the sign of the new value
              EX   DE,HL                ; DE = the new value
              LD   HL,(DEST)
              INC  HL                   ; Step over the zero exponent byte
              LD   (HL),A
              LD   B,A                  ; B = the sign of the new value
              INC  HL
              LD   (HL),E
              INC  HL
              LD   (HL),D
              INC HL
              INC HL
              INC HL
              LD A,(HL)                 ; The sign of the limit
              INC  HL
              LD   C,(HL)
              INC  HL
              LD   H,(HL)
              LD   L,C                  ; HL = limit
              XOR  B
              JR   NZ,NEXTSR1           ; The signs differ, so no subtraction is needed to decide

              DEC  A                    ; A = &FF, meaning "loop"
              SBC  HL,DE
              RET  Z                    ; limit equals value, so this iteration still runs

              SBC  A,A
              CPL                       ; 0 if the limit has been passed, &FF if not
              LD   B,A

NEXTSR1:      EX   AF,AF'               ; The sign of the step
              XOR  B                    ; A negative step reverses the decision
              CP   A                    ; Force Z: the integer path succeeded
              RET


; ---------------------------------------------------------------------------------------------------------------------
; ONERROR -- ON ERROR handler | ON ERROR STOP
;
; Records where the handler is, rather than jumping to it: MAINER re-enters the line at the recorded statement when
; an error occurs. Used in the edit line it merely disarms, since there would be nothing to return to.
; ---------------------------------------------------------------------------------------------------------------------

ONERROR:    POP HL                      ; The next-statement return
            CALL RUNFLG
            JP NC,STMTLP1               ; Syntax check: verify what follows

            PUSH HL
            RST &18
            CP TOK_STOP
            JR NZ,ONERR2

            RST &20                     ; ON ERROR STOP
            XOR A
            JR ONERR3

ONERR2:     LD HL,(PPC)
            LD (ERRLN),HL               ; Remember where the handler lives
            LD A,(SUBPPC)
            LD (ERRSTAT),A
            PUSH HL
            CALL SKIPCSTAT              ; Step over the handler statement for now
            POP AF
            INC A
            JR Z,ONERR3                 ; In the edit line: arm nothing

            LD A,FONERRBOTH             ; Both the temporary and permanent bits.
                                        ; An error now sends MAINER to ERRLN/ERRSTAT.
ONERR3:     LD (ONERRFLG),A
            RET

                                        ; Routines in this file: RETURN, END PROC, FNDLNHL, IF, ELSE, CALBAS,
                                        ; FOR, NEXT
