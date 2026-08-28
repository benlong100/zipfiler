*--------------------------------------
* QPATCH.S -- change what QUIT does, on a volume you cannot reach from the Mac
*
* tools/quitpatch.py does this to a disk image. That is safer and is still the
* right way when the disk is a floppy image. But a large volume on a card, or
* one reached over a network share, is not a .po file sitting on the Mac -- and
* those are exactly the volumes worth having ZipFiler come back on. So this
* does the same job from the Apple, on a live volume.
*
* WHAT IT WRITES
*
* MLI QUIT copies four pages out of the language card to $1000 and jumps there.
* Those 1024 bytes live verbatim inside the PRODOS file, and this replaces
* them. See docs/design.md section 15.
*
* HOW IT TRIES NOT TO RUIN YOUR DISK
*
* Writing to a volume's PRODOS is writing to its operating system. If this goes
* wrong the volume does not boot, so the order below is the whole design and
* not an implementation detail:
*
*   1. Read PRODOS. Find the block by its signature, and refuse unless there is
*      exactly one -- no match or several means this is not a ProDOS we know.
*   2. Write the ORIGINAL block to QUIT.ORIG on the same volume.
*   3. Read QUIT.ORIG back and compare it. If the save did not survive the
*      trip, stop. PRODOS has not been touched at this point and the disk is
*      exactly as it was.
*   4. Only now write the new block, with SET_MARK and 1024 bytes -- not by
*      rewriting the whole 17K file, which is a much bigger thing to be halfway
*      through when something goes wrong.
*   5. Read it back and compare that too.
*
* Restoring is the same in reverse, and refuses if QUIT.ORIG is not there.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   QPATCH.SYSTEM

*--- monitor
COUT         equ   $fded
HOME         equ   $fc58
SETTXT       equ   $fb2f
SETVID       equ   $fe93
SETKBD       equ   $fe89
KBD          equ   $c000
KBDSTRB      equ   $c010
ROMIN        equ   $c082
CLR80VID     equ   $c00c
CLR80STORE   equ   $c000
MLI          equ   $bf00

*--- buffers. This is a standalone program; all of memory below the globals is
*    ours, and the biggest thing needed is somewhere to hold PRODOS.
IOBUF        equ   $0800            ; 1K, page aligned, ProDOS insists
ONLBUF       equ   $0c00            ; the volume list
PATH         equ   $0d00            ; /VOLUME/PRODOS
PATH2        equ   $0d80            ; /VOLUME/QUIT.ORIG
VERIFY       equ   $0e00            ; 1K, for reading back what we wrote
PROBUF       equ   $4000            ; PRODOS itself, up to 32K
PROMAX       equ   $8000            ; and no more than that

*--- zero page
PTR          equ   $06
SRC          equ   $08
DST          equ   $0a
TMPA         equ   $0c
TMPB         equ   $0d
CNT          equ   $0e

QUITLEN      equ   1024

*--------------------------------------
START        lda   ROMIN
             sta   CLR80VID
             sta   CLR80STORE
             jsr   SETVID
             jsr   SETKBD
             jsr   SETTXT
             jsr   HOME
             lda   #<MTITLE
             ldy   #>MTITLE
             jsr   PUTS

*--------------------------------------
* Pick a volume
*--------------------------------------
PICK         jsr   ONLINE
             bcs   :nodev
             lda   #<MVOLS
             ldy   #>MVOLS
             jsr   PUTS

             lda   #$00
             sta   ENTI
:show        jsr   ENTADDR
             ldy   #$00
             lda   (PTR),y
             and   #$0f
             beq   :next
             lda   ENTI             ; "  1. " and so on, one-based
             clc
             adc   #$b1
             jsr   COUT
             lda   #$ae             ; '.'
             jsr   COUT
             lda   #$a0
             jsr   COUT
             jsr   PUTVOL
             lda   #$8d
             jsr   COUT
:next        inc   ENTI
             lda   ENTI
             cmp   #$10
             bcc   :show

             lda   #<MWHICH
             ldy   #>MWHICH
             jsr   PUTS
