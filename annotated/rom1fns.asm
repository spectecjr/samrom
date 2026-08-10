; =====================================================================================================================
; ROM1FNS.ASM -- BASIC functions living in ROM 1
; =====================================================================================================================
;
; The functions collected here are the ones that either need no ROM 0 code at all, or are small enough that keeping
; them out of ROM 0 buys space where it is scarcest. Roughly by theme:
;
;   Re-entering the interpreter   VAL, VAL$              -- tokenise a string and evaluate it as an expression
;   Random and screen enquiries   RND, ATTR, POINT
;   String producers              CHR$, BIN$, HEX$, MEM$, STR$, TRUNC$, INKEY$, string concatenation
;   String consumers              CODE, LEN
;   Arithmetic                    SQR, ABS, unary minus, SGN, INT, TRUNCATE
;   Addresses                     SVAR, UDG, USR, USR$, PEEK, DPEEK
;   DOS hand-offs                 DVAR, EOF, PTR, PATH$
;   The tokeniser's helper        AMPERSAND, which evaluates &-prefixed hex at syntax-check time
;
; Calling convention. Everything here is reached from the calculator's function table (see fpcmain.asm), so a unary
; function is entered with HL pointing at its argument on the calculator stack and DE at STKEND, and must return
; with the result in place and DE = STKEND. Functions that parse their own arguments from the program text are
; entered instead from the evaluator, with CHAD pointing at the token.
;
; Paging. ROM 1 sits at &C000, so anything at &8000-&BFFF is reached through URPORT (port 251) and anything in
; ROM 0's half of the address space needs the ROM to be switched out; R1OFRD, R1OFFCL and R1OFFJP do that. Several
; routines here save URPORT on entry and restore it through the shared OSBC/PPORT tails.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; FPVAL / FPVALS -- VAL and VAL$
;
; Both take a string and evaluate it as a BASIC expression. The implementation genuinely re-enters the interpreter:
; the string is copied into workspace, tokenised in place by TOKDE, CHAD is pointed at the copy, and the ordinary
; expression evaluator is run over it. The only thing that separates the two functions is which result type is
; acceptable, so they share one body and are distinguished by a flag pushed on entry.
;
; The flag is set by the entry point itself. FPVAL is a one-byte "LD A,n" whose operand is the XOR A at FPVALS, so
; entering at FPVAL leaves A = &AF (non-zero, meaning VAL) while entering at FPVALS executes the XOR and leaves
; A = 0 (meaning VAL$).
;
; The expression is scanned twice, as anywhere else in the interpreter: first with FLAGS bit 7 reset, which is the
; syntax pass and is what causes numeric literals to acquire their invisible 5-byte forms, and then with it set,
; which is the run pass that actually stacks a value. Between the two, the terminator is checked: anything other
; than a carriage return means the string held more than one expression.
;
; Entry:  string on the calculator stack
; Exit:   the value of the expression on the calculator stack, DE = STKEND
; Errors: ERR_NONSENSE if the string is not a single expression of the right type
; Notes:  IX is preserved across the call (a fix over earlier ROMs); CHAD and CHADP are saved and restored, since
;         the caller is in the middle of scanning a program line.
; ---------------------------------------------------------------------------------------------------------------------

FPVAL:     DB SKIP1LDA       ;'LD A,&AF'

FPVALS:    XOR A
           PUSH IX           ;** BUG FIX
           LD BC,(CHADP-1)   ;B=CHADP
           PUSH BC
           LD HL,(CHAD)
           PUSH HL
           AND A
           PUSH AF           ;A=0 IF VAL$, NZ IF VAL
         ;  CALL UNSTKPRT     ;DE=START, BC=LEN, A=PORT
           CALL GETSTRING
           INC BC            ;LEN OF AT LEAST 1; ROOM FOR TERMINATOR
          ; LD (BCSTORE),BC
;          CALL R1OFFCL      ;**
           CALL SCOPYWK        ;COPY STRING PLUS 1 BYTE OF JUNK TO WKSPACE
       ;    DEC HL           ;TERMINATE WITH 0DH
      ;     LD (HL),&0D       ;TERMINATE STRING COPY IN WKSPACE
           LD (CHAD),DE
           IN A,(URPORT)
           LD (CHADP),A
           PUSH DE
           CALL R1OFFCL
           DW TOKDE         ;TOKENISE FROM DE ON
           POP HL
           LD (CHAD),HL
           PUSH HL
           LD HL,FLAGS
           RES 7,(HL)        ;'SYNTAX CHECK' SO FP FORMS INSERTED
           CALL EXPTEXPR     ;RETURN WITH Z FOR STRING, NZ FOR NUM.
           EX AF,AF'
           LD A,(HL)         ;TERMINATOR
           CP CC_ENTER
           JR NZ,VALNONS     ;CHECK FOR TERMINATOR

           POP HL            ;STRING START IN WKSPACE
           POP AF            ;VAL/VAL$ FLAG
           JR NZ,FPVAL2      ;JR IF VAL

           EX AF,AF'
           JR Z,FPVALOK      ;IF VAL$, STRING RESULT IS OK. ELSE EX AF, AF'
                             ;GIVES Z, THEN ERROR
FPVAL2:    EX AF,AF'
           JR Z,VALNONS      ;IF VAL, STRING EXPR IS AN ERROR

FPVALOK:   LD (CHAD),HL
           LD HL,FLAGS
           SET 7,(HL)        ;'RUNNING'
           CALL SCANNING     ;GET EXPR TO FPC STACK
           POP HL
           LD (CHAD),HL      ;ORIGINAL CHAD
           POP AF
           LD (CHADP),A
           CALL SELURPG
           POP IX            ;** BUG FIX

