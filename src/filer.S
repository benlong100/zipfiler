*--------------------------------------
* FILER.S -- a two-panel file manager for the Enhanced Apple //e
*
* ProDOS 8 enters a SYS file at $2000. See docs/design.md for what this is
* meant to become; at the moment it draws the layout with fixed content and
* waits for a key, which is enough to prove the toolchain, the 80 column
* screen and the column budget all agree with each other.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   FILER.SYSTEM

*--- equates emit nothing, so they are safe here. screen.S emits CODE, and
*    ProDOS enters a SYS file at $2000 -- so it is PUT at the end, after the
*    entry point, or the machine jumps straight into the display layer.
             put   equates

*--------------------------------------
* START
*--------------------------------------
START        jsr   DISPINIT
             jsr   DRAWSCREEN

*--- wait for a key, then hand back to ProDOS
:wait        lda   KBD
             bpl   :wait
             sta   KBDSTRB
             jsr   MLI
             dfb   $65
             da    QUITPARM
             rts                    ; the MLI quit does not come back

QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* DRAWSCREEN -- the whole layout
*--------------------------------------
DRAWSCREEN   jsr   DRAWPATHS
             jsr   DRAWRULE
             jsr   DRAWENTRIES
             jsr   DRAWSTATUS
             jsr   DRAWHINTS
             rts

*--------------------------------------
* DRAWPATHS -- the two panel paths, the focused one marked
*--------------------------------------
DRAWPATHS    jsr   CLRBUF
             jsr   PANELBAR
             lda   #<PATHL
             ldy   #>PATHL
             jsr   SETSTR
             ldx   #$00
             jsr   BUFSTR
             lda   #<PATHR
             ldy   #>PATHR
             jsr   SETSTR
             ldx   #RCOL
             jsr   BUFSTR
             lda   #PATHROW
             jmp   DRAWLINE

*--------------------------------------
* DRAWRULE -- dashes across, with the divider crossing them
*--------------------------------------
DRAWRULE     lda   #CHDASH
             ldx   #SCRWM1
:loop        sta   LINEBUF,x
             dex
             bpl   :loop
             lda   #CHPLUS
             ldx   #SEPCOL
             sta   LINEBUF,x
             lda   #RULEROW
             jmp   DRAWLINE

*--------------------------------------
* PANELBAR -- the divider in the column between the panels
*--------------------------------------
PANELBAR     lda   #CHBAR
             ldx   #SEPCOL
             sta   LINEBUF,x
             rts

*--------------------------------------
* DRAWENTRIES -- the panel rows
*
* Fixed content for now. ENTL and ENTR are tables of string pointers, ending
* in a zero high byte; a blank row is drawn for every row past the end.
*--------------------------------------
DRAWENTRIES  lda   #$00
             sta   ROWN
:row         jsr   CLRBUF
             jsr   PANELBAR
             lda   ROWN
             asl
             tax
             lda   ROWN
             cmp   #LCOUNT
             bcs   :right           ; past the end of the left list
             lda   ROWN
             asl
             tax
             lda   ENTL+1,x
             pha
             lda   ENTL,x
             ldy   #$00
             sta   STRPTR
             pla
             sta   STRPTR+1
             ldx   #$00
             jsr   BUFSTR
:right       lda   ROWN
             asl
             tax
             lda   ROWN
             cmp   #RCOUNT
             bcs   :put
             lda   ROWN
             asl
             tax
             lda   ENTR+1,x
             pha
             lda   ENTR,x
             sta   STRPTR
             pla
             sta   STRPTR+1
             ldx   #RCOL
             jsr   BUFSTR
:put         lda   ROWN
             clc
             adc   #TOPROW
             jsr   DRAWLINE
             inc   ROWN
             lda   ROWN
             cmp   #PANELROWS
             bcc   :row
             rts

*--------------------------------------
* DRAWSTATUS / DRAWHINTS
*--------------------------------------
DRAWSTATUS   jsr   CLRBUF
             jsr   PANELBAR
             lda   #<STATTXT
             ldy   #>STATTXT
             jsr   SETSTR
             ldx   #$00
             jsr   BUFSTR
             lda   #STATROW
             jmp   DRAWLINE

DRAWHINTS    jsr   CLRBUF
             lda   #<HINTTXT
             ldy   #>HINTTXT
             jsr   SETSTR
             ldx   #$08
             jsr   BUFSTR
             jsr   INVBUF           ; the hint row is chrome, so inverse
             lda   #HINTROW
             jmp   DRAWLINE

*--------------------------------------
* Fixed content, until there is a real catalogue to draw
*--------------------------------------
PATHL        asc   ">/WORK/DOCS"
             dfb   $00
PATHR        asc   " /BACKUP"
             dfb   $00

E1           asc   "> CHAPTER.ONE     TXT    14"
             dfb   $00
E2           asc   "  CHAPTER.TWO     TXT     9"
             dfb   $00
E3           asc   "> NOTES           TXT     3"
             dfb   $00
E4           asc   " *FILER.SYSTEM    SYS    21"
             dfb   $00
E5           asc   "  OLD             DIR     2"
             dfb   $00
E6           asc   "  ARCHIVE         DIR     4"
             dfb   $00
E7           asc   " *README          TXT     2"
             dfb   $00

LCOUNT       equ   5
RCOUNT       equ   2
ENTL         da    E1,E2,E3,E4,E5
ENTR         da    E6,E7

STATTXT      asc   "2 tagged, 17 blocks"
             dfb   $00
HINTTXT      asc   "TAB panel  SPC tag  RET open  C copy  R name  L ock  D el  S wap"
             dfb   $00

*--- mutable storage
             dum   $1400
ROWN         ds    1                ; which panel row is being drawn
             dend

*--- The display layer last: it emits code, and $2000 belongs to START.
             put   screen
