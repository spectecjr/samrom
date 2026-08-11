; =====================================================================================================================
; MISCX2.ASM -- More command bodies that execute from RAM: DEF KEYCODE, DEF FN, the tokeniser, MERGE
; =====================================================================================================================
;
; Like MISCX1.ASM, every routine here is assembled at its RAM execution address and copied there by a stub in
; MISC2.ASM before being run. Each ends with an EQU giving its length, which those stubs sum to locate the next
; body in ROM1.
;
; The tokeniser is the most significant of them: it is what turns typed keywords into the token bytes described in
; docs/tokenized-program-format.md.
;
; =====================================================================================================================

            ORG INSTBUF


; =====================================================================================================================
; DEF KEYCODE -- define the text a key produces
; =====================================================================================================================
;
; Forms: DEF KEYCODE n,a$        the definition is a string
;        DEF KEYCODE n: rest     the rest of the line is the definition
;
; The keyboard has 69 keys with three shifts (caps, symbol and control), giving 276 entries in the key map, any of
; which may be programmed to produce any code. Codes from 192 upwards may be given definitions.
; ---------------------------------------------------------------------------------------------------------------------

DKP2:       CALL EXPT1NUM               ; The key code
            CALL COMMASC
            JR Z,DFK4                   ; A comma or semicolon, so a string definition follows

            CALL RUNFLG
            JP NC,DFKNL                 ; Syntax check: verify the rest of the line and strip its number forms

            EX DE,HL                    ; DE = CHAD
            LD HL,(NXTLINE)
            SCF
            SBC HL,DE
            LD B,H
            LD C,L                      ; NXTLINE shares CHAD's page, so this is the length of the rest of the line
            DEC BC                      ; The ':' separator is not part of the definition
            INC DE
            LD HL,LINEEND
            EX (SP),HL                  ; Replace the next-statement return with LINEEND, so the rest of the line
            JR DFK5                     ; is stored rather than executed

DFK4:       CALL SSYNTAXA               ; A string definition

            CALL GETSTRING              ; BC = length, DE = start, page mapped

DFK5:       PUSH DE
            PUSH BC
            CALL GETBYTE                ; The key code
            INC A                       ; 255 wraps to 0
            CP 193
            JP C,IOORERR                ; Only codes 192 to 254 may be defined

            DEC A
            PUSH AF
            CALL FNDKYD                 ; Is there already a definition?
            JR C,DFK55                  ; No

; --- Close up the existing definition: HL -> its text, BC = its length ---

            INC BC
            INC BC
            INC BC                      ; Include the code byte and the two length bytes
            PUSH HL
            ADD HL,BC                   ; -> just past the definition, plus three
            PUSH HL
            CALL DKTR                   ; -> the terminator, plus three
            POP DE
            AND A
            SBC HL,DE
            INC HL
            LD B,H
            LD C,L                      ; The bytes to move down
            EX DE,HL
            DEC HL
            DEC HL
            DEC HL                      ; -> just past the definition's end
            POP DE
            DEC DE
            DEC DE
            DEC DE                      ; -> its start
            LDIR

DFK55:      POP AF                      ; The key code
            POP BC                      ; The definition's length
            PUSH AF
            LD A,B
            CP &FF
            JR Z,DFK6                   ; A length of &FFFF, as produced by "DEF KEY 1" followed by ENTER

            OR C                        ; A zero length is also nothing to store

DFK6:       JP Z,PPRET                  ; Discard the key code and source, and return

; --- Open room for the new definition: BC+3 bytes ---

            PUSH BC
            CALL DKTR                   ; HL -> the terminator, plus three
            POP BC
            PUSH HL
            ADD HL,BC                   ; The terminator's new position; NC
            EX DE,HL
            LD HL,(DKLIM)
            SBC HL,DE
            JP C,TMDERR                 ; It would pass the limit. The terminator may sit exactly on it.

            EX DE,HL
            LD (HL),&FF                 ; The new terminator; the old one is about to be overwritten
            POP DE
            DEC DE
            DEC DE
            DEC DE                      ; -> the old terminator

            POP AF                      ; The key code
            POP HL                      ; The definition text
            LD (DE),A
            INC DE
            LD A,C
            LD (DE),A
            INC DE
            LD A,B
            LD (DE),A                   ; The length
            INC DE
            LDIR
DKFIN:      RET

DKLN:       EQU DKFIN+1-DKP2


RDLN:       EQU 0                       ; READ now executes in place; its length is retained as zero so that the
                                        ; address arithmetic in the stubs still adds up


