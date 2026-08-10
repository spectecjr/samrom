; =====================================================================================================================
; LOOKVAR.ASM -- Variable lookup
; =====================================================================================================================
;
; Finds a named variable, or reports where a new one of that name should be created. Every reference to a variable in
; a running program comes through here, so the layouts described below are the definitive record of how SAM BASIC
; stores its variables.
;
; ENTRY CONTRACT
; --------------
; A variable name is expected at (CHAD), with its first character already in A. NAMTOBUF copies the name into the
; buffer at FIRLET, classifies it, and steps CHAD past it. The search then splits by kind:
;
;   Simple numerics       NUMLOOK   -- 26 singly-linked chains, one per initial letter
;   Strings and arrays    STARYLK   -- one flat list scanned linearly
;
; EXIT CONTRACT (common to both searches)
;   NZ        Found.    HL -> the value (numerics: the first of 5 bytes; strings/arrays: the length-in-pages byte)
;                       C  = the type/length byte as stored in the variables area
;   Z         Not found. C = the type/length byte that was wanted, and HL points at the place a new record would go:
;                        the &FFFF chain terminator for numerics, or the VARSTERM stopper for strings and arrays.
;   Always    FLAGS bit 6 (FFLAGNUM) reflects the type, and FIRLET holds the name.
;
; NUMERIC VARIABLE LAYOUT
; -----------------------
; NVARS points at 26 sixteen-bit chain roots, one per letter a-z. Each is a displacement from its own address to the
; first variable starting with that letter, or &FFFF for "none". Each record then is:
;
;     +0      type/length byte    (see below)
;     +1..2   displacement to the next variable of this letter, or &FFFF to end the chain
;     +3..    second and subsequent name letters (absent for a one-letter name)
;     ..      5-byte value
;     ..      FOR variables only: limit (5), step (5), looping page (1), address (2), statement (1)
;
; Links are relative, so the whole area can be moved without rewriting them.
;
; Type/length byte:  bit 7 TLHIDDEN   shadowed by a PROC local
;                    bit 6 TLFORVAR   FOR control variable, record extended as above
;                    bit 5 TLUNUSED   dead slot, available for a PROC local to re-use
;                    bits 4-0         name length minus one, so 0 means a single letter
;
; STRING AND ARRAY LAYOUT
; -----------------------
; A single list running from SAVARS up to ELINE, terminated by VARSTERM. Each record is:
;
;     +0      type/length byte
;     +1..10  name, padded to MAXNAMELEN characters
;     +11     data length in 16K pages
;     +12..13 data length modulo 16K
;     +14..   the data itself
;
; Type/length byte:  bit 7 TLHIDDEN     shadowed by a PROC local
;                    bit 6 TLSTRARRAY   string array (or a sliced reference to one)
;                    bit 5 TLNUMARRAY   numeric array
;                    bits 4-0           true name length (bits 6 and 5 both clear means a simple string)
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; LOOKVARS / LKVARS2 -- find the variable named at (CHAD)
;
; Entry:  LOOKVARS with CHAD pointing at the name; LKVARS2 from the evaluator with A and (HL) already the first
;         character.
; Exit:   As the common contract above. CHAD points past the name and any trailing '$' or '('.
; Notes:  At syntax-check time the searches are skipped entirely -- there are no variables yet, so the routine just
;         reports "found" so that the caller's type checking can proceed.
; ---------------------------------------------------------------------------------------------------------------------

LOOKVARS:   RST &18                     ; A = first character of the name, HL = CHAD

LKVARS2:    CALL NAMTOBUF               ; Copy the name to FIRLET and classify it.
                                        ; Returns C = type/length, HL = FLAGS, DE past the name, A = terminator.
            LD (CHAD),DE                ; Step CHAD past the name and any '$' or '(' that followed it
            LD A,C
            AND TLARRAY
            JP NZ,STARYLK               ; Either array bit set: use the string/array list

            LD A,(HL)                   ; FLAGS
            ADD A,A
            JP P,STARYLK                ; FFLAGNUM clear (now bit 7 after the shift): a string, so same list

            LD A,C
            LD (TLBYTE),A               ; Record the wanted type/length for the error handler to print
            RET NC                      ; FFLAGRUN was clear, so this is a syntax check. NZ says "found", which is
                                        ; what the caller needs to carry on checking types.


