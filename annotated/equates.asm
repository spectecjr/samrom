; =====================================================================================================================
; EQUATES.ASM -- Named constants for the SAM Coupe ROM 3.0
; =====================================================================================================================
;
; This file is new in the annotated build. It gives names to the magic numbers that the original source spelled out as
; bare literals: error codes, BASIC token values, hardware paging bits, system-variable flag bits, and the various
; small enumerations the interpreter uses internally.
;
; It contains EQU definitions only, so it emits no bytes and can be included first without altering the ROM image.
;
; Naming conventions used throughout the annotated build:
;
;   ERR_xxx     Error / report code, as passed in the byte following RST &08.
;   HOOK_xxx    DOS hook code (also passed via RST &08, values >= 128).
;   TOK_xxx     BASIC keyword token as stored in a tokenised program line.
;   FN_xxx      Function code as stored after the &FF function prefix.
;   F_xxx       Bit mask for a named flag byte (F<var>_<meaning>).
;   LMPR_/HMPR_ Paging port bit values.
;   CC_xxx      Print control code.
;   FT_xxx      Save/load file type.
;
; Legacy names defined in VARS.ASM (SAVETOK, THENTOK, ...) are retained there as aliases of the TOK_ names, so both
; spellings resolve to the same value and older listings remain readable.
;
; =====================================================================================================================


; =====================================================================================================================
; SECTION 1 -- Paging hardware
; =====================================================================================================================
;
; The Z80's 64K space is four 16K sections. LMPR (port &FA) controls sections A and B plus ROM visibility; HMPR
; (port &FB, called URPORT in the original source) controls sections C and D.
;
;   Section A  &0000-&3FFF   ROM0, or LMPR page when ROM0 is disabled
;   Section B  &4000-&7FFF   LMPR page + 1  (the system page in normal operation)
;   Section C  &8000-&BFFF   HMPR page
;   Section D  &C000-&FFFF   HMPR page + 1, or ROM1 when enabled
; ---------------------------------------------------------------------------------------------------------------------

LMPRPAGE:   EQU %00011111       ; Mask for the page number field of LMPR / HMPR (0-31)
LMPRROM0:   EQU %00100000       ; LMPR bit 5: set = DISABLE ROM0 (RAM at &0000 instead)
LMPRROM1:   EQU %01000000       ; LMPR bit 6: set = ENABLE  ROM1 at &C000
LMPRNOR1:   EQU %10111111       ; AND mask that clears LMPR bit 6, i.e. pages ROM1 out

; The system page value written to LMPR during normal operation. Page 31 wraps so that section B holds physical page 0
; (the system page) while ROM0 remains visible in section A.
LMPRSYS:    EQU LMPRPAGE                    ; &1F -- ROM0 on, ROM1 off, system page at &4000
LMPRSYSR1:  EQU LMPRPAGE + LMPRROM1         ; &5F -- as above but with ROM1 also paged in at &C000

; ---------------------------------------------------------------------------------------------------------------------
; Video / screen page bits, as stored in CUSCRNP, FISCRNP and SCLIST and written to VIDPORT.
; ---------------------------------------------------------------------------------------------------------------------

VIDPAGE:    EQU %00011111       ; Screen page number field
VIDMODE:    EQU %01100000       ; Screen mode field (internal mode << 5)
VIDMIDI:    EQU %10000000       ; MIDI-through bit (low = inactive)
VIDNOTMD:   EQU %10011111       ; AND mask preserving everything except the mode field


; =====================================================================================================================
; SECTION 2 -- Error and report codes
; =====================================================================================================================
;
; Raised with:    RST &08
;                 DB  ERR_xxx
;
; The handler (ERROR2 in MISC2.ASM) never returns: it stores the code in ERRNR and resets SP from ERRSP. Codes >= 128
; are DOS hook codes rather than errors and may return -- see section 3.
;
; The message text for each code lives in the ERRMVAL table in TEXT.ASM, in this same order.
; ---------------------------------------------------------------------------------------------------------------------

