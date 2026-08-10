; =====================================================================================================================
; MAIN.ASM -- ROM0 restart vectors, interrupt entries and the public jump table
; =====================================================================================================================
;
; SAM Coupe ROM 3.0 source code.  Copyright Andrew J.A. Wright 1989-90.
;
; This is the base of ROM0 and the first thing the Z80 sees. It contains, in address order:
;
;   &0000-&007F   The eight Z80 restarts, the maskable interrupt entry at &0038 and the NMI entry at &0066, packed
;                 in among a handful of one- and two-instruction helpers that fill the gaps between them.
;   &0080-&00FF   The floating point calculator entry taken by RST &28, and the paging helper it returns through.
;   &0100-&0192   The public jump table: fixed entry points that external code (a DOS, a utility, machine code
;                 called from BASIC) can rely on across ROM versions.
;   Onwards       The inter-ROM call mechanism, string output, and the initial stream table.
;
; PAGING MODEL
; ------------
; Sections A and B (&0000-&7FFF) are controlled by LMPR, sections C and D (&8000-&FFFF) by HMPR. In normal operation
; ROM0 occupies section A and the system page occupies section B. ROM1 can be paged over section D by setting LMPR
; bit 6, but then it hides whatever was there -- which is why any routine that must read the BASIC program while
; running ROM1 code has to be copied into RAM first.
;
; Because the two ROMs cannot both call each other directly, this file provides the two halves of the linkage:
;
;   RST &30       Called from ROM0 to reach ROM1. The word following the RST is the target address minus &8000.
;   R1OFFCL etc.  Called from ROM1 to reach ROM0 with ROM1 paged out.
;
; Both save and restore the caller's paging, so a routine never has to know how it was entered.
;
; =====================================================================================================================

PAGE0:      EQU 0                       ; RAM page 0 -- the system page
PAGE1:      EQU 1                       ; RAM page 1
PAGE1F:     EQU LMPRSYS                 ; &1F. LMPR value selecting ROM0 in section A and the system page in
                                        ; section B: page 31 plus one wraps to page 0.

            ORG &0000


; =====================================================================================================================
; RST &00 -- Reset
; =====================================================================================================================

L0000:      DI                          ; No interrupts until the vectors and stack exist
            JP MINITH                   ; Delay for the ASIC, page ROM1 in, then initialise the machine


; ---------------------------------------------------------------------------------------------------------------------
; Gap filler at &0004. Discards one return address and jumps to the address below it -- "return to my caller's caller".
; ---------------------------------------------------------------------------------------------------------------------

            POP HL                      ; &04. Junk the immediate return address
HLJUMP:     JP (HL)                     ; &05. Computed jump, used throughout the ROM for vector dispatch

IYJUMP:     JP (IY)                     ; &08 would be the error restart; this sits just before it


; =====================================================================================================================
; RST &08 -- Raise an error
; =====================================================================================================================
;
; Entry:  The byte immediately following the RST is the error code (ERR_xxx) or DOS hook code (HOOK_xxx).
; Exit:   Does not return for an error: ERROR2 stores the code in ERRNR and resets SP from ERRSP, landing in the
;         main loop, an editor error frame, or whatever frame SETESP most recently pushed. A DOS hook code may
;         return normally if the DOS handled it.
; ---------------------------------------------------------------------------------------------------------------------

            NOP                         ; Some hardware prefers a settling instruction here
            EXX                         ; Preserve the alternate set for the error handler
            JP ERROR2

; ---------------------------------------------------------------------------------------------------------------------
; Gap filler: write A to (HL). Reachable as a subroutine so a caller can perform one store with a chosen page mapped.
; ---------------------------------------------------------------------------------------------------------------------

NRWRITE:    LD (HL),A
            RET

            DB 30                       ; &0F. ROM version number, read by software wanting to identify the ROM


; =====================================================================================================================
; RST &10 -- Print the character in A through the current channel
; =====================================================================================================================

            JP RST102


; =====================================================================================================================
; &0013 -- PRINTSTR: print BC characters starting at (DE)
; =====================================================================================================================
;
; Called rather than restarted, since &0013 is not a restart address. Public entry point.
; ---------------------------------------------------------------------------------------------------------------------