; =====================================================================================================================
; DEF FN -- check a function definition and create its parameter buffers
; =====================================================================================================================
;
; Inert at run time. At check time each parameter name is followed by an invisible six-byte form, which IMFN fills
; with the argument's value when the function is called.
; ---------------------------------------------------------------------------------------------------------------------

            ORG INSTBUF

DFNP2:      CALL RUNFLG
            JP C,SKIPCSTAT              ; Running: a DEF FN does nothing

            RST &18
            CALL FNNAME
            PUSH AF                     ; A = 1 for a string-typed name
            LD (CHAD),HL
            RST &18
            CP "("
            JR NZ,DFN5                  ; No parameter list

            RST &20
            CP ")"
            JR Z,DFN4                   ; An empty list

DFNPL:      CALL GETALPH                ; A parameter must be a single letter
            INC HL
            LD A,(HL)
            CP "$"
            JR NZ,DFN3

            INC HL                      ; A string parameter

DFN3:       CALL MAKESIX                ; Open the value buffer after the name
            LD (CHAD),DE                ; -> the last of the five bytes
            RST &20
            CP ")"
            JR Z,DFN4

            CALL INSISCOMA
            JR DFNPL

DFN4:       RST &20

DFN5:       CP "="
            JR NZ,DFNNS

            CALL SEXPTEXPR              ; The body; Z if it yields a string
            POP BC
            JR Z,DFN6                   ; A string body

            DEC B
            RET NZ                      ; A numeric body and a numeric name: correct

DFN6:       DEC B                       ; A string body needs a name ending in '$'
            RET Z

DFNNS:      RST &08
            DB ERR_NONSENSE

DFNLN:      EQU DFNNS+2-DFNP2


; =====================================================================================================================
; THE TOKENISER
; =====================================================================================================================
;
; Replaces spelled-out keywords in a line with their token bytes. Runs at CDBUFF+&80 rather than INSTBUF, because
; INSTBUF belongs to whichever command invoked it.
;
; Entry:  DE -> the text, normally the edit line; VAL supplies its own.
; Exit:   The text is tokenised in place and shortened accordingly.
;
; A match produces either a single byte in &85-&FE, or the two bytes &FF and a function code in &3B-&83. One space
; before the word and one after are absorbed into the token, so listings can put them back without accumulating.
;
; Nothing inside a string literal is tokenised, nothing after REM is tokenised, and an &FF already present is
; stepped over with its code byte, so re-tokenising an edited line is safe.
;
; See docs/tokenized-program-format.md for the resulting format.
; ---------------------------------------------------------------------------------------------------------------------

            ORG CDBUFF+&80

TOKPT2:     EXX
            EX DE,HL                    ; HL = the start of the edit line, workspace, or wherever

TOKRST:     LD A,(HL)                   ; Re-entry after a substitution: point CHAD at the new position
            JR TOKQUEN

; --- LOOKNA: no keyword matched, so skip the rest of this word ---

LOOKNA:     POP HL
            LD A,(HL)
            INC HL
            CP "A"
            JR C,TOKQUEN                ; The candidate was '<' or '>', which is only one character

            DB SKIP1CP

LKNONALP:   INC HL
            LD A,(HL)
            CALL ALPHA
            JR C,LKNONALP               ; Run past the letters ...

            CP "_"

            JR Z,LKNONALP               ; ... and any underscores, so "print_out" is not matched at "print"

TOKQUEN:    LD (CHAD),HL
            DB SKIP1CP

TOKMLP:     RST &20
            EX DE,HL
            CP CC_ENTER
            RET Z                       ; End of the line

            CALL ALPHA
            JR C,POSFIRST               ; A letter may begin a keyword

            CP "<"
            JR Z,POSFIRST               ; So may '<', for "<=" and "<>"

            CP ">"
            JR Z,POSFIRST               ; ... and '>', for ">="

            INC DE
            CP TOK_FNPREFIX
            JR Z,FNTS                   ; An existing function token: skip its code byte too

            DEC DE
            CP &22
            JR NZ,TOKMLP

; --- Inside a string literal: skip to the closing quote ---

QUOTELP:    INC DE
            LD A,(DE)
            CP CC_ENTER
            RET Z

            CP &22
            JR NZ,QUOTELP

FNTS:       INC DE
            EX DE,HL
            LD A,(HL)
            JR TOKQUEN


; ---------------------------------------------------------------------------------------------------------------------
; POSFIRST -- a possible keyword starts here
; ---------------------------------------------------------------------------------------------------------------------

