* A program that does nothing but quit, to prove the replaced quit routine
* catches ANY program and not just ZipFiler's own Q.
             org   $2000
             typ   $ff
             dsk   QUITTER
COUT         equ   $fded
START        ldx   #$00
:say         lda   MSG,x
             beq   :go
             jsr   COUT
             inx
             bne   :say
:go          jsr   $bf00
             dfb   $65
             da    QP
             brk
MSG          asc   "SOME OTHER PROGRAM. QUITTING NOW."
             dfb   $8d,$00
QP           dfb   $04,$00,$00,$00,$00,$00,$00
