; =====================================================================================================================
; MISC1.ASM -- Streams and channels, temporary colour state, READ, POKE and colour items
; =====================================================================================================================
;
; Four loosely related groups of routines that share a theme: they set up the context an output or assignment
; operation runs in.
;
;   Streams and channels   STRMINFO, SETSTRM, CHANFLAG -- turn a stream number into a selected channel
;   Colour state           TEMPS, GTEMPS, COLEX        -- refresh the working colour variables from the permanent set
;   Addressing             POKE, DPOKE, PDPSUBR        -- the 0-524287 address model shared with PEEK, CALL and USR
;   Statements             READ, PERMS, CITEM          -- READ, the colour commands, and inline colour items
;
; STREAMS AND CHANNELS
; --------------------
; A stream is a small number the user quotes as "#n"; a channel is a record describing an actual device. STREAMS
; holds one 16-bit displacement per stream into the channel area at (CHANS), or zero if the stream is closed. Each
; channel record is five bytes: output address, input address, letter.
;
; Streams -5 to -1 are the fixed system streams (B, $, K, S, R); 0 to 15 are the user's. Stream 16 is special --
; output to it is appended to a string variable -- and is mapped internally onto stream -4.
;
; PERMANENT AND TEMPORARY COLOUR STATE
; ------------------------------------
; Every colour attribute exists twice. The permanent copy is what INK, PAPER and friends set as commands; the
; temporary copy is what a print or plot actually uses. TEMPS refreshes the temporary set from the permanent one at
; the start of each operation, which is what makes "PRINT INK 2;x" affect only that statement while "INK 2" as a
; command persists.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; PRHSH1 / PRHSH2 -- parse and select a "#stream" prefix
;
; Entry:  PRHSH1 from LIST with the current character in A; PRHSH2 from PRINT, which has already seen the '#'.
; Exit:   The stream is selected. PRHSH1 simply returns if the character was not '#'.
; ---------------------------------------------------------------------------------------------------------------------

PRHSH1:     CP "#"
            RET NZ

PRHSH2:     CALL SSYNTAX6               ; Skip the '#' and insist on a numeric expression

            CALL GETBYTE                ; Stream number into A and C
            CALL STRMINF2
            JR STSM2


; ---------------------------------------------------------------------------------------------------------------------
; STRMINFO -- look up a stream's channel
;
; Entry:  STRMINFO with the stream number on the calculator stack; STRMINF2 with it already in A and C;
;         STRMINF3 from SETSTRM with a system stream number (&FC-&FF) in A.
; Exit:   DE = the channel displacement, HL -> its high byte in the stream table, C = the stream number,
;         Z if the stream is closed.
; ---------------------------------------------------------------------------------------------------------------------

STRMINFO:   CALL GETBYTE                ; Stream number into A and C

STRMINF2:   CP 17
            JR NC,INVSTRM               ; Only streams 0-16 may be named by a program

STRMINF3:   CP 16
            JR NZ,STRMINF4

            LD A,&FC                    ; Stream 16 is internally stream -4: output into a string variable
            LD C,A

STRMINF4:   ADD A,&0B                   ; Bias so the system streams become small positive numbers
            ADD A,A                      ; Two bytes per entry
            LD L,A
            LD H,STREAMS/256            ; The stream table lies wholly within the &5Cxx page
            LD E,(HL)
            INC HL
            LD D,(HL)
            LD A,D
            OR E                        ; Z if the displacement is zero, meaning the stream is closed
            RET

INVSTRM:    RST &08
            DB ERR_BADSTREAM

SNOTOPER:   RST &08
            DB ERR_STRMSHUT


; ---------------------------------------------------------------------------------------------------------------------
; STREAMFE / STREAMFD / SETSTRM -- select a stream as the current channel
;
; STREAMFE selects stream -2 (channel S, the main screen) and STREAMFD stream -3 (channel K, the lower screen);
; these are the two the ROM switches between constantly, so they get their own entry points.
;
; Entry:  SETSTRM with the stream number in A, in the range &FC-&03.
; Exit:   CURCHL, CLET and (for K, S and P) DEVICE are set, and the temporary colour variables are refreshed.
; ---------------------------------------------------------------------------------------------------------------------

