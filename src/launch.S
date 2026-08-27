*--------------------------------------
* LAUNCH.S -- run the selected program, or boot a slot
*
* Both commands end ZipFiler. Neither comes back.
*
* The awkward part is that a SYS file loads at $2000, which is where ZipFiler
* is running. The code doing the reading would be overwritten halfway through
* its own MLI call, so it cannot be part of ZipFiler: a small stub is copied
* somewhere the incoming file will not reach, and the jump is made from there.
*
* That stub is POSITION INDEPENDENT, because it is assembled here at $2000-odd
* and executed from wherever it was copied to. Which means, inside STUB:
*
*   - no jsr or jmp to a label inside the stub. Branches only; they are
*     relative and survive the move.
*   - absolute addresses are fine as long as they name something that does not
*     move -- the MLI at $BF00, a parameter block in the dum area below, the
*     entry point being jumped to.
*   - no assumption about where it is running. It never reads its own address.
*
* The first rule is the one that fails silently: a jsr inside the stub
* assembles perfectly and jumps into the middle of whatever the program being
* launched has just loaded. tools/stubcheck.py enforces it.
*
* Everything that CAN fail safely happens before any of that, while ZipFiler
* is still whole -- the path, the prefix, the file's own attributes, and the
* OPEN. A failure there is a message on the status row and nothing else. Once
* the READ begins there is no way back, so the stub's error path is QUIT: the
* global page is still there, and ZipFiler is not.
*
* Three paths are in play and they are not the same path:
*
*   RUNPATH   what gets OPENed and read. For a BASIC program that is the
*             interpreter, not the program.
*   PATHWORK  the entry under the cursor, which is what goes to $0280 and
*             whose directory becomes the prefix.
*
* See docs/design.md section 14.
*--------------------------------------

*--------------------------------------
* RUNINIT -- the parameter blocks, which live in dum space and so start as
* whatever the last program left there. Called once at startup.
*--------------------------------------
RUNINIT      lda   #$00
             sta   RUNNAME          ; no program named until one is
             lda   #$04
             sta   RUNRPARM         ; READ takes four parameters
             lda   #$01
             sta   RUNCPARM         ; CLOSE takes one
             sta   PFXPARM          ; and so does SET_PREFIX
             lda   #$03
             sta   RUNOPARM         ; OPEN takes three
             lda   #$04
             sta   RUNQPARM         ; QUIT takes four
             lda   #<PFXPATH
             sta   PFXPTR
             lda   #>PFXPATH
             sta   PFXPTR+1
             lda   #$00
             sta   RUNQTYPE         ; and the only type there is
             sta   RUNQRES
             sta   RUNQRES+1
             sta   RUNQRES+2
             sta   RUNQRES+3
             rts

*--------------------------------------
* RUNSEL -- run the entry under the cursor, if it is something that runs
*
* Returns only on failure, with the status row already saying why.
*--------------------------------------
RUNSEL       ldx   PANSEL
             lda   PCOUNT,x
             bne   :some
             rts
:some        lda   PINVOL,x         ; a volume is not a program
             bne   :no
             ldy   PCURSEL,x
             lda   (PTYPE),y
             sta   RUNTYPE
             cmp   #$ff             ; SYS
             beq   :ok
             cmp   #$06             ; BIN
             beq   :ok
             cmp   #$fc             ; BAS
             beq   :ok
:no          lda   #<MNOTPROG
             ldy   #>MNOTPROG
             jmp   SAYTEXT

*--- the path of the thing itself, which every branch below needs
:ok          ldx   PANSEL
             lda   PCURSEL,x
             jsr   PATHENT

*--- its real attributes: the panel's type byte came off the directory block,
*    but a BIN's load address and its size did not
             jsr   GINFOF
             bcc   :got
             jmp   RUNFAIL
:got         lda   RUNTYPE
             cmp   #$fc
             beq   :tbas            ; further off than a branch reaches
             cmp   #$06
             beq   :tbin
             bne   RUNSYS
:tbas        jmp   RUNBAS
:tbin        jmp   RUNBIN

