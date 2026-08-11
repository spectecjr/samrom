; =====================================================================================================================
; TEXT.ASM -- Messages, keywords, dispatch tables, the key map and the character set
; =====================================================================================================================
;
; Everything in this file is data. Nothing here is executed; it is read by code elsewhere, and the ROM's remaining
; free space is largely a consequence of how tightly it is packed.
;
; Contents, in order:
;
;   UMVAL      utility messages (the copyright banner, "scroll?", file type names)
;   ERRMVAL    the 56 error and report messages
;   COMPLIST   the substring dictionary those two are compressed against
;   KEYWTAB    every keyword and function name, in token order
;   DKSRC      the initial DEF KEY definitions for the function keys
;   CHIT/MAIT  the initial values of the system variables, copied wholesale at cold start
;   CHANTAB    the initial channel table
;   KSRC       the key map: 70 keys x 3 shift states
;   CKTAB      the CONTROL-key table
;   INITCOLS   the initial palette
;   CMDADT     the command address table -- token &90-&F6 to routine
;   U8TAB      the eighth-scan patches for descenders
;   SUBTAB     powers of ten for printing integers
;   CHARSRC    the character set, packed five bits to a scan
;
; ---------------------------------------------------------------------------------------------------------------------
; Message encoding
; ---------------------------------------------------------------------------------------------------------------------
;
; Messages are strings whose final character has bit 7 set; there are no lengths or terminators, so the printer walks
; forward from the start of the table counting terminators to find message n.
;
; Bytes below 32 within a message are not characters but indices into COMPLIST, the dictionary of common substrings
; -- " without ", "Invalid ", "creen" and so on. The message printer (POMSR3 in TPRINT.ASM) recurses one level to
; expand them. The comment on each COMPLIST entry records how many messages use it; the whole scheme saves over 200
; bytes, which is why messages read so oddly in the source.
;
; The dictionary index for each entry is defined by an EQU immediately after it, so adding an entry renumbers
; nothing.
; =====================================================================================================================


; ---------------------------------------------------------------------------------------------------------------------
; UMVAL -- utility messages. Copied to the UMSGS system variable at initialisation
;
;   0  the copyright banner, printed by NEW and by report &50
;   1  "scroll?"
;   2  unused
;   3  "Start tape and then press a key"
;   4-8 the file type names used while searching a tape: "Basic: ", "Numeric array: " and so on
; ---------------------------------------------------------------------------------------------------------------------

UMVAL:

  DM "   MILES GORDON TECHNOLOGY PLC  "
  DM "     "
  DB 127                    ; The copyright sign
  DM " 1990  SAM Cou"
  DB "p"+&80  ;0

  DM "scroll"
  DB "?"+&80  ;1

  DB " "+&80  ;2 NOT USED

  DM "St"
  DB CAR
  DM "t tape and then press a ke"
  DB "y"+&80  ;3

  DM "Basic:"
  DB " "+&80  ;4

  DM "Nu"
  DB CME
  DM "ric"
  DB ARRAY+&80  ;5

  DB STRING,ARRAY+&80  ;6

  DM "Co"
  DB CDE,":"," "+&80  ;7

  DB "S",CREEN,":"," "+&80  ;8


; ---------------------------------------------------------------------------------------------------------------------
; ERRMVAL -- error and report messages, in code order. Copied to ERRMSGS at initialisation
;
; The index is the byte following RST &08; see the ERR_ constants in EQUATES.ASM. Code 0 ("OK") is the normal end of
; a program rather than an error, and codes 14-17 are reports of a stop rather than of a fault.
; ---------------------------------------------------------------------------------------------------------------------

ERRMVAL:

  DB "O","K"+&80  ;0

  DM "Out"
  DB SOFS,CME
  DM "mor"
  DB "y"+&80  ;1

  DB SNOTS
  DM "foun"
  DB "d"+&80  ;2

  DM "DATA has all been rea"
  DB "d"+&80  ;3

  DM "Subscript wron"
  DB "g"+&80  ;4

  DB CNXT,WITHOUT
  DM "FO"
  DB "R"+&80  ;5

  DM "FOR"
  DB WITHOUT,CNXT+&80  ;6

  DM "FN"
  DB WITHOUT
  DM "DEF F"
  DB "N"+&80  ;7

  DM "RETURN"
  DB WITHOUT
  DM "GOSU"
  DB "B"+&80  ;8

  DB MISSING,CLOOP+&80  ;9

  DB CLOOP,WITHOUT,"D","O"+&80  ;10

  DB NO
  DM "POP dat"
  DB "a"+&80  ;11

  DB MISSING
  DM "DEF"
  DB CPROC+&80  ;12

  DB NO
  DM "END"
  DB CPROC+&80  ;13

  DB BREAK
  DM "- CONTINUE "
  DB CTO
  DM " repea"
  DB "t"+&80  ;14

  DB BREAK,CIN,CTO
  DM " progra"
  DB "m"+&80  ;15

  DB CSTOP,"s",TATEMENT+&80  ;16

  DB CSTOP,CIN
  DM " INPU"
  DB "T"+&80  ;17

  DB INVALID,FILE,SNAME+&80  ;18

  DM "Load"
  DB CIN,"g",ERROR+&80  ;19

  DB INVALID,CDE
  DM "vic"
  DB "e"+&80  ;20

  DB INVALID,"s",TREAM
  DM " n"
  DB UMBER+&80  ;21

  DM "End"
  DB SOFS,FILE+&80  ;22

  DB INVALID,CLOUR+&80  ;23

  DB INVALID,PALET,CLOUR+&80  ;24

  DB TOOMANY,PALET
  DM "change"
  DB "s"+&80  ;25

  DB "P",CAR,"a",CME
  DM "ter"
  DB ERROR+&80  ;26

  DB INVALID,CAR
  DM "gu"
  DB CME,"n","t"+&80  ;27

  DB "N",UMBER,TOO,"l",CAR,"g","e"+&80  ;28

  DM "Not un"
  DB CDE
  DM "rs"
  DB CTO,"o","d"+&80  ;29

  DM "Integer out"
  DB SOFS
  DM "rang"
  DB "e"+&80  ;30

  DB "S",TATEMENT
  DM " doesn't exis"
  DB "t"+&80  ;31

  DM "Off s"
  DB CREEN+&80  ;32

  DB NO
  DM "room for l"
  DB CIN,"e"+&80  ;33

  DB INVALID,"s",CREEN
  DM " mod"
  DB "e"+&80  ;34

  DB INVALID
  DM "BLITZ cod"
  DB "e"+&80  ;35

  DB "S",CTO
  DM "red "
  DB CAR
  DM "ea"
  DB TOO
  DM "bi"
  DB "g"+&80  ;36

  DB INVALID
  DM "PUT bloc"
  DB "k"+&80  ;37

  DM "PUT mask mismatc"
  DB "h"+&80  ;38

  DB MISSING
  DM "END I"
  DB "F"+&80  ;39

  DB INVALID,"v",CAR
  DM "iable"
  DB SNAME+&80  ;40

  DM "BASIC stack ful"
  DB "l"+&80  ;41

  DB STRING,TOO,LONG+&80  ;42

  DB INVALID,"s",CREEN
  DM " n"
  DB UMBER+&80  ;43

  DB "S",CREEN,ISALREDOP+&80  ;44

  DB "S",TREAM,ISALREDOP+&80  ;45

  DM "Current s"
  DB CREEN+&80  ;46  WAS INVALID CHANNEL

  DB "S",TREAM
  DM " is"
  DB SNOTS
  DM "ope"
  DB "n"+&80  ;47

  DB INVALID
  DM "CLEAR addres"
  DB "s"+&80  ;48

  DB INVALID,NOTE+&80  ;49

  DB NOTE,TOO,LONG+&80  ;50

  DM "FPC"
  DB ERROR+&80  ;51

  DB TOOMANY,CDE,"f",CIN
  DM "ition"
  DB "s"+&80  ;52

  DM "No DO"
  DB "S"+&80  ;53

  DB INVALID
  DM "WINDO"
  DB "W"+&80  ;54

  DB MISSING
  DM "dis"
  DB "k"+&80  ;55


