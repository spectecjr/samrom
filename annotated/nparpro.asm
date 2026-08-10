; =====================================================================================================================
; NPARPRO.ASM -- Procedure parameter binding, RESTORE, and local variable teardown
; =====================================================================================================================
;
; The most intricate part of the interpreter. Binding a procedure's parameters has to make the caller's arguments
; visible under the definition's names, hide any globals those names would otherwise refer to, and leave behind
; enough information for END PROC to put everything back.
;
; That information is a stack of undo records, pushed onto the BASIC stack below the return frame. DELOCAL walks
; them in reverse at END PROC.
;
; WHAT HAPPENS PER PARAMETER
; --------------------------
; Numeric, by value:
;     Look the name up. If a global exists, note its address so it can be hidden once every parameter is bound, and
;     keep searching so the last link in the letter's chain is found. Create a new variable of the same name holding
;     the argument's value. It stays invisible (bit 7 of its type byte) until binding finishes, so that a later
;     parameter naming the same variable still finds the global. Its address is recorded so END PROC can mark it
;     unused -- procedures reuse such slots rather than accumulating dead variables.
;
; Numeric, by REF:
;     As above, except the argument must be a variable name. That variable is hidden too, and its address recorded,
;     so that END PROC can copy the local's final value back into it.
;
; String or array, by value:
;     Hide any global of that name, then create a local at the end of the string area. Record the name so END PROC
;     can delete the local and reveal the global.
;
; String or array, by REF:
;     No copy is made. The caller's variable is *renamed* to the definition's name, and the original name is kept on
;     a rename stack so END PROC can rename it back.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; PROPAR / PROP2 -- bind a procedure's parameters
;
; Entry:  PRPTR -> the caller's argument list, DPPTR -> the definition's parameter list.
; Exit:   The parameters are bound and the undo records are on the BASIC stack.
; Notes:  PROP2 is the entry used by LOCAL, which does not want the terminator written first.
; ---------------------------------------------------------------------------------------------------------------------

PROPAR:     LD HL,(BSTKEND)
            DEC HL
            XOR A
            LD (HL),A
            DEC HL
            LD (HL),A                   ; A two-byte zero terminates the undo records
            LD (BSTKEND),HL

PROP2:      XOR A
            PUSH AF                     ; A zero on the machine stack terminates the "make invisible" list
            LD HL,HDR                   ; The tape header buffer doubles as the rename stack
            LD (HL),A
            LD (RNSTKE),HL
            CALL PTTODP
            JP Z,PPM2                   ; The definition takes no parameters

            CP TOK_DATA
            JR NZ,PPML

; --- "DEF PROC name DATA": arguments are read from a DATA list, so simply point DATADD at the caller's list ---

            POP AF
            LD HL,(PRPTR)
            LD A,(PRPTRP)
            JR RESTORE3


; ---------------------------------------------------------------------------------------------------------------------
; RESTORE -- the RESTORE command
;
; Placed here so that the DATA case above can reach RESTORE3 with a JR.
; ---------------------------------------------------------------------------------------------------------------------

RESTORE:    CALL SYNTAX3                ; A line number, or zero if none is given

            CALL GETINT

RESTORE2:   CALL FNDLINE                ; The address of that line; the page may change
            DEC HL                      ; READ increments before reading, so point just before it
            IN A,(251)

RESTORE3:   LD (DATADD),HL
            LD (DATADDP),A
            RET

; --- RESTOREZ: RESTORE 0, used by CLEAR and by LOAD of a program ---

RESTOREZ:   LD HL,0
            JR RESTORE2


; ---------------------------------------------------------------------------------------------------------------------
; PPLOOP / PPML -- bind one parameter
; ---------------------------------------------------------------------------------------------------------------------

PPLOOP:     CALL PTTODP
            JP Z,PPM2                   ; The definition's list has ended