POSFIRST:   PUSH DE                     ; Where the word begins in the line
            EX DE,HL
            LD DE,TOKFIN+3              ; A scratch area just past this routine, in the code buffer
            LD BC,MAXTOKENLEN
            PUSH DE
            LDIR                        ; Copy the candidate somewhere the matcher can read it safely
            POP DE
            LD HL,KEYWTAB-1
            LD A,KEYWNO+1
            CALL JGTTOK                 ; A = 1 to KEYWNO on a match, Z if none
            JR NZ,YGOTM

            LD HL,(MTOKV)               ; Offer the word to a user tokeniser
            INC H
            DEC H
            CALL NZ,HLJUMP

            JR Z,LOOKNA                 ; No match, or no vector installed

YGOTM:      EX DE,HL                    ; HL = the word's start, DE just past it, both in the scratch copy
            AND A
            SBC HL,DE                   ; The length of the matched word
            POP DE                      ; The word's position in the line
            ADD HL,DE
            EX DE,HL                    ; HL -> the start in the line, DE -> just past it

            CP &4A
            JR NC,TOK42                 ; Match index &4A and above are commands

            ADD A,&3A                   ; Below that they are functions, giving codes &3B-&83
            LD (HL),TOK_FNPREFIX        ; The first letter becomes the prefix ...
            INC HL
            JR TOK55                    ; ... and the code overwrites the second

TOK42:      ADD A,&3B                   ; Commands: match index to token, giving &85 upwards
            CP TOK_FNPREFIX
            JR NZ,TOK43                 ; The last table entry is "INK", which would give &FF

            LD A,TOK_PEN                ; So INK is accepted as a synonym for PEN

TOK43:      DEC HL                      ; -> the character before the word
            EX AF,AF'
            LD A,(HL)
            CP " "
            JR Z,TOK5                   ; A leading space, which the token overwrites

            INC HL                      ; No space, so the token goes on the first letter

TOK5:       EX AF,AF'

TOK55:      LD (HL),A                   ; Write the token over the spelled-out form
            INC HL                      ; HL -> the first byte to remove
            EX DE,HL
            LD A,(HL)
            CP " "
            JR NZ,TOK6                  ; No trailing space

            INC HL                      ; Absorb one trailing space into the region being closed up

TOK6:       PUSH DE
            CALL RECLAIM1               ; Close up from (DE) to (HL)
            POP DE
            LD H,D
            LD L,E                      ; Carry on scanning from here
            DEC DE
            LD A,(DE)
            CP TOK_REM
            JP NZ,TOKRST                ; Keep tokenising

TOKFIN:     RET                         ; REM: the rest of the line is left exactly as typed

TOKLN:      EQU TOKFIN+1-TOKPT2


; =====================================================================================================================
; MERGE -- load a program and splice it into the current one
; =====================================================================================================================
;
; The file is loaded into workspace, then its three parts are merged separately: lines replace lines of the same
; number, numeric variables are re-created one at a time, and strings and arrays replace any of the same name.
; ---------------------------------------------------------------------------------------------------------------------

            ORG INSTBUF

MEPRO2:     CALL SETWORK                ; Clear workspace, in case of MERGE a$+b$
            LD BC,1
            CALL WKROOM                 ; One byte, which also forces WKEND to move via MKRBIG
            LD (HL),&FF                 ; A terminator, so the merge loops know where to stop
            PUSH HL
            CALL RDLLEN                 ; CDE = the file's length
            POP HL
            PUSH BC
            PUSH DE
            LD A,C
            LD B,D
            LD C,E
            CALL MKRBIG                 ; Open ABC bytes
            POP DE
            POP BC
            SCF                          ; Load rather than verify
            CALL JLDVD
            CALL MBASLNS                ; Merge the program lines
            CALL MNUMS                  ; ... the numeric variables
            LD HL,HDL+16
            CALL RDTHREE                ; CDE = the length of the program alone
            PUSH BC
            PUSH DE
            LD L,(HDL+22)\256
            CALL RDTHREE                ; CDE = program plus numeric variables plus the gap
            LD A,C
            EX DE,HL
            POP DE
            POP BC
            CALL SUBAHLCDE              ; AHL = the numeric variables and the gap
            LD BC,1
            CALL ADDAHLBC               ; Allow for the program terminator
            PUSH AF
            PUSH HL
            CALL ADDRWK
            POP BC
            POP AF
            CALL RECL2BIG               ; Discard the loaded variables and gap, leaving only the string area


; ---------------------------------------------------------------------------------------------------------------------
; MSTAR -- merge the loaded strings and arrays
;
; Entry:  Workspace holds the loaded records, terminated by &FF.
; ---------------------------------------------------------------------------------------------------------------------