; ---------------------------------------------------------------------------------------------------------------------
; COMPLIST -- the substring dictionary
;
; Entries are ordinary bit-7-terminated strings; the EQU after each gives the code that stands for it inside a
; message. Codes run 0-31, which is why no message may contain a literal control code below 32.
;
; SAVES OVER 200 BYTES.
; ---------------------------------------------------------------------------------------------------------------------

COMPLIST:  DM "Invalid"
           DB " "+&80            ;14 uses

INVALID:   EQU 0

           DM " without"
           DB " "+&80           ;5 uses

WITHOUT:   EQU 1

           DM "Missing"
           DB " "+&80            ;5 uses

MISSING:   EQU 2

           DM " too"
           DB " "+&80               ;3 uses

TOO:       EQU 3

           DM " is already ope"
           DB "n"+&80    ;2 uses

ISALREDOP: EQU 4

           DM "palette"
           DB " "+&80            ;2 uses

PALET:     EQU 5

           DM " of"
           DB " "+&80                ;3 uses

SOFS:      EQU 6

           DM " erro"
           DB "r"+&80              ;4 uses

ERROR:     EQU 7

           DM "trea"
           DB "m"+&80               ;3 uses

TREAM:     EQU 8

           DM "umbe"
           DB "r"+&80               ;3 uses

UMBER:     EQU 9

           DM "NEX"
           DB "T"+&80                ;2 uses

CNXT:      EQU 10

           DM "No"
           DB " "+&80                 ;3 uses

NO:        EQU 11

           DM "BREAK"
           DB " "+&80              ;2 uses

BREAK:     EQU 12

           DM "cree"
           DB "n"+&80               ;6 USES

CREEN:     EQU 13

           DM " array:"
           DB " "+&80            ;2 USES

ARRAY:     EQU 14

           DM "Not"
           DB "e"+&80                ;2 USES

NOTE:      EQU 15

           DM "lon"
           DB "g"+&80                ;2 USES

LONG:      EQU 16

           DM " not"
           DB " "+&80               ;2 USES

SNOTS:     EQU 17

           DM " nam"
           DB "e"+&80               ;2 USES

SNAME:     EQU 18

           DM "Strin"
           DB "g"+&80          ;2 USES

STRING:    EQU 19

           DM "Too many"
           DB " "+&80       ;2 USES

TOOMANY:   EQU 20

           DM "tatemen"
           DB "t"+&80         ;2 USES

TATEMENT:  EQU 21

           DM "STOP"
           DB " "+&80           ;2 USES

CSTOP:     EQU 22

           DM "fil"
           DB "e"+&80            ;2 USES

FILE:      EQU 23

           DM "colou"
           DB "r"+&80          ;2 USES

CLOUR:     EQU 24

           DB "i","n"+&80              ;5 USES

CIN:       EQU 25

           DM " PRO"
           DB "C"+&80           ;2 USES

CPROC:     EQU 26

           DM "LOO"
           DB "P"+&80            ;2 USES

CLOOP:     EQU 27

           DB "t","o"+&80              ;4 USES

CTO:       EQU 28

           DB "d","e"+&80              ;4 USES

CDE:       EQU 29

           DB "m","e"+&80              ;2 USES

CME:       EQU 30

           DB "a","r"+&80              ;6 USES

CAR:       EQU 31


