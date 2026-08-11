; =====================================================================================================================
; FN.ASM -- DEF FN and FN, DEF PROC and PROC, LOCAL, and the compile pass
; =====================================================================================================================
;
; CALL BUFFERS
; ------------
; A user-defined function or procedure is found by name, but searching the program by name on every call would be
; far too slow. Instead, the syntax check opens a six-byte buffer immediately after the name at each call site:
;
;     FN call:     0E FE FE FE ?? ??
;     PROC call:   0E FD FD FD ?? ??
;
; The leading NUMMARKER makes every other part of the ROM -- the lister, the statement skipper, the searcher --
; treat the buffer as an invisible numeric form and step over all six bytes. The repeated &FE or &FD bytes are what
; the compile pass recognises.
;
; COMPILE then fills in the last three bytes with the page and address of the definition. At call time the buffer is
; simply read, so no name search happens while a program is running.
;
; Since the program moves whenever it is edited, and is reloaded at a different address, the addresses go stale --
; so COMPILE re-resolves every buffer before each run. That in turn means a program image can be saved, moved or
; relocated freely: the addresses in it are never trusted.
;
; DEF FN PARAMETERS
; -----------------
; A DEF FN's parameter list gets the same treatment. Each parameter name is followed by a plain
; "0E xx xx xx xx xx" buffer, which IMFN fills with the argument's value at call time. LKFNVAR then resolves
; single-letter names from those buffers while the function body is evaluated.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; ELCOMAL / COMALL / COMDP -- resolve the call buffers
;
; ELCOMAL compiles FNs only when this line actually contains one, which REFFLG records during the syntax check.
; ---------------------------------------------------------------------------------------------------------------------

ELCOMAL:    LD A,(REFFLG)
            CP 1                        ; CY if zero
            CCF                          ; CY if non-zero, meaning an FN appeared

COMALL:     CALL C,COMDF                ; Resolve FN buffers

COMDP:      CALL COMLEN                 ; Map the program; BC = its length modulo 8K, B' = the number of 8K blocks

CMDPL:      LD D,PROCBUFFILL
            CALL LKCALL                 ; Find the next PROC call buffer
            RET C                       ; No more

            PUSH BC                     ; Bytes left to search
            CALL LOOKDP                 ; Find the DEF PROC and patch the buffer, or mark it unresolved
            POP BC
            JR CMDPL


; ---------------------------------------------------------------------------------------------------------------------
; COMDF -- resolve the FN call buffers
;
; Searching the program for each name in turn would be too slow, so one pass first tabulates the page and address of
; every DEF FN in INSTBUF.
; ---------------------------------------------------------------------------------------------------------------------

COMDF:      LD HL,INSTBUF
            LD (TEMPW1),HL              ; Where the next table entry goes
            CALL ADDRPROG
            LD A,(HL)
            INC A
            RET Z                       ; No program at all

            INC HL
            INC HL
            INC HL

DFPPL:      INC HL
            LD (CHAD),HL                ; Start at the first character of the first line, and after each find
                                        ; resume just past the DEF FN that was found
            LD E,TOK_DEFFN
            CALL SRCHPROG
            JR NC,CMDF2                 ; All found

            EX DE,HL                    ; HL points past DEF FN
            DEC DE                      ; DE -> the token itself
            LD HL,(TEMPW1)
            LD BC,-INSTBUF-509
            ADD HL,BC
            JR C,TMDERR                 ; The table would pass INSTBUF+509, which allows about 170 definitions

            SBC HL,BC
            IN A,(251)
            LD (HL),A                   ; Page
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D                   ; ... and address
            INC HL
            LD (TEMPW1),HL
            EX DE,HL
            JR DFPPL

; --- TMDERR: shared with DEF KEYCODE ---

TMDERR:     RST &08
            DB ERR_TOOMANYDEF

CMDF2:      CALL COMLEN

CMDFL:      LD D,FNBUFFILL
            CALL LKCALL
            RET C

            PUSH BC
            CALL LOOKDF
            POP BC
            JR CMDFL


; ---------------------------------------------------------------------------------------------------------------------
; COMLEN -- map the area to be searched and measure it
;
; Exit:   HL -> its start, BC = its length modulo 8K, B' = the number of 8K blocks plus one.
; Notes:  The block count exists so that LKCALL can use CPIR, whose counter is only 16 bits, on an area that may be
;         larger than that; and so there is always room after a match to step the pointer on.
; ---------------------------------------------------------------------------------------------------------------------

