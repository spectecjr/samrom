# SAM Coupé ROM 3.0 — Constants Reference

Every constant defined with `EQU` in the ROM source, grouped by the file that
defines it. Only six files define constants; all other source files consume
them. Values are given in hexadecimal (`&`-prefixed, as in the source) and
decimal where useful.

| File | What it defines |
|---|---|
| [main.asm](#mainasm) | ROM page-select constants used with the paging ports |
| [vars.asm](#varsasm) | The entire system-variable map, buffer addresses, token codes, DOS hook codes, disc controller ports, save/load header offsets, and hardware I/O ports |
| [fpcmain.asm](#fpcmainasm) | The floating-point calculator (FPC) operation codes — the "instruction set" of the RST &28 calculator |
| [text.asm](#textasm) | Error-message compression codes (indexes into `COMPLIST`) |
| [miscx1.asm](#miscx1asm) | Lengths of ROM1 routine bodies that are copied into RAM buffers before execution |
| [miscx2.asm](#miscx2asm) | More copied-routine lengths (DEF KEYCODE, READ, DEF FN, tokenizer, MERGE) |

---

## main.asm

| Constant | Value | Description |
|---|---|---|
| `PAGE0` | 0 | RAM page 0 |
| `PAGE1` | 1 | RAM page 1 |
| `PAGE1F` | &1F | Page number 31 — written to port 250 (LRPORT) to select the system page in section B with ROM0 enabled |

---

## vars.asm

vars.asm contains no code: it is the memory map of the interpreter. All
"system variables" are `EQU` definitions. `VAR2` = **&5A00** is the base of the
main system-variable block (it must start on a page boundary).

### Editor / device configuration block (initialised from `CHIT` table)

| Constant | Value | Description |
|---|---|---|
| `VAR2` | &5A00 | Base of system variables (page-aligned) |
| `LNCUR` | VAR2+&00 | Current-line cursor character (usually `>`) |
| `KURCHAR` | VAR2+&01 | (2 bytes) Cursor characters — lower-case / upper-case |
| `BIN1DIG` | VAR2+&03 | Digit used by BIN$ for 1 (usually `1`) |
| `BIN0DIG` | VAR2+&04 | Digit used by BIN$ for 0 (usually `0`) |
| `INSTHASH` | VAR2+&05 | INSTR wildcard character, normally `#` |
| `PSLD` | VAR2+&06 | (2) Device letter/number (number = tape speed / disc number / net station) |
| `SPEEDINK` | VAR2+&08 | Ink flash counter reload value |
| `LINIPTR` | VAR2+&09 | (2) Pointer to line-interrupt palette-change table |
| `XCMDP` | VAR2+&0B | (3) Page/address of first external command list, or FFxxxx |
| `PRRHS` | VAR2+&0E | Printer right-hand-side limit (79) |
| `AFTERCR` | VAR2+&0F | &0A or NUL — whether auto line-feed needed after CR |
| `LPTPRT1` | VAR2+&10 | (2) Printer control port / strobe value (rest of block reserved for DUMP) |
| `TABVAR` | VAR2+&2F | 0 if TAB=16, else TAB=8 |
| `M23LSC` | VAR2+&30 | (2) Mode 2/3 lower-screen colours |
| `SOFE` | VAR2+&32 | Screen-off enable/disable flag (0=on) |
| `TPROMPTS` | VAR2+&33 | Bit 0: suppress printed names during LOAD; bit 1: suppress prompts during SAVE |

### Screen/print variables (saved with a switched-out screen)

| Constant | Value | Description |
|---|---|---|
| `BGFLG` | VAR2+&34 | Block graphics flag |
| `FL6OR8` | VAR2+&35 | 0 = 6-bit chars in MODE 2, NZ = 8-bit |
| `CSIZE` | VAR2+&36 | (2) Character height/width |
| `UWRHS` | VAR2+&38 | Upper window RHS (starts at 31) |
| `UWLHS` | VAR2+&39 | Upper window LHS (starts 0) |
| `UWTOP` | VAR2+&3A | Upper window top (starts 0) |
| `UWBOT` | VAR2+&3B | Upper window bottom (starts 18) |
| `LWRHS` | VAR2+&3C | Lower window RHS |
| `LWLHS` | VAR2+&3D | Lower window LHS |
| `LWTOP` | VAR2+&3E | Lower window top |
| `LWBOT` | VAR2+&3F | Lower window bottom (starts 20) |
| `MODE` | VAR2+&40 | Current screen mode 0–3 |
| `YCOORD` | VAR2+&41 | Graphics Y position, 0–191, 0 at top |
| `XCOORD` | VAR2+&42 | (2) Graphics X position 0–255 (fat) or 0–511 (thin) |
| `RLINE` | = XCOORD | Alias used by ROLL |
| `THFATP` | VAR2+&44 | 0 = thin pixels, NZ = fat (permanent) |
| `ATTRP` | VAR2+&45 | Attribute used by modes 0 and 1 (permanent) |
| `MASKP` | VAR2+&46 | Attribute mask (permanent) |
| `PFLAGP` | VAR2+&47 | Bit 4 = PAPER 9, bit 6 = INK 9 (permanent) |
| `M23PAPP` | VAR2+&48 | Mode 2/3 paper byte (permanent) |
| `M23INKP` | VAR2+&49 | Mode 2/3 ink byte (permanent, must precede OVERP) |
| `OVERP` | VAR2+&4A | OVER state 0–1 (permanent) |
| `INVERP` | VAR2+&4B | 00/FF = normal/inverse (permanent) |
| `GOVERP` | VAR2+&4C | Graphics over mode 0–3: normal, XOR, OR, AND (used by PUT) |
| `THFATT` | VAR2+&4D | Temporary copy of THFATP (forced fat outside MODE 2) |
| `ATTRT` | VAR2+&4E | Temporary attribute |
| `MASKT` | VAR2+&4F | Temporary mask |
| `PFLAGT` | VAR2+&50 | Temporary print flags |
| `M23PAPT` | VAR2+&51 | Temporary mode 2/3 paper |
| `M23INKT` | VAR2+&52 | Temporary mode 2/3 ink |
| `OVERT` | VAR2+&53 | Temporary OVER |
| `INVERT` | VAR2+&54 | Temporary inverse |
| `GOVERT` | VAR2+&55 | Temporary graphics-over |
| `WINDRHS` | VAR2+&56 | Current window RHS (temp) |
| `WINDLHS` | VAR2+&57 | Current window LHS |
| `WINDTOP` | VAR2+&58 | Current window top |
| `WINDBOT` | VAR2+&59 | Current window bottom |
| `WINDMAX` | VAR2+&5A | (2) Upper window lowest bottom / max RHS |
| `ORGOFF` | VAR2+&5C | Graphics origin offset |
| `LSOFF` | VAR2+&5D | Lower screen bit offset |
| `SPOSNU` | VAR2+&6C | (2) Upper screen print position |
| `SPOSNL` | VAR2+&6E | (2) Lower screen print position |

### Interpreter state

| Constant | Value | Description |
|---|---|---|
| `PRPOSN` | VAR2+&70 | (2) Printer position |
| `OPCHAR` | VAR2+&72 | Current output char (LPRINT) |
| `DEVICE` | VAR2+&73 | 0=upper screen, 1=lower screen, 2=printer… |
| `CLET` | VAR2+&74 | Current channel letter (K/S/P/B/T/$ etc.) |
| `IFTYPE` | VAR2+&75 | Long/short IF flag |
| `REFFLG` | VAR2+&76 | Z if a REF variable being worked on (also: NZ = FN used in line, for compiler) |
| `CURDISP` | VAR2+&77 | Current display number |
| `CUSCRNP` | VAR2+&78 | Current screen page (includes mode bits) |
| `CURP` | VAR2+&79 | Current upper RAM port value |
| `CLRP` | VAR2+&7A | Current lower RAM port (temp store during paging) |
| `CSA` | VAR2+&7B | (2) Current statement address |
| `FIRST` | VAR2+&7D | (2) First line number for LIST x TO y (also array slicer) |
| `LAST` | VAR2+&7F | (2) Last line number for LIST x TO y (also array slicer) |

### Memory-area pointers (page byte + 16-bit address; adjusted by MAKEROOM/RECLAIM)

Each is a page number (`…P`) immediately followed by a 16-bit address in the
&8000–&BFFF range. They must stay in this order:

| Page var | Addr var | Value | Points to |
|---|---|---|---|
| `SAVARSP` | `SAVARS` | VAR2+&81/&82 | String/array variables area |
| `NUMENDP` | `NUMEND` | VAR2+&84/&85 | End of numeric variables |
| `NVARSP` | `NVARS` | VAR2+&87/&88 | Numeric variables area (= end of program) |
| `DATADDP` | `DATADD` | VAR2+&8A/&8B | DATA list read pointer |
| `WKENDP` | `WKEND` | VAR2+&8D/&8E | End of work space |
| `WORKSPP` | `WORKSP` | VAR2+&90/&91 | Work space |
| `ELINEP` | `ELINE` | VAR2+&93/&94 | Edit line |
| `CHADP` | `CHAD` | VAR2+&96/&97 | Interpretation pointer (current character) |
| `KCURP` | `KCUR` | VAR2+&99/&9A | Editor cursor position |
| `NXTLINEP` | `NXTLINE` | VAR2+&9C/&9D | Address of next program line |
| `PROGP` | `PROG` | VAR2+&9F/&A0 | Start of BASIC program |
| `XPTRP` | `XPTR` | VAR2+&A2/&A3 | Syntax-error position marker (`?`) |
| `DESTP` | `DEST` | VAR2+&A5/&A6 | Assignment destination |
| `PRPTRP` | `PRPTR` | VAR2+&A8/&A9 | PROC pointer (call-site parameter list) |
| `DPPTRP` | `DPPTR` | VAR2+&AB/&AC | DEF PROC pointer (not adjusted) |
| `CLAPG` | `CLA` | VAR2+&AE/&AF | Current line address (not adjusted) |

### Miscellaneous flags and stores

| Constant | Value | Description |
|---|---|---|
| `DFTFB` | VAR2+&B1 | DEFAULT flag byte |
| `STRNO` | VAR2+&B2 | Current stream number |
| `LDCO` | VAR2+&B3 | LOAD ZX code offset (pages) |
| `OPSTORE` | VAR2+&B5 | (2) Output-address store (control-code handling) |
| `DMPFG` | VAR2+&B7 | NZ = print output dumped (discarded) |
| `LISTFLG` | VAR2+&B8 | 0/1/2 = LIST FORMAT 0/1/2 (pretty-listing indent) |
| `LSTFT` | VAR2+&B9 | Temporary LISTFLG used by channel "R" |
| `INQUFG` | VAR2+&BA | In-quotes flag: bit 0 = 1 inside quotes (tokens not expanded) |
| `SPROMPT` | VAR2+&BB | NZ = no "scroll?" prompts |
| `OLDSPCS` | VAR2+&BC | Space status of previous listed line |
| `INDOPFG` | VAR2+&BD | Indented output flag |
| `NXTSPCS` | VAR2+&BE | Next-line leading spaces (list indenting) |
| `CURSPCS` | VAR2+&BF | Current-line leading spaces |
| `NXTHSPCS` | VAR2+&C0 | Next-line half spaces |
| `CURTHSPCS` | VAR2+&C1 | Current-line half spaces |
| `KPOS` | VAR2+&C2 | (2) Cursor screen position |
| `SOFFCT` | VAR2+&C4 | Screen-off counter (next 4 must stay in order) |
| `SOFLG` | VAR2+&C5 | NZ = screen has been turned off |
| `SPEEDIC` | VAR2+&C6 | Flashing-ink counter |
| `PALFLAG` | VAR2+&C7 | Bit 0 shows which palette table is in use |
| `TEMPW1`–`TEMPW3` | VAR2+&C8/&CA/&CC | (2 each) Temporary words |
| `TEMPB1`–`TEMPB3` | VAR2+&CE/&CF/&D0 | Temporary bytes (TEMPB3 = final FILL param / CALL param count) |
| `LASTSTAT` | VAR2+&D1 | STATPORT value on last interrupt |
| `SPSTORE` | VAR2+&D2 | (2) SP store, exclusive to interrupts |
| `JVSP` | VAR2+&D5 | (2) JSVIN SP store |
| `NMISP` | VAR2+&D7 | (2) NMI SP store |
| `NMILRP` | VAR2+&D9 | LRPORT value when NMI occurred |

### Vector table (all 2 bytes each)

`VECTBS` (= VAR2+&DA) is the base. Setting a vector non-zero diverts the
corresponding ROM routine.

| Vector | Value | Hooked function |
|---|---|---|
| `DMPV` | VAR2+&DA | DUMP command |
| `SETIYV` | VAR2+&DC | Interrupt IY setup |
| `PRTOKV` | VAR2+&DE | Print-token |
| `NMIV` | VAR2+&E0 | NMI (normally super-break) |
| `FRAMIV` | VAR2+&E2 | Frame interrupt |
| `LINIV` | VAR2+&E4 | Line interrupt |
| `COMSV` | VAR2+&E6 | Communications interrupt |
| `MIPV` | VAR2+&E8 | Main input |
| `MOPV` | VAR2+&EA | Main output |
| `EDITV` | VAR2+&EC | Editor entry |
| `RST8V` | VAR2+&EE | RST &08 (error) |
| `RST28V` | VAR2+&F0 | RST &28 (FP calculator) |
| `RST30V` | VAR2+&F2 | RST &30 called from outside ROM0 |
| `CMDV` | VAR2+&F4 | Command dispatch (add new commands) |
| `EVALUV` | VAR2+&F6 | Function evaluation (add new functions) |
| `LPRTV` | VAR2+&F8 | LPRINT output |
| `MTOKV` | VAR2+&FA | Tokenizer extension (extra keyword matching) |
| `MOUSV` | VAR2+&FC | Mouse read |
| `KURV` | VAR2+&FE | Cursor |

### Print expansion tables and compiler/error state

| Constant | Value | Description |
|---|---|---|
| `CEXTAB` | VAR2+&0100 | (32) Colour-applied expansion table (mode 2/3 printing) |
| `EXTAB` | VAR2+&0120 | (32) 16 words of mode-3 nibble→word expansion (or 16 bytes of mode-2 doubled data) |
| `COMPFLG` | VAR2+&0140 | Flag bits used by label/FN/PROC compiler (bit 7 = whole program needs compiling) |
| `BREAKDI` | VAR2+&0141 | NZ = BREAK between statements disabled |
| `ERRSTAT` | VAR2+&0142 | Statement number for ON ERROR |
| `ERRLN` | VAR2+&0143 | (2) Line to GOTO on error |
| `ONERRFLG` | VAR2+&0145 | Bit 7 = temporary ON ERROR, bit 0 = permanent |
| `ONSTORE` | VAR2+&0146 | ON command's statement number |
| `BCSTORE` | VAR2+&0147 | (2) BC store used by RST &30 |
| `M3PAPP` | VAR2+&0149 | (2) Mode 3 paper (saved across mode 2) |
| `M3LSC` | VAR2+&014B | (2) Mode 3 lower-screen colours |
| `TEMPW4`/`TEMPW5` | VAR2+&014D/&014F | (2 each) Used by POINTERS |
| `LPT` | VAR2+&0152 | (30) Line-pointer table: one byte per screen line, FF if a line number starts there |
| `ANYIV` | VAR2+&0170 | (2) "Any interrupt" vector |
| `RNSTKE` | VAR2+&0172 | (2) Rename stack pointer (parameter processing) |
| `CURCMD` | VAR2+&0174 | Token code of command being executed |
| `LTDFF` | VAR2+&0175 | LET/DEFAULT flag |
| `STRM16NM` | VAR2+&0176 | (11) Type/length byte + name of the variable that stream 16 writes to |
| `GRARF` | VAR2+&0181 | Graphics record flag (0=off) |
| `DHADJ` | VAR2+&0182 | Double-height adjust |
| `PAGCOUNT` | VAR2+&0183 | Page counter used by FARLDIR |
| `MODCOUNT` | VAR2+&0184 | (2) Mod-16K counter used by FARLDIR |
| `BCREG` | VAR2+&0186 | (2) The FP calculator's B register (BREG) |
| `AUTOFLG` | VAR2+&0188 | AUTO mode on/off |
| `AUTOSTEP` | VAR2+&0189 | (2) AUTO step (alias `RSTEP` = RENUM step) |
| `LSPTR` | VAR2+&018B | (2) Line scan pointer |
| `LNPTR` | VAR2+&018D | Screen line holding the `>` cursor (>&3F = none) |
| `MSEDP` | VAR2+&018E | (8) Mouse driver data |
| `BUTSTAT` | VAR2+&018F | Mouse button status |
| `MXCRD` | VAR2+&0196 | (2) Mouse X coordinate |
| `MYCRD` | VAR2+&0198 | (2) Mouse Y coordinate |

### PRINTFP (number formatting) workspace

| Constant | Value | Description |
|---|---|---|
| `FRACLIM` | VAR2+&019A | Fraction digit limit |
| `NPRPOS` | VAR2+&019B | (2) Number print position |
| `DIGITS` | VAR2+&019D | Digit count (these four must stay in order) |
| `EPOWER` | VAR2+&019E | Exponent power |
| `DECPNTED` | VAR2+&019F | Decimal point emitted flag |
| `PRNBUFF` | VAR2+&01A0 | (16) Number print buffer |
| `BCDBUFF` | VAR2+&01B0 | (5) BCD conversion buffer |

### Save/load & DOS state

| Constant | Value | Description |
|---|---|---|
| `OTHER` | VAR2+&01B5 | Net destination station number |
| `DCT` | VAR2+&01B6 | Disc error counter |
| `SLDEV` | VAR2+&01B7 | (2) Temporary device letter/number |
| `OVERF` | VAR2+&01B9 | SAVE OVER flag (0 = save over allowed) |
| `INSLV` | VAR2+&01BA | (2) (Unused insert-line vector) |
| `STRLOCN` | VAR2+&01BC | (2) Used by LOOKVARS — location of found string |
| `TVDATA` | VAR2+&01BE | (2) Control-code parameter store |
| `DOSER` | VAR2+&01C0 | (2) Jump vector after DOS execution |
| `DOSFLG` | VAR2+&01C2 | Z if no DOS loaded, else DOS page |
| `DOSCNT` | VAR2+&01C3 | Bit 0 set if DOS in control |
| `BSTKEND` | VAR2+&01C4 | (2) BASIC (DO/GOSUB/PROC) stack end |

### Init block (26 bytes initialised from `MAIT` table)

| Constant | Value | Description |
|---|---|---|
| `BASSTK` | VAR2+&01C6 | (2) BASIC stack base |
| `HEAPEND` | VAR2+&01C8 | (2) Heap end |
| `HPST` | VAR2+&01CA | (2) Heap start |
| `FPSBOT` | VAR2+&01CC | (2) Bottom of FP calculator stack |
| `DKDEF` | VAR2+&01CE | (2) DEF KEY definitions start |
| `DKLIM` | VAR2+&01D0 | (2) DEF KEY buffer growth limit |
| `PATOUT` | VAR2+&01D2 | (2) Address of "printable chars" output routine |
| `ERRMSGS` | VAR2+&01D4 | (2) Error message table address |
| `UMSGS` | VAR2+&01D6 | (2) Utility message table address |
| `KBTAB` | VAR2+&01D8 | (2) Keyboard table address |
| `CMDADDRT` | VAR2+&01DA | (2) Command address table (in ROM1) |
| `MNOP` | VAR2+&01DC | (2) Main output routine address |
| `MNIP` | VAR2+&01DE | (2) Main input routine address |
| `PAGER` | VAR2+&01E0 | (14) Reserved for paging subroutine |
| `KBUFF` | VAR2+&01EE | (18) Two 72-bit keyboard state tables |

### ZX-compatible system variables (&5C00 block)

| Constant | Value | Description |
|---|---|---|
| `LHM1` | &5C00 | Used by KEYSCAN as LASTH-1 (LASTH = &5C01 = last key hit) |
| `KDATA` | &5C02 | Control-code store during colour-parameter input |
| `LKPB` | &5C03 | (2) Last keyboard state |
| `REPCT` | &5C05 | Repeat counter |
| `LASTKV` | &5C06 | (2) Last key vector |
| `LASTK` | &5C08 | Key from buffer queue head |
| `REPDEL` | &5C09 | Repeat delay |
| `REPPER` | &5C0A | Repeat period |
| `STREAMS` | &5C10 | (42) Stream displacements for streams −5 to 15 (16 maps to −4; table physically at &5C0C–&5C35) |
| `CHARS` | &5C36 | (2) Character set pointer (address − 256) |
| `RASP` | &5C38 | Warning buzz length |
| `PIP` | &5C39 | Key-click length |
| `ERRNR` | &5C3A | Error number (0 = OK) |
| `FLAGS` | &5C3B | Main flags: bit 7 = running (vs syntax check), bit 6 = numeric result, bit 5 = new key, bit 0 = leading space suppressed |
| `TVFLAG` | &5C3C | TV flags: bit 5 = clear lower screen on keystroke, bit 4 = autolist, bit 3 = print edit line to lower screen |
| `ERRSP` | &5C3D | (2) Error stack pointer |
| `LISTSP` | &5C3F | (2) SP for aborting AUTOLIST at screen end |
| `NEWPPC` | &5C42 | (2) Line number to jump to |
| `NSPPC` | &5C44 | Statement to jump to (&FF = no jump pending) |
| `PPC` | &5C45 | (2) Current line number |
| `SUBPPC` | &5C47 | Current statement number within line |
| `BORDCR` | &5C48 | Lower-screen attributes in modes 1/2 |
| `EPPC` | &5C49 | (2) Current edit line number (cursor `>` line) |
| `BORDCOL` | &5C4B | Border port value |
| `CHANS` | &5C4F | (2) Channels area pointer |
| `CURCHL` | &5C51 | (2) Current channel pointer |
| `DEFADDP`/`DEFADD` | &5C53/&5C54 | Page/address of DEF FN parameter bracket during FN evaluation (0 = none) |
| `NLASTH` | &5C56 | (3) New last-key data |
| `ZIPLIB` | &5C61 | (2) Reserved for Simon N. Goodwin's ZIP compiler |
| `ZIPTEMP` | &5C63 | (2) ZIP compiler temp |
| `STKEND` | &5C65 | (2) End of FP calculator stack (first free byte) |
| `KPFLG` | &5C67 | Keypad flag: even = function keys, odd = number pad |
| `MEM` | &5C68 | (2) Calculator memory-area pointer |
| `FLAGS2` | &5C6A | Bit 3 = caps lock, bit 0 = screen not clear |
| `SDTOP` | &5C6C | (2) Line number at top of AUTOLIST screen |
| `OLDPPC` | &5C6E | (2) Line for CONTINUE |
| `OSPPC` | &5C70 | Statement for CONTINUE |
| `FLAGX` | &5C71 | Bit 5 = INPUT mode, bit 0 = variable doesn't exist yet |
| `STRLEN` | &5C72 | (2) String length in assignments |
| `SEED` | &5C76 | (2) RND seed |
| `FRAMES` | &5C78 | (3) Frame counter |
| `UDG` | &5C7B | (2) User-defined graphics pointer |
| `HUDG` | &5C7D | (2) High UDG pointer |
| `FRAMES34` | &5C7F | (2) Frames bytes 3–4 (5-byte frame counter) |
| `OLDPOS` | &5C82 | Previous print position |
| `SCRCT` | &5C8C | Scroll count (lines before "scroll?" prompt) |
| `KBQB` | &5C8D | (8) Keyboard queue |
| `KBQP` | &5C95 | (2) Keyboard queue pointers (low = end, high = head) |
| `SCPTR` | &5C9D | (2) Address of current screen in SCLIST |
| `FISCRNP` | &5C9F | Page of screen 1 (not cleared by NEW, from here on) |
| `SCLIST` | &5CA0 | (16) Screens list: mode/page of screens 1–16, or &FF |
| `LASTPAGE` | &5CB0 | Last page reserved by BASIC |
| `RAMTOPP`/`RAMTOP` | &5CB1/&5CB2 | Page/address of RAMTOP |
| `PRAMTP` | &5CB4 | Last physical page present in machine |

### Token codes and keyword count

| Constant | Value | Description |
|---|---|---|
| `KEYWNO` | &C4 (196) | Number of words in the keyword table |
| `TSPEED` | 112 | Default tape speed |
| `PITOK` | &3B | PI function token (first function code) |
| `PI` | &21 (PITOK−&1A) | PI's internal evaluator code (tokens are stored −&1A internally) |
| `INSTOK` | &4A | INSTR token — separates numeric from string immediate functions |
| `INSTR` | &30 (INSTOK−&1A) | INSTR internal code |
| `FNTOK` | &42 | FN function token |
| `BINTOK` | &43 | BIN function token (also recognised by CALC5BY for binary literals) |
| `SCRNTOK` | &4C | SCREEN$ token (used by SAVE/LOAD) |
| `SINTOK` | &53 | SIN token (first FPC-handled function) |
| `INTOK` | &60 | IN token |
| `CODETOK` | &6C | CODE token (used by SAVE/LOAD) |
| `CHRSTOK` | &70 | CHR$ token (used by COPY) |
| `MODTOK` | &7A | MOD token (first alphabetic binary operator) |
| `ANDTOK` | &80 | AND token |
| `USINGTOK` | &85 | USING qualifier token (first single-byte token) |
| `ATTOK` | &87 | AT |
| `TABTOK` | &88 | TAB |
| `WHILETOK` | &8A | WHILE |
| `UNTILTOK` | &8B | UNTIL |
| `LINETOK` | &8C | LINE |
| `THENTOK` | &8D | THEN |
| `TOTOK` | &8E | TO |
| `STEPTOK` | &8F | STEP |
| `SAVETOK` | &94 | SAVE command token |
| `LOADTOK` | &95 | LOAD |
| `MERGETOK` | &96 | MERGE |
| `VERIFYTOK` | &97 | VERIFY |

(Commented out in source: `FORMATTOK`=&91, `ERASETOK`=&92, `RECORDTOK`=&EF.)

### DOS hook codes (invoked via `RST &08` with code ≥ 128)

| Constant | Value | Description |
|---|---|---|
| `BTHK` | 128 | DOS boot (DOS can ignore, or treat as ALHK) |
| `FOPHK` | 129 | DOS open (get header) |
| `LDHK` | 130 | DOS load |
| `VFYHK` | 131 | DOS verify |
| `SVHK` | 132 | DOS save |
| `OSHK` | 134 | DOS open stream |
| `CSHK` | 135 | DOS close stream |
| `ALHK` | 136 | DOS load auto-load file (follows BOOT) |
| `DIRHK` | 137 | DOS directory |
| `DVHK` | 139 | DOS DVAR |
| `EOFHK` | 140 | DOS EOF |
| `PTRHK` | 141 | DOS PTR |
| `PATHHK` | 142 | DOS PATH$ |

### Disc controller (WD1772) ports and commands

| Constant | Value | Description |
|---|---|---|
| `COMM` | 224 | Command/status port |
| `TRCK` | 225 | Track port |
| `SECT` | 226 | Sector port |
| `DTRQ` | 227 | Data port |
| `DRES` | 9 | Restore command |
| `STPIN` | &59 | Step-in command |
| `STPOUT` | &79 | Step-out command |
| `DRSEC` | &80 | Read-sector command |

### Save/load header offsets

| Constant | Value | Description |
|---|---|---|
| `HFG` | 15 | Displacement to header flag |
| `HDT` | 26 | Displacement to header date/time |
| `HDN` | 31 | Displacement to header numbers |
| `HDRL` | 80 (&50) | Header buffer length |
| `NMLEN` | 10 | Max file name length |
| `YOSDISP` | 57 | Displacement of YOS (Y offset) system pseudo-variable |
| `YRGDISP` | 67 | Displacement of YRG (Y range) |
| `XOSDISP` | 77 | Displacement of XOS |
| `XRGDISP` | 87 | Displacement of XRG |
| `RSBUFF` | &E003 | ROM-load save buffer |
| `SBO` | &8000 | Section B origin |
| `SBN` | &C000 | Section C origin |

### Fixed buffer addresses (system page, section A when paged at &4000)

| Constant | Value | Description |
|---|---|---|
| `HPEND` | &4000 | Heap end |
| `BSTACK` | &4AFF | BASIC (DO/LOOP/PROC/GOSUB) stack base (grows down) |
| `HDR` | &4B00 | Save header buffer (&50 bytes; also PARPRO rename stack) |
| `HDL` | &4B50 | Loaded header buffer |
| `INTSTK` | &4C00 | Interrupt stack (uses down to ~&49EE) |
| `BUFF256` | &4C00 | 256-byte buffer (page aligned) |
| `FPSB` | &4D00 | Bottom of FP calculator stack |
| `CDBUFF` | &4D00 | Code buffer for generated multi-LDI/RLD code (max &181 bytes; the RAM tokenizer also runs at CDBUFF+&80) |
| `ISPVAL` | &4F00 | Initial SP value |
| `INSTBUF` | &4F00 | Buffer for code copied from ROM1, etc. (&200 bytes) |
| `MSGBUFF` | INSTBUF+&1C0 | Message assembly buffer |
| `FILBUFF` | &5080 | File buffer |
| `ALLOCT` | &5100 | Page allocation table (32 bytes, 1 per page, + terminator; page aligned) |
| `MEMVAL` | &5121 | Memory test value |
| `TLBYTE` | &513F | Type/length byte of variable name being looked up |
| `NMBUFF` | &5140 | Variable/FN/PROC name buffer (alias `FIRLET` = first letter) |
| `NMISTK` | &5188 | NMI stack |
| `SCRNBUF` | &5188 | 8 bytes used by SCREEN$ for compressed form |
| `CHARSVAL` | &5190 | Expanded character set (copied from compressed CHARSRC) |
| `PALTAB` | &55D8 | Working palette table |
| `LINICOLS` | &5600 | Line-interrupt colour table |
| `DKBU` | &5800 | DEF KEY buffer |
| `KTAB` | &58E0 | Keyboard map |
| `PVBUFF` | &FEB0 | Print vars of the non-displayed screen (in second screen page) |
| `FILLSTK` | = PVBUFF | FILL command stack |
| `PALBUF` | &FFD8 | Palette of non-displayed screen |

### Hardware I/O ports

| Constant | Value | Description |
|---|---|---|
| `SNDPORT` | &FF | Sound chip (address reg at &1FF, data at &FF) |
| `KEYPORT` | &FE | Keyboard |
| `MDIPORT` | &FD | MIDI |
| `VIDPORT` | &FC | Video mode/page |
| `URPORT` | &FB | Upper RAM page select (section C/D) |
| `LRPORT` | &FA | Lower RAM page select (section A/B) + ROM0/ROM1 enable bits |
| `STATPORT` | &F9 | Status/line-interrupt |
| `CLUTPORT` | &F8 | Palette (colour look-up table) |

---

## fpcmain.asm

These are the operation codes of the floating-point calculator — the byte
codes that follow `RST &28` (`DB CALC` … `DB EXIT`) in calculator literals.
See [tokenized-program-format.md](tokenized-program-format.md) for how the
calculator is driven.

### Binary operations (&00–&1F)

| Constant | Value | Operation |
|---|---|---|
| `MULT` | &00 | Multiply |
| `ADDN` | &01 | Add (numeric) |
| `CONCAT` | &02 | String concatenation |
| `SUBN` | &03 | Subtract |
| `POWER` | &04 | Raise to power |
| `DIVN` | &05 | Divide |
| `SWOP` | &06 | Swap top two stack entries |
| `DROP` | &07 | Drop top entry |
| `MOD` | &08 | Modulo |
| `IDIV` | &09 | Integer divide (DIV) |
| `NUOR` | &0D | Numeric OR |
| `NUAND` | &0E | Numeric AND |
| `NNOTE` | &0F | Numeric <> |
| `NLESE` | &10 | Numeric <= |
| `NGRTE` | &11 | Numeric >= |
| `NLESS` | &12 | Numeric < |
| `NEQUAL` | &13 | Numeric = |
| `NGRTR` | &14 | Numeric > |
| `SAND` | &15 | String AND (string vs number) |
| `SNOTE` | &16 | String <> |
| `SLESE` | &17 | String <= |
| `SGRTE` | &18 | String >= |
| `SLESS` | &19 | String < |
| `SEQUAL` | &1A | String = |
| `SGRTR` | &1B | String > |
| `SWOP13` | &1C | Swap 1st and 3rd stack entries |
| `SWOP23` | &1D | Swap 2nd and 3rd stack entries |
| `JPTRUE` | &1E | Jump (following displacement byte) if true |
| `JPFALSE` | &1F | Jump if false |

(Codes &0A–&0C are the gap between IDIV and NUOR: unused.)

### Control / stack manipulation (&20–&34)

| Constant | Value | Operation |
|---|---|---|
| `JUMP` | &20 | Unconditional jump (displacement byte follows) |
| `LDBREG` | &21 | Load BREG from following byte |
| `DECB` | &22 | Decrement BREG, jump if not zero (displacement follows) |
| `STKBREG` | &23 | Stack BREG as a number |
| `USEB` | &24 | Execute operation code held in BREG |
| `DUP` | &25 | Duplicate top entry |
| `ONELIT` | &26 | Stack 1-byte literal (sign-extended small integer) |
| `FIVELIT` | &27 | Stack 5-byte literal (follows inline) |
| `SOMELIT` | &28 | Stack several literals (count byte follows) |
| `LKADDRB` | &29 | Look up address, byte displacement |
| `LKADDRW` | &2A | Look up address, word displacement |
| `REDARG` | &2B | Reduce argument (trig range reduction) |
| `LESS0` | &2C | True if < 0 |
| `LESE0` | &2D | True if <= 0 |
| `GRTR0` | &2E | True if > 0 |
| `GRTE0` | &2F | True if >= 0 |
| `TRUNC` | &30 | Truncate to integer |
| `RESTACK` | &31 | Re-stack (normalise to 5-byte FP form) |
| `POWR2` | &32 | Power of 2 |
| `EXIT` | &33 | Leave calculator |
| `EXIT2` | &34 | Leave calculator (alternate) |

### Functions (&39–&5D) — dispatched from expression evaluator codes

| Constant | Value | Function |
|---|---|---|
| `SIN` | &39 | Sine |
| `COS` | &3A | Cosine |
| `TAN` | &3B | Tangent |
| `ASN` | &3C | Arcsine |
| `ACS` | &3D | Arccosine |
| `ATN` | &3E | Arctangent |
| `LOGN` | &3F | Natural log (LN) |
| `EXP` | &40 | Exponential |
| `ABS` | &41 | Absolute value |
| `SGN` | &42 | Sign |
| `SQR` | &43 | Square root |
| `INT` | &44 | Integer (floor) |
| `INP` | &46 | IN (port read) |
| `PEEK` | &47 | PEEK |
| `EOF` | &4C | EOF |
| `UDGA` | &4F | UDG address |
| `LEN` | &51 | String length |
| `CODE` | &52 | First-character code |
| `VALS` | &53 | VAL$ |
| `VAL` | &54 | VAL |
| `CHRS` | &56 | CHR$ |
| `STRS` | &57 | STR$ |
| `INKEY` | &5B | INKEY$ |
| `NOT` | &5C | Logical NOT |
| `NEGATE` | &5D | Unary minus |

### Calculator-literal prefix codes (&C8–&FF ranges)

| Constant | Value | Operation |
|---|---|---|
| `CALC` | &EF | The `RST &28` opcode value — `DB CALC` starts an inline calculator program |
| `STOD0`–`STOD4` | &C8–&CC | Store top of stack to memory slot 0–4 and drop |
| `STO0`–`STO5` | &D0–&D5 | Store top of stack to memory slot 0–5 (keep) |
| `RCL0`–`RCL5` | &D8–&DD | Recall memory slot 0–5 onto the stack |
| `STKHALF` | &E0 | Stack constant 0.5 |
| `STKZERO` | &E1 | Stack constant 0 |
| `STK16K` | &E2 | Stack constant 16384 |
| `STKFONE` | &E6 | Stack constant 1 in full FP form |
| `STKONE` | &E9 | Stack constant 1 |
| `STKTEN` | &EC | Stack constant 10 |
| `STKHALFPI` | &F0 | Stack constant π/2 |

---

## text.asm

Error messages are compressed: codes 0–31 in a message expand to a common
word/fragment from `COMPLIST`. These constants are the fragment indexes
(each fragment shown with its exact text, including significant leading /
trailing spaces).

| Constant | Value | Expansion text |
|---|---|---|
| `INVALID` | 0 | `Invalid ` |
| `WITHOUT` | 1 | ` without ` |
| `MISSING` | 2 | `Missing ` |
| `TOO` | 3 | ` too ` |
| `ISALREDOP` | 4 | ` is already open` |
| `PALET` | 5 | `palette ` |
| `SOFS` | 6 | ` of ` |
| `ERROR` | 7 | ` error` |
| `TREAM` | 8 | `tream` |
| `UMBER` | 9 | `umber` |
| `CNXT` | 10 | `NEXT` |
| `NO` | 11 | `No ` |
| `BREAK` | 12 | `BREAK ` |
| `CREEN` | 13 | `creen` |
| `ARRAY` | 14 | ` array: ` |
| `NOTE` | 15 | `Note` |
| `LONG` | 16 | `long` |
| `SNOTS` | 17 | ` not ` |
| `SNAME` | 18 | ` name` |
| `STRING` | 19 | `String` |
| `TOOMANY` | 20 | `Too many ` |
| `TATEMENT` | 21 | `tatement` |
| `CSTOP` | 22 | `STOP ` |
| `FILE` | 23 | `file` |
| `CLOUR` | 24 | `colour` |
| `CIN` | 25 | `in` |
| `CPROC` | 26 | ` PROC` |
| `CLOOP` | 27 | `LOOP` |
| `CTO` | 28 | `to` |
| `CDE` | 29 | `de` |
| `CME` | 30 | `me` |
| `CAR` | 31 | `ar` |

---

## miscx1.asm

ROM1 cannot be executed while the BASIC program area is paged into section C,
so several command bodies are copied from ROM1 into RAM buffers
(`INSTBUF`/`CDBUFF`) and executed there. These constants are the *lengths* of
those relocatable bodies, computed from their start/end labels; the stubs in
misc2.asm sum them to find each body's source address in ROM1 (they are
assembled consecutively from &C000).

| Constant | Value expression | Body |
|---|---|---|
| `RENLN` | TRANSF+3−RNMP2 | RENUM part 2 |
| `GETLN` | GT4+6−GETP2 | GET |
| `DELLN` | DELFIN+3−DELPT2 | DELETE |
| `KEYLN` | KEYFIN+3−KEYP2 | KEYIN |
| `POPLN` | POP5−POPP2+1 | POP |
| `INPLN` | INPFIN+1−INPP2 | INPUT |

## miscx2.asm

| Constant | Value expression | Body |
|---|---|---|
| `DKLN` | DKFIN+1−DKP2 | DEF KEYCODE |
| `RDLN` | 0 | READ (now executes in place; length retained as 0) |
| `DFNLN` | DFNNS+2−DFNP2 | DEF FN |
| `TOKLN` | TOKFIN+1−TOKPT2 | The tokenizer (runs at CDBUFF+&80) |
| `MELN` | MEEND+1−MEPRO2 | MERGE |

## mult.asm

Defines no constants (a comment mentions `EQU` only in describing DOUBLE
FPFORM's behaviour).

> [!WARNING] AI Generated Documentation
>
> These docs were generated by @spectecjr using AI. They may contain errors,
> but appear to be correct.