PPML:       LD HL,(BSTKEND)
            LD DE,-23                   ; The most one parameter can need
            ADD HL,DE
            LD DE,(HEAPEND)
            SBC HL,DE                   ; The stack must not reach the heap
            JP C,BSFERR

            SUB TOK_REF
            LD (REFFLG),A               ; Zero marks a REF parameter
            JR NZ,PPNREF

            RST &20                     ; Skip REF

PPNREF:     CALL LVFLAGS                ; Look the definition's name up
            EX DE,HL                    ; Protect the previous-link address, needed if it does not exist
            LD HL,(CHAD)
            LD (DPPTR),HL               ; DPPTRP is still correct
            JP P,PPAS                   ; A string

            BIT 5,C
            JP NZ,PPAS                  ; A numeric array

            EX AF,AF'
            JR Z,PPA2                   ; No global of this name exists

            PUSH IX
            POP HL
            DEC HL                      ; -> its type byte
            PUSH HL                     ; Remember it, to be hidden once binding finishes
            IN A,(URPORT)
            OR &E0                      ; %111xxxxx: bit 7 says "record an address to reveal later"
            PUSH AF
            INC HL

PPNLP:      CALL NVMLP                  ; Keep searching this letter's chain
            JR Z,PPA15                  ; No second copy

; --- A second copy exists. Set it to minus zero, which DEFAULT reads as "does not exist": if the caller supplies a
; --- value it is overwritten, and if not the variable behaves as undefined.

            LD A,0
            LD (FIRLET),A
            PUSH HL
            LD (HL),A
            INC HL
            LD (HL),&FF
            INC HL
            LD (HL),A
            INC HL
            LD (HL),A
            POP DE                      ; The value's address
            DB SKIP2LDHL                ; Skip the LD C,D below

PPA15:      LD C,D                      ; D is zero here, giving a plain numeric type (clearing the FOR bit, which
            EX DE,HL                    ; would otherwise be read as "array")

PPA2:       CALL SYN1PP                 ; Build a destination descriptor, flagged as a new variable
            CALL PTTOPR                 ; Look at the caller's argument list
            JP Z,PPD2                   ; It has ended


; ---------------------------------------------------------------------------------------------------------------------
; UNVLK -- look for an unused numeric slot to reuse
;
; Procedures mark their locals unused rather than deleting them, so that repeated calls do not extend the variables
; area indefinitely. This finds such a slot with the right name length and type.
;
; Entry:  TLBYTE and FIRLET hold the wanted name.
; ---------------------------------------------------------------------------------------------------------------------

UNVLK:      LD BC,(TLBYTE)              ; C = type/length, B = the first letter
            LD A,B
            ADD A,A
            JR Z,PPA3                   ; The first letter was zeroed above, meaning a second copy already exists

            SUB "a"*2
            LD E,A                      ; The letter as a word index
            LD D,0
            CALL ADDRNV
            SET 5,C                     ; Looking for a slot marked unused
            LD A,C
            ADD HL,DE

UNVLP:      LD E,(HL)
            INC HL                      ; A link of &FFFF ends the chain and produces the carry tested below
            LD D,(HL)
            ADD HL,DE
            JR C,PPA3                   ; End of chain, or a page overflow

;           BIT 6,H
;           CALL NZ,INCURPAGE
            CALL CHKHL
            LD A,C                      ; Reload in case CHKHL used A
            CP (HL)
            INC HL
            JR NZ,UNVLP

            DEC HL                      ; -> the type byte of the unused slot
            PUSH HL
            LD A,(HL)
            SET 7,(HL)                  ; Hide it, so a later parameter cannot claim the same slot
            INC HL
            INC HL
            INC HL                      ; -> the rest of the name, or the value
            AND TLNAMELEN
            JR Z,PPA25                  ; A one-letter name

            EX DE,HL
            LD HL,FIRLET+1
            LD C,A
            LD B,0
            LDIR                        ; Overwrite the old name with the new one
            EX DE,HL

