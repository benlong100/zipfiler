*--------------------------------------
* COPY.S -- C, always from the left panel to the right
*
* The direction is fixed so that it never has to be expressed; when something
* has to go the other way, S exchanges the panels. See design.md section 5.
*
* A directory goes with everything inside it -- see CPYTREE at the foot of
* this file, which is written flat rather than recursively.
*
* Everything here is written so that a failure leaves nothing behind. A copy
* that stops halfway leaves a truncated file on the destination with a
* plausible name and the right type, which is worse than no copy at all
* because it looks like it worked -- so a copy that fails destroys its own
* output before it reports. The free space check is deferred (section 11);
* handling the failure is not.
*--------------------------------------

*--------------------------------------
* CPYCMD -- copy what the command applies to
*--------------------------------------
CPYCMD       lda   #$00
             sta   OVERW            ; nothing decided about overwriting yet
             sta   NDONE
             sta   NSKIP
             sta   NFAIL
             sta   NITEM

*--- The same directory in both panels would mean copying a file onto itself.
*    Easy to arrange, and nothing good comes of it.
             jsr   SAMEDIR
             bcc   :start
             lda   #<MSAMEDIR
             ldy   #>MSAMEDIR
             jmp   SAYTEXT

:start       lda   #$00
             jsr   SELPANEL         ; targets always come from the left
             jsr   TGTINIT

*--- How many things were asked for, as against how many files that turns out
*    to be. A tagged directory is one thing to the writer and a dozen files to
*    the program, and the progress line has to speak the writer's language.
             lda   NTAG
             bne   :havetot
             lda   #$01             ; no tags: the cursor line, so one thing
:havetot     sta   NTOTAL
:each        jsr   TGTNEXT
             bcs   :done

*--- Say what is about to happen, not what just did. Copying is the slow part,
*    so a count printed after each file is a count nobody sees until the whole
*    run is over -- and what showed up at the end was the destination rescan
*    announcing itself, which reads as the program only starting work once it
*    had finished. NITEM is the item in hand, so it counts up as each one
*    begins.
             inc   NITEM
             jsr   SHOWPROG

*--- a directory goes with everything in it
             ldy   TGTI
             lda   (PTYPE),y
             cmp   #$0f
             bne   :file
             jsr   CPYPATHS
             jsr   CPYTREE
             lda   CPYSTOP
             beq   :next
             jmp   :done

:file        jsr   CPYPATHS
             jsr   CPYONE
             bcc   :ok
             lda   CPYSTOP
             bne   :done            ; the writer asked to stop
             jmp   :next
:ok          inc   NDONE
:next        lda   #$00
             jsr   SELPANEL         ; CPYPATHS left the right panel chosen
             jmp   :each

:done        lda   #$01             ; the destination listing has changed
             jsr   SELPANEL
             jsr   RESCAN
             jsr   CLAMPSEL
             lda   #$00
             jsr   SELPANEL
             jmp   CPYSAY

*--------------------------------------
* CPYPATHS -- PATHWORK = the source, PATHNEW = where it is going
*
* NAMPTR is an address in the left panel's names, so it survives choosing the
* right panel: the name comes from one side and the directory from the other.
*--------------------------------------
CPYPATHS     lda   TGTI
             jsr   PATHENT          ; the left panel's directory and the name
             lda   #$01
             jsr   SELPANEL
             lda   #<PATHNEW
             sta   PBUF
             lda   #>PATHNEW
             sta   PBUF+1
             jmp   PATHBLD          ; the right panel's directory, same name

*--------------------------------------
* SAMEDIR -- carry set if both panels are looking at the same directory
*--------------------------------------
SAMEDIR      ldy   PATH0
             cpy   PATH1
             bne   :no
             cpy   #$00
             beq   :yes             ; both empty: both the volume list
:loop        lda   PATH0,y
             cmp   PATH1,y
             bne   :no
             dey
             bne   :loop
:yes         sec
             rts
:no          clc
             rts

*--------------------------------------
* CPYONE -- one file from PATHWORK to PATHNEW. Carry set if it did not go.
*--------------------------------------
CPYONE       lda   #$00
             sta   CPYSTOP

*--- what it is, so that what arrives is the same thing
             jsr   GINFOF
             bcc   *+5
             jmp   :bad
             lda   GACCESS
             sta   CREACCESS
             lda   GTYPE
             sta   CRETYPE
             lda   GAUX
             sta   CREAUX
             lda   GAUX+1
             sta   CREAUX+1
             lda   GCRED
             sta   CREDATE
             lda   GCRED+1
             sta   CREDATE+1
             lda   GCRET
             sta   CRETIME
             lda   GCRET+1
             sta   CRETIME+1

