; =====================================================================================================================
; GRAPH0.ASM -- CIRCLE and DRAW
; =====================================================================================================================
;
; The two drawing commands that generate many points from a few parameters. Both take the same approach: work out
; once which plot routine applies (SETIY, in graph1.asm), then run a tight integer loop that calls it through IY.
;
; CIRCLE
; ------
; A midpoint circle algorithm exploiting eightfold symmetry. Only one octant is stepped; each position generated
; there yields eight points, obtained by swapping and negating the two displacements. The nesting of CIRCEX,
; CIRC3, CIRC4, CIRCP5 and CIRC6 is a chain of fall-throughs -- each level calls the next and then falls into it,
; so "do 8 points" is literally "do 4 points, twice, with the displacements swapped".
;
; DRAW
; ----
; Bresenham's line algorithm. C accumulates the tracking error; H holds the larger of the two coordinate
; differences and L the smaller. Each pass adds the smaller difference to the error and, when that overflows,
; steps on both axes instead of one.
;
; The alternate register set carries the loop state that must survive a call to the plot routine:
;
;     HL'   the current coordinates, Y in H and X in L
;     DE'   the step along the faster-changing axis alone
;     BC'   the diagonal step, both axes at once
;
; Both step values are precomputed as 16-bit addends so that a single ADD HL,BC moves the point. A negative X step
; is held as &FF in the low byte, which would carry into the Y byte, so the Y byte is pre-decremented to compensate
; -- that is what the INC C / DEC B / DEC C sequences in DRMSUB are doing.
;
; RUNNING OFF THE EDGE
; --------------------
; Rather than range-check every plotted point, DRAW checks before it starts whether the line can possibly leave the
; screen. If it cannot, IX points at PRLABEL and each plot returns straight into the loop. If it can, IX points at
; PLOTCHK instead, which tests the coordinates after each point and reports "Off screen" when one goes out of range.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; JCIRCLE -- draw a circle (jump table entry &013C)
;
; Entry:  A = the radius, C = X and B = Y, HL = the thin-pixel X offset.
; ---------------------------------------------------------------------------------------------------------------------

JCIRCLE:   PUSH AF
           LD (TEMPW1),HL
           JR JCIRC3


; ---------------------------------------------------------------------------------------------------------------------
; CIRCLE -- the CIRCLE command
; ---------------------------------------------------------------------------------------------------------------------

CIRCLE:    CALL SYNTAX9                     ; Colour items, then X and Y
           CALL INSISCOMA
           CALL SYNTAX6                     ; The radius; X and Y are already on the calculator stack

           CALL GETBYTE                     ; Radius into A and C

; --- CIRCLEFD: the entry BLITZ uses, with the parameters already prepared ---

CIRCLEFD:
           PUSH BC                          ; Radius in C
           PUSH AF
           RST &30
           DW CIFILSR                       ; Bit 15 set, so this is a CALL into ROM1: clips the centre and sets
                                            ; TEMPW1 to the thin-pixel offset

           POP AF

JCIRC3:    LD IX,CIRCEXT                    ; Where the plot routine returns to
           LD D,A                           ; Radius
           SRL A
           EX AF,AF'                        ; Half the radius, kept in A' as the initial tracking error
           LD E,3                           ; BLITZ record code for CIRCLE
           LD A,(THFATT)
           AND A
           CALL NZ,GRAREC                   ; Record it if RECORD is active and pixels are fat
           CALL SPSS                        ; Save the paging, map the screen
           CALL SETIY
           JR NC,CIRCTK

           LD IY,THCIRCSR                   ; Thin pixels need the wrapper below

CIRCTK:    EXX
           LD D,A                           ; D' = the mode 2/3 plot ink, ignored in other modes
           EXX

           LD D,B
           LD E,C                           ; DE = the centre, Y in D and X in E
           POP HL                           ; L = the radius
           INC L
           DEC L
           JR NZ,DOCIRCLE

           EX DE,HL                         ; A zero radius is just a point at the centre
           LD IX,TRCURP
           JP (IY)


; ---------------------------------------------------------------------------------------------------------------------
; DOCIRCLE -- the midpoint circle loop
;
; L holds the displacement along one axis and H along the other. The first four points -- the extremes of the two
; axes -- are handled specially before the loop, because at those positions the eight symmetric points collapse into
; four and plotting them twice would leave gaps under OVER 1.
; ---------------------------------------------------------------------------------------------------------------------

