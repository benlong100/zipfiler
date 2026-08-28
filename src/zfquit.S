*--------------------------------------
* ZFQUIT.S -- the ProDOS quit routine, replaced
*
* WHAT THIS IS
*
* MLI QUIT ($65) does not "call" anything. It copies a fixed block out of the
* second 4K bank of the language card down to $1000 and jumps there. That
* block IS the quit routine: on ProDOS 2.4 it is Bitsy Bye, and it is four
* pages, $D100-$D4FF, landing at $1000-$13FF.
*
* So replacing what happens when a program quits means replacing those 1024
* bytes. That is what this is, and tools/quitpatch.py is what puts it in.
* Bird's Better Bye did the same thing in 1987; Dave Cotter's BYE.SYSTEM
* existed to put the old one back, which is why the patcher restores as well
* as installs.
*
* THE RULES THIS PLAYS BY
*
* - It must assemble to 1024 bytes or fewer and run at $1000. There is no
*   relocation and no second chance.
* - It is entered with the language card banked in and interrupts disabled.
*   The preamble below is Bitsy Bye's own, byte for byte in intent: bank the
*   ROM back so the monitor's routines work, clear decimal mode, let
*   interrupts back in, and put the screen in a state a program can print on.
* - Everything below $BF00 except its own thousand bytes is free. The program
*   that just quit is dead. So $0800 is the ProDOS I/O buffer and $0C00 holds
*   the volume list; ZipFiler itself loads at $2000, over the top of both.
*
* WHY IT SCANS
*
* It looks for ZIPFILER.SYSTEM on every volume that is on line, rather than
* remembering where it was installed from. A disk gets copied to a card, a
* card gets repartitioned, a slot changes -- and a quit routine that cannot
* find its program leaves you with no way out, because the thing it replaced
* was the way out.
*
* If it finds nothing it says so and waits, then looks again. Putting a disk
* in and pressing a key is a recovery; a hang is not.
*--------------------------------------
             org   $1000
             typ   $06
             dsk   ZFQUIT.BIN

*--- monitor and hardware
CLRALTZP     equ   $c008
ROMIN        equ   $c082
CLR80VID     equ   $c00c
CLR80STORE   equ   $c000
SETVID       equ   $fe93
SETKBD       equ   $fe89
SETTXT       equ   $fb2f
HOME         equ   $fc58
COUT         equ   $fded
KBD          equ   $c000
KBDSTRB      equ   $c010
MLI          equ   $bf00

*--- memory we are free to use; the dead program's, and about to be ZipFiler's
IOBUF        equ   $0800            ; 1K, page aligned, ProDOS insists
ONLBUF       equ   $0c00            ; the volume list, 16 entries of 16
PATH         equ   $0d00            ; the pathname being tried
LOADAT       equ   $2000            ; where a SYS file goes

*--- zero page. The program that quit is gone and ProDOS keeps its own state
*    in the global page, so the usual scratch is ours.
PTR          equ   $06
TMPA         equ   $08
TMPB         equ   $09

*--------------------------------------
START        cld                    ; a quit can arrive in decimal mode
             lda   ROMIN            ; the monitor's routines, please
             cli
             sta   CLRALTZP
             sta   CLR80VID
             sta   CLR80STORE
             jsr   SETVID           ; output to the screen
             jsr   SETKBD           ; input from the keyboard
             jsr   SETTXT
             jsr   HOME

*--------------------------------------
* SCAN -- every volume on line, looking for ZIPFILER.SYSTEM
*--------------------------------------
SCAN         jsr   ONLINE
             bcs   :none            ; no device list: nothing to search

             lda   #$00
             sta   ENTI
:each        jsr   ENTADDR          ; PTR = this entry
             ldy   #$00
             lda   (PTR),y
             and   #$0f             ; the name length; zero means an error
             beq   :next
             jsr   BUILD            ; PATH = /VOLUME/ZIPFILER.SYSTEM
             jsr   GINFO
             bcs   :next
             lda   GTYPE
             cmp   #$ff             ; and it must really be a SYS file
             bne   :next
             jmp   FOUND
:next        inc   ENTI
             lda   ENTI
             cmp   #$10             ; sixteen entries is the whole list
             bcc   :each

*--- nothing. Say so, and look again when a key is pressed: a disk that was
*    not in the drive a moment ago may be in it now.
:none        jsr   HOME
             lda   #<MNOTFOUND
             ldy   #>MNOTFOUND
             jsr   PUTS
:key         lda   KBD
             bpl   :key
             sta   KBDSTRB
             jmp   SCAN

*--------------------------------------
* FOUND -- PATH names it. Hand the machine over.
*--------------------------------------
FOUND        jsr   PUT280           ; where a system program reads its name
             jsr   SETPFX           ; and the volume it came off

             jsr   OPENIT
             bcs   :bad
             lda   OREF
             sta   RREF
             sta   CREF
             jsr   READIT           ; over us, and over everything
             bcs   :bad
             jsr   CLOSEIT
             jmp   LOADAT

*--- It was there a moment ago and now it will not load. Say so rather than
*    jumping into whatever half arrived.
:bad        jsr   CLOSEIT
             jsr   HOME
             lda   #<MBADLOAD
             ldy   #>MBADLOAD
             jsr   PUTS
