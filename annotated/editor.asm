; =====================================================================================================================
; EDITOR.ASM -- The line editor
; =====================================================================================================================
;
; Collects a line of input, either into the edit line (ELINE) for the main loop to tokenise and run, or into
; workspace for INPUT. The two cases share almost all of this code; FLAGX bit 5 (FFLXINPUT) selects between them.
;
; STRUCTURE
; ---------
; EDITOR pushes an error frame and then loops. Each pass fetches one key and classifies it by code:
;
;     &00-&06        Inserted literally (block graphics, comma tab, and so on)
;     &07-&0F        An editing key -- dispatched through the EKPT displacement table
;     &10-&15        A colour control code, which is inserted along with the parameter keystroke that follows it
;     &16 and above  Inserted literally
;
; Editing routines simply RET, because the loop address is pushed on the stack each time round.
;
; THE CURSOR
; ----------
; KCUR points at the character the cursor sits before. Insertions open one byte there with MAKEROOM; deletions close
; bytes with RECLAIM. Because a function token is the two bytes &FF and a code, cursor movement and deletion treat
; such a pair as a single character.
;
; CHANNEL "R"
; -----------
; ADDCHAR is the output routine of channel R, a pseudo-device whose "screen" is the edit line. Printing to it
; inserts characters at the cursor. That is how EDIT lists an existing program line back into the buffer for
; editing, and how AUTO pre-types the next line number: both simply print through channel R.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; EDER -- error trap for the editor
;
; Entered by an error raised while editing. On the keyboard or screen channels the error is reported as a buzz and
; the line is re-presented; anywhere else it is passed on as a real error.
; ---------------------------------------------------------------------------------------------------------------------

EDER:       CALL KSCHK                  ; Z if this is channel K or S
            JP NZ,ERRCHK

            CALL WARNBZ                 ; Buzz, clear the error, and fall back into the loop
            JR EDAG


; ---------------------------------------------------------------------------------------------------------------------
; EDCX -- editor entry that first clears any pending error marker
;
; Used by INPUT, which needs ERRNR clear so that a failed conversion can be distinguished from an earlier error.
; ---------------------------------------------------------------------------------------------------------------------

EDCX:       XOR A
            LD (XPTR+1),A               ; Cancel the flashing '?' position marker
            LD (ERRNR),A                ; Needed by INPUT LINE


; ---------------------------------------------------------------------------------------------------------------------
; EDITOR -- edit a line
;
; Entry:  ELINE (or the INPUT buffer) already set up; FLAGX bit 5 selects which.
; Exit:   On ENTER, returns to the caller with the line in the buffer.
; Notes:  ERRSP is redirected to EDER for the duration, so a syntax error raised while editing re-enters the loop
;         rather than aborting to the main loop.
; ---------------------------------------------------------------------------------------------------------------------

EDITOR:     LD HL,(EDITV)
            LD A,H
            OR L
            CALL NZ,HLJUMP              ; Allow a utility to take over or pre-process the edit

            LD HL,(ERRSP)
            PUSH HL                     ; Remember the caller's error frame
            CALL POFETCH
            LD (OLDPOS),DE              ; Where the line currently ends on screen, so redraws can overwrite it

EDAG:       LD HL,EDER
            PUSH HL
            LD (ERRSP),SP               ; Errors now land in EDER
            CALL AULN                   ; If AUTO is on, pre-type the next line number

EDLP:       LD HL,EDLP
            PUSH HL                     ; Every editing routine returns straight back here
            CALL EDFK                   ; Fetch a key, expanding any DEF KEY definition
            PUSH AF
            CALL NOISE                  ; Key click
            POP AF
            CP CC_AT
            JR NC,ADCH1                 ; &16 and above: insert literally

            CP CC_EDIT
            JR C,ADCH1                  ; &00-&06: insert literally

            CP CC_INK
            JR NC,TWOKYS                ; &10-&15: a colour code, which takes a parameter

; --- &07-&0F: an editing key. EKPT holds a self-relative displacement per key. ---

            LD HL,EKPT-CC_EDIT          ; Bias so that key 7 indexes entry 0
            LD C,A
            LD E,A
            LD D,0
            ADD HL,DE
            LD E,(HL)
            ADD HL,DE                   ; HL = the routine address
            PUSH HL
            JP ADDRKC                   ; Page in and load HL from KCUR, then "return" to the routine