*--- an unlocked destination, whatever the source was; the access is put back
*    at the end, once there is something to protect
             lda   CREACCESS
             ora   #$c2
             sta   CREACCESS

:make        jsr   CREATEF
             bcc   :opened
             lda   MLIERR
             cmp   #$47             ; there is one there already
             beq   :exists
             jmp   :bad2

*--- Asked once for the whole batch, not once a file: right for one file and
*    miserable for twelve. design.md section 7.
:exists      lda   OVERW
             bne   :decided
             jsr   ASKOVER
:decided     lda   OVERW
             cmp   #$02             ; skip everything that is already there
             bne   *+5
             jmp   :skipped
             cmp   #$03             ; stop altogether
             bne   *+5
             jmp   :stop
             jsr   DESTNEW          ; overwrite: take the old one away first
             bcc   *+5
             jmp   :bad2
             jmp   :make

:bad2        jmp   :bad

:opened      jsr   COPENSF
             bcs   :undo
             lda   SRCREF
             sta   CREADREF
             jsr   COPENDF
             bcs   :shutsrc
             lda   DSTREF
             sta   CWRITEREF

:move        jsr   CREADF
             bcs   :fin             ; the end of the file arrives as an error
             lda   CGOT
             ora   CGOT+1
             beq   :fin
             lda   CGOT
             sta   CWANT
             lda   CGOT+1
             sta   CWANT+1
             jsr   CWRITEF
             bcs   :wfail
             jmp   :move

:fin         jsr   SHUTBOTH
*--- and now the dates and the access the source had
             lda   GTYPE
             sta   STYPE
             lda   GAUX
             sta   SAUX
             lda   GAUX+1
             sta   SAUX+1
             lda   GMODD
             sta   SMODD
             lda   GMODD+1
             sta   SMODD+1
             lda   GMODT
             sta   SMODT
             lda   GMODT+1
             sta   SMODT+1
             lda   GACCESS
             sta   SACCESS
             jsr   SETNEW
             clc
             rts

*--- a write that failed leaves a plausible-looking file that is not the file
:wfail       jsr   SHUTBOTH
             jsr   DESTNEW
             inc   NFAIL
             sec
             rts

:shutsrc     lda   SRCREF
             sta   CCLOSEREF
             jsr   CCLOSEF
:undo        jsr   DESTNEW
:bad         inc   NFAIL
             sec
             rts

:skipped     inc   NSKIP
             sec
             rts
:stop        lda   #$01
             sta   CPYSTOP
             sec
             rts

*--------------------------------------
* SHUTBOTH -- close the two files, whatever happened
*--------------------------------------
SHUTBOTH     lda   SRCREF
             sta   CCLOSEREF
             jsr   CCLOSEF
             lda   DSTREF
             sta   CCLOSEREF
             jmp   CCLOSEF

*--- DESTNEW / SETNEW -- act on PATHNEW rather than on PATHWORK
DESTNEW      lda   #<PATHNEW
             sta   DESTPARM+1
             lda   #>PATHNEW
             sta   DESTPARM+2
             jsr   DESTROYF
             pha
             lda   #<PATHWORK       ; and put it back, for D
             sta   DESTPARM+1
             lda   #>PATHWORK
             sta   DESTPARM+2
             pla
             rts

SETNEW       lda   #<PATHNEW
             sta   SINFOPARM+1
             lda   #>PATHNEW
             sta   SINFOPARM+2
             jsr   SINFOF
             pha
             lda   #<PATHWORK
             sta   SINFOPARM+1
             lda   #>PATHWORK
             sta   SINFOPARM+2
             pla
             rts

*--------------------------------------
* ASKOVER -- once for the batch: overwrite, skip them, or stop
*--------------------------------------
ASKOVER      jsr   CLRBUF
             lda   #<MOVER
             ldy   #>MOVER
             jsr   SETSTR
             jsr   CENTRE
             jsr   BUFSTR
             jsr   INVBUF
             lda   #STATROW
             jsr   DRAWLINE
:key         lda   KBD
             bpl   :key
             sta   KEYCHR
             sta   KBDSTRB
             lda   KEYCHR
             cmp   #$9b             ; ESC stops, as everywhere else
             beq   :stop
             and   #$df
             cmp   #$cf             ; O: overwrite them
             beq   :over
             cmp   #$d3             ; S: skip the ones already there
             beq   :skip
             jmp   :key
:over        lda   #$01
             sta   OVERW
             rts
:skip        lda   #$02
             sta   OVERW
             rts
:stop        lda   #$03
             sta   OVERW
             rts

