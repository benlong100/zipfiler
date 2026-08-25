*--------------------------------------
* FILER.S -- a two-panel file manager for the Enhanced Apple //e
*
* ProDOS 8 enters a SYS file at $2000. See docs/design.md.
*
* At the moment one panel works and it is read-only: the list of online
* volumes, a directory read from any of them, arrow keys to move and RET to
* go in. The second panel, tagging and everything destructive are still to
* come.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   FILER.SYSTEM

*--- equates emit nothing, so they are safe here. The rest emit CODE, and
*    ProDOS enters a SYS file at $2000 -- so they are PUT at the end, after
*    the entry point, or the machine jumps straight into the display layer.
             put   equates

*--------------------------------------
* START -- both panels open on the list of volumes
*--------------------------------------
START        jsr   DISPINIT
             lda   #$00
             sta   PANEL
             lda   #$01
             jsr   SELPANEL
             jsr   TOVOLUMES
             lda   #$00
             jsr   SELPANEL
             jsr   TOVOLUMES

MAINLOOP     jsr   DRAWSCREEN
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             jsr   FOCUS            ; every command acts on the focused panel
             lda   KEYCHR
             cmp   #$8b             ; up arrow
             beq   :tup
             cmp   #$8a             ; down arrow
             beq   :tdown
             cmp   #$8d             ; RET: go in
             beq   :tenter
             cmp   #$88             ; left arrow: up a level
             beq   :tparent
             cmp   #$89             ; TAB: the other panel
             beq   :ttab
             cmp   #$d3             ; S, either case: swap the panels
             beq   :tswap
             cmp   #$f3
             beq   :tswap
             cmp   #$9b             ; ESC: back to ProDOS
             beq   :tquit
             jmp   :key

*--- the handlers are further off than a branch reaches
:tup         jmp   :up
:tdown       jmp   :down
:tenter      jmp   :enter
:tparent     jmp   :parent
:ttab        jmp   :tab
:tswap       jmp   :swap
:tquit       jmp   :quit

:tab         lda   PANEL
             eor   #$01
             sta   PANEL
             jmp   MAINLOOP

:up          ldx   PANSEL
             lda   PCURSEL,x
             bne   *+5              ; already at the top
             jmp   :key
             dec   PCURSEL,x
             lda   PCURSEL,x
             cmp   PTOP,x
             bcc   *+5
             jmp   MAINLOOP
             dec   PTOP,x
             jmp   MAINLOOP

:down        ldx   PANSEL
             lda   PCURSEL,x
             clc
             adc   #$01
             cmp   PCOUNT,x
             bcc   *+5              ; already at the end
             jmp   :key
             sta   PCURSEL,x
             sec
             sbc   PTOP,x
             cmp   #PANELROWS
             bcs   *+5
             jmp   MAINLOOP
             inc   PTOP,x
             jmp   MAINLOOP

:quit        jsr   MLI
             dfb   $65
             da    QUITPARM
             rts                    ; the MLI quit does not come back

*--- RET. From the volume list that means entering a volume; from a directory
*    it means entering a subdirectory, and nothing at all on a file.
:enter       ldx   PANSEL
             lda   PCOUNT,x
             bne   *+5
             jmp   :key
             lda   PINVOL,x
             beq   :subdir
             jsr   PATHVOL
             jmp   :read
:subdir      ldy   PCURSEL,x
             lda   (PTYPE),y
             cmp   #$0f             ; a directory, and only a directory
             beq   *+5
             jmp   :key
             jsr   PATHDOWN
:read        jsr   DIRSCAN
             bcs   :fell
             ldx   PANSEL
             lda   #$00
             sta   PINVOL,x
             sta   PCURSEL,x
             sta   PTOP,x
             jmp   MAINLOOP
:fell        jsr   TOVOLUMES        ; unreadable: fall back to the list
             jmp   MAINLOOP

*--- Left arrow. Up out of a directory, and up out of a volume root is the
*    list of volumes -- which is what makes the volume picker not a command.
:parent      ldx   PANSEL
             lda   PINVOL,x
             beq   *+5              ; already as far out as there is
             jmp   :key
             jsr   PATHUP
             bcs   :fell
             jsr   DIRSCAN
             bcs   :fell
             ldx   PANSEL
             lda   #$00
             sta   PCURSEL,x
             sta   PTOP,x
             jmp   MAINLOOP

