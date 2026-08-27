*--------------------------------------
* RUNBIN.S -- the same thing as a BIN, to prove the other launch path
*
* The suite needs to prove that RET on a program actually starts it, and the
* only proof the screen can carry is something appearing on it that ZipFiler
* could not have drawn. So this prints a phrase that appears nowhere in
* ZipFiler and then stops, leaving it there to be read.
*
* It also prints the pathname ProDOS convention says it should find at $0280,
* which is how the suite checks that the launcher set it: getting that wrong
* is invisible until some real program needs it.
*
* A BIN names its own load address in aux_type, so this one deliberately does
* NOT load at $2000: page 3 is a classic BIN address, it is nowhere near the
* stub or either 1K buffer, and landing there proves the launcher read the
* address out of the file rather than assuming the SYS one.
*--------------------------------------
             org   $0300
             typ   $06
             dsk   RUNBIN

COUT         equ   $fded
CR           equ   $8d

START        lda   #CR
             jsr   COUT
             ldx   #$00
:say         lda   BANNER,x
             beq   :path
             jsr   COUT
             inx
             bne   :say

*--- the pathname the launcher is meant to have left at $0280, length first
:path        lda   #CR
             jsr   COUT
             ldx   $0280
             beq   :stop
             ldx   #$01
:name        lda   $0280,x
             ora   #$80             ; ProDOS keeps it in low ASCII
             jsr   COUT
             inx
             cpx   $0280
             bcc   :name
             beq   :name

*--- and the prefix, which is the other thing the launcher sets and the other
*    thing that is invisible until some real program depends on it
             lda   #CR
             jsr   COUT
             jsr   $bf00
             dfb   $c7              ; GET_PREFIX
             da    PFXPARM
             bcs   :stop
             ldx   PFXBUF
             beq   :stop
             ldx   #$01
:pfx         lda   PFXBUF,x
             ora   #$80
             jsr   COUT
             inx
             cpx   PFXBUF
             bcc   :pfx
             beq   :pfx

:stop        jmp   :stop            ; hold it on screen for the suite to read

BANNER       asc   "RUNBIN AT 0300"
             dfb   $00
PFXPARM      dfb   $01
             da    PFXBUF
PFXBUF       ds    64