SETUPDE:   LD DE,(STKEND)
           RET

VALNONS:   RST &08
           DB ERR_NONSENSE


; ---------------------------------------------------------------------------------------------------------------------
; FPDVAR / FPEOF / FPPTR / IMPATHS -- functions implemented by DOS
;
; Each is a single RST &08 hook call: DOS traps the "error" code, does the work, and returns with the result already
; on the calculator stack. All that is left is to reload DE from STKEND, which the SKIP2LDHL bytes arrange by
; falling the first three entries through to the JR at SUDH.
; ---------------------------------------------------------------------------------------------------------------------

FPDVAR:    RST &08           ;LET DOS STACK ADDR OF ITS VARS
           DB DVHK
           DB SKIP2LDHL      ;'JR+2'

FPEOF:     RST &08
           DB EOFHK          ;DOS EOF
           DB SKIP2LDHL      ;'JR+2'

FPPTR:     RST &08
           DB PTRHK          ;DOS PTR
           JR SUDH

IMPATHS:   CALL SABORTER

           RST &08
           DB PATHHK

SUDH:      JR SETUPDE


; ---------------------------------------------------------------------------------------------------------------------
; IMRND -- RND and RND(n)
;
; A 16-bit linear congruential generator. SEED is advanced by the multiply-and-subtract sequence below, stacked as
; an integer, converted to full floating point by RESTACK, and then scaled into 0..1 by subtracting &10 from the
; exponent -- a division by 65536 that costs one instruction because it is exactly 16 binary places.
;
; With a parameter, RND(n) yields an integer in 0..n by multiplying by n+1 and truncating.
;
; Entry:  CHAD points at the RND token
; Exit:   result on the calculator stack (or nothing at all during the syntax pass)
; ---------------------------------------------------------------------------------------------------------------------

IMRND:     RST &20           ;SKIP 'RND'
           CALL RUNFLG
           JR NC,IMRND4      ;JR IF NOT RUNNING

           LD B,0
           LD HL,(SEED)
           LD E,&FD
           LD D,L
           LD A,H
           ADD HL,HL
           SBC A,B
           EX DE,HL
           SBC HL,DE
           SBC A,B
           LD C,A
           SBC HL,BC
           JR NC,IMRND1

           INC HL

IMRND1:    LD (SEED),HL
           CALL STACKHL

           DB CALC
           DB RESTACK        ;EXP WILL BE 00 IF ZERO, ELSE 81-90H
           DB EXIT

           LD A,(HL)
           SUB &10           ;DIVIDE BY 65536
           JR C,IMRND4       ;LEAVE IT ALONE IF ZERO

           LD (HL),A         ;NEW EXP

IMRND4:    RST &18
           CP "("
           RET NZ

           CALL SEX1NUMCB    ;SKIP, GET 'N)', PASS CLOSING BRACKET
           RET NC            ;RET IF NOT RUNNING

           DB CALC           ;RND,PARAM
           DB STKONE         ;RND,P,1
           DB ADDN           ;RND,P+1
           DB MULT           ;RND*(P+1)
           DB TRUNC
           DB EXIT2          ;EXIT WITH INTEGER BETWEEN 0 AND PARAM


; ---------------------------------------------------------------------------------------------------------------------
; IMATTR -- ATTR(line,column)
;
; Reads the colour byte of a character cell. Only modes 0 and 1 have per-cell colour to read: mode 0 keeps its
; attributes in the ZX-layout block at &9800 (third*256 + row*32 + column), mode 1 keeps one byte per 8x1 cell
; exactly &2000 above the corresponding pixel byte.
;
; Entry:  CHAD points at "("
; Exit:   the attribute byte on the calculator stack
; Errors: ERR_BADMODE in modes 2 and 3, ERR_OFFSCREEN if the position is outside the 24x32 grid
; ---------------------------------------------------------------------------------------------------------------------

IMATTR:    CALL EXB2NUMB  ;CHECK (X,Y). CY IF RUNNING
           RET NC

           LD HL,&1820       ;LINE/COL LIMITS (PLUS 1)
           CALL GETCP        ;GET CHAR POSITION WITHIN LIMITS, IN DE
           LD A,(MODE)
           CP MODE4COL
           JP NC,INVMERR      ;INVALID MODE UNLESS 0 OR 1

           AND A
           JR Z,DOATT2       ;JR IF MODE 0

           CALL M1DEADDR     ;GET CHAR ADDR
           LD A,D
           ADD A,&20         ;GET ATTR ADDR (ADD 8K)
           JR DOATT3

DOATT2:    CALL M0DEADDR
           LD A,D
           RRCA
           RRCA
           RRCA
           AND &03
           OR &98            ;FORM ATTR ADDR IN AE

DOATT3:    LD D,A
           EX DE,HL
           CALL SREAD
           JR POATC


; ---------------------------------------------------------------------------------------------------------------------
; IMPOINT -- POINT(x,y)
;
; Returns the colour index of a pixel: 0 or 1 in modes 0 and 1, 0-3 in mode 2, 0-15 in mode 3. The screen byte is
; fetched and then rotated left until the wanted pixel occupies the low bits, at which point a mask of the right
; width extracts it. B carries the rotate count, which is where the per-mode differences live:
;
;   modes 0/1  one bit per pixel, x mod 8 + 1 rotations
;   mode 3     one nibble per pixel, 4 or 8 rotations depending on whether x is odd
;   mode 2     two bits per pixel, but stored as two separate bitplanes interleaved odd/even within the byte. The
;              XOR &AA sequence swaps adjacent bit pairs so that the two bits of one pixel become adjacent, after
;              which the mode 3 machinery works. With FATPIX 1 in force a "pixel" is a mode 3 pixel and the mode 3
;              path is taken directly.
;
; Entry:  CHAD points at "("
; Exit:   the pixel value on the calculator stack
; ---------------------------------------------------------------------------------------------------------------------