PPA25:      LD (DEST),HL                ; The reused slot's value area
            POP HL
            PUSH HL                     ; Its type byte, to be marked used at the end
            IN A,(URPORT)
            AND LMPRPAGE
            LD (DESTP),A
            OR &20                      ; %001xxxxx: "mark this used when binding finishes"
            PUSH AF
            XOR A
            LD (FLAGX),A                ; Not a new variable, since the slot already exists
            DB SKIP3IX

PPA3:       LD HL,(NUMEND)              ; No slot to reuse, so the variable will be created here

PPA4:       LD B,&40                    ; Bit 7 clear, bit 6 set so the record is not mistaken for the terminator
            CALL RUAHL                  ; Record the local's address, to be marked unused at END PROC
            CALL PTTOPR
            LD A,(REFFLG)
            AND A
            JR NZ,PPA5                  ; Not a REF parameter. NZ is essential here.

; --- A REF numeric: the argument must be a variable ---

            CALL LVFLAGS
            JP P,PARERR                 ; A string was supplied

            EX AF,AF'
            JR NZ,PPRNE                 ; It exists

; --- It does not, so create both it and the local with the value zero ---

            DB CALC
            DB STKZERO
            DB DUP
            DB EXIT

            CALL ASSISR                 ; Create the definition's variable with value zero, using the name at
                                        ; TLBYTE+33. C is zero.

            CALL CRTVAR35               ; Look the caller's variable up again -- it still does not exist -- and
                                        ; create it with value zero too
            LD A,(TLBYTE)
            LD C,A
            CALL NUMLOOK                ; Now find the variable just created
            XOR A                       ; Z: the local has already been assigned

PPRNE:      EX AF,AF'                   ; Z if the assignment is already done
            DEC IX                      ; -> the type byte of the caller's variable
            PUSH IX                     ; Remember it, to be hidden
            IN A,(URPORT)
            OR &E0                      ; %111xxxxx: an address to reveal later
            PUSH AF
            LD B,&A0                    ; Bits 7 and 5 of the page: "REF" and "belongs to a procedure"
            PUSH HL
            EX DE,HL
            LD HL,(BSTKEND)
            SET 5,(HL)                  ; Mark the record just pushed as REF; bit 7 clear means "the definition's
            EX DE,HL                    ; variable", so the pair reads as a REF binding
            CALL RUAHL                  ; Record the caller's variable, so END PROC can copy the value back:
                                        ;     TEST z
                                        ;     DEF PROC TEST REF x
                                        ; binds z's value into x; END PROC writes x's value into z and marks x
                                        ; unused.
            POP HL
            EX AF,AF'
            CALL NZ,HLTOFPCS            ; Stack the caller's value, if it was not created above
            CALL NZ,ASSIGN              ; ... and assign it to the local
            CP A                        ; Z, so the call below is skipped

;PPA5:      CALL SELCHADP               ; Ensure the variable search has not left the wrong page mapped
;PPA5:      CALL RCRC
;           JR NZ,PPA55
;           DB CALC
;           DB STKZERO
;           DB EXIT
;           INC HL
;           DEC (HL)                    ; NZ flag, value = minus zero
;           JR PPA45

PPA5:       CALL NZ,VALFET1             ; A by-value parameter: evaluate the argument and assign it.
                                        ; Returns with the destination's page mapped.
PPD1H:      JR PPD1


; ---------------------------------------------------------------------------------------------------------------------
; PPAS -- a string or array parameter
; ---------------------------------------------------------------------------------------------------------------------

PPAS:       LD B,&10                    ; Bit 4: a string name. Bit 7 clear: no global to reveal.
            EX AF,AF'
            JR Z,PAS2                   ; No global of this name exists

            LD B,&90                    ; Bit 7 as well: there is a global to reveal
            LD HL,(STRLOCN)             ; -> the type byte of the variable just found
            PUSH HL                     ; Remember it, to be hidden
            IN A,(URPORT)
            AND LMPRPAGE                ; Bit 7 clear: no address needs recording, only the name
            OR &60                      ; %011xxxxx, which is never zero and so not the terminator
            PUSH AF

