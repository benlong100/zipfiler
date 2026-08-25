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
MAXENT       equ   256              ; per panel; a floppy cannot reach it

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
             dend