:wait        lda   KBD
             bpl   :wait
             sta   KBDSTRB
             jmp   SCAN

*--------------------------------------
* ENTADDR -- PTR = the start of entry ENTI in the ON_LINE list
*
* Sixteen bytes an entry, so this is the entry number times sixteen.
*--------------------------------------
ENTADDR      lda   ENTI
             asl
             asl
             asl
             asl
             clc
             adc   #<ONLBUF
             sta   PTR
             lda   #>ONLBUF
             adc   #$00
             sta   PTR+1
             rts

*--------------------------------------
* BUILD -- PATH = "/" + this volume's name + "/ZIPFILER.SYSTEM"
*--------------------------------------
BUILD        ldy   #$00
             lda   (PTR),y
             and   #$0f
             sta   TMPA             ; how long the volume name is

             ldx   #$01
             lda   #'/'
             sta   PATH,x
             ldy   #$00
:name        iny
             inx
             lda   (PTR),y
             sta   PATH,x
             cpy   TMPA
             bcc   :name

             ldy   #$00
:tail        inx
             lda   SUFFIX,y
             sta   PATH,x
             iny
             cpy   #SUFLEN
             bcc   :tail
             stx   PATH             ; the length byte goes on last
             rts

SUFFIX       asc   '/ZIPFILER.SYSTEM'
SUFLEN       equ   *-SUFFIX

*--------------------------------------
* PUT280 -- the pathname where a launched system program looks for it
*--------------------------------------
PUT280       ldy   PATH
:copy        lda   PATH,y
             sta   $0280,y
             dey
             bpl   :copy
             rts

*--------------------------------------
* SETPFX -- the prefix, set to the volume the program is on
*
* Everything up to the last separator, which for this path is the volume.
*--------------------------------------
SETPFX       ldx   PATH
:back        lda   PATH,x
             cmp   #'/'
             beq   :cut
             dex
             bne   :back
             clc                    ; no separator: leave the prefix be
             rts
:cut         dex
             beq   :done
             ldy   #$00
:copy        lda   PATH,y
             sta   PFXBUF,y
             iny
             cpy   PATH
             bcc   :copy
             stx   PFXBUF           ; shortened to the volume
             jsr   MLI
             dfb   $c6              ; SET_PREFIX
             da    PFXPARM
:done        rts

*--------------------------------------
* PUTS -- print the null-terminated string at A,Y
*--------------------------------------
PUTS         sta   PTR
             sty   PTR+1
             ldy   #$00
:loop        lda   (PTR),y
             beq   :done
             jsr   COUT             ; COUT preserves Y
             iny
             bne   :loop
:done        rts

*--------------------------------------
* The MLI calls, each returning with carry set on failure
*--------------------------------------
ONLINE       jsr   MLI
             dfb   $c5
             da    ONLPARM
             rts

GINFO        jsr   MLI
             dfb   $c4
             da    GIPARM
             rts

OPENIT       jsr   MLI
             dfb   $c8
             da    OPARM
             rts

READIT       jsr   MLI
             dfb   $ca
             da    RPARM
             rts

CLOSEIT      jsr   MLI
             dfb   $cc
             da    CPARM
             rts

*--------------------------------------
* Parameter blocks. Assembled with their values, unlike ZipFiler's, which
* live in dum space and have to be filled in at startup.
*--------------------------------------
ONLPARM      dfb   $02
             dfb   $00              ; unit 0: every device there is
             da    ONLBUF

GIPARM       dfb   $0a
             da    PATH
GIACCESS     dfb   $00
GTYPE        dfb   $00
GAUX         dfb   $00,$00
GSTORE       dfb   $00
GBLOCKS      dfb   $00,$00
GMODD        dfb   $00,$00
GMODT        dfb   $00,$00
GCRED        dfb   $00,$00
GCRET        dfb   $00,$00

PFXPARM      dfb   $01
             da    PFXBUF

OPARM        dfb   $03
             da    PATH
             da    IOBUF
OREF         dfb   $00

RPARM        dfb   $04
RREF         dfb   $00
             da    LOADAT
             da    $9f00            ; $2000 to the global page, and no further
RXFER        dw    $0000

CPARM        dfb   $01
CREF         dfb   $00

*--------------------------------------
* Storage and strings
*--------------------------------------
ENTI         dfb   $00              ; which ON_LINE entry is being tried
PFXBUF       ds    64

MNOTFOUND    asc   "ZIPFILER.SYSTEM IS NOT ON ANY DISK"
             dfb   $8d
             asc   "THAT IS ON LINE."
             dfb   $8d,$8d
             asc   "PUT ONE IN AND PRESS A KEY."
             dfb   $8d,$00

MBADLOAD     asc   "ZIPFILER.SYSTEM WOULD NOT LOAD."
             dfb   $8d,$8d
             asc   "PRESS A KEY TO LOOK AGAIN."
             dfb   $8d,$00

*--- The quit routine is four pages and not one byte more. tools/quitpatch.py
*    checks that and pads the rest with zeroes; Merlin cannot compute the
*    padding itself, and the tool has to know the size regardless. If it ever
*    complains, the thing to cut is the scanning, not the messages: being told
*    what went wrong is most of what makes this safe to install.