PRINTSTR:   JP SOP2                     ; &13

BCJUMP:     PUSH BC                     ; &16. Computed jump to (BC)
            RET


; =====================================================================================================================
; RST &18 -- Fetch the current character
; =====================================================================================================================
;
; The interpreter's character read. Skips every byte below CC_SIGNIF except CR, updating CHAD as it goes, so spaces
; and stray control codes are invisible to the parser almost everywhere.
;
; Exit:   A  = the significant character at (CHAD)
;         HL = CHAD
;         BC preserved; paging restored to whatever it was on entry.
; ---------------------------------------------------------------------------------------------------------------------

GETCHAR:    LD HL,(CHAD)                ; &18
            PUSH BC
            JP GETCHAR1

            DB 0                        ; Pad to the next restart


; =====================================================================================================================
; RST &20 -- Advance to the next character
; =====================================================================================================================
;
; As RST &18, but steps CHAD on by one first.
; ---------------------------------------------------------------------------------------------------------------------

NEXTCHAR:   LD HL,(CHAD)                ; &20
            INC HL
            PUSH BC
            JP NEXTCHAR1


; =====================================================================================================================
; RST &28 -- Floating point calculator
; =====================================================================================================================
;
; The bytes following the RST are a program for the calculator's stack machine; execution resumes after its
; terminating EXIT opcode. See docs/machine-code-interface.md.
; ---------------------------------------------------------------------------------------------------------------------

            JP FPCP2                    ; &28

DELAYB:     DJNZ DELAYB                 ; &2B. Gap filler: short delay loop, callable as a subroutine

IXJUMP:     JP (IX)                     ; &2D. Computed jump used as a cheap "return" by the inner print loops

            DS 1                        ; Pad to the next restart


; =====================================================================================================================
; RST &30 -- Call or jump into ROM1
; =====================================================================================================================
;
; From ROM0: the word following the RST is the ROM1 target address minus &8000. Bit 15 of the stored word selects
; call (set) or jump (clear); the handler sets it before use either way.
;
; From RAM (a caller above &3FFF): re-dispatched through the RST30V vector so user code can define its own meaning.
; ---------------------------------------------------------------------------------------------------------------------

            JP RST30L2                  ; &30

            PUSH DE                     ; &33. DEJUMP -- computed jump to (DE)
            RET

DELYB:      DJNZ DELYB                  ; Gap filler: a second delay loop

            RET


; =====================================================================================================================
; RST &38 -- Maskable interrupt
; =====================================================================================================================
;
; Latches the interrupt status and the current paging, forces a known configuration, then dispatches through ANYIV
; (normally ANYI below). The comments record the elapsed T-states at 6MHz, with the figures for a contended 24MHz
; machine in brackets -- the line interrupt handler has to hit an exact scan line, so this timing matters.
; ---------------------------------------------------------------------------------------------------------------------

            PUSH AF
            PUSH BC
            IN A,(STATPORT)             ; Which interrupt sources fired. About 36T (56) or 6us (9) in.
            LD C,A
            IN A,(LRPORT)
            LD B,A                      ; B = entry LMPR, C = interrupt status
            PUSH HL
            LD A,LMPRSYSR1              ; Both ROMs on, system page in section B
            OUT (LRPORT),A
            LD HL,(ANYIV)
            JP (HL)


; ---------------------------------------------------------------------------------------------------------------------
; ANYI -- default maskable interrupt handler
;
; Entry:  B = LMPR on entry, C = STATPORT value, AF/BC/HL already stacked.
; Exit:   Returns through the stacked registers with interrupts re-enabled.
; Notes:  Switches to a private stack so an interrupt taken while BASIC is using SP for a block operation (CLS uses
;         PUSH to clear the screen) cannot corrupt anything. Arrives about 113T (139) or 19us (23) after the pulse.
; ---------------------------------------------------------------------------------------------------------------------