TWOKYS:     CALL ADCH1                  ; Insert the control code itself
            CALL WAITKEY                ; Its parameter is whatever is typed next
            JR ADCH1


; ---------------------------------------------------------------------------------------------------------------------
; ADDCHAR -- output routine for channel "R": insert the character at the cursor
;
; Entry:  A = the character
; Exit:   The character is inserted and KCUR advanced.
;
; Token bytes are expanded back to their keyword text unless the in-quotes flag is set, so a program line printed
; through this channel arrives in the buffer as editable text. FLAGS bit 0 is maintained so that re-tokenising the
; edited line reproduces the original spacing.
; ---------------------------------------------------------------------------------------------------------------------

ADDCHAR:    CP TOK_USING
            JR NC,ADCH07                ; &85 and above may be a keyword

            LD HL,FLAGS                 ; &00-&84: insert as-is, tracking the leading-space rule
            CP " "
            JR Z,ADCH05

            RES 0,(HL)                  ; FFLAGNOSP clear: a leading space will be needed before the next keyword
            CP ":"
            JR NZ,ADCH1

            LD A,(LSTFT)                ; Pretty listing state, as seen by channel R
            AND A
            LD A,":"
            JR Z,ADCH1                  ; Plain listing: a colon does not suppress the space

ADCH05:     SET 0,(HL)                  ; No leading space needed after a space, or after a colon when pretty
                                        ; listing is on
            JR ADCH1

ADCH07:     LD C,A
            LD A,(INQUFG)
            RRCA
            LD A,C
            JR C,ADCH1                  ; Inside quotes: tokens are characters, so insert the byte unchanged

            RST &30
            DW PRGR802-&8000            ; Expand the keyword (&85-&FE) or function (&FF plus code) into text


; ---------------------------------------------------------------------------------------------------------------------
; ADCH1 -- insert the byte in A at the cursor
;
; The general entry point: anything at all can be inserted here, with no interpretation.
; ---------------------------------------------------------------------------------------------------------------------

ADCH1:      LD B,A
            CALL R1OSR                  ; ROM1 off, both port values saved
            PUSH BC                     ; The character
            CALL ADDRKC                 ; HL = KCUR, with its page mapped
            LD BC,1
            CALL MKRMCH                 ; Open one byte, permitting the last of memory to be used
            POP AF
            LD (HL),A
            INC HL
            LD (KCUR),HL                ; Leave KCURP alone: the cursor shares a page with ELINE or workspace
            JP POPOUT                   ; Restore both port values and return


; ---------------------------------------------------------------------------------------------------------------------
; EDFK -- fetch a key, expanding user-defined keys
;
; Entry:  Nothing.
; Exit:   A = a key code, or the routine has inserted a whole definition and returned to the loop.
;
; Codes 192-254 may carry a DEF KEY definition. Codes 192-201 are the keypad, which produce digits instead when
; KPFLG selects numeric mode. A definition ending in ':' is inserted without pressing ENTER, which is how the
; supplied F-key definitions leave the cursor mid-line.
; ---------------------------------------------------------------------------------------------------------------------

EDFK:       CALL WAITKEY
            CP 192
            RET C                       ; Not in the definable range

            CP 202
            JR NC,EDFK1                 ; Above the keypad keys

            LD C,A
            LD A,(KPFLG)
            RRA
            LD A,C
            JR NC,EDFK1                 ; Function-key mode, so look for a definition

            SUB 144                     ; Numeric mode: 192-201 become '0'-'9'
            RET

EDFK1:      CALL FNDKYD                 ; Look for a definition for this key
            LD A,D                      ; Recover the key code
            RET C                       ; None, so return the code itself

            PUSH HL                     ; Start of the definition
            ADD HL,BC
            DEC HL                      ; -> its last character
            LD A,(HL)
            CP ":"
            JR NZ,EDFK2

            DEC BC                      ; A trailing colon is dropped and suppresses the ENTER

