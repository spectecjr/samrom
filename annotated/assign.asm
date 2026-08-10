; =====================================================================================================================
; ASSIGN.ASM -- Assignment, array indexing, string slicing and DIM
; =====================================================================================================================
;
; Everything that writes to a variable, and everything that works out where in a variable to write.
;
; THE DESTINATION DESCRIPTOR
; --------------------------
; Before any assignment, SYNTAX1 (or SYNTAX4 for a FOR variable) looks the name up and records what it found:
;
;     DEST/DESTP   the value's address -- or, for a variable that does not exist yet, the place where its record
;                  should be linked in
;     STRLEN       the destination length for an existing string, or the type byte otherwise
;     FLAGX bit 0  set when the variable is new
;     DFTFB        zero when an existing numeric holds "minus zero", which DEFAULT treats as not existing
;
; ASSIGN then acts on that description. Numerics either overwrite five bytes or create a new chain entry; strings
; are more involved, because their length can change.
;
; STRINGS OF FIXED AND VARIABLE LENGTH
; ------------------------------------
; A slice, or an element of a string array, has a fixed size: the value is copied in, truncated or space-padded to
; fit. A simple string can change size, so assignment creates a whole new record at the end of the string area and
; then deletes the old one. Doing it in that order is what makes LET a$ = a$ + "x" work.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; VALFET1 / VALFET2 -- evaluate a value and assign it
;
; Entry:  VALFET1 with the destination already assessed; VALFET2 with the expected type in A.
; Exit:   The value is stored, or the types did not match and ERR_NONSENSE was raised.
; ---------------------------------------------------------------------------------------------------------------------

VALFET1:    LD A,(FLAGS)

VALFET2:    PUSH AF
            CALL SCANNING
            LD A,(FLAGS)
            LD D,A
            POP AF
            XOR D
            AND FFLAGNUM
            JP NZ,NONSENSE              ; A string cannot be assigned to a number, or the reverse

            LD A,D
            RLA
            RET NC                      ; Syntax check only


; ---------------------------------------------------------------------------------------------------------------------
; ASSIGN -- store the calculator stack top into the described destination
; ---------------------------------------------------------------------------------------------------------------------

ASSIGN:     CALL ASSISR
            JP SELCHADP                 ; The store may have changed the page


; ---------------------------------------------------------------------------------------------------------------------
; CGXRG -- halve or double the X range pseudo-variable
;
; Called when FATPIX or MODE changes the pixel width, so that graphics coordinates keep referring to the same place.
;
; Entry:  HL -> the XRG value, A = 0 to double or non-zero to halve.
; ---------------------------------------------------------------------------------------------------------------------

CGXRG:      PUSH HL
            CALL HLTOFPCS
            LD B,A

            DB CALC                     ; XRG
            DB ONELIT
            DB 2                        ; XRG, 2
            DB STKBREG                  ; XRG, 2, flag
            DB JPFALSE                  ; Zero means double, so jump to the multiply
            DB 4

            DB DIVN                     ; XRG / 2
            DB JUMP
            DB 2

            DB MULT                     ; XRG * 2
            DB EXIT

            POP DE
            JR ASENV                    ; Drop the result and copy it back into the variable


; ---------------------------------------------------------------------------------------------------------------------
; CRTVAR35 / CRTVAR4 -- create a numeric variable from a name already in the buffer
;
; Entry:  CRTVAR35 from PROC parameter processing; CRTVAR4 (also used by MERGE and SETUPVARS) with A = the type byte.
;         The value is on the calculator stack and the name is at FIRLET.
; ---------------------------------------------------------------------------------------------------------------------

CRTVAR35:   LD A,(TLBYTE)

CRTVAR4:    LD C,A
            LD HL,FLAGS
            SET 6,(HL)                  ; FFLAGNUM

            CALL NUMLOOK
            CALL SYN14C                 ; Build the destination descriptor from the search result


; ---------------------------------------------------------------------------------------------------------------------
; ASSISR -- the assignment proper
;
; Entry:  DEST, DESTP, STRLEN and FLAGX describe the destination; the value is on the calculator stack.
; ---------------------------------------------------------------------------------------------------------------------

ASSISR:     CALL ADDRDEST               ; For a new numeric this is the previous link; for an existing one the
                                        ; value; for a new string the area terminator; for an existing string its
                                        ; first character
            LD A,(FLAGS)
            ADD A,A
            LD A,(FLAGX)
            JP P,ASSTR                  ; A string

            EX DE,HL
            RRA
            JR C,ASNN                   ; FFLXNEWVAR: the numeric does not exist yet