ERR_OK:         EQU 0           ; "OK"                            -- normal end of a program
ERR_NOMEM:      EQU 1           ; "Out of memory"
ERR_NOTFOUND:   EQU 2           ; "<name> not found"              -- undefined variable; handler prints the name
ERR_DATADONE:   EQU 3           ; "DATA has all been read"
ERR_SUBSCRIPT:  EQU 4           ; "Subscript wrong"
ERR_NEXTNOFOR:  EQU 5           ; "NEXT without FOR"
ERR_FORNONEXT:  EQU 6           ; "FOR without NEXT"
ERR_FNNODEF:    EQU 7           ; "FN without DEF FN"             -- call buffer unresolved by the compile pass
ERR_RETNOGOSUB: EQU 8           ; "RETURN without GOSUB"
ERR_NOLOOP:     EQU 9           ; "Missing LOOP"
ERR_LOOPNODO:   EQU 10          ; "LOOP without DO"
ERR_NOPOPDATA:  EQU 11          ; "No POP data"                   -- BASIC stack empty
ERR_NODEFPROC:  EQU 12          ; "Missing DEF PROC"
ERR_NOENDPROC:  EQU 13          ; "No END PROC"
ERR_BRKCONT:    EQU 14          ; "BREAK - CONTINUE to repeat"    -- BREAK during I/O; statement will be re-run
ERR_BRKINTO:    EQU 15          ; "BREAK into program"            -- BREAK between statements
ERR_STOPSTMT:   EQU 16          ; "STOP statement"
ERR_STOPINPUT:  EQU 17          ; "STOP in INPUT"
ERR_BADFILENM:  EQU 18          ; "Invalid file name"
ERR_LOADING:    EQU 19          ; "Loading error"                 -- tape/net parity or timing failure
ERR_BADDEVICE:  EQU 20          ; "Invalid device"
ERR_BADSTREAM:  EQU 21          ; "Invalid stream number"
ERR_ENDOFFILE:  EQU 22          ; "End of file"
ERR_BADCOLOUR:  EQU 23          ; "Invalid colour"
ERR_BADPALETTE: EQU 24          ; "Invalid palette colour"
ERR_PALFULL:    EQU 25          ; "Too many palette changes"      -- LINICOLS table full
ERR_PARAMETER:  EQU 26          ; "Parameter error"               -- PROC argument count/type mismatch
ERR_BADARG:     EQU 27          ; "Invalid argument"
ERR_NUMTOOBIG:  EQU 28          ; "Number too large"              -- FP overflow, or literal out of range
ERR_NONSENSE:   EQU 29          ; "Not understood"                -- the general syntax error
ERR_IOOR:       EQU 30          ; "Integer out of range"
ERR_NOSTMT:     EQU 31          ; "Statement doesn't exist"
ERR_OFFSCREEN:  EQU 32          ; "Off screen"
ERR_NOROOMLINE: EQU 33          ; "No room for line"
ERR_BADMODE:    EQU 34          ; "Invalid screen mode"
ERR_BADBLITZ:   EQU 35          ; "Invalid BLITZ code"
ERR_AREATOOBIG: EQU 36          ; "Stored area too big"           -- GRAB/ROLL strip exceeds the 8K buffer
ERR_BADPUTBLK:  EQU 37          ; "Invalid PUT block"
ERR_PUTMASK:    EQU 38          ; "PUT mask mismatch"
ERR_NOENDIF:    EQU 39          ; "Missing END IF"
ERR_BADVARNAME: EQU 40          ; "Invalid variable name"         -- string/array name longer than 10 characters
ERR_BSTKFULL:   EQU 41          ; "BASIC stack full"
ERR_STRTOOLONG: EQU 42          ; "String too long"
ERR_BADSCRNUM:  EQU 43          ; "Invalid screen number"
ERR_SCROPEN:    EQU 44          ; "Screen is already open"
ERR_STRMOPEN:   EQU 45          ; "Stream is already open"
ERR_CURSCREEN:  EQU 46          ; "Current screen"                -- cannot close the screen in use
ERR_STRMSHUT:   EQU 47          ; "Stream is not open"
ERR_BADCLEAR:   EQU 48          ; "Invalid CLEAR address"
ERR_BADNOTE:    EQU 49          ; "Invalid Note"
ERR_NOTETOOLNG: EQU 50          ; "Note too long"
ERR_FPC:        EQU 51          ; "FPC error"                     -- unrecognised calculator opcode
ERR_TOOMANYDEF: EQU 52          ; "Too many definitions"          -- more than 170 DEF FNs
ERR_NODOS:      EQU 53          ; "No DOS"
ERR_BADWINDOW:  EQU 54          ; "Invalid WINDOW"
ERR_NODISC:     EQU 55          ; "Missing disk"

ERR_BANNER:     EQU &50         ; Not an error: prints the MGT copyright banner and waits for a keypress. Used by
                                ; MNINIT and NEW as their final action.

ERR_DOSBASE:    EQU &51         ; Codes &51 and up are DOS errors; their text comes from the DOS page, not ERRMVAL.


; =====================================================================================================================
; SECTION 3 -- DOS hook codes
; =====================================================================================================================
;
; Also raised via RST &08, but codes >= 128 are passed to the resident DOS rather than treated as errors, and control
; can return to the caller. Without a DOS these raise ERR_NODOS.
; ---------------------------------------------------------------------------------------------------------------------