PAS2:       CALL PPSUB                  ; Record the definition's name on the BASIC stack
            CALL PTTOPR
            JR Z,PPD2                   ; The caller's list has ended

            CALL SCOPNM                 ; Copy the definition's name to TLBYTE+33
            LD A,(REFFLG)
            AND A
            JR NZ,PPD0                  ; Not a REF parameter

; --- A REF string or array: rename the caller's variable rather than copying it ---

            LD A,(FLAGS)
            PUSH AF
            CALL LVFLAGS                ; Look up the caller's name
            JP P,REFSTR                 ; It is a string

            POP AF                      ; Bit 6 set if the definition's name is numeric
            RL C                        ; Bit 6 of C set if the caller's variable is an array
            AND C                       ; Both set: two numeric arrays, which is legal
            CPL
            DB SKIP1LDC

REFSTR:     POP AF

            AND TLSTRARRAY
            JP NZ,PARERR                ; A type mismatch

            EX AF,AF'
            JR Z,PAS3                   ; The caller's variable does not exist, so there is nothing to rename

            LD HL,(RNSTKE)              ; Push a rename record: definition name, variable address, page
            LD DE,(BSTKEND)             ; -> the definition's name on the BASIC stack
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D
            LD DE,(STRLOCN)             ; -> the caller's variable
            INC HL
            LD (HL),E
            INC HL
            LD (HL),D
            IN A,(URPORT)
            OR &80                      ; Ensure it is non-zero, since zero terminates the rename stack
            INC HL
            LD (HL),A
            LD (RNSTKE),HL

PAS3:       LD B,0                      ; Keep the original type byte
            CALL PPSUB                  ; Record the caller's original name too, so END PROC can restore it.
                                        ; The definition's name lies immediately beneath it.
            LD HL,(BSTKEND)
            DEC HL
            LD (HL),&FF                 ; An &FF prefix marks the pair as a REF rename
            LD (BSTKEND),HL
            JR PPD1


; ---------------------------------------------------------------------------------------------------------------------
; PPD0 -- a string or array passed by value: create a local copy
; ---------------------------------------------------------------------------------------------------------------------

PPD0:       LD A,(FLAGS)
            ADD A,A
            JP M,PARERR                 ; A numeric array cannot be passed by value

            LD HL,TLBYTE+33
            RES 6,(HL)                  ; Force a simple string type even if the definition wrote "a$()"
            CALL EXPTSTR
            CALL ASNST                  ; Create it at the end of the string area

PPD1:       CALL SELCHADP
            RST &18

PPD2:       LD (PRPTR),HL               ; Advance the caller's list pointer
            CP ")"
            JR NZ,PPD3

            RST &20                     ; Skip the closing bracket of, say, "NUM()"
            LD (PRPTR),HL

PPD3:       CP ","
            JR NZ,PPD35                 ; No more arguments

            RST &20
            LD (PRPTR),HL

PPD35:      CALL PTTODP
            CP ")"
            JR NZ,PPD4

            RST &20                     ; Skip the closing bracket in the definition too

PPD4:       CP ","
            JR NZ,PPM2                  ; The definition's list has ended

            RST &20
            JP PPML

;PPD5:      LD A,(REFFLG)
;           AND A
;           JR NZ,PARERR                ; REF with no argument would need a variable name
;           RST 20H
;           JR PPD2


; ---------------------------------------------------------------------------------------------------------------------
; PPMIL / PPM2 -- binding is complete, so apply the deferred visibility changes
;
; The machine stack holds pairs of (flags+page, address), terminated by a zero, describing what to hide, what to
; mark used, and whose address must be recorded for END PROC.
; ---------------------------------------------------------------------------------------------------------------------