ANYI:       LD (SPSTORE),SP
            LD SP,INTSTK
            CALL INTS                   ; Demultiplex line / frame / MIDI / mouse (SCRSEL1.ASM)
            LD SP,HL                    ; INTS returns the saved stack pointer in HL and the entry LMPR in A
            OUT (LRPORT),A
            POP HL
            POP BC
            POP AF
            EI
            RET

            DB 0

; ---------------------------------------------------------------------------------------------------------------------
; Gap filler: set HMPR from A and jump to (HL). Lets a caller page section C and enter a routine in one step.
; ---------------------------------------------------------------------------------------------------------------------

            OUT (URPORT),A
            JP (HL)

; ---------------------------------------------------------------------------------------------------------------------
; DELBC -- delay for BC iterations. Callable as a subroutine; used for tape and drive timing.
; ---------------------------------------------------------------------------------------------------------------------

DELBC:      LD A,B
            OR C
            DEC BC
            JR NZ,DELBC

            RET

            NOP


; =====================================================================================================================
; &0066 -- Non-maskable interrupt
; =====================================================================================================================
;
; Registers are stacked in whatever page happens to be mapped, so up to four bytes of that page may be disturbed --
; acceptable because the alternative (paging first) needs a register to do it with.
; ---------------------------------------------------------------------------------------------------------------------

            PUSH AF
            PUSH HL                     ; Saved in the original page; may corrupt 4 bytes if, say, SP is being used
                                        ; as a fast pointer by a CLS in progress
            IN A,(LRPORT)
            LD H,A
            LD A,LMPRSYS                ; ROM0 on, ROM1 off, system page at &4000
            OUT (LRPORT),A
            LD A,H
            LD (NMILRP),A               ; Remember the interrupted paging so it can be restored exactly
            LD (NMISP),SP
            LD SP,NMISTK                ; Private stack, clear of anything BASIC might be doing
            LD HL,(NMIV)
            LD A,H
            OR L
            CALL NZ,HLJUMP              ; Normally the super-break handler; ignored if the vector is zero

            LD SP,(NMISP)
            LD A,(NMILRP)
            OUT (LRPORT),A
            POP HL
            POP AF
            RETN


; ---------------------------------------------------------------------------------------------------------------------
; Block instruction gap fillers. Each is a single Z80 block opcode followed by RET, so a caller can perform one
; block operation with a specific page mapped and return -- cheaper than duplicating the sequence at every site.
; ---------------------------------------------------------------------------------------------------------------------

            LDIR
            RET

            LDDR
            RET

            CPIR
            RET

            CPDR
            RET

            OTIR
            RET

            OTDR
            RET


; ---------------------------------------------------------------------------------------------------------------------
; RDCN / NUMBER -- read a character, stepping over an invisible numeric form
;
; The canonical "skip a 5-byte form" primitive. A NUMMARKER byte in a program line is always followed by exactly five
; bytes holding the pre-converted value (or, for FN/PROC calls, the resolved target address), and every scanner in
; the ROM must step over all six without seeing them.
;
; Entry:  RDCN with HL pointing at a character; NUMBER with that character already in A.
; Exit:   A  = the character, or the one following a skipped form
;         HL = advanced past the form if there was one
; Notes:  About 34T to skip, against 54T for the equivalent ZX Spectrum routine. The single-byte add to L works
;         because a form never straddles a 256-byte boundary in a way that the INC H cannot fix.
; ---------------------------------------------------------------------------------------------------------------------

RDCN:       LD A,(HL)

NUMBER:     CP NUMMARKER
            RET NZ                      ; Not a form -- A already holds the character

            LD A,NUMFORMLEN             ; Marker plus five payload bytes
            ADD A,L
            LD L,A
            LD A,(HL)
            RET NC                      ; HL stayed within the page: A is the next character

            INC H                       ; Carried into the next page

NRREAD:     LD A,(HL)                   ; Also a public one-instruction read helper
            RET

RDDE:       LD A,(DE)                   ; As above, indexed by DE
            RET


; ---------------------------------------------------------------------------------------------------------------------
; MINITH -- power-on delay, then start initialisation
;
; The ASIC needs roughly 55ms to become ready after power-up. Pre-production ROMs lacked this delay, which is why
; they only work on the earliest hardware.
; ---------------------------------------------------------------------------------------------------------------------