DOCIRCLE:  LD H,0

           CALL CIRCP5                      ; The left and right extremes
           LD A,L
           LD L,H
           LD H,A
           CALL CIRC6                       ; The top
           PUSH HL
           XOR A
           SUB H
           LD H,A
           CALL CIRC6                       ; The bottom
           POP HL
           INC L                            ; Start the loop one step in, so those four are not repeated

; --- The main loop: one octant position per pass, eight plotted points ---

CIRC0:     CALL CIRCEX

           INC L
           EX AF,AF'
           SUB L                            ; Tracking error minus the new displacement
           JR NC,CIRC2

           ADD A,H                          ; The error went negative, so step in on the other axis
           DEC H

CIRC2:     EX AF,AF'
           LD A,L
           SUB H
           JP C,CIRC0                       ; Loop until the two displacements meet at 45 degrees

           DEC A
           CALL NZ,CIRCP4                   ; If the arcs have not quite met, fill in the last four points

           JP TRCURP                        ; Restore the paging


; ---------------------------------------------------------------------------------------------------------------------
; The symmetry chain. Each entry does its own work and falls into the next, so:
;
;     CIRCEX   eight points   -- CIRC3 twice
;     CIRC3    four points    -- CIRC4 twice, with the displacements swapped
;     CIRC4    two points     -- CIRCP5 with H negated, then CIRCP5 again
;     CIRCP5   the right-hand point, then falls into CIRC6
;     CIRC6    the left-hand point, then falls into CIRC5
;     CIRC5    one point
; ---------------------------------------------------------------------------------------------------------------------

CIRCEX:    CALL CIRC3

CIRC3:     LD A,L
           LD L,H
           LD H,A                           ; Swap the displacements: reflect about the diagonal

CIRCP4:    CALL CIRC4

CIRC4:     XOR A
           SUB H
           LD H,A                           ; Negate H: reflect into the lower half

CIRCP5:    LD A,E                           ; X of the centre
           ADD A,L
           CALL NC,CIRC5                    ; Plot on the right, unless the X coordinate wrapped

CIRC6:     LD A,E
           SUB L
           RET C                            ; The left-hand point is off the edge

CIRC5:     LD B,H
           LD C,L                           ; Preserve the displacements across the plot
           LD L,A                           ; X
           LD A,D
           ADD A,H
           CP 192
           JR NC,CIRCEXT                    ; Y off the top or bottom

           LD H,A

CIPLOT:    JP (IY)                          ; Plot HL, returning to CIRCEXT

CIRCEXT:   LD H,B
           LD L,C
           RET


; ---------------------------------------------------------------------------------------------------------------------
; THCIRCSR -- thin-pixel plot wrapper for CIRCLE
;
; The circle loop works in eight-bit coordinates, but a thin-pixel mode 2 screen is 512 pixels wide. TEMPW1 holds
; the offset that maps the loop's eight-bit X back onto the real screen: zero if the centre is in the left half,
; &0100 if it is in the right, and something in between otherwise -- so the eight-bit X plus the offset is always
; in range.
;
; Entry:  H = Y, already range-checked; L = X.
; ---------------------------------------------------------------------------------------------------------------------

THCIRCSR:  PUSH IX
           PUSH DE
           PUSH BC
           LD B,H                           ; B = Y
           EX DE,HL                         ; E = X
           LD D,0
           LD HL,(TEMPW1)

           ADD HL,DE                        ; The real X
           CALL M2CTPLOT                    ; Plot without disturbing the coordinate system variables
           POP BC
           POP DE
           POP IX
           JP (IX)                          ; To CIRCEXT, or straight out


; =====================================================================================================================
; DRAW -- the DRAW command
; =====================================================================================================================
;
; Three forms:
;
;     DRAW x,y          a relative line from the current position
;     DRAW TO x,y       an absolute line to a given position
;     DRAW x,y,c        a curved line, with c the curvature in radians
;
; The absolute and relative forms differ only in how the coordinates are resolved: DRAW TO applies the origin
; variables XOS/YOS as well as the ranges XRG/YRG, while the relative form applies only the ranges. Curves are drawn
; in ROM1 by DRCURVE and DRTCRV, which decompose them into short straight segments and re-enter here.
;
; Coordinate convention: with the origin variables at their defaults X runs 0 to 255 (or 511) and Y runs -16 to 175,
; but Y is stored inverted, as 0 at the top down to 191 at the bottom.
; ---------------------------------------------------------------------------------------------------------------------