:key         lda   KBD
             bpl   :key
             sta   KBDSTRB
             cmp   #$9b             ; ESC: leave without doing anything
             beq   BYE
             sec
             sbc   #$b1             ; '1' is entry zero
             bmi   :key
             cmp   #$10
             bcs   :key
             sta   ENTI
             jsr   ENTADDR
             ldy   #$00
             lda   (PTR),y
             and   #$0f
             beq   :key             ; an entry with no name is not a volume
             jmp   CHOSEN

:nodev       lda   #<MNODEV
             ldy   #>MNODEV
             jsr   PUTS
BYE          jsr   MLI
             dfb   $65
             da    QUITP
             brk                    ; QUIT does not come back

*--------------------------------------
* CHOSEN -- read that volume's PRODOS and say what is in it
*--------------------------------------
CHOSEN       jsr   HOME
             lda   #<MTITLE
             ldy   #>MTITLE
             jsr   PUTS

             jsr   MKPATHS          ; PATH = /VOL/PRODOS, PATH2 = /VOL/QUIT.ORIG
             jsr   PUTS2            ; show which volume, and a blank line

             jsr   LOADPRO          ; PRODOS -> PROBUF
             bcc   :ok
             lda   #<MNOPRO
             ldy   #>MNOPRO
             jsr   PUTS
             jmp   ANYKEY

:ok          jsr   FINDSIG          ; OFF = where the quit block starts
             bcc   :found
             lda   #<MNOSIG
             ldy   #>MNOSIG
             jsr   PUTS
             jmp   ANYKEY

:found       jsr   WHOSE            ; A = 0 original, 1 ours
             sta   ISOURS
             lda   #<MNOWIS
             ldy   #>MNOWIS
             jsr   PUTS
             lda   ISOURS
             beq   :orig
             lda   #<MISOURS
             ldy   #>MISOURS
             bne   :sayit
:orig        lda   #<MISORIG
             ldy   #>MISORIG
:sayit       jsr   PUTS

*--- what would you like to do about it
             lda   #<MMENU
             ldy   #>MMENU
             jsr   PUTS
:key         lda   KBD
             bpl   :key
             sta   KBDSTRB
             and   #$df             ; either case
             cmp   #$c9             ; I
             beq   :install
             cmp   #$d2             ; R
             beq   :restore
             cmp   #$9b
             beq   :leave
             jmp   :key
:leave       jmp   BYE
:install     jmp   INSTALL
:restore     jmp   RESTORE

*--------------------------------------
* INSTALL -- save the original, prove the save, then write the new block
*--------------------------------------
INSTALL      lda   ISOURS
             beq   :go
             lda   #<MALREADY       ; patching a patched disk would overwrite
             ldy   #>MALREADY       ; the saved original with a patch
             jsr   PUTS
             jmp   ANYKEY

:go          lda   #<MSAVING
             ldy   #>MSAVING
             jsr   PUTS

*--- QUIT.ORIG gets the block that is in PRODOS now
             jsr   DESTROY2         ; a stale one from a previous go
             jsr   CREATE2
             jsr   OPEN2
             bcs   :savefail
             lda   OREF
             sta   WREF
             sta   CREF
             jsr   SRCOFF           ; WBUF = PROBUF + OFF
             lda   SRC
             sta   WBUF
             lda   SRC+1
             sta   WBUF+1
             jsr   WRITEF
             php
             jsr   CLOSEF
             plp
             bcs   :savefail

*--- and is read back and compared before PRODOS is touched at all
             jsr   OPEN2
             bcs   :savefail
             lda   OREF
             sta   RREF
             sta   CREF
             lda   #<VERIFY
             sta   RBUF
             lda   #>VERIFY
             sta   RBUF+1
             jsr   READF
             php
             jsr   CLOSEF
             plp
             bcs   :savefail
             jsr   SRCOFF
             jsr   SAMEBLK          ; VERIFY vs the block in PROBUF
             bcs   :savefail