STREAMFE:   LD A,&FE                    ; Stream -2: channel "S"
            DB SKIP2LDHL                ; Skip the next two bytes

STREAMFD:   LD A,&FD                    ; Stream -3: channel "K"

SETSTRM:    LD (STRNO),A                ; Remembered so the DOS can see which stream is in use
            CALL STRMINF3

STSM2:      JR Z,SNOTOPER               ; A zero displacement means the stream was never opened

            LD HL,(CHANS)
            ADD HL,DE                   ; -> second byte of the channel record
            DEC HL                      ; -> its first byte


; ---------------------------------------------------------------------------------------------------------------------
; CHANFLAG -- make the channel at HL current
;
; Entry:  HL -> the channel record
; Exit:   CURCHL and CLET set. For channels K, S and P, DEVICE is set and TEMPS is run.
; ---------------------------------------------------------------------------------------------------------------------

CHANFLAG:   LD (CURCHL),HL
            INC HL
            INC HL
            INC HL
            INC HL
            LD A,(HL)                   ; The channel letter, at offset 4
            LD (CLET),A                 ; INPUT consults this to decide whether editing is possible
            LD C,2
            CP "P"
            JR Z,STSMD                  ; Printer: DEVICE 2

            DEC C
            CP "K"
            JR Z,STSMD                  ; Lower screen: DEVICE 1

            DEC C
            CP "S"
            RET NZ                      ; Any other channel leaves DEVICE alone and skips TEMPS

STSMD:      LD A,C
            LD (DEVICE),A               ; S = 0, K = 1, P = 2


; =====================================================================================================================
; TEMPS -- refresh the temporary colour and window variables
; =====================================================================================================================
;
; Copies the permanent graphics settings over the temporary ones, selects the window belonging to the current device,
; and rebuilds the coloured pixel expansion table if the mode needs one.
;
; The expansion table must also be rebuilt after any printed INK or PAPER control code, which is why COLEX is a
; separate entry point.
; ---------------------------------------------------------------------------------------------------------------------

TEMPS:      CALL GTEMPS                 ; Copy the nine permanent graphics bytes to the temporary set
            LD HL,(UWRHS)               ; Upper window right and left edges
            LD DE,(UWTOP)               ; Upper window top and bottom edges
            LD A,(DEVICE)
            DEC A
            JR NZ,TEMUS                 ; Not the lower screen, so the upper window is right

            LD HL,(LWRHS)
            LD DE,(LWTOP)

TEMUS:      LD (WINDRHS),HL
            LD (WINDTOP),DE


; ---------------------------------------------------------------------------------------------------------------------
; COLEX -- build the coloured pixel expansion table
;
; Combines EXTAB, which expands a nibble of character data into screen pixels, with the current ink and paper, so
; that the mode 2 and 3 print routines can turn four bits of a character straight into a screen byte with one table
; lookup and no further work.
;
; Entry:  Nothing; reads MODE, M23PAPT and M23INKT.
; Exit:   CEXTAB rebuilt. Returns immediately in internal modes 0 and 1, which use attributes instead.
; ---------------------------------------------------------------------------------------------------------------------

COLEX:      LD A,(MODE)
            SUB MODE4COL
            RET C                       ; Internal modes 0 and 1 have no expansion table

            LD B,32                     ; Internal mode 3: 16 words
            JR NZ,COLEX1

            LD B,16                     ; Internal mode 2: 16 bytes

COLEX1:     LD DE,(M23PAPT)             ; E = paper, D = ink (they are adjacent for exactly this reason)
            LD HL,EXTAB                 ; Uncoloured expansion data
            EXX
            LD HL,CEXTAB                ; Coloured result
            EXX
            LD A,D
            XOR E
            LD C,A                      ; C = paper XOR ink

COLEXLP:    LD A,C
            AND (HL)                    ; Where the expanded nibble has a set bit, take (paper XOR ink) ...
            INC L
            XOR E                        ; ... then XOR paper, giving ink there and paper elsewhere
            EXX
            LD (HL),A
            INC L
            EXX
            DJNZ COLEXLP

            RET