*--- S. Exchange the two panels, which is how anything is copied right to
*    left: the direction of a copy is fixed, so the panels move instead.
:swap        ldy   #$00
:sw          lda   PATH0,y
             tax
             lda   PATH1,y
             sta   PATH0,y
             txa
             sta   PATH1,y
             iny
             cpy   #65
             bcc   :sw
             lda   PINVOL
             ldx   PINVOL+1
             sta   PINVOL+1
             stx   PINVOL
             lda   #$00
             jsr   SELPANEL
             jsr   RESCAN
             lda   #$01
             jsr   SELPANEL
             jsr   RESCAN
             lda   #$00
             sta   PCURSEL
             sta   PCURSEL+1
             sta   PTOP
             sta   PTOP+1
             jmp   MAINLOOP

QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* TOVOLUMES -- the chosen panel shows the list of online volumes
*--------------------------------------
TOVOLUMES    jsr   VOLSCAN
             ldx   PANSEL
             lda   #$01
             sta   PINVOL,x
             lda   #$00
             sta   PCURSEL,x
             sta   PTOP,x
             rts

*--------------------------------------
* FOCUS -- point the working pointers at the panel that has focus
*--------------------------------------
FOCUS        lda   PANEL
             jmp   SELPANEL

*--------------------------------------
* RESCAN -- read the chosen panel again, whichever listing it is showing
*--------------------------------------
RESCAN       ldx   PANSEL
             lda   PINVOL,x
             beq   :dir
             jmp   VOLSCAN
:dir         jmp   DIRSCAN

*--------------------------------------
* DRAWSCREEN -- the whole layout
*--------------------------------------
DRAWSCREEN   jsr   DRAWPATHS
             jsr   DRAWRULE
             jsr   DRAWENTRIES
             jsr   DRAWSTATUS
             jsr   DRAWHINTS
             jmp   FOCUS            ; leave the pointers where the keys expect

*--------------------------------------
* DRAWPATHS -- where each panel is, the focused one marked
*--------------------------------------
DRAWPATHS    jsr   CLRBUF
             jsr   PANELBAR
             lda   #$00
             jsr   SELPANEL
             lda   #$00
             sta   FCOL
             lda   #LWIDTH
             sta   FWIDTH
             jsr   ONEPATH
             lda   #$01
             jsr   SELPANEL
             lda   #RCOL
             sta   FCOL
             lda   #RWIDTH
             sta   FWIDTH
             jsr   ONEPATH
             lda   #PATHROW
             jmp   DRAWLINE

ONEPATH      lda   FCOL
             clc
             adc   FWIDTH
             sta   TMPC             ; one past this panel's last column
             ldx   FCOL
             lda   PANSEL
             cmp   PANEL
             bne   :nomark
             lda   #$be             ; '>' marks the panel with focus
             sta   LINEBUF,x
:nomark      inx
             ldy   PANSEL
             lda   PINVOL,y
             beq   :path
             lda   #<VOLTXT
             ldy   #>VOLTXT
             jsr   SETSTR
             jmp   BUFSTR
:path        ldy   #$00
             lda   (PATHPTR),y
             beq   :done
             sta   TMPB
             ldy   #$01
:copy        lda   (PATHPTR),y
             ora   #$80
             sta   LINEBUF,x
             inx
             cpx   TMPC
             bcs   :done            ; clipped at this panel's edge
             cpy   TMPB
             bcs   :done
             iny
             bne   :copy
:done        rts

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
* DRAWENTRIES -- one row of both panels at a time
*--------------------------------------
DRAWENTRIES  lda   #$00
             sta   ROWN
:row         jsr   CLRBUF
             jsr   PANELBAR
             lda   #$00
             jsr   SELPANEL
             lda   #$00
             sta   FCOL
             lda   #LWIDTH
             sta   FWIDTH
             jsr   ONEENTRY
             lda   #$01
             jsr   SELPANEL
             lda   #RCOL
             sta   FCOL
             lda   #RWIDTH
             sta   FWIDTH
             jsr   ONEENTRY
             lda   ROWN
             clc
             adc   #TOPROW
             jsr   DRAWLINE
             inc   ROWN
             lda   ROWN
             cmp   #PANELROWS
             bcc   :row
             rts

ONEENTRY     ldx   PANSEL
             lda   PTOP,x
             clc
             adc   ROWN
             sta   ENTI
             cmp   PCOUNT,x
             bcs   :none            ; past the end: leave the row blank
             jsr   FMTPANEL
             lda   PANSEL           ; only the focused panel shows a cursor
             cmp   PANEL
             bne   :none
             ldx   PANSEL
             lda   ENTI
             cmp   PCURSEL,x
             bne   :none
             jsr   INVPANEL