COMLEN:     LD A,(COMPFLG)
            RLA
            JR C,PRGLEN                 ; Bit 7: the whole program

            CALL ADDRELN                ; Otherwise just the edit line
            PUSH HL
            EX DE,HL
            LD C,A                      ; CDE = its start
            LD HL,(WORKSP)
            LD A,(WORKSPP)
            JR CPLENC

PRGLEN:     CALL ADDRPROG
            PUSH HL
            EX DE,HL
            LD C,A                      ; CDE = PROG
            LD HL,(NVARS)
            LD A,(NVARSP)

CPLENC:     CALL SUBAHLCDE              ; The length, in page form
            PUSH HL
            ADD HL,HL
            ADD HL,HL
            ADD HL,HL
            RLA                         ; A = the number of 8K blocks
            EXX
            INC A
            LD B,A
            EXX
            POP BC
            LD A,B
            AND &1F
            LD B,A                      ; BC = the length modulo 8K
            POP HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LKCALL -- find the next call buffer
;
; Recognises the pattern: a byte that is not NUMMARKER, then NUMMARKER, then two copies of &FD or &FE, then a byte
; with bit 7 set.
;
; Requiring exactly one leading NUMMARKER rules out a numeric literal whose five value bytes happen to contain the
; pair. A line header cannot be mistaken for one either, since "0E FE FE 80" would imply a line longer than 32K.
;
; Entry:  HL = where to start, D = FNBUFFILL or PROCBUFFILL, BC = bytes to search modulo 8K, B' = 8K blocks
; Exit:   NC with HL -> the second &FD or &FE, and the call site's name in NMBUFF as a length byte plus text;
;         CY when no more buffers exist.
; ---------------------------------------------------------------------------------------------------------------------

LKCALL:     LD A,B
            OR C
            JR Z,LPC5                   ; This 8K block is exhausted

            LD A,D
            CPIR
            JR NZ,LPC5                  ; Not found in this block

            CP (HL)
            JR NZ,LKCALL                ; No second copy, so a false alarm

            DEC HL
            DEC HL
            LD A,NUMMARKER
            CP (HL)
            JR Z,LPC3                   ; A marker precedes it, as required

LPC2:       INC HL
            INC HL
            JR LKCALL

LPC3:       DEC HL
            CP (HL)                     ; There must be only one marker: reject "0E 0E FE FE 80 41"
            INC HL
            INC HL
            INC HL
            JR Z,LKCALL

            INC HL                      ; -> the probable page byte
            LD A,(HL)
            DEC HL                      ; Back to the second &FD or &FE
            RLA
            JR NC,LKCALL                ; Bit 7 clear, so not a buffer. A fresh buffer holds &FD or &FE here, and a
                                        ; resolved one a page with bit 7 set, so both pass.
            PUSH HL
            PUSH BC                     ; Bytes left to search
            DEC HL
            DEC HL                      ; -> the marker
            LD BC,&00FF                 ; The length counter increments to zero on the first pass; B = 0

FDFLP:      DEC HL
            INC C
            LD A,(HL)
            CP "$"
            JR Z,FDFLP                  ; A name may end in '$'

            CALL ALNUMUND
            JR C,FDFLP                  ; Letters, digits and underscores are all part of the name.
                                        ; The walk stops at the &FF of an FN token, a space, a control code, the
                                        ; high byte of a line length, a ':', or the string area's terminator.
            INC A
            JR NZ,LPC4                  ; Not the &FF of an "FN" token

            LD A,D
            CP PROCBUFFILL
            JR Z,LPC4                   ; A PROC name genuinely can be preceded by &FF

            INC HL                      ; Step over the &FF ...
            DEC C                       ; ... and drop the &42 that was wrongly counted

LPC4:       INC HL                      ; -> the first character of the name
            LD DE,NMBUFF
            LD A,C
            DEC A
            AND TLNAMELEN
            INC A                       ; Clamp the length so a runaway scan cannot overrun the buffer
            LD C,A
            LD (DE),A                   ; Length first
            INC DE
            LDIR                        ; ... then the name
            POP BC
            POP HL                      ; -> where the CPIR stopped
            RET

LPC5:       LD B,&20                    ; C is zero, so this is another 8K
            CALL CHKHL
            EXX
            DEC B
            EXX
            JR NZ,LKCALL

            SCF                          ; No more buffers
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LOOKDF -- match an FN call against the table of DEF FNs
;
; Entry:  HL -> the call buffer, with its page mapped; the name is in NMBUFF.
; ---------------------------------------------------------------------------------------------------------------------

