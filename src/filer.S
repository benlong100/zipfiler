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
             jsr   VOLSCAN
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
* DRAWENTRIES -- the panel rows, from what the panel has read
*--------------------------------------
DRAWENTRIES  lda   #$00
             sta   ROWN
:row         jsr   CLRBUF
             jsr   PANELBAR
             lda   ROWN
             cmp   LCOUNT
             bcs   :put             ; past the end of the listing: blank row
             jsr   FMTLEFT
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
* FMTLEFT -- entry ROWN of the left panel into LINEBUF
*
* Columns, and they are the ones docs/design.md counted: 0 tag, 1 lock,
* 2-16 name, 18-20 type, 22-26 blocks.
*--------------------------------------
FMTLEFT      jsr   NAMEPTR
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB             ; length
             beq   :type
             ldx   #$02             ; the name starts at column 2
:copy        iny
             lda   (NAMPTR),y
             ora   #$80             ; held low ASCII, drawn high
             sta   LINEBUF,x
             inx
             dec   TMPB
             bne   :copy
:type        ldx   ROWN
             lda   LTYPE,x
             ldx   #$12             ; column 18
             jmp   TYPESTR

*--------------------------------------
* NAMEPTR -- NAMPTR = LNAMES + ROWN * 16
*
* The name block is 4K, so this cannot be an index register.
*--------------------------------------
NAMEPTR      lda   ROWN
             sta   TMPA
             lda   #$00
             sta   TMPC
             ldx   #$04
:shift       asl   TMPA
             rol   TMPC
             dex
             bne   :shift
             lda   TMPA
             clc
             adc   #<LNAMES
             sta   NAMPTR
             lda   TMPC
             adc   #>LNAMES
             sta   NAMPTR+1
             rts

*--------------------------------------
* TYPESTR -- A = ProDOS file type, X = column. Three characters into LINEBUF.
*
* A table of the types worth naming, and hex for everything else, which is
* what a catalogue has always done with a type it does not recognise.
*--------------------------------------
TYPESTR      sta   TMPB
             stx   TMPA
             ldy   #$00
:scan        cpy   #TYPLEN
             bcs   :hex
             lda   TYPTBL,y
             cmp   TMPB
             beq   :found
             iny
             iny
             iny
             iny
             bne   :scan

:found       ldx   TMPA
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             inx
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             inx
             iny
             lda   TYPTBL,y
             sta   LINEBUF,x
             rts

:hex         ldx   TMPA
             lda   #$a4             ; '$'
             sta   LINEBUF,x
             inx
             lda   TMPB
             lsr
             lsr
             lsr
             lsr
             jsr   HEXDIG
             sta   LINEBUF,x
             inx
             lda   TMPB
             and   #$0f
             jsr   HEXDIG
             sta   LINEBUF,x
             rts

*--- A = 0-15 -> the character for it, high ASCII
HEXDIG       cmp   #$0a
             bcc   :digit
             clc
             adc   #$b7             ; 'A' - 10
             rts
:digit       clc
             adc   #$b0             ; '0'
             rts

TYPTBL       dfb   TYPVOL
             asc   "VOL"
             dfb   $04
             asc   "TXT"
             dfb   $06
             asc   "BIN"
             dfb   $0f
             asc   "DIR"
             dfb   $19
             asc   "ADB"
             dfb   $1a
             asc   "AWP"
             dfb   $1b
             asc   "ASP"
             dfb   $fc
             asc   "BAS"
             dfb   $fd
             asc   "VAR"
             dfb   $fe
             asc   "REL"
             dfb   $ff
             asc   "SYS"
TYPLEN       equ   *-TYPTBL

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
* What is on screen above the panels
*--------------------------------------
PATHL        asc   ">(volumes)"
             dfb   $00
PATHR        asc   " "
             dfb   $00

STATTXT      asc   "2 tagged, 17 blocks"
             dfb   $00
HINTTXT      asc   "TAB panel  SPC tag  RET open  C copy  R name  L ock  D el  S wap"
             dfb   $00

*--- mutable storage
             dum   $1400
ROWN         ds    1                ; which panel row is being drawn
LCOUNT       ds    1                ; entries the left panel has read
IDX          ds    1                ; scratch counter
             dend

*--- The display layer last: it emits code, and $2000 belongs to START.
             put   screen
             put   prodos
             put   catalog