*--- the original is safely on the disk. Now, and only now, PRODOS changes.
             lda   #<MWRITING
             ldy   #>MWRITING
             jsr   PUTS
             lda   #<QUITCODE
             sta   WBUF
             lda   #>QUITCODE
             sta   WBUF+1
             jsr   PUTBLOCK
             bcs   :writefail

*--- read it back off the disk and compare
             jsr   GETBLOCK
             bcs   :writefail
             lda   #<QUITCODE
             sta   SRC
             lda   #>QUITCODE
             sta   SRC+1
             jsr   SAMEBLK
             bcs   :writefail
             lda   #<MDONEI
             ldy   #>MDONEI
             jsr   PUTS
             jmp   ANYKEY

:savefail    lda   #<MSAVEFAIL
             ldy   #>MSAVEFAIL
             jsr   PUTS
             jmp   ANYKEY
:writefail   lda   #<MWRITEFAIL
             ldy   #>MWRITEFAIL
             jsr   PUTS
             jmp   ANYKEY

*--------------------------------------
* RESTORE -- put back what QUIT.ORIG holds
*--------------------------------------
RESTORE      jsr   OPEN2
             bcc   :got
             lda   #<MNOSAVE
             ldy   #>MNOSAVE
             jsr   PUTS
             jmp   ANYKEY
:got         lda   OREF
             sta   RREF
             sta   CREF
             lda   #<VERIFY
             sta   RBUF
             lda   #>VERIFY
             sta   RBUF+1
             jsr   READF
             php
             jsr   CLOSEF
             plp
             bcs   :bad

             lda   #<MWRITING
             ldy   #>MWRITING
             jsr   PUTS
             lda   #<VERIFY
             sta   WBUF
             lda   #>VERIFY
             sta   WBUF+1
             jsr   PUTBLOCK
             bcs   :bad

             jsr   DESTROY2         ; the save has served its purpose
             lda   #<MDONER
             ldy   #>MDONER
             jsr   PUTS
             jmp   ANYKEY
:bad         lda   #<MWRITEFAIL
             ldy   #>MWRITEFAIL
             jsr   PUTS
             jmp   ANYKEY

*--------------------------------------
* ANYKEY -- wait, then start over so another volume can be done
*--------------------------------------
ANYKEY       lda   #<MAGAIN
             ldy   #>MAGAIN
             jsr   PUTS
:key         lda   KBD
             bpl   :key
             sta   KBDSTRB
             cmp   #$9b
             bne   :again
             jmp   BYE
:again       jsr   HOME
             lda   #<MTITLE
             ldy   #>MTITLE
             jsr   PUTS
             jmp   PICK

*--------------------------------------
* PUTBLOCK / GETBLOCK -- the 1024 bytes at OFF inside PRODOS
*
* SET_MARK and a single 1024-byte transfer, rather than rewriting the whole
* file: far less to be in the middle of if something goes wrong.
*--------------------------------------
PUTBLOCK     jsr   OPENPRO
             bcs   :out
             lda   OREF
             sta   WREF
             sta   MREF
             sta   CREF
             jsr   SETMARK
             bcs   :shut
             jsr   WRITEF
:shut        php
             jsr   CLOSEF
             plp
:out         rts

GETBLOCK     jsr   OPENPRO
             bcs   :out
             lda   OREF
             sta   RREF
             sta   MREF
             sta   CREF
             lda   #<VERIFY
             sta   RBUF
             lda   #>VERIFY
             sta   RBUF+1
             jsr   SETMARK
             bcs   :shut
             jsr   READF
:shut        php
             jsr   CLOSEF
             plp
:out         rts

*--------------------------------------
* SAMEBLK -- 1024 bytes at SRC against VERIFY. Carry set if they differ.
*--------------------------------------
SAMEBLK      lda   #<VERIFY
             sta   DST
             lda   #>VERIFY
             sta   DST+1
             lda   #$04             ; four pages
             sta   CNT