LOOKDF:     PUSH HL
            IN A,(251)
            PUSH AF                     ; The buffer's page
            LD HL,INSTBUF               ; The table built by COMDF

LKDFLP:     LD BC,(TEMPW1)              ; Just past the last entry
            AND A
            SBC HL,BC
            ADD HL,BC
            JR NC,LKDP4                 ; Every entry tried without success

            LD A,(HL)                   ; Page
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)                   ; Address
            INC HL
            OUT (251),A
            PUSH HL
            CALL MATCHER                ; Compare (DE+1) with the buffered name
            POP HL
            JR C,LKDFLP                 ; No match

            JR LKDP3


; ---------------------------------------------------------------------------------------------------------------------
; LOOKDP -- match a PROC call against the DEF PROC statements
;
; DEF PROC statements are found by scanning line starts, so no table is needed.
;
; Entry:  HL -> the call buffer, with its page mapped; the name is in NMBUFF.
; Exit:   The buffer holds the page and the address just past the definition's name, or a page byte of &FF.
; ---------------------------------------------------------------------------------------------------------------------

LOOKDP:     PUSH HL
            IN A,(251)
            PUSH AF
            CALL ADDRPROG
            DB SKIP1CP                  ; Skip the ADD on the first pass

LKDPLP:     ADD HL,DE                   ; -> the next line

            LD BC,(CC_SIGNIF*256)+TOK_DEFPROC
            CALL LKFC                   ; Look for DEF PROC at the start of a line
            JR C,LKDP4                  ; None left: mark the buffer unresolved.
                                        ; Otherwise HL -> the first character of the line and CHAD -> the token.

            PUSH DE                     ; The line length
            PUSH HL
            LD DE,(CHAD)
            CALL MATCHER
            POP HL
            POP DE
            JR C,LKDPLP                 ; The name did not match

            DEC HL
            DEC HL
            DEC HL
            DEC HL
            EX DE,HL                    ; DE -> the start of the line

LKDP3:      LD B,CALLBUFOK

LKDP35:     IN A,(251)
            AND LMPRPAGE
            OR B                        ; The page, with bit 7 set
            LD B,A
            DB SKIP2LDHL

LKDP4:      LD B,&FF                    ; No definition: bit 5 set marks it as missing

            POP AF
            OUT (251),A                 ; Back to the call site's page
            POP HL
            PUSH HL
            INC HL
            LD (HL),B                   ; Page
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D                   ; Address, or junk when B is &FF
            POP HL                      ; -> where the CPIR stopped
            RET


; ---------------------------------------------------------------------------------------------------------------------
; MATCHERF / MATCHFN / MATCHER -- compare a name
;
; MATCHER compares the candidate at (DE+1) with the name in NMBUFF; MATCHFN compares against a type/length byte and
; name pointed to by DE, which is how NEXT identifies its own variable.
;
; Exit:   NC if they match, with DE past the candidate and HL past the buffered name.
; Notes:  Case is ignored, and spaces in the candidate are skipped -- although PROC and FN names never contain any.
;         A match is only accepted if the candidate name ends there, so ABC does not match ABCD.
; ---------------------------------------------------------------------------------------------------------------------

MATCHERF:   LD DE,TLBYTE

; --- MATCHFN: called by FOR with DE = TLBYTE+33 ---

MATCHFN:    EX DE,HL
            LD A,(HL)
            AND TLNAMELEN
            INC A
            LD B,A                      ; The number of characters to compare
            INC HL
            JR MTCCM

MATCHER:    LD HL,NMBUFF
            LD B,(HL)
            INC HL

MSKIP:      INC DE

MTCCM:      LD A,(DE)
            CP &20
            JR Z,MSKIP                  ; Skip spaces in the candidate

            XOR (HL)
            INC HL
            AND &DF                     ; Ignore case
            SCF
            RET NZ

            DJNZ MSKIP

            INC DE
            LD A,(DE)                   ; The candidate must end here
            JP ALNUMUND                 ; CY if it does not


; =====================================================================================================================
; IMFN -- evaluate a user-defined function
; =====================================================================================================================
;
; For example:
;     PRINT FN OCTAL(345)
; is stored as:
;     PRINT FN OCTAL 0E FE FE pg+80 lo hi (345 0E 01 02 03 04 05)
;
; The page and address point at the '(' or '=' in the DEF FN.
; ---------------------------------------------------------------------------------------------------------------------

IMFN:       CALL RUNFLG
            JP NC,FNSYN                 ; Syntax check

            RST &20                     ; Skip FN
            LD A,NUMMARKER