; =====================================================================================================================
; KEYWTAB -- the keyword table
; =====================================================================================================================
;
; Every keyword and function name, in token order, each terminated by setting bit 7 of its last character. The table
; is walked forwards from a known anchor, counting terminators, both by the tokeniser (GETTOKEN in SCRSEL2.ASM,
; matching text against the table) and by LIST (PRGR80 in TPRINT.ASM, expanding a token back into text). The
; labels IMFNTL, FPCFNTL, BINFNTL, KWDS85, KWDSA0, KWDSC0 and KWDSE0 are those anchors; searching from the nearest
; one is what keeps tokenising fast.
;
; A single "-" entry is a placeholder for an unused code, present so the count stays right. It can never match
; anything the tokeniser is looking for, since a lone hyphen is punctuation rather than a word.
;
; ---------------------------------------------------------------------------------------------------------------------
; The code space
; ---------------------------------------------------------------------------------------------------------------------
;
;   &21-&69   functions, always preceded by &FF
;   &20-&7F   ASCII
;   &80-&8F   block graphics / extended characters
;   &90-&A8   extended characters
;   &96-&9F   qualifiers
;   &A0-&FE   commands
;
; &80-&A8 act as UDGs -- programmed as block graphics followed by extended characters on power-up, with the UDG
; system variable pointing at USR "A". That takes 328 bytes of RAM. The overlap with command tokens is resolved by
; context: PRINT CHR$ 160 gives a UDG, LIST of a command gives the keyword, and quotes force UDGs.
;
; The original source notes two ideas here that were never implemented: allowing codes &80-&95 in PROC names "so a
; face symbol can be a command name?" (its own question mark), and using "." to introduce an external command.
; GETALPH accepts only A-Z and a-z, so neither works in the shipped ROM.
; =====================================================================================================================

KEYWTAB:      DB &A0            ; Lead byte: the table proper starts at the next byte

; --- "Immediate" functions: those the evaluator handles itself rather than through the calculator -------------------

IMFNTL:       DM "P"            ;&3B
              DB "I"+&80

              DM "RN"           ;
              DB "D"+&80

              DM "POIN"         ;
              DB "T"+&80

              DM "FRE"          ;
              DB "E"+&80

              DM "LENGT"        ;
              DB "H"+&80

              DM "ITE"          ;
              DB "M"+&80

              DM "ATT"          ;
              DB "R"+&80

              DM "F"            ;
              DB "N"+&80

              DM "BI"           ;
              DB "N"+&80

              DM "XMOUS"        ;
              DB "E"+&80

              DM "YMOUS"        ;
              DB "E"+&80

              DM "XPE"          ;
              DB "N"+&80

              DM "YPE"          ;
              DB "N"+&80

              DM "RAMTO"        ;
              DB "P"+&80

              DB "-"+&80        ; UNUSED INARRAY

              DM "INST"         ;&4A
              DB "R"+&80

              DM "INKEY"        ;&4B
              DB "$"+&80


              DM "SCREEN"       ;
              DB "$"+&80

              DM "MEM"          ;
              DB "$"+&80

              DB "-"+&80        ; UNUSED CHAR$

              DM "PATH"         ;
              DB "$"+&80

              DM "STRING"       ;
              DB "$"+&80

              DB "-"+&80        ; UNUSED USING$
              DB "-"+&80        ;&52 UNUSED SHIFT$

; --- Functions evaluated by the floating-point calculator ------------------------------------------------------------

FPCFNTL:      DM "SI"           ;&53
              DB "N"+&80

              DM "CO"           ;
              DB "S"+&80

              DM "TA"           ;
              DB "N"+&80

              DM "AS"           ;
              DB "N"+&80

              DM "AC"           ;
              DB "S"+&80

              DM "AT"           ;
              DB "N"+&80

              DM "L"            ;
              DB "N"+&80

              DM "EX"           ;
              DB "P"+&80

              DM "AB"           ;
              DB "S"+&80

              DM "SG"           ;
              DB "N"+&80

              DM "SQ"           ;
              DB "R"+&80

              DM "IN"           ;
              DB "T"+&80

              DM "US"           ;
              DB "R"+&80

              DM "I"            ;
              DB "N"+&80

              DM "PEE"          ;
              DB "K"+&80

              DM "DPEE"         ;
              DB "K"+&80

              DM "DVA"          ;
              DB "R"+&80

              DM "SVA"          ;
              DB "R"+&80

              DM "BUTTO"        ;
              DB "N"+&80

              DM "EO"           ;
              DB "F"+&80

              DM "PT"           ;   DISC USE?
              DB "R"+&80

              DB "-"+&80

              DM "UD"           ;
              DB "G"+&80

              DB "-"+&80

              DM "LE"           ;
              DB "N"+&80

              DM "COD"          ;
              DB "E"+&80

              DM "VAL"          ;
              DB "$"+&80

              DM "VA"           ;
              DB "L"+&80

              DM "TRUNC"        ;
              DB "$"+&80

              DM "CHR"          ;
              DB "$"+&80

              DM "STR"          ;
              DB "$"+&80

              DM "BIN"          ;
              DB "$"+&80

              DM "HEX"          ;
              DB "$"+&80

              DM "USR"          ;
              DB "$"+&80

              DB "-"+&80        ; CORRESPONDS TO INKEY$ FPC CODE

              DM "NO"           ;
              DB "T"+&80

              DB "-"+&80        ;
              DB "-"+&80        ;
              DB "-"+&80        ;&79

; --- Binary operators that are spelled as words ----------------------------------------------------------------------

BINFNTL:      DM "MO"           ;&7A
              DB "D"+&80

              DM "DI"           ;
              DB "V"+&80

              DM "BO"           ;
              DB "R"+&80

              DB "-"+&80

              DM "BAN"          ;
              DB "D"+&80

              DM "O"            ;
              DB "R"+&80

              DM "AN"           ;
              DB "D"+&80

              DM "<"            ;
              DB ">"+&80

              DM "<"            ;
              DB "="+&80

              DM ">"            ;&83
              DB "="+&80



; --- Qualifiers: keywords that appear inside a statement rather than starting one, range &85-&8F ---------------------

KWDS85:       DM "USIN"             ;&85
              DB "G"+&80

              DM "WRIT"             ;86
              DB "E"+&80

              DM "A"                ;87
              DB "T"+&80

              DM "TA"               ;88
              DB "B"+&80

              DM "OF"               ;89
              DB "F"+&80

              DM "WHIL"             ;8A
              DB "E"+&80

              DM "UNTI"             ;8B
              DB "L"+&80

              DM "LIN"              ;8C
              DB "E"+&80

              DM "THE"              ;8D
              DB "N"+&80

              DM "T"                ;8E
              DB "O"+&80

              DM "STE"              ;8F
              DB "P"+&80