*--------------------------------------
* RUNSYS -- a SYS file: $2000, and nothing to decide
*--------------------------------------
RUNSYS       lda   #$00
             sta   RUNNAME          ; nothing to patch into a SYS file
             jsr   RUNSELF          ; the file under the cursor is the one to load
             lda   #$00
             sta   RUNLO
             lda   #$20
             sta   RUNHI            ; every SYS file loads here
             lda   #<IOBUF
             sta   RUNBUF
             lda   #>IOBUF
             sta   RUNBUF+1
             lda   #<STUBHOME
             sta   RUNSTUB
             lda   #>STUBHOME
             sta   RUNSTUB+1
             jmp   RUNGO

*--------------------------------------
* RUNBIN -- a BIN file: it names its own address, and may name ours
*
* aux_type is where it wants to land and blocks_used bounds how far it will
* reach -- an over-estimate, since the last block is rarely full, which is the
* right way for a safety check to be wrong.
*
* Three things must not be inside that range: the stub, the 1K buffer ProDOS
* reads through, and the stack and zero page underneath everything. The first
* two can be moved, so they are, and only a program that leaves nowhere to put
* them is refused.
*--------------------------------------
RUNBIN       lda   #$00
             sta   RUNNAME          ; nor into a BIN
             jsr   RUNSELF
             lda   GAUX
             sta   RUNLO
             lda   GAUX+1
             sta   RUNHI

*--- end = start + blocks * 512. A carry out of sixteen bits is a file that
*    claims to reach past the top of memory, which is refusal either way.
             lda   GBLOCKS
             sta   TMPA
             lda   GBLOCKS+1
             sta   TMPB
             asl   TMPA
             rol   TMPB             ; blocks * 512, with the low byte of the
             bcs   :toobig          ; result being the HIGH byte of a count
             lda   RUNLO
             sta   RUNEND
             lda   TMPA
             clc
             adc   RUNHI
             sta   RUNEND+1
             bcs   :toobig

*--- it may not sit on the zero page or the stack, and may not reach ProDOS
             lda   RUNHI
             cmp   #$02
             bcc   :low
             lda   RUNEND+1
             cmp   #$bf
             bcc   :room
:toobig      lda   #<MNOROOM
             ldy   #>MNOROOM
             jmp   SAYTEXT
:low         lda   #<MTOOLOW
             ldy   #>MTOOLOW
             jmp   SAYTEXT

*--- somewhere to read through: either 1K buffer will do
:room        lda   #<IOBUF
             ldy   #>IOBUF
             ldx   #$04
             jsr   FREEBLK
             bcc   :gotbuf
             lda   #<IOBUF2
             ldy   #>IOBUF2
             ldx   #$04
             jsr   FREEBLK
             bcs   :toobig
:gotbuf      sta   RUNBUF
             sty   RUNBUF+1

*--- the parameter blocks the stub reads after the program has landed. They
*    cannot move, so a program that covers them is refused.
             lda   #$00
             ldy   #>RUNRPARM
             ldx   #$01
             jsr   FREEBLK
             bcs   :toobig

*--- and somewhere to run from. $1800 is the usual home; the screen is the
*    fallback, since we have finished drawing on it and a BIN that loads
*    there is rare enough to be worth a second chance.
             lda   #<STUBHOME
             ldy   #>STUBHOME
             ldx   #$01
             jsr   FREEBLK
             bcc   :gotstub
             lda   #<STUBALT
             ldy   #>STUBALT
             ldx   #$01
             jsr   FREEBLK
             bcs   :toobig
:gotstub     sta   RUNSTUB
             sty   RUNSTUB+1
             jmp   RUNGO

*--------------------------------------
* RUNBAS -- a BASIC program, which needs an interpreter to run it
*
* So the file that gets LOADED is BASIC.SYSTEM, and the program under the
* cursor is named to it: the prefix becomes the program's directory, and the
* stub writes the program's name into BASIC.SYSTEM's own start-up field before
* entering it. See BASNAME2 for what that field is and why it works.
*
* Two other ways in were tried first, and both were checked on the machine
* rather than reasoned about. Neither works, and both are worth knowing about
* so nobody spends the afternoon again:
*
*   - The pathname at $0280. BASIC.SYSTEM reads it, but only to work out a
*     prefix. It has no bearing on what gets run.
*   - Typing the command through KSW, the hook every character GETLN reads
*     passes through. The routine survives the load, but BASIC.SYSTEM puts KSW
*     back to KEYIN as it starts, so it is never called -- confirmed by finding
*     it still intact on page 3 afterwards with $38/$39 reading $FD1B.
*--------------------------------------
RUNBAS       jsr   FINDBASIC        ; RUNPATH = the interpreter, if it exists
             bcc   :found
             lda   #<MNOBASIC
             ldy   #>MNOBASIC
             jmp   SAYTEXT