FNRL:       CP (HL)
            INC HL
            JR NZ,FNRL                  ; Scan forward to the call buffer

            INC HL                      ; Skip the two filler bytes
            INC HL
            LD B,(HL)                   ; The page, with bit 7 set
            BIT 5,B
            JR NZ,MDFERR                ; Bit 5 marks it unresolved

            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)                   ; The address just past the name in the DEF FN
            LD (CHAD),HL                ; CHAD ends at the buffer, so the argument list follows
            RST &20
            CP "("
            JR NZ,FNBF2                 ; No arguments given

            CALL FORESP                 ; The first significant character after '('
            CP ")"
            JR NZ,FNBF                  ; There are arguments

            RST &20                     ; Empty brackets: skip them both
            RST &20

FNBF:       CP A                        ; Z: the call had brackets

FNBF2:      EX AF,AF'                   ; Z' records whether it did
            EX DE,HL
            LD A,B
            CALL TSURPG                 ; HL -> the '(' or '=' in the definition, as in
                                        ; DEF FN TEST=123 or DEF FN TEST(A,B)=A*B
            LD A,(HL)
            SUB "="
            JR NZ,FNBC                  ; The definition takes parameters

            PUSH AF                     ; DEFADD will be &00xx, meaning no parameters
            EX AF,AF'
            JR NZ,FNR6                  ; The call had no brackets either, so evaluate the body

PARAMERR:   RST &08                     ; A parameterless definition called with brackets
            DB ERR_PARAMETER

MDFERR:     RST &08
            DB ERR_FNNODEF

FNBC:       EX AF,AF'
            JR NZ,PARAMERR              ; The definition takes parameters, so the call must have brackets

            CALL FORESP                 ; Skip '(' and find the first significant character
            SUB ")"
            PUSH AF
            JR Z,FNRLE                  ; "()" in the definition: no parameters to bind

            POP AF
            PUSH HL                     ; The address DEFADD will take

; --- Bind each argument to its parameter buffer ---

FNRLA:      INC HL                      ; Skip the parameter letter on the first pass
            LD A,(HL)
            CP NUMMARKER
            JR NZ,FNRLA                 ; Find this parameter's buffer

            IN A,(251)
            PUSH AF                     ; The definition's page
            DEC HL
            LD A,(HL)                   ; A '$' or the parameter letter precedes the marker
            SUB "$"-1
            INC HL
            INC HL                      ; -> the five value bytes
            PUSH AF                     ; A = 1 for a string parameter
            PUSH HL
            CALL SELCHADP               ; Back to the call site
            CALL SEXPTEXPR              ; Evaluate the argument; Z if it is a string
            POP DE                      ; The parameter buffer
            POP BC                      ; B = 1 if a string was expected
            JR Z,FNR3                   ; A string was supplied

            DJNZ FNR4                   ; A number was supplied and expected

FNR3:       DJNZ PARAMERR               ; Type mismatch

FNR4:       CP ")"
            JR NZ,FNR5

            EX AF,AF'
            RST &20                     ; Step over the closing bracket if this was the last argument
            EX AF,AF'

FNR5:       EX AF,AF'                   ; The character after the argument
            POP AF
            OUT (251),A                 ; The definition's page
            CALL FDELETE                ; Drop the value, leaving HL pointing at it
            LD BC,NUMVALSIZE
            LDIR                        ; Copy it into the parameter buffer
            EX DE,HL                    ; HL -> just past the buffer
            CALL FORESP1                ; The next significant character in the definition: ')' or ','
            LD B,A
            EX AF,AF'                   ; The one after the argument in the call
            CP B
            JR NZ,PARAMERR              ; They must agree

            CP ","
            JR Z,FNRLA                  ; Another parameter

            CP ")"
            JR NZ,PARAMERR

FNRLE:      INC HL
            LD A,(HL)
            CP "="
            JR NZ,FNRLE                 ; Find the '=' that introduces the body

            LD BC,1                     ; Advance CHAD past the call's closing bracket

; --- FNR6: evaluate the body ---

FNR6:       LD DE,(CHAD)
            LD A,(CHADP)
            LD B,A
            LD A,(DEFADDP)
            LD C,A
            LD (CHAD),HL                ; Point CHAD at the '=' in the definition
            LD HL,(DEFADD)
            EX (SP),HL
            LD (DEFADD),HL              ; Point DEFADD at this definition's parameter list
            IN A,(251)
            LD (DEFADDP),A
            LD (CHADP),A
            PUSH DE                     ; The caller's CHAD
            PUSH BC                     ; ... and the previous DEFADD, so a function may call a function

            CALL TSURPG
            CALL SEXPTEXPR              ; Skip the '=' and evaluate
            POP BC
            LD A,C
            LD (DEFADDP),A
            LD A,B
            PUSH AF
            CALL SETCHADP
            POP AF
            POP HL
            LD (CHAD),HL
            POP HL
            LD (DEFADD),HL