EDFK2:      PUSH AF                     ; The last character
            PUSH BC                     ; Length
            CALL ADDRKC
            CALL MAKEROOM               ; Open room for the whole definition
            EX DE,HL                    ; DE = the space
            POP BC
            POP AF
            POP HL                      ; Source
            PUSH AF
            LDIR
            EX DE,HL
            LD (KCUR),HL                ; Cursor ends after the inserted text
            CALL NOISE
            POP AF
            POP DE                      ; Discard the return to the editor loop
            JP NZ,EDENT                 ; No trailing colon: act as though ENTER were pressed

            RET                         ; Otherwise carry on editing


; ---------------------------------------------------------------------------------------------------------------------
; EKPT -- editing key dispatch table
;
; One byte per key, each a displacement from its own entry to the routine. The subtractions correct for the table
; index having already advanced.
; ---------------------------------------------------------------------------------------------------------------------

EKPT:       DB EDKY-EKPT                ; &07  EDIT
            DB EDLT-EKPT-1              ; &08  Cursor left
            DB EDRT-EKPT-2              ; &09  Cursor right
            DB EDDN-EKPT-3              ; &0A  Cursor down
            DB EDUP-EKPT-4              ; &0B  Cursor up
            DB EDDLL-EKPT-5             ; &0C  Delete left
            DB EDENT-EKPT-6             ; &0D  ENTER
            DB EDDLR-EKPT-7             ; &0E  Delete right
            DB EDKPX-EKPT-8             ; &0F  Keypad toggle


; ---------------------------------------------------------------------------------------------------------------------
; EDKY -- the EDIT key: list a program line into the edit buffer
;
; Prints line EPPC through channel R, which inserts it into ELINE as editable text. Pretty listing is turned off for
; the duration so that colons stay colons rather than becoming line breaks, and the '>' cursor is suppressed.
; ---------------------------------------------------------------------------------------------------------------------

EDKY:       LD A,(FLAGX)
            AND FFLXINPUT
            JP NZ,CLEARSP               ; In INPUT mode there is no program line to fetch, so just clear the line

            CALL EVALLINO               ; A line number typed before EDIT selects that line
            JR C,EDKY2                  ; Out of range: ignore it

            RST &18
            CP CC_ENTER
            JR NZ,EDKY2                 ; The line held more than just a number, so ignore it

; --- Entry from the EDIT command, with the line number already in BC ---

EDKY1:      LD A,B
            OR C
            JR Z,EDKY2                  ; Line 0 is not a real line

            LD (EPPC),BC                ; Typing "123" then EDIT moves the cursor to line 123

EDKY2:      CALL CLEARSP                ; Empty the edit or INPUT line
            LD HL,(EPPC)
            CALL FNDLINE
            CALL LNNM                   ; DE = the line number actually found, or zero
            LD A,D
            OR E
            RET Z                       ; Nothing to edit

            LD DE,(CURCHL)
            PUSH DE                     ; Save the current channel
            LD A,(EPPC+1)
            PUSH AF
            PUSH HL                     ; Low byte of the line number
            LD A,&FF
            LD (EPPC+1),A               ; An impossible line number, so no '>' cursor is printed
            CALL SETSTRM                ; Select channel R -- output now inserts into the edit line
            LD HL,LISTFLG
            LD A,(HL)
            LD (LSTFT),A                ; Let channel R see the real pretty-listing setting
            LD (HL),0                   ; ... but list with it off, so colons are preserved
            EX (SP),HL
            DEC HL                      ; -> the start of the line record
            RST &30
            DW OUTLINE                  ; List it into the buffer
            POP HL
            LD A,(LSTFT)
            LD (HL),A                   ; Restore LISTFLG
            POP AF
            LD (EPPC+1),A
            LD HL,(ELINE)
            LD BC,5
            ADD HL,BC
            LD (KCUR),HL                ; Put the cursor just after the five-digit line number
            POP HL
            JP CHANFLAG                 ; Restore the previous channel


; ---------------------------------------------------------------------------------------------------------------------
; EDLT / EDRT -- cursor left and right
;
; A function token occupies two bytes, &FF followed by a code, and must be stepped over as a unit. Moving left tests
; the byte before the new position: if it is &FF then the cursor would land on the code byte, so it moves again.
; ---------------------------------------------------------------------------------------------------------------------

EDLT:       CALL SETDE                  ; DE = start of the line, HL = the cursor. Returns NC.