; --- JDRAWTO: jump table entry &013F. X and Y in C,B or HL,B ---

JDRAWTO:      LD A,(THFATT)
              CP 1
              EX AF,AF'                     ; CY in A' means thin pixels
              JR JDRTO3

DRAW:         SUB TOTOK                     ; Zero if the line reads DRAW TO
              LD (TEMPB3),A
              JR NZ,PASTTO

              RST &20                       ; Step over the TO token

PASTTO:       CALL SYNTAX9
              CP ","
              JR NZ,DRNOCU

              CALL SSYNTAX6                 ; A third parameter: the curvature

              LD HL,TEMPB3
              LD A,(HL)
              AND A
              JR Z,DRNC2                    ; DRAW TO x,y,c

              RST &30
              DW DRCURVE-&8000              ; Bit 15 clear, so this is a JUMP into ROM1: relative curved draw

DRNC2:        LD (HL),H                     ; TEMPB3 non-zero marks the line as curved

              DB CALC
              DB STOD0                      ; Stash the curvature so X and Y are reachable again
              DB EXIT

              JR DRAWTOFD

DRNOCU:       CALL CHKEND

              LD A,(TEMPB3)
              AND A
              JR NZ,DRAWFD                  ; A relative straight line

                                            ; Otherwise DRAW TO, with TEMPB3 = 0 marking it straight

DRAWTOFD:     CALL GTFCOORDS                ; Apply XOS/YOS and XRG/YRG, and unstack the coordinates.
                                            ; B = Y with 0 at the top; HL = X and CY for thin pixels, else C = X.
                                            ; The ranges have already been checked.
              JR C,FDRNR

              LD A,(TEMPB3)
              AND A
              LD E,2                        ; BLITZ record code for a fat DRAW TO
              CALL Z,GRAREC                 ; Only straight lines are recorded; curves recurse into straight ones
              AND A

FDRNR:        EX AF,AF'                     ; CY in A' means thin pixels

; --- Convert the destination into a signed displacement from the current position ---

JDRTO3:       LD A,(YCOORD)
              SUB B
              LD D,&FF                      ; Assume the step is negative
              JR NC,ADJOK2

              NEG
              LD D,&01

ADJOK2:       LD B,A                        ; B = the Y distance, D = its direction
              EX AF,AF'
              JR C,THINADJ

              LD A,(XCOORD)
              SUB C
              LD E,&FF
              JR NC,ADJOK3

              NEG
              LD E,&01

ADJOK3:       LD C,A                        ; C = the X distance, E = its direction
              JR ADJOK5

THINADJ:      PUSH DE
              LD DE,(XCOORD)
              XOR A
              SBC HL,DE                     ; Destination minus current
              INC A                         ; Assume positive
              JR NC,ADJOK4

              EX DE,HL
              LD L,A                        ; L = 1
              DEC A
              LD H,A                        ; H = 0; the 1 compensates for the carry the SBC below will consume
              SBC HL,DE                     ; Negate
              DEC A                         ; A = &FF

ADJOK4:       POP DE
              LD E,A

ADJOK5:       LD A,(TEMPB3)
              AND A
              JR Z,JDRAW

              RST &30
              DW DRTCRV-&8000               ; Curved DRAW TO, in ROM1
            ;  JP DRTCRV

; --- The relative form ---

DRAWFD:       CALL DRCOORDFD                ; Apply XRG/YRG only

DRAWLINE:     CALL TWONUMS                  ; B = Y distance, C = X distance, D and E the directions as 01 or FF;
                                            ; or HL = X with CY for thin pixels

              DEC E                         ; The X direction becomes &FE or &00, which is also the BLITZ record
              CALL NC,GRAREC                ; code for a fat relative DRAW
              INC E


; ---------------------------------------------------------------------------------------------------------------------
; JDRAW -- set up and run the line loop
;
; Register use from here on:
;     HL    H = the larger coordinate difference, L = the smaller
;     DE    the two direction signs, then D alone as the mode 2/3 ink
;     B     the point count, C the tracking error
;     HL'   the current coordinates, DE' the single-axis step, BC' the diagonal step
; ---------------------------------------------------------------------------------------------------------------------