MINITH:     LD B,250                    ; 250 x ~1.2ms

IDEL:       DEC BC
            LD A,B
            OR C
            JR NZ,IDEL                  ; Approximately 1.2ms per pass through B

            LD A,LMPRSYSR1              ; ROM1 on, so MNINIT (which lives there) can be reached
            OUT (LRPORT),A
            JP MNINIT


; ---------------------------------------------------------------------------------------------------------------------
; GETCHAR1 / NEXTCHAR1 -- bodies of RST &18 and RST &20
;
; ROM1 is paged out around the read because CHAD normally points into the BASIC program, which occupies the same
; addresses as ROM1. The original LMPR value is restored before returning, so the caller cannot tell.
;
; Exit:   A = first character at or after (CHAD) that is CC_SIGNIF or above, or CR
;         HL = CHAD, BC restored
; ---------------------------------------------------------------------------------------------------------------------

NEXTCHAR1:  LD (CHAD),HL                ; RST &20 arrives here with HL already incremented

GETCHAR1:   IN A,(LRPORT)
            LD B,A                      ; Remember the caller's ROM1 state
            AND LMPRNOR1                ; Force bit 6 low
            OUT (LRPORT),A              ; ROM1 off -- the program is now visible in section D

GTCH1:      LD A,(HL)
            CP CC_SIGNIF
            JR C,GTCH3                  ; Below &21: a space or control code, so consider skipping it

GTCH2:      LD C,LRPORT
            OUT (C),B                   ; Restore the caller's ROM1 state
            POP BC
            RET

GTCH3:      CP CC_ENTER
            JR Z,GTCH2                  ; CR terminates a line and must never be skipped

            INC HL                      ; Step over the space or control code and keep looking
            LD (CHAD),HL
            JR GTCH1


; ---------------------------------------------------------------------------------------------------------------------
; NXCHAR -- advance CHAD and read, with no skipping at all
;
; Entry point &0074. Used by the numeric literal parser, which must see every character: if spaces were skipped here
; then "1 2" would read as the number 12.
; ---------------------------------------------------------------------------------------------------------------------

NXCHAR:     LD HL,(CHAD)
            INC HL
            LD (CHAD),HL
            LD A,(HL)
            RET


; =====================================================================================================================
; FPCP2 -- body of RST &28, the floating point calculator
; =====================================================================================================================
;
; IX becomes the calculator's instruction pointer. Exchanging it with the stacked return address both saves any IX
; belonging to an outer RST &28 (calculator routines are themselves written as calculator programs, so this nests)
; and points IX at the opcode bytes that follow the RST.
;
; Entry:  B  = value to be captured into BCREG, where STKBREG, LDBREG, DECB and USEB can reach it
;         The bytes after the RST are the program to run.
; Exit:   Execution resumes after the terminating EXIT opcode, with IX, BC and the paging all restored.
; ---------------------------------------------------------------------------------------------------------------------

FPCP2:      EX (SP),IX                  ; Save any caller's IX; make IX point at the byte after the RST
            LD (BCREG),BC
            IN A,(LRPORT)
            PUSH AF                     ; Caller's paging
            OR LMPRROM1                 ; ROM1 holds the calculator
            OUT (LRPORT),A
            CALL FPCMAIN
            POP AF
            EX (SP),IX                  ; Recover the caller's IX; (SP) now points past the EXIT opcode

LRPOUT:     LD BC,(BCREG)               ; Also the common exit for FPEXIT2
            OUT (LRPORT),A
            RET

            DS &0100-$                  ; Pad up to the jump table (zero bytes in this build)