; --- Commands, range &90-&FE. CMDADT below holds the address of each ------------------------------------------------
; Codes &90-&93, &E3, &F1 and &F2 are DOS commands: the ROM tokenises them but dispatches them to NONSENSE unless
; DOS has claimed them.

              DM "DI"               ;90
              DB "R"+&80

              DM "FORMA"            ;91
              DB "T"+&80

              DM "ERAS"             ;92
              DB "E"+&80

              DM "MOV"              ;93
              DB "E"+&80

              DM "SAV"              ;94
              DB "E"+&80

              DM "LOA"              ;95
              DB "D"+&80

              DM "MERG"             ;96
              DB "E"+&80

              DM "VERIF"            ;97
              DB "Y"+&80

              DM "OPE"              ;98
              DB "N"+&80

              DM "CLOS"             ;99
              DB "E"+&80


              DM "CIRCL"            ;9A
              DB "E"+&80

              DM "PLO"              ;9B
              DB "T"+&80

              DM "LE"               ;9C
              DB "T"+&80

              DM "BLIT"             ;9D
              DB "Z"+&80

              DM "BORDE"            ;9E
              DB "R"+&80

              DM "CL"               ;9F
              DB "S"+&80

KWDSA0:       DM "PALETT"           ;A0
              DB "E"+&80

              DM "PE"               ;A1
              DB "N"+&80

              DM "PAPE"             ;A2
              DB "R"+&80

              DM "FLAS"             ;A3
              DB "H"+&80

              DM "BRIGH"            ;A4
              DB "T"+&80

              DM "INVERS"           ;A5
              DB "E"+&80

              DM "OVE"              ;A6
              DB "R"+&80


              DM "FATPI"            ;A7  0=THIN, 1=FAT
              DB "X"+&80

              DM "CSIZ"             ;A8
              DB "E"+&80

              DM "BLOCK"            ;A9
              DB "S"+&80

              DM "MOD"              ;AA
              DB "E"+&80

              DM "GRA"              ;AB
              DB "B"+&80

              DM "PU"               ;AC
              DB "T"+&80


              DM "BEE"              ;AD
              DB "P"+&80

              DM "SOUN"             ;AE
              DB "D"+&80


              DM "NE"               ;AF
              DB "W"+&80

              DM "RU"               ;B0
              DB "N"+&80

              DM "STO"              ;B1
              DB "P"+&80

              DM "CONTINU"          ;B2
              DB "E"+&80

              DM "CLEA"             ;B3
              DB "R"+&80

              DM "GO T"             ;B4
              DB "O"+&80

              DM "GO SU"            ;B5
              DB "B"+&80

              DM "RETUR"            ;B6
              DB "N"+&80

              DM "RE"               ;B7
              DB "M"+&80


              DM "REA"              ;B8
              DB "D"+&80

              DM "DAT"              ;B9
              DB "A"+&80

              DM "RESTOR"           ;BA
              DB "E"+&80


              DM "PRIN"             ;BB
              DB "T"+&80

              DM "LPRIN"            ;BC
              DB "T"+&80

              DM "LIS"              ;BD
              DB "T"+&80

              DM "LLIS"             ;BE
              DB "T"+&80

              DM "DUM"              ;BF
              DB "P"+&80

KWDSC0:       DM "FO"               ;C0
              DB "R"+&80

              DM "NEX"              ;C1
              DB "T"+&80

              DM "PAUS"             ;C2
              DB "E"+&80

              DM "DRA"              ;C3
              DB "W"+&80

              DM "DEFAUL"           ;C4
              DB "T"+&80

              DM "DI"               ;C5
              DB "M"+&80

              DM "INPU"             ;C6
              DB "T"+&80

              DM "RANDOMIZ"         ;C7
              DB "E"+&80

              DM "DEF F"            ;C8
              DB "N"+&80

              DM "DEF KEYCOD"       ;C9
              DB "E"+&80

              DM "DEF PRO"          ;CA
              DB "C"+&80

              DM "END PRO"          ;CB
              DB "C"+&80

              DM "RENU"             ;CC
              DB "M"+&80

              DM "DELET"            ;CD
              DB "E"+&80

              DM "RE"               ;CE
              DB "F"+&80

              DM "COP"              ;CF
              DB "Y"+&80

              DB "-"+&80            ;D0

              DM "KEYI"             ;D1
              DB "N"+&80

              DM "LOCA"             ;D2
              DB "L"+&80

              DM "LOOP I"           ;D3
              DB "F"+&80

              DM "D"                ;D4
              DB "O"+&80

              DM "LOO"              ;D5
              DB "P"+&80

              DM "EXIT I"           ;D6
              DB "F"+&80

; &D7/&D8 and &D9/&DA are pairs spelling the same word. The tokeniser always produces the first of each pair (the
; "long" form); the syntax checker rewrites it to the second when the IF or ELSE turns out to be a single-line one.
; See docs/tokenized-program-format.md.

              DM "I"                ;D7
              DB "F"+&80

              DM "I"                ;D8
              DB "F"+&80

              DM "ELS"              ;D9
              DB "E"+&80

              DM "ELS"              ;DA
              DB "E"+&80

              DM "END I"            ;DB
              DB "F"+&80

              DM "KE"               ;DC
              DB "Y"+&80

              DM "ON ERRO"          ;DD
              DB "R"+&80

              DM "O"                ;DE
              DB "N"+&80

              DM "GE"               ;DF
              DB "T"+&80

KWDSE0:       DM "OU"               ;E0
              DB "T"+&80

              DM "POK"              ;E1
              DB "E"+&80

              DM "DPOK"             ;E2
              DB "E"+&80

              DM "RENAM"            ;E3
              DB "E"+&80

              DM "CAL"              ;E4
              DB "L"+&80

              DM "ROL"              ;E5
              DB "L"+&80

              DM "SCROL"            ;E6
              DB "L"+&80

              DM "SCREE"            ;E7
              DB "N"+&80

              DM "DISPLA"           ;E8
              DB "Y"+&80