; ---------------------------------------------------------------------------------------------------------------------
; ASENV -- overwrite an existing numeric
;
; Entry:  DE -> the five bytes in the variables area.
; ---------------------------------------------------------------------------------------------------------------------

ASENV:      CALL FDELETE                ; Drop the value, leaving HL pointing at it

LDI5:       LD BC,NUMVALSIZE
            LDIR
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ASNN -- create a new numeric variable
;
; Entry:  DE -> the low byte of the last link in this letter's chain.
; Notes:  The new record goes at NUMEND, so the link is set to the displacement from itself to there. The link
;         cannot be written until the space is known to exist, hence the two-stage approach.
; ---------------------------------------------------------------------------------------------------------------------

ASNN:       LD A,(DESTP)
            AND LMPRPAGE
            LD C,A
            LD HL,(NUMEND)
            LD A,(NUMENDP)
            SUB C
            JR Z,ANSP                   ; The usual case: both are in the same page

            LD BC,&4000

ANSPL:      ADD HL,BC                   ; Bring NUMEND into the same frame of reference as the link, so the
            DEC A                       ; subtraction below is meaningful. Wrapping past 64K does not matter,
            JR NZ,ANSPL                 ; since a chain never spans that much.

            AND A

ANSP:       SBC HL,DE                   ; Displacement from the link's low byte to the first free byte
            DEC HL                      ; ... measured from its high byte, as the link format requires
            PUSH HL                     ; Keep it: the link cannot be written until the space is secured

            LD A,(NUMENDP)
            LD C,A
            LD HL,(SAVARS)
            LD A,(SAVARSP)
            CP C                        ; The string area is always the higher of the two
            JR Z,ABSP                   ; Unusually, both are in the same page

            SET 6,H                     ; One page apart, so add 16K to compare them

ABSP:       LD BC,(NUMEND)
            SBC HL,BC
            EX DE,HL                    ; DE = the free gap, HL = the link address
            LD A,D
            AND A
            JR NZ,ANOK                  ; At least 256 bytes free

            LD A,E
            CP 60
            JR NC,ANOK                  ; At least 60, which is the largest a numeric record can be

            CALL ADDRSAV                ; Not enough: open more space before the string area
            CALL DECPTR
            LD BC,&0200
            CALL MAKEROOM
            CALL ADDRDEST               ; The move may have shifted the link, so fetch it again

; --- ANOK: there is room, so commit ---

ANOK:       POP DE
            LD (HL),E                   ; Point the previous last variable of this letter at the new one
            INC HL
            LD (HL),D
            CALL ADDRNE                 ; HL -> NUMEND, where the record goes
            LD A,(TLBYTE+33)
            LD (HL),A                   ; Type and name length
            INC HL
            LD B,&FF
            LD (HL),B
            INC HL
            LD (HL),B                   ; A link of &FFFF: this is now the last of its letter
            INC HL
            EX DE,HL
            LD HL,FIRLET+34             ; The second letter of the name
            AND TLNAMELEN
            JR Z,ASNCL                  ; A one-letter name

            LD C,A
            INC B                       ; BC = the rest of the name
            LDIR

ASNCL:      CALL ASENV                  ; Copy the value in


; ---------------------------------------------------------------------------------------------------------------------
; NELOAD -- set NUMEND past a newly created variable
; ---------------------------------------------------------------------------------------------------------------------

NELOAD:     LD (NUMEND),DE
            BIT 6,D
            RET Z                       ; Still inside the window

            RES 6,D                     ; Crossed 16K, so advance the page
            LD A,(NUMENDP)
            INC A
            LD (NUMENDP),A
            JR NELOAD


; =====================================================================================================================
; ASSTR -- assign to a string
; =====================================================================================================================

ASSTR:      RRA
            JP C,ASNST                  ; FFLXNEWVAR: create it

; --- An existing string ---

            LD BC,(STRLEN)              ; The destination length
            LD A,(DESTP)
            RLA
            JR C,ASDEL                  ; Bit 7 set: a simple string, so replace the whole record

; --- A slice or array element: fixed size, so copy in place ---

            LD A,B
            OR C
            RET Z                       ; A zero-length destination, as in LET a$(4 TO 3) = "test"

            PUSH HL                     ; The destination
            PUSH BC                     ; Its size
            CALL STKFETCH               ; ADE = the source, BC = its length
            POP HL                      ; The destination size
            SBC HL,BC                   ; NC here
            JR NC,AES1                  ; The source is no longer than the destination

            ADD HL,BC                   ; It is longer, so truncate it
            LD B,H
            LD C,L
            LD HL,0                     ; ... and no padding is needed