FNTYP:      RET NZ                      ; Numeric: FN is nominally numeric, so the flags are already right

            POP BC                      ; A string result, so discard the return ...
            JP STRCONT                  ; ... and set the string flag instead


; ---------------------------------------------------------------------------------------------------------------------
; FNSYN -- check an FN reference and create its call buffer
; ---------------------------------------------------------------------------------------------------------------------

FNSYN:      RST &20                     ; Skip FN
            LD (REFFLG),A               ; Non-zero: this line uses FN, so the compile pass must resolve it
            CALL FNNAME
            PUSH AF                     ; A = 1 for a string-typed name
            LD A,FNBUFFILL
            CALL MKCLBF
            CP "("
            JR NZ,FNSY5                 ; No arguments, as in FN TEST

            RST &20
            CP ")"
            JR Z,FNSY4                  ; Empty brackets, as in FN TEST()

FNARL:      CALL SCANNING               ; Arguments may be of either type
            LD A,C
            CP ")"
            JR Z,FNSY4

            CALL INSISCOMA
            JR FNARL

FNSY4:      RST &20

FNSY5:      POP AF
            DEC A                       ; Z if the name ended in '$'
            JR FNTYP                    ; Numeric returns; a string result discards the return and sets the flag


; ---------------------------------------------------------------------------------------------------------------------
; FNNAME -- check a function name
;
; Exit:   A = 1 if the name ended in '$', 0 otherwise; HL past it.
; ---------------------------------------------------------------------------------------------------------------------

FNNAME:     CALL GETALPH                ; It must begin with a letter

DFNLP:      INC HL
            LD A,(HL)
            CALL ALNUMUND
            JR C,DFNLP                  ; Letters, digits and underscores continue it

            SUB "$"
            JR NZ,FNN2

            INC HL

FNN2:       INC A
            RET


; =====================================================================================================================
; LOCAL -- make variables local to the current procedure
; =====================================================================================================================
;
; Implemented as a procedure call with an empty argument list: the same parameter machinery hides any globals of
; those names and creates local copies, and END PROC unwinds them.
; ---------------------------------------------------------------------------------------------------------------------

LOCAL:      CALL RUNFLG
            LD D," "                    ; A null "intervening token", so "LOCAL REF x" is not accepted
            JR NC,DPSY2                 ; Syntax check

            XOR A
            LD (PRPTRP),A
            LD HL,CARET                 ; Point the call list at a CR that happens to sit in ROM, giving an
            LD (PRPTR),HL               ; argument list that is immediately empty
            CALL ADDRCHAD
            LD (DPPTRP),A
            LD (DPPTR),HL               ; The definition list is this statement's own variable list
            CALL DPRA                   ; The enclosing procedure's return frame
            LD B,A
            PUSH BC
            PUSH HL
            CALL PROP2                  ; Bind the "parameters", without writing a terminator
            CALL PTTODP
            LD HL,(BSTKEND)
            DEC HL
            DEC HL
            DEC HL
            DEC HL
            POP DE                      ; The address
            POP BC
            LD (HL),B                   ; Type and page
            LD A,C
            JP SEDA                     ; Re-stack the frame that DPRA removed


; =====================================================================================================================
; DEF PROC and PROC
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; DEFPROC -- the DEF PROC statement
;
; Reaching one during ordinary execution means the procedure was fallen into rather than called, so the whole body
; is skipped.
; ---------------------------------------------------------------------------------------------------------------------

DEFPROC:    CALL RUNFLG
            JR NC,DPROC2

            POP DE                      ; Discard the next-statement return
            LD DE,(TOK_THEN*256)+TOK_ENDPROC
                                        ; TOK_THEN acts as the null "intervening" token
            CALL SEARCH
            DB ERR_NOENDPROC

DPROC2:     RST &18
            CALL GETALPH                ; The name must begin with a letter

DPNMLP:     INC HL
            LD A,(HL)
            CALL ALNUMUND
            JR C,DPNMLP

            LD (CHAD),HL
            RST &18
            CP TOK_DATA
            JR NZ,DPSY1

            RST &20                     ; "DEF PROC name DATA" takes its arguments from a DATA list
            RET