BTWD:         DM "BOO"              ;E9 USED BY BOOT TO CHECK FILE NAME
              DB "T"+&80

              DM "LABE"             ;EA
              DB "L"+&80

              DM "FIL"              ;EB
              DB "L"+&80

              DM "WINDO"            ;EC
              DB "W"+&80

              DM "AUT"              ;ED
              DB "O"+&80

              DM "PO"               ;EE
              DB "P"+&80

              DM "RECOR"            ;EF
              DB "D"+&80

              DM "DEVIC"            ;F0
              DB "E"+&80

              DM "PROTEC"           ;F1
              DB "T"+&80

              DM "HID"              ;F2
              DB "E"+&80

              DM "ZA"               ;F3
              DB "P"+&80

              DM "PO"               ;F4
              DB "W"+&80

              DM "BOO"              ;F5
              DB "M"+&80

              DM "ZOO"              ;F6
              DB "M"+&80

              DB "-"+&80            ;F7
              DB "-"+&80            ;F8
              DB "-"+&80            ;F9
              DB "-"+&80            ;FA
              DB "-"+&80            ;FB
              DB "-"+&80            ;FC
              DB "-"+&80            ;FD
              DB "-"+&80            ;FE

              DM "IN"               ;FF (FUNCTION PREFIX) AND TEMP "INK" TOKEN
              DB "K"+&80


; ---------------------------------------------------------------------------------------------------------------------
; DKSRC -- the initial DEF KEY definitions, copied into the DEF KEY buffer at cold start
;
; Each record is: key code, length, a zero, then that many bytes of expansion (tokens and characters, exactly as
; DEF KEY would store them). &FF ends the table.
;
; The first ten are the function keys F0-F9; the last three redefine TAB and the INVERSE control codes so that the
; editor's TAB key produces a comma tab and shifted forms produce INVERSE on and off.
; ---------------------------------------------------------------------------------------------------------------------

DKSRC:     DB 192,1,0,TOK_LIST                       ;F0 LIST
           DB 193,2,0,TOK_RENUM,":"                  ;F1 RENUM :
           DB 194,2,0,TOK_PRINT,":"                  ;F2 PRINT :
           DB 195,2,0,TOK_MODE,":"                   ;F3 MODE :
           DB 196,1,0,TOK_RUN                        ;F4 RUN
           DB 197,1,0,TOK_CONTINUE                   ;F5 CONTINUE
           DB 198,2,0,TOK_CLS,"#"                    ;F6 CLS #
           DB 199,3,0,LOADTOK,&22,&22                ;F7 LOAD ""
           DB 200,5,0,LOADTOK,&22,&22,&FF,CODETOK    ;F8 LOAD "" CODE
           DB 201,1,0,TOK_BOOT                       ;F9 BOOT

           DB 252,2,0,CC_COMMA,":"                   ;TAB
           DB 253,3,0,CC_INVERSE,1,":"               ;INVERSE 1 CC
           DB 254,3,0,CC_INVERSE,0,":"               ;INVERSE 0 CC
DKEN:      DB &FF


; ---------------------------------------------------------------------------------------------------------------------
; CHIT / MAIT -- initial values for the system variables
;
; Copied verbatim at cold start: CHIT into the byte-sized variables from CHARS onwards, MAIT into the word-sized
; ones. MISC31.ASM does both with a single LDIR each, which is why the order here has to match the order in
; VARS.ASM exactly. The two are contiguous, and the copy of CHIT runs straight into MAIT -- see the commented-out
; LD HL in MISC31.ASM's cold start.
;
; MAIT's last entry runs into the first four bytes of CHANTAB, which is deliberate: the address of the "K" channel's
; output routine doubles as the last initial value.
; ---------------------------------------------------------------------------------------------------------------------

CHIT:      DB ">"        ;CURRENT LINE CURSOR
           DB 128,129    ;CURSOR CHARACTERS - LOWER CASE/UPPER CASE
           DB "1","0"    ;DIGIT CHARS FOR "BIN$"
           DB "#"        ;INSTR WILD CARD CHAR
           DB "T",TSPEED ;DEVICE T, TAPE SPEED
           DB 17         ;COLOUR FLASH SPEED
           DW LINICOLS   ;LINIPTR
           DB &FF,0,0    ;XCMDP SHOWS "NO EXTERNAL CMDS"

           DB 79         ;PRINTER RHS
           DB 10         ;AFTER CR CHARACTER
           DB &E9        ;PRINTER CONTROL PORT (E8=DATA)
           DB 1          ;PRINTER STROBE BYTE

MAIT:      DW BSTACK     ;BASSTK
           DW HPEND      ;HEAPEND
           DW HPEND      ;HPST  START WITH EMPTY HEAP
           DW FPSB       ;FPSBOT
           DW DKBU       ;DEF KEY BUFFER START
           DW DKBU+128   ;LIMIT OF DEF KEY BUFFER GROWTH
           DW ENDOUTP    ;"PRINTABLE CHARS" O/P ROUTINE
           DW ERRMVAL    ;ERROR MESSAGES
           DW UMVAL      ;"UTILITY" MESSAGES
           DW KTAB       ;KEYBOARD TABLE
           DW CMDADT     ;START OF CMD ADDR TABLE
                         ;FIRST 4 BYTES IN CHANTAB ALSO USED!


; ---------------------------------------------------------------------------------------------------------------------
; CHANTAB -- the initial channel table
;
; Five bytes per channel: output routine, input routine, letter. IDERR is the "invalid device" stub used where a
; channel has no input side.
;
;   K  keyboard and screen -- input echoes, output goes to the lower screen
;   S  screen only
;   R  the editor's own channel: output appends to the line being edited
;   P  printer
;   $  output into a string (stream 16, used by RECORD)
;   B  buffer
;
; The trailing &0D is not part of any channel: READ scans forward from here on the very first line and needs a
; carriage return to stop at.
; ---------------------------------------------------------------------------------------------------------------------

CHANTAB:   DW PRMAIN
           DW KYIP
           DB "K"

           DW PRMAIN
           DW KYIP
           DB "S"

           DW ADDCHAR
           DW IDERR
           DB "R"

           DW PRMAIN
           DW IDERR
           DB "P"

           DW S16OP
           DW IDERR
           DB "$"

           DW SENDA
           DW IDERR
           DB "B"

           DB &0D            ;KEEPS READ CMD HAPPY ON FIRST LINE