PPMIL:      PUSH AF
            CALL SELURPG
            POP AF                      ; %011xxxxx a string or array, no address to record
                                        ; %111xxxxx a number, with an address to record
                                        ; %001xxxxx a number to be marked used
            ADD A,A                     ; CY when a displacement must be recorded;
                                        ; P when the variable is only to be marked used
            POP HL
            RES 7,(HL)                  ; Visible
            JP P,PPM3

            SET 7,(HL)                  ; Hide the existing global
            LD B,&80
            CALL C,RUAHL                ; Record its displacement from NVARS, as a "variable to reveal"
            DB SKIP2LDHL

PPM3:       RES 5,(HL)                  ; Mark the reused slot used

PPM2:       POP AF
            AND A
            JR NZ,PPMIL                 ; Not yet the terminator


; ---------------------------------------------------------------------------------------------------------------------
; RNMLP -- perform the REF renames
;
; Each rename record holds the definition's name on the BASIC stack, and the address of the caller's variable.
; ---------------------------------------------------------------------------------------------------------------------

RNMLP:      LD HL,(RNSTKE)
            LD A,(HL)
            AND A
            JR Z,RNMF                   ; The rename stack is empty

            CALL SELURPG
            DEC HL
            LD D,(HL)
            DEC HL
            LD E,(HL)
            PUSH DE                     ; -> the caller's variable
            DEC HL
            LD D,(HL)
            DEC HL
            LD E,(HL)
            DEC HL
            LD (RNSTKE),HL
            EX DE,HL
            POP DE                      ; HL -> the definition's name, DE -> the variable
            LD A,(HL)
            AND &0F
            LD C,A                      ; The definition name's length
            LD A,(DE)
            AND &70                     ; Visible, keeping the type bits
            OR C                        ; Type from the variable, length from the new name
            LD B,A
            LD A,(DE)
            RLA
            CALL C,NEGVTR               ; If the variable had been hidden, cancel the matching "reveal" record.
                                        ; That happens when a REF argument has the same name as one of the
                                        ; definition's parameters: a renamed variable must not also be hidden.
            LD A,B
            LD B,0
            CALL ILDISR                 ; Overwrite the variable's name with the definition's
            JR RNMLP

RNMF:       CALL PTTOPR
            RET Z                       ; The caller's list has ended too, so the counts matched

PARERR:     RST &08
            DB ERR_PARAMETER


; ---------------------------------------------------------------------------------------------------------------------
; NEGVTR -- cancel a "variable to reveal" record
;
; Entry:  DE -> the type byte of the variable about to be renamed.
; ---------------------------------------------------------------------------------------------------------------------

NEGVTR:     PUSH BC                     ; B = the new type byte, C = the definition name's length
            PUSH DE
            PUSH HL
            LD HL,(BSTKEND)

FDPNL:      LD A,(HL)
            AND A
            JR Z,PARERR                 ; Ran off the end without finding it

            BIT 4,A
            JR NZ,FDPN2                 ; A string name

            LD C,3                      ; A numeric displacement record: three bytes
            JR FDPN4

FDPN2:      CP &FF
            JR NZ,FDPN3                 ; Not a REF rename pair

            INC HL                      ; Step over the &FF
            LD A,(HL)

FDPN3:      AND &0F
            LD C,A
            LD A,(DE)
            XOR (HL)
            INC HL
            AND &AF                     ; Compare the reveal bit, the type bits and the length, ignoring bit 4
            JR Z,FDPN5                  ; (always clear in the variables area) and bit 6 ($ against $ array)

FDPN4:      LD B,0
            ADD HL,BC                   ; Step over this record
            JR FDPNL

FDPN5:      PUSH HL
            PUSH DE
            LD B,C

FDPBL:      INC DE
            LD A,(DE)
            CP (HL)
            INC HL
            JR NZ,FDPN6

            DJNZ FDPBL

FDPN6:      POP DE
            POP HL
            JR NZ,FDPN4                 ; The names differed

            DEC HL
            RES 7,(HL)                  ; Cancel the "reveal" bit
            POP HL
            POP DE
            POP BC
            RET