JDRAW:        CALL SPSS
              CALL SETIY                    ; A = the ink for mode 3, CY for thin-pixel mode 2
              JP C,THINDRAW

              EX AF,AF'                     ; A' = the mode 3 ink
              LD IX,PRLABEL                 ; Assume no edge checking is needed
              LD HL,(YCOORD)                ; H = X, L = Y
              LD A,H
              LD H,L
              LD L,A                        ; H = Y, L = X
              PUSH HL

              EXX
              POP HL                        ; HL' = the coordinates
              EXX

; --- Decide whether the line can leave the screen ---

              LD A,C
              AND A
              JR Z,CHKYCO2                  ; A zero X distance cannot run off, and avoids a spurious +/- 0

              LD A,L
              DEC E
              JR Z,DOXADD                   ; Moving right

              AND A
              JR Z,OSERRHP                  ; Moving left from X = 0

              SUB C
              JR CHKYCO

DOXADD:       CP 255
              JR Z,OSERRHP                  ; Moving right from the right-hand edge

              ADD A,C

CHKYCO:       INC E
              JR C,RUNOFF                   ; The X coordinate wrapped

CHKYCO2:      LD A,B
              AND A
              LD A,H
              JR Z,FINCHK2                  ; A zero Y distance cannot run off

              DEC D
              JR Z,DOYADD                   ; Moving down

              AND A
              JR Z,OSERRHP                  ; Moving up from the top

              SUB B
              JR FINCHK

DOYADD:       CP 191

OSERRHP:      JR Z,OSERROR                  ; Moving down from the bottom

              ADD A,B

FINCHK:       INC D                         ; D is the direction again; the carry is untouched
              JR C,RUNOFF

FINCHK2:      CP 192
              JR C,DRMSUBC                  ; The Y coordinate stays in range

RUNOFF:       LD IX,PLOTCHK                 ; The line may leave the screen, so check after each point rather than
                                            ; returning straight to the loop

DRMSUBC:      CALL DRMSUB
              EXX                           ; HL = the final coordinates
              SCF                           ; Signal that the line completed
              JP DRAWEND


; ---------------------------------------------------------------------------------------------------------------------
; DRMSUB -- the Bresenham loop proper
;
; Entry:  B = the Y distance, C = the X distance, D and E the direction signs, HL' = the starting coordinates.
; Exit:   HL' = the final coordinates, with DE' and BC' still holding the step values.
;
; The two step values are built as 16-bit addends whose high byte moves Y and low byte moves X. Because a negative
; step is stored as &FF, adding it to the low byte always carries into the high byte, so the high byte is
; pre-decremented to cancel that carry.
; ---------------------------------------------------------------------------------------------------------------------

DRMSUB:       PUSH DE                       ; The direction flags

              EXX
              POP BC
              INC C
              JR NZ,NDHDIAG

              DEC B                         ; C was &FF, so adding it to L will always carry into H

NDHDIAG:      DEC C                         ; BC' = the diagonal step
              EXX

              LD   A,C
              CP   B
              JR   NC,XGRTR                 ; The X distance is the larger

              LD   L,C                      ; The smaller distance
              LD   E,0                      ; The single-axis step must not move X, since Y changes faster
                                            ; B already holds the larger distance
              JR   DRPREL

XGRTR:        OR   B
              RET  Z                        ; Both distances are zero: there is no line

              LD   L,B                      ; The smaller distance
              LD   B,C                      ; The larger
              LD   D,0                      ; The single-axis step must not move Y

DRPREL:       PUSH DE

              EXX
              POP DE
              INC E
              JR NZ,NDHFLAT

              DEC D                         ; Same carry compensation as for the diagonal step

NDHFLAT:      DEC E                         ; DE' = the single-axis step
              EXX

              EX AF,AF'
              LD D,A                        ; D = the mode 3 ink
              LD H,B                        ; H = the larger distance
              LD A,B                        ; The tracking error starts at half the larger distance, so the line is
              SRL A                         ; symmetric about its midpoint

DRLOOP:       ADD A,L                       ; Accumulate the smaller distance into the error
              JR C,TWOMOVE                  ; It overflowed, so a step on both axes is due

              CP H
              JR C,ONEMOVE                  ; The error has not yet earned a step on the slower axis

