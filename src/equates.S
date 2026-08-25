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
KEYCHR       equ   $18              ; last key read

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

*--- screen codes we draw chrome with ---
CHDASH       equ   $ad              ; '-'
CHPLUS       equ   $ab              ; '+'
CHBAR        equ   $fc              ; '|'
CHSPACE      equ   $a0