; =====================================================================================================================
; THE PUBLIC JUMP TABLE AT &0100
; =====================================================================================================================
;
; Fixed three-byte entries that external code calls by address. Entries that reach ROM1 use RST &30, so the caller
; never has to know which ROM a routine lives in or manage the paging itself.
;
; Documented in full in docs/machine-code-interface.md.
; ---------------------------------------------------------------------------------------------------------------------

            RST &30
            DW JSCRN-&8000              ; &0100  Select screen C as the current output screen
            JP JSVIN                    ; &0103  Call a routine with the system page mapped and a private stack
            RST &30
            DW HEAPROOM-&8000           ; &0106  Reserve (or with negative BC release) BC bytes of heap
            JP WKROOM                   ; &0109  Open BC bytes at the end of workspace
            JP MKRBIG                   ; &010C  Open A*16K + BC bytes at HL
            JP CALBAS                   ; &010F  Execute BASIC line HL as a subroutine
            JP SETSTRM                  ; &0112  Select the stream in A
            JP POMSG                    ; &0115  Print message A from the list at DE
            JP EXPT1NUM                 ; &0118  Evaluate a numeric expression at (CHAD)
            JP EXPTSTR                  ; &011B  Evaluate a string expression at (CHAD)
            JP EXPTEXPR                 ; &011E  Evaluate an expression of either type at (CHAD)
            JP GETINT                   ; &0121  Pop the calculator stack top as an integer into BC (HL = BC, A = C)
            JP STKFETCH                 ; &0124  Pop a string descriptor: A = start page, DE = start, BC = length
            JP STKSTORE                 ; &0127  Push a 5-byte entry from A, E, D, C, B
            JP SBUFFET                  ; &012A  Pop a string and copy it to the buffer in the system page.
                                        ;        Errors if it is longer than 255 bytes.

            JP FARLDIR                  ; &012D  Copy (PAGCOUNT*16K + MODCOUNT) bytes from page A, HL to page C, DE
            JP FARLDDR                  ; &0130  As above but descending, for overlapping upward moves

            JP JPUT                     ; &0133  PUT a block
            JP JGRAB                    ; &0136  GRAB a block
            JP JPLOT                    ; &0139  Plot a point
            JP JDRAW                    ; &013C  Draw a relative line
            JP JDRAWTO                  ; &013F  Draw to an absolute position
            JP JCIRCLE                  ; &0142  Draw a circle
            JP JFILL                    ; &0145  Flood fill
            JP JBLITZ                   ; &0148  Execute a BLITZ graphics string
            JP JROLL                    ; &014B  Roll or scroll an area
            JP CLSBL                    ; &014E  Clear the whole screen if A is zero, otherwise the window
            JP CLSLOWER                 ; &0151  Clear the lower screen
            RST &30
            DW JPALET-&8000             ; &0154  Set a palette entry.
                                        ;        A = scan line or &FF for none, B/C = colours, E = palette entry.
            RST &30
            DW JOPSCR-&8000             ; &0157  Open a screen

MODET:      RST &30
            DW MODPT2-&8000             ; &015A  Set the screen mode in A
            RST &30
            DW JTCOPY-&8000             ; &015D  Text COPY (via the DMPV vector)
            RST &30
            DW JGCOPY-&8000             ; &0160  Graphics COPY (via the DMPV vector)

            JP RECLAIM2                 ; &0163  Close up BC bytes at HL
            JP KBFLUSH                  ; &0166  Empty the keyboard queue
            JP READKEY                  ; &0169  Read the keyboard as INKEY$ does, flushing the buffer.
                                        ;        Z and NC if no key, CY and NZ with the code in A if there is one.
            JP KYIP2                    ; &016C  Take a key from the queue without waiting

            RST &30
            DW BEEPP2-&8000             ; &016F  Sound DE-1 cycles at a half period of HL units of 8T

            RST &30
            DW SABYTES-&8000            ; &0172  Save a block to tape or network

            RST &30
            DW LDBYTES-&8000            ; &0175  Load or verify a block from tape or network

JLDVD:      RST &30
            DW LDVD2-&8000              ; &0178  Load (CY) or verify CDE bytes at HL from the selected device

            JP EDGE2                    ; &017B  Tape edge timer

JPFSTRS:    RST &30
            DW PFSTRS-&8000             ; &017E  Convert the calculator stack top to text in the print buffer