:none        rts

*--------------------------------------
* FMTPANEL -- entry ENTI of the chosen panel into LINEBUF
*
* The columns docs/design.md counted, offset by where the panel starts:
* 0 tag, 1 lock, 2-16 name, 18-20 type, 22-26 blocks.
*--------------------------------------
FMTPANEL     lda   ENTI
             jsr   NAMEAT
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
             beq   :type
             lda   FCOL
             clc
             adc   #$02
             tax
:copy        iny
             lda   (NAMPTR),y
             ora   #$80             ; held low ASCII, drawn high
             sta   LINEBUF,x
             inx
             cpy   TMPB
             bcc   :copy

:type        ldy   ENTI
             lda   (PTYPE),y
             sta   TMPC
             lda   FCOL
             clc
             adc   #$12
             tax
             lda   TMPC
             jsr   TYPESTR

*--- locked is the access byte's write-enable bit, clear
             ldy   ENTI
             lda   (PACC),y
             and   #$02
             bne   :blocks
             lda   FCOL
             clc
             adc   #$01
             tax
             lda   #$aa             ; '*', the same mark CATALOG uses
             sta   LINEBUF,x

:blocks      ldx   PANSEL
             lda   PINVOL,x
             bne   :done            ; a volume has no size in this listing
             ldy   ENTI
             lda   (PBLKLO),y
             sta   NUMLO
             lda   (PBLKHI),y
             sta   NUMHI
             lda   FCOL
             clc
             adc   #$16
             sta   TMPA
             jsr   PUTNUM
:done        rts

*--------------------------------------
* PUTNUM -- NUMLO/NUMHI right aligned in five columns from TMPA
*--------------------------------------
PUTNUM       lda   #$00
             sta   LEADZ
             ldy   #$00
:power       lda   #$00
             sta   DIG
:sub         lda   NUMLO
             sec
             sbc   POWLO,y
             tax
             lda   NUMHI
             sbc   POWHI,y
             bcc   :emit
             stx   NUMLO
             sta   NUMHI
             inc   DIG
             jmp   :sub
:emit        lda   DIG
             bne   :show
             lda   LEADZ
             bne   :show
             cpy   #$04             ; the units digit shows even as a zero
             beq   :show
             lda   #CHSPACE
             bne   :put             ; always taken
:show        lda   #$01
             sta   LEADZ
             lda   DIG
             clc
             adc   #$b0
:put         ldx   TMPA
             sta   LINEBUF,x
             inc   TMPA
             iny
             cpy   #$05
             bcc   :power
             rts

POWLO        dfb   $10,$e8,$64,$0a,$01
POWHI        dfb   $27,$03,$00,$00,$00

*--------------------------------------
* TYPESTR -- A = ProDOS file type, X = column. Three characters into LINEBUF.
*
* A table of the types worth naming, and hex for the rest, which is what a
* catalogue has always done with a type it does not recognise.
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
             ldx   PANEL            ; the focused panel is the one described
             lda   PCOUNT,x
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   #<ENTTXT
             ldy   #>ENTTXT
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
             lda   #STATROW
             jmp   DRAWLINE

DRAWHINTS    jsr   CLRBUF
             lda   #<HINTTXT
             ldy   #>HINTTXT
             jsr   SETSTR
             jsr   CENTRE
             jsr   BUFSTR
             jsr   INVBUF           ; the hint row is chrome, so inverse
             lda   #HINTROW
             jmp   DRAWLINE

VOLTXT       asc   "(volumes)"
             dfb   $00
ENTTXT       asc   "entries"
             dfb   $00
HINTTXT      asc   "ARROWS move   TAB panel   RET open   LEFT up   S wap   ESC quit"
             dfb   $00

*--- mutable storage
             dum   $1400
ROWN         ds    1                ; which panel row is being drawn
ENTI         ds    1                ; the entry being drawn
FCOL         ds    1                ; the column that panel starts at
FWIDTH       ds    1                ; and how wide it is
PANEL        ds    1                ; which panel has focus
NUMLO        ds    1                ; PUTNUM's value
NUMHI        ds    1
DIG          ds    1
LEADZ        ds    1
             dend

*--- The rest emit code, and $2000 belongs to START.
             put   screen
             put   prodos
             put   catalog
