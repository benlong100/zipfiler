*--------------------------------------
* EQUATES.S -- hardware, ProDOS, zero page and the screen geometry
*
* Emits no code; included first so everything below can reference it.
*--------------------------------------

*--- soft switches (write to set, unless noted) ---
SET80STORE   equ   $c001            ; PAGE2 then selects the screen half
SET80VID     equ   $c00d            ; 80 column video
SETALTCHAR   equ   $c00f            ; alt charset: MouseText + inverse lower
MAINWR       equ   $c054            ; PAGE2 off -> screen writes to MAIN
AUXWR        equ   $c055            ; PAGE2 on  -> screen writes to AUX
TXTSET       equ   $c051
MIXCLR       equ   $c052
HIRESOFF     equ   $c056

*--- keyboard (read) ---
KBD          equ   $c000            ; bit 7 set when a key is waiting
KBDSTRB      equ   $c010
OPNAPPLE     equ   $c061            ; bit 7 = Open-Apple held

*--- ProDOS 8 ---
MLI          equ   $bf00

*--- zero page ---
SCRPTR       equ   $06              ; 2 bytes, current screen row base
STRPTR       equ   $08              ; 2 bytes, string source
TMPA         equ   $0a
TMPB         equ   $0b
NAMPTR       equ   $0c              ; 2 bytes, into the 4K name block
TMPC         equ   $0e
KEYCHR       equ   $0f              ; last key read
ENTPTR       equ   $10              ; 2 bytes, walking a directory block

*--- The arrays of whichever panel is being read or drawn. SELPANEL points
*    them at one panel or the other, so every routine below can be written
*    once and used by both.
PNAMES       equ   $12              ; 2 bytes each
PTYPE        equ   $14
PBLKLO       equ   $16
PBLKHI       equ   $18
PACC         equ   $1a
PDST         equ   $1c              ; 2 bytes, where a path is being built
PATHPTR      equ   $1e              ; 2 bytes, the chosen panel's path
PTAGS        equ   $20              ; 2 bytes, the chosen panel's tag bitmap

*--- The screen. Fixed at 80 columns: unlike the editor there is no 40 column
*    machine to support, so the geometry is a set of equates rather than a
*    record filled in at startup.
SCRW         equ   80
SCRWM1       equ   79
LWIDTH       equ   39               ; left panel
SEPCOL       equ   39               ; the divider
RCOL         equ   40               ; right panel starts here
RWIDTH       equ   40

PATHROW      equ   0                ; the two paths
RULEROW      equ   1
TOPROW       equ   2                ; first entry row
PANELROWS    equ   20               ; entries visible at once
STATROW      equ   22               ; tagged count, errors, progress
HINTROW      equ   23

*--- A volume is not a file and has no ProDOS file type. $00 is "typeless"
*    and effectively unused by real files, so it serves as the marker.
TYPVOL       equ   $00

*--- Where each panel keeps what it has read. 5,120 bytes apiece: 4K of names
*    at a 16-byte stride, then a 256-byte array for each of the other four
*    things a listing shows. See docs/design.md section 4.
PAN0         equ   $5000
PAN1         equ   $6400
PANSIZE      equ   $1400
OFFTYPE      equ   $1000            ; from a panel's base
OFFBLKLO     equ   $1100
OFFBLKHI     equ   $1200
OFFACC       equ   $1300

*--- A tag is a bit, so a panel's worth is 32 bytes. See design.md section 6.
TAGS0        equ   $1600
TAGS1        equ   $1620

*--- screen codes we draw chrome with ---
CHDASH       equ   $ad              ; '-'
CHPLUS       equ   $ab              ; '+'
CHBAR        equ   $fc              ; '|'
CHSPACE      equ   $a0