; ---------------------------------------------------------------------------------------------------------------------
; KSRC -- the key map
;
; Three tables of 70 entries, for the unshifted, CAPS-shifted and SYMBOL-shifted states, indexed by the scan code
; KEYSCAN produces. KYVL selects a table by adding KBSHIFTTAB (70) to the base for each shift level.
;
;KEY MAP FOR 70 KEYS (3 NOT READ THIS WAY) IN UNSHIFTED, CAPS SHIFTED AND SYMB.
;SHIFTED STATES. EACH ROW CORRESPONDS TO A BIT ON THE PORT (BIT 7 AT TOP) AND
;EACH COLUMN TO A PORT MSB. CAPS SHIFT (BIT 0,PORT FE) SCANNED SEPARATELY, AS
;IS SYM SHIFT (BIT 1,PORT 7F) AND CONTROL (BIT 0,PORT FF)
;
;PORT MSB:     FF  7F  BF  DF  EF  F7  FB  FD  FE
;BIT MAP BYTE  8   7   6   5   4   3   2   1   0
;
; "X" marks a position that is not a key (or is one of the three scanned separately). Codes 192-201 and 252-254 are
; the DEF KEY codes defined in DKSRC above, so pressing F0 yields code 192, which the editor then expands.
;
;254 DEFINED AS INVERSE CC,0
;253 DEFINED AS INVERSE CC,1
;252 DEFINED AS CHR$ 6
; ---------------------------------------------------------------------------------------------------------------------

KSRC:      DB     253,&07,&C0, 12,&06,&C9,198,195  ;BIT 7
           DB "X",".",":", 34,"+",252,200,197,194  ;    6
           DB "X",",",";","=","-"," ",199,196,193  ;    5

           DB &09,"b","h","y","6","5","t","g","v"  ;    4
           DB &08,"n","j","u","7","4","r","f","c"  ;    3
           DB &0A,"m","k","i","8","3","e","d","x"  ;    2
           DB &0B,"X","l","o","9","2","w","s","z"  ;    1
           DB "X"," ",&0D,"p","0","1","q","a"      ;    0

;CAPS SHIFTED

           DB     "\",&07,202,&0E,&06,211,208,205
           DB "X",".",":",127,"*",252,210,207,204
           DB "X",",",";","_","/"," ",209,206,203

           DB &09,"B","H","Y","&","%","T","G","V"
           DB &08,"N","J","U","'","$","R","F","C"
           DB &0A,"M","K","I","(","#","E","D","X"
           DB &0B,"X","L","O",")","@","W","S","Z"
           DB "X"," ",&0D,"P",126,"!","Q","A"

; SYMBOL SHIFTED. Entries of &80 and above are keyword tokens, which is how SYMBOL SHIFT with a letter types a
; whole keyword: VERIFYTOK, SAVETOK, &CF (COPY), &B1 (STOP) and so on.

           DB     254,&0F,"0",&0E,&06,"9","6","3"
           DB "X",">","*",&CF,"*",252,"8","5","2"
           DB "X","<","+","_","/"," ","7","4","1"

           DB &09,&9E,&5E,157,134,133,"]","}",VERIFYTOK
           DB &08,164,"-",129,135,132,"[","{",168
           DB &0A,165,"+",&A5,128,131,130,&9C,"?"
           DB &0B,"X",&60,148,124,130,">",SAVETOK,"?"
           DB "X"," ",&0D,187,126,129,"<",&B1


; ---------------------------------------------------------------------------------------------------------------------
; CKTAB -- the CONTROL-key table
;
; CONTROL plus a key is not looked up in a fourth key map but in this much shorter list of displacement/value pairs,
; because only eleven combinations are defined. The first byte of each pair is the control code or character to
; produce, the second its parameter -- so CONTROL with the key that gives BRIGHT emits control code 19 with
; parameter 3.
; ---------------------------------------------------------------------------------------------------------------------

CKTAB:     DB 19,3           ;BRIGHT CC
           DB 137,1          ;GRAPHICS
           DB 138,8
           DB 136,1
           DB 139,7
           DB 16,1           ;PEN CC
           DB 143,1
           DB 140,9
           DB 141,7
           DB 17,2           ;PAPER CC
           DB 142,0


; ---------------------------------------------------------------------------------------------------------------------
; INITCOLS -- the initial palette
;
; Twenty entries: sixteen for the ordinary palette and four more for mode 2, which has only four colours and takes
; them from separate palette registers.
;
; A palette byte is not a colour index but the hardware's own encoding, with the green, red and blue intensities
; split across two groups of bits by a bright bit:
;
;                GRBbGRB
; ---------------------------------------------------------------------------------------------------------------------

INITCOLS:    DB %0000000     ;BLACK
             DB %0010000     ;BLUE
             DB %0100000     ;RED
             DB %0110000     ;MAGENTA
             DB %1000000     ;GREEN
             DB %1010000     ;CYAN
             DB %1100000     ;YELLOW
             DB %1111000     ;WHITE

             DB %0000000     ;BRIGHT BLACK=BLACK
             DB %0010001     ;BLUE
             DB %0100010     ;RED
             DB %0110011     ;MAGENTA
             DB %1000100     ;GREEN
             DB %1010101     ;CYAN
             DB %1100110     ;YELLOW
             DB %1111111     ;WHITE

            ;COLOURS FOR 4-COLOUR MODE

             DB %0000000     ;BLACK
             DB %0010001     ;BLUE
             DB %0100010     ;RED
             DB %1111111     ;WHITE


; ---------------------------------------------------------------------------------------------------------------------
; CMDADT -- the command address table
;
; One word per command token, from &90 to &F6, in exactly the order of the keyword table above. The main loop
; indexes it with (token - &90) * 2. NONSENSE occupies the slots for commands the ROM tokenises but does not
; implement -- the DOS commands, and a handful never finished.
; ---------------------------------------------------------------------------------------------------------------------