HOOK_BOOT:      EQU 128         ; Boot; DOS may ignore this or treat it as HOOK_AUTOLOAD
HOOK_OPEN:      EQU 129         ; Open a file for reading and return its header (IX -> HDR)
HOOK_LOAD:      EQU 130         ; Load the file body
HOOK_VERIFY:    EQU 131         ; Verify the file body against memory
HOOK_SAVE:      EQU 132         ; Save header and body
HOOK_OPENSTRM:  EQU 134         ; Open a stream onto a DOS channel
HOOK_CLOSESTRM: EQU 135         ; Close a stream; the channel letter is at HDR+1
HOOK_AUTOLOAD:  EQU 136         ; Load and run the disc's auto-load file (issued by BOOT)
HOOK_DIR:       EQU 137         ; Directory listing
HOOK_DVAR:      EQU 139         ; DVAR function -- DOS stacks the address of its own variables
HOOK_EOF:       EQU 140         ; EOF function
HOOK_PTR:       EQU 141         ; PTR function
HOOK_PATH:      EQU 142         ; PATH$ function

; Values placed in E by the DOS when it re-enters the ROM's common save/load code.
DOSRET_LOAD:    EQU 1           ; Resume at LDFL -- load the body of an already-opened file
DOSRET_SAVE:    EQU 2           ; Resume at SVFL -- save the whole file
DOSRET_LOADALL: EQU 3           ; Resume at LKTH -- find the header, then load the body


; =====================================================================================================================
; SECTION 4 -- BASIC tokens
; =====================================================================================================================
;
; Single-byte tokens occupy &85-&FE and are stored directly in the program line. Functions and the alphabetic operators
; are stored as the two-byte sequence &FF followed by an FN_ code in the range &3B-&83.
;
; Outside quotes these same byte values would otherwise be UDG characters; the print routines resolve the ambiguity
; from the in-quotes flag. See docs/tokenized-program-format.md.
; ---------------------------------------------------------------------------------------------------------------------

TOK_FNPREFIX:   EQU &FF         ; Prefix byte introducing a two-byte function/operator token

; --- Qualifiers, &85-&8F ---------------------------------------------------------------------------------------------

TOK_USING:      EQU &85
TOK_WRITE:      EQU &86
TOK_AT:         EQU &87
TOK_TAB:        EQU &88
TOK_OFF:        EQU &89
TOK_WHILE:      EQU &8A
TOK_UNTIL:      EQU &8B
TOK_LINE:       EQU &8C
TOK_THEN:       EQU &8D         ; Also used internally as the "no intervening token" null value in searches
TOK_TO:         EQU &8E
TOK_STEP:       EQU &8F

; --- Commands, &90-&FE -----------------------------------------------------------------------------------------------

TOK_DIR:        EQU &90         ; Reserved for DOS -- CMDADT entry is NONSENSE
TOK_FORMAT:     EQU &91         ; Reserved for DOS
TOK_ERASE:      EQU &92         ; Reserved for DOS
TOK_MOVE:       EQU &93         ; Reserved for DOS
TOK_SAVE:       EQU &94
TOK_LOAD:       EQU &95
TOK_MERGE:      EQU &96
TOK_VERIFY:     EQU &97
TOK_OPEN:       EQU &98
TOK_CLOSE:      EQU &99
TOK_CIRCLE:     EQU &9A
TOK_PLOT:       EQU &9B
TOK_LET:        EQU &9C
TOK_BLITZ:      EQU &9D
TOK_BORDER:     EQU &9E
TOK_CLS:        EQU &9F
TOK_PALETTE:    EQU &A0
TOK_PEN:        EQU &A1         ; Typing INK also produces this token
TOK_PAPER:      EQU &A2
TOK_FLASH:      EQU &A3
TOK_BRIGHT:     EQU &A4
TOK_INVERSE:    EQU &A5
TOK_OVER:       EQU &A6
TOK_FATPIX:     EQU &A7
TOK_CSIZE:      EQU &A8
TOK_BLOCKS:     EQU &A9
TOK_MODE:       EQU &AA
TOK_GRAB:       EQU &AB
TOK_PUT:        EQU &AC
TOK_BEEP:       EQU &AD
TOK_SOUND:      EQU &AE
TOK_NEW:        EQU &AF
TOK_RUN:        EQU &B0
TOK_STOP:       EQU &B1
TOK_CONTINUE:   EQU &B2
TOK_CLEAR:      EQU &B3
TOK_GOTO:       EQU &B4
TOK_GOSUB:      EQU &B5
TOK_RETURN:     EQU &B6
TOK_REM:        EQU &B7         ; Tokenising stops for the rest of the line after this
TOK_READ:       EQU &B8
TOK_DATA:       EQU &B9
TOK_RESTORE:    EQU &BA
TOK_PRINT:      EQU &BB
TOK_LPRINT:     EQU &BC
TOK_LIST:       EQU &BD
TOK_LLIST:      EQU &BE
TOK_DUMP:       EQU &BF
TOK_FOR:        EQU &C0
TOK_NEXT:       EQU &C1
TOK_PAUSE:      EQU &C2
TOK_DRAW:       EQU &C3
TOK_DEFAULT:    EQU &C4
TOK_DIM:        EQU &C5
TOK_INPUT:      EQU &C6
TOK_RANDOMIZE:  EQU &C7
TOK_DEFFN:      EQU &C8
TOK_DEFKEYCODE: EQU &C9
TOK_DEFPROC:    EQU &CA
TOK_ENDPROC:    EQU &CB
TOK_RENUM:      EQU &CC
TOK_DELETE:     EQU &CD
TOK_REF:        EQU &CE
TOK_COPY:       EQU &CF
                                ; &D0 unused
