; =====================================================================================================================
; SAMROM.ASM -- Build glue for the SAM Coupe ROM 3.0
; =====================================================================================================================
;
; Assembles the complete 32K ROM image with pyz80:
;
;     pyz80.py --obj=samrom.bin --exportfile=samrom.sym -o /dev/null samrom.asm
;
; The image is two independent 16K ROMs that share one binary:
;
;   ROM0  &0000-&3FFF   Always visible in section A. Holds the restarts, the public jump table at &0100, the line
;                       editor, the interpreter main loop, the expression evaluator front end, variable handling and
;                       the graphics primitives.
;
;   ROM1  &C000-&FFFF   Paged into section D on demand (LMPR bit 6, driven by the RST &30 mechanism). Holds the
;                       floating-point calculator and arithmetic, the print/token output routines, tape and network
;                       I/O, screen and interrupt handling, and the keyword and message tables.
;
; The two halves are assembled at their runtime addresses but dumped consecutively, so the file offset of a ROM1
; routine is (address - &C000) + &4000.
;
; Include order note: the annotated build pulls the two pure-EQU files in first so that every module can refer to
; hardware, token and system-variable names symbolically. Neither file emits any bytes, so the image is unchanged.
;
; =====================================================================================================================

            ; --- Definitions. These emit no code and must precede everything that uses them. ---
            include "equates.asm"       ; Named constants: errors, tokens, flag bits, paging (new in this build)
            include "vars.asm"          ; System variable addresses and fixed buffer locations

            ; --- ROM0 is assembled at &0000 but written to the start of the image ---
            DUMP &8000

            include "main.asm"          ; Restarts, interrupt entries, public jump table, inter-ROM call helpers
            include "editor.asm"        ; Line editor: key dispatch, cursor movement, DEF KEY expansion
            include "list.asm"          ; AUTOLIST, LIST/LLIST, the CLS family, PRINT, program cursor movement
            include "roll.asm"          ; ROLL and SCROLL, window clear, editor scroll, pixel row stepping
            include "mainlp.asm"        ; Interpreter main loop: syntax pass, statement dispatch, error handling
            include "misc1.asm"         ; Streams and channels, temporary colour variables, READ, POKE/DPOKE
            include "lookvar.asm"       ; Variable lookup: name parsing, numeric chains, string/array search
            include "eval.asm"          ; Expression evaluator, operator priorities, numeric literal conversion
            include "do.asm"            ; DO/LOOP, IF/ELSE, FOR/NEXT, GOTO/GOSUB support, BASIC stack, line finder
            include "tadjm.asm"         ; FP stack helpers, program search, MAKEROOM/RECLAIM, page-form arithmetic
            include "graph0.asm"        ; CIRCLE and DRAW
            include "graph1.asm"        ; PLOT and the per-mode pixel plotting subroutines
            include "graph2.asm"        ; BLITZ, FILL, check-screen transfer, coordinate scaling
            include "grabput.asm"       ; GRAB and PUT block graphics, FARLDIR/FARLDDR cross-page block moves
            include "assign.asm"        ; Assignment, DIM, string slicing, variable creation
            include "fn.asm"            ; DEF FN/FN, DEF PROC/PROC, LOCAL, the call-site compile pass
            include "nparpro.asm"       ; PROC parameter binding (by value and by REF), RESTORE, local teardown
            include "misc2.asm"         ; RST 8 error entry and DOS hand-off, ROM1-to-RAM stubs, LET, RUN/CLEAR
            include "endprint.asm"      ; Per-mode character rendering, screen addressing, string compare

            ; --- ROM1 must start on the second 16K boundary: both ROMs assume this layout when paging ---
            DUMP &C000

            include "miscx1.asm"        ; RAM-relocated bodies: RENUM, GET, DELETE, KEYIN, POP, INPUT
            include "miscx2.asm"        ; RAM-relocated bodies: DEF KEYCODE, DEF FN, the tokeniser, MERGE
            include "fpcmain.asm"       ; Floating-point calculator: opcode table and control loop
            include "transend.asm"      ; Transcendental functions and the Chebyshev series engine
            include "mult.asm"          ; FP multiply, divide, add, subtract and number form conversion
            include "rom1fns.asm"       ; VAL, RND, ATTR, POINT, INKEY$, CHR$, BIN$/HEX$, MEM$, string concatenation
            include "scrsel1.asm"       ; OPEN/CLOSE screens and streams, page allocation, all interrupt handling
            include "scrsel2.asm"       ; GOTO/GOSUB, GETTOKEN keyword matcher, MODE, CSIZE, AUTO, SOUND, BOOT
            include "printfp.asm"       ; Number to text conversion and power-of-ten scaling
            include "tprint.asm"        ; Character and token output, control codes, scroll prompts
            include "tapemn.asm"        ; SAVE/LOAD/MERGE/VERIFY command parsing and execution
            include "tapex.asm"         ; Tape and network block level I/O, edge timing
            include "using.asm"         ; Pointer adjustment after MAKEROOM/RECLAIM, heap, INSTR, LENGTH, STRING$
            include "misc31.asm"        ; CALL, machine initialisation, NEW, charset unpacking, PALETTE
            include "misc32.asm"        ; BEEP and sound effects, KEY, DEVICE, PAUSE, BORDER, WINDOW, OUT
            include "scrfn.asm"         ; COPY, SCREEN$, OUTLINE (the lister/detokeniser), cursor output
            include "text.asm"          ; Data: messages, keyword table, key maps, command address table, charset