SENDA:      RST &30
            DW SNDA2-&8000              ; &0181  Send the byte in A to the printer

                                        ; --- Added in version 1.1 ---

            RST &30
            DW IMSCSR-&8000             ; &0184  SCREEN$ -- identify the character at a screen position

            JP GRCOMP                   ; &0187  Compress a screen cell to one bit per pixel

JGTTOK:     RST &30
            DW GETTOKEN-&8000           ; &018A  Match the text at DE against A-1 words of the list at HL+1

            RST &30
            DW JCLSCR-&8000             ; &018D  Close a screen


; =====================================================================================================================
; MODECMD -- the MODE command
; =====================================================================================================================
;
; MODE 1 to MODE 4 select internal modes 0 to 3. Performs a full clear and rebuilds the pixel expansion table if the
; new mode needs one.
; ---------------------------------------------------------------------------------------------------------------------

MODECMD:    CALL SYNTAX6                ; Insist on a numeric argument (returns early at syntax check time)

            LD DE,(MODEMAX*256)+ERR_BADMODE
            CALL LIMDB                  ; D = limit, E = error code. Accept 1-4, decrement to internal 0-3.
            JR MODET                    ; Enter the jump table slot, which reaches MODPT2 in ROM1


; ---------------------------------------------------------------------------------------------------------------------
; OTCD -- print the digit in A. Falls into RST102, so the character is emitted through the current channel.
; ---------------------------------------------------------------------------------------------------------------------

OTCD:       LD E,"0"
            ADD A,E


; ---------------------------------------------------------------------------------------------------------------------
; RST102 -- body of RST &10, print the character in A
;
; Every character the ROM prints passes through here. The output address is fetched from the current channel each
; time, which is what lets the control-code handlers temporarily divert output to collect their operands.
;
; Entry:  A = character
; Exit:   All registers except AF preserved.
; ---------------------------------------------------------------------------------------------------------------------

RST102:     PUSH IX
            PUSH HL
            PUSH DE
            PUSH BC
            LD HL,(CURCHL)
            CALL HLJPI                  ; Call the channel's output routine
            POP BC
            POP DE
            POP HL
            POP IX
            RET


; ---------------------------------------------------------------------------------------------------------------------
; S16OP -- output routine for channel '$' (stream 16)
;
; Appends the character to the string variable named in STRM16NM. The body lives in ROM0 but must run with ROM1
; paged out so it can reach the variables area.
; ---------------------------------------------------------------------------------------------------------------------

S16OP:      EX AF,AF'
            PUSH AF
            LD BC,S16OSR
            CALL R1OF2                  ; Call S16OSR with ROM1 off
            POP AF
            EX AF,AF'
            RET


; ---------------------------------------------------------------------------------------------------------------------
; INPUTAD -- call the current channel's input routine
;
; The input address is the second word of the channel record, hence the two increments.
; ---------------------------------------------------------------------------------------------------------------------

INPUTAD:    EXX
            PUSH HL
            LD HL,(CURCHL)
            INC HL
            INC HL
            CALL HLJPI
            POP HL
            EXX
            RET


; ---------------------------------------------------------------------------------------------------------------------
; HLJPI -- jump to the address stored at (HL)
; ---------------------------------------------------------------------------------------------------------------------

HLJPI:      LD E,(HL)
            INC HL
            LD D,(HL)
            EX DE,HL
            JP (HL)


; ---------------------------------------------------------------------------------------------------------------------
; PRMAIN -- the standard channel output routine, installed in channels K, S and P
; ---------------------------------------------------------------------------------------------------------------------

PRMAIN:     RST &30
            DW PROM1-&8000              ; The main print routine lives in ROM1


; =====================================================================================================================
; RST30L2 -- body of RST &30, the inter-ROM link
; =====================================================================================================================
;
; Entry:  Called by RST &30. The word following the RST is the ROM1 target minus &8000.
; Exit:   For a call, returns to the instruction after the word. For a jump, never returns to the caller.
;
; Bit 15 of the stored word doubles as the call/jump selector: a ROM1 address is &C000 or above, so the assembled
; word already has bit 15 set for "call". A source line that deliberately omits the -&8000 leaves bit 15 clear and
; is treated as a jump, with the caller's return address discarded.
;
; A caller above &3FFF is not in ROM0 at all, so it is redirected through RST30V instead.
; ---------------------------------------------------------------------------------------------------------------------

