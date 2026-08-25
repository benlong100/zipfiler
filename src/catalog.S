*--------------------------------------
* CATALOG.S -- what a panel has read, and how it is held
*
* Parallel arrays rather than records: names in a block of 16-byte stride,
* everything else in an array of its own. Indexing a 16-byte stride is a
* shift rather than a multiply, and nothing is padded. See design.md §4.
*
* Names are held as ProDOS gives them -- plain, low ASCII -- because that is
* what has to go back into a pathname. Bit 7 goes on at the screen.
*
* Every routine here works on whichever panel SELPANEL last chose, so none of
* it is written twice.
*--------------------------------------
MAXENT       equ   255              ; per panel, and a count that fits a byte

*--------------------------------------
* SELPANEL -- A = 0 or 1. Point the working pointers at that panel.
*
* Also aims the MLI open at that panel's pathname, so a scan reads the path
* belonging to the panel it is filling.
*--------------------------------------
SELPANEL     sta   PANSEL
             tax
             lda   PANBASE,x
             sta   PNAMES
             sta   PTYPE
             sta   PBLKLO
             sta   PBLKHI
             sta   PACC
             lda   PANBASE+2,x
             sta   PNAMES+1
             clc
             adc   #>OFFTYPE
             sta   PTYPE+1
             clc
             adc   #$01
             sta   PBLKLO+1
             clc
             adc   #$01
             sta   PBLKHI+1
             clc
             adc   #$01
             sta   PACC+1

*--- and the path this panel is showing
             lda   PATHLO,x
             sta   OPENPARM+1
             sta   PATHPTR
             lda   PATHHI,x
             sta   OPENPARM+2
             sta   PATHPTR+1
             rts

PANBASE      dfb   <PAN0,<PAN1
             dfb   >PAN0,>PAN1
PATHLO       dfb   <PATH0,<PATH1
PATHHI       dfb   >PATH0,>PATH1

*--------------------------------------
* NAMEAT -- NAMPTR = the name of entry A in the chosen panel
*--------------------------------------
NAMEAT       sta   TMPA
             lda   #$00
             sta   TMPC
             ldx   #$04
:shift       asl   TMPA
             rol   TMPC
             dex
             bne   :shift
             lda   TMPA
             clc
             adc   PNAMES
             sta   NAMPTR
             lda   TMPC
             adc   PNAMES+1
             sta   NAMPTR+1
             rts

*--------------------------------------
* VOLSCAN -- fill the chosen panel from the list of online volumes
*
* The volume list is what "up from a root" reaches, so it is a listing like
* any other and goes in the same arrays.
*
* An ONLBUF answer and a cached name have the same shape -- a length byte
* then the characters -- so pointing at both and using one index copies one
* into the other with nothing to adjust.
*--------------------------------------
VOLSCAN      jsr   ONLINEF
             ldx   PANSEL
             lda   #$00
             sta   PCOUNT,x
             sta   IDX

:each        lda   IDX
             asl                    ; each answer is sixteen bytes
             asl
             asl
             asl
             clc
             adc   #<ONLBUF
             sta   ENTPTR
             lda   #>ONLBUF
             adc   #$00
             sta   ENTPTR+1

             ldy   #$00
             lda   (ENTPTR),y
             and   #$0f             ; the name length; zero is a device that
             beq   :next            ; could not be read, so it is not listed
             sta   TMPB

             ldx   PANSEL
             lda   PCOUNT,x
             jsr   NAMEAT
             lda   TMPB
             ldy   #$00
             sta   (NAMPTR),y
:copy        iny
             lda   (ENTPTR),y
             sta   (NAMPTR),y
             cpy   TMPB
             bcc   :copy

*--- a volume is not a file: no type of its own, and nothing to unlock
             ldx   PANSEL
             ldy   PCOUNT,x
             lda   #TYPVOL
             sta   (PTYPE),y
             lda   #$02             ; write-enable set, so it draws unlocked
             sta   (PACC),y
             lda   #$00
             sta   (PBLKLO),y
             sta   (PBLKHI),y
             inc   PCOUNT,x

:next        inc   IDX
             lda   IDX
             cmp   #16
             bcc   :each
             rts

*--------------------------------------
* DIRSCAN -- read the directory named by the chosen panel's path
*
* Carry set and MLIERR meaningful if it could not be read.
*--------------------------------------
DIRSCAN      ldx   PANSEL
             lda   #$00
             sta   PCOUNT,x
             jsr   OPENF
             bcs   :fail
             lda   OPENREF
             sta   READREF
             sta   CLOSEREF

:block       jsr   READF
             bcs   :done            ; end of file arrives as an error, and
             lda   XFERCNT          ; means only that there are no more
             ora   XFERCNT+1
             beq   :done

*--- past the four link bytes, thirteen entries of thirty-nine
             lda   #<DIRBUF+4
             sta   ENTPTR
             lda   #>DIRBUF+4
             sta   ENTPTR+1
             lda   #$0d
             sta   ENTN