TOK_KEYIN:      EQU &D1
TOK_LOCAL:      EQU &D2
TOK_LOOPIF:     EQU &D3
TOK_DO:         EQU &D4
TOK_LOOP:       EQU &D5
TOK_EXITIF:     EQU &D6
TOK_LIF:        EQU &D7         ; "IF" as produced by the tokeniser (long/block form)
TOK_SIF:        EQU &D8         ; "IF" rewritten in place by the syntax check when THEN follows (short form)
TOK_LELSE:      EQU &D9         ; "ELSE" as produced by the tokeniser (long/block form)
TOK_ELSE:       EQU &DA         ; "ELSE" rewritten in place when the preceding IF on the line was short
TOK_ENDIF:      EQU &DB
TOK_KEY:        EQU &DC
TOK_ONERROR:    EQU &DD
TOK_ON:         EQU &DE
TOK_GET:        EQU &DF
TOK_OUT:        EQU &E0
TOK_POKE:       EQU &E1
TOK_DPOKE:      EQU &E2
TOK_RENAME:     EQU &E3         ; Reserved for DOS
TOK_CALL:       EQU &E4
TOK_ROLL:       EQU &E5
TOK_SCROLL:     EQU &E6
TOK_SCREEN:     EQU &E7
TOK_DISPLAY:    EQU &E8
TOK_BOOT:       EQU &E9
TOK_LABEL:      EQU &EA
TOK_FILL:       EQU &EB
TOK_WINDOW:     EQU &EC
TOK_AUTO:       EQU &ED
TOK_POP:        EQU &EE
TOK_RECORD:     EQU &EF
TOK_DEVICE:     EQU &F0
TOK_PROTECT:    EQU &F1         ; Reserved for DOS
TOK_HIDE:       EQU &F2         ; Reserved for DOS
TOK_ZAP:        EQU &F3
TOK_POW:        EQU &F4
TOK_BOOM:       EQU &F5
TOK_ZOOM:       EQU &F6         ; Last implemented command; &F7-&FE are unused

TOK_CMDFIRST:   EQU &90         ; First command token -- CMDADT is indexed by (token - TOK_CMDFIRST) * 2
TOK_CMDLAST:    EQU &F7         ; One past the last command with a CMDADT entry

; --- Function / operator codes following the &FF prefix, &3B-&83 -------------------------------------------------------
;
; The expression evaluator subtracts &1A from these to index its own tables; that adjusted value never appears in a
; stored program.
; ---------------------------------------------------------------------------------------------------------------------

FN_PI:          EQU &3B
FN_RND:         EQU &3C
FN_POINT:       EQU &3D
FN_FREE:        EQU &3E
FN_LENGTH:      EQU &3F
FN_ITEM:        EQU &40
FN_ATTR:        EQU &41
FN_FN:          EQU &42
FN_BIN:         EQU &43
FN_XMOUSE:      EQU &44
FN_YMOUSE:      EQU &45
FN_XPEN:        EQU &46
FN_YPEN:        EQU &47
FN_RAMTOP:      EQU &48
                                ; &49 unused (INARRAY)
FN_INSTR:       EQU &4A         ; Boundary: codes below this yield numbers, above yield strings
FN_INKEYS:      EQU &4B
FN_SCREENS:     EQU &4C
FN_MEMS:        EQU &4D
                                ; &4E unused (CHAR$)
FN_PATHS:       EQU &4F
FN_STRINGS:     EQU &50
                                ; &51 unused (USING$), &52 unused (SHIFT$)
FN_SIN:         EQU &53         ; First function handled by the FP calculator rather than immediately
FN_COS:         EQU &54
FN_TAN:         EQU &55
FN_ASN:         EQU &56
FN_ACS:         EQU &57
FN_ATN:         EQU &58
FN_LN:          EQU &59
FN_EXP:         EQU &5A
FN_ABS:         EQU &5B
FN_SGN:         EQU &5C
FN_SQR:         EQU &5D
FN_INT:         EQU &5E
FN_USR:         EQU &5F
FN_IN:          EQU &60
FN_PEEK:        EQU &61
FN_DPEEK:       EQU &62
FN_DVAR:        EQU &63
FN_SVAR:        EQU &64
FN_BUTTON:      EQU &65
FN_EOF:         EQU &66
FN_PTR:         EQU &67
                                ; &68 unused
