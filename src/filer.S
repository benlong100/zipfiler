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
* START
*--------------------------------------
START        jsr   DISPINIT
             jsr   TOVOLUMES

MAINLOOP     jsr   DRAWSCREEN
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   KEYCHR
             cmp   #$8b             ; up arrow
             beq   :up
             cmp   #$8a             ; down arrow
             beq   :down
             cmp   #$8d             ; RET: go in
             beq   :enter
             cmp   #$88             ; left arrow: go up a level
             beq   :parent
             cmp   #$9b             ; ESC: back to ProDOS
             beq   :quit
             jmp   :key

:up          lda   CURSEL
             beq   :key             ; already at the top
             dec   CURSEL
             lda   CURSEL
             cmp   LTOP
             bcs   MAINLOOP
             dec   LTOP
             jmp   MAINLOOP

:down        lda   CURSEL
             clc
             adc   #$01
             cmp   LCOUNT
             bcs   :key             ; already at the end
             sta   CURSEL
             sec
             sbc   LTOP
             cmp   #PANELROWS
             bcc   MAINLOOP
             inc   LTOP
             jmp   MAINLOOP

:quit        jsr   MLI
             dfb   $65
             da    QUITPARM
             rts                    ; the MLI quit does not come back

*--- RET. From the volume list that means entering a volume; from a directory
*    it means entering a subdirectory, and nothing at all on a file.
:enter       lda   LCOUNT
             bne   *+5              ; nothing to enter
             jmp   :key
             lda   INVOL
             beq   :subdir
             jsr   PATHVOL
             jmp   :read
:subdir      ldx   CURSEL
             lda   LTYPE,x
             cmp   #$0f             ; a directory, and only a directory
             beq   *+5
             jmp   :key
             jsr   PATHDOWN
:read        jsr   DIRSCAN
             bcs   :err
             lda   #$00
             sta   INVOL
             sta   CURSEL
             sta   LTOP
             jmp   MAINLOOP
:err         jsr   TOVOLUMES        ; unreadable: fall back to the list
             jmp   MAINLOOP

*--- Left arrow. Up out of a directory, and up out of a volume root is the
*    list of volumes -- which is what makes the volume picker not a command.
:parent      lda   INVOL
             beq   *+5              ; already as far out as there is
             jmp   :key
             jsr   PATHUP
             bcs   :tovol           ; was a volume root
             jsr   DIRSCAN
             bcs   :tovol
             lda   #$00
             sta   CURSEL
             sta   LTOP
             jmp   MAINLOOP
:tovol       jsr   TOVOLUMES
             jmp   MAINLOOP

QUITPARM     dfb   $04
             dfb   $00
             da    $0000
             dfb   $00
             da    $0000

*--------------------------------------
* TOVOLUMES -- show the list of online volumes
*--------------------------------------
TOVOLUMES    jsr   VOLSCAN
             lda   #$01
             sta   INVOL
             lda   #$00
             sta   CURSEL
             sta   LTOP
             rts

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
* DRAWPATHS -- where each panel is, the focused one marked
*--------------------------------------
DRAWPATHS    jsr   CLRBUF
             jsr   PANELBAR
             lda   #$be             ; '>' marks the panel with focus
             sta   LINEBUF
             lda   INVOL
             beq   :path
             lda   #<VOLTXT
             ldy   #>VOLTXT
             jsr   SETSTR
             ldx   #$01
             jsr   BUFSTR
             jmp   :draw
*--- the length is the INDEX of the last character, not one past it, so the
*    test belongs after the copy or the last letter goes missing
:path        lda   PATHBUF
             beq   :draw
             ldx   #$01
             ldy   #$01
:copy        lda   PATHBUF,y
             ora   #$80
             sta   LINEBUF,x
             inx
             cpx   #LWIDTH
             bcs   :draw
             iny
             cpy   PATHBUF
             bcc   :copy
             beq   :copy
:draw        lda   #PATHROW
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
             lda   LTOP
             clc
             adc   ROWN
             sta   ENTI
             cmp   LCOUNT
             bcs   :put             ; past the end: leave the row blank
             jsr   FMTLEFT
             lda   ENTI
             cmp   CURSEL
             bne   :put
             jsr   INVLEFT          ; the cursor line
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
* FMTLEFT -- entry ENTI into LINEBUF
*
* The columns docs/design.md counted: 0 tag, 1 lock, 2-16 name, 18-20 type,
* 22-26 blocks.
*--------------------------------------
FMTLEFT      jsr   ENTPTRN
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
             beq   :type
             ldx   #$02
:copy        iny
             lda   (NAMPTR),y
             ora   #$80             ; held low ASCII, drawn high
             sta   LINEBUF,x
             inx
             dec   TMPB
             bne   :copy

:type        ldx   ENTI
             lda   LTYPE,x
             ldx   #$12
             jsr   TYPESTR

*--- locked is the write-enable bit of the access byte, clear
             ldx   ENTI
             lda   LACCESS,x
             and   #$02
             bne   :blocks
             lda   #$aa             ; '*', the same mark CATALOG uses
             sta   LINEBUF+1

:blocks      lda   INVOL
             bne   :done            ; a volume's size is not in this list
             ldx   ENTI
             lda   LBLKLO,x
             sta   NUMLO
             lda   LBLKHI,x
             sta   NUMHI
             lda   #$16             ; column 22
             sta   TMPA
             jsr   PUTNUM
:done        rts

*--------------------------------------
* ENTPTRN -- NAMPTR = the name of entry ENTI
*
* The name block is 4K, so this cannot be an index register.
*--------------------------------------
ENTPTRN      lda   ENTI
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
             lda   LCOUNT
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
             ldx   #$05
             jsr   BUFSTR
             jsr   INVBUF           ; the hint row is chrome, so inverse
             lda   #HINTROW
             jmp   DRAWLINE

VOLTXT       asc   "(volumes)"
             dfb   $00
ENTTXT       asc   "entries"
             dfb   $00
HINTTXT      asc   "ARROWS move   RET open   LEFT up a level   ESC quit"
             dfb   $00

*--- mutable storage
             dum   $1400
ROWN         ds    1                ; which panel row is being drawn
LCOUNT       ds    1                ; entries the left panel has read
IDX          ds    1                ; scratch counter
CURSEL       ds    1                ; the entry the cursor is on
ENTI         ds    1                ; the entry being drawn
LTOP         ds    1                ; first entry visible
ENTN         ds    1                ; entries left in this directory block
INVOL        ds    1                ; non-zero when showing the volume list
NUMLO        ds    1                ; PUTNUM's value
NUMHI        ds    1
DIG          ds    1
LEADZ        ds    1
             dend

*--- The rest emit code, and $2000 belongs to START.
             put   screen
             put   prodos
             put   catalog