:entry       ldy   #$00
             lda   (ENTPTR),y
             beq   :next            ; never used, or since deleted
             lsr
             lsr
             lsr
             lsr                    ; the storage type
             cmp   #$0e
             bcs   :next            ; $E and $F are the directory's own header
             jsr   TAKEENT
             ldx   PANSEL
             lda   PCOUNT,x
             cmp   #MAXENT
             bcs   :shut            ; the cap in design.md section 4

:next        lda   ENTPTR
             clc
             adc   #$27             ; thirty-nine bytes on
             sta   ENTPTR
             bcc   :n2
             inc   ENTPTR+1
:n2          dec   ENTN
             bne   :entry
             jmp   :block

:shut        jsr   CLOSEF
             clc
             rts
:done        jsr   CLOSEF
             clc
             rts
:fail        sec
             rts

*--------------------------------------
* TAKEENT -- the entry at ENTPTR into the arrays, at the panel's count
*--------------------------------------
TAKEENT      ldx   PANSEL
             lda   PCOUNT,x
             jsr   NAMEAT

*--- the name, length first
             ldy   #$00
             lda   (ENTPTR),y
             and   #$0f
             sta   TMPB
             sta   (NAMPTR),y
:copy        iny
             lda   (ENTPTR),y
             sta   (NAMPTR),y
             cpy   TMPB
             bcc   :copy

*--- and the three other things a listing shows
             ldx   PANSEL
             ldy   PCOUNT,x
             lda   #$10             ; file type
             sta   TMPA
             jsr   ENTBYTE
             sta   (PTYPE),y
             lda   #$13             ; blocks used, low
             sta   TMPA
             jsr   ENTBYTE
             sta   (PBLKLO),y
             lda   #$14
             sta   TMPA
             jsr   ENTBYTE
             sta   (PBLKHI),y
             lda   #$1e             ; access; bit 1 is write-enable
             sta   TMPA
             jsr   ENTBYTE
             sta   (PACC),y
             ldx   PANSEL
             inc   PCOUNT,x
             rts

*--- A = the byte at offset TMPA of the entry, Y preserved
ENTBYTE      sty   TMPC
             ldy   TMPA
             lda   (ENTPTR),y
             ldy   TMPC
             rts

*--------------------------------------
* Building a path
*
* A path is a length byte, then the characters, low ASCII. A name is a length
* byte then the characters too -- so aiming the destination pointer one byte
* before where the name is to land lets one index walk both.
*--------------------------------------

*--- PATHVOL -- the panel's path = "/" + the name under its cursor
PATHVOL      ldx   PANSEL
             lda   PCURSEL,x
             jsr   NAMEAT
             lda   PATHPTR          ; the slash sits at path[1], so the name
             clc                    ; starts at path[2] == (PDST),1
             adc   #$01
             sta   PDST
             lda   PATHPTR+1
             adc   #$00
             sta   PDST+1
             jsr   APPNAME
             lda   TMPB
             clc
             adc   #$01             ; the name and the slash
             ldy   #$00
             sta   (PATHPTR),y
             rts

*--- PATHDOWN -- append "/" and the name under the cursor
PATHDOWN     ldx   PANSEL
             lda   PCURSEL,x
             jsr   NAMEAT
             ldy   #$00
             lda   (PATHPTR),y      ; what is already there
             sta   TMPA
             clc
             adc   PATHPTR
             sta   PDST
             lda   PATHPTR+1
             adc   #$00
             sta   PDST+1
             inc   PDST             ; the slash goes one past the end
             bne   :go
             inc   PDST+1
:go          jsr   APPNAME
             lda   TMPA
             sec                    ; the old length, the name, and the slash
             adc   TMPB
             ldy   #$00
             sta   (PATHPTR),y
             rts

*--- APPNAME -- "/" at (PDST),0 and the name from NAMPTR after it. TMPB = the
*    name length on return.
APPNAME      ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
             lda   #$2f             ; '/', low ASCII: a path is not screen
             sta   (PDST),y
:copy        iny
             lda   (NAMPTR),y
             sta   (PDST),y
             cpy   TMPB
             bcc   :copy
             rts

*--------------------------------------
* PATHUP -- drop the last component of the panel's path
*
* Carry set if there was nothing left to drop, which means the path was a
* volume root: above that is the list of volumes, and the caller goes there.
*--------------------------------------
PATHUP       ldy   #$00
             lda   (PATHPTR),y
             beq   :top
             tay
:scan        lda   (PATHPTR),y
             cmp   #$2f             ; '/'
             beq   :found
             dey
             bne   :scan
:top         sec
             rts
:found       cpy   #$01
             beq   :top             ; "/VOLUME" -- above it is the volume list
             dey
             tya
             ldy   #$00
             sta   (PATHPTR),y
             clc
             rts

*--------------------------------------
* Per-panel state. The arrays themselves are at PAN0 and PAN1.
*--------------------------------------
             dum   $1480
PANSEL       ds    1                ; the panel SELPANEL last chose
PCOUNT       ds    2                ; entries read, per panel
PCURSEL      ds    2                ; where each cursor is
PTOP         ds    2                ; first entry visible in each
PINVOL       ds    2                ; non-zero while showing the volume list
IDX          ds    1
ENTN         ds    1
             dend

             dum   $1500
PATH0        ds    65               ; length byte then up to 64 characters
PATH1        ds    65
             dend