*--------------------------------------
* CPYSAY -- what happened
*--------------------------------------
CPYSAY       lda   NFAIL
             beq   :nofail
             sta   MSGN
             lda   #<MCPYFAIL
             ldy   #>MCPYFAIL
             jmp   SAYMSG
:nofail      lda   NSKIP
             beq   :plain
             lda   NITEM
             sta   MSGN
             lda   #<MCPYSOME
             ldy   #>MCPYSOME
             jmp   SAYMSG

*--- The count is what was ASKED FOR, not how many files it came to. Those
*    differ the moment a directory is tagged, and reporting the second while
*    the writer counted the first reads as a bug.
:plain       lda   NITEM
             sta   MSGN
             lda   NDONE
             cmp   NITEM
             bne   :andfiles
             lda   #<MCOPIED
             ldy   #>MCOPIED
             jmp   SAYMSG
:andfiles    lda   NDONE
             sta   MSGN2
             lda   #<MCOPIEDF
             ldy   #>MCOPIEDF
             jmp   SAYMSG2

MSAMEDIR     asc   "both panels are the same directory"
             dfb   $00
MOVER        asc   "already there.  O verwrite, S kip, ESC to stop"
             dfb   $00
MCOPIED      asc   "copied"
             dfb   $00
MCOPIEDF     asc   "copied, and that came to"
             dfb   $00
MCPYSOME     asc   "copied; the rest were skipped"
             dfb   $00
MCPYFAIL     asc   "could not be copied"
             dfb   $00

*--- $1480-$1490 is catalog.S's; dumcheck.py caught the collision
             dum   $1492
OVERW        ds    1                ; what was decided about existing files
CPYSTOP      ds    1                ; the writer asked to stop
NITEM        ds    1                ; things asked for that are finished
NTOTAL       ds    1                ; and how many were asked for
MSGN2        ds    1                ; a second number for the status row
             dend

*--------------------------------------
* CPYTREE -- copy the directory at PATHWORK to PATHNEW, and all of it
*
* Written flat rather than recursively. Only one directory is open at a time
* and DIRBUF holds one block of it, so going down would lose the parent's
* place -- instead the place is written on a small stack, and on the way back
* up the block is read again with SET_MARK doing the seek.
*
* PATHWORK and PATHNEW ARE the descent. Appending a component to both is
* going down; taking one off each is coming back up. That is why no separate
* pair of buffers is needed, and why CPYONE works unchanged at any depth: it
* copies whatever those two paths currently name.
*--------------------------------------
CPYTREE      lda   #$00
             sta   CDEPTH
             sta   CBLK
             sta   CENT

*--- the top of the tree. An existing directory is not an error here: the
*    files inside it are still to be copied.
             jsr   MKDESTDIR
             bcc   :block
             jmp   :bail

*--- read one block of the directory named by PATHWORK
:block       jsr   TOPENDIR
             bcc   :got
             jmp   :updir           ; unreadable: treat it as finished
:got         lda   TGOT
             ora   TGOT+1
             bne   *+5              ; no more blocks
             jmp   :updir

             lda   #<DIRBUF+4
             sta   ENTPTR
             lda   #>DIRBUF+4
             sta   ENTPTR+1
             lda   CENT
             beq   :scan
             sta   TMPA             ; skip the entries already dealt with
:skip        lda   ENTPTR
             clc
             adc   #$27
             sta   ENTPTR
             bcc   :s2
             inc   ENTPTR+1
:s2          dec   TMPA
             bne   :skip

:scan        lda   CENT
             cmp   #$0d             ; thirteen to a block
             bcc   :entry
             inc   CBLK             ; on to the next block
             lda   #$00
             sta   CENT
             jmp   :block

:entry       jsr   CHECKSTOP
             bcc   *+5
             jmp   :bail
             ldy   #$00
             lda   (ENTPTR),y
             bne   *+5              ; never used, or since deleted
             jmp   :next
             pha
             lsr
             lsr
             lsr
             lsr
             sta   TMPC             ; the storage type
             pla
             and   #$0f
             sta   TMPB             ; the name length
             lda   TMPC
             cmp   #$0e
             bcc   *+5              ; the directory's own header
             jmp   :next

*--- take the name out of DIRBUF before anything can overwrite it
             ldy   #$00
             lda   TMPB
             sta   NAMBUF
:name        iny
             lda   (ENTPTR),y
             sta   NAMBUF,y
             cpy   TMPB
             bcc   :name
             lda   #<NAMBUF
             sta   NAMPTR
             lda   #>NAMBUF
             sta   NAMPTR+1

             lda   TMPC
             cmp   #$0d             ; a subdirectory
             beq   :down