:found       jsr   BASNAME2         ; the name BASIC.SYSTEM is to run
             lda   #$00             ; BASIC.SYSTEM is a SYS file: $2000
             sta   RUNLO
             lda   #$20
             sta   RUNHI
             lda   #<IOBUF
             sta   RUNBUF
             lda   #>IOBUF
             sta   RUNBUF+1
             lda   #<STUBHOME
             sta   RUNSTUB
             lda   #>STUBHOME
             sta   RUNSTUB+1
             jmp   RUNGO

*--------------------------------------
* BASNAME2 -- RUNNAME = the last component of PATHWORK, length first
*
* BASIC.SYSTEM keeps the name of the program it runs at start-up in its own
* image, at $2006: a length byte and up to fifteen characters, holding
* "STARTUP" as it comes off the disk. Overwrite that between loading it and
* entering it and it runs whatever you name instead. That is the whole trick,
* and it is what ProDOS 2.4's own selector does.
*
* A NAME, not a path -- BASIC.SYSTEM looks for it in the prefix, which RUNGO
* has already set to the directory the program is in.
*--------------------------------------
BASNAME2     ldx   PATHWORK
             beq   :none
:back        lda   PATHWORK,x       ; back to the last separator
             cmp   #'/'
             beq   :cut
             dex
             bne   :back
:none        lda   #$00             ; no separator: nothing safe to name
             sta   RUNNAME
             rts
:cut         stx   TMPA             ; TMPA = where the name starts, less one
             lda   PATHWORK
             sec
             sbc   TMPA
             cmp   #$10             ; ProDOS allows fifteen; anything longer
             bcs   :none            ; is not a name we can have come from
             sta   RUNNAME
             sta   TMPB
             ldy   #$01
             ldx   TMPA
:copy        inx
             lda   PATHWORK,x
             sta   RUNNAME,y
             iny
             cpy   TMPB
             bcc   :copy
             beq   :copy
             rts

*--------------------------------------
* RUNSELF -- the file under the cursor is also the file to load
*--------------------------------------
RUNSELF      ldy   PATHWORK
:copy        lda   PATHWORK,y
             sta   RUNPATH,y
             dey
             bpl   :copy
             rts

*--------------------------------------
* RUNGO -- the point of no return
*
* The prefix, the pathname a system program reads at $0280, and the OPEN all
* happen here, where a failure is still only a message. Then the stub goes in
* and the machine stops being ours.
*--------------------------------------
RUNGO        jsr   SETPFX           ; the directory the PROGRAM lives in
             jsr   PUT280           ; and its name, where a SYS file reads it
             jsr   OPENRUN
             bcc   :open
             jmp   RUNFAIL
:open
*--- from here nothing may fail in a way that can be reported: the screen and
*    the code that draws it are both about to be written over
             lda   RUNOREF          ; the refnum OPEN just handed back
             sta   RUNREF
             sta   RUNCREF
             lda   RUNLO            ; READ puts the file straight where it
             sta   RUNRBUF          ; runs; the 1K buffer was OPEN's business
             lda   RUNHI
             sta   RUNRBUF+1

*--- ask for everything from the load address to the global page, which is
*    more than the file holds. A short read is not an error.
             lda   #$00
             sec
             sbc   RUNLO
             sta   RUNCNT
             lda   #$bf
             sbc   RUNHI
             sta   RUNCNT+1

*--- put the machine back the way a program expects to find it
             jsr   PLAINSCR

*--- and move the stub clear of what is about to land on us. The destination
*    pointer has to be on the zero page for (),y to reach it.
             lda   RUNSTUB
             sta   PDST
             lda   RUNSTUB+1
             sta   PDST+1
             ldy   #STUBLEN-1
