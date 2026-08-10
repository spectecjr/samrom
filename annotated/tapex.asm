; =====================================================================================================================
; TAPEX.ASM -- the tape and network block transfer engine
; =====================================================================================================================
;
; SABLK saves one block and LDBLK loads or verifies one, in either case dispatching to the network routines instead
; if the selected device is the network. Everything above this level -- headers, filenames, the LOAD and SAVE
; commands -- lives in tapemn.asm.
;
; TAPE ENCODING
; -------------
; Data is recorded as square-wave pulses whose *width* carries the information: a short pulse is a 0 bit and a long
; one is a 1. Each block begins with a long run of uniform leader pulses, then a single short sync pulse, then the
; data bits, most significant first, then a parity byte which is the exclusive-or of everything sent.
;
; The pulse widths are set by SLDEV+1, the DEVICE T speed. 19 is the fastest, about five times ZX Spectrum speed;
; larger values are slower. To keep the leader roughly constant in real time whatever the speed, SVCLC computes how
; many leader cycles to emit by repeatedly adding the delay constant until it overflows.
;
; The saving loop is cycle-counted, and the original comments give the exact timings; the pattern is
;
;     from SVBL: 38 or 37 T states, OUT, 13*R-1, 34, OUT, 13*R-27, 22, then round again
;
; where R is the delay register. Handling a byte boundary costs about 187 extra T states, which SV5 compensates for
; by shortening that one delay by 17 units.
;
; LOADING
; -------
; The loader has no idea what speed the tape was recorded at, so it measures. EDGE2 times each signal transition,
; and LDLDR maintains a running average of the leader pulse width -- a fifteen-sixteenths decay filter -- while
; requiring 256 consecutive pulses to stay within 25 per cent of that average. From the settled average it derives
; two thresholds: D' is the short/long decision point and E' the longest acceptable pulse.
;
; The border is used as a progress indicator throughout: white while searching, red during the leader, then blue
; and yellow alternating as data arrives.
;
; NETWORK
; -------
; The network uses the MIDI port hardware rather than pulse timing, so it needs none of the above. WNF and WNH are
; the network equivalents of SABLK and LDBLK, and share the same block-splitting logic in NIXR/NIXJ.
;
; PAGE FORM ADDRESSING
; --------------------
; Lengths arrive as CDE in page form and are converted by CDENORM to a 19-bit count: C counts 64K blocks and DE the
; remainder. As HL walks past &BFFF the code bumps the high memory page register and drops HL back to &8000, so a
; transfer can cross the whole of memory.
;
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; WNF -- save a block over the network
;
; Entry:  HL -> the data, CDE = the length in page form, the type byte on the stack.
;
; A 100-unit delay gives the receiver time to get back into its listening loop between blocks.
; ---------------------------------------------------------------------------------------------------------------------

WNF:       PUSH BC
           LD B,100
           CALL DELBC
           POP BC
           CALL CKNET                       ; Wait for the network to go quiet
           POP AF
           CALL NMOUT                       ; Send the type byte

           LD IX,NOSR                       ; The per-byte output routine
           CALL NIXR

; --- Send the parity byte ---

           EXX
           LD A,H
           EXX


; ---------------------------------------------------------------------------------------------------------------------
; NMOUT -- send one byte to the network or MIDI port
;
; Waits for the transmitter to become free, checking BREAK on both sides of the wait so a hung network can still be
; escaped from.
; ---------------------------------------------------------------------------------------------------------------------

NMOUT:     PUSH AF

NMOUT1:    CALL BRKCR
           XOR A
           IN A,(CLUTPORT)
           AND 2
           JR NZ,NMOUT1                     ; Still transmitting

           CALL BRKCR
           POP AF
           OUT (MDIPORT),A
           RET


; =====================================================================================================================
; SABLK -- save one block to tape
; =====================================================================================================================
;
; Entry:  HL -> the data, CDE = the length in page form, A = the type byte, which is also the first byte sent.
;         &01 is a header, &FF is data.
; Exit:   NC if the block was saved, CY if SPACE was pressed.
; ---------------------------------------------------------------------------------------------------------------------

SABLK:     DI
           PUSH AF
           CALL TCHK
           JR NZ,WNF                        ; The network is selected

           CALL CDENORM                     ; CDE to a 19-bit count
           POP AF
           PUSH AF
           EXX
           LD B,A
           EX AF,AF'                        ; The running parity starts as the type byte
           LD A,(SLDEV+1)                   ; The DEVICE T speed: 19 is fastest, higher is slower
           LD L,A
           INC A
           ADD A,A
           JR NC,SVLC

           LD A,&FE                         ; Cap the delay if doubling overflowed