; ---------------------------------------------------------------------------------------------------------------------
; GRATEMPS / GTEMPS -- refresh the temporary graphics variables
;
; GRATEMPS forces the upper screen first and skips COLEX, which the plotting routines do not need; the table is only
; consulted when printing characters.
; ---------------------------------------------------------------------------------------------------------------------

GRATEMPS:   XOR A
            LD (DEVICE),A               ; Graphics always go to the upper screen

GTEMPS:     LD HL,THFATP
            LD DE,THFATT
            LD BC,9                     ; THFATP to GOVERP inclusive
            LDIR
            LD A,(DEVICE)
            AND A
            JR Z,TEMPS1                 ; Upper screen: the permanent colours are correct

            LD H,B                      ; B and C are both zero after the LDIR
            LD L,B
            LD (OVERT),HL               ; OVER 0 and INVERSE 0 in the lower screen
            LD A,(BORDCR)
            LD L,A
            LD (ATTRT),HL               ; Lower screen attribute; MASKT becomes zero
            LD HL,(M23LSC)              ; Lower screen colours for internal modes 2 and 3
            LD (M23PAPT),HL

TEMPS1:     LD A,(MODE)
            CP MODE4COL
            RET Z                       ; Internal mode 2 honours the thin-pixel setting

            LD A,1
            LD (THFATT),A               ; Every other mode forces fat pixels
            RET


; =====================================================================================================================
; POKE, DPOKE and the shared address model
; =====================================================================================================================
;
; POKE, DPOKE, PEEK, DPEEK, CALL and USR all accept addresses from 0 to 524287, interpreted relative to the base page
; of the current context:
;
;     0      - 16383    ROM0                         (section A)
;     16384  - 32767    the base page                (section B)
;     32768  - 49151    base + 1                     (section C)
;     49152  - 65535    base + 2                     (section D)
;     65536  and above  paged into &8000-&BFFF, so 65536 maps base+3 into section C
;
; The last case only matters to code that is not relocatable, since the address it sees is always &8000-&BFFF.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; POKE -- POKE address,value[,value...]  or  POKE address,string
;
; A string argument is block-copied to the address. Numeric arguments are stored ascending from it, and up to 31
; extras may follow the first.
; ---------------------------------------------------------------------------------------------------------------------

POKE:       CALL EXPT1NUM               ; The address
            CALL INSISCOMA
            CALL EXPTEXPR               ; The value, of either type
            JR NZ,POKE2                 ; Numeric, so fall through to the list handling

            RET NC                      ; String at syntax check time: nothing more to do

            CALL STKFETCH               ; A = page, DE = start, BC = length
            PUSH AF
            PUSH DE
            CALL SPLITBC                ; Set PAGCOUNT and MODCOUNT from the length
            CALL UNSTLEN                ; The destination address, as page and offset
            LD C,A
            DEC C
            EX DE,HL
            SET 7,D                     ; CDE = destination, normalised into &8000-&BFFF
            POP HL
            POP AF                      ; AHL = source
            JP FARLDIR

POKE2:      JR NC,POKE3                 ; Syntax check: just count the arguments

            DB CALC                     ; Stack holds address, value
            DB SWOP                     ; ... value, address
            DB STOD0                    ; Save the address in memory 0 and drop it
            DB EXIT

POKE3:      LD DE,0                     ; Count of extra values beyond the first
            RST &18
            JR POKE4

POKENL:     PUSH DE
            CALL SEXPT1NUM              ; Skip the comma and evaluate another value
            POP DE
            INC E
            BIT 5,E
            JP NZ,NONSENSE              ; At most 31 extra values

POKE4:      CP ","
            JR Z,POKENL

            CALL CHKEND                 ; Returns to the caller's caller at syntax check time

            PUSH DE

            DB CALC                     ; The values are on the stack; recover the address behind them
            DB RCL0
            DB EXIT

            CALL NPDPS                  ; HL = the mapped address, A = the entry HMPR value
            POP DE                      ; E = number of extra values
            ADD HL,DE                   ; Start at the far end and work back, since the values unstack in reverse
            INC E