DPSY1:      CALL CRCOLON
            RET Z                       ; No parameters

            LD D,TOK_REF

; --- DPSY2: LOCAL enters here with D = a space, so the REF test never matches ---

DPSY2:      CP D
            JR NZ,DPSY3

            RST &20                     ; Skip REF

DPSY3:      PUSH DE
            CALL VARAR                  ; Check for the "name()" form
            CALL NZ,LOOKVARS            ; Otherwise an ordinary name
            CALL RCRC
            POP DE
            RET Z                       ; The list has ended

            CALL INSISCOMA
            JR DPSY2


; ---------------------------------------------------------------------------------------------------------------------
; VARNAME -- check for a variable name
;
; Entry:  CHAD at the name.
; Exit:   C = its length excluding spaces, CY if the length is legal for a "name()" form.
;         CHAD is unchanged; A = the character after the name.
; ---------------------------------------------------------------------------------------------------------------------

VARNAME:    RST &18
            CALL ALPHA
            RET NC                      ; Not a legal first character

            PUSH HL
            LD BC,&0B00                 ; B = the maximum length plus one, C = the length so far

VNMLP:      RST &20
            INC C
            CALL ALNUMUND
            JR C,VNMLP

            CP "$"
            JR NZ,VNM2

            RST &20

VNM2:       LD A,C
            CP B
            EX (SP),HL
            LD (CHAD),HL                ; Restore the original CHAD
            POP HL
            LD A,(HL)
            RET                         ; CY if the length is acceptable


; ---------------------------------------------------------------------------------------------------------------------
; VARAR -- check for the "name()" form, as in FRED$() or DOGS()
;
; Used by LOCAL and DEF PROC, where a bare array name is written that way.
;
; Exit:   Z with CHAD and HL past it if that is what was found; NZ with CHAD unchanged otherwise.
; ---------------------------------------------------------------------------------------------------------------------

VARAR:      CALL VARNAME
            DEC A                       ; NZ: A holds a significant character
            RET NC                      ; Not a legal name for the "()" form

            CP "("-1
            RET NZ                      ; An ordinary variable

            CALL FORESP
            CP ")"
            RET NZ                      ; Something inside the brackets, as in ALPHA(8)

            LD (CHAD),HL
            RST &20
            CP A                        ; Z: the "()" form was skipped
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PROCS -- call a procedure
;
; Reached whenever a statement begins with a letter rather than a command token.
; ---------------------------------------------------------------------------------------------------------------------

PROCS:      ADD A,TOK_CMDFIRST          ; Undo the subtraction the dispatcher made
            CALL GETALPH
            RST &18
            CALL RUNFLG
            JR NC,PROCSY

            LD A,NUMMARKER

PRRL:       CP (HL)
            INC HL
            JR NZ,PRRL                  ; Find the call buffer

            INC HL                      ; Skip the two filler bytes
            INC HL
            LD B,(HL)                   ; The page
            BIT 5,B
            JR NZ,MDPERR                ; Bit 7 is always set; bit 6 marks an external command and bit 5
                                        ; "no definition"
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)                   ; The DEF PROC line, or the external command's entry point
            INC HL
            LD (PRPTR),HL               ; The argument list begins here
            IN A,(251)
            LD (PRPTRP),A
            LD A,B
            LD (DPPTRP),A
            CALL TSURPG                 ; Map the definition
            LD HL,5
            ADD HL,DE                   ; Step over the line header and the DEF PROC token
            CALL FORESP1                ; Skip any spaces or control codes

PRPNM:      INC HL
            LD A,(HL)
            CALL ALNUMUND
            JR C,PRPNM                  ; Step over the definition's name

            LD (DPPTR),HL               ; Its parameter list begins here
            PUSH DE
            CALL PROPAR                 ; Bind the arguments
            LD B,BSTKPROC
            CALL BSTKE
            INC (HL)                    ; Return to the statement after the call
            POP HL                      ; The DEF PROC line
            POP DE                      ; Discard the next-statement return
            LD A,(DPPTRP)
            LD C,2                      ; Statement 2: just past the DEF PROC statement itself
            JP RLEPC2


; ---------------------------------------------------------------------------------------------------------------------
; DPRA -- unstack a PROC return frame
; ---------------------------------------------------------------------------------------------------------------------

DPRA:       LD B,BSTKPROC
            CALL RETLOOP
            RET Z

MDPERR:     RST &08
            DB ERR_NODEFPROC


; ---------------------------------------------------------------------------------------------------------------------
; PROCSY -- check a procedure call and create its buffer
; ---------------------------------------------------------------------------------------------------------------------