SVLC:      INC A
           LD H,A                           ; H gives about twice the delay of L, so a 1 bit is twice a 0 bit
           PUSH HL

           LD C,A                           ; The leader pulse delay

; --- Choose the leader length so that its duration is roughly constant whatever the speed. The original comment
;     gives the resulting multipliers: 128 or more gives 2 cycles' worth, 86-127 gives 3, 64-85 gives 4, 52-63
;     gives 5, 43-51 gives 6, 37-42 gives 8, down to 19 giving 14. ---

           XOR A
           LD H,A
           LD L,A
           LD DE,3000

SVCLC:     ADD HL,DE
           ADD A,C
           JR NC,SVCLC

           INC B
           DJNZ SVTYP                       ; A data block

           ADD HL,HL                        ; A header gets twice the leader

SVTYP:     LD DE,&0202                      ; D holds the border colour bits: red during the leader

SVHDR:     LD A,D
           XOR &0F                          ; Flip the MIC bit and the border colour together
           LD D,A
           OUT (KEYPORT),A
           LD B,C

SVDL0:     DEC B
           JR NZ,SVDL0                      ; 16 T states per pass

           DEC HL
           LD A,H
           OR L
           JR NZ,SVHDR

; --- The sync pulse: a single short cycle marking the end of the leader ---

           SRL C
           SRL C                            ; Quarter-length pulses
           INC C
           INC C
           INC C                            ; Never let it get so short that the receiver misses it
           LD L,2                           ; Two half-cycles only
           DEC E
           JR NZ,SVHDR

           POP HL                           ; H and L are the delays for a 1 and a 0 bit
           POP AF                           ; The type byte
           LD E,A                           ; The first byte to send
           LD D,1                           ; Border blue during the data
           SCF                              ; The marker bit that signals the byte is finished
           RL E


; ---------------------------------------------------------------------------------------------------------------------
; SVBL -- the bit-saving loop
;
; One pass emits one full cycle: two transitions, each followed by a delay chosen by the bit value. E holds the byte
; being sent with a marker bit rotated in behind it, so when the rotation produces Z the byte is complete.
;
; The second delay is two units shorter to compensate for the 26 T states the loop body costs between the two
; transitions.
; ---------------------------------------------------------------------------------------------------------------------

SVBL:      LD C,H                           ; Assume a 1 bit
           JR C,SV2

           LD C,L                           ; A 0 bit

SV2:       LD A,D
           XOR &0F                          ; Flip the MIC and border bits
           OUT (KEYPORT),A                  ; 38 or 37 T states from SVBL to the end of this OUT; 55 or 54 from the
                                            ; previous OUT, plus the delay, when within a byte
           LD B,C

SVDL:      DJNZ SVDL                        ; 13*C minus 1 T states

           DEC C
           DEC C                            ; Take 26 T states off the second delay
           XOR &0F                          ; NC
           RL E
           OUT (KEYPORT),A                  ; 34 T states from the previous OUT, plus the delay

           JP Z,SVBY                        ; The marker rotated out, so the byte is complete

           LD B,C

SVDL2:     DJNZ SVDL2

           JR SVBL

; From SVBL: 38/37, OUT, 13*R-1, 34, OUT, 13*R-27, 22; then 38/37, OUT and so on, where R is the delay register.
; With R = 20:  38/37, OUT, 293, OUT, 293/291, OUT, 293   -- 0.098 msec at 6 MHz
; With R = 43:  38/37, OUT, 592, OUT, 592/591, OUT        -- 0.197 msec at 6 MHz


; ---------------------------------------------------------------------------------------------------------------------
; SVBY -- fetch the next byte, or finish the block
;
; C counts down the 64K blocks and doubles as an end-of-block state: &FF once the parity byte has been sent, &FE
; after one further junk byte -- which exists only so the parity byte's last bit gets a closing transition -- and 0
; when every block is done.
; ---------------------------------------------------------------------------------------------------------------------

SVBY:      EXX
           LD A,D
           OR E
           LD A,C
           JR NZ,SV4                        ; More bytes left in this 64K block

           INC A
           INC A
           RET Z                            ; Everything sent: NC and Z

           DEC C
           CP 3
           JR NC,SV4                        ; C was neither &FF nor 0, so blocks remain

           EX AF,AF'                        ; The parity byte
           LD B,A
           JR SV45