AES1:       EX (SP),HL                  ; Stack the padding count, recover the destination
            EX DE,HL                    ; DE = destination, HL = source
            EX AF,AF'
            CALL SPLITBC
            IN A,(251)
            LD C,A                      ; CDE = the destination
            EX AF,AF'                   ; AHL = the source
            CALL FARLDIR
            POP BC                      ; The padding count
            LD A,B
            OR C
            RET Z

; --- Space-pad the remainder of the destination ---

            LD A,(TEMPB2)
            CALL TSURPG                 ; The page the copy finished in
            LD HL,(TEMPW1)              ; ... and the address just past it
            XOR A
            CP C                        ; NC only when C is zero
            ADC A,B                     ; A = B, or B+1 when C is non-zero: whole passes of the loop below
            LD B,C
            LD C,A
            LD A," "

ASPSL:      LD (HL),A
            INC HL
            DJNZ ASPSL

            DEC C
            RET Z

            CALL CHKHL                  ; Keep the pointer inside the window
            JR ASPSL


; ---------------------------------------------------------------------------------------------------------------------
; RECORD -- RECORD TO a$  |  RECORD STOP
;
; Arms stream 16 so that printing to it appends to the named string, and makes graphics commands append BLITZ
; records to it as well.
; ---------------------------------------------------------------------------------------------------------------------

RECORD:     CP TOK_STOP
            JR NZ,RECORD2

            XOR A
            LD (GRARF),A                ; Graphics recording off
            RST &20
            RET

RECORD2:    CP TOTOK
            JR NZ,RCNONS

            RST &20
            CALL LVFLAGS
            JP M,NONSENSE               ; A numeric target makes no sense

            JR C,RECORD3                ; Running

            BIT 6,C
            RET Z                       ; Syntax check: a simple string is acceptable

RCNONS:     RST &08
            DB ERR_NONSENSE

RECORD3:    EX AF,AF'
            CALL NZ,ASDEL2              ; Delete any existing variable of that name

            LD DE,STRM16NM
            CALL SCOPN1                 ; Record the name where the stream 16 driver can find it.
                                        ; This may copy 12 bytes and touch GRARF, which is harmless since GRARF is
                                        ; set immediately afterwards.
            LD A,D
            LD (GRARF),A                ; Graphics recording on
            CALL SCOPNM                 ; Exits with BC = 0
            JR ASNS1                    ; Create the variable as a null string


; ---------------------------------------------------------------------------------------------------------------------
; ASDEL -- assign a simple string, then delete the previous version
;
; The new value is built first, so that LET a$ = a$ and LET a$ = a$ + "x" both work.
; ---------------------------------------------------------------------------------------------------------------------

ASDEL:      CALL ASNST                  ; Create the new record at the end of the string area
            CALL ADDRDEST               ; HL -> the text of the old one
            LD DE,-STRHDRSIZE
            ADD HL,DE                   ; -> its type byte
            CALL CHKPTR
            JR ASDEL3


; ---------------------------------------------------------------------------------------------------------------------
; ASDL1 / ASDEL2 / ASDEL3 -- delete a string or array record
;
; Entry:  ASDL1 with A = the page; ASDEL2 with STRLOCN pointing at it and its page mapped;
;         ASDEL3 with HL pointing at it.
; ---------------------------------------------------------------------------------------------------------------------

ASDL1:      CALL SELURPG

ASDEL2:     LD HL,(STRLOCN)

ASDEL3:     PUSH HL
            LD BC,STRHDRSIZE-3
            ADD HL,BC                   ; -> the length in pages
            CALL ADD14
            LD B,H
            LD C,L
            POP HL
            JP RECL2BIG                 ; Remove the data and its 14-byte header together


; ---------------------------------------------------------------------------------------------------------------------
; ADD14 -- read a record's data length and add the header size
;
; Entry:  HL -> the length in pages.
; Exit:   AHL = the total record length.
; ---------------------------------------------------------------------------------------------------------------------

ADD14:      LD A,(HL)
            INC HL
            LD E,(HL)
            INC HL
            LD D,(HL)
            EX DE,HL                    ; AHL = the data length
            LD BC,STRHDRSIZE
            ADD HL,BC
            BIT 6,H
            RET Z

            INC A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; ASNST -- create a new string record at the end of the string area
;
; Entry:  The value is on the calculator stack; the name is at TLBYTE+33.
; Notes:  A source that lies above WKEND -- a temporary in workspace -- must not be auto-adjusted when MAKEROOM
;         moves memory, because it sits above the change point and would be adjusted wrongly. Such a source is
;         parked in FIRST/LAST instead of XPTR.
; ---------------------------------------------------------------------------------------------------------------------