EDLT2:      DEC HL
            SBC HL,DE
            ADD HL,DE
            RET C                       ; Already at the start: the new position would be the VARSTERM byte

            JR Z,EDRLC                  ; The new position is exactly the line start, which is fine

            DEC HL                      ; Look at the character before the new position
            LD A,(HL)
            INC HL
            INC A
            JR Z,EDLT2                  ; It is &FF, so step over the whole token

            JR EDRLC

EDRT:       LD A,(HL)
            INC HL
            CP CC_ENTER
            RET Z                       ; At the end of the line

            INC A
            JR Z,EDRT                   ; Stepped onto an &FF prefix, so move again

EDRLC:      LD (KCUR),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; EDDN / EDUP -- cursor down and up
;
; Within a line these move the cursor to the same column on the row above or below. That is done by re-printing the
; line through the special CUOP output routine, which watches for the screen position matching the wanted one and
; records the corresponding position in the line.
;
; In edit mode with an empty line, the keys instead move the '>' program cursor through the listing.
; ---------------------------------------------------------------------------------------------------------------------

EDDN:                                   ; A = &0A
EDUP:       LD A,C                      ; A = &0B or &0A, whichever key was pressed
            LD HL,FLAGX
            BIT 5,(HL)
            JR NZ,EDUD2                 ; FFLXINPUT: INPUT mode, so always move within the line

            CALL ADDRELN
            LD A,(HL)
            CP CC_ENTER
            LD A,C
            JP Z,FUPDN                  ; Edit mode with an empty line: move the program cursor instead

EDUD2:      LD HL,KPOS+1                ; The row the cursor is currently on
            CP CC_UP
            JR Z,EDUD25

            INC (HL)                    ; Down: aim one row lower
            INC (HL)

EDUD25:     DEC (HL)                    ; Both paths end up adjusting by one row
            LD DE,CUOP
            CALL KOPSET                 ; Divert channel K's output to the position-watching routine
            LD HL,(WORKSP)
            DEC HL
            LD A,(FLAGX)
            AND FFLXINPUT
            JR Z,EDUD3                  ; Edit mode: HL is the end of ELINE

            LD HL,(WKEND)               ; INPUT mode: the end of the input line

EDUD3:      DEC HL
            LD (KCUR),HL                ; Default to the end of the line if no position matches
            CALL NOISE
            CALL EDPRT                  ; Re-print, letting CUOP find the matching position
            LD DE,(MNOP)                ; Restore normal output


; ---------------------------------------------------------------------------------------------------------------------
; KOPSET -- point channel K's output address at DE
; ---------------------------------------------------------------------------------------------------------------------

KOPSET:     LD HL,(CHANS)
            JR DETOHL


; ---------------------------------------------------------------------------------------------------------------------
; EDKPX -- toggle the keypad between function keys and digits
; ---------------------------------------------------------------------------------------------------------------------

EDKPX:      LD HL,KPFLG
            INC (HL)                    ; Only bit 0 is tested, so incrementing flips the mode
            RET


; ---------------------------------------------------------------------------------------------------------------------
; EDDLR / EDDLL -- delete right and left
;
; Deletes both bytes of a function token. When the byte before the deletion point is a colour control code, the code
; is deleted first and the cursor left pointing past its parameter, so the next press removes that too.
; ---------------------------------------------------------------------------------------------------------------------

EDDLR:      LD A,(HL)
            CP CC_ENTER
            JR NZ,EDDLC

            RET                         ; Nothing to the right of the line end

EDDLL:      CALL EDLT                   ; Move left, then delete at the new position
            RET C                       ; Already at the start of the line

EDDLC:      LD BC,2                     ; Assume a two-byte function token
            LD A,(HL)
            INC A
            JR Z,EDDL3                  ; It is one, so delete the &FF and its code together

; --- CARET: delete a single byte at (HL). Also called by LOCAL. ---

CARET:      DEC C                       ; Just one byte after all
            DEC HL
            LD A,(HL)                   ; The character before it -- possibly the VARSTERM byte
            INC HL
            CP CC_OVER+1
            JR NC,EDDL3                 ; Above OVER, so an ordinary character

            CP CC_INK
            JR C,EDDL3                  ; Below INK, so an ordinary character

            INC HL                      ; A colour code precedes this byte, so this byte is its parameter
            LD (KCUR),HL                ; Leave the cursor past the parameter, to be deleted next time
            DEC HL
            DEC HL                      ; Delete the control code now instead