SV4:       DEC DE
           LD B,(HL)
           EX AF,AF'
           XOR B                            ; Accumulate the parity
           EX AF,AF'

SV45:      LD A,&F7
           IN A,(STATPORT)
           AND &20
           SCF
           RET Z                            ; ESC pressed: CY

           INC HL
           LD A,H
           CP &C0
           IN A,(URPORT)
           INC A                            ; The next page, ready in case the address has passed &BFFF
           JR C,SV5

           LD H,&80
           OUT (URPORT),A                   ; Page on and wrap the address back to &8000

SV5:       LD A,B
           EXX

           LD E,A                           ; The next byte to send
           LD A,C                           ; The original delay, less two
           INC B                            ; B = 1, the fallback delay
           SUB 17                           ; Compensate for the time spent fetching the byte
           JR C,SV6                         ; The delay was too short to shorten further

           INC A                            ; Never zero, which would mean 256
           LD B,A                           ; 182 T states less delay this once
           SCF                              ; The marker bit for the new byte

SV6:       RL E
           JR SVDL2                         ; About 187 extra T states were spent handling this byte


; ---------------------------------------------------------------------------------------------------------------------
; SABYTES / LDBYTES -- save or load a block, with the border and interrupts restored afterwards
;
; Exit:   CY if the transfer succeeded.
; ---------------------------------------------------------------------------------------------------------------------

SABYTES:   CALL SABLK
           CCF                              ; SABLK returns NC for success; invert it to match LDBLK
           JR SVLDCOM

LDBYTES:   CALL LDBLK

SVLDCOM:   EI
           EX AF,AF'
           LD A,(BORDCOL)
           OUT (KEYPORT),A                  ; Restore the user's border colour
           CALL BRKCR
           EX AF,AF'
           RET


; ---------------------------------------------------------------------------------------------------------------------
; WNH -- load or verify a block from the network
;
; Entry:  HL -> the destination, CDE = the length in page form, the type byte on the stack.
;
; Blocks whose type byte does not match are skipped, so a receiver can wait for a header while data blocks pass.
; ---------------------------------------------------------------------------------------------------------------------

WNH:       POP AF
           LD B,A
           EX AF,AF'                        ; CY means load rather than verify
           LD A,B

WNHL:      PUSH AF
           CALL CKNET

WTNI:      CALL NMIN
           JR NC,WTNI                       ; Nothing yet

           LD B,A
           POP AF
           CP B
           JR NZ,WNHL                       ; Not the block type we want

           LD IX,NISR                       ; The per-byte input routine
           CALL NIXR

; --- Check the parity byte ---

           CALL NMIN

NERR:      JP NC,TERROR                     ; Nothing arrived: loading error

           EXX
           XOR H
           EXX

           CP 1                             ; CY if the accumulated parity came to zero
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NOSR / NISR -- the per-byte network routines called through IX by NIXJ
;
; NOSR sends (HL); NISR either stores the received byte at (HL) or compares it, depending on the load/verify flag in
; A'. Both accumulate the parity in H'.
; ---------------------------------------------------------------------------------------------------------------------

NOSR:      LD A,(HL)
           CALL NMOUT
           JR NTVL

NISR:      CALL NMIN
           JR NC,NERR                       ; Nothing arrived within the timeout

           EX AF,AF'
           JR NC,NTV                        ; Verifying

           EX AF,AF'
           LD (HL),A
           JR NTVL

NTV:       EX AF,AF'
           CP (HL)
           JR NZ,NERR

NTVL:      EXX
           XOR H
           LD H,A                           ; The running parity
           EXX

           RET


; =====================================================================================================================
; LDBLK -- load or verify one block from tape
; =====================================================================================================================
;
; Entry:  HL -> the destination, CDE = the length in page form, A = the expected type byte. A ZX Spectrum header is
;         recognised by a type byte of 0, in which case only 17 bytes are read.
; Exit:   CY if the block loaded correctly, NC on any error.
; ---------------------------------------------------------------------------------------------------------------------

LDBLK:     DI
           PUSH AF
           CALL TCHK
           JR NZ,WNH                        ; The network is selected

           POP AF
           CALL CDENORM
           LD (TEMPW1),BC                   ; The 64K block count
           LD (TEMPW2),HL                   ; The destination
           INC C
           EX AF,AF'                        ; NZ means the type byte is still expected; CY load, NC verify
           LD A,8
           OUT (KEYPORT),A                  ; The MIC bit must start low or the EAR input cannot be read.
                                            ; This also sets the border white and initialises the edge polarity.

LDERR:     CALL BRKTST
           RET Z                            ; ESC: NC