FN_UDG:         EQU &69
                                ; &6A unused
FN_LEN:         EQU &6B
FN_CODE:        EQU &6C
FN_VALS:        EQU &6D
FN_VAL:         EQU &6E
FN_TRUNCS:      EQU &6F
FN_CHRS:        EQU &70
FN_STRS:        EQU &71
FN_BINS:        EQU &72
FN_HEXS:        EQU &73
FN_USRS:        EQU &74
                                ; &75 unused
FN_NOT:         EQU &76
                                ; &77-&79 unused
FN_MOD:         EQU &7A         ; First alphabetic binary operator
FN_DIV:         EQU &7B
FN_BOR:         EQU &7C
                                ; &7D unused (BXOR)
FN_BAND:        EQU &7E
FN_OR:          EQU &7F
FN_AND:         EQU &80         ; Last operator that lists with spaces on both sides
FN_NOTEQ:       EQU &81         ; "<>"  -- these three list with no surrounding spaces
FN_LESSEQ:      EQU &82         ; "<="
FN_GRTREQ:      EQU &83         ; ">="


; =====================================================================================================================
; SECTION 5 -- System variable flag bits
; =====================================================================================================================

; --- FLAGS (&5C3B) ----------------------------------------------------------------------------------------------------

FFLAGRUN:       EQU %10000000   ; Bit 7: running a program (clear = syntax-checking a line)
FFLAGNUM:       EQU %01000000   ; Bit 6: last expression result was numeric (clear = string)
FFLAGKEY:       EQU %00100000   ; Bit 5: a new key is waiting in LASTK
FFLAGNOSP:      EQU %00000001   ; Bit 0: previous character was a space, so no leading space needed before a keyword

; --- TVFLAG (&5C3C) ---------------------------------------------------------------------------------------------------

FTVCLRLS:       EQU %00100000   ; Bit 5: clear the lower screen on the next keystroke
FTVAUTOLIST:    EQU %00010000   ; Bit 4: an AUTOLIST is in progress
FTVCOPYLINE:    EQU %00001000   ; Bit 3: the edit line needs printing to the lower screen
FTVLOWER:       EQU %00000001   ; Bit 0: output is going to the lower screen

; --- FLAGS2 (&5C6A) ---------------------------------------------------------------------------------------------------

FFL2CAPS:       EQU %00001000   ; Bit 3: caps lock engaged
FFL2DIRTY:      EQU %00000001   ; Bit 0: the screen is not clear

; --- FLAGX (&5C71) ----------------------------------------------------------------------------------------------------

FFLXINPLINE:    EQU %10000000   ; Bit 7: an INPUT LINE is in progress (accept raw text, print codes as UDGs)
FFLXINPUT:      EQU %00100000   ; Bit 5: INPUT mode -- the editor is working in workspace, not the edit line
FFLXNEWVAR:     EQU %00000001   ; Bit 0: the variable just looked up does not exist yet

; --- INQUFG (VAR2+&BA) -------------------------------------------------------------------------------------------------

FINQUOTES:      EQU %00000001   ; Bit 0: inside a string literal, so token bytes print as UDGs instead of keywords

; --- ONERRFLG (VAR2+&145) ----------------------------------------------------------------------------------------------

FONERRTEMP:     EQU %10000000   ; Bit 7: armed for the next error (cleared when it fires)
FONERRPERM:     EQU %00000001   ; Bit 0: ON ERROR is permanently enabled
FONERRBOTH:     EQU FONERRTEMP + FONERRPERM


; =====================================================================================================================
; SECTION 6 -- Variable type/length bytes
; =====================================================================================================================
;
; Every variable record starts with a type/length byte. The meaning of bits 6 and 5 differs between the numeric chains
; and the string/array area.
; ---------------------------------------------------------------------------------------------------------------------

TLHIDDEN:       EQU %10000000   ; Bit 7: hidden -- a global shadowed by a PROC local
TLFORVAR:       EQU %01000000   ; Bit 6 (numerics): FOR control variable; record carries limit/step/loop address
TLSTRARRAY:     EQU %01000000   ; Bit 6 (strings): string array, or a sliced string reference
TLUNUSED:       EQU %00100000   ; Bit 5 (numerics): slot no longer in use and available for re-use
TLNUMARRAY:     EQU %00100000   ; Bit 5 (strings): numeric array
TLNAMELEN:      EQU %00011111   ; Bits 4-0: name length (minus one for numerics, actual length for strings/arrays)
TLARRAY:        EQU TLSTRARRAY + TLNUMARRAY     ; Mask testing "is an array of either kind"

MAXNAMELEN:     EQU 10          ; Longest permitted string/array name; longer raises ERR_BADVARNAME
NUMVALSIZE:     EQU 5           ; Bytes in a numeric value (and in every FP calculator stack entry)
STRHDRSIZE:     EQU 14          ; Bytes of header on a string/array record: type + 10 name + 3 length