RST30L2:    EX (SP),HL                  ; HL = address of the word after the RST
            PUSH AF
            LD A,H
            CP &40
            JR NC,RST30L4               ; Caller is outside ROM0, so use the user vector

            LD (BCSTORE),BC
            LD C,(HL)
            INC HL
            LD B,(HL)                   ; BC = target
            INC HL                      ; HL = return address
            BIT 7,B
            JR NZ,RST30L3               ; Bit 15 set: an ordinary call into ROM1

            SET 7,B                     ; Bit 15 clear meant "jump", so complete the address ...
            POP AF
            POP HL                      ; ... restore HL and discard the return address
            JR R1ONCLBC

RST30L3:    POP AF
            EX (SP),HL                  ; Put the return address back and recover the caller's HL

; ---------------------------------------------------------------------------------------------------------------------
; R1ONCLBC -- call BC with ROM1 paged in, restoring the entry paging afterwards
; ---------------------------------------------------------------------------------------------------------------------

R1ONCLBC:   EX AF,AF'
            IN A,(LRPORT)
            PUSH AF
            OR LMPRROM1
            JR R1OFON

RST30L4:    POP AF
            EX (SP),HL
            PUSH HL
            LD HL,(RST30V)
            EX (SP),HL
            RET                         ; "Return" to the vector with every register intact


; =====================================================================================================================
; ROM1-OFF CALL HELPERS
; =====================================================================================================================
;
; The mirror image of RST &30: these let ROM1 code reach ROM0 routines, or reach data that ROM1 is hiding. The
; original paging is always restored, so the caller need not care how it was entered.
; ---------------------------------------------------------------------------------------------------------------------

; ---------------------------------------------------------------------------------------------------------------------
; R1OFFJP -- jump to the address in the following word, with ROM1 off
;
; The caller's return address is discarded, making this a jump; the entry paging is still restored when the target
; eventually returns.
; ---------------------------------------------------------------------------------------------------------------------

R1OFFJP:    EX (SP),HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            POP HL
            JR R1OFFCLBC


; ---------------------------------------------------------------------------------------------------------------------
; R1OFFCL -- call the address in the following word, with ROM1 off
;
; May be called from anywhere. The original ROM1 state is restored on return.
; ---------------------------------------------------------------------------------------------------------------------

R1OFFCL:    EX (SP),HL
            LD C,(HL)
            INC HL
            LD B,(HL)
            INC HL
            EX (SP),HL                  ; BC = target, return address stepped past the word


; ---------------------------------------------------------------------------------------------------------------------
; R1OFFCLBC -- call BC with ROM1 off
;
; Entry:  BC = target address. All registers except AF' are passed through to it.
; Exit:   All registers except AF' come back from it; the entry paging is restored.
; ---------------------------------------------------------------------------------------------------------------------

R1OFFCLBC:  EX AF,AF'

R1OF2:      IN A,(LRPORT)
            PUSH AF                     ; Entry paging
            AND LMPRNOR1                ; ROM1 off

R1OFON:     OUT (LRPORT),A              ; Shared by the ROM1-on path above
            EX AF,AF'
            CALL LDBCJP
            EX AF,AF'
            POP AF
            OUT (LRPORT),A
            EX AF,AF'
            RET

; ---------------------------------------------------------------------------------------------------------------------
; LDBCJP -- restore BC from BCSTORE and jump to the target already in BC
; ---------------------------------------------------------------------------------------------------------------------

LDBCJP:     PUSH BC
            LD BC,(BCSTORE)
            RET


; ---------------------------------------------------------------------------------------------------------------------
; R1XJP -- page ROM1 out permanently and jump to (BC)
;
; Used where control is leaving ROM1 for good, so there is nothing to restore.
; ---------------------------------------------------------------------------------------------------------------------

R1XJP:      IN A,(LRPORT)
            AND LMPRNOR1
            OUT (LRPORT),A
            PUSH BC
            RET