LDSTRT:    LD B,8
           CALL EDGE2                       ; Look for a change on the EAR input
           JR NC,LDERR                      ; Timeout or ESC

           CALL EDGE2
           JR NC,LDERR

           EXX
           LD L,A                           ; Seed the running average with this pulse width
           LD B,0
           EXX

           LD L,0                           ; 256 samples to check


; ---------------------------------------------------------------------------------------------------------------------
; LDLDR -- confirm that what is arriving is a leader, and measure its pulse width
;
; Maintains L' as a running average with a fifteen-sixteenths decay: new average = (15*old + sample)/16. Every
; sample must lie within 25 per cent of the current average, and 256 consecutive samples must pass; any failure
; restarts the search from LDSTRT.
; ---------------------------------------------------------------------------------------------------------------------

LDLDR:     CALL EDGE2
           JR NC,LDERR

           EXX
           LD H,B                           ; B is zero, so HL = the average
           LD C,L
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL                        ; Times 16
           SBC HL,BC                        ; Times 15
           LD C,A
           ADD HL,BC                        ; Plus the new sample
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL                        ; H is now the new average, that is HL/16
           LD L,H
           LD A,L
           SUB C                            ; The difference from the average
           JR NC,BLWAV

           NEG                              ; Take its magnitude

BLWAV:     ADD A,A
           ADD A,A
           CP L                             ; Four times the deviation must be less than the average
           EXX

           JR NC,LDSTRT                     ; Outside 25 per cent, so this is not a clean leader

           DEC L
           JR NZ,LDLDR                      ; L ends at zero, which is also the initial parity value

           LD A,B
           AND &F8
           OR &02
           LD B,A                           ; Border red: a leader has been found

; --- Derive the bit-width thresholds from the settled average ---

           EXX
           LD A,L
           SRL A
           LD B,A
           SRL A
           ADC A,L                          ; 1.25 times the average leader pulse
           LD E,A                           ; E' = the longest acceptable pulse
           LD D,E
           DEC D
           DEC D                            ; Nudge it to sit centrally between the two bit widths
           SRL D                            ; D' = the short/long decision threshold
           LD A,B
           ADD A,L                          ; 1.5 times the average
           LD BC,(TEMPW1-1)
           INC B                            ; B' = the 64K block count plus one
           EXX

           LD H,A
           SRL H                            ; 0.75 times the average


; ---------------------------------------------------------------------------------------------------------------------
; WTSYNC -- wait for the sync pulse
;
; The sync pulse is a single short cycle. Waiting for it this way -- requiring first a short half-cycle and then a
; short whole cycle -- both locates the start of the data and guarantees that the two halves of every subsequent
; pulse are read as a pair, whatever the polarity of the recorded signal.
; ---------------------------------------------------------------------------------------------------------------------

WTSYNC:    LD C,0
           CALL EDGSENS
           CP H
           JR NC,LDSTRT                     ; Longer than 0.75 of the average: the signal has gone wrong

           ADD A,A
           CP H
           JR NC,WTSYNC                     ; Wait until a half-cycle doubled is still under 0.75 of the average

           CALL EDGSENS                     ; C carries in as the starting count, so A times the whole pulse
           CP H
           JR NC,WTSYNC                     ; The whole sync cycle must also be under the threshold

           LD A,B
           XOR 3
           LD B,A                           ; Border now alternates blue and yellow
           EXX
           LD HL,(TEMPW2)                   ; The destination pointer
           EXX
           JR LDSTART                       ; Read the type byte first


; ---------------------------------------------------------------------------------------------------------------------
; LDTYPE -- check the type byte, which is the first byte of every block
; ---------------------------------------------------------------------------------------------------------------------

LDTYPE:    RL C                             ; Park the carry, which the compare below would destroy
           INC H
           DEC H
           JR NZ,LDTCP                      ; Not type 0, so not a ZX Spectrum header

           INC H                            ; Treat it as a SAM header, type 1
           LD E,17                          ; A ZX header is 17 bytes

LDTCP:     XOR H                            ; Compare against the type expected in A'
           RET NZ                           ; Wrong type: NC and NZ

           LD A,C
           RRA                              ; Recover the carry; RR C cannot be used as it would alter Z
           EX AF,AF'
           JR LDSTART


; ---------------------------------------------------------------------------------------------------------------------
; LDLOOP / LDBITS -- the bit-loading loop
;
; Bits accumulate in H behind a marker bit, so when the marker rotates out into carry the byte is complete. Each bit
; is decided by comparing its measured pulse width against D'; anything longer than E' is an error.
;
; C carries a starting value into the edge timer to compensate for time lost between bits: 3 at a byte boundary,
; 0 otherwise.
; ---------------------------------------------------------------------------------------------------------------------