; =====================================================================================================================
; SECTION 7 -- BASIC stack frame types
; =====================================================================================================================
;
; Frames are four bytes: type|page, line address (2), statement number. The type occupies the top three bits of the
; page byte so RETLOOP can match on it with AND %11100000.
; ---------------------------------------------------------------------------------------------------------------------

BSTKGOSUB:      EQU %00000000   ; GOSUB return frame
BSTKPROC:       EQU %01000000   ; PROC return frame
BSTKDO:         EQU %10000000   ; DO loop frame
BSTKTYPE:       EQU %11100000   ; Mask isolating the type field
BSTKFRAME:      EQU 4           ; Bytes per frame
BSTKMCSTAT:     EQU &FF         ; Statement number used by CALBAS: RETURN sees it and exits to machine code


; =====================================================================================================================
; SECTION 8 -- Page allocation table (ALLOCT) entries
; =====================================================================================================================

PAGEFREE:       EQU &00         ; Page is unallocated
PAGEBASIC:      EQU &40         ; Reserved by BASIC for the current context
PAGEDOS:        EQU &60         ; In use by the resident DOS
PAGESCREEN:     EQU &C0         ; Part of an open screen (screens take two consecutive pages)
PAGEABSENT:     EQU &FF         ; Page not fitted; also the table terminator


; =====================================================================================================================
; SECTION 9 -- Print control codes
; =====================================================================================================================
;
; Codes below &20 embedded in printed output. Those from CC_INK upwards take operand bytes, which the print routine
; collects by temporarily redirecting the channel output address.
; ---------------------------------------------------------------------------------------------------------------------

CC_COMMA:       EQU 6           ; Column tab (the effect of "," in PRINT)
CC_EDIT:        EQU 7           ; EDIT key
CC_LEFT:        EQU 8           ; Cursor left
CC_RIGHT:       EQU 9           ; Cursor right
CC_DOWN:        EQU 10          ; Cursor down
CC_UP:          EQU 11          ; Cursor up
CC_DELLEFT:     EQU 12          ; Delete left
CC_ENTER:       EQU 13          ; Carriage return
CC_DELRIGHT:    EQU 14          ; Delete right
CC_KEYPAD:      EQU 15          ; Function/number keypad toggle
CC_INK:         EQU 16          ; INK n     -- first code taking one operand
CC_PAPER:       EQU 17          ; PAPER n
CC_FLASH:       EQU 18          ; FLASH n
CC_BRIGHT:      EQU 19          ; BRIGHT n
CC_INVERSE:     EQU 20          ; INVERSE n
CC_OVER:        EQU 21          ; OVER n    -- last one-operand code
CC_AT:          EQU 22          ; AT row,col  -- two operands
CC_TAB:         EQU 23          ; TAB col     -- two operands, second discarded
CC_FIRSTPARAM:  EQU CC_INK      ; Range of codes taking operands
CC_LASTPARAM:   EQU CC_TAB
CC_SIGNIF:      EQU &21         ; First "significant" character: RST &18 skips everything below this except CR


; =====================================================================================================================
; SECTION 10 -- Tokenised line structure
; =====================================================================================================================

NUMMARKER:      EQU &0E         ; Marks an invisible 5-byte form. Always followed by exactly 5 bytes, and skipped
                                ; wholesale (6 bytes) by every scanner. Introduces numeric literals, FN/PROC calling
                                ; buffers, and DEF FN parameter slots.
NUMFORMLEN:     EQU 6           ; Total bytes consumed by a marker plus its payload
CALLBUFLEN:     EQU 6           ; Size of an FN/PROC calling buffer (marker + 5)
FNBUFFILL:      EQU &FE         ; Filler byte marking an unresolved FN call buffer
PROCBUFFILL:    EQU &FD         ; Filler byte marking an unresolved PROC call buffer
CALLBUFOK:      EQU &80         ; Set in the page byte once the compile pass has resolved the buffer
CALLBUFBAD:     EQU %00100000   ; Set in the page byte when no matching definition was found
CALLBUFEXT:     EQU %01000000   ; Would mark the target as an external command rather than a DEF PROC. Never set or
                                ; tested by the ROM; see docs/extending-basic.md and docs/dos-and-extensions.md.

PROGTERM:       EQU &FF         ; Byte marking the end of the program (where a line-number MSB would be)
VARSTERM:       EQU &FF         ; Byte marking the end of the string/array area
LINEHDRLEN:     EQU 4           ; Line header: number MSB, number LSB, length LSB, length MSB
MAXLINENUM:     EQU &FEFF       ; Highest legal line number (65279)
MAXLINELEN:     EQU &3F00       ; Line text longer than this raises ERR_NOROOMLINE
MAXTOKENLEN:    EQU 15          ; Characters of a candidate word the tokeniser will try to match