EDDL3:      JP RECLAIM2


; ---------------------------------------------------------------------------------------------------------------------
; EDENT -- ENTER: leave the editor
;
; Discards the editor loop and warning-buzz frames so that control returns to whatever called EDITOR.
; ---------------------------------------------------------------------------------------------------------------------

EDENT:      POP AF                      ; Discard the EDLP return
            POP AF                      ; Discard the WARNBZ return

ERRCHK:     POP HL                      ; The caller's ERRSP, stacked by EDITOR

RESESP:     LD (ERRSP),HL
            LD A,(ERRNR)
            AND A
            RET Z                       ; No error outstanding

            LD SP,HL
            RET                         ; Unwind to the error handler instead of returning normally


; =====================================================================================================================
; Control code parameter handling
; =====================================================================================================================
;
; A colour control code needs the byte or two that follow it. Rather than buffer them, the print routine temporarily
; rewrites the channel's output address, so the next characters printed are captured instead of displayed.
; ---------------------------------------------------------------------------------------------------------------------

RESTOP:     LD DE,(OPSTORE)             ; Restore the saved output address

POCHNG:     LD HL,(CURCHL)

DETOHL:     LD (HL),E                   ; Store DE at (HL)
            INC HL
            LD (HL),D
            RET

PRERESTOP:  LD DE,CCRESTOP              ; Two-operand code: capture the second one too
            LD (TVDATA+1),A             ; Save the first operand
            JR POCHNG


; ---------------------------------------------------------------------------------------------------------------------
; CUOP -- special output routine used by cursor up and down
;
; Called for each character as the line is re-printed; when the screen position reaches the wanted one it records
; the corresponding address within the line in KCUR.
; ---------------------------------------------------------------------------------------------------------------------

CUOP:       RST &30
            DW CUOPP-&8000


; ---------------------------------------------------------------------------------------------------------------------
; WARNBZ / RSPNS / NOISE -- editor sounds
;
; WARNBZ reports an editing error as a buzz, but only on the lower screen; elsewhere the error is passed on.
; ---------------------------------------------------------------------------------------------------------------------

WARNBZ:     LD A,(DEVICE)
            DEC A
            JR NZ,ERRCHK                ; Not the lower screen, so report the error properly

; --- RSPNS: the rasp made when a line is refused ---

RSPNS:      LD H,7                      ; Pitch
            XOR A
            LD (ERRNR),A                ; Cancel the error
            LD A,(RASP)
            JR NS2

; --- NOISE: the click made on each keypress ---

NOISE:      LD HL,250                   ; Pitch
            LD A,(PIP)

NS2:        LD E,A                      ; Duration
            LD D,0

BEEPER:     RST &30
            DW BEEPP2-&8000


; ---------------------------------------------------------------------------------------------------------------------
; CLEARSP -- empty the edit line or the INPUT line
;
; Reclaims ELINE to WORKSP-1 in edit mode, or WORKSP to WKEND-1 in INPUT mode, then resets the cursor.
; ---------------------------------------------------------------------------------------------------------------------

CLEARSP:    CALL SETDE
            JR Z,CLRSP2                 ; Edit mode

            LD HL,(WKEND)               ; INPUT mode
            JR CLRSP3

CLRSP2:     LD HL,(WORKSP)
            DEC HL                      ; Stop short of the CR that terminates ELINE

CLRSP3:     DEC HL
            CALL RECLAIM1

SETKC:      IN A,(URPORT)

SETKC2:     AND LMPRPAGE
            LD (KCURP),A
            LD (KCUR),HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; SETDE -- find the start of the line being edited
;
; Exit:   DE -> the start of ELINE (with Z set) in edit mode, or of the INPUT line in workspace (NZ).
;         HL is preserved.
; ---------------------------------------------------------------------------------------------------------------------

SETDE:      PUSH HL
            LD A,(FLAGX)
            AND FFLXINPUT
            JR NZ,SETDE2

            CALL ADDRELN
            CP A                        ; Force Z for "edit mode"

SETDE2:     PUSH AF
            CALL NZ,ADDRWK
            EX DE,HL

; --- PPRET: pop AF, pop HL, return. Also used by DEF KEYCODE. ---

PPRET:      POP AF
            POP HL
            RET