; =====================================================================================================================
; NUMLOOK -- search the numeric variable chains
; =====================================================================================================================
;
; Entry:  FIRLET holds the name, upper case letters folded and spaces removed
;         C = the type/length byte being looked for
; Exit:   NZ  Found. HL -> the 5-byte value, IX-1 -> the type/length byte in the variables area,
;             C = the type/length byte from the variables area, DE = the displacement that reached it.
;         Z   Not found. HL -> the &FFFF that terminates this letter's chain, C = the wanted type/length byte.
;
; The comparison deliberately ignores TLFORVAR, so "FOR i" and a plain "i" are the same variable.
; ---------------------------------------------------------------------------------------------------------------------

NUMLOOK:    LD A,(FIRLET)
            SUB "a"                     ; Fold the initial letter to a chain index 0-25
            ADD A,A                      ; Two bytes per root
            LD E,A
            LD D,0
            CALL ADDRNV                 ; HL -> the chain roots, with their page mapped
            ADD HL,DE                   ; HL -> this letter's root
            DB SKIP1CP                  ; Skip the POP on the way in

NVMOLP:     POP HL                      ; A name match failed part way: recover the pointer to this link

NVMLP:      LD A,C                      ; Wanted type/length
            LD E,(HL)
            INC HL                      ; A link of &FFFF means the chain has ended; the resulting carry out of the
            LD D,(HL)                   ; ADD is what NVSPOV tests for.
            ADD HL,DE                   ; Follow the relative link to the next record
            JR C,NVSPOV                 ; Either the end of the chain, or a genuine page overflow

            BIT 6,H
            JR NZ,NVSINCP               ; Keep the pointer inside the &8000-&BFFF window

NVSIEN:     XOR (HL)
            AND &BF                     ; Compare type and name length, ignoring TLFORVAR (bit 6)
            INC HL                      ; -> link low byte
            JR NZ,NVMLP                 ; No match: 84T per chain step

            LD A,C
            AND TLNAMELEN               ; Length of the remaining name characters
            PUSH HL                     ; Remember this link in case the name comparison fails
            INC HL
            INC HL                      ; Step over the link to the second name letter
            JR Z,NVSFND                 ; Single-letter name: the type/length byte already proved the match

            LD B,A
            LD IX,FIRLET+1              ; Compare against the buffered name from its second letter

NVMTCHLP:   LD A,(IX+0)
            CP (HL)
            JR NZ,NVMOLP                ; Mismatch: resume the chain from the saved link

            INC IX
            INC HL
            DJNZ NVMTCHLP               ; HL ends pointing at the value

NVSFND:     POP IX                      ; IX -> the link, so IX-1 is the type/length byte
            LD C,(IX-1)                 ; Report the stored type, which may differ in its FOR bit

NZST:       INC A                       ; Force NZ = "found"
            RET                         ; The previous record's link is at IX-DE-1


; ---------------------------------------------------------------------------------------------------------------------
; NVSPOV -- the link addition carried
;
; Either the chain has ended (a link of &FFFF, so D incremented to zero) or the area genuinely spans a page boundary.
; ---------------------------------------------------------------------------------------------------------------------

NVSPOV:     INC D
            RET Z                       ; Chain terminator: Z = not found, HL has stepped back to the link low byte

            CALL PGOVERF                ; Real overflow: correct the page and the address
            CP A                        ; Force Z so the call below is not made

NVSINCP:    CALL NZ,INCURPAGE           ; Address crossed into section D: advance one page and pull it back

            LD A,C
            JR NVSIEN


; ---------------------------------------------------------------------------------------------------------------------
; LKBSV -- look up a variable whose name is held on the BASIC stack
;
; Used by the PROC teardown code, which recorded the names it must restore rather than their addresses (the addresses
; move as locals are deleted).
;
; Entry:  HL -> the name on the BASIC stack, A = its type/length byte
; Exit:   As STARYLK2. BSTKEND is advanced past the name.
; ---------------------------------------------------------------------------------------------------------------------