; =====================================================================================================================
; SECTION 11 -- Screen modes and character cells
; =====================================================================================================================
;
; User-facing MODE 1-4 are internal modes 0-3. See docs/font-rendering.md.
; ---------------------------------------------------------------------------------------------------------------------

MODEZX:         EQU 0           ; User MODE 1: 256x192, ZX layout, 8x8 attributes
MODELINEAR:     EQU 1           ; User MODE 2: 256x192, linear layout, 8x1 attributes
MODE4COL:       EQU 2           ; User MODE 3: 512x192, 4 colours -- the only mode with 6-pixel characters
MODE16COL:      EQU 3           ; User MODE 4: 256x192, 16 colours
MODEMAX:        EQU 4           ; Argument limit for the MODE command (1-4 before decrementing)

CELLBYTES:      EQU 8           ; Bytes in a character bitmap, one per scan line
UDGFIRST:       EQU 144         ; First user-defined graphic; the UDG variable points at this character's bitmap
HUDGFIRST:      EQU 169         ; First "high" UDG; the HUDG variable points at this one. See docs/hudg.md
MINCHARHT:      EQU 6           ; Smallest CSIZE height
MAXCHARHT:      EQU 32          ; Largest CSIZE height
DBLHEIGHTAT:    EQU 16          ; CSIZE heights of this or more are drawn double-height
NARROWWIDTH:    EQU 6           ; CSIZE width giving 85 columns in MODE 3
NORMALWIDTH:    EQU 8           ; CSIZE width giving 64 columns in MODE 3, 32 elsewhere

SCRNLENM0:      EQU &1B00       ; Screen data length, internal mode 0
SCRNLENM1:      EQU &3800       ; Screen data length, internal mode 1
SCRNLENM23:     EQU &6000       ; Screen data length, internal modes 2 and 3 (24K, spans two pages)
SCANBYTESM01:   EQU 32          ; Bytes per scan line in internal modes 0 and 1
SCANBYTESM23:   EQU 128         ; Bytes per scan line in internal modes 2 and 3
SCREENHEIGHT:   EQU 192         ; Scan lines

; ROLL/SCROLL directions, as supplied by the user and by the jump-table entry. The numbering is chosen so that the
; two interesting tests are single-bit ones: bit 0 distinguishes the horizontal directions from the vertical ones,
; and bit 2 picks DOWN out of the two verticals (and, as it happens, is also clear for both horizontals).
;
;   1 = %001 LEFT    2 = %010 UP    3 = %011 RIGHT    4 = %100 DOWN

RDIRLEFT:       EQU 1           ; ROLL/SCROLL direction: left
RDIRUP:         EQU 2           ; ROLL/SCROLL direction: up
RDIRRIGHT:      EQU 3           ; ROLL/SCROLL direction: right
RDIRDOWN:       EQU 4           ; ROLL/SCROLL direction: down
RDIRMAX:        EQU 4           ; Highest legal direction
RDIRBITLR:      EQU 0           ; Bit of the direction code that is set for LEFT and RIGHT
RDIRBITDOWN:    EQU 2           ; Bit of the direction code that is set for DOWN

RSROLL:         EQU &FF         ; TEMPB3: wrap the data that falls off the edge back in at the other side
RSSCROLL:       EQU &00         ; TEMPB3: discard it and fill the vacated area with paper

MAXSCREENS:     EQU 16          ; Entries in SCLIST

; SCLIST entries. One byte per screen: bit 7 clear, the internal mode in bits 6-5, and the number of the first of
; the screen's two pages in bits 4-0 (always even). &FF means the screen is not open.

SCLISTPAGE:     EQU %00011111   ; Page number field
SCLISTMODE:     EQU %01100000   ; Internal mode field (mode << 5)
SCLISTFREE:     EQU &FF         ; Screen is closed
PALTABLEN:      EQU &28         ; Bytes in PALTAB: two 16-entry palettes plus mode-2 spares


; =====================================================================================================================
; SECTION 12 -- Save / load
; =====================================================================================================================

FT_BASIC:       EQU 16          ; File type: BASIC program (plus its variables)
FT_NUMARRAY:    EQU 17          ; File type: numeric array
FT_STRARRAY:    EQU 18          ; File type: string array
FT_CODE:        EQU 19          ; File type: raw code
FT_SCREENS:     EQU 20          ; File type: SCREEN$

BLKHEADER:      EQU &01         ; Tape/net block type byte: header block
BLKDATA:        EQU &FF         ; Tape/net block type byte: data block

HDRFLAGINVIS:   EQU %00000001   ; Header flag byte (offset HFG): name not printed while searching
HDRFLAGPROT:    EQU %00000010   ; Header flag byte: protected -- auto-run code cannot be stopped

TPROMPTNAMES:   EQU %00000001   ; TPROMPTS bit 0: suppress file names during LOAD
TPROMPTSAVE:    EQU %00000010   ; TPROMPTS bit 1: suppress prompts during SAVE