; ---------------------------------------------------------------------------------------------------------------------
; RUAHL -- record a variable's displacement from NVARS on the BASIC stack
;
; Entry:  AHL = the variable, B = the flag bits: bit 7 set to mark it unused at END PROC, clear to reveal it.
; ---------------------------------------------------------------------------------------------------------------------

RUAHL:      LD A,(NVARSP)
            LD C,A
            LD DE,(NVARS)               ; CDE = NVARS
            IN A,(URPORT)               ; AHL = the variable's type byte
            CALL SUBAHLCDE
            EX DE,HL                    ; ADE = the displacement, in page form
            LD HL,(BSTKEND)
            DEC HL
            LD (HL),D
            DEC HL
            LD (HL),E
            DEC HL
            AND &0F                     ; Bit 4 clear marks this a numeric record
            OR B
            LD (HL),A

BSSET:      LD (BSTKEND),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; PPSUB -- record a type byte and name on the BASIC stack
;
; Entry:  B = flag bits to merge into the stored type byte.
; Exit:   BC = 0.
; ---------------------------------------------------------------------------------------------------------------------

PPSUB:      LD DE,TLBYTE
            LD HL,(BSTKEND)
            LD A,(DE)
            AND &0F
            LD C,A
            LD A,(DE)
            AND &6F

            OR B                        ; Bit 4 always set to mark a string name; bit 7 set when there is a global
                                        ; to reveal
            LD B,0
            SBC HL,BC
            DEC HL                      ; Room for the type byte too
            LD (BSTKEND),HL
            EX DE,HL

ILDISR:     LD (DE),A
            INC DE
            INC HL
            LDIR
            RET


; =====================================================================================================================
; DELOCAL -- undo a procedure's parameter bindings
; =====================================================================================================================
;
; Called by END PROC and by POP when it discards a PROC frame. Walks the undo records left by PROPAR.
;
; Record formats, distinguished by the first byte:
;
;     00 00        the terminator
;     &FF          a REF string or array: the original name follows, then the definition's name. Find the variable
;                  under the definition's name and rename it back.
;     bit 4 set    a string or array name. Delete the local of that name; if bit 7 is also set, reveal the last
;                  hidden global of the same name.
;     bit 4 clear  a numeric displacement from NVARS.
;                     bit 7 set          a global to reveal
;                     bit 7 clear        a local to mark unused
;                     bits 7 and 5 set   the address of a REF argument's value; copy the local's value into it
;                     bit 7 clear, 5 set the local whose value is to be copied, then marked unused
; ---------------------------------------------------------------------------------------------------------------------

DELOCAL:    LD HL,(BSTKEND)
            LD A,(HL)
            INC HL
            INC HL
            AND A
            JR Z,BSSET                  ; The terminator. Checking one byte suffices.

            DEC HL
            BIT 4,A
            JR NZ,DLOCS                 ; A string or array name

            PUSH AF
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC HL
            LD (BSTKEND),HL
            AND &0F
            LD C,A                      ; CDE = the displacement, in page form
            CALL ADDRNV
            CALL ADDAHLCDE              ; HL -> the variable
            POP AF
            BIT 5,A
            JR Z,DLOC3                  ; An ordinary reveal or mark-unused

            RLA
            JR NC,DLOC2                 ; Bit 7 clear: this is the definition's variable, which always follows the
                                        ; REF argument's address

            IN A,(URPORT)               ; Bit 7 set: this is the REF argument's address, which is not needed until
            PUSH AF                     ; the next record supplies the value, so stack it
            PUSH HL
            JR DELOCAL