LKBSV:      LD DE,FIRLET
            LD B,A
            AND &0F
            LD C,A
            LD A,B
            LD B,0                      ; BC = name length
            LDIR                        ; Copy the stacked name into the search buffer
            LD (BSTKEND),HL             ; The stack entry has now been consumed
            AND &6F                     ; Clear TLHIDDEN, so the visible local is found rather than a hidden global,
                                        ; and force bit 4 low
            JR STARYLK2


; =====================================================================================================================
; STARYLK -- search the string and array list
; =====================================================================================================================
;
; Entry:  FIRLET holds the name
;         C = type/length byte: bit 6 set for a string array or sliced string, bit 5 for a numeric array, both clear
;             for a simple string
; Exit:   NZ  Found. HL -> the length-in-pages byte, DE -> the type/length byte, C = the stored type/length,
;             STRLOCN = address of the record.
;         Z   Not found. C = the wanted type/length, STRLOCN and HL' point at the VARSTERM stopper.
; Uses:   All registers, including the alternate set.
; ---------------------------------------------------------------------------------------------------------------------

STARYLK:    INC C                       ; Names here are stored with their true length, not length-1
            LD A,C
            LD (TLBYTE),A
            AND TLNAMELEN
            CP MAXNAMELEN+1
            JP NC,INVVARNM              ; Strings and arrays are limited to 10 characters

            LD A,(HL)                   ; FLAGS
            RLA
            JR NC,NZST                  ; Syntax check: report "found". A cannot have held &FF, so NZ is guaranteed.

            LD A,C

; ---------------------------------------------------------------------------------------------------------------------
; STARYLK2 -- search entry point taken directly by PROC parameter processing, with A = the wanted type/length byte
; ---------------------------------------------------------------------------------------------------------------------

STARYLK2:   EXX
            LD C,A                      ; C' = wanted type/length
            LD B,TLNAMELEN              ; B' = name length mask
            LD E,&BF                    ; E' = mask ignoring TLSTRARRAY, so a$ also matches a 1-D string array
            EXX

            CALL ADDRSAV                ; HL -> the first record, with its page mapped
            IN A,(URPORT)               ; Track the page by hand as the scan crosses 16K boundaries

LKSTRLP:    LD DE,FIRLET
            OUT (URPORT),A              ; No effect on the first pass, and on most later ones
            LD (STRLOCN),HL             ; Remember where this record starts
            LD A,(HL)                   ; Type and name length
            EXX

            LD H,A                      ; Keep the stored byte
            XOR C                        ; Compare with the wanted one
            AND E                        ; ... ignoring bit 6, so simple and array strings match each other
            JR NZ,TLNOMTCH

            LD A,H
            AND B                       ; Isolate the name length, which both now agree on
            EXX

            LD B,A
            INC HL
            LD A,(DE)                   ; First letter of the wanted name
            CP (HL)
            JR NZ,FLNOMTCH              ; Cheap rejection before comparing the whole name

            JR DCNMLN

STMTCHLP:   INC HL
            INC DE
            LD A,(DE)
            CP (HL)
            JR NZ,FLNOMTCH

DCNMLN:     DJNZ STMTCHLP               ; B is 1 to 10

            LD HL,(STRLOCN)
            LD C,(HL)                   ; Report the type/length byte as stored
            EX DE,HL
            LD HL,STRHDRSIZE-2
            DEC L                       ; = 11, and leaves NZ for "found"
            ADD HL,DE                   ; HL -> length in pages, DE -> the type/length byte
            RET


; ---------------------------------------------------------------------------------------------------------------------
; TLNOMTCH / FLNOMTCH -- step over the current record
;
; TLNOMTCH is entered with the stored type byte in H (alternate set active); FLNOMTCH when only the name differed.
; ---------------------------------------------------------------------------------------------------------------------

TLNOMTCH:   INC H                       ; A stored byte of &FF is the list terminator
            RET Z                       ; Z = not found, C = the wanted type/length

            EXX

FLNOMTCH:   LD HL,(STRLOCN)
            LD BC,STRHDRSIZE-3
            ADD HL,BC                   ; -> length in pages
            IN A,(URPORT)
            ADD A,(HL)                  ; Add the whole-page part of the length to the page number
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            INC HL                      ; -> the data
            ADD HL,BC                   ; Skip it: BC is 0-&3FFF so this can carry at most once
            JR C,LKSTRPO                ; Rare: the record started near the top of section C and the length is
                                        ; close to 16K
            BIT 6,H
            JR Z,LKSTRLP                ; Still inside &8000-&BFFF

            RES 6,H                     ; Wrapped into section D: subtract 16K and count a page