IMPOINT:   CALL EXB2NUMB  ;CHECK (X,Y). CY IF RUNNING
           RET NC

           CALL GTFCOORDS    ;GET COORDS IN B,C OR B,HL (THIN) AND CY
           CALL ANYPIXAD     ;GET ADDRESS IN HL, PIXEL OFFSET IN A
           INC A
           LD B,A            ;B=X MOD 8+1
           CALL SREAD
           LD E,A            ;E=SCREEN BYTE
           LD D,&01          ;MODE 0/1 MASK
           LD A,(MODE)
           CP MODE4COL
           JR C,DPOINTC      ;JR IF MODE 0/1

           LD D,&0F          ;MODE 3 MASK
           JR NZ,M3POINT     ;JR IF MODE 3

           LD D,3            ;MODE 2 MASK
           LD A,E
           RLA
           RR E
           XOR E
           AND &AA
           XOR E
           LD E,A            ;SWAP ODD/EVEN BITS IN MODE 2

           LD A,(THFATT)
           AND A
           JR NZ,M3POINT     ;DO MODE 3 POINT IF FATPIX 1

           LD A,B
           DEC A
           AND D             ;AND 3
           INC A
           ADD A,A           ;IF THIN PIX, A=2/4/6/8 FOR PIX 0/1/2/3
           LD B,A

DPOINTC:   LD A,E

POINLP:    RLCA
           DJNZ POINLP

           JR M3ODPT

M3POINT:   LD A,E
           LD B,4
           BIT 0,C           ;SEE IF X IS ODD
           JR Z,POINLP

M3ODPT:    AND D

POATC:     CALL RCURP
           JR STKAB          ;ATTR OR POINT


; ---------------------------------------------------------------------------------------------------------------------
; GETCP -- fetch a line,column pair and range-check it
;
; Entry:  H = line limit, L = column limit (both one more than the highest legal value)
; Exit:   D = line, E = column
; Errors: ERR_OFFSCREEN
; ---------------------------------------------------------------------------------------------------------------------

GETCP:     PUSH HL           ;LINE/COL MAX
           CALL GETBYTE      ;COL
           POP HL
           CP L
           JR NC,OSERR

           PUSH BC
           PUSH HL
           CALL GETBYTE      ;LINE
           POP HL
           POP DE
           LD D,A
           CP H
           RET C

OSERR:     RST &08
           DB ERR_OFFSCREEN  ;'Off screen'


; ---------------------------------------------------------------------------------------------------------------------
; FPINKEY -- INKEY$ #n
;
; Polls a stream for a character without waiting. The current channel is saved and restored around the poll so that
; INKEY$ on one stream does not disturb output on another.
;
; Entry:  stream number on the calculator stack
; Exit:   a one-character string, or the null string if nothing was ready
; Errors: ERR_IOOR if the stream number is 17 or more
; ---------------------------------------------------------------------------------------------------------------------

FPINKEY:   LD DE,&1100+ERR_IOOR ;LIMIT <17
           CALL LIMBYTE

           LD HL,(CURCHL)
           PUSH HL
           CALL SETSTRM      ;SET STREAM 'A'
           CALL INPUTAD      ;SCAN INPUT STREAM WITHOUT WAITING
           POP HL            ;PREV. CHANNEL
           PUSH AF           ;INKEY VALUE
           CALL CHANFLAG     ;RESTORE ORIG CHANNEL
           POP AF

FPINKEN:   LD D,A
           JR C,CHRINKC      ;IF GOT KEY, D=BYTE. COPY TO WKSPACE

           XOR A             ;IF NO INPUT - NULL STRING
           JR STKAB


; ---------------------------------------------------------------------------------------------------------------------
; FPBUTTON -- BUTTON n
;
; Returns 1 if mouse button n is down, 0 if not. BUTTON 0 tests all three at once.
;
; The mask is derived arithmetically rather than by table: CP 3 / SBC A,&FF maps 0,1,2,3 to 0,1,2,4, which is the
; bit mask for buttons 1, 2 and 3 with zero left over for the "any button" case, and that zero is turned into &FF by
; the CPL.
;
; Errors: ERR_IOOR if n is 4 or more
; ---------------------------------------------------------------------------------------------------------------------

FPBUTTON:  LD DE,&0400+ERR_IOOR ;LIMIT TO 0-3
           CALL LIMBYTE
           CP 3              ;CY IF 0/1/2, NC IF 3
           SBC A,&FF         ;00,01,02,04
           JR NZ,FPBT2

           CPL               ;'BUTTON 0' TEST ALL 3

FPBT2:     LD HL,BUTSTAT     ;HAS BITS 2-0 SET FOR BUTTONS 3-1
           AND (HL)
           JR Z,STKAB

           LD A,1

STKAB:     JP STACKA


; ---------------------------------------------------------------------------------------------------------------------
; FPSVAR -- SVAR n
;
; The address of system variable n. Written entirely as calculator bytecode: load the literal base of the system
; variable area and add the argument.
; ---------------------------------------------------------------------------------------------------------------------

FPSVAR:    DB CALC
           DB LKADDRW
           DW VVAR2
           DB ADDN
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPCHRS -- CHR$ n, and the tail shared with INKEY$
;
; Builds a one-character string. The character is written into TEMPW1 (a scratch word in the system variables, which
; is always paged in) and CWKSTK copies it from there into workspace and stacks the descriptor.
;
; Entry:  FPCHRS -- the code on the calculator stack; CHRINKC -- the character already in D
; Exit:   a one-character string on the calculator stack, DE = STKEND
; ---------------------------------------------------------------------------------------------------------------------