DLOC2:      SET 5,(HL)                  ; Mark the local unused
            LD A,(HL)
            AND TLNAMELEN
            ADD A,7                     ; Step over the link and the rest of the name
            LD C,A
            LD B,0
            ADD HL,BC                   ; -> the last byte of the value
            LD DE,TEMPW1+4
            LD C,NUMVALSIZE
            LDDR                        ; Copy the local's value to a scratch area
            INC DE
            EX DE,HL
            POP DE
            POP AF
            OUT (URPORT),A              ; DE -> the REF argument's value
            LD C,NUMVALSIZE
            LDIR                        ; Copy it back
            JR DELOCAL

DLOC3:      RLA
            RES 7,(HL)                  ; Make it visible, in case it is a global that was hidden
            JR C,DELOCAL                ; It was, so nothing more to do

            SET 5,(HL)                  ; It was a local, so mark it unused
            JR DELOCAL


; ---------------------------------------------------------------------------------------------------------------------
; DLOCS -- a string or array record
; ---------------------------------------------------------------------------------------------------------------------

DLOCS:      CP &FF
            JR NZ,DLCS2                 ; Not a REF rename

; --- A REF rename: find the variable under the definition's name and give it back its original one ---

            LD A,(HL)                   ; The original type byte
            AND &0F
            INC A
            LD C,A
            LD B,0
            PUSH HL
            ADD HL,BC                   ; -> the definition's name, which follows the original
            LD C,(HL)                   ; Its coded type byte: bit 7 carries extra data, bit 4 is set
            PUSH BC
            LD A,C
            AND &6F                     ; The plain type byte for the search; the search ignores the difference
                                        ; between a simple string and a string array
            INC HL
            CALL LKBSV
            JP Z,VNFERR

            POP BC                      ; B = 0, C = the coded byte
            POP DE                      ; -> the original name
            PUSH BC
            LD A,(DE)
            AND &0F
            LD C,A
            INC C                       ; BC = the name length plus the type byte
            LD HL,(STRLOCN)             ; -> the type byte in the variables area
            XOR (HL)
            AND &0F
            XOR (HL)                    ; Type bits from the variable, length from the original name
            EX DE,HL
            LD (HL),A
            LDIR                        ; Restore the original name
            POP BC
            LD A,C
            AND &EF                     ; Clear bit 4
            JR DLCS3                    ; A renamed variable never has a copy to erase


; ---------------------------------------------------------------------------------------------------------------------
; DLCS2 -- an ordinary string or array local: delete it, and reveal any global it hid
; ---------------------------------------------------------------------------------------------------------------------

DLCS2:      AND &EF                     ; Bit 4 is always clear in the variables area
            PUSH AF
            CALL LKBSV                  ; Find the local named on the stack

            CALL NZ,ASDEL2              ; Delete it if it exists
            POP AF

DLCS3:      BIT 7,A
            CALL NZ,STARYLK2            ; A global was hidden, so look for it
            JR Z,DELCLH                 ; None found, which should not happen

; --- Find the last hidden copy: successive definitions may have hidden the same name more than once ---

DLOCL:      PUSH DE                     ; -> the type byte just found
            IN A,(URPORT)
            PUSH AF
            CALL FLNOMTCH               ; Continue the search from here
            POP BC
            POP HL                      ; BHL = the previous match
            JR NZ,DLOCL                 ; Another one, so keep the newer

            LD A,B
            OUT (URPORT),A
            RES 7,(HL)                  ; Reveal the last hidden copy

DELCLH:     JP DELOCAL


; ---------------------------------------------------------------------------------------------------------------------
; PTTODP / PTTOPR -- point CHAD at one of the two parameter lists
;
; Exit:   Z if the list has ended, that is if CHAD points at a carriage return or colon. A comma is skipped.
; ---------------------------------------------------------------------------------------------------------------------

PTTODP:     LD HL,(DPPTR)
            LD A,(DPPTRP)
            JR PTTOC

PTTOPR:     LD HL,(PRPTR)
            LD A,(PRPTRP)

PTTOC:      LD (CHAD),HL
            LD (CHADP),A
            CALL SELURPG
            JP RCRC
;           RST 18H
;           CP 0DH
;           RET Z
;           CP ":"
;           RET