MSTAR:      CALL ADDRWK                 ; -> the next record's type byte, or the terminator
            LD A,(HL)
            INC A
            JP Z,GT4R                   ; All done

            LD DE,TLBYTE
            AND &0F
            LD C,A
            LD B,0
            LD A,(HL)
            LDIR                        ; Copy its type byte and name to the search buffer
            CALL STARYLK2               ; Is there already a variable of that name?
            CALL NZ,ASDEL2              ; Delete it

            CALL ADDRWK
            LD BC,11
            ADD HL,BC                   ; -> the length field
            LD A,(HL)
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            EX DE,HL
            LD C,STRHDRSIZE
            CALL ADDAHLBC               ; AHL = the whole record's length
            PUSH AF
            PUSH HL
            CALL ADDRELND               ; -> the end of the string area
            POP BC
            POP AF
            PUSH AF
            PUSH BC
            CALL MKRBIG                 ; Open room for it
            EX DE,HL
            IN A,(251)
            LD C,A                      ; CDE = the destination
            POP HL
            RES 7,H
            LD (MODCOUNT),HL
            POP AF
            LD (PAGCOUNT),A
            CALL ADDRWK
            IN A,(251)                  ; AHL = the source
            CALL FARLDIR
            CALL ADDRWK
            CALL ASDEL3                 ; Remove it from workspace
            JR MSTAR


; ---------------------------------------------------------------------------------------------------------------------
; MBASLNS -- merge the loaded program lines
; ---------------------------------------------------------------------------------------------------------------------

MBASLNS:    CALL ADDRWK

MPRG1:      LD B,(HL)
            INC HL
            LD A,B
            INC A
            RET Z                       ; The terminator: every line has been dealt with

            LD C,(HL)
            CALL FNDLP                  ; Find line BC, searching from PROG
            PUSH HL
            IN A,(251)
            PUSH AF                     ; The destination's page
            CALL Z,NORECL               ; A line of that number exists, so delete it

            CALL ADDRWK
            INC HL
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            INC BC
            INC BC
            INC BC
            INC BC                      ; BC = the whole source line, header included
            POP AF
            POP HL
            PUSH HL
            PUSH AF
            PUSH BC
            CALL TSURPG
            CALL MAKEROOM
            CALL ADDRWK                 ; AHL = the source
            POP BC
            CALL SPLITBC
            POP BC
            LD C,B
            POP DE                      ; CDE = the destination
            CALL FARLDIR
            CALL ADDRWK
            CALL NORECL                 ; Remove the line from workspace
            JR MPRG1


; ---------------------------------------------------------------------------------------------------------------------
; MNUMS -- merge the loaded numeric variables
;
; Each is re-created through the ordinary variable machinery rather than copied, so that the chains are rebuilt
; correctly. Works with up to 16K of numeric variables.
; ---------------------------------------------------------------------------------------------------------------------

MNUMS:      LD A,"a"

MNUML:      LD (FIRLET),A
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC D
            CALL NZ,MNUMSR              ; This letter's chain is not empty

            INC HL
            LD A,(FIRLET)
            INC A
            CP "z"+1
            JR C,MNUML

            RET

MNUMSR:     PUSH HL                     ; The position in the loaded chain roots

MNSRL:      DEC D
            ADD HL,DE                   ; Follow the relative link
            LD A,(HL)
            AND TLHIDDEN+TLUNUSED
            JR NZ,MNSR3                 ; Hidden or unused variables are not merged

            IN A,(251)
            PUSH AF
            PUSH HL
            LD A,(HL)
            AND TLNAMELEN
            LD C,A
            LD A,(HL)
            RES 6,A                     ; Clear the FOR bit: a merged variable is an ordinary one
            LD (TLBYTE),A
            INC HL
            INC HL
            INC HL                      ; -> the rest of the name, or the value
            JR Z,MNSR2                  ; A one-letter name

            LD B,0
            LD DE,FIRLET+1
            LDIR                        ; Copy the rest of the name to the buffer

MNSR2:      CALL HLTOFPCS               ; Stack the value
            CALL CRTVAR4                ; Create the variable with that value, name and type
            POP HL
            POP AF
            OUT (251),A

MNSR3:      INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC D
            JR NZ,MNSRL                 ; More variables of this letter

            POP HL
MEEND:      RET

MELN:      EQU MEEND+1-MEPRO2

 ORG &C000+RENLN+GETLN+DELLN+KEYLN+POPLN+INPLN+DKLN+RDLN+DFNLN+TOKLN+MELN

                                        ; Routines in this file: MERGE, EOF, PTR, PATH$, the FN stubs, LINK