:move        lda   STUB,y
             sta   (PDST),y
             dey
             bpl   :move
             jmp   (RUNSTUB)

*--------------------------------------
* STUB -- read the file over us and enter it
*
* POSITION INDEPENDENT: see the rules at the top of this file. Copied to
* RUNSTUB and entered there. Nothing in here may jsr or jmp to a label in
* here.
*--------------------------------------
STUB         jsr   MLI
             dfb   $ca              ; READ
             da    RUNRPARM
             bcs   :bad
             jsr   MLI
             dfb   $cc              ; CLOSE
             da    RUNCPARM

*--- Name the program for BASIC.SYSTEM, now that it is in memory and before it
*    is entered. Zero length for anything else, which is every other launch.
             ldx   RUNNAME
             beq   :go
:pname       lda   RUNNAME,x
             sta   $2006,x
             dex
             bpl   :pname
:go          jmp   (RUNRBUF)
*--- nothing left to report to, and nothing left to report with
:bad         jsr   MLI
             dfb   $65              ; QUIT
             da    RUNQPARM
             brk                    ; QUIT does not return; if it did, stop
STUBEND      equ   *
STUBLEN      equ   STUBEND-STUB

*--------------------------------------
* FREEBLK -- is the X-page block at A,Y clear of the incoming program?
*
* Carry clear and A,Y unchanged if it is. Two ranges miss each other only if
* one ends at or before the other starts, which is both of the tests below.
*--------------------------------------
FREEBLK      sta   TMPA
             sty   TMPB
             txa
             clc
             adc   TMPB
             sta   TMPC             ; TMPC = the page after the block

*--- clear if the block ends at or before the program starts...
             lda   TMPC
             cmp   RUNHI
             bcc   :clear
             beq   :clear
*--- ...or begins at or after the program ends
             lda   RUNEND+1
             cmp   TMPB
             bcc   :clear
             beq   :clear
             sec                    ; otherwise they overlap
             rts
:clear       lda   TMPA
             ldy   TMPB
             clc
             rts

*--------------------------------------
* PUT280 -- the pathname at $0280, where a launched system program reads it
*
* ProDOS 8's own dispatcher leaves it there and programs rely on it; a
* launcher that skips it works until it meets one that cares.
*--------------------------------------
PUT280       ldy   PATHWORK         ; the length byte, then the name
:copy        lda   PATHWORK,y
             sta   $0280,y
             dey
             bpl   :copy
             rts

*--------------------------------------
* SETPFX -- the prefix, set to the directory holding PATHWORK
*
* Everything up to the last separator. A program launched with the prefix
* still pointing at wherever the other panel happened to be would look for
* its own files on the wrong disk.
*--------------------------------------
SETPFX       ldx   PATHWORK
             beq   :none
:back        lda   PATHWORK,x       ; the last '/' in the path
             cmp   #'/'
             beq   :cut
             dex
             bne   :back
:none        clc                    ; no separator: leave the prefix alone
             rts
:cut         dex                    ; the directory is everything before it
             beq   :none            ; "/NAME" would leave an empty prefix
             stx   PFXPATH
             ldy   #$01
:copy        lda   PATHWORK,y
             sta   PFXPATH,y
             iny
             dex
             bne   :copy
             jsr   MLI
             dfb   $c6              ; SET_PREFIX
             da    PFXPARM
             sta   MLIERR
             rts

*--------------------------------------
* OPENRUN -- open RUNPATH through whichever buffer was chosen
*--------------------------------------
OPENRUN      lda   #<RUNPATH
             sta   RUNOPATH
             lda   #>RUNPATH
             sta   RUNOPATH+1
             lda   RUNBUF
             sta   RUNOBUF
             lda   RUNBUF+1
             sta   RUNOBUF+1
             jsr   MLI
             dfb   $c8              ; OPEN
             da    RUNOPARM
             sta   MLIERR
             rts

*--------------------------------------
* RUNFAIL -- an MLI error, while there is still a screen to say so on
*--------------------------------------
RUNFAIL      lda   #<MRUNFAIL
             ldy   #>MRUNFAIL
             jmp   SAYTEXT