; ---------------------------------------------------------------------------------------------------------------------
; LNNM -- read the line number a pointer refers to
;
; Entry:  HL -> a line number, DE -> the previous line
; Exit:   DE = the line number.
; Notes:  If HL has reached the program terminator the previous line's number is returned instead, and if there is
;         no program at all DE comes back zero.
; ---------------------------------------------------------------------------------------------------------------------

LNNM:       LD A,(HL)
            INC A
            JR NZ,LNNM2                 ; Not the terminator

            EX DE,HL                    ; Fall back to the previous line
            LD A,(HL)
            INC A
            LD D,A
            LD E,A
            RET Z                       ; No program: DE = 0

LNNM2:      LD D,(HL)                   ; Line numbers are stored most significant byte first
            INC HL
            LD E,(HL)
            RET


; ---------------------------------------------------------------------------------------------------------------------
; GTKBK / WKBR -- wait for a key, honouring BREAK
;
; GTKBK flushes any queued keys first, so a key pressed earlier cannot satisfy the wait. Used by the scroll prompt
; and by SAVE.
; ---------------------------------------------------------------------------------------------------------------------

GTKBK:      CALL KBFLUSH

WKBR:       CALL BRKCR                  ; Stop if BREAK is pressed
            CALL KYIP2
            JR Z,WKBR

            RET


; ---------------------------------------------------------------------------------------------------------------------
; WAITKEY -- wait for a key through the current channel
;
; Exit:   A = the key code.
; Notes:  Raises "End of file" if the channel reports that no more input is available. TVFLAG bit 3 is set so the
;         edit line is printed to the lower screen on the first call.
; ---------------------------------------------------------------------------------------------------------------------

WAITKEY:    LD HL,TVFLAG
            LD A,(HL)
            AND FTVCLRLS
            JR NZ,WTKY2                 ; The lower screen is about to be cleared anyway

            SET 3,(HL)                  ; FTVCOPYLINE: print the line on the first call to the input routine

WTKY2:      CALL INPUTAD                ; Call the channel's input routine, usually KYIP below
            RET C                       ; Got a key

            JR Z,WTKY2                  ; No key and no error, so keep waiting

            RST &08
            DB ERR_ENDOFFILE


; ---------------------------------------------------------------------------------------------------------------------
; KYIP / KYIP2 -- the keyboard input routine
;
; Installed in every channel that accepts keyboard input.
;
; Exit:   CY        A = the key code
;         NC, Z     no key available
;         NC, NZ    end of file
;
; Codes &10-&15 are colour controls that need a parameter. Rather than wait here, the routine returns the code and
; redirects the channel's input address to KYPM, so the next key is range-checked as that code's parameter.
; ---------------------------------------------------------------------------------------------------------------------

KYIP:       LD A,(TVFLAG)
            AND FTVCOPYLINE
            CALL NZ,EDPRT               ; Print the line to the lower screen if it is pending

; --- KYIP2: fetch a key without the line printing. Also used by GET. ---

KYIP2:      LD HL,FLAGS
            AND A                       ; NC
            BIT 5,(HL)
            RET Z                       ; FFLAGKEY clear: no key waiting

            LD A,(LASTK)
            RES 5,(HL)                  ; Consume it
            PUSH AF
            INC HL                      ; -> TVFLAG
            BIT 5,(HL)
            CALL NZ,CLSLOWER            ; FTVCLRLS: the first keypress clears the lower screen
            POP AF
            CP CC_AT
            CCF
            RET C                       ; &16 and above are accepted as they stand

            CP 6
            JR Z,KYCL                   ; CHR$ 6 doubles as the caps lock key

            CP CC_INK
            RET C                       ; &00-&0F are accepted as they stand

            LD (KDATA),A                ; &10-&15: remember the control code
            LD DE,KYPM
            JR KYCZ                     ; Return it now, and validate the next key as its parameter


; ---------------------------------------------------------------------------------------------------------------------
; KYPM -- temporary input routine that validates a colour parameter
; ---------------------------------------------------------------------------------------------------------------------

