; =====================================================================================================================
; VARS.ASM -- System variable map and fixed buffer addresses
; =====================================================================================================================
;
; This module contains no code. It is the address map of the interpreter's working storage, all of which lives in
; physical RAM page 0 -- the "system page" -- which normal operation keeps mapped at &4000-&7FFF (section B).
;
; Two blocks of system variables exist for historical reasons:
;
;   VAR2  &5A00   The SAM-specific block: screen state, colour variables, the memory-area pointers, vectors, and
;                 the compiler/error/printing workspaces. Must start on a page boundary because several routines
;                 index into it with an 8-bit offset and a fixed high byte.
;
;   &5C00         The ZX Spectrum-compatible block: keyboard state, streams, FLAGS, PPC, CHANS, STKEND, RAMTOP.
;                 Names and offsets follow the Spectrum where the meaning is the same.
;
; Beyond &5CD5 the same page holds the start of the BASIC program area, which BASIC addresses through section C as
; page 0 offset &9CD5 and grows upwards across pages 1, 2, ... to RAMTOP.
;
; A recurring convention: a memory-area pointer is stored as three bytes -- a page number followed by a 16-bit
; address normalised into the &8000-&BFFF window. The "...P" symbol names the page byte and the unsuffixed symbol
; the address, and the two are always adjacent so a routine can load all three with one indexed access.
;
; See docs/memory-map.md for the region-by-region layout with sizes, and docs/constants.md for the full table.
;
; =====================================================================================================================

VAR2:       EQU &5A00           ; Base of the SAM system variable block. MUST be page-aligned.


; =====================================================================================================================
; SECTION 1 -- Editor and device configuration
; =====================================================================================================================
;
; The first 18 bytes are initialised as a block by copying the CHIT table from TEXT.ASM, so their order is fixed.
; ---------------------------------------------------------------------------------------------------------------------

LNCUR:      EQU VAR2+&00        ; Character used for the current-line cursor in listings (normally '>')
KURCHAR:    EQU VAR2+&01        ; (2) Edit cursor characters: lower case, then upper case (caps lock selects)
BIN1DIG:    EQU VAR2+&03        ; Character BIN$ emits for a 1 bit (normally '1')
BIN0DIG:    EQU VAR2+&04        ; Character BIN$ emits for a 0 bit (normally '0')
INSTHASH:   EQU VAR2+&05        ; INSTR wildcard character, matching anything (normally '#')
PSLD:       EQU VAR2+&06        ; (2) Permanent save/load device: letter, then number
                                ;     The number is tape speed, disc number or net station depending on the letter.
SPEEDINK:   EQU VAR2+&08        ; Frames between FLASH palette swaps (reload value for SPEEDIC)
LINIPTR:    EQU VAR2+&09        ; (2) Pointer into the line-interrupt colour table for the next scan to service
XCMDP:      EQU VAR2+&0B        ; (3) Page/address of the first external command list, or &FFxxxx for none
PRRHS:      EQU VAR2+&0E        ; Printer right margin (normally 79)
AFTERCR:    EQU VAR2+&0F        ; Byte sent after a printer CR: &0A for auto line feed, 0 for none
LPTPRT1:    EQU VAR2+&10        ; (2) Printer control port, then the strobe value
                                ;     VAR2+&12 to VAR2+&2E are reserved for a DUMP driver's own use.

TABVAR:     EQU VAR2+&2F        ; PRINT comma tab width: 0 selects 16 columns, non-zero selects 8
M23LSC:     EQU VAR2+&30        ; (2) Lower screen paper/ink bytes for internal modes 2 and 3
SOFE:       EQU VAR2+&32        ; Screen blanking enable: 0 permits the automatic screen-off timer
TPROMPTS:   EQU VAR2+&33        ; Prompt suppression -- see TPROMPTNAMES / TPROMPTSAVE in EQUATES.ASM


; =====================================================================================================================
; SECTION 2 -- Screen and print state
; =====================================================================================================================
;
; From BGFLG to SPOSNL inclusive this block travels with the screen: switching screens saves it into the second page
; of the outgoing screen (at PVBUFF) and reloads it from the incoming one, so every open screen keeps its own
; windows, cursor position and colours.
;
; Most of the graphics settings exist twice. The "permanent" copy (...P) holds what the user last set with a command;
; the "temporary" copy (...T) is what the current operation actually uses. TEMPS refreshes the temporary set from the
; permanent one at the start of each print or plot, so an inline "INK 2;" affects only that statement.
; ---------------------------------------------------------------------------------------------------------------------

BGFLG:      EQU VAR2+&34        ; Block graphics flag: 0 synthesises block shapes for codes &80-&8F, non-zero uses UDGs
FL6OR8:     EQU VAR2+&35        ; Character width in internal mode 2: 0 selects 6-pixel cells, non-zero 8-pixel
CSIZE:      EQU VAR2+&36        ; (2) Cell height (low byte, 6-32) then width (high byte, 6 or 8)

UWRHS:      EQU VAR2+&38        ; Upper window right column (initially 31)
UWLHS:      EQU VAR2+&39        ; Upper window left column (initially 0)
UWTOP:      EQU VAR2+&3A        ; Upper window top row (initially 0)
UWBOT:      EQU VAR2+&3B        ; Upper window bottom row (initially 18 -- 19 rows up and 2 down, of 9 pixels each.
                                ; The leftover 3 scan lines become LSOFF.)

LWRHS:      EQU VAR2+&3C        ; Lower window right column
LWLHS:      EQU VAR2+&3D        ; Lower window left column
LWTOP:      EQU VAR2+&3E        ; Lower window top row (rises as INPUT prompts grow the window)
LWBOT:      EQU VAR2+&3F        ; Lower window bottom row (initially 20)