FPCHRS:    CALL GETBYTE      ;B=0, L=BYTE
           LD D,L

CHRINKC:   LD BC,1           ;LEN=1

INKYEN:    LD HL,TEMPW1+1
           LD (HL),E
           DEC HL
           LD (HL),D
           JP CWKSTK         ;COPY BC FROM (HL) TO WKSPACE, PARAMS TO FPCS
                             ;EXITS WITH DE=STKEND


; ---------------------------------------------------------------------------------------------------------------------
; FPBINS -- BIN$ n
;
; An 8- or 16-digit binary string, the wider form being used whenever the value does not fit in a byte. The digit
; characters come from BIN1DIG and BIN0DIG rather than being hard-coded, so a program can redefine them (to draw
; bar charts out of block graphics, say).
;
; The digits are written backwards into a scratch buffer borrowed from the MEM$ area, shifting the least significant
; bit out first.
; ---------------------------------------------------------------------------------------------------------------------

FPBINS:    CALL GETINT
           EX DE,HL          ;INT IN DE
           LD A,D
           LD C,8            ;ASSUME LEN 8 FOR RESULT STRING
           AND A
           JR Z,BINS2

           LD C,16           ;USE 16 IF NEEDED

BINS2:     LD HL,MEMVAL+16   ;GET HL POINTING TEMP $ BUFFER IN MEMS
           LD B,C

BINSLP:    DEC HL
           SRL D
           RR E              ;SHIFT LS BITS OUT FIRST
           LD A,(BIN1DIG)
           JR C,BINS4        ;LEAVE IT IF CY

           LD A,(BIN0DIG)

BINS4:     LD (HL),A
           DJNZ BINSLP
                             ;HL=START, BC=LEN
BCWKHP:    JP CWKSTK         ;COPY BC FROM (HL) TO WKSPACE, PARAMS TO FPCS


; ---------------------------------------------------------------------------------------------------------------------
; FPHEXS -- HEX$ n
;
; Two, four or six hex digits, whichever the magnitude needs. The argument is taken in page form (UNSTLEN gives a
; page in A and an offset in BC), which is how addresses above 64K reach here; the page's low two bits are folded
; into the top of the address to make a single 20-bit value in HBC.
;
; Digits are pushed on the machine stack most significant first and popped back off into the buffer, which reverses
; them into the right order without a second pass over the value.
; ---------------------------------------------------------------------------------------------------------------------

FPHEXS:    CALL UNSTLEN      ;ABC=PAGE/'ADDR' **
           RRCA
           RRCA              ;LS 2 BITS TO POSN 7,6
           LD H,A
           XOR B
           AND &C0
           XOR B
           LD B,A            ;HBC=20-BIT NUMBER
           LD E,0            ;INIT DIGIT COUNTER
           OR H
           JR Z,HEX2DIG      ;JR IF MS 2 BYTES (OF 3)=0

           LD A,H
           AND &0F
           JR Z,HEX4DIG      ;JR IF MSB=0

           EX AF,AF'
           LD A,B
           EX AF,AF'         ;SAVE MIDDLE BYTE IN A'
           LD B,A            ;B=MS BYTE
           CALL HEXASCSR
           EX AF,AF'
           LD B,A            ;MIDDLE BYTE

HEX4DIG:   CALL HEXASCSR     ;DERIVE 2 DIGITS FROM B, STACK THEM

HEX2DIG:   LD B,C            ;LS BYTE
           CALL HEXASCSR
           LD C,E
           LD B,0
           LD HL,MEMVAL+6    ;TEMP BUFFER
           LD B,C

HEXPUTLP:  DEC HL
           POP AF            ;UNSTACK AN ASCII DIGIT
           LD (HL),A
           DJNZ HEXPUTLP
                             ;HL=START-1, BC=LEN
           JR BCWKHP         ;STACK STRING FROM HL ON FPCS


; ---------------------------------------------------------------------------------------------------------------------
; HEXASCSR -- convert B to two ASCII hex digits, pushed on the machine stack
;
; Nibble to ASCII in three instructions. CP &0A sets carry for 0-9; SBC A,&69 then gives &97-&A0 for 0-9 and
; &A1-&A6 for A-F, and DAA's BCD correction turns those into &30-&39 and &41-&46 exactly. It works because DAA
; consults the H and N flags left by the subtraction as well as the value itself.
;
; The routine pops its own return address into HL and returns with JP (HL), because the digits it pushes have to sit
; on top of the stack when it returns.
;
; Entry:  B = byte, E = digit count so far
; Exit:   E incremented by 2, two digits pushed (as the high halves of two AF pairs)
; ---------------------------------------------------------------------------------------------------------------------

HEXASCSR:  INC E
           INC E             ;COUNT OF DIGITS ON STACK=COUNT+2
           LD A,B
           LD D,2            ;2 DIGITS
           POP HL            ;RET ADDR
           RRCA              ;MS NIBBLE FIRST
           RRCA
           RRCA
           RRCA

HEXSRLP:   AND &0F
           CP &0A
           SBC A,&69         ;
           DAA               ;A STRANGE TWIDDLE THAT GIVES THE RIGHT ANSWER!
           PUSH AF           ;SAVE ASCII 0-9, A-F
           LD A,B
           DEC D
           JR NZ,HEXSRLP

           JP (HL)           ;RETURN