CMDADT:    DW NONSENSE      ;DIR      90 ** ALTERED
           DW NONSENSE      ;FORMAT   91
           DW NONSENSE      ;ERASE    92
           DW NONSENSE      ;MOVE     93
           DW SLMVC         ;SAVE     94
           DW SLMVC         ;LOAD     95
           DW SLMVC         ;MERGE    96
           DW SLMVC         ;VERIFY   97
           DW OPSCRN        ;OPEN     98
           DW CLSCRN        ;CLOSE    99
           DW CIRCLE        ;CIRCLE   9A
           DW PLOT          ;PLOT     9B
           DW LET           ;LET      9C
           DW BLITZ         ;BLITZ    9D
           DW BORDER        ;BORDER   9E
           DW CLS           ;CLS      9F

           DW COLOUR        ;PALETTE  A0
           DW PERMS         ;INK      A1
           DW PERMS         ;PAPER    A2
           DW PERMS         ;FLASH    A3
           DW PERMS         ;BRIGHT   A4
           DW PERMS         ;INVERSE  A5
           DW PERMS         ;OVER     A6
           DW FATPIX        ;FATPIX   A7  PIXEL WIDTH
           DW WIDTH         ;CSIZE    A8
           DW BGRAPHICS     ;BLOCKS   A9  BLOCK GRAPHICS/UDGS
           DW MODECMD       ;MODE     AA
           DW GRAB          ;GRAB     AB
           DW PUT           ;PUT      AC
           DW BEEP          ;BEEP     AD
           DW SOUND         ;SOUND    AE
           DW NEW           ;NEW      AF

           DW RUN           ;RUN      B0
           DW STOP          ;STOP     B1
           DW CONTINUE      ;CONTINUE B2
           DW CLEAR         ;CLEAR    B3
           DW GOTO          ;GO TO    B4
           DW GOSUB         ;GO SUB   B5
           DW RETURN        ;RETURN   B6
           DW REMARK        ;REM      B7
           DW READ          ;READ     B8
           DW DATA          ;DATA     B9
           DW RESTORE       ;RESTORE  BA
           DW PRINT         ;PRINT    BB
           DW LPRINT        ;LPRINT   BC
           DW LIST          ;LIST     BD
           DW LLIST         ;LLIST    BE
           DW COPY          ;DUMP     BF

           DW FOR           ;FOR         C0
           DW NEXT          ;NEXT        C1
           DW PAUSE         ;PAUSE       C2
           DW DRAW          ;DRAW        C3
           DW DEFAULT       ;DEFAULT     C4
           DW DIM           ;DIM         C5
           DW INPUT         ;INPUT       C6
           DW RANDOMIZE     ;RAND        C7
           DW DEFFN         ;DEF FN      C8
           DW DEFKEY        ;DEF KEYCODE C9
           DW DEFPROC       ;DEF PROC    CA
           DW ENDPROC       ;END PROC    CB
           DW RENUM         ;RENUM       CC
           DW DELETE        ;DELETE      CD
           DW NONSENSE      ;REF         CE
           DW NONSENSE      ;COPY        CF

           DW NONSENSE      ;DRIVER   D0
           DW KEYIN         ;KEYIN    D1
           DW LOCAL         ;LOCAL    D2
           DW LOOPIF        ;LOOP IF  D3
           DW DO            ;DO       D4
           DW LOOP          ;LOOP     D5
           DW EXITIF        ;EXIT IF  D6
           DW LIF           ;LONG IF  D7
           DW SIF           ;SHORT IF D8
           DW LELSE         ;LELSE    D9
           DW ELSE          ;ELSE     DA
           DW ENDIF         ;END IF   DB
           DW KEY           ;KEY      DC
           DW ONERROR       ;ON ERROR DD
           DW ON            ;ON       DE
           DW GET           ;GET      DF

           DW OUT           ;OUT      E0
           DW POKE          ;POKE     E1
           DW DPOKE         ;DPOKE    E2
           DW NONSENSE      ;RENAME   E3
           DW CALLER        ;CALL     E4
           DW ROLL          ;ROLL     E5
           DW SCROLL        ;SCROLL   E6
           DW SCREEN        ;SCREEN   E7
           DW DISPLAY       ;DISPLAY  E8
           DW BOOT          ;BOOT     E9
           DW LABEL         ;LABEL    EA
           DW FILL          ;FILL     EB
           DW WINDOW        ;WINDOW   EC
           DW AUTO          ;AUTO     ED
           DW POP           ;POP      EE
           DW RECORD        ;RECORD   EF

           DW SLDEVICE      ;DEVICE   F0
           DW NONSENSE      ;PROTECT  F1
           DW NONSENSE      ;HIDE     F2
           DW ZAP           ;ZAP      F3
           DW POW           ;POW      F4
           DW BOOM          ;BOOM     F5
           DW ZOOM          ;ZOOM     F6
         ;  DW NONSENSE      ;         F7
          ; DW NONSENSE      ;         F8
          ; DW NONSENSE      ;         F9
          ; DW NONSENSE      ;         FA
          ; DW NONSENSE      ;         FB
          ; DW NONSENSE      ;         FC
          ; DW NONSENSE      ;         FD
          ; DW NONSENSE      ;         FE
          ; DW NONSENSE      ;         FF (FUNCTION PREFIX)


; ---------------------------------------------------------------------------------------------------------------------
; U8TAB -- eighth-scan patches for the character set
;
; CHARSRC stores only seven scans per character, so a descender would be clipped. This table supplies the missing
; eighth scan for the thirteen characters that need one, as (value, displacement to the next such character) pairs
; walked by UPACK in MISC31.ASM. A displacement byte of zero ends the table -- and that terminator is the first
; byte of VVAR2 below, shared to save a byte.
; ---------------------------------------------------------------------------------------------------------------------

U8TAB:     DB &08,&78        ;","
           DB &08,&80        ;";"
           DB &00,&A0        ;DUMMY
           DB &FF,&40        ;"_"
           DB &1C,&18        ;"g"
           DB &10,&30        ;"j"
           DB &20,&08        ;"p"
           DB &02,&40        ;"q"
           DB &1C            ;"y"

; VVAR2 -- the base address of the system variable area, as a word. SVAR n adds n to this; the low byte doubles as
; U8TAB's terminating zero displacement.