MODE:       EQU VAR2+&40        ; Current internal screen mode 0-3 (user MODE 1-4)
YCOORD:     EQU VAR2+&41        ; Graphics Y position, 0-191 with 0 at the TOP (inverted from BASIC's convention)
XCOORD:     EQU VAR2+&42        ; (2) Graphics X position: 0-255 with fat pixels, 0-511 with thin
RLINE:      EQU XCOORD          ; Alias: ROLL/SCROLL reuse the X coordinate word as a line counter

; --- Permanent graphics and print settings ---

THFATP:     EQU VAR2+&44        ; 0 = thin pixels, non-zero = fat (only meaningful in internal mode 2)
ATTRP:      EQU VAR2+&45        ; Attribute byte for internal modes 0 and 1
MASKP:      EQU VAR2+&46        ; Attribute mask: set bits are taken from the existing screen attribute
PFLAGP:     EQU VAR2+&47        ; Print flags: bit 4 = PAPER 9, bit 6 = INK 9 (contrast against the other colour)
M23PAPP:    EQU VAR2+&48        ; Paper byte for internal modes 2 and 3; nibbles normally match
M23INKP:    EQU VAR2+&49        ; Ink byte for internal modes 2 and 3. Must precede OVERP: some code loads both
                                ; as a word with LD DE,(M23INKT).
OVERP:      EQU VAR2+&4A        ; Text OVER state, 0 or 1
INVERP:     EQU VAR2+&4B        ; INVERSE state as a mask: &00 normal, &FF inverse
GOVERP:     EQU VAR2+&4C        ; Graphics OVER 0-3 (replace, XOR, OR, AND) -- used by PLOT, DRAW and PUT

; --- Temporary copies, refreshed from the above by TEMPS ---

THFATT:     EQU VAR2+&4D        ; Copy of THFATP in internal mode 2; forced non-zero (fat) in every other mode
ATTRT:      EQU VAR2+&4E        ; Working attribute
MASKT:      EQU VAR2+&4F        ; Working attribute mask
PFLAGT:     EQU VAR2+&50        ; Working print flags
M23PAPT:    EQU VAR2+&51        ; Working mode 2/3 paper
M23INKT:    EQU VAR2+&52        ; Working mode 2/3 ink
OVERT:      EQU VAR2+&53        ; Working OVER
INVERT:     EQU VAR2+&54        ; Working INVERSE mask
GOVERT:     EQU VAR2+&55        ; Working graphics OVER

; --- The window currently being written to (upper, lower or printer) ---

WINDRHS:    EQU VAR2+&56        ; Current window right column
WINDLHS:    EQU VAR2+&57        ; Current window left column
WINDTOP:    EQU VAR2+&58        ; Current window top row
WINDBOT:    EQU VAR2+&59        ; Current window bottom row

WINDMAX:    EQU VAR2+&5A        ; (2) Limits for the upper window: lowest permitted bottom row, then maximum right
ORGOFF:     EQU VAR2+&5C        ; Distance of the graphics origin above the screen bottom, in scan lines
LSOFF:      EQU VAR2+&5D        ; Spare scan lines between the upper and lower screens (screen height mod cell height)
                                ; VAR2+&5E to VAR2+&6B are spare.

SPOSNU:     EQU VAR2+&6C        ; (2) Upper screen print position: column, then row
SPOSNL:     EQU VAR2+&6E        ; (2) Lower screen print position: column, then row

                                ; --- End of the block saved with a switched-out screen ---


; =====================================================================================================================
; SECTION 3 -- Interpreter state
; =====================================================================================================================

PRPOSN:     EQU VAR2+&70        ; (2) Printer column (the second byte exists only so it can be loaded as a word)
OPCHAR:     EQU VAR2+&72        ; Character currently being output, kept for the LPRINT driver
DEVICE:     EQU VAR2+&73        ; Output device: 0 = upper screen, 1 = lower screen, 2 = printer
CLET:       EQU VAR2+&74        ; Letter of the current channel (K, S, P, B, T, $ ...)
IFTYPE:     EQU VAR2+&75        ; Records whether the last IF on this line was long or short, so ELSE can match it
REFFLG:     EQU VAR2+&76        ; Zero while a REF parameter is being bound; also set non-zero when a line uses FN,
                                ; which tells the compile pass that FN buffers need resolving
CURDISP:    EQU VAR2+&77        ; Screen number selected by DISPLAY, or 0 to follow the current screen
CUSCRNP:    EQU VAR2+&78        ; Page and mode bits of the screen being drawn on
CURP:       EQU VAR2+&79        ; Saved HMPR value, restored after a routine borrows section C
CLRP:       EQU VAR2+&7A        ; Saved LMPR value, restored after a routine borrows section A/B
CSA:        EQU VAR2+&7B        ; (2) Address of the statement currently executing
FIRST:      EQU VAR2+&7D        ; (2) Low end of a line range (LIST/DELETE); also reused by the array slicer
LAST:       EQU VAR2+&7F        ; (2) High end of a line range; also reused by the array slicer


; =====================================================================================================================
; SECTION 4 -- Memory area pointers
; =====================================================================================================================
;
; These fourteen pointers delimit the movable BASIC area. MAKEROOM and RECLAIM adjust every one of them that lies at
; or above the point where bytes are inserted or removed, so that all of BASIC's bookkeeping survives a memory move.
; The order below is load-bearing: XOINTERS walks them as a contiguous table.
;
; Regions run in this order, low to high:
;     PROG -> program | NVARS -> numeric variables | NUMEND -> gap | SAVARS -> strings and arrays
;          | ELINE -> edit line | WORKSP -> workspace | WKEND -> free memory | RAMTOP
; ---------------------------------------------------------------------------------------------------------------------

SAVARSP:    EQU VAR2+&81        ; Page of the string and array area
SAVARS:     EQU VAR2+&82        ; (2) Start of the string and array area. SAVARS/NUMEND/NVARS must stay in this order.

NUMENDP:    EQU VAR2+&84        ; Page of the end of the numeric variables
NUMEND:     EQU VAR2+&85        ; (2) End of numeric variables; new numerics are created here

NVARSP:     EQU VAR2+&87        ; Page of the numeric variable area
NVARS:      EQU VAR2+&88        ; (2) Start of the numeric variables (26 chain roots), i.e. the end of the program

DATADDP:    EQU VAR2+&8A        ; Page of the DATA read pointer
DATADD:     EQU VAR2+&8B        ; (2) Position within the current DATA statement, advanced by READ

WKENDP:     EQU VAR2+&8D        ; Page of the end of workspace
WKEND:      EQU VAR2+&8E        ; (2) End of workspace -- the top of everything BASIC has allocated

WORKSPP:    EQU VAR2+&90        ; Page of the workspace
WORKSP:     EQU VAR2+&91        ; (2) Start of workspace: INPUT text and temporary strings

ELINEP:     EQU VAR2+&93        ; Page of the edit line
ELINE:      EQU VAR2+&94        ; (2) Start of the line being typed or edited

CHADP:      EQU VAR2+&96        ; Page of the interpretation pointer
CHAD:       EQU VAR2+&97        ; (2) Next character to be interpreted -- the program counter of the interpreter

KCURP:      EQU VAR2+&99        ; Page of the edit cursor
KCUR:       EQU VAR2+&9A        ; (2) Position of the edit cursor within the edit or INPUT line

NXTLINEP:   EQU VAR2+&9C        ; Page of the next program line
NXTLINE:    EQU VAR2+&9D        ; (2) Address of the line following the one being executed

PROGP:      EQU VAR2+&9F        ; Page of the program
PROG:       EQU VAR2+&A0        ; (2) Start of the BASIC program

XPTRP:      EQU VAR2+&A2        ; Page of the syntax error marker
XPTR:       EQU VAR2+&A3        ; (2) Position at which to print the flashing '?' after a syntax error

DESTP:      EQU VAR2+&A5        ; Page of the assignment destination
DEST:       EQU VAR2+&A6        ; (2) Where the value being assigned should be stored

PRPTRP:     EQU VAR2+&A8        ; Page of the PROC call pointer
PRPTR:      EQU VAR2+&A9        ; (2) Position in the PROC call's argument list. Also borrowed by READ and INPUT as a
                                ;     safe place to park CHAD while creating variables moves memory.

                                ; --- End of the auto-adjusted pointers ---

DPPTRP:     EQU VAR2+&AB        ; Page of the DEF PROC parameter pointer
DPPTR:      EQU VAR2+&AC        ; (2) Position in the DEF PROC parameter list (not auto-adjusted)

CLAPG:      EQU VAR2+&AE        ; Page of the current line
CLA:        EQU VAR2+&AF        ; (2) Start of the line being executed. A high byte of zero means the edit line,
                                ;     which RETURN and NEXT test for (not auto-adjusted).


; =====================================================================================================================
; SECTION 5 -- Assorted flags and scratch storage
; =====================================================================================================================

DFTFB:      EQU VAR2+&B1        ; Zero if the numeric variable just found holds "minus zero", which DEFAULT treats
                                ; as not existing
STRNO:      EQU VAR2+&B2        ; Number of the stream last selected, kept for the DOS
LDCO:       EQU VAR2+&B3        ; Page offset applied when loading ZX-format code
                                ; VAR2+&B4 is spare.
OPSTORE:    EQU VAR2+&B5        ; (2) Saved channel output address, while it is diverted to collect control-code
                                ; operands
DMPFG:      EQU VAR2+&B7        ; Non-zero discards all output. Used to measure a line's height without drawing it.
LISTFLG:    EQU VAR2+&B8        ; LIST FORMAT setting 0-2: columns of indent added per nesting level
LSTFT:      EQU VAR2+&B9        ; Copy of LISTFLG placed where channel R can see it during EDIT
INQUFG:     EQU VAR2+&BA        ; In-quotes flag -- see FINQUOTES. Set while printing so token bytes render as UDGs;
                                ; OUTLINE clears it so that listings expand keywords outside strings.
SPROMPT:    EQU VAR2+&BB        ; Non-zero suppresses the "scroll?" prompt
OLDSPCS:    EQU VAR2+&BC        ; Indent state of the previous listed line, so a line printed twice indents the same
INDOPFG:    EQU VAR2+&BD        ; Non-zero enables indented output (wrapped lines are padded to the indent)

NXTSPCS:    EQU VAR2+&BE        ; Indent columns for the next statement
CURSPCS:    EQU VAR2+&BF        ; Indent columns for the current statement
NXTHSPCS:   EQU VAR2+&C0        ; Additional indent applied after THEN, for the next statement
CURTHSPCS:  EQU VAR2+&C1        ; Additional indent applied after THEN, for the current statement

KPOS:       EQU VAR2+&C2        ; (2) Screen position at which the edit cursor was last drawn

; --- The next four are read as a group and must stay in order ---

SOFFCT:     EQU VAR2+&C4        ; Frames remaining before the screen blanks automatically
SOFLG:      EQU VAR2+&C5        ; Non-zero once the screen has actually been blanked
SPEEDIC:    EQU VAR2+&C6        ; Frames remaining before the next FLASH palette swap
PALFLAG:    EQU VAR2+&C7        ; Bit 0 selects which of the two palette tables is currently loaded

TEMPW1:     EQU VAR2+&C8        ; (2) General scratch word
TEMPW2:     EQU VAR2+&CA        ; (2) General scratch word
TEMPW3:     EQU VAR2+&CC        ; (2) General scratch word
TEMPB1:     EQU VAR2+&CE        ; General scratch byte
TEMPB2:     EQU VAR2+&CF        ; General scratch byte
TEMPB3:     EQU VAR2+&D0        ; General scratch byte; also carries the CALL parameter count and the FILL mode

; --- Interrupt and NMI bookkeeping (system page only) ---

LASTSTAT:   EQU VAR2+&D1        ; STATPORT value latched by the last interrupt, identifying which sources fired
SPSTORE:    EQU VAR2+&D2        ; (2) Stack pointer saved across an interrupt
JVSP:       EQU VAR2+&D5        ; (2) Stack pointer saved by the JSVIN entry point
NMISP:      EQU VAR2+&D7        ; (2) Stack pointer saved by the NMI handler
NMILRP:     EQU VAR2+&D9        ; LMPR value at the moment the NMI fired


; =====================================================================================================================
; SECTION 6 -- Vector table
; =====================================================================================================================
;
; Each entry is a 16-bit address. A non-zero vector diverts the corresponding ROM routine, which is how a DOS or a
; utility extends the interpreter without patching ROM. The ROM checks each for zero before calling it.
; ---------------------------------------------------------------------------------------------------------------------

VECTBS:     EQU VAR2+&DA        ; Base of the vector table (used by the LINK routine to index it)

DMPV:       EQU VAR2+&DA        ; (2) DUMP / COPY -- no printer driver in ROM, so COPY does nothing without this
SETIYV:     EQU VAR2+&DC        ; (2) Plot routine selection, called by SETIY
PRTOKV:     EQU VAR2+&DE        ; (2) Token printing, called before a keyword is expanded
NMIV:       EQU VAR2+&E0        ; (2) Non-maskable interrupt (normally the super-break handler)
FRAMIV:     EQU VAR2+&E2        ; (2) Frame interrupt, 50 times a second
LINIV:      EQU VAR2+&E4        ; (2) Line interrupt
COMSV:      EQU VAR2+&E6        ; (2) Communications interrupt
MIPV:       EQU VAR2+&E8        ; (2) MIDI input interrupt
MOPV:       EQU VAR2+&EA        ; (2) MIDI output interrupt
EDITV:      EQU VAR2+&EC        ; (2) Editor entry
RST8V:      EQU VAR2+&EE        ; (2) Error handling, called before the code is acted on
RST28V:     EQU VAR2+&F0        ; (2) FP calculator, called with every opcode before dispatch
RST30V:     EQU VAR2+&F2        ; (2) RST &30 issued from outside ROM0, letting user code define its own convention
CMDV:       EQU VAR2+&F4        ; (2) Command dispatch, called with the command byte -- the hook for new keywords
EVALUV:     EQU VAR2+&F6        ; (2) Function evaluation, called with the function code -- the hook for new functions
LPRTV:      EQU VAR2+&F8        ; (2) LPRINT output
MTOKV:      EQU VAR2+&FA        ; (2) Tokeniser, called when a word fails to match the ROM keyword table
MOUSV:      EQU VAR2+&FC        ; (2) Mouse reading, called from the frame interrupt
KURV:       EQU VAR2+&FE        ; (2) Cursor drawing


; =====================================================================================================================
; SECTION 7 -- Print expansion tables, compiler and error state
; =====================================================================================================================

CEXTAB:     EQU VAR2+&0100      ; (32) EXTAB with the current ink and paper applied, so the mode 2/3 print routines
                                ; can turn a character nibble straight into coloured screen bytes
EXTAB:      EQU VAR2+&0120      ; (32) Pixel expansion table, rebuilt whenever the mode changes.
                                ; Internal mode 3: 16 words, each expanding a nibble to four 4-bit pixels.
                                ; Internal mode 2: 16 bytes, each expanding a nibble to four 2-bit pixels.
                                ; Entry &0A (%1010) becomes %1111000011110000 or %11001100 respectively.

COMPFLG:    EQU VAR2+&0140      ; Compile pass control: bit 7 set means the whole program needs recompiling, not
                                ; just the edit line
BREAKDI:    EQU VAR2+&0141      ; Non-zero disables the BREAK test between statements
ERRSTAT:    EQU VAR2+&0142      ; Statement number of the active ON ERROR
ERRLN:      EQU VAR2+&0143      ; (2) Line number of the active ON ERROR
ONERRFLG:   EQU VAR2+&0145      ; ON ERROR arming -- see FONERRTEMP / FONERRPERM
ONSTORE:    EQU VAR2+&0146      ; Real statement number saved by ON, since it fakes SUBPPC while dispatching
BCSTORE:    EQU VAR2+&0147      ; (2) BC saved across the RST &30 inter-ROM call
M3PAPP:     EQU VAR2+&0149      ; (2) Internal mode 3 paper, preserved while mode 2 is selected
M3LSC:      EQU VAR2+&014B      ; (2) Internal mode 3 lower screen colours, likewise preserved
TEMPW4:     EQU VAR2+&014D      ; (2) Scratch used by the pointer adjustment code
TEMPW5:     EQU VAR2+&014F      ; (2) Scratch used by the pointer adjustment code
                                ; VAR2+&0151 is spare.

LPT:        EQU VAR2+&0152      ; (30) Line pointer table: one byte per screen row, non-zero where a program line
                                ; begins. Lets the up/down cursor keys step between listed lines.

ANYIV:      EQU VAR2+&0170      ; (2) Entry taken by every maskable interrupt before source demultiplexing
RNSTKE:    EQU VAR2+&0172       ; (2) Top of the rename stack used when binding REF string parameters
CURCMD:     EQU VAR2+&0174      ; Token of the command currently executing (SAVE/LOAD and the colour commands read it)
LTDFF:      EQU VAR2+&0175      ; Distinguishes LET from DEFAULT in the shared assignment code
STRM16NM:   EQU VAR2+&0176      ; (11) Type/length byte and name of the string that stream 16 appends to
GRARF:      EQU VAR2+&0181      ; Graphics recording flag: non-zero makes graphics commands append BLITZ records
DHADJ:      EQU VAR2+&0182      ; Scan offset applied while printing the lower half of a double-height character
PAGCOUNT:   EQU VAR2+&0183      ; Whole 16K pages remaining in a FARLDIR/FARLDDR transfer
MODCOUNT:   EQU VAR2+&0184      ; (2) Bytes beyond those pages in a FARLDIR/FARLDDR transfer
BCREG:      EQU VAR2+&0186      ; (2) The FP calculator's B register, holding loop counts and indirect opcodes
AUTOFLG:    EQU VAR2+&0188      ; Non-zero while AUTO line numbering is active
AUTOSTEP:   EQU VAR2+&0189      ; (2) AUTO line number increment
RSTEP:      EQU AUTOSTEP        ; Alias: RENUM reuses the same word for its step

LSPTR:      EQU VAR2+&018B      ; (2) Position within the line being listed, used to place the edit cursor
LNPTR:      EQU VAR2+&018D      ; Screen row carrying the '>' cursor, or >= &40 if it is not on screen
MSEDP:      EQU VAR2+&018E      ; (8) Mouse driver data, VAR2+&018E to VAR2+&0195
BUTSTAT:    EQU VAR2+&018F      ; Mouse button state, bits 2-0 for buttons 3-1

MXCRD:      EQU VAR2+&0196      ; (2) Mouse X coordinate
MYCRD:      EQU VAR2+&0198      ; (2) Mouse Y coordinate


; =====================================================================================================================
; SECTION 8 -- Number formatting workspace (PRINTFP.ASM)
; =====================================================================================================================

FRACLIM:    EQU VAR2+&019A      ; Leading fraction zeros permitted before switching to E notation (normally 6)
NPRPOS:     EQU VAR2+&019B      ; (2) Write position within PRNBUFF
DIGITS:     EQU VAR2+&019D      ; Significant digits still to produce.  These four
EPOWER:     EQU VAR2+&019E      ; Power of ten factored out for E notation.  must stay
DECPNTED:   EQU VAR2+&019F      ; Set once the decimal point has been emitted.   in order.
PRNBUFF:    EQU VAR2+&01A0      ; (16) Assembled number text. Sized for "-0.0000123456789" or "-1.2345678E-35".
BCDBUFF:    EQU VAR2+&01B0      ; (5) Packed BCD digits produced while converting the integer part


; =====================================================================================================================
; SECTION 9 -- Save, load and DOS state
; =====================================================================================================================

OTHER:      EQU VAR2+&01B5      ; Destination station number for network transfers
DCT:        EQU VAR2+&01B6      ; Disc retry counter
SLDEV:      EQU VAR2+&01B7      ; (2) Device letter and number for the transfer in progress (a copy of PSLD, which
                                ;     a device prefix in the file name may override)
OVERF:      EQU VAR2+&01B9      ; SAVE OVER flag: 0 means overwriting is permitted
INSLV:      EQU VAR2+&01BA      ; (2) Vector consulted by the block move routine (unused by the ROM itself)
STRLOCN:    EQU VAR2+&01BC      ; (2) Address of the string/array record last found by the variable search
TVDATA:     EQU VAR2+&01BE      ; (2) Operands collected for a control code: the code itself, then its first operand
DOSER:      EQU VAR2+&01C0      ; (2) Address to jump to after the DOS returns, or zero for the normal path
DOSFLG:     EQU VAR2+&01C2      ; Zero if no DOS is resident, otherwise the DOS page number
DOSCNT:     EQU VAR2+&01C3      ; Bit 0 set while the DOS is in control, preventing recursive error dispatch
BSTKEND:    EQU VAR2+&01C4      ; (2) Lowest used address of the BASIC stack, which grows downwards from BASSTK


; =====================================================================================================================
; SECTION 10 -- Addresses initialised as a block from MAIT
; =====================================================================================================================
;
; These 26 bytes are copied in one LDIR from the MAIT table in TEXT.ASM, so their order is fixed.
; ---------------------------------------------------------------------------------------------------------------------

BASSTK:     EQU VAR2+&01C6      ; (2) Base of the BASIC (DO/GOSUB/PROC) stack; frames grow downwards from here
HEAPEND:    EQU VAR2+&01C8      ; (2) Current top of the heap; the gap up to BSTKEND is free
HPST:       EQU VAR2+&01CA      ; (2) Base of the heap; the heap is empty when HEAPEND equals this
FPSBOT:     EQU VAR2+&01CC      ; (2) Base of the floating point calculator stack
DKDEF:      EQU VAR2+&01CE      ; (2) Start of the DEF KEY definition buffer
DKLIM:      EQU VAR2+&01D0      ; (2) Address the DEF KEY buffer may grow to before ERR_TOOMANYDEF
PATOUT:     EQU VAR2+&01D2      ; (2) Routine that renders a printable character (normally ENDOUTP)
ERRMSGS:    EQU VAR2+&01D4      ; (2) Base of the error message table
UMSGS:      EQU VAR2+&01D6      ; (2) Base of the utility message table
KBTAB:      EQU VAR2+&01D8      ; (2) Base of the keyboard translation table
CMDADDRT:   EQU VAR2+&01DA      ; (2) Base of the command address table, indexed by (token - TOK_CMDFIRST) * 2
MNOP:       EQU VAR2+&01DC      ; (2) Main output routine, copied into channels when they are reset
MNIP:       EQU VAR2+&01DE      ; (2) Main input routine, likewise

PAGER:      EQU VAR2+&01E0      ; (14) Reserved for a paging subroutine
KBUFF:      EQU VAR2+&01EE      ; (18) Two 72-bit keyboard state maps, for detecting newly pressed keys


; =====================================================================================================================
; SECTION 11 -- ZX Spectrum compatible system variables
; =====================================================================================================================

LHM1:       EQU &5C00           ; Scratch byte immediately below LASTH, addressed as "LASTH-1" by the key scanner
                                ; &5C01 LASTH: last key hit, or 0. Stops updating once the buffer fills; clearing
                                ; FLAGS bit 5 counts as reading it.
KDATA:      EQU &5C02           ; Control code being collected while its colour operand is typed
LKPB:       EQU &5C03           ; (2) Previous keyboard scan result, for detecting changes
REPCT:      EQU &5C05           ; Frames until the held key repeats
LASTKV:     EQU &5C06           ; (2) Raw port values of the last key read
LASTK:      EQU &5C08           ; Key taken from the head of the queue; retains its value until overwritten
REPDEL:     EQU &5C09           ; Frames before a held key first repeats
REPPER:     EQU &5C0A           ; Frames between subsequent repeats
                                ; &5C0B is spare.
STREAMS:    EQU &5C10           ; (42) Stream table for streams -5 to 15 (stream 16 maps to -4 internally). Each
                                ; entry is a 16-bit displacement into the channel area, or 0 if closed. The table
                                ; physically starts at &5C0C; this symbol points at stream 0.
CHARS:      EQU &5C36           ; (2) Character set base, stored 256 low so that code * 8 indexes it directly
RASP:       EQU &5C38           ; Length of the warning buzz
PIP:        EQU &5C39           ; Length of the keyboard click
ERRNR:      EQU &5C3A           ; Current error number; 0 means OK
FLAGS:      EQU &5C3B           ; Principal interpreter flags -- see FFLAGRUN, FFLAGNUM, FFLAGKEY, FFLAGNOSP
TVFLAG:     EQU &5C3C           ; Screen output flags -- see FTVCLRLS, FTVAUTOLIST, FTVCOPYLINE, FTVLOWER
ERRSP:      EQU &5C3D           ; (2) Stack pointer an error should unwind to
LISTSP:     EQU &5C3F           ; (2) Stack pointer an aborted AUTOLIST unwinds to
                                ; &5C41 is spare.
NEWPPC:     EQU &5C42           ; (2) Line number a pending jump will go to
NSPPC:      EQU &5C44           ; Statement a pending jump will go to; &FF means no jump is pending
PPC:        EQU &5C45           ; (2) Line number currently executing (&FFFF while running the edit line)
SUBPPC:     EQU &5C47           ; Statement number currently executing, counting from 1
BORDCR:     EQU &5C48           ; Lower screen attribute in internal modes 0 and 1
EPPC:       EQU &5C49           ; (2) Line number carrying the '>' cursor in listings
BORDCOL:    EQU &5C4B           ; Value written to the border port
                                ; &5C4C to &5C4E are spare.
CHANS:      EQU &5C4F           ; (2) Base of the channel information area
CURCHL:     EQU &5C51           ; (2) Channel currently selected for input and output
DEFADDP:    EQU &5C53           ; Page of the DEF FN parameter list
DEFADD:     EQU &5C54           ; (2) DEF FN parameter list being evaluated, or 0 when not inside an FN
NLASTH:     EQU &5C56           ; (3) Raw port data for the most recent keypress
                                ; &5C59 to &5C60 are spare.
ZIPLIB:     EQU &5C61           ; (2) Reserved for Simon N. Goodwin's compiler
ZIPTEMP:    EQU &5C63           ; (2) Reserved for Simon N. Goodwin's compiler
STKEND:     EQU &5C65           ; (2) First free byte of the FP calculator stack
KPFLG:      EQU &5C67           ; Keypad mode: even selects function keys, odd selects digits
MEM:        EQU &5C68           ; (2) Base of the calculator's six numbered memories
FLAGS2:     EQU &5C6A           ; Secondary flags -- see FFL2CAPS, FFL2DIRTY
SDTOP:      EQU &5C6C           ; (2) Line number displayed at the top of an AUTOLIST
OLDPPC:     EQU &5C6E           ; (2) Line number CONTINUE will resume at
OSPPC:      EQU &5C70           ; Statement number CONTINUE will resume at
FLAGX:      EQU &5C71           ; Assignment and INPUT flags -- see FFLXINPLINE, FFLXINPUT, FFLXNEWVAR
STRLEN:     EQU &5C72           ; (2) Length of the destination string, or the type byte for other assignments
                                ; &5C74 and &5C75 are spare.
SEED:       EQU &5C76           ; (2) RND seed
FRAMES:     EQU &5C78           ; (3) Frame counter, low three bytes
UDG:        EQU &5C7B           ; (2) Bitmap of CHR$ 144; codes &80-&A8 are addressed relative to it
HUDG:       EQU &5C7D           ; (2) Bitmap of CHR$ 169, for codes &A9-&FF. The ROM reads this but never sets it --
                                ; see docs/hudg.md.
FRAMES34:   EQU &5C7F           ; (2) Frame counter, high two bytes
OLDPOS:     EQU &5C82           ; (2) Screen position at which the edit line last finished printing
                                ; &5C84 to &5C8B are spare.
SCRCT:      EQU &5C8C           ; Lines that may still be scrolled before the "scroll?" prompt
KBQB:       EQU &5C8D           ; (8) Keyboard queue
KBQP:       EQU &5C95           ; (2) Keyboard queue pointers: tail in the low byte, head in the high byte
                                ; &5C97 to &5C9C are spare.
SCPTR:      EQU &5C9D           ; (2) Entry in SCLIST for the current screen

; --- Not cleared by NEW -----------------------------------------------------------------------------------------------

FISCRNP:    EQU &5C9F           ; Mode and page of screen 1
SCLIST:     EQU &5CA0           ; (16) Mode and page of screens 1-16, or &FF where the screen is closed
LASTPAGE:   EQU &5CB0           ; Highest page reserved by BASIC
RAMTOPP:    EQU &5CB1           ; Page of RAMTOP
RAMTOP:     EQU &5CB2           ; (2) Highest address BASIC may use
PRAMTP:     EQU &5CB4           ; Highest page physically fitted (&0F on a 256K machine, &1F on a 512K)
                                ; &5CB5 is spare; the channel area starts at &5CB6.


; =====================================================================================================================
; SECTION 12 -- Legacy token names
; =====================================================================================================================
;
; The original source named only the handful of tokens it happened to test for. Those names are kept here as aliases
; of the systematic TOK_ / FN_ definitions in EQUATES.ASM so that both spellings resolve to the same value.
; ---------------------------------------------------------------------------------------------------------------------

KEYWNO:     EQU &C4             ; Number of entries in the keyword table (196)
TSPEED:     EQU 112             ; Default tape speed placed in PSLD at startup

PITOK:      EQU FN_PI           ; &3B -- first function code
PI:         EQU PITOK-&1A       ; The evaluator's internal code for PI, offset from the stored token
INSTOK:     EQU FN_INSTR        ; &4A -- boundary between numeric-result and string-result immediate functions
INSTR:      EQU INSTOK-&1A      ; The evaluator's internal code for INSTR
FNTOK:      EQU FN_FN           ; &42 -- used by the token printer for its spacing rules
BINTOK:     EQU FN_BIN          ; &43 -- recognised by the literal converter as introducing a binary constant
SCRNTOK:    EQU FN_SCREENS      ; &4C -- used by SAVE/LOAD to spot SCREEN$
SINTOK:     EQU FN_SIN          ; &53 -- first function evaluated by the calculator rather than immediately
INTOK:      EQU FN_IN           ; &60
CODETOK:    EQU FN_CODE         ; &6C -- used by SAVE/LOAD to spot CODE
CHRSTOK:    EQU FN_CHRS         ; &70 -- used by COPY to spot COPY CHR$
MODTOK:     EQU FN_MOD          ; &7A -- first alphabetic binary operator
ANDTOK:     EQU FN_AND          ; &80 -- last operator printed with spaces on both sides

USINGTOK:   EQU TOK_USING       ; &85 -- first single-byte token
ATTOK:      EQU TOK_AT          ; &87
TABTOK:     EQU TOK_TAB         ; &88
WHILETOK:   EQU TOK_WHILE       ; &8A
UNTILTOK:   EQU TOK_UNTIL       ; &8B
LINETOK:    EQU TOK_LINE        ; &8C
THENTOK:    EQU TOK_THEN        ; &8D -- also the "no intervening token" null value used by the program searcher
TOTOK:      EQU TOK_TO          ; &8E
STEPTOK:    EQU TOK_STEP        ; &8F

                                ; FORMATTOK (&91) and ERASETOK (&92) exist as tokens but have no ROM implementation;
                                ; see TOK_FORMAT and TOK_ERASE.
SAVETOK:    EQU TOK_SAVE        ; &94
LOADTOK:    EQU TOK_LOAD        ; &95
MERGETOK:   EQU TOK_MERGE       ; &96
VERIFYTOK:  EQU TOK_VERIFY      ; &97
                                ; RECORDTOK (&EF) likewise -- see TOK_RECORD.


; =====================================================================================================================
; SECTION 13 -- DOS hook codes (legacy names)
; =====================================================================================================================
;
; Passed in the byte after RST &08. IX points at the header buffer HDR, whose loaded counterpart is at HDR+&50.
; ---------------------------------------------------------------------------------------------------------------------

BTHK:       EQU HOOK_BOOT       ; 128 -- boot; a DOS may ignore this or treat it as ALHK
FOPHK:      EQU HOOK_OPEN       ; 129 -- open a file and return its header
LDHK:       EQU HOOK_LOAD       ; 130 -- load the file body
VFYHK:      EQU HOOK_VERIFY     ; 131 -- verify the file body
SVHK:       EQU HOOK_SAVE       ; 132 -- save the file
OSHK:       EQU HOOK_OPENSTRM   ; 134 -- open a stream
CSHK:       EQU HOOK_CLOSESTRM  ; 135 -- close a stream; the channel letter is at HDR+1
ALHK:       EQU HOOK_AUTOLOAD   ; 136 -- load the auto-load file, issued straight after BOOT
DIRHK:      EQU HOOK_DIR        ; 137 -- directory
DVHK:       EQU HOOK_DVAR       ; 139 -- DVAR
EOFHK:      EQU HOOK_EOF        ; 140 -- EOF
PTRHK:      EQU HOOK_PTR        ; 141 -- PTR
PATHHK:     EQU HOOK_PATH       ; 142 -- PATH$


; =====================================================================================================================
; SECTION 14 -- WD1772 disc controller
; =====================================================================================================================

COMM:       EQU 224             ; Command port on write, status port on read
TRCK:       EQU 225             ; Track register
SECT:       EQU 226             ; Sector register
DTRQ:       EQU 227             ; Data register
DRES:       EQU 9               ; Command: restore to track 0
STPIN:      EQU &59             ; Command: step in
STPOUT:     EQU &79             ; Command: step out
DRSEC:      EQU &80             ; Command: read sector


; =====================================================================================================================
; SECTION 15 -- Save and load header layout
; =====================================================================================================================
;
; Displacements within the 80-byte header buffers. See docs/file-formats.md for the complete field list.
; ---------------------------------------------------------------------------------------------------------------------

HFG:        EQU 15              ; Displacement to the flags byte (invisible / protected)
HDT:        EQU 26              ; Displacement to the date and time field
HDN:        EQU 31              ; Displacement to the three page-form triples: start, length, execute/auto-run
HDRL:       EQU 80              ; Total header length
NMLEN:      EQU 10              ; Maximum file name length

; Displacements of the graphics pseudo-variables within the numeric variable area, used to scale coordinates.
YOSDISP:    EQU 57              ; Y origin offset
YRGDISP:    EQU 67              ; Y range
XOSDISP:    EQU 77              ; X origin offset
XRGDISP:    EQU 87              ; X range

RSBUFF:     EQU &E003           ; Roll/scroll and GRAB staging buffer, in the second page of the current screen
SBO:        EQU &8000           ; Section C origin -- the RENUM old-line-number table
SBN:        EQU &C000           ; Section D origin -- the RENUM new-line-number table


; =====================================================================================================================
; SECTION 16 -- Fixed buffers in the system page
; =====================================================================================================================
;
; Addresses as seen in section B. Several regions deliberately overlap because their users never run at the same time.
; ---------------------------------------------------------------------------------------------------------------------

HPEND:      EQU &4000           ; Initial heap start and end (the heap begins empty and grows upwards)

BSTACK:     EQU &4AFF           ; Base of the BASIC stack; frames grow downwards towards the heap

HDR:        EQU &4B00           ; (80) Header being requested or built. Also serves as the PROC rename stack.
HDL:        EQU &4B50           ; (80) Header just loaded from tape, disc or network

INTSTK:     EQU &4C00           ; Interrupt stack, growing downwards (reaches about &49EE at its deepest)
BUFF256:    EQU &4C00           ; 256-byte bounce buffer for cross-page block moves. Must be page aligned.

FPSB:       EQU &4D00           ; Base of the FP calculator stack, growing upwards
CDBUFF:     EQU &4D00           ; Generated code buffer, overlaying the calculator stack. Holds runs of LDI, LDD,
                                ; RLD and RRD built on the fly by the roll, scroll, GRAB, PUT and CLS routines,
                                ; because a straight-line run beats the equivalent loop. Maximum length &0181.
                                ; The RAM copy of the tokeniser also executes here, at CDBUFF+&80.
                                ; The machine stack occupies the space between here and ISPVAL.

ISPVAL:     EQU &4F00           ; Initial stack pointer; the machine stack grows down from here to about &4E98

INSTBUF:    EQU &4F00           ; (512) Execution buffer for command bodies copied out of ROM1, and general scratch
                                ; for file names, SOUND lists and INSTR targets
MSGBUFF:    EQU INSTBUF+&01C0   ; Message assembly buffer, sized for the longest DOS message

FILBUFF:    EQU &5080           ; (128) FILL pattern buffer
ALLOCT:     EQU &5100           ; (33) Page allocation table, one byte per page plus a terminator. Page aligned.
MEMVAL:     EQU &5121           ; (30) The calculator's six numbered memories, the default target of MEM
TLBYTE:     EQU &513F           ; Type/length byte of the variable name being processed
NMBUFF:     EQU &5140           ; Name buffer: length byte followed by the name
FIRLET:     EQU NMBUFF          ; Alias used by the variable search, which treats the first byte as the first letter

NMISTK:     EQU &5188           ; NMI stack, growing downwards
SCRNBUF:    EQU &5188           ; (8) SCREEN$ workspace, holding a screen cell reduced to one bit per pixel
CHARSVAL:   EQU &5190           ; (1096) Unpacked character set: codes 32-168, eight bytes each
PALTAB:     EQU &55D8           ; (40) Working palette: two 16-entry tables that alternate to produce FLASH
LINICOLS:   EQU &5600           ; (512) Line interrupt colour table: four bytes per entry, &FF terminated
DKBU:       EQU &5800           ; DEF KEY definition buffer
KTAB:       EQU &58E0           ; (288) Keyboard translation table: three 70-entry planes plus control key values

PVBUFF:     EQU &FEB0           ; Print variables of a screen that is not currently selected, stored in the second
                                ; page of that screen. BGFLG-SPOSNL occupy &FEB0-&FEEB and CEXTAB/EXTAB &FF7C-&FFBB;
                                ; &FEEC-&FF7B and &FFBC-&FFD7 are unused.
FILLSTK:    EQU PVBUFF          ; FILL reuses the same area as its coordinate stack
PALBUF:     EQU &FFD8           ; Palette of a non-displayed screen (reached at &BFD8 when only one page is mapped)


; =====================================================================================================================
; SECTION 17 -- Hardware I/O ports
; =====================================================================================================================

SNDPORT:    EQU &FF             ; Sound chip data; the address register is at &01FF
KEYPORT:    EQU &FE             ; Keyboard rows, border colour, tape output and speaker
MDIPORT:    EQU &FD             ; MIDI and network
VIDPORT:    EQU &FC             ; Displayed screen page and mode
URPORT:     EQU &FB             ; HMPR -- page for sections C and D
LRPORT:     EQU &FA             ; LMPR -- page for sections A and B, plus the ROM enable bits
STATPORT:   EQU &F9             ; Interrupt status on read, line interrupt scan number on write
CLUTPORT:   EQU &F8             ; Palette (colour look-up table); also returns the light pen position

                                ; Mode 1 screen data would appear at &8000 and its attributes at &9800.