*--- a file: hang its name on both paths, copy it, take it off again
             jsr   TACKBOTH
             bcc   *+5
             jmp   :toodeep
             jsr   CPYONE
             bcc   :counted
             lda   CPYSTOP
             beq   :untack
             jsr   UNTACK
             jmp   :bail
:counted     inc   NDONE
             jsr   SHOWPROG
:untack      jsr   UNTACK
             jmp   :next

*--- a directory: go into it, and remember where we were
:down        jsr   TACKBOTH
             bcc   *+5
             jmp   :toodeep
             jsr   MKDESTDIR
             bcs   :undown
             ldx   CDEPTH
             cpx   #MAXDEEP
             bcs   :undown          ; deeper than the stack goes
             lda   CBLK
             sta   LVLBLK,x
             lda   CENT
             clc
             adc   #$01             ; resume AFTER this entry
             sta   LVLENT,x
             inc   CDEPTH
             lda   #$00
             sta   CBLK
             sta   CENT
             jmp   :block
:undown      jsr   UNTACK
             inc   NFAIL
             jmp   :next

*--- the path would not fit. Count it and carry on with the rest, rather than
*    writing past the end of a buffer to find out.
:toodeep     inc   NFAIL
             jmp   :next

:next        inc   CENT
             lda   ENTPTR
             clc
             adc   #$27
             sta   ENTPTR
             bcc   :n2
             inc   ENTPTR+1
:n2          jmp   :scan

*--- the end of a directory: back up a level, or stop if this was the top
:updir       lda   CDEPTH
             beq   :bail
             dec   CDEPTH
             jsr   UNTACK
             ldx   CDEPTH
             lda   LVLBLK,x
             sta   CBLK
             lda   LVLENT,x
             sta   CENT
             jmp   :block

:bail        rts

*--------------------------------------
* UNTACK -- take the last component off both paths
*--------------------------------------
UNTACK       jsr   SETPW
             jsr   CTRIM
             jsr   SETPN
             jmp   CTRIM

*--------------------------------------
* TOPENDIR -- open PATHWORK, seek to block CBLK, read it, close again
*
* Opened and closed around every block so that CPYONE has both file buffers
* to itself. The seek is what makes that affordable.
*--------------------------------------
TOPENDIR     jsr   COPENSF
             bcs   :no
             lda   SRCREF
             sta   TREADREF
             sta   TMARKREF
             sta   CCLOSEREF

             lda   #$00             ; block CBLK is 512 * CBLK bytes in
             sta   TMARKPOS
             lda   CBLK
             asl                    ; the high byte of CBLK * 512
             sta   TMARKPOS+2
             lda   CBLK
             lsr
             lda   #$00
             ror
             sta   TMARKPOS+1
             jsr   TMARKF
             bcs   :shut
             jsr   TREADF
             php
             jsr   CCLOSEF
             plp
             bcs   :no
             clc
             rts
:shut        jsr   CCLOSEF
:no          sec
             rts

*--------------------------------------
* MKDESTDIR -- make PATHNEW a directory. Already being one is not a failure.
*--------------------------------------
MKDESTDIR    lda   #$c3
             sta   CREACCESS
             lda   #$0f
             sta   CRETYPE
             lda   #$00
             sta   CREAUX
             sta   CREAUX+1
             sta   CREDATE
             sta   CREDATE+1
             sta   CRETIME
             sta   CRETIME+1
             lda   #$0d
             sta   CRESTORE
             jsr   CREATEF
             php
             lda   #$01             ; back to seedling, for the files
             sta   CRESTORE
             plp
             bcc   :ok
             lda   MLIERR
             cmp   #$47             ; it is already there, which is fine
             beq   :ok
             sec
             rts
:ok          clc
             rts

*--------------------------------------
* CHECKSTOP -- ESC gives up on a tree that is taking too long
*--------------------------------------
CHECKSTOP    lda   KBD
             bpl   :on
             cmp   #$9b
             bne   :eat
             sta   KBDSTRB
             lda   #$01
             sta   CPYSTOP
             sec
             rts
:eat         sta   KBDSTRB          ; anything else is not an answer
:on          clc
             rts