; ---------------------------------------------------------------------------------------------------------------------
; MEMRYSP2 -- the second half of MEM$
;
; MEM$ n TO m yields the bytes of memory from n to m inclusive as a string. The length is computed in calculator
; bytecode as m-n+1, clamped to the null string if that comes out negative, and then the descriptor is built by hand
; because the "string" is not in workspace at all: it is the memory itself, addressed in page form, which is why
; STKSTOS is handed a page and an address rather than a workspace pointer.
; ---------------------------------------------------------------------------------------------------------------------

MEMRYSP2:  DB CALC
           DB SWOP           ;N2,N1
           DB STO0
           DB SUBN           ;N2-N1
           DB STKONE         ;ALLOW FOR INCLUSIVE CHAR.
           DB ADDN           ;LEN
           DB DUP
           DB LESS0          ;LEN, 1/0
           DB JPFALSE        ;JP IF LEN <0
           DB &03

           DB DROP
           DB STKZERO        ;NULL STRING IF LEN <0

           DB RCL0           ;LEN,N1
           DB EXIT

           CALL UNSTLEN      ;GET AHL=START
           SET 7,H           ;PAGE FORM
           DEC A
           PUSH AF
           PUSH HL
           CALL GETINT       ;GET BC=LEN
           POP DE            ;ADDR
           POP AF
           JP STKSTOS


; ---------------------------------------------------------------------------------------------------------------------
; FPCONCAT -- string concatenation, s1 + s2
;
; Both operands are unstacked (each giving a page, an address and a length), the total length is checked for
; overflow, workspace is claimed for the result, and the two halves are copied in with FARLDIR, which can cross page
; boundaries. The descriptor for the result is stacked before the copying, so that if the copy fails the calculator
; stack is still consistent.
;
; The second copy enters FARLDIR at its second entry point: the destination page and offset are already set up in
; TEMPW1/TEMPB2 by the first copy, and the first copy left them pointing exactly where the second must start.
;
; Entry:  two strings on the calculator stack, DE = the address the result descriptor must occupy
; Exit:   the concatenated string on the calculator stack, DE = STKEND
; Errors: ERR_STRTOOLONG if the total exceeds 65535 characters
; ---------------------------------------------------------------------------------------------------------------------

FPCONCAT:  IN A,(URPORT)
           PUSH AF
           PUSH DE           ;S2 PTR WILL BE NEW STKEND
           CALL STKFETCH     ;ADE=S2 START, BC=S2 LEN
           PUSH AF
           PUSH DE
           PUSH BC           ;S2 LEN
           PUSH BC
           CALL STKFETCH
           POP HL            ;S2 LEN
           ADD HL,BC         ;TOTAL LEN
           JP C,STLERR       ;** BUG FIX

           PUSH AF           ;PAGE OF S1
           PUSH DE           ;START OF S1
           PUSH BC           ;LEN OF S1
           LD B,H
           LD C,L            ;BC=TOTAL LEN
           CALL WKROOM       ;GET DE=START, BC=TOTAL LEN, PAGED IN
           CALL STKSTOREP    ;PARAMS OF STRING TO BE CREATED TO FPCS

           POP BC            ;LEN OF S1
           CALL SPLITBC      ;SET UP PAGCOUNT/MODCOUNT
           IN A,(URPORT)
           LD C,A            ;DEST=CDE
           POP HL            ;START OF S1
           POP AF            ;PAGE OF S1
           CALL FARLDIR
           POP BC            ;LEN OF S2
           CALL SPLITBC
           POP DE            ;START OF S2
           POP HL            ;H=PAGE OF S2
           SCF
           CALL FARLDIR2     ;ENTRY PT 2 BECAUSE TEMPW1 AND TEMPB2 = DEST
           POP DE            ;NEW STKEND
           JP PPORT


; ---------------------------------------------------------------------------------------------------------------------
; AMPERSAND -- &-prefaced hexadecimal, e.g. &FC0D
;
; Called by the evaluator when it meets "&" where a number is expected. Up to six hex digits are accumulated into
; A'HL, an accumulator wide enough for the 24-bit values a full address needs; letters are accepted in either case
; by forcing bit 5.
;
; The result is stacked as a small integer when it fits in 16 bits, and otherwise normalised into a floating-point
; number by hand: &98 is the exponent for a 24-bit value with its top bit set, and the mantissa is shifted left
; until it is, decrementing the exponent as it goes.
;
; Because this runs during the syntax pass, the value is converted once and stored back into the program as an
; invisible 5-byte form; the run pass then reads that rather than re-scanning the digits. See
; docs/tokenized-program-format.md.
;
; Errors: ERR_NUMTOOBIG on a seventh significant digit
; ---------------------------------------------------------------------------------------------------------------------

AMPERSAND: XOR A
           LD H,A
           LD L,A            ;INIT RESULT TO ZERO
           EX AF,AF'         ; IN A'HL

AMPDILP:   EX DE,HL
           RST &20
           EX DE,HL          ;HL=RESULT
           SUB "0"           ;NUMS NOW 00-09, LETS 11-2A, 31-4A
           JR C,AMPEND

           CP &0A
           JR C,AMPVALID     ;JR IF DIGIT

           ADD A,"0"
           OR &20            ;LETS NOW 61-7A
           CP "a"
           JR C,AMPEND

           CP "g"
           JR NC,AMPEND

           SUB "a"-&0A       ;a-f->0A-0F

AMPVALID:  LD B,4
           EX AF,AF'

AMPERLP:   ADD HL,HL
           RLA
           JP C,NTLERR       ;NUM. TOO LARGE (ONLY SEE MSG WITH EG VAL("&"+A$))

           DJNZ AMPERLP

           EX AF,AF'
           OR L
           LD L,A            ;ADD IN NEW HEX DIGIT
           JR AMPDILP