TWOMOVE:      SUB H
              LD C,A                        ; Keep the error across the plot

              EXX
              ADD HL,BC                      ; The diagonal step
              JP (IY)                       ; Plot, then return through IX to PRLABEL or PLOTCHK

ONEMOVE:      LD   C,A

              EXX
              ADD HL,DE                     ; The single-axis step
              JP (IY)

PRLABEL:      EXX
              LD   A,C                      ; Recover the tracking error
              DJNZ DRLOOP

              RET                           ; HL' = the coordinates, DE' and BC' still the steps


; ---------------------------------------------------------------------------------------------------------------------
; PLOTCHK -- after each point, when the line might leave the screen
;
; Returns to the loop while the point is comfortably inside; drops through to DRAWEND once an edge is reached.
; ---------------------------------------------------------------------------------------------------------------------

PLOTCHK:      LD A,L
              INC A
              CP 2
              CCF
              JR NC,DRAWEND                 ; X reached 0 or 255

              LD A,H
              DEC A                         ; 0 becomes 255, 191 becomes 190
              CP 190
              JR C,PRLABEL                  ; Still inside, so carry on

DRAWEND:      PUSH AF                       ; NC records that an edge was hit
              LD A,H
              LD H,L
              LD L,A
              LD (YCOORD),HL                ; Record where the line stopped
              CALL TRCURP
              POP AF
              RET C                         ; The line completed normally

OSERROR:      RST &08
              DB 32                         ; "Off screen"


; ---------------------------------------------------------------------------------------------------------------------
; THINDRAW -- thin-pixel line drawing in mode 2
;
; The Bresenham loop only handles eight-bit distances, but a thin-pixel X distance can be up to 511. The line is
; therefore repeatedly halved until it fits, drawn at that scale, and the halving undone by the coordinate wrapper
; -- each halved pass rounds up, so the endpoint is still reached exactly.
;
; Entry:  B = the Y distance, HL = the X distance, D and E the direction signs.
; ---------------------------------------------------------------------------------------------------------------------

THINDRAW:     EXX
              LD HL,0                       ; The wrapper works from the coordinate variables, so start at zero
              EXX
              LD IY,THINDR2

DUBT:         LD A,H
              AND A
              JR Z,EASYTHIN                 ; The X distance already fits in eight bits

              RRA
              LD A,L
              RRA                           ; A = half the X distance
              LD C,A
              PUSH AF                       ; Keep it, and CY if the distance was odd
              LD A,B
              AND A
              RRA
              LD B,A
              PUSH AF                       ; Half the Y distance, and CY if it was odd
              PUSH DE
              CALL DRMSUB                   ; Draw the first half
              POP DE
              POP AF
              ADC A,0                       ; Round up if it was odd
              LD B,A
              POP AF
              LD H,1
              ADC A,0                       ; Could come back to zero if the original was &1FF
              LD L,A
              JR C,DUBT                     ; HL = &0100, so it must be halved again

EASYTHIN:     LD C,L
              CALL DRMSUB
              JP TRCURP


; ---------------------------------------------------------------------------------------------------------------------
; THINDR2 -- thin-pixel plot wrapper for DRAW
;
; The loop's coordinates are reset to zero after every point, so HL' only ever holds one step's worth of movement --
; which means it equals either the diagonal step or the single-axis step. The real position is kept in XCOORD and
; YCOORD and updated one step at a time here.
; ---------------------------------------------------------------------------------------------------------------------

THINDR2:      PUSH BC
              PUSH DE
              EX DE,HL
              LD A,(YCOORD)
              ADD A,D
              LD B,A
              LD HL,(XCOORD)
              LD A,E
              AND A
              JR Z,TPNCHNG                  ; No X movement this step

              JP P,TPINC

              INC B                         ; Undo the carry compensation built into the step value
              DEC HL
              DEC HL                        ; One extra, cancelled by the INC below

TPINC:        INC HL

              LD A,H
              CP 2
              JR NC,OSERROR                 ; X went past 511 or below zero

              LD A,B
              CP 192
              JR NC,OSERROR

TPNCHNG:      CALL TDPLOT
              LD HL,0                       ; Reset the loop's notion of position
              POP DE
              POP BC
              JP PRLABEL
