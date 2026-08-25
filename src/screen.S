*--------------------------------------
* SCREEN.S -- the //e's 80 column screen
*
* The //e 80-column screen interleaves banks: even screen columns live in
* auxiliary memory, odd columns in main, both at the same offset from the row
* base. With 80STORE on, $C054/$C055 pick which bank a write to $0400-$07FF
* lands in.
*
* Everything draws through LINEBUF, an 80-byte main-memory line of screen
* codes. Callers fill it, then blit it, so DRAWLINE sets the bank switch twice
* a line instead of twice a character.
*
* Screen codes, with ALTCHARSET on:
*   normal  = ascii | $80          ($A0-$FF)
*   inverse = ascii & $3f          for ascii < $60
*           = ascii                for ascii >= $60 (inverse lowercase)
*--------------------------------------

*--------------------------------------
* DISPINIT -- 80 column text mode, screen cleared
*--------------------------------------
DISPINIT     sta   TXTSET
             sta   MIXCLR
             sta   HIRESOFF
             sta   SET80VID
             sta   SET80STORE
             sta   SETALTCHAR
             jsr   CLRSCRN
             rts

*--------------------------------------
* CLRSCRN -- fill both screen halves with spaces
*--------------------------------------
CLRSCRN      ldx   #$00
:loop        lda   #CHSPACE
             sta   MAINWR
             sta   $0400,x
             sta   $0500,x
             sta   $0600,x
             sta   $0700,x
             lda   #CHSPACE
             sta   AUXWR
             sta   $0400,x
             sta   $0500,x
             sta   $0600,x
             sta   $0700,x
             inx
             bne   :loop
             rts

*--------------------------------------
* SETROW -- A = row (0-23) -> SCRPTR = row base address
*--------------------------------------
SETROW       tax
             lda   ROWLO,x
             sta   SCRPTR
             lda   ROWHI,x
             sta   SCRPTR+1
             rts

*--------------------------------------
* DRAWLINE -- A = row. Blit LINEBUF to the screen.
*
* Two passes: 40 even columns into aux, then 40 odd columns into main. X walks
* LINEBUF two at a time while Y walks the screen offset, so no self-modifying
* code is needed and the code image stays immutable -- which lets a test
* compare emulated RAM against the build artifact byte for byte.
*--------------------------------------
DRAWLINE     jsr   SETROW

             sta   AUXWR            ; even columns -> aux
             ldx   #$00
             ldy   #$00
:l1          lda   LINEBUF,x
             sta   (SCRPTR),y
             inx
             inx
             iny
             cpy   #40
             bne   :l1

             sta   MAINWR           ; odd columns -> main
             ldx   #$01
             ldy   #$00
:l2          lda   LINEBUF,x
             sta   (SCRPTR),y
             inx
             inx
             iny
             cpy   #40
             bne   :l2
             rts

*--------------------------------------
* CLRBUF -- fill LINEBUF with spaces
*--------------------------------------
CLRBUF       lda   #CHSPACE
             ldx   #SCRWM1
:loop        sta   LINEBUF,x
             dex
             bpl   :loop
             rts

*--------------------------------------
* BUFSTR -- copy a null-terminated high-ASCII string into LINEBUF
*   STRPTR -> string, X = starting column. Clips at the right margin.
*--------------------------------------
BUFSTR       ldy   #$00
:loop        lda   (STRPTR),y
             beq   :done
             cpx   #SCRW
             bcs   :done
             sta   LINEBUF,x
             inx
             iny
             bne   :loop
:done        rts

*--------------------------------------
* SETSTR -- STRPTR = the string at A/Y (low/high)
*--------------------------------------
SETSTR       sta   STRPTR
             sty   STRPTR+1
             rts

*--------------------------------------
* INVBUF -- turn the whole of LINEBUF inverse
*
* The alternate character set carries inverse lowercase at $60-$7F, so those
* are already their own inverse form and only the rest need folding down.
*--------------------------------------
INVBUF       ldy   #SCRWM1
:loop        lda   LINEBUF,y
             bpl   :raw             ; MouseText: leave it alone
             and   #$7f
             cmp   #$60
             bcs   :keep            ; inverse lowercase is itself
             and   #$3f
:keep        sta   LINEBUF,y
:raw         dey
             bpl   :loop
             rts

*--------------------------------------
* CENTRE -- X = the column at which the string at STRPTR is centred
*
* Measure the string and halve what is left, rather than hand-counting a
* column into the source: the text can then change without the number under
* it having to.
*--------------------------------------
CENTRE       ldy   #$00
:count       lda   (STRPTR),y
             beq   :mid
             iny
             bne   :count
:mid         tya
             sta   TMPB
             lda   #SCRW
             sec
             sbc   TMPB
             lsr                    ; half of what is left, rounding down
             tax
             rts

*--------------------------------------
* INVPANEL -- turn one panel's columns of LINEBUF inverse
*   FCOL = where it starts, FWIDTH = how many
*--------------------------------------
INVPANEL     ldx   FCOL
             ldy   FWIDTH
:loop        lda   LINEBUF,x
             bpl   :raw             ; MouseText: leave it alone
             and   #$7f
             cmp   #$60
             bcs   :keep            ; inverse lowercase is itself
             and   #$3f
:keep        sta   LINEBUF,x
:raw         inx
             dey
             bne   :loop
             rts

*--------------------------------------
* Row base addresses. The 24 text rows are not contiguous.
*--------------------------------------
ROWLO        dfb   $00,$80,$00,$80,$00,$80,$00,$80
             dfb   $28,$a8,$28,$a8,$28,$a8,$28,$a8
             dfb   $50,$d0,$50,$d0,$50,$d0,$50,$d0
ROWHI        dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07
             dfb   $04,$04,$05,$05,$06,$06,$07,$07

*--- mutable storage, declared but not emitted. Keeping writable data out of
*    the code image means emulated RAM at $2000 stays byte-identical to the
*    build artifact for as long as the program runs.
             dum   $0200
LINEBUF      ds    SCRW             ; one screen line of screen codes
             dend