AMPEND:    LD B,H
           LD C,L
           EX AF,AF'
           AND A
           JR Z,STACKBCH     ;JR IF SMALL INTEGER

           LD B,&98          ;EXP FOR FF FF FF

AMPALLP:   BIT 7,A
           JR NZ,AMPFP

           ADD HL,HL         ;ALIGN MANTISSA IN AHL
           RLA
           DJNZ AMPALLP      ;B NEVER HITS ZERO!

AMPFP:     AND &7F           ;+VE SIGN BIT
           LD E,A
           LD D,H
           LD C,L
           LD A,B            ;EXP
           LD B,0           ;FP NUM IN A E D C B
           JP STKSTORE


; ---------------------------------------------------------------------------------------------------------------------
; FPUSRS / FPUSR -- USR$ and USR
;
; Both live in ROM 0; these are trampolines that switch ROM 1 out and jump across. See
; docs/machine-code-interface.md for what a USR routine receives.
; ---------------------------------------------------------------------------------------------------------------------

FPUSRS:    CALL R1OFFJP      ;JP TO MAIN ROUTINE IN ROM 0 WITH ROM1 OFF
           DW R0USRS

FPUSR:     CALL R1OFFJP
           DW R0USR


; ---------------------------------------------------------------------------------------------------------------------
; FPPEEK / FPDPEEK -- PEEK and DPEEK
;
; PEEK reads one byte, DPEEK two (low byte first). Both go through R1OFRD, which reads with ROM 1 switched out so
; that addresses in ROM 1's own range see RAM. The original URPORT setting is saved and restored, since the address
; may have paged a different 16K bank into the upper window.
;
; Unary calculator functions: entered with the address on the calculator stack.
; ---------------------------------------------------------------------------------------------------------------------

FPPEEK:    CALL PDPSUBR      ;GET HL=ADDR (PAGED IN), A=ORIG URPORT
           LD D,A
           XOR A
           JR FPPDPC

FPDPEEK:   IN A,(URPORT)
           PUSH AF
           CALL NPDPS        ;GET HL=ADDR
           INC HL
           CALL R1OFRD
           DEC HL
           POP DE

FPPDPC:    LD B,A
           CALL R1OFRD
           LD C,A
           LD A,D

OSBC:      OUT (URPORT),A

STACKBCH:  JP STACKBC


; ---------------------------------------------------------------------------------------------------------------------
; FPTRUSTR -- TRUNC$ s
;
; The string with trailing spaces removed, which is chiefly useful on elements of a string array, where every
; element is padded to the declared length. An all-spaces string gives the null string.
;
; Entry:  a string of 1-255 characters on the calculator stack
; ---------------------------------------------------------------------------------------------------------------------

FPTRUSTR:  CALL SBUFFET      ;DE=START, A AND BC=LEN, PAGING UNCHANGED
                             ;LEN 1-255
           LD H,D
           LD L,E
           ADD HL,BC         ;PT PAST END OF STRING
           LD A," "

TRUNCSLP:  DEC HL
           CP (HL)
           JR NZ,FPSTRS2     ;JR WITH DE=START, BC=LEN

           DEC C
           JR NZ,TRUNCSLP    ;TRUNC$ OF ALL-SPACES STRING=NULL STRING

           JR STACKBCH


; ---------------------------------------------------------------------------------------------------------------------
; FPSTRS -- STR$ n
;
; PFSTRS renders the number into common memory as it would be printed; all that remains is to copy the digits into
; workspace and stack a descriptor. TRUNC$ joins at FPSTRS2 with its own DE/BC.
; ---------------------------------------------------------------------------------------------------------------------

FPSTRS:    CALL PFSTRS       ;GET NUMBER AS BC DIGITS AT (DE) IN COMMON MEM

FPSTRS2:   EX DE,HL
           JP CWKSTK


; ---------------------------------------------------------------------------------------------------------------------
; FPCODE -- CODE s
;
; The ASCII code of the first character, or 0 for the null string. GETSTRING may page a different bank in to reach
; the string, so URPORT is saved and restored through the OSBC tail.
; ---------------------------------------------------------------------------------------------------------------------

FPCODE:    IN A,(URPORT)
           PUSH AF
           CALL GETSTRING    ;UNSTACK STRING. DE=START, BC=LEN, PAGED IN
           LD A,B
           OR C
           JR Z,FPCODE2      ;JR IF NUL STRING

           LD A,(DE)
           LD C,A
           LD B,0

FPCODE2:   POP AF
           JR OSBC


; ---------------------------------------------------------------------------------------------------------------------
; FPLEN -- LEN s
;
; The length is part of the descriptor, so no paging is needed and the string itself is never touched.
; ---------------------------------------------------------------------------------------------------------------------

FPLEN:     CALL STKFETCH     ;BC=LEN, NO PAGING
           JR STACKBCH


; ---------------------------------------------------------------------------------------------------------------------
; FPSQR -- SQR n  (algorithm by W. E. Thomson)
;
; Newton-Raphson on x = (x + n/x)/2, five iterations, which is enough for the full 32-bit mantissa because the
; initial guess is already good to within a factor of two: halving the exponent of n gives a number of the right
; order, and forcing the mantissa to &7F... starts x at roughly one times that.
;
; The halving that completes each iteration is done by decrementing the exponent in place rather than by a
; divide -- the DEC (HL) after the bytecode block.
;
; Entry:  n on the calculator stack at (HL)
; Exit:   sqrt(n), DE = STKEND
; Errors: ERR_BADARG for a negative argument
; ---------------------------------------------------------------------------------------------------------------------