ASNST:      CALL STKFETCH               ; A = page, DE = start, BC = length

            AND LMPRPAGE
            LD H,A
            LD A,(WKENDP)
            LD L,A
            LD A,H
            CP L
            JR C,ASNS1                  ; The source page is below WKEND's

            JR NZ,ASNS0                 ; ... or above it

            LD HL,(WKEND)
            SBC HL,DE
            JR NC,ASNS1                 ; Same page, and the source is at or below WKEND

ASNS0:      LD (FIRST),DE               ; Above WKEND: remember it somewhere that is not auto-adjusted
            LD (LAST),A
            LD A,&FF                    ; Signal that XPTR is not in use

; --- ASNS1: also entered by RECORD, to create a null string ---

ASNS1:      PUSH AF
            PUSH BC                     ; The text length
            LD (XPTR),DE                ; Park the source where MAKEROOM will adjust it if it moves
            LD (XPTRP),A
            LD A,STRHDRSIZE             ; Type byte, 10 name characters and the 3-byte length
            ADD A,C
            LD C,A
            JR NC,ASNS2

            INC B
            JP Z,STLERR                 ; The whole record must fit in 65535 bytes

ASNS2:      LD A,B
            RLCA
            RLCA
            AND &03                     ; A = whole 16K pages, BC = the remainder
            CALL SAROOM                 ; Open the space and write the type byte and name
            POP BC                      ; The text length
            CALL MBC                    ; Write the length into the record
            IN A,(251)
            LD C,A                      ; CDE = the destination
            POP AF
            INC A
            LD A,(XPTRP)
            LD HL,(XPTR)
            JR NZ,ASNS3                 ; XPTR was in use, so it holds the adjusted source

            LD A,(LAST)                 ; Otherwise the source was parked in FIRST/LAST
            LD HL,(FIRST)

ASNS3:      LD (XPTR+1),A               ; The page has bit 7 clear, which cancels the '?' marker
            JP FARLDIR


; =====================================================================================================================
; Assessing a destination
; =====================================================================================================================

; ---------------------------------------------------------------------------------------------------------------------
; SYNTAX4 -- assess a FOR control variable
;
; A FOR variable must be a simple numeric. Any ordinary variables of the same name are marked unused, so that the
; FOR record replaces them rather than shadowing them.
; ---------------------------------------------------------------------------------------------------------------------

SYNTAX4:    CALL LVFLAGS
            JP P,NONSENSE               ; A string

            BIT 5,C
            JP NZ,NONSENSE              ; A numeric array

            JR NC,SYNT41                ; Syntax check

            EX AF,AF'

SYN42:      JR Z,SYN14C                 ; It does not exist yet

            BIT 6,C                     ; TLFORVAR: it is already a FOR variable, so reuse it
            JR NZ,SYN14C

            PUSH IX
            POP HL                      ; -> the link
            SET 5,(IX-1)                ; Mark the ordinary variable unused
            CALL NVMLP                  ; Keep searching the chain
            JR SYN42                    ; ... and mark every copy

SYNT41:     EX AF,AF'

            JR SYN14C


; ---------------------------------------------------------------------------------------------------------------------
; SSYNTAX1 / SYNTAX1 -- assess a destination for LET, READ or INPUT
; ---------------------------------------------------------------------------------------------------------------------

SSYNTAX1:   RST &20

SYNTAX1:    CALL LOOKVARS


; ---------------------------------------------------------------------------------------------------------------------
; SYN14C / SYN1PP -- build the destination descriptor from a search result
;
; Entry:  DE -> the value if found; C = the type byte, from the variables area if found or the wanted one if not.
; Exit:   DEST, DESTP, STRLEN, FLAGX and DFTFB all set.
; ---------------------------------------------------------------------------------------------------------------------

SYN14C:     EX DE,HL

; --- SYN1PP: entered from PROC parameter processing ---

SYN1PP:     LD HL,FLAGX
            LD (HL),0                   ; Assume the variable exists
            JR NZ,TSYNT12               ; It does, or this is a syntax check

            INC (HL)                    ; FFLXNEWVAR

            LD A,C
            AND TLARRAY
            JR Z,TSYNT14                ; A simple string or number: DESTP bit 7 stays clear

VNFERR:     RST &08                     ; An undimensioned array, or a slice of a string that does not exist
            DB ERR_NOTFOUND

; --- The variable exists, or this is a syntax check ---

TSYNT12:    LD A,(FLAGS)
            ADD A,A
            JP P,TSYNT13                ; A string

            BIT 5,C
            JR Z,TSYNT14                ; A simple number