*--------------------------------------
* FINDBASIC -- RUNPATH = a BASIC.SYSTEM we can reach, carry clear if found
*
* Beside the program first, then at the root of its own volume. A copy on some
* other disk is no use: the interpreter has to be on a volume that is still on
* line when it starts.
*--------------------------------------
FINDBASIC    lda   #$00
             sta   TMPC             ; 0 = beside it, 1 = the volume root
:try         jsr   BASPATH
             jsr   GINFOB
             bcs   :next
             lda   BTYPE
             cmp   #$ff             ; and it must really be a SYS file
             beq   :found
:next        inc   TMPC
             lda   TMPC
             cmp   #$02
             bcc   :try
             sec
             rts
:found       clc
             rts

*--- RUNPATH = <directory>/BASIC.SYSTEM, for whichever directory TMPC names.
*    PATHWORK still holds the program, so the directory is taken from there.
BASPATH      ldx   PATHWORK
             beq   :done
:back        lda   PATHWORK,x       ; back to the last separator
             cmp   #'/'
             beq   :cut
             dex
             bne   :back
             beq   :done
:cut         dex                    ; X = the length of the directory part
             lda   TMPC
             beq   :take
*--- the volume alone: everything up to the SECOND separator
             ldx   #$01
:scan        inx
             cpx   PATHWORK
             bcs   :take
             lda   PATHWORK,x
             cmp   #'/'
             bne   :scan
             dex
:take        cpx   #$34             ; leave room for what gets tacked on
             bcs   :done
             stx   RUNPATH
             ldy   #$01
:copy        cpy   RUNPATH
             beq   :last
             bcs   :tack
:last        lda   PATHWORK,y
             sta   RUNPATH,y
             iny
             bne   :copy
:tack        ldx   RUNPATH
             ldy   #$00
:tick        inx
             lda   BASNAME,y
             sta   RUNPATH,x
             iny
             cpy   #BASLEN
             bcc   :tick
             stx   RUNPATH
:done        rts

BASNAME      asc   "/BASIC.SYSTEM"
BASLEN       equ   *-BASNAME

*--- GET_FILE_INFO on RUNPATH rather than on PATHWORK, which FINDBASIC still
*    needs to hold the program
GINFOB       jsr   MLI
             dfb   $c4
             da    BINFOPARM
             sta   MLIERR
             rts

BINFOPARM    dfb   $0a
             da    RUNPATH
BACCESS      dfb   $00
BTYPE        dfb   $00
BAUX         dfb   $00,$00
BSTORE       dfb   $00
BBLOCKS      dfb   $00,$00
BMODD        dfb   $00,$00
BMODT        dfb   $00,$00
BCRED        dfb   $00,$00
BCRET        dfb   $00,$00

*--------------------------------------
* PLAINSCR -- undo everything DISPINIT set
*
* A program launched into 80STORE, with the alternate character set on and the
* auxiliary bank switched under it, does not stand a chance. This is the state
* ProDOS's own dispatcher hands over.
*--------------------------------------
PLAINSCR     sta   MAINWR           ; PAGE2 off before 80STORE goes
             sta   CLR80STORE
             sta   CLR80VID
             sta   CLRALTCHAR
             sta   TXTSET
             sta   MIXCLR
             sta   HIRESOFF

*--- and a screen it can print on. Forty columns of what ZipFiler drew for
*    eighty is unreadable, and the text window and cursor are wherever the
*    last thing to use them left them -- which is nowhere, since this program
*    writes screen memory directly and never touches COUT.
             jsr   SETTXT           ; full window
             jsr   HOME             ; cleared, cursor home
             rts

*--------------------------------------
* BOOTCMD -- PR#, then a slot, then that slot's ROM
*
* PR#6 is how an Apple II owner says "boot the disk". There is no ProDOS call
* for it: the slot's firmware is entered at $Cn00 and takes the machine from
* there.
*--------------------------------------
BOOTCMD      jsr   ASKSLOT
             bcc   :go
             rts                    ; ESC
:go          sta   TMPA             ; 1-6
             jsr   PLAINSCR