FPSQR:     DB CALC
           DB RESTACK        ;USE FULL F.P. FORMS
           DB STO0
           DB EXIT

           LD A,(HL)
           AND A
           RET Z             ;RET IF SQR(0) WITH ZERO ON FPCS, DE=STKEND

           ADD A,&80         ;GET TRUE EXPONENT. CY IF WAS >=80H
           RRA               ;/2, WITH BIT 7 AS ORIGINAL
           LD (HL),A
           INC HL
           LD A,(HL)         ;FETCH SGN BIT
           RLA
           JP C,INVARG       ;ERROR IF SQR OF -VE NUMBER

           LD (HL),&7F       ;MANTISSA STARTS AT ABOUT ONE
           LD B,5            ;5 ITERATIONS

SQURLP:    DB CALC
           DB DUP            ;X,X
           DB RCL0           ;X,X,N
           DB SWOP           ;X,N,X
           DB DIVN           ;X,N/X
           DB ADDN           ;X+N/X
           DB EXIT

           DEC (HL)          ;DEC EXPONENT (HALVE VALUE)
           DJNZ SQURLP

           RET               ;DE=STKEND


; ---------------------------------------------------------------------------------------------------------------------
; FPABS -- ABS n. Unary, operating in place
;
; Two number formats have to be handled. A small integer is stored as 00, sign, low, high, 00 with the sign byte 0
; or &FF, so ABS of a negative one has to negate the 16-bit value as well as clear the sign byte -- which is exactly
; what NEGATE does, so the two share that code. A floating-point number just needs bit 7 of its first mantissa byte
; cleared.
;
; Entry:  HL points at the number on the calculator stack
; ---------------------------------------------------------------------------------------------------------------------

FPABS:     LD A,(HL)
           INC HL
           AND A
           JR NZ,FPABS2      ;JR IF FP

           LD A,(HL)         ;SGN BYTE
           INC A
           RET NZ            ;RET IF SIGN WAS 0 (+VE), OK
                             ;ELSE SIGN WAS FF, NOW A=0
           JR NEGABSC

FPABS2:    RES 7,(HL)        ;SIGN=POS.
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPNEGAT -- unary minus. Unary, operating in place
;
; As ABS, but the sign byte is complemented rather than cleared, so the shared tail at NEGABSC serves both: ABS
; arrives with A = 0 and NEGATE with A = the complemented sign. Integer zero is left alone, since negating it would
; produce the illegal form &FF,0,0.
; ---------------------------------------------------------------------------------------------------------------------

FPNEGAT:   LD A,(HL)
           INC HL
           AND A
           JR NZ,FPNEGAT2    ;JR IF FP

           INC HL
           OR (HL)
           INC HL
           OR (HL)           ;TEST FOR INTEGER=0
           RET Z             ;DO NOTHING IF SO

           DEC HL
           DEC HL
           LD A,(HL)         ;SGN
           CPL

NEGABSC:   LD (HL),A         ;REVERSE SIGN (OR MAKE +VE IF ABS)
           INC HL
           LD A,(HL)
           CPL
           LD C,A
           INC HL
           LD A,(HL)
           CPL
           LD B,A
           INC BC            ;NEGATE INTEGER
           LD (HL),B
           DEC HL
           LD (HL),C         ;LOAD IT BACK
           RET

FPNEGAT2:  LD A,&80
           XOR (HL)          ;REVERSE SIGN BIT
           LD (HL),A
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPSGN -- SGN n. Unary
;
; Returns -1, 0 or 1. The sign is extracted by rotating the second byte (the sign byte of an integer, or the byte
; holding the sign bit of a float) into carry and using SBC A,A to spread it to &00 or &FF.
; ---------------------------------------------------------------------------------------------------------------------

FPSGN:     CALL TSTZERO2
           EX DE,HL
           RET Z             ;SGN ZERO=0

           PUSH DE
           INC HL
           LD A,(HL)
           RLA
           DEC HL

           SBC A,A           ;-VE=FF, +VE=00
           LD C,A
           LD DE,&0001
           JP STOREI         ;STORE SIGNED INTEGER, POP DE, RET


; ---------------------------------------------------------------------------------------------------------------------
; FPINT -- INT n. Unary
;
; The floor function, which differs from truncation only for negative non-integers: TRUNC -5.9 is -5.0 but
; INT -5.9 must be -6.0. Written as calculator bytecode: truncate, and if the truncation changed the value and the
; value was negative, subtract one.
;
; The equality test is done by subtracting the original from the truncated value and testing for zero, rather than
; by comparing, because the calculator has no three-way compare.
; ---------------------------------------------------------------------------------------------------------------------

FPINT:     LD A,(HL)
           AND A
           RET Z             ;RET IF INTEGER ALREADY (OR ZERO)

           DB CALC
           DB DUP            ;N1,N1
           DB GRTR0          ;N1,(0 OR 1)
           DB JPTRUE         ;JP IF +VE, FPINTP
           DB &0B            ;** BUG FIX

           DB DUP            ;N,N
           DB TRUNC          ;N,TRUNC N
           DB DUP            ;N,TRUNC N,TRUNC N
           DB SWOP13         ;TRUNC N,TRUNC N,N
           DB SUBN           ;TRUNC N,0 IF N WAS A WHOLE NUMBER
           DB JPFALSE        ;TRUNC N. JP IF VALUE WAS INTEGER, TO EXIT2
           DB &03

           DB STKONE         ;TRUNC N,1
           DB SUBN           ;TRUNC N-1
           DB EXIT2

FPINTP:    DB TRUNC          ;INT(N)
           DB EXIT2