PROCSY:     INC HL
            LD A,(HL)
            CALL ALNUMUND
            JR C,PROCSY                 ; Step over the name

            LD A,PROCBUFFILL
            CALL MKCLBF
            CALL CRCOLON
            RET Z                       ; No arguments

PCSYL:      CALL VARAR                  ; The "name()" form is allowed as an argument
            CALL NZ,SCANNING            ; Otherwise evaluate it
            CALL RCRC
            RET Z

            CALL INSISCOMA
            JR PCSYL


; ---------------------------------------------------------------------------------------------------------------------
; MKCLBF -- create a call buffer at (HL)
;
; Entry:  A = the filler byte, FNBUFFILL or PROCBUFFILL.
; Exit:   The buffer reads "0E xx xx xx ?? ??"; CHAD points past it and A is the next significant character.
; ---------------------------------------------------------------------------------------------------------------------

MKCLBF:     PUSH AF
            CALL MAKESIX                ; Open six bytes after the name and write the marker
            POP AF
            LD (HL),A
            INC HL
            LD (HL),A
            INC HL
            LD (HL),A
            INC HL
            INC HL                      ; The last two bytes are left as they fall
            LD (CHAD),HL
            RST &20
            RET


; ---------------------------------------------------------------------------------------------------------------------
; MAKESIX -- open a six-byte invisible form at (HL)
;
; The primitive behind every embedded value: numeric literals, call buffers and DEF FN parameter slots.
;
; Exit:   HL -> the five bytes after the marker.
; ---------------------------------------------------------------------------------------------------------------------

MAKESIX:    LD BC,NUMFORMLEN
            CALL MAKEROOM
            LD (HL),NUMMARKER
            INC HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LKFNVAR -- resolve a name from the current DEF FN's parameters
;
; Called by the evaluator whenever DEFADD is set, which is only while a function body is being evaluated.
;
; Entry:  HL -> the first character of the name.
; Exit:   NC with HL unchanged if it is not a parameter, so the ordinary variables are searched instead.
;         CY if it is: the value has been stacked, the name skipped, and A = '$' for a string.
; Notes:  Only single-letter names are considered. Anything longer always refers to a global.
; ---------------------------------------------------------------------------------------------------------------------

LKFNVAR:    CALL RUNFLG
            RET NC                      ; Syntax check

            PUSH HL                     ; In case it turns out not to be a parameter
            LD B,(HL)                   ; The letter
            RST &20
            CP "$"
            LD C,NUMMARKER              ; A value that cannot be a letter, used as "no dollar"
            JR NZ,LKFV0

            LD C,A
            RST &20

LKFV0:      CALL ALNUMUND
            JR C,LKFVF                  ; A longer name, such as TEST, X1 or ABC$: not a parameter

            LD HL,DEFADD-1
            CALL ASV2                   ; -> just past the '(' in the definition

LKFV1:      INC HL
            LD A,(HL)
            CP NUMMARKER
            JR NZ,LKFV1                 ; Find the next parameter buffer

            DEC HL
            LD A,(HL)
            CP C                        ; '$' if a string was wanted
            JR NZ,LKFV2                 ; A numeric parameter

            DEC HL
            LD A,(HL)                   ; The letter precedes the '$'
            INC HL

LKFV2:      XOR B
            AND &DF                     ; Case-insensitive comparison
            JR Z,LKFVM

            LD DE,7
            ADD HL,DE                   ; Step over this parameter's five-byte buffer
            CALL FORESP1
            CP ","
            JR Z,LKFV1                  ; More parameters follow

LKFVF:      POP HL                      ; Not found: restore the original position
            AND A
            RET

LKFVM:      INC HL
            INC HL                      ; -> the five bytes
            LD A,C
            CALL HLTOFPCS               ; Stack them
            POP BC                      ; Discard the saved position
            LD HL,FLAGS
            RES 6,(HL)
            CP "$"
            SCF
            RET Z                       ; A string parameter

            SET 6,(HL)                  ; Numeric
            RET


; ---------------------------------------------------------------------------------------------------------------------
; FORESP / FORESP1 -- advance HL to the next significant character
; ---------------------------------------------------------------------------------------------------------------------

FORESP:     INC HL

FORESP1:    LD A,(HL)
            CP CC_SIGNIF
            RET NC

            JR FORESP


; =====================================================================================================================
; The compile pass
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; SCOMP -- mark the whole program as needing recompilation
;
; Called by LOAD, DELETE, KEYIN, RENUM and line insertion.
; ---------------------------------------------------------------------------------------------------------------------