VVAR2:     DB &00,&5A        ;U8TAB TERMINATOR/SVAR BASE ADDR


; ---------------------------------------------------------------------------------------------------------------------
; SUBTAB -- negated powers of ten, used by PRNUMB to print an integer by repeated subtraction
;
; There is no entry for 1: the final digit is whatever is left. The table has no terminator either -- the first byte
; of CHARSRC, which is zero, serves as one.
; ---------------------------------------------------------------------------------------------------------------------

SUBTAB:    DW -10000
           DW -1000
           DW -100
           DW -10
;          DB  0  CHARSRC 1ST BYTE IS TERMINATOR!


; =====================================================================================================================
; CHARSRC -- the packed character set
; =====================================================================================================================
;
;CHARSET BY SIMON N. GOODWIN
;CHARACTERS USE CENTRE 6 PIXELS, CAN BE UP TO 8 PIXELS HIGH
;COMPRESSED FORM USES 7 5-BIT SLICES PER CHAR, TAKES 600 BYTES VS 1096
;
; 99 characters, starting at code 32, each seven scans of five bits, packed continuously across byte boundaries with
; no padding: 99 x 7 x 5 bits. UPACK (MISC31.ASM) expands each five-bit slice into a full byte, rotating it one place
; left so the glyph sits with two blank columns to its left and one to its right -- which is what makes the set look
; right in both the 6-pixel and 8-pixel character widths (see docs/font-rendering.md). The eighth scan is blank
; except for the characters U8TAB patches.
;
; The figures in the original comment predate the removal of the foreign character set; the table as it stands is
; 434 bytes.
; =====================================================================================================================

CHARSRC:

    DB &00,&00,&00,&00,&04
    DB &21,&08,&40,&11,&4A
    DB &00,&00,&00,&29,&5F
    DB &57,&D4,&A7,&52,&8E
    DB &29,&5D,&9C,&88,&88
    DB &9C,&D1,&4A,&22,&B2
    DB &69,&84,&40,&00,&00
    DB &08,&88,&42,&08,&30
    DB &41,&08,&44,&40,&95
    DB &77,&DD,&52,&00,&84
    DB &F9,&08,&00,&00,&00
    DB &31,&84,&00,&03,&E0
    DB &00,&00,&00,&00,&06
    DB &30,&42,&22,&22,&10
    DB &74,&67,&5C,&C5,&C4
    DB &61,&08,&42,&39,&D1
    DB &08,&88,&8F,&BA,&21
    DB &30,&62,&E1,&19,&52
    DB &F8,&85,&F8,&78,&21
    DB &8B,&8C,&88,&7A,&31
    DB &77,&C2,&22,&22,&10
    DB &74,&62,&E8,&C5,&CE
    DB &8C,&5E,&11,&30,&00
    DB &31,&80,&63,&00,&06
    DB &30,&0C,&20,&88,&88
    DB &20,&82,&00,&7C,&1F
    DB &00,&20,&82,&08,&88
    DB &83,&A2,&11,&10,&04
    DB &74,&67,&5B,&C1,&CE
    DB &8C,&7F,&18,&C7,&D1
    DB &8F,&A3,&1F,&3A,&30
    DB &84,&22,&EF,&46,&31
    DB &8C,&7D,&F8,&43,&D0
    DB &87,&FF,&08,&7A,&10
    DB &83,&A3,&08,&4E,&2E
    DB &8C,&63,&F8,&C6,&2E
    DB &21,&08,&42,&38,&21
    DB &08,&43,&17,&46,&54
    DB &C5,&25,&18,&42,&10
    DB &84,&3F,&1D,&D6,&31
    DB &8C,&63,&1C,&D6,&71
    DB &8B,&A3,&18,&C6,&2E
    DB &F4,&63,&E8,&42,&0E
    DB &8C,&63,&59,&37,&D1
    DB &8F,&A9,&28,&BA,&30
    DB &70,&62,&EF,&90,&84
    DB &21,&09,&18,&C6,&31
    DB &8B,&A3,&18,&C6,&2A
    DB &24,&63,&18,&D6,&AA
    DB &8C,&54,&45,&46,&31
    DB &8A,&88,&42,&13,&E1
    DB &11,&11,&0F,&9C,&84
    DB &21,&08,&78,&41,&04
    DB &10,&43,&C2,&10,&84
    DB &27,&08,&EA,&90,&84
    DB &20,&00,&00,&00,&00
    DB &32,&51,&C4,&23,&E0
    DB &03,&82,&F8,&BE,&10
    DB &F4,&63,&1F,&00,&0F
    DB &84,&20,&F0,&85,&F1
    DB &8C,&5E,&00,&3A,&3F
    DB &83,&CC,&94,&79,&08
    DB &40,&00,&F8,&C5,&E1
    DB &84,&3D,&18,&C6,&24
    DB &01,&08,&42,&08,&80
    DB &21,&08,&42,&42,&11
    DB &97,&25,&12,&10,&84
    DB &21,&0C,&00,&6A,&B5
    DB &AD,&40,&0F,&46,&31
    DB &88,&00,&E8,&C6,&2E
    DB &00,&3D,&18,&FA,&00
    DB &03,&E3,&17,&84,&00
    DB &B6,&61,&08,&00,&0F
    DB &83,&83,&E2,&11,&E4
    DB &21,&06,&00,&46,&31
    DB &8B,&C0,&08,&C6,&2A
    DB &20,&01,&18,&C6,&AA
    DB &00,&22,&A2,&2A,&20
    DB &04,&63,&17,&84,&00
    DB &F8,&88,&8F,&88,&84
    DB &41,&08,&22,&10,&84
    DB &21,&08,&82,&10,&44
    DB &22,&0A,&A0,&00,&00
    DB &07,&82,&D4,&B4,&3E
    DB &00,&00,&0F,&7B,&C0
    DB &F7,&BC,&00,&00,&C8
    DB &74,&7F,&07,&80

;    DB "AW,BG"

;          DS 0FFFFH-$,0


;          SEND COMPUTER1
;          END &8000     ;dummy value
