*--------------------------------------
* CATALOG.S -- what a panel has read, and how it is held
*
* Parallel arrays rather than records: names in a block of 16-byte stride,
* everything else in an array of its own. Indexing a 16-byte stride is a
* shift rather than a multiply, a tag costs a bit rather than a byte, and
* nothing is padded. See docs/design.md section 4.
*
* Names are held as ProDOS gives them -- plain, low ASCII -- because that is
* what has to go back into a pathname. Bit 7 is set on the way to the screen.
*--------------------------------------
MAXENT       equ   255              ; per panel, and a count that fits a byte;
*                                     a floppy cannot come close to it anyway

*--------------------------------------
* VOLSCAN -- fill the left panel from the list of online volumes
*
* The volume list is what "up from the root" reaches, so it is a listing like
* any other and goes in the same arrays.
*--------------------------------------
VOLSCAN      jsr   ONLINEF
             lda   #$00
             sta   LCOUNT
             sta   IDX
:each        lda   IDX
             asl                    ; entry = IDX * 16
             asl
             asl
             asl
             tay
             lda   ONLBUF,y
             and   #$0f             ; name length; zero means an unreadable
             beq   :next            ; device, which we simply do not list
             sta   TMPB             ; how many characters to copy

*--- the name goes at LNAMES + count*16, length first
             lda   LCOUNT
             asl
             asl
             asl
             asl
             tax
             lda   TMPB
             sta   LNAMES,x
             inx
             iny                    ; ONLBUF entry byte 1 is the first letter
:copy        lda   ONLBUF,y
             sta   LNAMES,x
             inx
             iny
             dec   TMPB
             bne   :copy

*--- a volume has no file type and no block count of its own here
             ldx   LCOUNT
             lda   #TYPVOL
             sta   LTYPE,x
             inc   LCOUNT

:next        inc   IDX
             lda   IDX
             cmp   #16
             bcc   :each
             rts

*--------------------------------------
* The arrays. Declared, not emitted.
*--------------------------------------
             dum   $5000
LNAMES       ds    4096             ; 256 * 16: length byte then 15 characters
LTYPE        ds    256              ; ProDOS file type, or TYPVOL
LBLKLO       ds    256              ; blocks used
LBLKHI       ds    256
LACCESS      ds    256              ; bit 1 clear means locked
             dend

*--------------------------------------
* PATHVOL -- PATHBUF = "/" + the name of entry CURSEL
*--------------------------------------
PATHVOL      jsr   SELPTR
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB             ; the name length
             clc
             adc   #$01             ; and the slash
             sta   PATHBUF
             lda   #$2f             ; '/', low ASCII: a pathname is not screen
             sta   PATHBUF+1
             ldx   #$02
:copy        iny
             lda   (NAMPTR),y
             sta   PATHBUF,x
             inx
             dec   TMPB
             bne   :copy
             rts

*--------------------------------------
* PATHDOWN -- append "/" + entry CURSEL to PATHBUF
*--------------------------------------
PATHDOWN     jsr   SELPTR
             ldx   PATHBUF          ; where the existing path ends
             inx
             lda   #$2f             ; '/'
             sta   PATHBUF,x
             ldy   #$00
             lda   (NAMPTR),y
             sta   TMPB
:copy        inx
             iny
             lda   (NAMPTR),y
             sta   PATHBUF,x
             dec   TMPB
             bne   :copy
             stx   PATHBUF          ; the new length
             rts

*--------------------------------------
* SELPTR -- NAMPTR = the name of entry CURSEL
*--------------------------------------
SELPTR       lda   CURSEL
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
* DIRSCAN -- read the directory named by PATHBUF into the arrays
*
* Carry set and MLIERR meaningful if it could not be read.
*--------------------------------------
DIRSCAN      lda   #$00
             sta   LCOUNT
             jsr   OPENF
             bcs   :fail
             lda   OPENREF
             sta   READREF
             sta   CLOSEREF

:block       jsr   READF
             bcs   :done            ; end of file is an error code, and means
             lda   XFERCNT          ; simply that there are no more blocks
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
             beq   :next            ; never used, or deleted
             lsr
             lsr
             lsr
             lsr                    ; the storage type
             cmp   #$0e
             bcs   :next            ; $E and $F are the directory's own header
             jsr   TAKEENT
             lda   LCOUNT
             cmp   #MAXENT
             bcs   :shut            ; the cap in design.md section 4

:next        lda   ENTPTR           ; on to the next entry
             clc
             adc   #$27             ; thirty-nine bytes
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
* TAKEENT -- copy the entry at ENTPTR into the arrays at LCOUNT
*--------------------------------------
TAKEENT      lda   LCOUNT
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

*--- the name, length first
             ldy   #$00
             lda   (ENTPTR),y
             and   #$0f
             sta   TMPB
             sta   (NAMPTR),y
:copy        iny
             lda   (ENTPTR),y
             sta   (NAMPTR),y
             dec   TMPB
             bne   :copy

*--- and the three things the listing shows
             ldx   LCOUNT
             ldy   #$10             ; file type
             lda   (ENTPTR),y
             sta   LTYPE,x
             ldy   #$13             ; blocks used, two bytes
             lda   (ENTPTR),y
             sta   LBLKLO,x
             iny
             lda   (ENTPTR),y
             sta   LBLKHI,x
             ldy   #$1e             ; the access byte; bit 1 is write-enable
             lda   (ENTPTR),y
             sta   LACCESS,x
             inc   LCOUNT
             rts

*--------------------------------------
* PATHUP -- drop the last component of PATHBUF
*
* Carry set if there was nothing left to drop, which means the path was a
* volume root: above that is the list of volumes, and the caller goes there.
*--------------------------------------
PATHUP       ldy   PATHBUF
             beq   :top
:scan        lda   PATHBUF,y
             cmp   #$2f             ; '/'
             beq   :found
             dey
             bne   :scan
:top         sec
             rts
:found       cpy   #$01
             beq   :top             ; "/VOLUME" -- above it is the volume list
             dey
             sty   PATHBUF
             clc
             rts