:page        ldy   #$00
:byte        lda   (SRC),y
             cmp   (DST),y
             bne   :differ
             iny
             bne   :byte
             inc   SRC+1
             inc   DST+1
             dec   CNT
             bne   :page
             clc
             rts
:differ      sec
             rts

*--- SRC = PROBUF + OFF, the block as it stands in the copy we read
SRCOFF       lda   OFF
             clc
             adc   #<PROBUF
             sta   SRC
             lda   OFF+1
             adc   #>PROBUF
             sta   SRC+1
             rts

*--------------------------------------
* FINDSIG -- OFF = the quit block. Carry set if it is not there exactly once.
*
* The signature is what any quit routine has to start with: clear decimal,
* bank the ROM in, allow interrupts. A fixed offset would silently patch the
* wrong kilobyte of a ProDOS that moved it.
*--------------------------------------
FINDSIG      lda   #$00
             sta   OFF
             sta   OFF+1
             sta   NFOUND
             lda   #<PROBUF
             sta   PTR
             lda   #>PROBUF
             sta   PTR+1
             lda   #$00
             sta   TMPA             ; how far along we are, low
             sta   TMPA+1

:scan        ldy   #$00
:cmp         lda   (PTR),y
             cmp   SIGDATA,y
             bne   :step
             iny
             cpy   #SIGLEN
             bcc   :cmp
*--- a match. Remember the first, and count them.
             lda   NFOUND
             bne   :more
             lda   TMPA
             sta   OFF
             lda   TMPA+1
             sta   OFF+1
:more        inc   NFOUND

:step        inc   TMPA
             bne   :nohi
             inc   TMPA+1
:nohi        inc   PTR
             bne   :nohi2
             inc   PTR+1
:nohi2       lda   TMPA+1           ; stop before the end, less the block
             cmp   PROLEN+1
             bcc   :scan
             lda   TMPA
             cmp   PROLEN
             bcc   :scan

             lda   NFOUND
             cmp   #$01             ; exactly one, or we do not touch it
             bne   :no
             clc
             rts
:no          sec
             rts

SIGDATA      dfb   $d8,$ad,$82,$c0,$58
SIGLEN       equ   *-SIGDATA

*--------------------------------------
* WHOSE -- A = 1 if the block already holds our routine, 0 if it does not
*--------------------------------------
WHOSE        jsr   SRCOFF
             ldy   #$00
:cmp         lda   (SRC),y
             cmp   QUITCODE,y
             bne   :no
             iny
             cpy   #$20             ; the first thirty-two bytes settle it
             bcc   :cmp
             lda   #$01
             rts
:no          lda   #$00
             rts

*--------------------------------------
* LOADPRO -- PRODOS into PROBUF; PROLEN = how much came back
*--------------------------------------
LOADPRO      jsr   OPENPRO
             bcs   :out
             lda   OREF
             sta   RREF
             sta   CREF
             lda   #<PROBUF
             sta   RBUF
             lda   #>PROBUF
             sta   RBUF+1
             lda   #<PROMAX
             sta   RCNT
             lda   #>PROMAX
             sta   RCNT+1
             jsr   READF
             php
             lda   RXFER
             sta   PROLEN
             lda   RXFER+1
             sta   PROLEN+1
             jsr   CLOSEF
             plp
:out         rts

*--------------------------------------
* MKPATHS -- PATH = /VOL/PRODOS and PATH2 = /VOL/QUIT.ORIG
*--------------------------------------
MKPATHS      jsr   ENTADDR
             ldy   #$00
             lda   (PTR),y
             and   #$0f
             sta   TMPB

             ldx   #$01
             lda   #'/'
             sta   PATH,x
             sta   PATH2,x
             ldy   #$00
:name        iny
             inx
             lda   (PTR),y
             sta   PATH,x
             sta   PATH2,x
             cpy   TMPB
             bcc   :name
             stx   TMPA             ; where the volume name ends

*--- /PRODOS
             ldx   TMPA
             ldy   #$00