KYPM:       LD HL,FLAGS
            LD A,(HL)
            AND FFLAGKEY
            RET Z                       ; NC, Z: still waiting

            LD A,(LASTK)
            RES 5,(HL)                  ; Consume the key
            SUB "0"
            JR C,KYPN                   ; Only digits are acceptable

            CP 8
            JR NC,KYPN                  ; Limit to 0-7

            LD B,A
            LD A,(KDATA)                ; The control code this parameter belongs to
            CP CC_FLASH
            JR C,KYPM6                  ; INK or PAPER: 0-7 are all valid

            CP CC_OVER
            LD A,B
            JR Z,KYPM5                  ; OVER

            CP 2
            JR NC,KYPN                  ; FLASH, BRIGHT and INVERSE take only 0 or 1

KYPM5:      CP 4
            JR NC,KYPN                  ; OVER takes 0-3

KYPM6:      LD A,B                      ; Accept the parameter
            LD DE,(MNIP)                ; Restore the normal input routine

KYCZ:       SCF
            LD HL,(CHANS)               ; Patch the input address of channel K
            INC HL
            INC HL
            JP DETOHL

KYCL:       LD HL,FLAGS2
            LD A,(HL)
            XOR FFL2CAPS                ; Toggle caps lock
            LD (HL),A

            LD HL,TVFLAG
            SET 3,(HL)                  ; FTVCOPYLINE: redraw the line so the cursor changes shape

KYPN:       CP A                        ; NC, Z: report "no key"
            RET


; ---------------------------------------------------------------------------------------------------------------------
; EDPRT -- print the edit or INPUT line to the lower screen
; ---------------------------------------------------------------------------------------------------------------------

EDPRT:      RST &30
            DW EDPTR2-&8000


; ---------------------------------------------------------------------------------------------------------------------
; FONOP -- force normal output
;
; Used by the cursor drawing code, so that a cursor printed between a control code and its parameter still appears
; rather than being swallowed as the parameter.
; ---------------------------------------------------------------------------------------------------------------------

FONOP:      RST &30
            DW FONOP2-&8000


; ---------------------------------------------------------------------------------------------------------------------
; AULN -- automatic line numbering
;
; If AUTO is active and the edit line is empty, prints the next line number into it through channel R.
; ---------------------------------------------------------------------------------------------------------------------

AULN:       LD A,(FLAGX)
            AND FFLXINPUT
            RET NZ                      ; Not in INPUT mode

            LD A,(AUTOFLG)
            AND A
            RET Z                       ; AUTO is off

            CALL ADDRELN
            LD A,(HL)
            CP CC_ENTER
            RET NZ                      ; The line already has something in it

            LD HL,(EPPC)
            LD BC,(AUTOSTEP)
            ADD HL,BC
            LD A,H
            CP &FF
            RET Z                       ; The next number would exceed the maximum

            PUSH HL
            LD A,&FF
            CALL SETSTRM                ; Channel R: printing inserts into the edit line
            POP BC
            RST &30
            DW PRNUMB1

STRM0:      XOR A                       ; Select stream 0
            JP SETSTRM


; ---------------------------------------------------------------------------------------------------------------------
; FNDKYD / DKTR -- find a DEF KEY definition
;
; Definitions are stored consecutively from (DKDEF) as: key code, 16-bit length, text. A code byte of &FF ends the
; list.
;
; Entry:  FNDKYD with A = the key code, 192-255; DKTR to locate the terminator instead.
; Exit:   NC  HL -> the definition text, BC = its length, D = the key code
;         CY  no definition for that key; HL points three bytes past the terminator
; Uses:   AF, BC, D, HL
; ---------------------------------------------------------------------------------------------------------------------

DKTR:       LD A,&FF                    ; Searching for the terminator finds the end of the list

FNDKYD:     LD D,A
            LD HL,(DKDEF)

FDKL:       LD A,(HL)                   ; Key code
            INC HL
            LD C,(HL)
            INC HL
            LD B,(HL)                   ; BC = length
            INC HL
            ADD A,1
            RET C                       ; &FF: the end of the list

            DEC A
            CP D
            RET Z                       ; Found

            ADD HL,BC                   ; Step over the text to the next definition
            JR FDKL


; ---------------------------------------------------------------------------------------------------------------------
; KSCHK -- Z if the current channel is K or S
;
; Used by the editor and INPUT to decide whether interactive editing is possible on this channel.
; ---------------------------------------------------------------------------------------------------------------------

KSCHK:      LD A,(CLET)
            CP "K"
            RET Z

            CP "S"
            RET