TSYNT13:    CALL STKVAR                 ; Index the array or stack the string details
            LD A,(FLAGS)
            ADD A,A
            JP M,TSYNT15                ; A numeric array element: HL -> it, its page mapped

            CALL C,STKFETCH             ; A string: DE = start, BC = length, A = page with bit 7 set when the old
            EX DE,HL                    ; copy must be deleted, as in LET a$ = "ss"
            JR TSYN16

TSYNT14:    EX DE,HL

; --- Record the result. For numerics and new variables STRLEN holds the type byte and junk; for existing strings
; --- and arrays it holds the length.

TSYNT15:    IN A,(251)
            AND LMPRPAGE

TSYN16:     LD (STRLEN),BC
            LD (DEST),HL
            LD (DESTP),A
            LD B,(HL)
            INC HL
            LD A,(HL)
            INC A
            OR B
            INC HL
            OR (HL)
            INC HL
            OR (HL)                     ; Zero only when the value is 00 FF 00 00, i.e. minus zero
            LD (DFTFB),A                ; Meaningless for a variable that does not exist


; ---------------------------------------------------------------------------------------------------------------------
; SCOPNM / SCOPN1 / SCOPN2 -- copy the name to a second buffer
;
; The evaluator will reuse TLBYTE and FIRLET, so the name of the destination is kept at TLBYTE+33.
; ---------------------------------------------------------------------------------------------------------------------

SCOPNM:     LD DE,TLBYTE+33

; --- SCOPN1: entered by RECORD TO, which copies to STRM16NM instead ---

SCOPN1:     LD HL,TLBYTE
            LD A,(HL)
            AND TLNAMELEN               ; Name length minus one for a numeric, the true length otherwise
            ADD A,2                     ; Allow for the type byte and, for a numeric, the first letter
            LD C,A

; --- SCOPN2: entered by the LENGTH function ---

SCOPN2:     LD B,0
            LDIR
            JP SELCHADP


; =====================================================================================================================
; STKVAR -- index an array, or stack a string's parameters
; =====================================================================================================================
;
; Entry:  DE -> the length in pages if running, C = the type byte, CY if running.
;         CHAD points past the '$' or '(' unless an error follows.
; Exit:   For a numeric array, HL -> the element. For a string, its parameters are on the calculator stack.
; ---------------------------------------------------------------------------------------------------------------------

STKVAR:     EX DE,HL

STKVAR2:    JR C,SVRUNT                 ; Running

; --- Syntax check: verify the subscript or slicer syntax only ---

            BIT 6,C
            JR NZ,SVSSL                 ; A string array or a sliced string

            BIT 5,C
            RET Z                       ; A simple unsliced string: nothing to check

            DB SKIP1CP                  ; A numeric array: fall into the subscript check

SVDSL:      RST &20

; --- SVDSK: check "n,n,...,n)". Also called by DIM. ---

SVDSK:      CALL EXPT1NUM
            CP ","
            JR Z,SVDSL

SVIBH:      JP INSISCBRK


; ---------------------------------------------------------------------------------------------------------------------
; SVSSL -- check string array or slicer syntax
;
; Accepts "()", "(n,x TO y)", "(n,n, TO y)", "(n,n,y TO)" and the like.
; ---------------------------------------------------------------------------------------------------------------------

SVSSL:      RST &18
            CP ")"
            JR Z,SVSL3                  ; "()" is allowed

            DB SKIP1CP

SVSSLP:     RST &20

            CP TOTOK
            JR Z,SVSL2                  ; A slicer with no first number

            CALL EXPT1NUM
            CP ","
            JR Z,SVSSLP

            CP TOTOK
            JR Z,SVSL2

            CALL INSISCBRK
            JR SLPXHP

SVSL2:      RST &20                     ; Skip TO
            CP ")"
            JR Z,SVSL3                  ; "x TO )"

            CALL EX1NUMCB               ; "x TO n)"
            DB SKIP1CP

SVSL3:      RST &20

SLPXHP:     JP SLLPEX                   ; EXPT1NUM left the type as numeric; restore "string"


; =====================================================================================================================
; SVRUNT -- run-time array indexing and string parameter stacking
; =====================================================================================================================

SVRUNT:     LD A,C
            AND TLARRAY
            JR NZ,SVARRAYS

; --- A simple string: convert the stored pages-plus-remainder length to a plain 16-bit one ---

            LD A,(HL)                   ; Pages, 0-3
            INC HL
            LD C,(HL)
            INC HL
            RRCA
            RRCA                        ; The page count becomes the top two bits
            OR (HL)
            LD B,A                      ; BC = the length
            LD D,&80                    ; Bit 7: delete the old copy after assignment

SVSIMPLE:   EX DE,HL
            INC DE                      ; -> the text
            IN A,(251)
            BIT 6,D
            JR Z,SVSS2                  ; The text is in the window

            RES 6,D                     ; A string starting near &BFFF leaves the pointer in section D
            INC A