; =====================================================================================================================
; SOP2 -- string output, the body of PRINTSTR (&0013)
; =====================================================================================================================
;
; Entry:  DE = start of the data, already paged in
;         BC = number of bytes; zero means do nothing
; Exit:   DE points just past the last byte, BC = 0, HL corrupt.
;
; If the channel provides a block output entry -- flagged by a &40 byte at the start of its record, followed by a
; JR over the flag -- the whole string is handed over in one call. Otherwise it is emitted a character at a time
; through RST &10.
; ---------------------------------------------------------------------------------------------------------------------

SOP2:       PUSH DE
            LD HL,(CURCHL)              ; Fetch the channel's output address
            LD E,(HL)
            INC HL
            LD D,(HL)
            EX DE,HL
            POP DE                      ; DE = source, HL = channel routine
            IN A,(LRPORT)
            PUSH AF
            AND LMPRNOR1                ; ROM1 off -- the data may be in the program area
            OUT (LRPORT),A
            LD A,(HL)
            CP &40
            JR NZ,SOP3                  ; No block output provided, so loop on RST &10

            INC HL
            INC HL
            INC HL                      ; Step over the "&40, JR xx" marker to the string routine proper
            CALL HLJUMP
            JR SOP4

SOPL:       LD A,(DE)
            RST &10
            INC DE
            LD A,D
            CP &C0
            CALL NC,INCURPDE            ; Source ran into section D: step the page and pull DE back

SOP3:       LD A,B
            OR C
            DEC BC
            JR NZ,SOPL

SOP4:       POP AF
            OUT (LRPORT),A
            RET


; ---------------------------------------------------------------------------------------------------------------------
; R1OFRD -- read the byte at (HL) with ROM1 paged out
;
; The one-instruction read used wherever ROM1 code needs to see a byte of the BASIC program.
; ---------------------------------------------------------------------------------------------------------------------

R1OFRD:     PUSH BC
            CALL R1OFFCL
            DW NRREAD
            POP BC
            RET


; =====================================================================================================================
; JSVIN -- call a routine with the system page mapped (jump table entry &0103)
; =====================================================================================================================
;
; Entry:  The word following the CALL is the target address.
;         A = a value passed straight through to the target.
; Exit:   Everything is restored: the caller's paging, stack and registers.
;
; Gives external code a safe way to run something that needs the system variables mapped at &4000 without having to
; know the paging rules or find a stack that survives the switch.
; ---------------------------------------------------------------------------------------------------------------------

JSVIN:      EXX
            POP HL                      ; Return address, which points at the target word
            LD E,(HL)
            INC HL
            LD D,(HL)
            INC HL
            PUSH HL                     ; Return address for the caller, now past the word
            LD C,A                      ; Preserve the entry A briefly
            IN A,(LRPORT)
            LD B,A                      ; Entry LMPR
            LD A,LMPRSYS
            DI
            OUT (LRPORT),A              ; System page at &4000, ROM0 on, ROM1 off
            LD (JVSP),SP
            LD SP,ISPVAL-&40            ; Private stack, clear of the caller's
            EI
            PUSH BC
            LD HL,JSVIN2                ; Return address for the target
            PUSH HL
            PUSH DE                     ; Target address
            LD A,C                      ; Entry A
            EXX
            RET                         ; "Return" to the target with the main registers intact; it then
                                        ; "returns" to JSVIN2

JSVIN2:     EX AF,AF'
            POP AF                      ; Entry LMPR, stacked as B above
            DI
            LD SP,(JVSP)
            OUT (LRPORT),A
            EI
            EX AF,AF'
            RET


; =====================================================================================================================
; STRMTAB -- initial stream table
; =====================================================================================================================
;
; Displacements from the start of the channel area to each channel record. Copied into STREAMS at startup and by NEW.
; The first five entries are the fixed system streams -5 to -1; the last four are user streams 0 to 3.
; ---------------------------------------------------------------------------------------------------------------------

STRMTAB:    DB 26,21,1,6,11             ; Streams &FB-&FF: channels B, $, K, S, R (fixed)
            DB 1,1,6,16                 ; Streams 0-3: channels K, K, S, P