; =====================================================================================================================
; SECTION 13 -- Assorted opcode literals used as data
; =====================================================================================================================
;
; The original source is full of one-byte opcodes used as jumps over the following instruction -- a classic space
; optimisation. Naming them makes the intent obvious at the point of use.
;
;   DB SKIP1  places a "CP n" whose operand is the next byte, so the next instruction is skipped and only the flags
;             are disturbed. Equivalent to a one-byte "JR +1" that corrupts F.
;   DB SKIP2  places a "LD HL,nn" (or LD DE,nn / AND n) whose operand is the next two bytes.
;   DB SKIP3  places a "JP cc,nnnn"-style prefix consuming three bytes.
; ---------------------------------------------------------------------------------------------------------------------

SKIP1CP:        EQU &FE         ; CP n     -- skips 1 byte, corrupts flags
SKIP1LDA:       EQU &3E         ; LD A,n   -- skips 1 byte, corrupts A
SKIP1LDH:       EQU &26         ; LD H,n   -- skips 1 byte, corrupts H
SKIP1LDC:       EQU &0E         ; LD C,n   -- skips 1 byte, corrupts C
SKIP1LDB:       EQU &06         ; LD B,n   -- skips 1 byte, corrupts B
SKIP2LDHL:      EQU &21         ; LD HL,nn -- skips 2 bytes, corrupts HL
SKIP2LDDE:      EQU &11         ; LD DE,nn -- skips 2 bytes, corrupts DE
SKIP2LDBC:      EQU &01         ; LD BC,nn -- skips 2 bytes, corrupts BC
SKIP2LDNN:      EQU &22         ; LD (nn),HL -- skips 2 bytes, and writes HL to whatever address they spell
SKIP3IX:        EQU &DD         ; IX prefix -- turns a following "LD HL,nn" into "LD IX,nn", skipping 3 bytes
SKIP3IY:        EQU &FD         ; IY prefix -- likewise, giving "LD IY,nn"


; =====================================================================================================================
; SECTION 14 -- Keyboard
; =====================================================================================================================

KBQSIZE:        EQU 8           ; Entries in the keyboard type-ahead queue KBQB
KBQMASK:        EQU KBQSIZE-1   ; Wrap mask for the queue head and tail displacements
KBROWS:         EQU 9           ; Key matrix rows: eight at ports &FEFE..&7FFE plus the special port &FFFE
KBSHIFTTAB:     EQU 70          ; Bytes between the unshifted key table and each shifted one
KBENTERCODE:    EQU 65          ; Scan code of ENTER, which needs an extra debounce check

KBSHNONE:       EQU 0           ; KEYSCAN shift result: no shift key held
KBSHCAPS:       EQU 1           ; CAPS SHIFT
KBSHSYM:        EQU 2           ; SYMBOL SHIFT
KBSHCTRL:       EQU 3           ; CONTROL


; =====================================================================================================================
; SECTION 15 -- Save/load header buffers
; =====================================================================================================================
;
; Layout is documented at the head of TAPEMN.ASM and in docs/file-formats.md. HDR is the requested header, HDL the
; one just read from tape or net; HFG, HDN and NMLEN are displacements within them, defined in VARS.ASM.

HDRLEN:         EQU 80          ; Bytes of header written to tape or net
ZXHDRLEN:       EQU 17          ; Bytes of a Spectrum header, which LDBYTES accepts and LDHDR converts
FT_ZXCODE:      EQU 3           ; Spectrum file type 3 (CODE); types 0-3 mark a Spectrum header


; =====================================================================================================================
; SECTION 16 -- FILL and BLITZ
; =====================================================================================================================

FILPATLEN:      EQU 128         ; Bytes of pattern FILL copies into FILBUFF: a 16x8-pixel tile in mode 3 terms
FILGETBLKLEN:   EQU 131         ; Length of a 2x2-cell GRAB string: control code, width, length, then FILPATLEN bytes
FILCHKSCRN:     EQU &E000       ; Base of the fill check screen: one bit per pixel, 32 bytes by 192 scans

; BLITZ command codes, as stored in the string a BLITZ program consists of. Codes 0 and 1 are the sign byte of a
; relative draw rather than commands in their own right.

BLZDRAWREL:     EQU 0           ; 00/FF sign of X, then X, sign of Y, Y -- relative DRAW
BLZPLOT:        EQU 1           ; 01, x, y
BLZDRAWTO:      EQU 2           ; 02, x, y
BLZCIRCLE:      EQU 3           ; 03, x, y, r
BLZOVER:        EQU 4           ; 04, over
BLZINK:         EQU 5           ; 05, ink
BLZCLS:         EQU 6           ; 06, 0 = whole screen, 1 = window
BLZPAUSE:       EQU 7           ; 07, frames