:p1          inx
             lda   SUFPRO,y
             sta   PATH,x
             iny
             cpy   #SUFPROL
             bcc   :p1
             stx   PATH

*--- /QUIT.ORIG
             ldx   TMPA
             ldy   #$00
:p2          inx
             lda   SUFSAVE,y
             sta   PATH2,x
             iny
             cpy   #SUFSAVEL
             bcc   :p2
             stx   PATH2
             rts

SUFPRO       asc   '/PRODOS'
SUFPROL      equ   *-SUFPRO
SUFSAVE      asc   '/QUIT.ORIG'
SUFSAVEL     equ   *-SUFSAVE

*--------------------------------------
* ENTADDR / PUTVOL / PUTS2 -- the volume list
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

PUTVOL       lda   #$af             ; '/'
             jsr   COUT
             jsr   ENTADDR
             ldy   #$00
             lda   (PTR),y
             and   #$0f
             sta   TMPB
             ldy   #$00
:loop        iny
             lda   (PTR),y
             ora   #$80
             jsr   COUT
             cpy   TMPB
             bcc   :loop
             rts

*--- the chosen volume, then a blank line
PUTS2        jsr   PUTVOL
             lda   #$8d
             jsr   COUT
             lda   #$8d
             jmp   COUT

*--------------------------------------
* PUTS -- the null-terminated string at A,Y
*--------------------------------------
PUTS         sta   PTR
             sty   PTR+1
             ldy   #$00
:loop        lda   (PTR),y
             beq   :done
             jsr   COUT
             iny
             bne   :loop
:done        rts

*--------------------------------------
* The MLI calls
*--------------------------------------
ONLINE       jsr   MLI
             dfb   $c5
             da    ONLPARM
             rts

OPENPRO      lda   #<PATH
             sta   OPATH
             lda   #>PATH
             sta   OPATH+1
             jmp   OPENIT

OPEN2        lda   #<PATH2
             sta   OPATH
             lda   #>PATH2
             sta   OPATH+1
             jmp   OPENIT

OPENIT       jsr   MLI
             dfb   $c8
             da    OPARM
             rts

READF        jsr   MLI
             dfb   $ca
             da    RPARM
             rts

WRITEF       jsr   MLI
             dfb   $cb
             da    WPARM
             rts

SETMARK      lda   OFF
             sta   MPOS
             lda   OFF+1
             sta   MPOS+1
             lda   #$00
             sta   MPOS+2
             jsr   MLI
             dfb   $ce
             da    MPARM
             rts

CLOSEF       jsr   MLI
             dfb   $cc
             da    CPARM
             rts

CREATE2      lda   #<PATH2
             sta   CRPATH
             lda   #>PATH2
             sta   CRPATH+1
             jsr   MLI
             dfb   $c0
             da    CRPARM
             rts

DESTROY2     lda   #<PATH2
             sta   DPATH
             lda   #>PATH2
             sta   DPATH+1
             jsr   MLI
             dfb   $c1
             da    DPARM
             rts

*--------------------------------------
* Parameter blocks
*--------------------------------------
ONLPARM      dfb   $02
             dfb   $00
             da    ONLBUF

OPARM        dfb   $03
OPATH        da    PATH
             da    IOBUF
OREF         dfb   $00

RPARM        dfb   $04
RREF         dfb   $00
RBUF         da    VERIFY
RCNT         da    QUITLEN
RXFER        dw    $0000

WPARM        dfb   $04
WREF         dfb   $00
WBUF         da    QUITCODE
             da    QUITLEN
WXFER        dw    $0000

MPARM        dfb   $02
MREF         dfb   $00
MPOS         dfb   $00,$00,$00

CPARM        dfb   $01
CREF         dfb   $00

CRPARM       dfb   $07
CRPATH       da    PATH2
             dfb   $c3              ; access: everything
             dfb   $06              ; type BIN
             da    $0000            ; aux
             dfb   $01              ; storage type: seedling
             da    $0000            ; date
             da    $0000            ; time

DPARM        dfb   $01
DPATH        da    PATH2