SVSS2:      AND LMPRPAGE
            OR H                        ; Bit 7 set for a simple string (delete the old copy), clear for a
                                        ; one-dimensional string array element (overwrite in place)
            CALL STKSTORE               ; FFLAGNUM is already correct
            CALL SELCHADP
            LD A,(TLBYTE)
            BIT 6,A
            RET Z                       ; No bracket followed the name, so no slicing

            JP SLCL2


; ---------------------------------------------------------------------------------------------------------------------
; SVARRAYS -- index an array
;
; The element offset is built up as total = (...(s1 * d2 + s2) * d3 + ...) + sn, computed on the calculator stack,
; then multiplied by the element size and added to the data start.
; ---------------------------------------------------------------------------------------------------------------------

SVARRAYS:   INC HL
            INC HL
            INC HL
            LD B,(HL)                   ; The number of dimensions
            BIT 5,C
            JR NZ,SVCDIS                ; A numeric array

            DJNZ SVCKS                  ; A multi-dimensional string array

            LD D,B                      ; One dimension: D = 0, so bit 7 stays clear meaning "overwrite"
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)                   ; BC = the single dimension's length
            JR SVSIMPLE                 ; Treat it exactly like a simple string

SVCKS:      LD A,(TLBYTE)               ; A multi-dimensional string array must be referred to with a slicer
            AND TLSTRARRAY
            JR Z,SWERHP

SVCDIS:     IN A,(URPORT)
            PUSH AF                     ; The page holding the dimension list
            PUSH BC                     ; B = the dimension count, excluding the last for a string array
            INC HL
            PUSH HL
            XOR A
            CALL STACKA                 ; The running total starts at zero
            POP HL
            POP BC

SVLOOP:     POP AF
            PUSH AF
            OUT (URPORT),A              ; Map the dimension list
            PUSH BC
            LD C,(HL)
            INC HL
            LD B,(HL)                   ; BC = this dimension's size, the subscript limit
            INC HL
            PUSH HL
            PUSH BC
            CALL SELCHADP               ; Map the program, to evaluate the subscript
            CALL STACKBC                ; Stack the dimension size
            POP BC
            CALL GETSUBS                ; The subscript, checked against the limit and decremented

SWERHP:     JP NC,SWER2                 ; Out of range

            CALL STACKHL

            DB CALC                     ; total, size, subscript
            DB SWOP13                   ; subscript, size, total
            DB MULT
            DB ADDN                     ; total * size + subscript
            DB EXIT

            POP DE                      ; The dimension list pointer
            POP BC                      ; The dimension counter
            RST &18
            DEC B
            JR Z,SVEXLP                 ; All dimensions done

            CP ","
            JR NZ,SWER2                 ; More dimensions require more subscripts

            RST &20
            EX DE,HL
            JR SVLOOP


; ---------------------------------------------------------------------------------------------------------------------
; SVEXLP -- all subscripts consumed; compute the element address
;
; Entry:  The array's page is on the stack, DE -> the data start.
; ---------------------------------------------------------------------------------------------------------------------

SVEXLP:     BIT 5,C
            JR NZ,SVNUMER

; --- A string array: the last dimension is the element length, and a slicer may follow ---

            POP AF
            OUT (URPORT),A
            EX DE,HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            INC HL
            EX DE,HL                    ; DE -> the data start
            PUSH BC                     ; The element length
            CALL SVSR                   ; AHL = the element's address
            POP BC
            EX DE,HL
            CALL STKST0                 ; Stack it; bit 7 clear means "do not erase the original"
            CALL SELCHADP
            RST &18
            CP ")"
            JR Z,SVDIM                  ; No slicer, as in a$(3)

            CP ","
            JR Z,SLCL                   ; A slicer follows, as in a$(3,2 TO 5)

SWER2:      RST &08
            DB ERR_SUBSCRIPT

SVDIM:      RST &20
            CP "("
            JR NZ,SLLPEX                ; Nothing more

SLCL:       RST &20                     ; Skip the '(' or ','

SLCL2:      CALL SLICING
            JR SVDIM

SLLPEX:     LD HL,FLAGS
            RES 6,(HL)                  ; FFLAGNUM clear: the result is a string
            RET


; --- A numeric array: five bytes per element ---

SVNUMER:    CP ")"
            JR NZ,SWER2

            RST &20
            LD BC,NUMVALSIZE
            POP AF                      ; The page
            CALL SVSR
            JP TSURPG


