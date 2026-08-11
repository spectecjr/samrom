; =====================================================================================================================
; ROMTEST.ASM -- compare a freshly assembled ROM image against the ROM in the running machine
; =====================================================================================================================
;
; This is a standalone diagnostic, not part of the ROM. It is assembled on its own and produces an autoexecuting
; CODE file: load it on a SAM and it reports every byte where the assembled image differs from the ROM the machine
; is actually running, then, if all is well, hot-patches the assembled ROM0 over the live one.
;
;     pyz80 romtest.asm
;
; HOW IT WORKS
; ------------
; The program runs at &7000, in section B of the low memory area. `include "samrom.asm"` at the bottom appends the
; whole 32K ROM image immediately after it, so the assembled ROM0 lands at &8000 in the same physical page sequence
; the paging hardware can reach. Each half is then compared against the live ROM in turn:
;
;     assembled ROM0 at &8000   vs   live ROM0 at &0000
;     assembled ROM1 at &8000   vs   live ROM1 at &C000   (after paging both into view)
;
; Any difference is printed as four hex digits of address followed by the expected and actual bytes. A clean run
; prints "OK".
;
; WHY THE LITERALS STAY
; ---------------------
; `samrom.asm` is included at the *end* of the file, so none of the ROM's own EQUs -- LRPORT, URPORT, the jump table
; addresses -- are defined yet when the code above is assembled. The port numbers and entry addresses therefore have
; to be written as literals. For reference:
;
;     &015A = MODET      set the screen mode
;     &0112 = SETSTRM    select the output stream
;     port 250 = LMPR    low memory page register; bit 5 pages ROM0 out, bit 6 pages ROM1 into section D
;     port 251 = HMPR    high memory page register; selects the page seen at &8000
;
; NOTE
; ----
; The final LDIR overwrites part of the assembled image's own working view, which is why the comparison must be
; complete before it runs. The program halts afterwards rather than returning.
;
; =====================================================================================================================

        org &7000
        dump $
        autoexec

        xor a                 ; MODE 1
        call &015a            ; MODET
        ld  a,2               ; Stream 2, the main screen
        call &0112            ; SETSTRM

; --- Compare ROM0: the assembled copy at &8000 against the live ROM at &0000 ---

        ld  hl,&8000          ; Assembled ROM0
        ld  de,&0000          ; Live ROM0
lp:     ld  a,(de)
        cp  (hl)
        call nz,mismatch
        inc hl
        inc de
        bit 6,d               ; Stop once DE reaches &4000, that is 16K
        jr  z,lp

; --- Page both copies of ROM1 into view and compare them ---

        ld  a,2               ; Page 2 holds the second half of the assembled image
        out (251),a           ; Assembled ROM1 now visible at &8000

        in  a,(250)
        or  %01000000         ; Enable ROM1
        out (250),a           ; Live ROM1 now visible at &C000

        ld  hl,&8000          ; Assembled ROM1
        ld  de,&c000          ; Live ROM1
lp2:    ld  a,(de)
        cp  (hl)
        call nz,mismatch
        inc hl
        inc de
        bit 6,d               ; Stop once DE wraps past &FFFF, that is 16K
        jr  nz,lp2

        ld  a,"O"
        rst 16
        ld  a,"K"
        rst 16

; --- Install the assembled ROM0 over the live one ---

        ld  a,1               ; Page 1: the whole assembled image now spans &8000-&FFFF
        out (251),a

        di                    ; The LMPR change swaps the code under our feet, so no interrupts
        in  a,(250)
        and %10111111         ; ROM1 off
        or  %00100000         ; ROM0 off, so &0000-&3FFF becomes writable RAM
        out (250),a

        ld  hl,&8000
        ld  de,&0000
        ld  bc,&4000
        ldir                  ; Copy the assembled ROM0 into place

        halt                  ; Done


; ---------------------------------------------------------------------------------------------------------------------
; mismatch -- report one differing byte as "aaaa xx yy"
;
; Entry:  DE = the address in the live ROM, HL = the corresponding address in the assembled image.
; Exit:   all registers preserved.
;
; The four values are pushed and popped in reverse print order so that a single register can carry each in turn.
; ---------------------------------------------------------------------------------------------------------------------

mismatch:
        push de
        push hl
        ld  a,(hl)
        push af               ; The assembled byte, printed last
        ld  a,(de)
        push af               ; The live byte
        ld  a,e
        push af               ; The address low byte
        ld  a,d
        call prhex            ; Address high byte
        pop af
        call prhex            ; Address low byte
        ld  a," "
        rst 16
        pop af
        call prhex            ; Live byte
        ld  a," "
        rst 16
        pop af
        call prhex            ; Assembled byte
        ld  a,13
        rst 16
        pop hl
        pop de
        ret


; ---------------------------------------------------------------------------------------------------------------------
; prhex -- print A as two hexadecimal digits
;
; A is stacked so the low nibble can be recovered after the high one has been printed. Each nibble is converted by
; adding "0" and, if the result is past "9", pushing it on into the letter range.
; ---------------------------------------------------------------------------------------------------------------------

prhex:  push af
        rra
        rra
        rra
        rra
        and %00001111
prhexd: add a,"0"
        cp  "9"+1
        jr  c,prleft
        add a,"A"-"0"-10
prleft: rst 16
        pop af
        and %00001111
        add a,"0"
        cp  "9"+1
        jr  c,prright
        add a,"A"-"0"-10
prright:rst 16
        ret

; The whole 32K ROM image is appended here, so it lands at &8000 onwards.
include "samrom.asm"