QUITP        dfb   $04,$00,$00,$00,$00,$00,$00

*--------------------------------------
* Storage
*--------------------------------------
ENTI         dfb   $00
OFF          dw    $0000
PROLEN       dw    $0000
NFOUND       dfb   $00
ISOURS       dfb   $00

*--------------------------------------
* What it says
*--------------------------------------
MTITLE       asc   "ZIPFILER -- QUIT PATCHER"
             dfb   $8d,$8d,$00
MVOLS        asc   "VOLUMES ON LINE:"
             dfb   $8d,$8d,$00
MWHICH       dfb   $8d
             asc   "WHICH ONE? (ESC TO LEAVE) "
             dfb   $00
MNODEV       asc   "NO VOLUMES ARE ON LINE."
             dfb   $8d,$00
MNOPRO       asc   "THAT VOLUME HAS NO PRODOS FILE,"
             dfb   $8d
             asc   "SO IT IS NOT ONE YOU BOOT FROM."
             dfb   $8d,$00
MNOSIG       asc   "THE QUIT ROUTINE IS NOT WHERE THIS"
             dfb   $8d
             asc   "EXPECTS IT, OR THERE IS MORE THAN"
             dfb   $8d
             asc   "ONE PLACE IT COULD BE. NOTHING HAS"
             dfb   $8d
             asc   "BEEN CHANGED."
             dfb   $8d,$00
MNOWIS       asc   "QUITTING NOW GOES TO: "
             dfb   $00
MISOURS      asc   "ZIPFILER"
             dfb   $8d,$00
MISORIG      asc   "THE ORIGINAL (BITSY BYE)"
             dfb   $8d,$00
MMENU        dfb   $8d
             asc   "  I  MAKE QUIT GO TO ZIPFILER"
             dfb   $8d
             asc   "  R  PUT THE ORIGINAL BACK"
             dfb   $8d
             asc   "  ESC  LEAVE IT ALONE"
             dfb   $8d,$8d
             asc   "  > "
             dfb   $00
MALREADY     dfb   $8d
             asc   "IT ALREADY GOES TO ZIPFILER."
             dfb   $8d,$00
MSAVING      dfb   $8d
             asc   "SAVING THE ORIGINAL TO QUIT.ORIG..."
             dfb   $8d,$00
MWRITING     asc   "WRITING PRODOS..."
             dfb   $8d,$00
MSAVEFAIL    asc   "THE ORIGINAL COULD NOT BE SAVED, SO"
             dfb   $8d
             asc   "PRODOS HAS NOT BEEN TOUCHED. THE"
             dfb   $8d
             asc   "DISK IS AS IT WAS."
             dfb   $8d,$00
MWRITEFAIL   asc   "THE WRITE FAILED OR DID NOT READ"
             dfb   $8d
             asc   "BACK THE SAME. QUIT.ORIG HOLDS THE"
             dfb   $8d
             asc   "ORIGINAL; USE R TO PUT IT BACK."
             dfb   $8d,$00
MNOSAVE      dfb   $8d
             asc   "THERE IS NO QUIT.ORIG ON THAT"
             dfb   $8d
             asc   "VOLUME, SO THERE IS NOTHING TO PUT"
             dfb   $8d
             asc   "BACK."
             dfb   $8d,$00
MDONEI       dfb   $8d
             asc   "DONE. QUITTING ANY PROGRAM ON THAT"
             dfb   $8d
             asc   "VOLUME NOW RUNS ZIPFILER.SYSTEM."
             dfb   $8d
             asc   "REBOOT FOR IT TO TAKE EFFECT."
             dfb   $8d,$00
MDONER       dfb   $8d
             asc   "DONE. THE ORIGINAL QUIT ROUTINE IS"
             dfb   $8d
             asc   "BACK. REBOOT FOR IT TO TAKE EFFECT."
             dfb   $8d,$00
MAGAIN       dfb   $8d
             asc   "A KEY FOR ANOTHER VOLUME, ESC TO GO."
             dfb   $8d,$00

             put   zfquitdata