; ---------------------------------------------------------------------------------------------------------------------
; SVSR -- turn an element index into an address
;
; Entry:  BC = the element size, DE -> the data start, A = its page, the index on the calculator stack.
; Exit:   AHL = the element's address.
; ---------------------------------------------------------------------------------------------------------------------

SVSR:       PUSH AF
            PUSH DE
            CALL STACKBC

            DB CALC                     ; total, element size
            DB MULT                     ; the byte offset
            DB EXIT

            CALL UNSTLEN                ; AHL = it, in page form
            POP DE
            POP BC
            LD C,B                      ; CDE = the data start
            BIT 6,D
            JR Z,SVSR2

            INC C                       ; ADDAHLCDE ignores bit 6, so account for it here

SVSR2:      JP ADDAHLCDE


; =====================================================================================================================
; SLICING -- evaluate a string slicer
; =====================================================================================================================
;
; Forms: (), (n), (a TO b), (a TO), ( TO b). An empty result is produced for a reversed range such as (5 TO 2),
; but a genuinely out-of-range value is an error.
; ---------------------------------------------------------------------------------------------------------------------

SLICING:    CALL RUNFLG
            CALL C,STKFETCH             ; ADE = start, BC = length

            PUSH AF                     ; The page
            RST &18
            POP HL                      ; H = the page
            CP ")"
            JR Z,SLSTORE                ; "()" means the whole string

            LD (TEMPB2),A               ; Non-zero: no subscript error yet
            PUSH DE                     ; The string start
            PUSH HL                     ; H = its page
            LD DE,0                     ; The default first position
            CP TOTOK
            JR Z,SLSEC                  ; "( TO x)"

            CALL GETSUBS                ; The first number, checked against the length and decremented
            EX DE,HL
            RST &18
            CP TOTOK
            JR Z,SLSEC

            CP ")"

NONSH:      JR NZ,SWER2

            LD H,D                      ; "(n)" means a single character
            LD L,E
            JR SLDEF

SLSEC:      RST &20
            CP ")"
            LD H,B
            LD L,C
            DEC HL                      ; Default the second number to the last position
            JR Z,SLDEF                  ; "(x TO )" or "( TO )"

            PUSH DE
            CALL GETSUBS                ; The second number
            POP DE
            JR C,SLSE2                  ; In range, or a syntax check

            LD A,H
            OR L
            JR Z,SLND                   ; "(2 TO 0)" is an empty string, not an error

SLSE2:      PUSH HL
            RST &18
            POP HL
            CP ")"
            JR NZ,NONSH

SLDEF:      SBC HL,DE                   ; Second minus first; NC here
            LD BC,0                     ; A reversed range gives an empty string
            JR C,SLNUL

            LD A,(TEMPB2)
            AND A
            JP Z,SWER2                  ; A subscript really was out of range

            INC HL

SLND:       LD B,H
            LD C,L                      ; BC = the slice length

SLNUL:      POP AF
            POP HL                      ; AHL = the string start
            ADD HL,DE                   ; ... plus the first position
            CALL C,PGOA
            BIT 6,H
            JR Z,SLDF2

            RES 6,H
            INC A

SLDF2:      EX DE,HL                    ; ADE = the slice start, BC = its length
            LD H,A

SLSTORE:    LD A,(FLAGS)
            AND &BF
            LD (FLAGS),A                ; FFLAGNUM clear: a string
            RLA
            RET NC                      ; Syntax check

            LD A,H
            JP STKST0                   ; Stack it, with bit 7 clear: do not delete the original


; =====================================================================================================================
; DIM -- DIM name(d1,...,dn)
; =====================================================================================================================
;
; Deletes any existing variable of the same name, then builds a record whose data area holds the dimension count,
; the dimension sizes, and the elements, all cleared.
; ---------------------------------------------------------------------------------------------------------------------

DIM:        CALL LOOKVARS
            IN A,(URPORT)               ; The page of the existing variable, if there is one
            EX AF,AF'                   ; NZ if it was found
            PUSH BC
            CALL SCOPNM                 ; Copy the name where the evaluator cannot disturb it
            POP BC
            LD A,(TLBYTE)               ; The requested type, which may differ from what was found
            AND TLARRAY
            JP Z,NONSENSE               ; DIM needs a bracket

            CALL RUNFLG
            JR C,DIMRUN

            CALL SVDSK                  ; Syntax check: "n,n,...,n)"

DIM2:       CP ","
            RET NZ

            RST &20
            JR DIM                      ; DIM a(8),b(6,5),a$(2) and so on

DIMRUN:     EX AF,AF'
            PUSH BC
            CALL NZ,ASDL1               ; Delete the existing array

            CALL SELCHADP
            POP BC
            BIT 5,C
            LD BC,1                     ; String elements are one byte each
            JR Z,DIM4

            LD C,NUMVALSIZE             ; Numeric elements are five