PKALP:      PUSH HL
            PUSH DE
            CALL FPTOA
            JP C,IOORERR                ; Values must fit in a byte

            JR Z,POKE5                  ; Positive

            NEG                         ; Accept negative values as their two's complement

POKE5:      POP DE
            POP HL
            LD (HL),A
            DEC HL
            DEC E
            JR NZ,PKALP

            RET


; ---------------------------------------------------------------------------------------------------------------------
; DPOKE -- DPOKE address,word
; ---------------------------------------------------------------------------------------------------------------------

DPOKE:      CALL SYNTAX8                ; Insist on two numeric arguments

            CALL GETINT                 ; The word to store
            CALL NPDPS                  ; HL = the mapped address
            LD (HL),C
            INC HL
            LD (HL),B
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PDPSUBR -- resolve a 0-524287 address and page it in
;
; Entry:  PDPSUBR with the address on the calculator stack; PDPSR2 (used by LOAD CODE) with it already in AHL.
; Exit:   HL = the address as seen by the caller, with the right page mapped
;         A  = the entry HMPR value, so the caller can restore it
;         BC preserved; LMPR untouched.
; ---------------------------------------------------------------------------------------------------------------------

PDPSUBR:    PUSH BC                     ; BC survives the whole routine
            IN A,(URPORT)
            PUSH AF
            CALL UNSTLEN                ; AHL = the address in page form
            SET 7,H                     ; Normalise the offset into &8000-&BFFF
            DB SKIP2LDDE                ; Skip the PUSH AF below

PDPSR2:     PUSH BC
            PUSH AF                     ; Balance the stack for the shared exit

PDPC:       CP 4
            JR NC,PDPSUBR4              ; Above &FFFF: leave it in section C and just select the page

            LD C,2                      ; Paging will be ROM0, base, base+1, base+2
            CP C
            JR Z,PDPSUBR3               ; &8000-&BFFF already suits page 2

            JR NC,PDPSUBR2              ; Page 3, so the offset belongs in section D

            RES 7,H                     ; Bring the offset down to 0000-&3FFF
            AND A
            JR Z,PDPSUBR3               ; Page 0 is ROM0, and the offset is already right

PDPSUBR2:   SET 6,H                     ; Add &4000, moving the offset into the next section up

PDPSUBR3:   LD A,C

PDPSUBR4:   DEC A                       ; The page selected in section C is one below the notional one
            CALL TSURPG
            POP AF                      ; The entry HMPR value
            POP BC
            RET


; ---------------------------------------------------------------------------------------------------------------------
; CHKMD23 -- insist on internal mode 2 or 3
;
; The block graphics operations (GRAB, PUT, ROLL, FILL) need a linear, attribute-free screen.
; ---------------------------------------------------------------------------------------------------------------------

CHKMD23:    LD A,(MODE)
            CP MODE4COL
            RET NC

INVMERR:    RST &08
            DB ERR_BADMODE


; =====================================================================================================================
; READ -- READ var[,var...]  and  READ LINE var$
; =====================================================================================================================
;
; DATADD tracks a position inside the current DATA statement. If it no longer points at a separator, the program is
; searched forwards for the next DATA statement.
;
; Plain READ evaluates the DATA text as a full expression, so a DATA item may be any constant expression. READ LINE
; instead takes the raw characters up to the next comma, colon or end of line -- but the text may contain invisible
; numeric forms left there by the syntax check, so it is copied to workspace and stripped before being assigned.
; ---------------------------------------------------------------------------------------------------------------------

READ:       CP LINETOK
            PUSH AF                     ; Z if this is READ LINE
            JR NZ,READ2

            CALL SSYNTAX1               ; Skip LINE and assess the destination variable
            LD HL,FLAGS
            BIT  6,(HL)
            JP NZ,NONSENSE              ; READ LINE needs a string variable
                                        ; (falling through here would re-assess the variable)