LKSI:       INC A
            JR LKSTRLP

LKSTRPO:    INC A                       ; Overflowed past &FFFF into 0000-&3FFF, which is two pages on
            SET 7,H
            JR LKSI


; =====================================================================================================================
; NAMTOBUF -- copy and classify a variable name
; =====================================================================================================================
;
; Entry:  HL -> the first character, which is also in A
; Exit:   DE -> the character after the name (and after any '$' or '(')
;         HL =  the address of FLAGS
;         C  =  bits 4-0 name length minus one; bit 6 set for a string array; bit 5 set for a numeric array
;         FLAGS bit 6 (FFLAGNUM) set for a numeric name, clear for a string
;         FIRLET onwards holds the name with spaces removed and letters folded to lower case
; Uses:   AF, BC, DE, HL
;
; Names may contain letters, digits, underscores and embedded spaces; the spaces are dropped, so "price of bread" and
; "priceofbread" are the same variable. Numerics may run to 32 characters. Strings and arrays are limited to
; MAXNAMELEN, but that is enforced later by STARYLK, once the type is known.
; ---------------------------------------------------------------------------------------------------------------------

NAMTOBUF:   LD B,TLNAMELEN+1            ; 32 -- the longest name, excluding the first character
            LD DE,FIRLET                ; The buffer lives in the system page, always mapped
            CALL GETALPH                ; A name must begin with a letter
            OR &20                      ; Fold to lower case
            LD (DE),A                   ; Store the first letter

NMTBL:      INC HL
            LD A,(HL)
            CP " "
            JR Z,NMTBL                  ; Spaces inside a name are not significant

            CALL ALPHANUM
            JR C,NMTB2                  ; A letter or digit continues the name

            CP "_"
            JR NZ,NAMEND                ; Anything else ends it

            JR NMTB3                    ; Underscores are kept as typed

NMTB2:      OR &20                      ; Fold letters to lower case; digits are unaffected

NMTB3:      INC DE
            LD (DE),A
            DJNZ NMTBL                  ; Fall through only when the name is too long

            LD (CHAD),HL                ; Point CHAD at the offending character so the '?' marker lands on it

INVVARNM:   RST &08
            DB ERR_BADVARNAME           ; Normally caught during the syntax check


; ---------------------------------------------------------------------------------------------------------------------
; NAMEND -- the name proper has ended; a type character may follow
; ---------------------------------------------------------------------------------------------------------------------

NAMEND:     EX DE,HL
            LD HL,FLAGS
            LD A,TLNAMELEN+1
            SUB B
            LD C,A                      ; C = name length minus one, 0-31
            LD A,(DE)
            CP "$"
            JR NZ,NMEN2                 ; No '$', so this is a numeric name

            RES 6,(HL)                  ; FFLAGNUM clear: a string
            INC DE
            LD A,(DE)
            CP "("
            RET NZ                      ; A simple string

            INC DE
            SET 6,C                     ; TLSTRARRAY: a string array or a sliced string
            RET

NMEN2:      SET 6,(HL)                  ; FFLAGNUM set: numeric
            CP "("
            RET NZ                      ; A simple number

            INC DE
            SET 5,C                     ; TLNUMARRAY: a numeric array
            RET

; Unreachable: superseded by the length calculation now performed at NAMEND above.
            LD A,TLNAMELEN+1
            SUB B
            LD C,A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LVFLAGS -- look up a variable and report its type in the flags
;
; A convenience wrapper used wherever the caller wants to branch on type and existence together.
;
; Exit:   Z' set if the variable was not found (test with EX AF,AF')
;         M   numeric, P string
;         CY  running rather than syntax-checking
; ---------------------------------------------------------------------------------------------------------------------

LVFLAGS:    CALL LOOKVARS
            EX AF,AF'                   ; Preserve the found/not-found result
            LD A,(FLAGS)
            ADD A,A
            RET