SCOMP:      LD A,&FF
            LD (COMPFLG),A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GT4R / GT4P -- resume execution after a command that disturbed the program
;
; GT4R keeps the current position (DELETE, MERGE); GT4P takes one from the stack (RENUM, KEYIN). Both arrange a jump
; so that CLA, NXTLINE and the page bytes are rebuilt from scratch.
; ---------------------------------------------------------------------------------------------------------------------

GT4R:       LD A,(SUBPPC)
            LD HL,(PPC)
            DB SKIP2LDDE

GT4P:       POP AF                      ; The statement
            POP HL                      ; The line

; --- Entry with A = the statement minus one and HL = the line ---

            INC A
            CALL GOTO4
            LD A,&FF
            LD (PPC+1),A                ; Force the line search to start at PROG, since PPC is now meaningless


; ---------------------------------------------------------------------------------------------------------------------
; DOCOMP / COMPILE -- resolve labels and call buffers
;
; Runs before every execution. CHAD is preserved through KCUR, which MAKEROOM adjusts automatically, because
; creating label variables can move memory.
; ---------------------------------------------------------------------------------------------------------------------

DOCOMP:     CALL SCOMP

COMPILE:    LD A,(CHADP)
            LD (KCURP),A
            LD HL,(CHAD)
            LD (KCUR),HL                ; Parked where it will be adjusted if memory moves
            LD HL,(CLA)
            PUSH HL
            LD A,(CLAPG)
            PUSH AF
            LD A,(COMPFLG)
            AND A
            JR Z,COMPILEL               ; Only the edit line needs doing

; --- Execute every LABEL statement, assigning its line number to the named variable ---

            CALL ADDRPROG

DOLBLP:     LD BC,(CC_SIGNIF*256)+TOK_LABEL
            CALL LKFC
            JR C,LABSD                  ; All done

            IN A,(251)                  ; HL -> the first character of the line, CHAD -> the token, DE = its length
            LD (CHADP),A                ; Keep CHAD consistent for the assignment below
            PUSH HL
            ADD HL,DE                   ; -> the next line
            EX (SP),HL
            DEC HL
            DEC HL
            DEC HL
            LD C,(HL)
            DEC HL
            LD B,(HL)                   ; BC = this line's number
            CALL STACKBC
            CALL SVNUMV                 ; Skip the token and check the variable name
            CALL ASSIGN
            POP HL
            JR DOLBLP

LABSD:                                  ; Bit 7 of COMPFLG still says "compiling the program"
            CALL COMALL                 ; Resolve PROC and FN buffers; CY here means FNs too

            XOR A
            LD (COMPFLG),A              ; Bit 7 clear: now compiling the edit line

COMPILEL:   CALL ELCOMAL                ; The edit line always needs PROC resolution, and FN if it uses one
            POP AF
            LD (CLAPG),A
            POP HL
            LD (CLA),HL
            LD HL,(KCUR)
            LD (CHAD),HL                ; Recover CHAD, adjusted if memory moved
            LD A,(KCURP)
            JP SETCHADP


; ---------------------------------------------------------------------------------------------------------------------
; LKFC -- find a token at the start of a program line
;
; Entry:  B = CC_SIGNIF, C = the token, HL -> a line.
; Exit:   NC with HL -> the first character of the line and CHAD -> the token; CY if the program ran out.
; Notes:  Leading spaces and control codes are skipped, so an indented DEF PROC is still found.
; ---------------------------------------------------------------------------------------------------------------------

LKFCLP:     ADD HL,DE

LKFC:       LD A,(HL)
            ADD A,1
            RET C                       ; The program terminator

            CALL CHKHL                  ; Keep line starts inside the window
            INC HL
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)                   ; DE = the line length
            INC HL
            LD A,(HL)                   ; The first character: a quick test for the common case of no indentation

LKFC2:      CP C
            JR Z,LKFC5

            CP B
            JR NC,LKFCLP                ; A significant character that is not the token: try the next line

            PUSH HL                     ; Indented, so skip the spaces and control codes

LKFCSK:     CP CC_ENTER
            JR Z,LKFC4                  ; An empty line

            INC HL
            LD A,(HL)
            CP B
            JR C,LKFCSK

            LD (CHAD),HL                ; Provisionally, in case this is a match
            POP HL
            CP C
            RET Z

            PUSH HL

LKFC4:      POP HL
            JR LKFCLP

LKFC5:      LD (CHAD),HL
            RET