READ2:      CALL NZ,SYNTAX1             ; Ordinary READ: assess the destination
            CALL RUNFLG
            JP NC,RJUNKFLG              ; Syntax check: just look for a following comma

            RST  &18
            LD (PRPTR),HL               ; Park CHAD in an auto-adjusted variable: creating the destination
            LD A,(CHADP)                ; variable may move memory, and CHAD itself is about to be reused
            LD (PRPTRP),A               ; to walk the DATA list
            CALL ADDRDATA               ; Page in the DATA pointer and load it into HL
            LD (CHADP),A
            LD   A,(HL)
            CP   " "
            JR   Z,READ3                ; A space follows the DATA keyword itself

            CP ","
            JR   Z,READ3                ; A comma separates items, so more data remains here

            LD (CHAD),HL                ; Otherwise search onwards for the next DATA statement
            LD E,TOK_DATA
            LD HL,(CLA)
            PUSH HL                     ; SRCHPROG moves CLA as it scans lines
            CALL SRCHPROG
            POP DE
            LD (CLA),DE                 ; Restore the executing line
            IN A,(URPORT)               ; CHAD now points just past the DATA keyword
            LD (CHADP),A
                                        ; DATADDP is deliberately not updated here; READ7 sets it from the final
                                        ; position, which is the value that matters
            JR C,READ4                  ; Found

            RST &08
            DB ERR_DATADONE

READ3:      INC HL                      ; Step over the separator
            LD (CHAD),HL

READ4:      POP  AF
            JR   Z,READLN               ; READ LINE

            CALL VALFET1                ; Evaluate the item and assign it
            JR   READ7


; ---------------------------------------------------------------------------------------------------------------------
; READLN -- READ LINE: take the raw text of the item
; ---------------------------------------------------------------------------------------------------------------------

READLN:     LD   BC,&FFFF               ; Length counter, pre-decremented
            PUSH HL                     ; Start of the item

READ5:      LD A,(HL)
            CP &22
            JR NZ,READ6

RDSTRL:     INC HL                      ; Inside quotes: run to the closing quote, ignoring separators
            INC BC
            CP (HL)
            JR NZ,RDSTRL

READ6:      CALL NUMBER                 ; Step over any invisible numeric form
            LD   (CHAD),HL
            INC  HL
            INC  BC                     ; Count only the characters that will survive
            CALL COMCRCO                ; Comma, colon or carriage return ends the item
            JR   NZ,READ5

            POP  DE
            PUSH BC                     ; Length excluding the invisible forms
            SBC  HL,DE                  ; Distance CHAD actually moved
            LD   B,H
            LD   C,L                    ; Length including the forms, plus one
            CALL SCOPYWK                ; Copy the raw text to workspace
            EX DE,HL
            PUSH HL
            CALL REMOVEFP               ; Strip the invisible forms from the copy
            POP  DE                     ; Start of the text in workspace
            POP  BC                     ; Its true length
            CALL STKSTOREP              ; Stack it as a string
            CALL ASSIGN

READ7:      RST  &18                    ; CHAD now points past the item just consumed
            LD (DATADD),HL              ; which becomes the new DATA position
            IN A,(URPORT)
            LD (DATADDP),A
            LD HL,(PRPTR)               ; Recover the real CHAD, adjusted if memory moved
            LD (CHAD),HL
            LD A,(PRPTRP)
            CALL SETCHADP
            DB SKIP1CP                  ; Skip the POP below

RJUNKFLG:   POP AF                      ; Discard the READ LINE flag
            RST  &18
            CP ","
            RET NZ

            RST &20                     ; Another variable follows
            JP READ


; =====================================================================================================================
; Colour items
; =====================================================================================================================
;
; A colour item is an inline "INK n;" style qualifier. They appear in PRINT, in INPUT, and before the coordinates of
; PLOT, CIRCLE and FILL. The same parsing serves the INK, PAPER, FLASH, BRIGHT, INVERSE and OVER commands, which are
; simply colour items that also copy the result to the permanent variables.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; SYNT9SR -- prepare for the colour items preceding a graphics coordinate pair
; ---------------------------------------------------------------------------------------------------------------------

SYNT9SR:    CALL RUNFLG
            JR NC,SYN9SR1               ; Syntax check: no state to set up

            XOR A
            LD (DEVICE),A               ; Graphics always target the upper screen
            CALL GRATEMPS
            LD HL,MASKT
            LD A,(HL)
            OR &F8                      ; Plotting uses only the ink bits of the attribute, so mask the rest through
            LD (HL),A
            INC HL
            RES 6,(HL)                  ; PFLAGT: not PAPER 9