; ---------------------------------------------------------------------------------------------------------------------
; FPTRUNCT -- TRUNCATE n. Unary
;
; Discards the bits after the binary point, converting to the compact integer form where the result will fit.
; Three cases:
;
;   exponent < &81   the value is less than 1, so the answer is zero: NILBYTES clears all 40 bits
;   exponent < &91   the integer part fits in 16 bits, so the mantissa is shifted right into DE, the implied leading
;                    1 bit is restored, and STOREI writes the compact form
;   otherwise        too big for the integer form, so the fractional bits are simply masked off in place by
;                    NILBYTES; a value of 2^32 or more has no fractional bits and is returned untouched (RET P)
;
; The shift count arithmetic in TRUNCI2 -- CPL, ADD &91, then the SUB/ADD of 8 -- computes &91 minus the exponent,
; testing on the way whether the shift is 8 or more so that a whole byte can be moved instead of shifted.
; ---------------------------------------------------------------------------------------------------------------------

FPTRUNCT:  LD A,(HL)
           AND A
           RET Z             ;RET IF INTEGER

           LD B,8            ;FOR LATER
           CP &81
           JR C,TRUNC0       ;JR IF LESS THAN 1

           CP &91
           JR NC,TRUNCLG     ;JR IF >=65536

           PUSH DE
           INC HL
           LD D,(HL)
           INC HL
           LD E,(HL)
           DEC HL
           DEC HL
           LD C,&FF
           BIT 7,D
           JR NZ,TRUNCI2     ;JR IF -VE WITH C=SIGN BYTE FOR SMALL INTEGER

           SET 7,D           ;TRUE NUMERIC BIT
           INC C             ;SIGN BYTE FOR +VE=0

TRUNCI2:   CPL
           ADD A,&91
           SUB B             ;B=8
           ADD A,B
           JR C,TRUNCI3

           LD E,D
           LD D,0
           SUB B

TRUNCI3:   JR Z,TRUNCI5

           LD B,A

TRUNCI4:   SRL D
           RR E
           DJNZ TRUNCI4

TRUNCI5:   JP STOREI

TRUNCLG:   ADD A,&60
           RET P             ;NO FRACTIONAL BITS AT ALL: NOTHING TO DO

           CPL
           INC A             ;NEG
           DB SKIP2LDNN      ;"JR+2" PAST THE LD A,&28. THE (nn) IT SPELLS IS IN ROM, SO THE WRITE IS LOST


; ---------------------------------------------------------------------------------------------------------------------
; NILBYTES -- clear the low A bits of the number at (DE)
;
; Whole bytes are zeroed eight bits at a time from the least significant end; the remainder, if any, is masked off
; with a value built by shifting &FF left the required number of places.
;
; Entry:  A = bits to clear, B = 8, DE = one past the last byte of the number
; Exit:   DE preserved, HL preserved
; ---------------------------------------------------------------------------------------------------------------------

TRUNC0:    LD A,&28          ;ZERO 40 BITS - ALL OF THEM!

NILBYTES:  PUSH DE
           EX DE,HL          ;PT TO AFTER LAST BYTE OF NUMBER
           DB SKIP2LDNN      ;"JR+2" INTO THE LOOP AT NILBYT2 -- AGAIN THE WRITE LANDS IN ROM

NILBYLP:   LD (HL),0

NILBYT2:   DEC HL
           SUB B             ;B=8
           JR NC,NILBYLP

           ADD A,B           ;CY SET
           JR Z,NILBYEND

           LD B,A
           SBC A,A           ;A=FF

NILBMASK:  ADD A,A           ;MASK FOR RHS BITS PRODUCED
           DJNZ NILBMASK

           AND (HL)
           LD (HL),A         ;DO THE MASKING

NILBYEND:  EX DE,HL
           POP DE
           RET


; ---------------------------------------------------------------------------------------------------------------------
; FPUDG -- UDG a$
;
; The address of a character's bitmap. Three ranges, three base pointers:
;
;   &20-&7F    the ordinary font, at (CHARS)
;   &80-&A8    the low UDGs, at (UDG) -- which points at the bitmap of CHR$ 144, so the base is biased down by
;              144 cells to make the arithmetic uniform
;   &A9-&FF    the high UDGs, at (HUDG), with the code reduced modulo the start of the range
;
; The tokeniser rewrites USR "A" as UDG "(CHR$ 144)" for compatibility with Spectrum programs, which is why this
; routine and USR share a spelling in old listings. Note that HUDG is never written by the ROM itself -- see
; docs/hudg.md.
;
; Entry:  a one-character string on the calculator stack at (HL)
; Exit:   the bitmap address on the calculator stack
; Errors: ERR_BADARG unless the string is exactly one character of code &20 or more
; ---------------------------------------------------------------------------------------------------------------------

FPUDG:     CALL SBUFFET
           DEC A

IAHOP:     JP NZ,INVARG      ;LEN MUST BE 1

           LD A,(DE)         ;READ CHAR FROM BUFFER
           CP " "
           JR C,IAHOP

           LD HL,(CHARS)
           CP &80
           JR C,FPUDG3       ;JR IF RANGE 20H-7FH

           LD HL,(UDG)
           LD DE,-UDGFIRST*CELLBYTES
           ADD HL,DE         ;ALLOW FOR UDG VAR. POINTING TO CHR$ 144
           CP HUDGFIRST
           JR C,FPUDG3       ;JR IF CHR$ 80H-A8H (LOW UDGS)

           SUB HUDGFIRST
           LD HL,(HUDG)

FPUDG3:    EX DE,HL
           LD L,A
           LD H,0
           ADD HL,HL
           ADD HL,HL
           ADD HL,HL
           ADD HL,DE
           JP STACKHL        ;STACK CHAR PATTERN ADDR