*--------------------------------------
* SHOWPROG -- a running count, because a tree off a floppy is slow
*--------------------------------------
SHOWPROG     jsr   CLRBUF
             jsr   PANELBAR
             lda   NITEM
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             sta   TMPA
             jsr   PUTNUM
             lda   #<MOF
             ldy   #>MOF
             jsr   SETSTR
             ldx   #$06
             jsr   BUFSTR
             lda   NTOTAL
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             lda   #$09
             sta   TMPA
             jsr   PUTNUM
             lda   NDONE
             sta   NUMLO
             lda   #$00
             sta   NUMHI
             lda   #$10
             sta   TMPA
             jsr   PUTNUM
             lda   #<MFILES
             ldy   #>MFILES
             jsr   SETSTR
             ldx   #$16
             jsr   BUFSTR
             lda   #STATROW
             jmp   DRAWLINE

MOF          asc   "of"
             dfb   $00
MFILES       asc   "files.  ESC to stop"
             dfb   $00

MAXDEEP      equ   8

             dum   $1498
CDEPTH       ds    1                ; how far down the tree
CBLK         ds    1                ; which block of this directory
CENT         ds    1                ; and which entry in it
LVLBLK       ds    MAXDEEP          ; where to resume, a level up
LVLENT       ds    MAXDEEP
NAMBUF       ds    16               ; a name taken out of DIRBUF before it goes
             dend

*--------------------------------------
* MOVECMD -- M, copy to the right panel and then take the source away
*
* Copy and delete, not a directory-entry relocation. A same-volume move could
* be done by moving the entry itself -- clear it in one directory, write it
* into the other, fix its header_pointer and the two file_counts -- and the
* data blocks would never move at all. ProDOS 8 has no MOVE call and RENAME
* will not cross directories, so that would mean editing directory blocks by
* hand with READ_BLOCK and WRITE_BLOCK, and growing the destination directory
* out of the volume bitmap when it is full. A mistake there is exactly the
* "freed somebody else's blocks" failure the whole test harness exists for.
*
* So: copy, then destroy, out of two routines that are already proven and
* already covered. It works across volumes and within one with no special
* case. The fast path is worth having later, with a test that asserts the
* bitmap did not change at all -- which is the signature that proves no block
* was touched.
*--------------------------------------
MOVECMD      lda   #$00
             sta   OVERW
             sta   NDONE
             sta   NSKIP
             sta   NFAIL
             sta   NITEM

             jsr   SAMEDIR
             bcc   :start
             lda   #<MSAMEDIR
             ldy   #>MSAMEDIR
             jmp   SAYTEXT

:start       lda   #$00
             jsr   SELPANEL
             jsr   TGTINIT
             lda   NTAG
             bne   :havetot
             lda   #$01
:havetot     sta   NTOTAL

:each        jsr   TGTNEXT
             bcs   :done
             inc   NITEM            ; the item in hand, said before the wait
             jsr   SHOWPROG

*--- A directory would need its source tree taken away afterwards, and
*    ProDOS will not destroy a directory with anything in it. Recursive
*    delete is not built, so this says so rather than copying the tree and
*    leaving the original behind pretending it moved.
             ldy   TGTI
             lda   (PTYPE),y
             cmp   #$0f
             bne   :notdir
             inc   NSKIP
             jmp   :next

*--- and a locked file is not taken away either, for the same reason D will
*    not take it: the lock is the writer's stated intent
:notdir      ldy   TGTI
             lda   (PACC),y
             and   #$02
             bne   :go
             inc   NSKIP
             jmp   :next

:go          jsr   CPYPATHS
             jsr   CPYONE
             bcc   :arrived
             lda   CPYSTOP
             beq   :next
             jmp   :done

*--- it is there; only now is it safe to take the original away
:arrived     jsr   DESTROYF
             bcs   :halfway
             inc   NDONE
             jmp   :next
:halfway     inc   NFAIL            ; copied but not removed, which is safe
             jmp   :next

:next        lda   #$00
             jsr   SELPANEL
             jmp   :each

*--- both listings changed: one lost files and the other gained them
:done        lda   #$01
             jsr   SELPANEL
             jsr   RESCAN
             jsr   CLAMPSEL
             lda   #$00
             jsr   SELPANEL
             jsr   RESCAN
             jsr   CLAMPSEL

             lda   NFAIL
             beq   :nofail
             sta   MSGN
             lda   #<MMVFAIL
             ldy   #>MMVFAIL
             jmp   SAYMSG
:nofail      lda   NSKIP
             beq   :plain
             lda   NITEM
             sta   MSGN
             lda   #<MMVSOME
             ldy   #>MMVSOME
             jmp   SAYMSG
:plain       lda   NITEM
             sta   MSGN
             lda   #<MMOVED
             ldy   #>MMOVED
             jmp   SAYMSG

MMOVED       asc   "moved"
             dfb   $00
MMVSOME      asc   "moved; directories and locked files were not"
             dfb   $00
MMVFAIL      asc   "copied but could not be removed:"
             dfb   $00