DIM4:       CALL STACKBC                ; The running product; B is still zero, so it doubles as the dimension count
            DB SKIP1CP

DIMSZLP:    RST &20                     ; Skip the comma

            CALL GETSUBS                ; The dimension size, returned decremented
            INC HL
            PUSH HL                     ; Keep it on the machine stack, behind the counter
            PUSH BC
            CALL STACKHL

            DB CALC
            DB MULT                     ; 5 * d1 * d2 ..., or 1 * d1 ...
            DB EXIT

            POP BC
            INC B                       ; One more dimension
            RST &18
            CP ","
            JR Z,DIMSZLP

            CALL INSISCBRK

            PUSH BC                     ; B = the dimension count
            LD L,B
            LD H,0
            ADD HL,HL                   ; Two bytes per dimension size ...
            INC HL                      ; ... plus one for the count itself
            CALL STACKHL

            DB CALC                     ; element bytes, dimension info bytes
            DB SWOP                     ; info, elements
            DB DUP                      ; info, elements, elements
            DB SWOP13                   ; elements, elements, info
            DB ADDN                     ; elements, elements + info
            DB DUP
            DB ONELIT
            DB STRHDRSIZE
            DB ADDN                     ; elements, elements + info, elements + info + 14
            DB EXIT

            CALL UNSTLEN                ; ABC = the total record size
            CALL SAROOM                 ; Open it and write the type byte and name; DE -> just past the name
            PUSH DE
            CALL UNSTLEN                ; The size excluding the 14-byte header
            EX DE,HL
            POP HL
            LD (HL),A                   ; Pages
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D                   ; ... and the remainder
            INC HL
            POP AF
            LD (HL),A                   ; The dimension count
            LD E,A
            LD D,0
            ADD HL,DE
            ADD HL,DE                   ; -> the high byte of the last dimension size
            LD D,H
            LD E,L

DIMENTLP:   POP BC                      ; The sizes come off the stack in reverse order
            LD (HL),B
            DEC HL
            LD (HL),C
            DEC HL
            DEC A
            JR NZ,DIMENTLP

            PUSH DE
            CALL UNSTLEN                ; The element area size
            CALL AHLNORM                ; ... as a 19-bit value
            POP DE
            EX DE,HL
            INC HL                      ; -> the first byte to clear
            LD B,E                      ; B counts bytes within a 256-byte block
            LD E,D
            LD D,A                      ; DE counts the blocks
            LD A,B
            AND A
            JR Z,DIMNAC

            INC DE                      ; A partial final block, so one more pass. DE is never zero.

DIMNAC:     LD A,(TLBYTE+33)
            AND TLSTRARRAY
            LD C," "                    ; String arrays are cleared to spaces
            JR NZ,GARC

            LD C,A                      ; Numeric arrays to zero

GARC:       CALL CHKHL

DIMCLP:     LD (HL),C
            INC HL
            DJNZ DIMCLP

            DEC DE
            LD A,D
            OR E
            JR NZ,GARC

            CALL SELCHADP
            RST &18
            JP DIM2


; ---------------------------------------------------------------------------------------------------------------------
; SAROOM -- open a record at the end of the string area and write its name
;
; Entry:  A = pages, BC = the remainder of the total size.
; Exit:   DE -> just past the 11-byte type and name field.
; ---------------------------------------------------------------------------------------------------------------------

SAROOM:     PUSH AF
            CALL ADDRELND               ; The end of the string area is one below the edit line
            POP AF
            CALL MKRBIG
            EX DE,HL
            LD HL,TLBYTE+33
            LD BC,11                    ; The type byte and ten name characters
            LDIR
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GETSUBS -- evaluate a subscript
;
; Entry:  CHAD at the expression, BC = the limit.
; Exit:   HL = the value minus one, so the range becomes 0 to limit-1. BC and DE unchanged.
;         CY if it was in range. A subscript of zero is always an error.
; ---------------------------------------------------------------------------------------------------------------------

GETSUBS:    PUSH BC
            CALL EXPT1NUM
            JR C,GTSBC

            POP BC
            RET                         ; Syntax check: a number is all that is required

; --- GTSBC: run time ---

GTSBC:      CALL GETINT
            POP BC                      ; The limit
            OR H
            JR Z,SWSIG                  ; Subscript zero

            DEC HL
            SBC HL,BC                   ; A limit of &FFFF permits 1 to &FFFF
            ADD HL,BC
            RET C

SWSIG:      XOR A
            LD (TEMPB2),A               ; Record that a subscript was out of range
            RET