LDLOOP:    EXX

LDDE:      EX AF,AF'
           LD A,H
           EXX
           JR C,LDNVER                      ; Loading rather than verifying

LDVERIF:   XOR (HL)
           RET NZ                           ; Mismatch: NC and NZ

           DB SKIP1LDA                      ; LD A,n swallows the LD (HL),A below

LDNVER:    LD (HL),A

LDNEXT:    EX AF,AF'
           INC HL
           LD A,H
           CP &C0
           IN A,(URPORT)
           INC A
           JR C,LDDEC

           LD H,&80
           OUT (URPORT),A                   ; Page on past &BFFF

LDDEC:     EXX
           DEC DE

LDSTART:   LD H,1                           ; The marker bit
           LD C,3                           ; Compensate for the time spent handling the byte

LDBITS:    CALL EDGEC
           RET NC                           ; Timeout, or SPACE pressed

           EXX
           CP E
           RET NC                           ; Longer than the maximum acceptable pulse

           CP D
           CCF                              ; NC if shorter than the decision threshold, so a 0 bit
           EXX

           RL H
           LD C,0
           JR NC,LDBITS                     ; Loop until the marker bit rotates out

           LD A,L                           ; Accumulate the parity
           XOR H
           LD L,A

           EX AF,AF'
           JR NZ,LDTYPE                     ; This was the type byte, so it does not count towards the length

           EX AF,AF'
           LD A,E
           OR D
           JR NZ,LDDE                       ; More bytes in this 64K block

           EXX
           DJNZ LDLOOP                      ; More 64K blocks
           EXX

           LD A,L
           CP 1                             ; CY if the parity came to zero
           RET


; ---------------------------------------------------------------------------------------------------------------------
; CKNET -- wait for the network to be free
;
; Requires the line to stay quiet for a full run of 1024 checks, so a momentary gap in someone else's traffic is not
; mistaken for the end of it.
; ---------------------------------------------------------------------------------------------------------------------

CKNET:     PUSH HL

CKNT1:     LD H,4                           ; HL counts down from &04xx

CKNT2:     CALL BRKCR
           IN A,(VIDPORT)
           RLA
           JR NC,CKNT1                      ; Busy again, so start the run over

           DEC HL
           LD A,H
           OR L
           JR NZ,CKNT2

           POP HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NMIN -- receive one byte from the network or MIDI port
;
; Exit:   CY with the byte in A, or NC and A = 0 if nothing arrived within the timeout.
; ---------------------------------------------------------------------------------------------------------------------

NMIN:      PUSH HL
           LD HL,300

NMIN1:     DEC HL
           LD A,H
           OR L
           JR Z,NMIN3                       ; Timed out

           CALL BRKCR
           IN A,(STATPORT)
           BIT 2,A
           JR NZ,NMIN1                      ; Nothing yet

NMIN2:     IN A,(STATPORT)
           BIT 2,A
           JR Z,NMIN2                       ; Wait for the byte to complete

           IN A,(MDIPORT)
           SCF

NMIN3:     POP HL
           RET


; ---------------------------------------------------------------------------------------------------------------------
; NIXR / NIXJ -- transfer a block over the network, byte at a time through IX
;
; Entry:  HL -> the data, C = the number of 64K blocks, DE = the remainder, IX = NOSR or NISR.
;
; The transfer is broken into 16K chunks so that the page crossing at &BFFF can be handled once per chunk rather
; than tested for every byte. Bit 7 of D is cleared to bring the length into the 0 to 16K range.
; ---------------------------------------------------------------------------------------------------------------------

NIXR:      EXX
           LD H,A                           ; Seed the parity byte with the type
           EXX

           RES 7,D
           LD A,C                           ; The 16K block count
           AND A
           JR Z,NIXJ

NIXL:      PUSH AF
           PUSH DE
           LD DE,&4000                      ; A full 16K
           CALL NIXJ
           POP DE
           POP AF
           DEC A
           JR NZ,NIXL

; --- NIXJ: transfer DE bytes from HL, where DE is 16K or less ---

NIXJ:      LD A,D
           OR E
           RET Z

           LD A,H
           CP &C0
           CALL NC,INCURPAGE                ; Past &BFFF, so page on
           CALL IXJUMP                      ; NOSR or NISR
           INC HL
           DEC DE
           JR NIXJ