*--- peripheral ROM rather than the //e's own. $C300 is the 80-column
*    firmware until this is done, so slot 3 in particular needs it.
             sta   SETSLOTCXROM
             lda   $cfff            ; and no card's expansion ROM banked in

*--- $Cn00, with the slot in X where the firmware expects to find it
             lda   TMPA
             asl
             asl
             asl
             asl
             tax                    ; X = slot * 16
             lda   TMPA
             clc
             adc   #$c0
             sta   BOOTVEC+1
             lda   #$00
             sta   BOOTVEC
             jmp   (BOOTVEC)

*--------------------------------------
* ASKSLOT -- "PR#" on the status row, one digit. Carry clear, slot in A
*
* Slots 1, 2 and 4 to 7. Not 3: on a //e $C300 is the eighty-column firmware
* rather than a card, and booting it is not a thing anybody means by PR#3.
* Every other slot is the writer's business -- an empty one hangs the machine,
* but so does PR# on a real Apple II, and second-guessing which slots are
* filled is not something this program can do from here.
*--------------------------------------
ASKSLOT      jsr   CLRBUF
             jsr   PANELBAR
             lda   #<MPRHASH
             ldy   #>MPRHASH
             jsr   SETSTR
             ldx   #$00
             jsr   BUFSTR
             lda   #$20             ; an inverse space, so there is a cursor
             sta   LINEBUF,x        ; sitting where the digit will go
             lda   #STATROW
             jsr   DRAWLINE
:key         lda   KBD
             bpl   :key
             sta   KBDSTRB
             cmp   #$9b             ; ESC
             beq   :quit
             cmp   #$b1             ; below '1'
             bcc   :key
             cmp   #$b8             ; above '7'
             bcs   :key
             cmp   #$b3             ; '3' is this machine's own firmware
             beq   :key
             and   #$0f
             clc
             rts
:quit        sec
             rts

MPRHASH      asc   "PR# "
             dfb   $00
MNOTPROG     asc   "NOT A PROGRAM"
             dfb   $00
MNOBASIC     asc   "NO BASIC.SYSTEM ON THIS VOLUME"
             dfb   $00
MNOROOM      asc   "NO ROOM TO LOAD IT SAFELY"
             dfb   $00
MTOOLOW      asc   "IT WOULD LOAD OVER THE STACK"
             dfb   $00
MRUNFAIL     asc   "COULD NOT START IT"
             dfb   $00

*--------------------------------------
* The parameter blocks the stub reaches after it has moved, so they must live
* below $2000 with it rather than in prodos.S. RUNINIT fills in the counts:
* dum storage starts as whatever the last program left here.
*--------------------------------------
             dum   $1760
RUNNAME      ds    16               ; what BASIC.SYSTEM should run, if anything
RUNTYPE      ds    1                ; the type under the cursor
RUNLO        ds    1                ; where the file loads
RUNHI        ds    1
RUNEND       ds    2                ; and how far it reaches
RUNBUF       ds    2                ; the 1K ProDOS reads through
RUNSTUB      ds    2                ; where the stub was put
BOOTVEC      ds    2                ; $Cn00, for the indirect jump

RUNRPARM     ds    1                ; READ
RUNREF       ds    1
RUNRBUF      ds    2
RUNCNT       ds    2
RUNXFER      ds    2

RUNCPARM     ds    1                ; CLOSE
RUNCREF      ds    1

RUNQPARM     ds    1                ; QUIT
RUNQTYPE     ds    1
RUNQRES      ds    5

RUNOPARM     ds    1                ; OPEN
RUNOPATH     ds    2
RUNOBUF      ds    2
RUNOREF      ds    1

PFXPARM      ds    1                ; SET_PREFIX
PFXPTR       ds    2
             dend

*--- the path that actually gets opened, and the prefix built out of it
             dum   $1900
RUNPATH      ds    65
PFXPATH      ds    65
             dend

*--- The stub's home, and the fallback for a BIN that wants it. Both below
*    $2000, where a SYS file starts, so neither is ever in a SYS file's way.
STUBHOME     equ   $1800
STUBALT      equ   $0400            ; the screen; we have stopped drawing on it