SYN9SR1:    RST &18


; ---------------------------------------------------------------------------------------------------------------------
; CITEM -- consume a run of colour items separated by commas or semicolons
; ---------------------------------------------------------------------------------------------------------------------

CITEM:      CALL CITEMSR
            RET  C                      ; Not a colour item, so the run has ended

            RST  &18
            CALL INSISCSC               ; Require and skip a comma or semicolon
            JR CITEM


; ---------------------------------------------------------------------------------------------------------------------
; CITEMSR -- handle one colour item, if the current character starts one
;
; Entry:  A = the current character
; Exit:   CY if this was not a colour item (the caller should try something else)
;         NC if one was dealt with
; ---------------------------------------------------------------------------------------------------------------------

CITEMSR:    CP TOK_PEN
            RET  C                      ; Below INK/PEN

            CP TOK_OVER+1
            CCF
            RET  C                      ; Above OVER

            LD C,A
            RST  &20                    ; Skip the keyword
            LD A,C

; ---------------------------------------------------------------------------------------------------------------------
; COTEMP4 -- shared with the INK/PAPER/... commands, which arrive with the token in A
; ---------------------------------------------------------------------------------------------------------------------

COTEMP4:    SUB TOK_PEN-CC_INK          ; Tokens &A1-&A6 become control codes 16-21
            PUSH AF
            CALL EXPT1NUM               ; The parameter
            POP  BC                     ; C = the control code
            CALL RUNFLG
            RET NC                      ; Syntax check: NC reports "item dealt with"

            PUSH BC
            CALL GETBYTE
            LD   D,A                    ; D = the parameter
            POP  AF                     ; A = the control code, then fall into PRCOITEM


; ---------------------------------------------------------------------------------------------------------------------
; PRCOITEM -- apply a colour control code to the temporary variables
;
; Also entered from the print routine when it meets an embedded control code.
;
; Entry:  A = control code CC_INK to CC_OVER, D = its parameter
; Exit:   NC, meaning "the item was dealt with".
;
; Notes:  The interpreter converts INK or PAPER 8 and 9 into 17 and 18 before arriving here. A few forms escape the
;         translation -- "INK n" with a variable, for instance -- and behave differently as a result.
;         INK i with BRIGHT b selects ink i + 8b in internal mode 3; BRIGHT is ignored in mode 2 although the mode
;         0/1 variables still change. INK i for i > 7 selects ink i-8 with BRIGHT 1.
;         OVER 0-3 sets both OVERT and GOVERT, giving PUT and the plotting routines their XOR, OR and AND modes.
; ---------------------------------------------------------------------------------------------------------------------

PRCOITEM:   RST &30
            DW PRCOITEM2                ; The body lives in ROM1
            CALL COLEX                  ; Ink or paper may have changed, so rebuild the expansion table
            AND A                       ; NC: dealt with
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PERMS -- the INK, PAPER, FLASH, BRIGHT, INVERSE and OVER commands
;
; Applies the change to the temporary variables exactly as an inline item would, then copies the result to the
; permanent ones so that it persists.
; ---------------------------------------------------------------------------------------------------------------------

PERMS:      CALL RUNFLG
            JR NC,PER2                  ; Syntax check: no state to set up

            XOR A
            LD (DEVICE),A               ; Colour commands act on the upper screen
            CALL TEMPS

PER2:       LD A,(CURCMD)               ; Which of the six commands this is
            CALL COTEMP4
            CALL CHKEND

; ---------------------------------------------------------------------------------------------------------------------
; PER3 -- copy the temporary colour variables to the permanent ones. Also used by CLS #.
; ---------------------------------------------------------------------------------------------------------------------

PER3:       LD HL,ATTRT
            LD DE,ATTRP

; ---------------------------------------------------------------------------------------------------------------------
; LDIR8 -- copy eight bytes from HL to DE. Also used by the screen scroll to save and restore the colour state.
; ---------------------------------------------------------------------------------------------------------------------

LDIR8:      LD BC,8
            LDIR                        ; ATTRT to GOVERT
            RET
